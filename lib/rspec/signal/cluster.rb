# frozen_string_literal: true

module RSpec
  module Signal
    # A set of failures that share one diagnostic symptom.
    #
    # Weaker than a {Group} on purpose. A group asserts that its failures are
    # the same failure; a cluster asserts only that they share a strong symptom
    # and are worth looking at together. The report says so in those words, so
    # nothing downstream mistakes one for the other.
    class Cluster
      Member = Struct.new(:failure, :detail)

      attr_reader :symptom, :first_seen

      def initialize(symptom:, first_seen:)
        @symptom = symptom
        @first_seen = first_seen
        @members = []
      end

      def add(failure, symptom)
        @members << Member.new(failure, symptom.detail)
        self
      end

      def failures
        @members.map(&:failure)
      end

      def size
        @members.size
      end

      def kind
        @symptom.kind
      end

      def key
        @symptom.key
      end

      def label
        @symptom.label
      end

      # The distinct wordings the symptom took, most common first, ties broken
      # by the order they were seen so the list is stable.
      def symptom_counts
        @symptom_counts ||= begin
          counts = @members.each_with_object(Hash.new(0)) { |member, tally| tally[member.detail] += 1 }
          seen = counts.keys.each_with_index.to_h
          counts.sort_by { |detail, count| [-count, seen[detail]] }.to_h
        end
      end

      # The exact signatures this cluster spans. More than one is what makes a
      # cluster worth printing at all.
      def signatures
        @signatures ||= failures.map { |failure| failure.fingerprint.digest }.uniq
      end

      def signature_count
        signatures.size
      end

      def spec_files
        @spec_files ||= failures.map { |failure| failure.spec_location.sub(/:\d+\z/, "") }.uniq
      end

      def to_h
        {
          kind: kind,
          key: key,
          label: label,
          count: size,
          signatures: signatures,
          symptoms: symptom_counts,
          specs: spec_files
        }
      end
    end
  end
end
