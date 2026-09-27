# frozen_string_literal: true

module RSpec
  module Signal
    # Builds the deliberately small, action-first terminal view. Detailed
    # evidence remains in the Markdown, JSON, and raw artifacts.
    class TerminalSummary
      MAX_PROBLEMS = 3
      MAX_CODE_PATHS = 2

      def initialize(report, report_path: nil, quiet: false, workers: nil)
        @report = report
        @report_path = report_path
        @quiet = quiet
        @workers = workers
      end

      def lines
        return success_lines unless report.reportable?

        rendered = []
        rendered << totals_line if quiet || workers
        rendered.concat(problem_heading)
        rendered.concat(render_problems? ? top_problems : exact_rerun)
        rendered.concat(outside_errors)
        rendered.concat(diagnostics)
        rendered << "Since last run: #{report.comparison.headline}" if report.comparison&.headline
        rendered << "Report: #{report_path}" if report_path
        rendered.compact
      end

      private

      attr_reader :report, :report_path, :quiet, :workers

      def success_lines
        return [] unless quiet || workers

        lines = [totals_line]
        lines << "Since last run: #{report.comparison.headline}" if report.comparison&.headline
        lines
      end

      def totals_line
        line = "RSpec totals: #{quantity(report.example_count, "example")}, " \
               "#{quantity(report.failure_count, "failure")}, #{quantity(report.pending_count, "pending", "pending")}"
        workers ? "#{line} across #{workers} workers" : line
      end

      # Native RSpec has already rendered an ordinary one-off failure. In that
      # mode Signal adds only the exact action and artifact pointer.
      def render_problems?
        quiet || workers || report.failure_count > report.group_count || report.group_count > 1
      end

      def problem_heading
        return [] if report.failure_count == 1 && report.group_count == 1
        return [] unless report.failure_count.positive?

        ["Signal problems: #{quantity(report.failure_count, "failure")}, " \
         "#{quantity(report.group_count, "distinct problem")}"]
      end

      def exact_rerun
        group = report.groups.first
        group ? ["Exact rerun: #{Rerun.command([group.representative.rerun_argument])}"] : []
      end

      def top_problems
        report.groups.first(MAX_PROBLEMS).each_with_index.flat_map do |group, index|
          label = report.group_count > 1 ? "Problem ##{index + 1}" : "Top problem"
          count = group.size > 1 ? " (#{quantity(group.size, "failure")})" : ""
          ["#{label}#{count}: #{group.exception_class}: #{group.message.summary}",
           "Exact rerun: #{Rerun.command([group.representative.rerun_argument])}"]
        end
      end

      def outside_errors
        return [] unless report.errors_outside_examples.positive?

        failure = report.outside_example_failures.first
        return exact_outside_rerun(failure) unless quiet || workers

        lines = ["Outside examples: #{quantity(report.errors_outside_examples, "error")}"]
        lines << "Load problem: #{failure.exception_class}: #{failure.message.summary}" if workers && failure
        lines.concat(exact_outside_rerun(failure))
        lines
      end

      def exact_outside_rerun(failure)
        failure ? ["Exact rerun: #{Rerun.command([failure.rerun_argument])}"] : []
      end

      # Existing relationship analysis is supporting context, never the
      # headline. Keep it after exact actions and bounded like the problems.
      def diagnostics
        lines = report.relationship_lines
        paths = report.code_paths.first(MAX_CODE_PATHS)
        return lines if paths.empty?

        rendered = paths.map { |path| "#{path.location} (#{quantity(path.signature_count, "signature")})" }
        lines + ["Shared code paths: #{rendered.join(", ")}"]
      end

      def quantity(count, singular, plural = "#{singular}s")
        "#{count} #{count == 1 ? singular : plural}"
      end
    end
  end
end
