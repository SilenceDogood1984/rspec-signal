# frozen_string_literal: true

require "rspec/core"
require "rspec/core/formatters"

module RSpec
  module Signal
    # The RSpec formatter. Collects failures as they happen, then writes the
    # artifacts once the run is over.
    #
    # When selected explicitly it is the only formatter, suppressing RSpec's
    # verbose failure renderer. When auto-installed it restores the default
    # formatter so requiring the gem does not change normal human output.
    class Formatter
      ::RSpec::Core::Formatters.register self, :start, :example_failed, :dump_summary, :seed, :close

      attr_reader :output

      def initialize(output)
        @output = output
        @failures = []
        @errors = []
        @summary = {}
        @seed = nil
        @seed_used = false
      end

      def config = RSpec::Signal.configuration

      def start(_notification)
        # Adding a formatter suppresses RSpec's default one. When rspec-signal
        # installed itself, the user never asked for that, so put it back.
        RSpec::Signal.restore_default_formatter! if RSpec::Signal.auto_installed? && !RSpec::Signal.quiet_mode?
      end

      def example_failed(notification)
        return unless config.enabled?

        @failures << builder.call(notification, position: @failures.size + 1)
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

        result = writer.write(report)
        print_summary(result)
      rescue StandardError => e
        record_error(e)
      ensure
        warn_about_errors
      end

      # @return [Report] exposed for testing and for tools that embed the gem.
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
          errors_outside_examples: @summary.fetch(:errors_outside_examples, 0),
          relate_failures: config.relate_failures
        )
      end

      private

      def builder = @builder ||= FailureBuilder.new(config)
      def writer  = @writer ||= Writer.new(config)

      def print_summary(result)
        return unless config.terminal_summary
        return if @failures.empty? && result.summary_path.nil?

        current = report
        @output.puts
        print_rspec_summary(current) if RSpec::Signal.quiet_mode?
        @output.puts "rspec-signal: #{current.failure_count} " \
                     "#{current.failure_count == 1 ? "failure" : "failures"} in " \
                     "#{current.group_count} distinct " \
                     "#{current.group_count == 1 ? "signature" : "signatures"}" \
                     "#{cluster_note(current)}#{omission_note(current)}"
        @output.puts "Report: #{writer.relative(result.summary_path)}" if result.summary_path
      rescue StandardError => e
        record_error(e)
      end

      def print_rspec_summary(current)
        @output.puts "#{current.example_count} examples, #{current.failure_count} failures, " \
                     "#{current.pending_count} pending"
        @output.puts
      end

      def cluster_note(current)
        return "" unless current.cluster_count.positive?

        ", #{current.cluster_count} related #{current.cluster_count == 1 ? "cluster" : "clusters"}"
      end

      def omission_note(current)
        return "" unless current.omitted_frames.positive?

        " (#{current.omitted_frames} backtrace frames omitted)"
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
