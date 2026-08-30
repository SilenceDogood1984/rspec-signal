# frozen_string_literal: true

module RSpec
  module Signal
    # The complete, renderer-independent result of a run.
    class Report
      # Bumped when the shape of {#to_h} changes incompatibly. Schema 2 adds
      # `run_id`, `code_paths`, `since_last_run`, and per-signature `rerun`,
      # `summary` and `loose_signature`; every schema 1 field kept its name and
      # meaning.
      SCHEMA = 2

      # The worker interchange payload is a different document with a different
      # audience (the parent merger, of the same gem version), so it carries its
      # own number rather than sharing the public one.
      WORKER_SCHEMA = 3

      attr_reader :failures, :groups, :clusters, :code_paths, :example_count, :failure_count,
                  :pending_count, :duration, :seed, :seed_used, :environment,
                  :errors_outside_examples, :outside_example_failures, :run_id
      attr_accessor :comparison

      def initialize(failures:, example_count: 0, failure_count: nil, pending_count: 0,
                     duration: nil, seed: nil, seed_used: false, environment: {},
                     errors_outside_examples: 0, relate_failures: true, outside_example_failures: [],
                     run_id: nil, code_path_depth: CodePaths::DEFAULT_DEPTH)
        @failures = failures
        @groups = Grouper.call(failures)
        @clusters = relate_failures ? safely { Clusterer.call(failures) } : []
        @code_paths = safely { CodePaths.call(failures, depth: code_path_depth) }
        @example_count = example_count
        @failure_count = failure_count || failures.size
        @pending_count = pending_count
        @duration = duration
        @seed = seed
        @seed_used = seed_used
        @environment = environment
        @errors_outside_examples = errors_outside_examples
        @outside_example_failures = outside_example_failures
        @run_id = run_id
      end

      # The analysis layers are the newest and least essential stages; a report
      # without them is still worth having, so they are never allowed to take
      # the run down.
      def safely
        yield
      rescue StandardError
        []
      end

      def group_count
        groups.size
      end

      def cluster_count
        clusters.size
      end

      def code_path_count
        code_paths.size
      end

      def any_failures?
        !failures.empty?
      end

      # Whether there is anything at all to report. An error outside every
      # example produces no failed example but is emphatically not a green run.
      def reportable?
        any_failures? || errors_outside_examples.positive?
      end

      def seed_used?
        !!@seed_used
      end

      # Backtrace frames dropped across the whole run. This is the number that
      # makes the reduction visible.
      def omitted_frames
        @omitted_frames ||= failures.sum { |failure| failure.reduced.omitted_count }
      end

      def total_frames
        @total_frames ||= failures.sum { |failure| failure.reduced.total }
      end

      def kept_frames
        total_frames - omitted_frames
      end

      def to_h(config = nil)
        budgets = message_budgets(config)
        {
          schema: SCHEMA,
          generated_by: "rspec-signal #{VERSION}",
          run_id: run_id,
          summary: summary_h,
          since_last_run: comparison&.to_h,
          environment: environment,
          backtrace_reduction: { total_frames: total_frames, kept_frames: kept_frames, omitted_frames: omitted_frames },
          signatures: groups.map { |group| group.to_h(**budgets) },
          related: clusters.map(&:to_h),
          code_paths: code_paths.map(&:to_h),
          outside_examples: outside_example_failures.map { |failure| failure.to_h(**budgets) }
        }.compact
      end

      # Worker interchange data. Unlike the public report summary this retains
      # every reduced failure so grouping can be repeated across all workers.
      #
      # `raw` -- the unreduced formatter output -- is included only when
      # `write_full` is on, since it is otherwise discarded on merge and would
      # just bloat every worker payload for no reason.
      def worker_h(write_full: false, config: nil)
        budgets = message_budgets(config)
        serialized = failures.map do |failure|
          attributes = failure.to_h(**budgets).merge(fingerprint: failure.fingerprint.to_h)
          attributes[:raw] = failure.raw if write_full
          attributes
        end
        to_h(config).merge(schema: WORKER_SCHEMA, failures: serialized)
      end

      private

      def summary_h
        {
          examples: example_count,
          failures: failure_count,
          pending: pending_count,
          signatures: group_count,
          related_clusters: cluster_count.positive? ? cluster_count : nil,
          shared_code_paths: code_path_count.positive? ? code_path_count : nil,
          duration_seconds: duration&.round(3),
          seed: seed_used? ? seed : nil,
          errors_outside_examples: errors_outside_examples.positive? ? errors_outside_examples : nil
        }.compact
      end

      def message_budgets(config)
        return { max_message_lines: 30, max_diff_lines: 20 } unless config

        { max_message_lines: config.max_message_lines, max_diff_lines: config.max_diff_lines }
      end
    end
  end
end
