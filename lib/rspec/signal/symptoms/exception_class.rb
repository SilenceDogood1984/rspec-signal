# frozen_string_literal: true

module RSpec
  module Signal
    module Symptoms
      # The last resort: cluster on the exception class itself.
      #
      # This is the one that would wreck the report if it were applied
      # generally, so it is applied narrowly. It fires only for a *namespaced*
      # class -- `PG::ConnectionBad`, `Errno::ECONNREFUSED` -- which is
      # specific enough that seeing it twice is a fact worth reporting. Bare
      # classes like RuntimeError and ArgumentError say nothing about cause and
      # are refused outright, and so is every class an earlier, finer extractor
      # is responsible for, so that a Capybara lookup with an unparseable
      # message cannot fall through and drag unrelated selectors in with it.
      module ExceptionClass
        GENERIC = %w[
          RuntimeError StandardError Exception ScriptError ArgumentError TypeError NameError
          NoMethodError NotImplementedError IndexError KeyError RangeError IOError EOFError
          FrozenError LocalJumpError StopIteration ZeroDivisionError SystemStackError
          LoadError SyntaxError SecurityError ThreadError FiberError
        ].freeze

        # Owned by an earlier extractor; never eligible here.
        CLAIMED = %w[
          RSpec::
          Capybara::ElementNotFound Capybara::ExpectationNotMet
          ActiveRecord::RecordNotFound ActiveRecord::RecordInvalid
          ActionController::RoutingError ActionController::UrlGenerationError
        ].freeze

        module_function

        def call(failure, _text)
          name = failure.exception_class.to_s
          return nil unless name.include?("::")
          return nil if GENERIC.include?(name)
          return nil if CLAIMED.any? { |prefix| name.start_with?(prefix) }

          Symptom.new(kind: :exception_class, key: "exception:#{name}",
                      label: "`#{name}` raised in several places", detail: name)
        end
      end
    end
  end
end
