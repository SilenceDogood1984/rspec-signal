# frozen_string_literal: true

require "rspec/core"
require "rspec/core/formatters"
require "securerandom"

module RSpec
  module Signal
    # The RSpec formatter. Collects failures as they happen, then writes the
    # artifacts once the run is over.
    #
    # When selected explicitly it is the only formatter, suppressing RSpec's
    # verbose failure renderer. When auto-installed it restores the default
    # formatter so requiring the gem does not change normal human output.
    class Formatter
      include FormatterOutput

      ::RSpec::Core::Formatters.register self, :start, :example_passed, :example_failed,
                                         :example_pending, :message, :dump_summary, :seed, :close

      MAX_TOP_CODE_PATHS = 2

      attr_reader :output

      def initialize(output)
        @output = output
        @failures = []
        @outside = []
        @errors = []
        @summary = {}
        @run_status = RunStatus.new
        @seed = nil
        @seed_used = false
        @run_id = "#{Time.now.utc.strftime("%Y%m%dT%H%M%S")}-#{SecureRandom.hex(4)}"
      end

      def config
        RSpec::Signal.configuration
      end

      def start(notification)
        # Adding a formatter suppresses RSpec's default one. When rspec-signal
        # installed itself, the user never asked for that, so put it back.
        RSpec::Signal.restore_default_formatter! if RSpec::Signal.auto_installed? && !RSpec::Signal.quiet_mode?
        writer.invalidate_current! if config.enabled? && !dry_run? && !ParallelRun.worker?
        @run_status.selected(notification.count)
        start_progress(notification.count)
      end

      def example_passed(notification)
        count_example(notification, failed: false)
        @run_status.example_executed
        advance_progress
      end

      def example_pending(_notification)
        @run_status.example_executed
        advance_progress
      end

      def example_failed(notification)
        return unless config.enabled?

        count_example(notification, failed: true)
        @failures << builder.call(notification, position: @failures.size + 1)
      rescue StandardError => e
        record_error(e)
      ensure
        @run_status.example_executed
        advance_progress
      end

      # RSpec reports a spec file that would not load, or a `before(:suite)`
      # hook that blew up, on this stream rather than as a failed example.
      # Registering for it is what lets those reach the report at all -- but it
      # also suppresses RSpec's `FallbackMessageFormatter`, so anything we
      # receive and nobody else prints has to be printed here.
      def message(notification)
        text = notification.message.to_s
        capture_outside_example(text) if config.enabled?
        echo_message(text)
      rescue StandardError => e
        record_error(e)
      end

      def dump_summary(notification)
        @summary = {
          example_count: notification.example_count,
          failure_count: notification.failure_count,
          pending_count: notification.pending_count,
          duration: notification.duration,
          errors_outside_examples: notification.errors_outside_of_examples_count
        }
        @run_status.summarized(notification.example_count)
      rescue StandardError => e
        record_error(e)
      end

      def seed(notification)
        @seed = notification.seed
        @seed_used = notification.seed_used?
      rescue StandardError => e
        record_error(e)
      end

      def close(_notification)
        return unless config.enabled?

        finish_progress
        return if dry_run?

        if ParallelRun.worker?
          ParallelRun.write_worker(report, config)
        else
          current = report
          compare_and_record(current)
          print_summary(writer.write(current), current)
        end
      rescue StandardError => e
        record_error(e)
      ensure
        warn_about_errors
      end

      def report
        Report.new(
          failures: @failures,
          example_count: @summary.fetch(:example_count, 0),
          failure_count: @summary.fetch(:failure_count, @failures.size),
          pending_count: @summary.fetch(:pending_count, 0),
          duration: @summary[:duration],
          seed: @seed,
          seed_used: @seed_used,
          environment: RSpec::Signal.environment,
          errors_outside_examples: outside_example_count,
          outside_example_failures: @outside,
          relate_failures: config.relate_failures,
          code_path_depth: config.code_path_depth,
          run_id: @run_id,
          census: @census,
          causal_analysis: config.causal_analysis
        )
      end

      private

      # Only when relationships are switched on: disabled, nothing is counted
      # and no census exists. Decided per example, because the formatter is
      # built when the gem is required -- before the project's configure block.
      def count_example(notification, failed:)
        (@census ||= Causal::Census.new).record(notification, failed: failed) if config.causal_analysis
      end

      # RSpec's own count is authoritative when it is at least as large as
      # ours; ours fills in when a run aborts before `dump_summary`.
      def outside_example_count
        [@summary.fetch(:errors_outside_examples, 0), @outside.size].max
      end

      def capture_outside_example(text)
        return unless OutsideExample.failure?(text)

        failure = OutsideExample.build(text, config, position: @outside.size + 1)
        @outside << failure if failure
      end

      # Only when no other formatter would print it. Registering `:message`
      # takes RSpec's fallback formatter out of the picture, and silently
      # swallowing a load error is far worse than any output we add.
      def echo_message(text)
        return unless echo_messages?

        @output.puts(text)
      end

      def echo_messages?
        return @echo_messages if defined?(@echo_messages)

        listeners = ::RSpec.configuration.reporter.registered_listeners(:message)
        @echo_messages = listeners.none? { |listener| !listener.equal?(self) }
      rescue StandardError
        @echo_messages = RSpec::Signal.quiet_mode?
      end

      # A dry run executes nothing, so it has neither failures to report nor
      # the standing to delete the report of the run that did.
      def dry_run?
        ::RSpec.configuration.dry_run?
      rescue StandardError
        false
      end

      def compare_and_record(current)
        return unless config.track_history
        return unless history_eligible_run?

        history = History.new(config)
        current.comparison = history.compare(current, run_id: current.run_id)
        history.record(current, run_id: current.run_id)
      rescue StandardError => e
        record_error(e)
      end

      def history_eligible_run?
        @run_status.history_eligible?(outside_errors: outside_example_count, targeted: targeted_run?)
      end

      def targeted_run?
        rules = ::RSpec.configuration.inclusion_filter.rules
        rule_names = rules.keys.map(&:to_s)
        (rule_names & %w[ids locations full_description]).any?
      rescue StandardError
        false
      end

      def start_progress(total)
        return unless config.enabled? && RSpec::Signal.quiet_mode?
        return if ParallelRun.worker?

        @progress = ProgressBar.for(@output, total)
      end

      def advance_progress
        @progress&.advance
      end

      def finish_progress
        @progress&.finish
        @progress = nil
      end

      def builder
        @builder ||= FailureBuilder.new(config)
      end

      def writer
        @writer ||= Writer.new(config)
      end

      def record_error(error)
        @errors << error
      end

      def warn_about_errors
        return if @errors.empty?

        first = @errors.first
        @output.puts "rspec-signal: #{@errors.size} internal " \
                     "#{@errors.size == 1 ? "error" : "errors"} while building the report " \
                     "(#{first.class}: #{first.message})"
        @output.puts first.backtrace.first(5).map { |line| "  #{line}" }.join("\n") if ENV["RSPEC_SIGNAL_DEBUG"]
      rescue StandardError
        nil
      end
    end
  end
end
