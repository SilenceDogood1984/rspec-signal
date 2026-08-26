# frozen_string_literal: true

module RSpec
  module Signal
    module Reporters
      # The unreduced failure output, preserved verbatim.
      #
      # This exists so reduction is never lossy in practice: if the compact
      # report dropped the one frame that mattered, the original is one file
      # away. It is not the artifact you hand to an agent.
      class FullOutput
        def initialize(report, config)
          @report = report
          @config = config
        end

        def render
          out = ["rspec-signal #{VERSION} -- unreduced failure output", ""]
          @report.failures.each_with_index do |failure, index|
            out << (failure.raw || fallback(failure, index + 1))
            out << ""
          end
          "#{out.join("\n").rstrip}\n"
        end

        private

        def fallback(failure, position)
          lines = ["  #{position}) #{failure.description}",
                   "     #{failure.exception_class}:",
                   *failure.message.lines.map { |line| "       #{line}" }]
          lines.concat(failure.frames.map { |frame| "     # #{frame}" })
          lines.join("\n")
        end
      end
    end
  end
end
