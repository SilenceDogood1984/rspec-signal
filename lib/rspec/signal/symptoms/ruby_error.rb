# frozen_string_literal: true

module RSpec
  module Signal
    module Symptoms
      # Two Ruby-level messages specific enough to cluster on: a method called
      # on the wrong thing, and a constant that was never defined.
      #
      # `undefined method 'progress' for nil` in six specs is one nil, not six
      # bugs. Both the method and the receiver are part of the key, so
      # `#name for nil` and `#total for nil` stay apart.
      module RubyError
        # Ruby 3.4 quotes with `'x'`, earlier versions with `` `x' ``.
        UNDEFINED_METHOD = /undefined method [`'"](?<name>[^'"`]+)['"`] for (?:an instance of )?(?<receiver>\S+)/.freeze
        UNINITIALIZED    = /uninitialized constant (?<constant>[A-Z]\w*(?:::\w+)*)/.freeze

        module_function

        def call(_failure, text)
          undefined_method(text) || uninitialized_constant(text)
        end

        def undefined_method(text)
          match = UNDEFINED_METHOD.match(text)
          return nil unless match

          name = match[:name]
          receiver = receiver_name(match[:receiver])
          Symptom.new(kind: :undefined_method, key: "undefined-method:#{name}:#{receiver}",
                      label: "undefined method `#{name}` on #{receiver}",
                      detail: "undefined `#{name}` for #{receiver}")
        end

        def uninitialized_constant(text)
          match = UNINITIALIZED.match(text)
          return nil unless match

          constant = match[:constant]
          Symptom.new(kind: :missing_constant, key: "missing-constant:#{constant}",
                      label: "uninitialized constant `#{constant}`", detail: "uninitialized #{constant}")
        end

        # `nil:NilClass`, `#<User:0x00007f9a>` and `an instance of User` all
        # name a class; use it, so two receivers of the same class cluster.
        def receiver_name(raw)
          text = raw.to_s
          return "nil" if text.start_with?("nil")
          return ::Regexp.last_match(1) if text =~ /\A#<([A-Z]\w*(?:::\w+)*)/

          text.split(":").first.to_s
        end
      end
    end
  end
end
