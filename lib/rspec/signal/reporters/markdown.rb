# frozen_string_literal: true

module RSpec
  module Signal
    module Reporters
      # Renders the primary artifact: a compact, model-neutral Markdown report.
      #
      # Deliberately contains no instructions to the reader. It is a diagnostic
      # document, not a prompt, so it works the same pasted into any assistant or
      # read by a human.
      class Markdown
        FENCE = "```"
        MAX_RERUN_ARGUMENTS = 10

        DIAGNOSTIC_LABELS = {
          url: "URL", path: "Path", title: "Page title", status_code: "Status",
          driver: "Driver", console: "Console", screenshot: "Screenshot", saved_page: "Saved HTML"
        }.freeze

        def initialize(report, config)
          @report = report
          @config = config
        end

        def render
          sections = [header]
          sections << outside_examples_notice
          # Themes before the inventory: what an agent needs first is the
          # possibility that thirty-five signatures are five problems.
          sections << related_section
          sections << index if @report.group_count > 1
          sections.concat(rendered_groups)
          sections << footer
          "#{sections.compact.join("\n\n").rstrip}\n"
        end

        private

        def header
          lines = ["# RSpec Signal", "", headline]
          lines << reduction_line if @report.total_frames.positive?
          lines << "" << meta_line
          lines << "" << conventions
          lines.join("\n")
        end

        def headline
          parts = [quantity(@report.example_count, "example"), quantity(@report.failure_count, "failure")]
          parts << "#{number(@report.pending_count)} pending" if @report.pending_count.positive?
          parts << "#{number(@report.group_count)} distinct #{plural(@report.group_count, "signature")}"
          parts << "#{number(@report.cluster_count)} related #{plural(@report.cluster_count, "cluster")}" \
            if @report.cluster_count.positive?
          parts << outside_examples_count if @report.errors_outside_examples.positive?
          "**#{parts.join(" | ")}**"
        end

        def outside_examples_count = "#{quantity(@report.errors_outside_examples, "error")} outside examples"

        def quantity(value, word) = "#{number(value)} #{plural(value, word)}"

        def reduction_line
          "Backtraces reduced from #{number(@report.total_frames)} to " \
            "#{number(@report.kept_frames)} frames " \
            "(#{number(@report.omitted_frames)} framework/library #{plural(@report.omitted_frames, "frame")} omitted)."
        end

        def meta_line
          bits = []
          bits << "seed `#{@report.seed}`" if @report.seed_used?
          bits << "#{@report.duration.round(2)}s" if @report.duration
          @report.environment.each { |name, version| bits << "#{name} #{version}" }
          bits << "rspec-signal #{VERSION}"
          bits.join(" | ")
        end

        def conventions
          "Trace frames are innermost first. Project paths are relative to the repository root; " \
            "third-party frames appear as `gem/path.rb:line`."
        end

        def index
          rows = groups.each_with_index.map do |group, position|
            "| #{position + 1} | #{group.size} | `#{group.exception_class}` | " \
              "#{escape(group.fingerprint.culprit)} | #{escape(one_line(group.message.headline(90)))} |"
          end
          ["## Signatures", "",
           "| # | Examples | Exception | Raised in | Message |",
           "|--:|---------:|-----------|-----------|---------|",
           *rows].join("\n")
        end

        def related_section
          RelatedFailures.new(@report.clusters, signature_positions, @config).render
        end

        # Cluster members point back at the numbered sections below, so the
        # reader can go straight from a symptom to the failures carrying it.
        def signature_positions
          @signature_positions ||= @report.groups.each_with_index.to_h { |group, i| [group.fingerprint.digest, i + 1] }
        end

        # A `before(:suite)` blow-up produces no failed examples at all. RSpec
        # only reports those through its message stream, which a formatter
        # cannot capture without swallowing every other message, so say plainly
        # what happened and where to look.
        def outside_examples_notice
          return nil unless @report.errors_outside_examples.positive?

          count = @report.errors_outside_examples
          ["## Errors outside examples", "",
           "#{number(count)} #{plural(count, "error")} occurred outside of any example " \
           "(a `before(:suite)` hook, a spec file that failed to load, or similar). " \
           "rspec-signal cannot capture their detail; the full text is in RSpec's own output."].join("\n")
        end

        def rendered_groups
          rendered = groups.each_with_index.map { |group, position| group_section(group, position + 1) }
          if truncated_groups.positive?
            rendered << "_#{truncated_groups} further #{plural(truncated_groups, "signature")} " \
                        "not rendered (see `signal.json`)._"
          end
          rendered
        end

        def group_section(group, position)
          sections = [
            heading(group, position),
            fenced(group.message.body(max_lines: @config.max_message_lines,
                                      max_diff_lines: @config.max_diff_lines)),
            locators(group).join("\n"),
            labelled("Trace", fenced(trace_lines(group.representative))),
            diagnostics_section(group.representative),
            labelled("Rerun", fenced(rerun_commands(group), "bash")),
            affected_section(group)
          ]
          sections.compact.join("\n\n")
        end

        def heading(group, position)
          ["## #{position}. #{group.exception_class}#{count_suffix(group)}", "",
           "> #{one_line(group.representative.description)}"].join("\n")
        end

        def labelled(label, body) = "**#{label}**\n\n#{body}"

        # The representative on its own, plus the whole signature when that is a
        # different command and short enough to be worth typing.
        def rerun_commands(group)
          commands = ["bundle exec rspec #{group.representative.rerun}"]
          arguments = group.failures.map(&:rerun).uniq
          if arguments.size > 1 && arguments.size <= MAX_RERUN_ARGUMENTS
            commands << "bundle exec rspec #{arguments.join(" ")}"
          end
          commands
        end

        def count_suffix(group)
          return "" if group.size == 1

          " -- #{group.size} examples"
        end

        def locators(group)
          failure = group.representative
          seen = [failure.spec_location]
          lines = ["- Example `#{failure.spec_location}`"]

          app_context = group.fingerprint.app_context
          if app_context && !seen.include?(app_context)
            lines << "- Your code `#{app_context}`"
            seen << app_context
          end

          culprit = group.fingerprint.culprit
          if culprit && !seen.include?(culprit)
            gem_name = culprit_frame(failure)&.gem_name
            lines << "- Raised in `#{culprit}`#{" (#{gem_name})" if gem_name}"
          end

          failure.shared_group_locations.first(3).each do |location|
            lines << "- Via shared example group #{location}"
          end

          if failure.reduced.fallback?
            lines << "- No first-party frames in this backtrace; innermost frames shown instead"
          end

          lines
        end

        # The same frame the fingerprint calls the culprit, so the gem label
        # beside a location always belongs to that location.
        def culprit_frame(failure) = failure.frames.reject(&:framework?).first

        def trace_lines(failure)
          entries = failure.reduced.entries.map(&:to_s)
          return ["#{failure.spec_location}  (no backtrace available)"] if entries.empty?

          entries
        end

        def diagnostics_section(failure)
          items = failure.diagnostics.reject { |_, value| value.nil? || value.to_s.empty? }
          return nil if items.empty?

          rows = items.map { |key, value| "- #{humanize(key)}: #{format_diagnostic(value)}" }
          labelled("Browser state", rows.join("\n"))
        end

        def format_diagnostic(value)
          return value.map { |item| "`#{one_line(item)}`" }.join("; ") if value.is_a?(Array)

          text = one_line(value)
          text.length > 300 ? "`#{text[0, 297]}...`" : "`#{text}`"
        end

        def affected_section(group)
          others = group.failures.reject { |failure| failure.equal?(group.representative) }
          return nil if others.empty?

          grouped = others.group_by(&:spec_location)
          shown = grouped.first(@config.max_affected_examples)
          rows = shown.map { |location, failures| affected_row(location, failures) }
          hidden = grouped.size - shown.size
          rows << "... and #{hidden} more #{plural(hidden, "location")}" if hidden.positive?

          labelled("Also failing identically (#{others.size})", fenced(rows))
        end

        # Parameterised examples all share one `it` line. Listing that line once
        # with a count says the same thing in a fraction of the space.
        def affected_row(location, failures)
          return "#{location}  #{one_line(failures.first.description)}" if failures.size == 1

          "#{location}  (#{failures.size} examples)"
        end

        def footer
          notes = ["---", "",
                   "Generated by [rspec-signal](https://github.com/SilenceDogood1984/rspec-signal). " \
                   "Backtrace frames from the test runner, loader and CLI are removed; " \
                   "first-party frames and the library frames adjacent to them are kept."]
          notes << "Review this file before sharing it: it can contain application data." if @config.redact?
          notes.join("\n")
        end

        def groups
          @groups ||= @config.max_groups ? @report.groups.first(@config.max_groups) : @report.groups
        end

        def truncated_groups = @report.group_count - groups.size

        def fenced(lines, language = "text")
          [FENCE + language, *Array(lines), FENCE].join("\n")
        end

        def one_line(text) = text.to_s.gsub(/\s+/, " ").strip

        def escape(text) = text.to_s.gsub("|", "\\|")

        def humanize(key)
          DIAGNOSTIC_LABELS.fetch(key.to_sym) { key.to_s.tr("_", " ").capitalize }
        end

        def plural(count, word) = count == 1 ? word : "#{word}s"

        def number(value) = value.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
      end
    end
  end
end
