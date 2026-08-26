# frozen_string_literal: true

module RSpec
  module Signal
    # Turns an RSpec `FailedExampleNotification` into a plain {Failure}.
    #
    # This is the only place that touches RSpec's notification API, which keeps
    # the reduction, grouping and rendering stages testable without booting a
    # suite.
    class FailureBuilder
      SCREENSHOT = /\[Screenshot(?:\s+Image)?\]:\s*(\S+)/i
      MAX_CAUSE_DEPTH = 3
      MAX_CAUSE_MESSAGE_LINES = 5
      MAX_CAUSE_SCAN = 40

      def initialize(config)
        @config = config
      end

      # @param notification [RSpec::Core::Notifications::FailedExampleNotification]
      # @param position [Integer] 1-based failure number, used for the raw dump
      # @return [Failure]
      def call(notification, position: nil)
        example = notification.example
        exception = notification.exception
        extra = Array(example.metadata[:extra_failure_lines])
        frames = Backtrace::Parser.parse(backtrace_for(exception), @config.classifier)

        Failure.new(
          **identity(example),
          exception_class: exception_class_name(exception),
          message: message_for(notification, exception, extra),
          reduced: @config.reducer.call(frames),
          frames: frames,
          diagnostics: diagnostics(example, extra),
          shared_group_locations: shared_group_locations(example),
          raw: raw_output(notification, position)
        )
      end

      private

      def identity(example)
        {
          description: example.full_description,
          spec_location: display_location(example),
          rerun: safe(example) { example.location_rerun_argument&.sub(%r{\A\./}, "") },
          example_id: safe(example) { example.id }
        }
      end

      def message_for(notification, exception, extra)
        appended = extra + shared_group_descriptions(notification.example)
        lines = message_lines_for(notification, appended) + cause_lines(exception)
        Message.new(lines, redactor: @config.redactor, project: @config.project)
      end

      # We use the exception's own backtrace rather than RSpec's filtered one:
      # RSpec's filter is all-or-nothing per line and we need to make the
      # keep/drop decision ourselves.
      #
      # An aggregated failure is the exception: its own backtrace is the
      # aggregator's internals and explains nothing, while each sub-failure
      # carries the real one.
      def backtrace_for(exception)
        sub_exceptions(exception).first&.backtrace || exception.backtrace || []
      end

      def sub_exceptions(exception)
        return [] unless exception.respond_to?(:all_exceptions)

        Array(exception.all_exceptions)
      rescue StandardError
        []
      end

      # For an aggregated failure RSpec deliberately empties `message_lines` and
      # moves the detail into formatter-only callbacks, so fall back to the
      # rendered output and strip the parts we render ourselves.
      def message_lines_for(notification, appended)
        lines = strip_appended(notification.message_lines, appended)
        return lines unless lines.all? { |line| line.to_s.strip.empty? }

        rendered_message_lines(notification)
      end

      def rendered_message_lines(notification)
        text = notification.fully_formatted(nil, ::RSpec::Core::Notifications::NullColorizer)
        lines = text.to_s.split("\n")
                    .reject { |line| line.strip.start_with?("# ") } # RSpec's own backtrace
                    .drop_while { |line| line.strip.empty? }
        lines.shift if lines.first.to_s.strip == notification.example.full_description
        dedent(lines)
      rescue StandardError
        []
      end

      def dedent(lines)
        present = lines.reject { |line| line.strip.empty? }
        return lines if present.empty?

        indent = present.map { |line| line[/\A */].length }.min
        lines.map { |line| line[indent..] || "" }
      end

      # RSpec puts the "Caused by" chain in the *backtrace*, not the message, so
      # it disappears the moment you reduce a backtrace. The root cause is very
      # often the actual answer -- a PG::UniqueViolation behind a bland
      # RuntimeError -- so it is folded into the message, where it also becomes
      # part of the fingerprint.
      def cause_lines(exception)
        causes(exception).flat_map do |cause|
          lines = ["", "Caused by #{exception_class_name(cause)}:"]
          lines.concat(cause.message.to_s.split("\n").first(MAX_CAUSE_MESSAGE_LINES).map { |line| "  #{line}" })
          origin = cause_origin(cause)
          lines << "  at #{origin}" if origin
          lines
        end
      rescue StandardError
        []
      end

      def causes(exception)
        chain = []
        seen = [exception]
        current = exception

        while (current = current.cause) && !seen.include?(current) && chain.size < MAX_CAUSE_DEPTH
          seen << current
          chain << current
        end
        chain
      end

      # The first frame of the cause that belongs to the project, so the reader
      # knows where to look without us rendering a second full trace.
      def cause_origin(cause)
        frames = Backtrace::Parser.parse(Array(cause.backtrace).first(MAX_CAUSE_SCAN), @config.classifier)
        frame = frames.find(&:project?) || frames.reject(&:framework?).first
        frame&.location
      end

      def exception_class_name(exception)
        name = exception.class.name.to_s
        name.empty? ? "(anonymous error class)" : name
      end

      def display_location(example)
        location = safe(example) { example.location } || ""
        @config.project.display_path(location.sub(/:(\d+)\z/, "")) + location[/:(\d+)\z/].to_s
      end

      def shared_group_descriptions(example)
        Array(example.metadata[:shared_group_inclusion_backtrace]).map { |frame| frame.description.to_s }
      rescue StandardError
        []
      end

      def shared_group_locations(example)
        Array(example.metadata[:shared_group_inclusion_backtrace]).filter_map do |frame|
          next unless frame.respond_to?(:inclusion_location)

          location = frame.inclusion_location.to_s.sub(/:in\s+[`'].*\z/, "")
          parsed = Backtrace::Parser.parse_line(location)
          next unless parsed

          rendered = "#{@config.project.display_path(parsed.path)}:#{parsed.line}"
          "#{frame.shared_group_name.inspect} at #{rendered}"
        end
      rescue StandardError
        []
      end

      # RSpec appends screenshot output and shared-group breadcrumbs to
      # `message_lines`. We surface those separately, so peel them back off.
      def strip_appended(lines, appended)
        result = Array(lines).dup
        drop = appended.map(&:to_s).map(&:rstrip).reject(&:empty?)
        while result.any?
          last = result.last.to_s.rstrip
          break unless last.empty? || drop.include?(last)

          result.pop
        end
        result
      end

      def diagnostics(example, extra_failure_lines)
        captured = example.metadata[:rspec_signal_diagnostics]
        diagnostics = captured.is_a?(Hash) ? captured.dup : {}

        screenshots = extra_failure_lines.flat_map { |line| line.to_s.scan(SCREENSHOT).flatten }
        diagnostics[:screenshot] ||= relative(screenshots.first) if screenshots.any?

        diagnostics = diagnostics.transform_values { |value| scrub(value) }
        diagnostics.reject { |_, value| value.nil? || value.to_s.strip.empty? }
      end

      def scrub(value)
        return value.map { |item| @config.redactor.call(item.to_s) } if value.is_a?(Array)

        @config.redactor.call(value.to_s)
      end

      def relative(path)
        @config.project.display_path(path.to_s)
      end

      def raw_output(notification, position)
        return nil unless @config.write_full

        text = notification.fully_formatted(position, ::RSpec::Core::Notifications::NullColorizer)
        @config.redactor.call(text)
      rescue StandardError => e
        "  #{position}) [rspec-signal could not render the original output: #{e.class}]"
      end

      def safe(_example)
        yield
      rescue StandardError
        nil
      end
    end
  end
end
