# frozen_string_literal: true

module RSpec
  module Signal
    # Collapses failures that share a fingerprint into {Group}s.
    #
    # Ordering is deterministic: biggest group first, ties broken by the order
    # the failures were seen, so two runs of the same suite produce byte-identical
    # reports.
    module Grouper
      module_function

      # @param failures [Array<Failure>]
      # @return [Array<Group>]
      def call(failures)
        groups = {}

        failures.each_with_index do |failure, index|
          key = failure.fingerprint.digest
          groups[key] ||= Group.new(fingerprint: failure.fingerprint, first_seen: index)
          groups[key] << failure
        end

        groups.values.sort_by { |group| [-group.size, group.first_seen] }
      end
    end
  end
end
