# frozen_string_literal: true

module RSpec
  module Signal
    # The complete, renderer-independent result of a run.
    class Report
      attr_reader :failures, :groups, :clusters, :example_count, :failure_count, :pending_count,
                  :duration, :seed, :seed_used, :environment, :errors_outside_examples

      def initialize(failures:, example_count: 0, failure_count: nil, pending_count: 0,
                     duration: nil, seed: nil, seed_used: false, environment: {},
                     errors_outside_examples: 0, relate_failures: true)
        @failures = failures
        @groups = Grouper.call(failures)
        @clusters = relate_failures ? safely { Clusterer.call(failures) } : []
        @example_count = example_count
        @failure_count = failure_count || failures.size
        @pending_count = pending_count
        @duration = duration
        @seed = seed
        @seed_used = seed_used
        @environment = environment
        @errors_outside_examples = errors_outside_examples
      end

      # Clustering is the newest and least essential stage; a report without it
      # is still worth having, so it is never allowed to take the run down.
      def safely
        yield
      rescue StandardError
        []
      end

      def group_count   = groups.size
      def cluster_count = clusters.size
      def any_failures? = !failures.empty?
      def seed_used? = !!@seed_used

      # Backtrace frames dropped across the whole run. This is the number that
      # makes the reduction visible.
      def omitted_frames
        @omitted_frames ||= failures.sum { |failure| failure.reduced.omitted_count }
      end

      def total_frames
        @total_frames ||= failures.sum { |failure| failure.reduced.total }
      end

      def kept_frames = total_frames - omitted_frames

      def to_h
        {
          schema: 1,
          generated_by: "rspec-signal #{VERSION}",
          summary: {
            examples: example_count,
            failures: failure_count,
            pending: pending_count,
            signatures: group_count,
            related_clusters: cluster_count.positive? ? cluster_count : nil,
            duration_seconds: duration&.round(3),
            seed: seed_used? ? seed : nil,
            errors_outside_examples: errors_outside_examples.positive? ? errors_outside_examples : nil
          }.compact,
          environment: environment,
          backtrace_reduction: { total_frames: total_frames, kept_frames: kept_frames, omitted_frames: omitted_frames },
          signatures: groups.map(&:to_h),
          related: clusters.map(&:to_h)
        }
      end

      # Worker interchange data. Unlike the public report summary this retains
      # every reduced failure so grouping can be repeated across all workers.
      def worker_h
        serialized = failures.map do |failure|
          failure.to_h.merge(fingerprint: failure.fingerprint.to_h, raw: failure.raw)
        end
        to_h.merge(schema: 2, failures: serialized)
      end
    end
  end
end
