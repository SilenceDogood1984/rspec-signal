# frozen_string_literal: true

module RSpec
  module Signal
    # Builds the related-failure clusters, and refuses to build most of them.
    #
    # Two rules do the work:
    #
    #   * a cluster needs at least two failures, and
    #   * a cluster needs at least two *exact signatures*.
    #
    # The second is the important one. If every failure sharing a symptom is
    # already the same signature, the signature section says it better and
    # saying it twice is noise. A cluster therefore only ever appears when it
    # tells the reader something the authoritative grouping could not: that
    # failures RSpec, and rspec-signal, consider distinct nevertheless share a
    # symptom.
    #
    # Ordering is deterministic -- biggest first, then most signatures spanned,
    # then run order -- so two runs of the same suite produce the same report.
    module Clusterer
      MIN_FAILURES = 2
      MIN_SIGNATURES = 2

      module_function

      # @param failures [Array<Failure>]
      # @return [Array<Cluster>]
      def call(failures)
        clusters = {}

        failures.each_with_index do |failure, index|
          symptom = failure.symptom
          next unless symptom

          clusters[symptom.key] ||= Cluster.new(symptom: symptom, first_seen: index)
          clusters[symptom.key].add(failure, symptom)
        end

        clusters.values.select { |cluster| worth_reporting?(cluster) }
                .sort_by { |cluster| [-cluster.size, -cluster.signature_count, cluster.first_seen] }
      end

      def worth_reporting?(cluster)
        cluster.size >= MIN_FAILURES && cluster.signature_count >= MIN_SIGNATURES
      end
    end
  end
end
