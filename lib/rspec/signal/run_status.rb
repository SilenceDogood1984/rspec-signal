# frozen_string_literal: true

module RSpec
  module Signal
    # Answers two deliberately separate questions about an RSpec invocation:
    # whether execution finished, and whether it represents a comparable run.
    class RunStatus
      def initialize
        @selected_count = nil
        @executed_count = 0
        @summary_example_count = nil
      end

      def selected(count)
        @selected_count = count
      end

      def example_executed
        @executed_count += 1
      end

      def summarized(example_count)
        @summary_example_count = example_count
      end

      def complete?(outside_errors:)
        !@summary_example_count.nil? && !@selected_count.nil? && outside_errors.zero? &&
          @executed_count == @selected_count && @summary_example_count == @executed_count
      end

      def history_eligible?(outside_errors:)
        complete?(outside_errors: outside_errors)
      end

      def skipped_reason(outside_errors:)
        "run incomplete" unless history_eligible?(outside_errors: outside_errors)
      end
    end
  end
end
