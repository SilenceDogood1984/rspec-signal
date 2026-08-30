# frozen_string_literal: true

module RSpec
  module Signal
    # Recovers the failures RSpec reports without an example: a spec file that
    # would not load, a `before(:suite)` hook that blew up, a `--require` that
    # raised.
    #
    # These arrive on RSpec's `message` stream rather than as failed examples
    # (`Reporter#notify_non_example_exception`), already rendered by RSpec's own
    # `ExceptionPresenter`. That rendering is what this parses back apart, so a
    # load error goes through the same reduction, redaction and grouping as any
    # other failure instead of being reported as a bare count.
    #
    # This is the failure mode an agent causes most often -- a bad require, a
    # constant renamed halfway through an edit -- and it was the one the report
    # could not describe.
    module OutsideExample
      # RSpec's own wording, from `Configuration#load_file_handling_errors` and
      # `Runner`. Matching on it keeps every other `message` -- filter
      # announcements, custom `reporter.message` calls -- out of the report.
      CONTEXTS = [
        /\AAn error occurred while loading /,
        /\AAn error occurred (?:in|while running) an? [`'"]?(?:before|after|around)/,
        /\AAn error occurred while (?:shutting down|loading)/
      ].freeze

      # `# ./spec/foo_spec.rb:1:in '<top (required)>'`
      BACKTRACE_LINE = /\A\s*#\s(.+)\z/.freeze

      # RSpec appends a spelling suggestion to the heading, and puts the
      # suggested command on the following lines.
      SUGGESTION = / - Did you mean\?.*\z/.freeze

      SPEC_FILE = /while loading (\S+?)\.?(?:\s|\z)/.freeze

      CLASS_LABEL = /\A[A-Z]\w*(?:::\w+)*:\z/.freeze

      module_function

      # @param text [String] the fully formatted message RSpec emitted
      # @return [Boolean]
      def failure?(text)
        first = text.to_s.lstrip.lines.first.to_s.strip
        CONTEXTS.any? { |pattern| pattern.match?(first) }
      end

      # @param text [String]
      # @param config [Configuration]
      # @param position [Integer] 1-based, for the raw dump
      # @return [Failure, nil]
      def build(text, config, position: nil)
        lines = text.to_s.split("\n").drop_while { |line| line.strip.empty? }
        return nil if lines.empty?

        heading = lines.first.to_s.strip
        context = heading.sub(SUGGESTION, "")
        body, backtrace = partition(strip_suggestion(lines.drop(1), heading))
        frames = Backtrace::Parser.parse(backtrace, config.classifier)
        location = location_for(context, frames, config)

        Failure.new(
          description: context,
          spec_location: location,
          exception_class: exception_class(body),
          message: message_for(body, config),
          reduced: config.reducer.call(frames),
          frames: frames,
          rerun: rerun_for(context, location),
          raw: raw(config, text, position)
        )
      rescue StandardError
        nil
      end

      # The suggested rerun command RSpec prints after "Did you mean?" is
      # advice about a different file, and would otherwise open the message.
      def strip_suggestion(lines, heading)
        return lines unless SUGGESTION.match?(heading)

        rest = lines.drop_while { |line| !line.strip.empty? }
        rest.empty? ? lines : rest.drop(1)
      end

      def partition(lines)
        body = []
        backtrace = []
        lines.each do |line|
          match = BACKTRACE_LINE.match(line)
          next backtrace << match[1] if match

          body << line
        end
        [body, backtrace]
      end

      # `Failure/Error: require "missing"` then a blank line then
      # `LoadError:` then the indented message.
      def exception_class(body)
        label = body.map(&:strip).find { |line| CLASS_LABEL.match?(line) }
        label ? label.chomp(":") : "Error outside examples"
      end

      def message_for(body, config)
        Message.new(body, redactor: config.redactor, project: config.project,
                          html_threshold: config.html_threshold)
      end

      # The file RSpec named, so the report points at something openable.
      def spec_file(context)
        context[SPEC_FILE, 1]
      end

      # The project frame if there is one -- it carries a line number, which is
      # what makes the location worth opening -- and the file RSpec named
      # otherwise.
      def location_for(context, frames, config)
        frame = frames.find(&:project?)
        return frame.location if frame

        file = spec_file(context)
        file ? config.project.display_path(file) : context
      end

      # A load error reruns the file RSpec named. Anything else -- a suite
      # hook, a shutdown error -- has no example to name, so rerun the file it
      # was raised from, without a line number: a `before(:suite)` hook is not
      # on the line you would otherwise target.
      def rerun_for(context, location)
        spec_file(context) || location.to_s.sub(/:\d+\z/, "")
      end

      def raw(config, text, position)
        prefix = position ? "  #{position}) " : ""
        config.redactor.call("#{prefix}#{text}")
      end
    end
  end
end
