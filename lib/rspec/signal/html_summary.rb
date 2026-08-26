# frozen_string_literal: true

module RSpec
  module Signal
    # Recognises bulk HTML inside a failure message and replaces it with the
    # handful of facts that actually diagnose it.
    #
    # A request spec that expects one sentence and receives a Rails exception
    # page produces a diff several thousand lines long whose opening hundred
    # lines are the exception page's own CSS. Printing the start of that is
    # worse than useless: it is the one part of the response guaranteed to be
    # identical for every failure in the suite. So the expected value is left
    # exactly as it was, the actual value is named as HTML and measured, and the
    # title, headings and leading visible text are pulled out -- which on a
    # Rails error page is the exception class and its message.
    #
    # Regex only, deliberately. A DOM parser would be a new hard dependency for
    # something that never has to be correct, only useful, and which is handed
    # broken markup by definition.
    class HtmlSummary
      MARKER = "[HTML document]"

      MIN_TAGS       = 5
      SCAN_WINDOW    = 4_000
      MAX_FACT_CHARS = 160
      MAX_FACTS      = 4

      DOCUMENT_START = /\A\s*(?:<!doctype\s+html|<html[\s>])/i
      TAG            = %r{</?[a-z][a-z0-9]*(?:\s[^<>]*?)?/?>}im
      STRUCTURAL     = /<(?:html|head|body|div|table|section|main|article|p)\b/i
      QUOTED         = /"(?:[^"\\]|\\.)*"/m
      DIFF_LINE      = /\A(\s*)([-+])(.*)\z/m
      NOISE          = %r{<(script|style)\b[^>]*>.*?</\1>|<!--.*?-->}im
      TITLE          = %r{<title[^>]*>(.*?)</title>}im
      H1             = %r{<h1[^>]*>(.*?)</h1>}im
      H2             = %r{<h2[^>]*>(.*?)</h2>}im
      PRE            = %r{<pre[^>]*>(.*?)</pre>}im

      ESCAPES  = { "n" => "\n", "t" => "\t", "r" => "\r", "e" => "\e", '"' => '"', "\\" => "\\" }.freeze
      ENTITIES = { "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"',
                   "apos" => "'", "#39" => "'", "nbsp" => " " }.freeze

      class << self
        # @param lines [Array<String>] message lines
        # @param threshold [Integer] smallest blob worth summarising
        # @return [Array<String>] the same lines with bulk HTML replaced
        def reduce(lines, threshold:)
          reduce_diff_runs(reduce_inline(lines, threshold), threshold)
        end

        # @return [HtmlSummary, nil]
        def summarise(text, threshold)
          return nil if text.length < threshold

          html = unescape(text)
          return nil unless html?(html)

          new(html)
        end

        def html?(text)
          return true if DOCUMENT_START.match?(text)

          window = text[0, SCAN_WINDOW].to_s
          STRUCTURAL.match?(window) && window.scan(TAG).size >= MIN_TAGS
        end

        private

        # RSpec renders the actual value with `inspect`, so a whole response
        # body arrives as one enormous line with two-character escapes in it.
        def reduce_inline(lines, threshold)
          lines.flat_map do |line|
            next [line] if line.length < threshold

            replaced, summaries = replace_blobs(line, threshold)
            next [line] if summaries.empty?

            [replaced, "", *summaries.flat_map(&:to_lines)]
          end
        end

        def replace_blobs(line, threshold)
          summaries = []
          replaced = line.gsub(QUOTED) do |quoted|
            summary = summarise(quoted[1..-2].to_s, threshold)
            next quoted unless summary

            summaries << summary
            MARKER
          end
          return [replaced, summaries] unless summaries.empty?

          replace_bare_blob(line, threshold)
        end

        # The same value, but rendered without quotes -- `eq` diffs and some
        # custom matchers do this.
        def replace_bare_blob(line, threshold)
          start = line =~ /<(?:!doctype|html|head|body|div)\b/i
          return [line, []] unless start

          summary = summarise(line[start..].to_s, threshold)
          return [line, []] unless summary

          ["#{line[0, start]}#{MARKER}", [summary]]
        end

        # In a unified diff the response arrives as a run of real lines, all
        # carrying the same +/- marker.
        def reduce_diff_runs(lines, threshold)
          result = []
          index = 0
          while index < lines.length
            finish, summary = diff_run(lines, index, threshold)
            if finish.nil?
              result << lines[index]
              index += 1
            else
              result.concat(summary ? summary.to_lines : lines[index...finish])
              index = finish
            end
          end
          result
        end

        def diff_run(lines, start, threshold)
          match = DIFF_LINE.match(lines[start].to_s)
          return nil unless match

          marker = match[2]
          finish = start
          payload = []
          while (line = lines[finish]) && (parts = DIFF_LINE.match(line.to_s)) && parts[2] == marker
            payload << parts[3]
            finish += 1
          end
          [finish, summarise(payload.join("\n"), threshold)]
        end

        # Only inspected strings carry escapes; a diff run is already real lines.
        def unescape(text)
          return text if text.include?("\n")

          text.gsub(/\\(.)/) { ESCAPES.fetch(::Regexp.last_match(1), ::Regexp.last_match(0)) }
        end
      end

      attr_reader :line_count, :byte_size

      def initialize(html)
        @html = html
        @line_count = html.count("\n") + 1
        @byte_size = html.bytesize
      end

      # `[["Title", "Action Controller: Exception caught"], ...]`
      def facts
        @facts ||= build_facts
      end

      def to_lines
        ["[HTML document: #{number(line_count)} #{plural(line_count, "line")}, #{human_size} " \
         "-- markup omitted]",
         *facts.map { |(label, value)| "  #{label}: #{value}" }]
      end

      def to_h
        { lines: line_count, bytes: byte_size }.merge(facts.to_h { |(label, value)| [label.downcase.to_sym, value] })
      end

      private

      def build_facts
        body = @html.gsub(NOISE, " ")
        entries = []
        push(entries, "Title", tag_text(@html, TITLE))
        push(entries, "Heading", tag_text(body, H1))
        push(entries, "Message", tag_text(body, H2) || tag_text(body, PRE))
        push(entries, "Text", excerpt(body)) if entries.size < 2
        entries.first(MAX_FACTS)
      end

      def push(entries, label, value)
        return if value.nil? || value.empty?
        return if entries.any? { |(_, existing)| existing == value }

        entries << [label, value]
      end

      def tag_text(source, pattern)
        match = pattern.match(source)
        return nil unless match

        visible(match[1])
      end

      def excerpt(body) = visible(body)

      def visible(fragment)
        text = fragment.to_s.gsub(NOISE, " ").gsub(TAG, " ")
        text = text.gsub(/&(#?\w+);/) { ENTITIES.fetch(::Regexp.last_match(1).downcase, " ") }
        truncate(text.gsub(/\s+/, " ").strip)
      end

      def truncate(text)
        return text if text.length <= MAX_FACT_CHARS

        "#{text[0, MAX_FACT_CHARS - 1]}…"
      end

      def human_size
        return "#{number(byte_size)} bytes" if byte_size < 1024
        return "#{number((byte_size / 1024.0).round)} KB" if byte_size < (1024 * 1024)

        "#{(byte_size / (1024.0 * 1024)).round(1)} MB"
      end

      def number(value) = value.to_s.reverse.scan(/\d{1,3}/).join(",").reverse

      def plural(count, word) = count == 1 ? word : "#{word}s"
    end
  end
end
