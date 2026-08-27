# frozen_string_literal: true

require_relative "frame"

module RSpec
  module Signal
    module Backtrace
      # A gap standing in for frames that were dropped.
      Gap = Struct.new(:count, :kind, keyword_init: true) do # rubocop:disable Lint/StructNewOverride
        def frame?
          false
        end

        def to_s
          noun = kind == :framework ? "framework/runtime" : "library"
          "[#{count} #{noun} frame#{"s" unless count == 1} omitted]"
        end

        def to_h
          { omitted: count, kind: kind.to_s }
        end
      end

      # Frames and gaps are rendered side by side, so both answer `frame?`.
      class Frame
        def frame?
          true
        end
      end

      # The result of reducing one backtrace.
      class Reduced
        attr_reader :entries, :total, :omitted, :fallback

        def initialize(entries:, total:, omitted:, fallback: false)
          @entries  = entries
          @total    = total
          @omitted  = omitted
          @fallback = fallback
        end

        def frames
          entries.select(&:frame?)
        end

        def project_frames
          frames.select(&:project?)
        end

        def kept_count
          frames.size
        end

        def fallback?
          @fallback
        end

        def empty?
          frames.empty?
        end

        def omitted_count
          omitted.values.sum
        end

        # The frame that best identifies where this blew up: the innermost frame
        # that is not test-runner plumbing.
        def culprit
          frames.first
        end

        # The innermost first-party frame — what the agent should open first.
        def primary_location
          project_frames.first
        end

        def to_a
          entries.map(&:to_s)
        end
      end

      # Reduces a full backtrace to the frames that carry diagnostic value.
      #
      # Rules, in order:
      #
      #   1. Consecutive repeats of the same file:line collapse into one.
      #   2. Framework frames (test runner, loader, CLI) are always dropped.
      #   3. Every first-party frame is kept.
      #   4. A run of library frames that directly touches first-party code is
      #      partially kept: the library entry point the project called, the site
      #      that raised, and (budget permitting) their immediate neighbours.
      #      This is the "what operation failed" context.
      #   5. Library frames that touch no first-party code at all are dropped.
      #   6. If nothing survives, progressively fall back so that the report is
      #      never empty: innermost non-framework frames, then innermost frames.
      class Reducer
        # Relative value of each kind of frame. Anything scoring 0 is dropped.
        SCORE_PROJECT          = 100
        SCORE_LIBRARY_ENTRY    = 70  # last library frame before first-party code
        SCORE_RAISE_SITE       = 65  # innermost frame of an adjacent library run
        SCORE_LIBRARY_NEAR     = 40  # neighbours of the two above
        SCORE_LIBRARY_CALLER   = 60  # library frame that called into first-party code

        # Labels that name no method: delegation shims and block frames.
        ANONYMOUS_LABEL = /\A(?:block\s|<(?:top|module|class|main)\b|rescue in\b|ensure in\b)/.freeze

        def initialize(max_frames: 12, max_external_context: 3, max_project_frames: 8, fallback_frames: 6)
          @max_frames = max_frames
          @max_external_context = max_external_context
          @max_project_frames = max_project_frames
          @fallback_frames = fallback_frames
        end

        # @param frames [Array<Frame>] innermost first, as Ruby emits them
        # @return [Reduced]
        def call(frames)
          frames = collapse_repeats(Array(frames))
          return Reduced.new(entries: [], total: 0, omitted: {}) if frames.empty?

          scored = score(frames)
          keep = select_keepers(scored)
          return fallback(frames) if keep.empty?

          build(frames, keep)
        end

        private

        # Only *identical* frames collapse. A one-line method definition puts
        # several different methods on the same file:line, and those are not
        # repeats -- they are the call chain.
        def collapse_repeats(frames)
          frames.chunk_while { |a, b| a.path == b.path && a.line == b.line && a.label == b.label }.map do |chunk|
            next chunk.first if chunk.size == 1

            frame = chunk.first.dup
            frame.label = "#{frame.label} (x#{chunk.size})"
            frame
          end
        end

        # @return [Hash<Integer, Integer>] frame index => score
        #
        # Adjacency is computed over the backtrace with framework frames removed,
        # so a stray runner frame wedged between a library and the spec file does
        # not hide the library context.
        def score(frames)
          scores = Hash.new(0)
          significant = frames.each_index.reject { |i| frames[i].framework? }
          project_indexes = significant.select { |i| frames[i].project? }

          return scores if project_indexes.empty?

          project_indexes.first(@max_project_frames).each { |i| scores[i] = SCORE_PROJECT }
          scores[project_indexes.first] = SCORE_PROJECT + 5

          positions = significant.each_with_index.to_h
          external_runs(frames, significant).each do |run|
            score_run(frames, run, scores, significant, positions)
          end

          scores
        end

        # Contiguous runs of :external frames within the significant subsequence,
        # as arrays of original frame indexes.
        def external_runs(frames, significant)
          significant.chunk { |i| frames[i].external? }.filter_map { |external, run| run if external }
        end

        def score_run(frames, run, scores, significant, positions)
          above, below = adjacency(frames, run, significant, positions)
          return unless above || below

          candidates(frames, run, above).each_with_index do |index, rank|
            scores[index] = [scores[index], run_score(index, run, above, below, rank)].max
          end
        end

        # Whether the run was called *by* first-party code (above) and/or calls
        # *into* first-party code (below).
        def adjacency(frames, run, significant, positions)
          first_position = positions.fetch(run.first)
          before = significant[first_position - 1] if first_position.positive?
          after  = significant[positions.fetch(run.last) + 1]

          [after && frames[after].project?, before && frames[before].project?]
        end

        # The frames of this run worth keeping, best first.
        def candidates(frames, run, above)
          ranked = []
          ranked << entry_point(frames, run) if above # library entry point
          ranked << run.first                         # raise site, or caller of project code
          ranked << run.last if above
          ranked << run[1] if run.size > 1
          ranked.compact.uniq.first(@max_external_context)
        end

        def run_score(index, run, above, below, rank)
          return SCORE_LIBRARY_CALLER if below && index == run.first
          return SCORE_RAISE_SITE if index == run.first
          return SCORE_LIBRARY_ENTRY if above && rank.zero?

          SCORE_LIBRARY_NEAR - rank
        end

        # The frame where project code entered the library. Scanning outwards in
        # for the first *named* method skips delegation shims, whose labels are
        # anonymous blocks and which say nothing about the failing operation:
        # `capybara/dsl.rb:52 in block (2 levels) in <module:DSL>` is noise,
        # `capybara/node/finders.rb:60 in find` is the answer.
        def entry_point(frames, run)
          run.reverse.find { |index| named_label?(frames[index].label) } || run.last
        end

        def named_label?(label)
          text = label.to_s.strip
          !text.empty? && !ANONYMOUS_LABEL.match?(text)
        end

        def select_keepers(scores)
          positive = scores.select { |_, value| value.positive? }
          positive.sort_by { |index, value| [-value, index] }.first(@max_frames).map(&:first).sort
        end

        def build(frames, keep)
          entries = []
          omitted = Hash.new(0)
          pending = Hash.new(0)

          frames.each_index do |i|
            if keep.include?(i)
              entries.concat(flush(pending))
              entries << frames[i]
            else
              bucket = frames[i].framework? ? :framework : :external
              pending[bucket] += 1
              omitted[bucket] += 1
            end
          end
          entries.concat(flush(pending))
          # A gap before the first kept frame is always runner plumbing sitting
          # above the real failure. The header already reports the totals.
          entries.shift while entries.first.is_a?(Gap) && entries.first.kind == :framework

          Reduced.new(entries: entries, total: frames.size, omitted: omitted)
        end

        # Gaps are emitted framework-last so the trailing note reads naturally.
        def flush(pending)
          %i[external framework].filter_map do |kind|
            next if pending[kind].zero?

            count = pending[kind]
            pending[kind] = 0
            Gap.new(count: count, kind: kind)
          end
        end

        # Never return an empty trace: something is always better than nothing.
        def fallback(frames)
          keep = frames.each_index.reject { |i| frames[i].framework? }.first(@fallback_frames)
          keep = frames.each_index.first(@fallback_frames) if keep.empty?

          reduced = build(frames, keep)
          Reduced.new(entries: reduced.entries, total: reduced.total, omitted: reduced.omitted, fallback: true)
        end
      end
    end
  end
end
