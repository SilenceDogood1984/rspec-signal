# frozen_string_literal: true

module RSpec
  module Signal
    # The human-readable failure message, plus a normalized form used for
    # grouping.
    class Message
      ANSI = /\e\[[0-9;]*[A-Za-z]/.freeze

      # Volatile substrings that would otherwise split identical failures into
      # separate signatures.
      NORMALIZERS = [
        [/0x[0-9a-f]{4,}/i, "0xXXXX"],
        [/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, "<uuid>"],
        [/\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?/, "<time>"],
        # No `\b` here: there is no word boundary between a space and a slash.
        [%r{(?<![\w/])(?:/tmp|/var/folders|/private/var/folders)/[\w./+-]+}, "<tmppath>"],
        [/\bid[:=]\s*\d+/i,                                             "id=<n>"],
        [/\b\d{4,}\b/,                                                  "<n>"],
        [/:\d+:in\s+[`'][^'`]*['`]/,                                    ""],
        # Diff hunk headers count lines; the lines themselves are already in
        # the message, and the counts split otherwise identical failures.
        [/@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@/,                          "@@"],
        # An HTML summary's size differs between two renderings of the same
        # broken page; its title and headings do not, and those are the part
        # worth fingerprinting.
        [/\[HTML document:[^\]]*\]/,                                    "[HTML document]"]
      ].freeze

      MAX_FINGERPRINT_CHARS = 400

      # Smallest HTML blob worth replacing with a summary. Below this the
      # markup is short enough to read, and reading it is the point.
      DEFAULT_HTML_THRESHOLD = 1_500

      attr_reader :lines, :cause_lines

      # @param lines [Array<String>] message lines as RSpec presents them
      # @param redactor [Redactor]
      # @param project [Project]
      # @param html_threshold [Integer, nil] nil disables HTML reduction
      # @param cause_lines [Array<String>] the `Caused by ...` chain, already
      #   bounded by {FailureBuilder} -- kept apart from `lines` so neither the
      #   line budget in {#body} nor the character budget in {#normalized} can
      #   push it out. It is very often the actual answer.
      def initialize(lines, redactor:, project:, html_threshold: DEFAULT_HTML_THRESHOLD, cause_lines: [])
        @redactor = redactor
        @project = project
        @lines = trim(squeeze(reduce_html(normalize(lines), html_threshold)))
        @cause_lines = trim(squeeze(reduce_html(normalize(cause_lines), html_threshold)))
      end

      def empty?
        @lines.all?(&:empty?) && @cause_lines.all?(&:empty?)
      end

      def text
        return @lines.join("\n") if @cause_lines.empty?

        "#{@lines.join("\n")}\n\n#{@cause_lines.join("\n")}"
      end

      # The one line that says what went wrong, for the signature index.
      #
      # RSpec opens every failure with `Failure/Error:` echoing the source
      # expression, which the reader can already see and which is identical
      # across every example that shares a line. The line worth showing is the
      # one after it: `key not found: :title`, not `def render; @rows.map ...`.
      def summary(limit = 160)
        line = diagnostic_line
        line.empty? ? headline(limit) : truncate(line, limit)
      end

      # First meaningful line, for headings and one-line summaries.
      def headline(limit = 160)
        line = @lines.find { |l| !l.strip.empty? }.to_s.strip
        line = @lines.reject(&:empty?)[1].to_s.strip if line.empty?
        truncate(line, limit)
      end

      # The message body for the report, with oversized diffs trimmed.
      #
      # Diffs are the single biggest source of bloat in RSpec output, and the
      # first lines of a diff almost always carry the signal. The cause chain
      # is appended after truncation, never counted against `max_lines`: a
      # verbose wrapper message must not be able to push the root cause out.
      def body(max_lines: 30, max_diff_lines: 20)
        kept = truncated_lines(max_lines: max_lines, max_diff_lines: max_diff_lines)
        return kept if @cause_lines.empty?

        kept + ["", *@cause_lines]
      end

      # Stable form used for fingerprinting. The cause chain is appended after
      # the main text is truncated to `MAX_FINGERPRINT_CHARS`, so two
      # otherwise-identical wrapper messages with different causes never
      # collapse into one signature just because the wrapper is long.
      def normalized
        @normalized ||= begin
          main = truncate(normalize_for_fingerprint(@lines.join(" ")), MAX_FINGERPRINT_CHARS)
          cause = normalize_for_fingerprint(@cause_lines.join(" "))
          cause.empty? ? main : "#{main} #{cause}"
        end
      end

      private

      # RSpec separates the source echo from the diagnosis with a blank line
      # when it can. When it cannot -- a matcher that appends its message
      # straight onto the echo -- fall back to dropping just the echo line.
      def diagnostic_line
        blocks = @lines.chunk { |line| line.strip.empty? }.reject(&:first).map(&:last)
        return "" if blocks.empty?

        candidate = source_echo?(blocks.first.first) && blocks.size > 1 ? blocks[1] : blocks.first
        candidate = candidate.drop(1) if source_echo?(candidate.first)
        candidate = candidate.drop(1) if candidate.size > 1 && class_label?(candidate.first)
        candidate.first.to_s.strip
      end

      def source_echo?(line)
        line.to_s.strip.start_with?("Failure/Error")
      end

      # A bare `KeyError:` / `ActiveRecord::RecordInvalid:` label line, which
      # duplicates the exception column beside it.
      def class_label?(line)
        /\A[A-Z]\w*(?:::\w+)*:\z/.match?(line.to_s.strip)
      end

      def truncated_lines(max_lines:, max_diff_lines:)
        kept = []
        diff_seen = 0
        in_diff = false

        @lines.each do |line|
          in_diff = true if line.strip.start_with?("Diff:", "@@")
          if in_diff
            diff_seen += 1
            next if diff_seen > max_diff_lines
          end
          kept << line
          break if kept.size >= max_lines
        end

        omitted = @lines.size - kept.size
        kept << "[#{omitted} more message line#{"s" unless omitted == 1} omitted]" if omitted.positive?
        kept
      end

      def normalize_for_fingerprint(text)
        text = @project.relative_to_root(text) if text.include?(@project.root)
        text = text.gsub(@project.root, ".")
        NORMALIZERS.each { |(pattern, replacement)| text = text.gsub(pattern, replacement) }
        text.gsub(/\s+/, " ").strip
      end

      # Reduction happens once, here, so that every later stage -- the body,
      # the headline in the index table, and the fingerprint -- sees the
      # summary rather than six thousand lines of exception-page CSS. The
      # original text can still be written verbatim to `full.txt` when enabled.
      def reduce_html(lines, threshold)
        return lines unless threshold

        HtmlSummary.reduce(lines, threshold: threshold)
      rescue StandardError
        lines
      end

      def normalize(lines)
        Array(lines).flat_map { |line| split_lines(line) }
                    .map { |line| @redactor.call(line.gsub(ANSI, "")).rstrip }
      end

      # `"".split("\n")` returns `[]`, which would silently swallow the blank
      # lines RSpec uses to separate the failing expression from the diff.
      def split_lines(line)
        text = line.to_s
        text.empty? ? [""] : text.split("\n")
      end

      def squeeze(lines)
        lines.chunk_while { |a, b| a.empty? && b.empty? }.map(&:first)
      end

      def trim(lines)
        lines.drop_while(&:empty?).reverse.drop_while(&:empty?).reverse
      end

      def truncate(string, limit)
        return string if string.length <= limit

        "#{string[0, limit - 1]}…"
      end
    end
  end
end
