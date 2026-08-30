# frozen_string_literal: true

module RSpec
  module Signal
    # One line of first-party code that several distinct signatures run through.
    class CodePath
      attr_reader :location, :first_seen, :failures

      def initialize(location:, first_seen:)
        @location = location
        @first_seen = first_seen
        @failures = []
        # Insertion-ordered set. A location crossed by hundreds of failures
        # would otherwise rescan the whole list on every one of them.
        @seen = {}
      end

      def add(failure)
        @failures << failure
        @seen[failure.fingerprint.digest] = true
        self
      end

      # The distinct signatures crossing this line, in the order first seen.
      def signatures
        @seen.keys
      end

      def size
        @failures.size
      end

      def signature_count
        @seen.size
      end

      def file
        @file ||= location.sub(/:\d+\z/, "")
      end

      # The method names the frame was seen under, most common first. Useful
      # when one file:line is reached through several call paths.
      def labels
        @labels ||= @failures.flat_map { |failure| failure.application_frames.select { |f| f.location == location } }
                             .map(&:label).compact.reject(&:empty?).uniq
      end

      def to_h
        { location: location, signatures: signatures, signature_count: signature_count,
          examples: size, labels: labels.first(3) }
      end
    end

    # Finds the first-party lines that more than one signature passes through.
    #
    # Every other clustering signal in this gem reads the failure *message*.
    # This one reads the *stack*, which is the only thing that can relate a
    # `KeyError` to the `expect { }.not_to raise_error` that swallowed it. Both
    # traces run through `app/pricing.rb:4`; nothing about their messages says
    # so.
    #
    # It claims nothing about causation. It reports a measured fact -- these N
    # signatures execute this line -- and the report says it in those words.
    #
    # Two rules keep it honest, and they are the ones the symptom clusterer
    # already uses:
    #
    #   * only first-party frames outside the spec suite are indexed, and only
    #     the innermost few, because the outer end of a stack is shared
    #     plumbing (`application_controller.rb`) while the inner end is the bug;
    #   * a location is reported only when two or more *distinct signatures*
    #     cross it. One signature crossing it is already reported as that
    #     signature's app context, and repeating it would be noise.
    module CodePaths
      MIN_SIGNATURES = 2

      # How far in from the raise site to look. Deep enough to pass through a
      # couple of application layers, shallow enough to stay off the framework
      # boundary.
      DEFAULT_DEPTH = 5

      module_function

      # @param failures [Array<Failure>]
      # @return [Array<CodePath>] most signatures spanned first; deterministic
      def call(failures, depth: DEFAULT_DEPTH, min_signatures: MIN_SIGNATURES)
        paths = {}

        failures.each_with_index do |failure, index|
          failure.application_frames(depth).map(&:location).uniq.each do |location|
            paths[location] ||= CodePath.new(location: location, first_seen: index)
            paths[location].add(failure)
          end
        end

        paths.values.select { |path| path.signature_count >= min_signatures }
             .sort_by { |path| [-path.signature_count, -path.size, path.first_seen] }
      end
    end
  end
end
