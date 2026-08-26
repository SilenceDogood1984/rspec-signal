# frozen_string_literal: true

require_relative "symptoms/http_status"
require_relative "symptoms/route"
require_relative "symptoms/selector"
require_relative "symptoms/record"
require_relative "symptoms/ruby_error"
require_relative "symptoms/exception_class"

module RSpec
  module Signal
    # The symptom extractors, in the order they are tried.
    #
    # A failure takes the first symptom that matches and no more, so it belongs
    # to at most one related cluster. The order is significance, not
    # convenience: a 404 in a request spec is a better organising fact than the
    # exception class that carried it, and the exception class is a worse one
    # than everything above it, which is why it is last.
    module Symptoms
      EXTRACTORS = [HttpStatus, Route, Selector, Record, RubyError, ExceptionClass].freeze

      module_function

      # @param failure [Failure]
      # @return [Symptom, nil]
      def for(failure)
        text = one_line(failure.message.text)
        EXTRACTORS.each do |extractor|
          symptom = extractor.call(failure, text)
          return symptom if symptom
        end
        nil
      rescue StandardError
        nil
      end

      # Extractor patterns are written against a single line: RSpec wraps the
      # same sentence differently depending on matcher and terminal width.
      def one_line(text) = text.to_s.gsub(/\s+/, " ").strip
    end
  end
end
