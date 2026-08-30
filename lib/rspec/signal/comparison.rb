# frozen_string_literal: true

module RSpec
  module Signal
    # What changed between the previous run and this one.
    #
    # Four buckets, from two keys per signature:
    #
    #   digest  the full fingerprint (exception, message, culprit, app context)
    #   loose   exception and message only -- independent of line numbers
    #
    #   persistent  paired entries with the same digest
    #   resolved    unpaired old entries after loose matching
    #   new         unpaired new entries after loose matching
    #   changed     remaining old/new entries paired by loose key
    #
    # The fourth bucket is what makes the other three trustworthy. Editing the
    # file that raises shifts every culprit line, which without it turns every
    # persistent failure into a spurious resolved/new pair -- and an agent that
    # reads "28 resolved" when it resolved nothing is worse off than one told
    # nothing at all.
    class Comparison
      Change = Struct.new(:digest, :loose, :exception, :count, keyword_init: true) do # rubocop:disable Lint/StructNewOverride
        def to_h
          { signature: digest, exception: exception, examples: count }.compact
        end
      end

      attr_reader :previous_run_id, :previous_at, :previous_failures, :failure_count,
                  :persistent, :resolved, :new_signatures, :changed

      def initialize(previous:, current:)
        @previous_run_id = previous["run_id"]
        @previous_at = previous["at"]
        @previous_failures = previous.fetch("failures", 0)
        @failure_count = current.fetch("failures", 0)
        classify(entries(previous), entries(current))
      end

      def any?
        [persistent, resolved, new_signatures, changed].any? { |bucket| !bucket.empty? }
      end

      # Reads as a sentence and fits on one terminal line.
      def headline
        parts = []
        parts << "#{resolved.size} resolved" unless resolved.empty?
        parts << "#{new_signatures.size} new" unless new_signatures.empty?
        parts << "#{persistent.size} persistent" unless persistent.empty?
        parts << "#{changed.size} changed" unless changed.empty?
        return nil if parts.empty?

        "Signatures: #{parts.join(", ")}; failures: #{previous_failures} -> #{failure_count}"
      end

      def to_h
        {
          previous_run_id: previous_run_id,
          previous_at: previous_at,
          previous_failures: previous_failures,
          resolved: resolved.map(&:to_h),
          new: new_signatures.map(&:to_h),
          persistent: persistent.map(&:to_h),
          changed: changed.map(&:to_h)
        }.compact
      end

      private

      def entries(run)
        Array(run["signatures"]).map do |item|
          Change.new(digest: item["digest"], loose: item["loose"],
                     exception: item["exception"], count: item["count"])
        end
      end

      # Pairing is cardinality-aware so signatures that share a loose key do
      # not hide resolved or new failures. Hash-backed queues keep the work
      # linear even for suites with many signatures.
      def classify(before, after)
        @persistent, gone, arrived = pair(before, after, :digest)
        @changed, @resolved, @new_signatures = pair(gone, arrived, :loose)
      end

      def pair(before, after, attribute)
        available = before.group_by { |entry| entry.public_send(attribute) }
        matched_before = {}.compare_by_identity

        matched_after, unmatched_after = after.partition do |entry|
          match = available[entry.public_send(attribute)]&.shift
          matched_before[match] = true if match
          match
        end

        unmatched_before = before.reject { |entry| matched_before.key?(entry) }

        [matched_after, unmatched_before, unmatched_after]
      end
    end
  end
end
