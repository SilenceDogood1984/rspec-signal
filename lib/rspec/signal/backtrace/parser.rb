# frozen_string_literal: true

require_relative "frame"

module RSpec
  module Signal
    module Backtrace
      # Turns raw backtrace strings into {Frame}s.
      #
      # Handles the two shapes Ruby emits:
      #   "/path/to/file.rb:12:in `method'"
      #   "/path/to/file.rb:12:in 'Klass#method'"   (Ruby 3.4+ quoting)
      # and the shapes RSpec emits after its own filtering:
      #   "./spec/models/user_spec.rb:12"
      module Parser
        LINE = /
          \A
          (?<path>.*?)
          (?::(?<line>\d+))?
          (?::in\s+[`'](?<label>.*)['`])?
          \s*\z
        /x.freeze

        module_function

        # @param backtrace [Array<String>, nil]
        # @param classifier [#call] receives a Frame with :kind unset, returns the kind
        # @return [Array<Frame>]
        def parse(backtrace, classifier)
          Array(backtrace).filter_map do |raw|
            frame = parse_line(raw)
            next unless frame

            classifier.call(frame)
            frame
          end
        end

        def parse_line(raw)
          text = raw.to_s.strip
          return nil if text.empty?

          match = LINE.match(text)
          return nil unless match

          path = match[:path].to_s.sub(%r{\A\./}, "")
          return nil if path.empty?

          Frame.new(
            raw: text,
            path: path,
            line: match[:line]&.to_i,
            label: match[:label],
            kind: :external,
            display_path: path
          )
        end
      end
    end
  end
end
