# frozen_string_literal: true

module RSpec
  module Signal
    # The human-readable failure message, plus a normalized form used for
    # grouping.
    class Message
      ANSI = /\e\[[0-9;]*[A-Za-z]/

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
        [/:\d+:in\s+[`'][^'`]*['`]/,                                    ""]
      ].freeze

      MAX_FINGERPRINT_CHARS = 400

      attr_reader :lines

      # @param lines [Array<String>] message lines as RSpec presents them
      # @param redactor [Redactor]
      # @param project [Project]
      def initialize(lines, redactor:, project:)
        @redactor = redactor
        @project = project
        @lines = trim(squeeze(normalize(lines)))
      end

      def empty? = @lines.all?(&:empty?)

      def text = @lines.join("\n")

      # First meaningful line, for headings and one-line summaries.
      def headline(limit = 160)
        line = @lines.find { |l| !l.strip.empty? }.to_s.strip
        line = @lines.reject(&:empty?)[1].to_s.strip if line.empty?
        truncate(line, limit)
      end

      # The message body for the report, with oversized diffs trimmed.
      #
      # Diffs are the single biggest source of bloat in RSpec output, and the
      # first lines of a diff almost always carry the signal.
      def body(max_lines: 30, max_diff_lines: 20)
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

      # Stable form used for fingerprinting.
      def normalized
        @normalized ||= begin
          text = @lines.join(" ")
          text = @project.relative_to_root(text) if text.include?(@project.root)
          text = text.gsub(@project.root, ".")
          NORMALIZERS.each { |(pattern, replacement)| text = text.gsub(pattern, replacement) }
          truncate(text.gsub(/\s+/, " ").strip, MAX_FINGERPRINT_CHARS)
        end
      end

      private

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
