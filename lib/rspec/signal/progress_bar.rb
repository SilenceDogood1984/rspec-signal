# frozen_string_literal: true

module RSpec
  module Signal
    # The single line repainted in place while a quiet run is in progress.
    #
    # Quiet mode prints nothing per example, which on a long suite is
    # indistinguishable from a hang. This is the smallest thing that fixes
    # that: bounded, repainted with a carriage return, and only ever drawn to a
    # terminal, so a redirected stream never accumulates control sequences.
    class ProgressBar
      WIDTH = 20

      # @return [ProgressBar, nil] nil whenever a bar would be inappropriate
      def self.for(output, total)
        return nil unless output.respond_to?(:tty?) && output.tty?
        return nil unless total.to_i.positive?

        new(output, total.to_i)
      end

      def initialize(output, total)
        @output = output
        @total = total
        @completed = 0
        render
      end

      def advance
        @completed = [@completed + 1, @total].min
        render
      end

      def finish
        @output.puts
      end

      private

      def render
        percentage = (@completed * 100) / @total
        filled = (@completed * WIDTH) / @total
        bar = ("█" * filled) + ("░" * (WIDTH - filled))
        @output.print "\rsignal [#{bar}] #{percentage}% #{@completed}/#{@total}"
      end
    end
  end
end
