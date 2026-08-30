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
    #   persistent  digest in both runs
    #   resolved    digest gone, and its loose key is gone too
    #   new         digest appeared, and its loose key is new too
    #   changed     digest changed but the loose key survived
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
        parts << "#{persistent.size} still failing" unless persistent.empty?
        parts << "#{changed.size} changed signature" unless changed.empty?
        return nil if parts.empty?

        "#{parts.join(", ")} (#{previous_failures} -> #{failure_count} failures)"
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

      # Membership is looked up rather than scanned: a suite with a thousand
      # signatures would otherwise compare each against every other.
      def classify(before, after)
        before_digests = index(before, :digest)
        after_digests = index(after, :digest)
        before_loose = index(before, :loose)
        after_loose = index(after, :loose)

        @persistent = after.select { |entry| before_digests.key?(entry.digest) }
        gone = before.reject { |entry| after_digests.key?(entry.digest) }
        arrived = after.reject { |entry| before_digests.key?(entry.digest) }

        @changed = arrived.select { |entry| before_loose.key?(entry.loose) }
        @new_signatures = arrived - @changed
        @resolved = gone.reject { |entry| after_loose.key?(entry.loose) }
      end

      def index(entries, attribute)
        entries.to_h { |entry| [entry.public_send(attribute), true] }
      end
    end
  end
end
