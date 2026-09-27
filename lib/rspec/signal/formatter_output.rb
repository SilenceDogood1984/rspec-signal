# frozen_string_literal: true

module RSpec
  module Signal
    # Terminal rendering kept separate from formatter notification handling.
    module FormatterOutput
      private

      # Stdout is a tool call's return value, so it should be the triage view:
      # enough to decide whether to open the report, whether the last edit
      # helped, and where to look first.
      def print_summary(result, current)
        return unless config.terminal_summary
        return print_comparison_only(current) if comparison_only?(result, current)

        return print_quiet_success(current) if quiet_success?(result)
        return unless current.reportable? || result.summary_path

        @output.puts
        print_rspec_summary(current) if RSpec::Signal.quiet_mode?
        @output.puts signal_line(current)
        current.relationship_lines.each { |line| @output.puts line }
        print_comparison(current)
        print_code_paths(current)
        @output.puts "Report: #{writer.relative(result.summary_path)}" if result.summary_path
      rescue StandardError => e
        record_error(e)
      end

      def comparison_only?(result, current)
        config.track_history && !history_eligible_run? && !current.reportable? && !result.summary_path
      end

      def print_comparison_only(current)
        @output.puts
        print_comparison(current)
      end

      def print_quiet_success(current)
        @output.puts
        print_rspec_summary(current)
        print_comparison(current)
      end

      def signal_line(current)
        "rspec-signal: #{quantity(current.failure_count, "failure")} in " \
          "#{quantity(current.group_count, "distinct signature")}" \
          "#{cluster_note(current)}#{outside_note(current)}#{omission_note(current)}"
      end

      def print_comparison(current)
        reason = comparison_skipped_reason
        if reason
          @output.puts "Since last run: comparison skipped (#{reason})"
          return
        end

        headline = current.comparison&.headline
        @output.puts "Since last run: #{headline}" if headline
      end

      def comparison_skipped_reason
        return unless config.track_history

        @run_status.skipped_reason(outside_errors: outside_example_count, targeted: targeted_run?)
      end

      def print_code_paths(current)
        top = current.code_paths.first(Formatter::MAX_TOP_CODE_PATHS)
        return if top.empty?

        rendered = top.map { |path| "#{path.location} (#{quantity(path.signature_count, "signature")})" }
        @output.puts "Shared code paths: #{rendered.join(", ")}"
      end

      def print_rspec_summary(current)
        @output.puts "#{current.example_count} examples, #{current.failure_count} failures, " \
                     "#{current.pending_count} pending"
        @output.puts
      end

      def quiet_success?(result)
        RSpec::Signal.quiet_mode? && result.summary_path.nil?
      end

      def quantity(count, word)
        "#{count} #{count == 1 ? word : "#{word}s"}"
      end

      def cluster_note(current)
        return "" unless current.cluster_count.positive?

        ", #{quantity(current.cluster_count, "related cluster")}"
      end

      def outside_note(current)
        return "" unless current.errors_outside_examples.positive?

        ", #{quantity(current.errors_outside_examples, "error")} outside examples"
      end

      def omission_note(current)
        return "" unless current.omitted_frames.positive?

        " (#{current.omitted_frames} backtrace frames omitted)"
      end
    end
  end
end
