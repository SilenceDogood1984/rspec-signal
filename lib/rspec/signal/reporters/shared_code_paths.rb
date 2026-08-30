# frozen_string_literal: true

module RSpec
  module Signal
    module Reporters
      # The "Shared code paths" section of the Markdown report.
      #
      # Every other analysis in this gem reads the failure *message*. This one
      # reads the *stack*, and it is the only thing in the report that can
      # relate two signatures whose messages have nothing in common.
      #
      # It states a measured fact and no more: these signatures execute this
      # line. It does not say the line is the cause -- the section says so in
      # those words -- because a reader who takes a shared frame for a diagnosis
      # has been misled, and this analysis is deliberately cheap enough to be
      # occasionally uninteresting.
      class SharedCodePaths
        MAX_SIGNATURES = 8
        MAX_LABELS = 2

        PREAMBLE = "First-party lines that more than one signature runs through, most signatures first. " \
                   "A measured fact, not a diagnosis: these examples all execute this line. " \
                   "The signatures below remain authoritative."

        # @param paths [Array<CodePath>]
        # @param signature_positions [Hash{String => Integer}] digest => index in the report
        def initialize(paths, signature_positions, config)
          @paths = paths
          @signature_positions = signature_positions
          @config = config
        end

        # @return [String, nil] nil when nothing is shared, so the section vanishes
        def render
          return nil if shown.empty?

          rows = shown.map { |path| row(path) }
          body = rows.join("\n")
          body = "#{body}\n\n#{truncation_note}" if hidden.positive?
          [["## Shared code paths", "", PREAMBLE].join("\n"), body].join("\n\n")
        end

        private

        def shown
          @shown ||= @config.max_code_paths ? @paths.first(@config.max_code_paths) : @paths
        end

        def hidden
          @paths.size - shown.size
        end

        def truncation_note
          "_#{hidden} further shared #{plural(hidden, "path")} not rendered (see `signal.json`)._"
        end

        def row(path)
          "- `#{path.location}`#{labels(path)} -- " \
            "#{path.signature_count} #{plural(path.signature_count, "signature")}, " \
            "#{path.size} #{plural(path.size, "example")} (#{signatures(path)})"
        end

        # The method names the line was reached under. Often the whole answer:
        # `rate_for` says more than `app/pricing.rb:4` alone.
        def labels(path)
          named = path.labels.reject { |label| label.start_with?("block ", "<") }.first(MAX_LABELS)
          return "" if named.empty?

          " in #{named.map { |label| "`#{label}`" }.join(", ")}"
        end

        def signatures(path)
          positions = path.signatures.filter_map { |digest| @signature_positions[digest] }.sort
          visible = positions.first(MAX_SIGNATURES).map { |position| "##{position}" }
          remaining = positions.size - visible.size
          visible << "and #{remaining} more" if remaining.positive?
          visible.join(", ")
        end

        def plural(count, word)
          count == 1 ? word : "#{word}s"
        end
      end
    end
  end
end
