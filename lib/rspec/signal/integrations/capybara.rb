# frozen_string_literal: true

require "fileutils"

module RSpec
  module Signal
    module Integrations
      # Captures browser state for failing system/feature examples.
      #
      # A failing system spec whose report says only "Unable to find css" is
      # much less useful than one that also says which URL the browser was on
      # and what the JavaScript console said. Everything here is best effort:
      # any problem simply means the report has less detail.
      module Capybara
        RELEVANT_TYPES = %i[system feature].freeze
        MAX_CONSOLE_LINES = 20

        module_function

        def install!(rspec_config, signal_config)
          # `prepend_after` so this runs *before* any example-group-level
          # `after(:each)` hook -- rspec-rails tears the Capybara session down
          # at that level, and capturing after teardown would find nothing.
          rspec_config.prepend_after(:each) do |example|
            RSpec::Signal::Integrations::Capybara.capture(example, signal_config)
          end
        end

        def capture(example, signal_config)
          return unless example.exception
          return unless relevant?(example)

          session = existing_session
          return unless session

          diagnostics = collect(session, signal_config)
          return if diagnostics.empty?

          example.metadata[:rspec_signal_diagnostics] =
            (example.metadata[:rspec_signal_diagnostics] || {}).merge(diagnostics)
        rescue StandardError, ::LoadError
          nil
        end

        def relevant?(example)
          metadata = example.metadata
          RELEVANT_TYPES.include?(metadata[:type]) || metadata[:js] == true
        end

        # Deliberately avoids `Capybara.current_session`, which would *create* a
        # session (and possibly boot a browser) if none exists.
        def existing_session
          return nil unless defined?(::Capybara)

          pool = ::Capybara.instance_variable_get(:@session_pool)
          return nil if pool.nil? || pool.empty?

          ::Capybara.current_session
        rescue StandardError
          nil
        end

        def collect(session, signal_config)
          diagnostics = {}
          diagnostics[:url] = try { session.current_url }
          diagnostics[:path] = try { session.current_path }
          diagnostics[:title] = try { session.title }
          diagnostics[:status_code] = try { session.status_code }
          diagnostics[:driver] = try { ::Capybara.current_driver }
          diagnostics[:console] = console_messages(session)
          diagnostics[:saved_page] = write_page_html(session, signal_config) if signal_config.capture_page_html
          diagnostics.reject { |_, value| value.nil? || value.to_s.strip.empty? }
        end

        # Browser console output is small and often contains the actual cause of
        # a JavaScript-driven failure.
        def console_messages(session)
          logs = try { session.driver.browser.logs.get(:browser) }
          return nil if logs.nil? || logs.empty?

          logs.last(MAX_CONSOLE_LINES).map { |entry| try { "#{entry.level}: #{entry.message}" } }.compact
        end

        def write_page_html(session, signal_config)
          dir = File.join(signal_config.output_path, "pages")
          FileUtils.mkdir_p(dir)
          path = File.join(dir, "#{Time.now.to_i}-#{rand(1_000_000)}.html")
          File.write(path, session.html)
          signal_config.project.display_path(path)
        rescue StandardError
          nil
        end

        def try
          yield
        rescue StandardError, ::NotImplementedError
          nil
        end
      end
    end
  end
end
