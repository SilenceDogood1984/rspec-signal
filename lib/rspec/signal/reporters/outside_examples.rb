# frozen_string_literal: true

module RSpec
  module Signal
    module Reporters
      # The "Errors outside examples" section of the Markdown report.
      #
      # A spec file that would not load, or a `before(:suite)` hook that blew
      # up, produces no failed example at all -- RSpec reports it on its message
      # stream instead. It goes first in the report because nothing below it
      # ran: a suite that reports two failures and one unloadable file has not
      # told you about two failures, it has told you about however many that
      # file contains, plus two.
      class OutsideExamples
        def initialize(report, config)
          @report = report
          @config = config
        end

        # @return [Array<String>] sections, empty when the run had none
        def render
          return [] unless @report.errors_outside_examples.positive?

          captured = @report.outside_example_failures
          [heading(captured.size)] +
            captured.each_with_index.map { |failure, index| section(failure, index + 1) }
        end

        private

        def heading(captured)
          count = @report.errors_outside_examples
          lines = ["## Errors outside examples", "",
                   "#{count} #{plural(count, "error")} occurred outside of any example " \
                   "(a spec file that failed to load, a `before(:suite)` hook, or similar). " \
                   "No example in the affected files ran."]
          lines << "" << uncaptured_note(count - captured) if captured < count
          lines.join("\n")
        end

        def uncaptured_note(remaining)
          "#{remaining} of #{remaining == 1 ? "them" : "those"} could not be captured; " \
            "the full text is in RSpec's own output."
        end

        def section(failure, position)
          [
            ["### E#{position}. #{failure.exception_class}", "", "> #{one_line(failure.description)}"].join("\n"),
            fenced(failure.message.body(max_lines: @config.max_message_lines,
                                        max_diff_lines: @config.max_diff_lines)),
            "- Raised in `#{failure.spec_location}`",
            labelled("Trace", fenced(trace(failure))),
            labelled("Rerun", fenced([Rerun.command([failure.rerun_argument])], "bash"))
          ].join("\n\n")
        end

        def trace(failure)
          entries = failure.reduced.entries.map(&:to_s)
          entries.empty? ? ["#{failure.spec_location}  (no backtrace available)"] : entries
        end

        def labelled(label, body)
          "**#{label}**\n\n#{body}"
        end

        def fenced(lines, language = "text")
          ["```#{language}", *Array(lines), "```"].join("\n")
        end

        def one_line(text)
          text.to_s.gsub(/\s+/, " ").strip
        end

        def plural(count, word)
          count == 1 ? word : "#{word}s"
        end
      end
    end
  end
end
