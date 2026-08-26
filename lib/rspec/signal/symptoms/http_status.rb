# frozen_string_literal: true

module RSpec
  module Signal
    module Symptoms
      # An HTTP status the application returned but the spec did not expect.
      #
      # Clustered on the *actual* status, because that is the fact with a shared
      # cause: eight specs that each wanted something different and all got 404
      # are eight symptoms of one broken route. The expected side survives only
      # as this failure's detail line, so a cluster can still show that some
      # examples wanted 200 and others wanted a redirect.
      module HttpStatus
        # One side of a status mismatch: `404`, `:not_found`, `:ok (200)`.
        CODE = /:?[\w-]+(?: \(\d{3}\))?/

        PATTERNS = [
          # rspec-rails `have_http_status(200)` / `have_http_status(:ok)`
          /expected the response to have status code (?<expected>#{CODE}) *,? *but it was (?<actual>#{CODE})/i,
          # rspec-rails `have_http_status(:success)` / `:redirect` / `:error` / `:missing`
          /expected the response to have an? (?<expected>\w+) status code \([^)]*\) *,? *but it was (?<actual>#{CODE})/i, # rubocop:disable Layout/LineLength
          # Rails' own `assert_response`
          /expected response to be a <(?<expected>[^>]+)>, *but was a <(?<actual>[^>]+)>/i,
          # The shorthand several house matchers use
          /expected(?: the)? response status (?:to be )?(?<expected>:?[\w-]+) *,? *(?:but )?got:? *(?<actual>:?[\w-]+)/i
        ].freeze

        # Enough of the standard set to name the common ones. An unrecognised
        # code still clusters, it just does not get a friendly name.
        NAMES = {
          "200" => "OK", "201" => "Created", "204" => "No Content", "301" => "Moved Permanently",
          "302" => "Found", "304" => "Not Modified", "400" => "Bad Request", "401" => "Unauthorized",
          "403" => "Forbidden", "404" => "Not Found", "406" => "Not Acceptable", "409" => "Conflict",
          "422" => "Unprocessable Entity", "429" => "Too Many Requests",
          "500" => "Internal Server Error", "502" => "Bad Gateway", "503" => "Service Unavailable"
        }.freeze

        CODES = {
          "ok" => "200", "created" => "201", "no_content" => "204", "moved_permanently" => "301",
          "found" => "302", "not_modified" => "304", "bad_request" => "400", "unauthorized" => "401",
          "forbidden" => "403", "not_found" => "404", "not_acceptable" => "406", "conflict" => "409",
          "unprocessable_entity" => "422", "unprocessable_content" => "422", "too_many_requests" => "429",
          "internal_server_error" => "500", "bad_gateway" => "502", "service_unavailable" => "503"
        }.freeze

        module_function

        GENERIC_EXPECTATION = /expected:\s*(?<expected>\d{3})\s+got:\s*(?<actual>\d{3})/i
        STATUS_EXPRESSION = /(?:response\s*\.\s*status|response\s*\.\s*status_code|response\s*\[\s*:status\s*\])/i

        def call(failure, text)
          match = PATTERNS.filter_map { |pattern| pattern.match(text) }.first
          match ||= generic_expectation(failure, text)
          return nil unless match

          actual = code(match[:actual])
          return nil unless actual

          Symptom.new(kind: :http_status, key: "http-status:#{actual}", label: label(actual),
                      detail: "expected #{token(match[:expected])}, got #{actual}")
        end

        # RSpec's generic equality matcher does not mention HTTP in its
        # expected/got lines. Only accept it when the captured failing
        # expression explicitly reads a response status, avoiding arbitrary
        # three-digit numeric comparisons.
        def generic_expectation(failure, text)
          return nil unless STATUS_EXPRESSION.match?(failure.message.text.to_s)

          GENERIC_EXPECTATION.match(text)
        end

        def label(actual)
          name = NAMES[actual]
          "unexpected #{actual}#{" (#{name})" if name} responses"
        end

        # The numeric code, whether it arrived as a number, a symbol, or both.
        def code(raw)
          text = raw.to_s
          return ::Regexp.last_match(1) if text =~ /(\d{3})/

          CODES[text.delete_prefix(":").downcase]
        end

        # How to word one side of the mismatch: a code where there is one, and
        # otherwise the word the matcher used -- `redirect`, `success`.
        def token(raw)
          text = raw.to_s.strip
          return ::Regexp.last_match(1) if text =~ /(\d{3})/

          bare = text.delete_prefix(":").downcase
          CODES[bare] || bare
        end
      end
    end
  end
end
