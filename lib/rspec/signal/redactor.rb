# frozen_string_literal: true

module RSpec
  module Signal
    # Best-effort scrubbing of obvious credentials before a report leaves the
    # machine.
    #
    # This is a safety net, not a guarantee. It targets shapes that are
    # unambiguous (token prefixes, auth headers, credential-ish assignments) and
    # deliberately does not try to guess at arbitrary secret values, because
    # false positives destroy the diagnostic value of a report.
    #
    # Always review artifacts before sending them somewhere you do not control.
    class Redactor
      PLACEHOLDER = "[REDACTED]"

      # Keys whose *values* are considered sensitive.
      SENSITIVE_KEY = /
        (?:api[_-]?key|secret[_-]?key|access[_-]?key|client[_-]?secret|private[_-]?key|
           secret|password|passwd|pwd|token|auth[_-]?token|access[_-]?token|refresh[_-]?token|
           session[_-]?id|csrf|cookie|authorization|credentials?)
      /xi

      DEFAULT_PATTERNS = [
        # Authorization: Bearer xyz / Basic xyz
        /\b(Authorization\s*[:=]\s*["']?\s*(?:Bearer|Basic|Token)\s+)[^\s"',;)\]}]+/i,
        # key: "value" / key => 'value' / key=value / "key":"value"
        /(["']?#{SENSITIVE_KEY.source}["']?\s*(?:=>|[:=])\s*)(["'])(?:(?!\2).){3,}\2/xi,
        /(\b#{SENSITIVE_KEY.source}\s*=\s*)(?!["'])[^\s"',;&)\]}]{3,}/xi,
        # URL query parameters
        /([?&]#{SENSITIVE_KEY.source}=)[^&\s"'<>]+/xi,
        # URL userinfo: https://user:pass@host
        %r{(\b[a-z][a-z0-9+.-]*://[^/\s:@]+:)[^/\s@]+(@)}i,
        # Well-known token shapes
        /\bAKIA[0-9A-Z]{16}\b/,
        /\bASIA[0-9A-Z]{16}\b/,
        /\bgh[pousr]_[A-Za-z0-9]{20,}\b/,
        /\bgithub_pat_[A-Za-z0-9_]{20,}\b/,
        /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/,
        /\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{10,}\b/,
        /\bglpat-[A-Za-z0-9_-]{16,}\b/,
        /\bAIza[0-9A-Za-z_-]{30,}\b/,
        # JWTs
        /\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*/,
        # PEM blocks
        /-----BEGIN[A-Z ]*PRIVATE KEY-----.*?-----END[A-Z ]*PRIVATE KEY-----/m
      ].freeze

      def initialize(enabled: true, patterns: DEFAULT_PATTERNS, extra_patterns: [], filter: nil)
        @enabled = enabled
        @patterns = patterns + Array(extra_patterns)
        @filter = filter
      end

      def enabled? = @enabled

      # @param text [String, nil]
      # @return [String, nil]
      def call(text)
        return text if text.nil? || !@enabled

        result = text.dup
        @patterns.each do |pattern|
          result = result.gsub(pattern) do |match|
            replacement_for(pattern, match, Regexp.last_match)
          end
        end
        result = @filter.call(result) if @filter
        result
      end
      alias scrub call

      private

      # Patterns with capture groups keep the identifying prefix so the report
      # still says *what* was redacted.
      def replacement_for(_pattern, match, captures)
        prefix = captures[1]
        return PLACEHOLDER if prefix.nil?

        suffix = captures[2] if captures[2] && captures[2] == "@"
        quote = captures[2] if captures[2] && %w[" '].include?(captures[2])

        return "#{prefix}#{quote}#{PLACEHOLDER}#{quote}" if quote
        return "#{prefix}#{PLACEHOLDER}#{suffix}" if suffix

        "#{prefix}#{PLACEHOLDER}" if match
      end
    end
  end
end
