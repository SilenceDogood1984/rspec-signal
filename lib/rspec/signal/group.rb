# frozen_string_literal: true

module RSpec
  module Signal
    # A set of failures that share a fingerprint.
    class Group
      attr_reader :fingerprint, :failures, :first_seen

      def initialize(fingerprint:, first_seen:)
        @fingerprint = fingerprint
        @first_seen = first_seen
        @failures = []
      end

      def <<(failure)
        @failures << failure
        self
      end

      def size
        @failures.size
      end

      # The failure shown in full. We pick the one carrying the most first-party
      # frames, because that is the one whose trace is most useful; ties break on
      # run order so the choice is stable across runs.
      def representative
        @representative ||= @failures.each_with_index.max_by do |failure, index|
          [failure.reduced.project_frames.size, failure.reduced.kept_count, -index]
        end.first
      end

      def exception_class
        representative.exception_class
      end

      def message
        representative.message
      end

      # Locations of every example in the group, in run order, deduplicated.
      def affected_locations
        @affected_locations ||= @failures.map(&:spec_location).uniq
      end

      def others
        @failures.reject { |failure| failure.equal?(representative) }
      end

      # Total backtrace frames this group's failures dropped.
      def omitted_frames
        @failures.sum { |failure| failure.reduced.omitted_count }
      end

      def to_h
        {
          signature: fingerprint.digest,
          count: size,
          exception: exception_class,
          culprit: fingerprint.culprit,
          app_context: fingerprint.app_context,
          representative: representative.to_h,
          affected: @failures.map { |failure| { location: failure.spec_location, description: failure.description } }
        }.compact
      end
    end
  end
end
