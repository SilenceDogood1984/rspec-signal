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

      # Arguments that rerun exactly this group's examples, in run order.
      def rerun_arguments
        @rerun_arguments ||= @failures.map(&:rerun_argument).uniq
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

      def to_h(max_message_lines: 30, max_diff_lines: 20)
        {
          signature: fingerprint.digest,
          loose_signature: fingerprint.loose_digest,
          count: size,
          exception: exception_class,
          summary: message.summary,
          culprit: fingerprint.culprit,
          app_context: fingerprint.app_context,
          rerun: Rerun.command([representative.rerun_argument]),
          rerun_ids: rerun_arguments,
          representative: representative.to_h(max_message_lines: max_message_lines,
                                              max_diff_lines: max_diff_lines),
          affected: @failures.map { |failure| affected_h(failure) }
        }.compact
      end

      private

      def affected_h(failure)
        { location: failure.spec_location, id: failure.example_id,
          description: failure.description }.compact
      end
    end
  end
end
