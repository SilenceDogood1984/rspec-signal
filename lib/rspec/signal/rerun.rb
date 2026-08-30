# frozen_string_literal: true

module RSpec
  module Signal
    # Builds commands that rerun exactly the examples they name.
    #
    # A location (`spec/user_spec.rb:12`) is what a human types, but it selects
    # every example defined on that line -- which for a loop-generated `it` is
    # all of them, and for two failures that share a line is both of them. An
    # agent that reruns a signature and still sees failures cannot then tell
    # whether its fix failed or whether it caught an unrelated example.
    #
    # RSpec's example ids (`./spec/user_spec.rb[1:3]`) are exact, and are what
    # RSpec's own `--only-failures` persistence file records. They contain
    # square brackets, so they must be quoted: bash passes an unmatched glob
    # through unchanged, but zsh fails the command outright.
    module Rerun
      DEFAULT_PREFIX = "bundle exec rspec"

      # Shell-safe without quoting. Deliberately conservative.
      SAFE = %r{\A[A-Za-z0-9_@%+=:,./-]+\z}.freeze

      module_function

      # @param arguments [Array<String>]
      # @return [String] a copy-pasteable command
      def command(arguments, prefix: DEFAULT_PREFIX)
        "#{prefix} #{Array(arguments).map { |argument| quote(argument) }.join(" ")}"
      end

      def quote(argument)
        text = argument.to_s
        return text if SAFE.match?(text)

        "'#{text.gsub("'", "'\\\\''")}'"
      end
    end
  end
end
