# frozen_string_literal: true

require "rspec/core"

require_relative "signal/version"
require_relative "signal/project"
require_relative "signal/backtrace/frame"
require_relative "signal/backtrace/parser"
require_relative "signal/backtrace/classifier"
require_relative "signal/backtrace/reducer"
require_relative "signal/redactor"
require_relative "signal/html_summary"
require_relative "signal/message"
require_relative "signal/fingerprint"
require_relative "signal/rerun"
require_relative "signal/symptom"
require_relative "signal/symptoms"
require_relative "signal/failure"
require_relative "signal/outside_example"
require_relative "signal/group"
require_relative "signal/grouper"
require_relative "signal/cluster"
require_relative "signal/clusterer"
require_relative "signal/code_paths"
require_relative "signal/comparison"
require_relative "signal/history"
require_relative "signal/report"
require_relative "signal/configuration"
require_relative "signal/reporters/related_failures"
require_relative "signal/reporters/outside_examples"
require_relative "signal/reporters/shared_code_paths"
require_relative "signal/reporters/markdown"
require_relative "signal/reporters/json_report"
require_relative "signal/reporters/full_output"
require_relative "signal/progress_bar"
require_relative "signal/writer"
require_relative "signal/parallel_run"
require_relative "signal/parallel_merger"
require_relative "signal/failure_builder"
require_relative "signal/formatter"
require_relative "signal/integrations/capybara"

module RSpec
  # Turns noisy RSpec failures into compact, high-signal diagnostic artifacts
  # designed to be handed to an AI coding agent.
  module Signal
    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield configuration if block_given?
        configuration.reset_memoized!
        configuration
      end

      # Registers the formatter and optional integrations.
      #
      # Called automatically when you `require "rspec/signal"` inside an
      # `RSpec.configure` block or from `spec_helper.rb`. Safe to call twice.
      #
      # @return [Boolean] whether anything was installed
      def install!(rspec_config = ::RSpec.configuration)
        return false if @installed

        @installed = true
        return false unless configuration.enabled?

        quiet_mode? # Capture CLI intent before RSpec finishes parsing ARGV.
        loader = rspec_config.formatter_loader
        unless loader.formatters.any?(Formatter)
          rspec_config.add_formatter(Formatter)
          @auto_installed = true
        end

        install_integrations!(rspec_config)
        true
      rescue StandardError => e
        warn "rspec-signal: could not install (#{e.class}: #{e.message})"
        false
      end

      def installed?
        !!@installed
      end

      # True when we added the formatter ourselves rather than the user asking
      # for it with `--format`. Only then do we put RSpec's default formatter
      # back, because only then did we displace it.
      def auto_installed?
        !!@auto_installed
      end

      # Explicit formatter selection happens after --require files are loaded,
      # so install! may initially look automatic. Detect the user's intent from
      # the original CLI arguments (or the wrapper's explicit marker) at start
      # time, after RSpec has finished configuring its formatter loader.
      def quiet_mode?
        return true if ENV["RSPEC_SIGNAL_QUIET"] == "1"
        return @quiet_mode_requested if defined?(@quiet_mode_requested)

        @quiet_mode_requested = !(formatter_arguments & ["RSpec::Signal::Formatter", "signal"]).empty?
      end

      # Adding any formatter suppresses RSpec's default one. When rspec-signal
      # installed itself the user did not ask for that, so restore normal
      # terminal feedback.
      def restore_default_formatter!(rspec_config = ::RSpec.configuration)
        loader = rspec_config.formatter_loader
        return if loader.formatters.any? { |formatter| primary_output_formatter?(formatter) }

        before = loader.formatters.dup
        loader.add(loader.default_formatter, rspec_config.output_stream)
        (loader.formatters - before).each do |formatter|
          formatter.start(::RSpec::Core::Notifications::StartNotification.new(0, 0)) if formatter.respond_to?(:start)
        end
      rescue StandardError
        nil
      end

      # Versions worth recording in the report header.
      def environment
        versions = { "ruby" => RUBY_VERSION, "rspec" => ::RSpec::Core::Version::STRING }
        versions["rails"] = ::Rails::VERSION::STRING if defined?(::Rails::VERSION::STRING)
        versions["capybara"] = ::Capybara::VERSION if defined?(::Capybara::VERSION)
        versions
      rescue StandardError
        { "ruby" => RUBY_VERSION }
      end

      # @api private Test support.
      def reset!
        @installed = false
        @auto_installed = false
        remove_instance_variable(:@quiet_mode_requested) if defined?(@quiet_mode_requested)
        @configuration = nil
      end

      private

      def formatter_arguments
        ARGV.each_with_index.filter_map do |argument, index|
          next ARGV[index + 1] if ["--format", "-f"].include?(argument)
          next ::Regexp.last_match(1) if argument =~ /\A--format=(.+)\z/

          argument[2..] if argument.start_with?("-f") && argument.length > 2
        end
      end

      def install_integrations!(rspec_config)
        return unless configuration.capture_capybara

        Integrations::Capybara.install!(rspec_config, configuration)
      end

      # Formatters that give the developer their normal terminal feedback.
      def primary_output_formatter?(formatter)
        return false if formatter.is_a?(Formatter)

        name = formatter.class.name.to_s
        !name.end_with?("DeprecationFormatter", "FallbackMessageFormatter", "ProfileFormatter")
      end
    end
  end
end

RSpec::Signal.install! if defined?(RSpec) && RSpec.respond_to?(:configuration)
