# frozen_string_literal: true

module RSpec
  module Signal
    module Causal
      # How many examples ran, and failed, per spec file and per `type:`.
      # Counters only -- no descriptions, no messages.
      #
      # Deliberately not per parallel worker: parallel_tests assigns files to
      # workers by size, so "every failure ran on worker 2" usually means
      # "every failing file was assigned to worker 2".
      #
      # This is the base rate every other signal lacks: "9 failures in one file"
      # means something only next to "11 examples in that file, 0 of 493
      # elsewhere failed".
      class Census
        DIMENSIONS = %w[file type].freeze

        attr_reader :total, :failed

        def initialize
          @total = 0
          @failed = 0
          @counts = DIMENSIONS.to_h { |dimension| [dimension, Hash.new { |hash, key| hash[key] = [0, 0] }] }
        end

        # Called with the notification for every passed and failed example.
        # Pending examples neither passed nor failed, and are left out of both
        # sides. Never raises: counting must not cost a failure its report.
        def record(notification, failed:)
          example = notification.example
          add({ "file" => Capture.file_of(example), "type" => Capture.type_of(example) }, failed: failed)
        rescue StandardError
          nil
        end

        def add(keys, failed:)
          @total += 1
          @failed += 1 if failed
          keys.each { |dimension, value| bump(dimension, value, 1, failed ? 1 : 0) }
          self
        end

        # @return [Array(Integer, Integer)] examples run and failed for one value
        def count(dimension, value)
          @counts.fetch(dimension, {}).fetch(value.to_s, [0, 0])
        end

        def values(dimension)
          @counts.fetch(dimension, {}).keys.sort
        end

        def empty?
          @total.zero?
        end

        def to_h
          { "total" => @total, "failed" => @failed }.merge(@counts.reject { |_, values| values.empty? })
        end

        # Adds one parallel worker's census.
        def merge(data)
          return self unless data.is_a?(Hash)

          run = data.fetch("total", 0).to_i
          failures = data.fetch("failed", 0).to_i
          @total += run
          @failed += failures
          %w[file type].each do |dimension|
            data.fetch(dimension, {}).each { |value, (count, failed)| bump(dimension, value, count.to_i, failed.to_i) }
          end
          self
        end

        private

        def bump(dimension, value, run, failures)
          return if value.nil? || value.to_s.empty? || !@counts.key?(dimension)

          @counts[dimension][value.to_s][0] += run
          @counts[dimension][value.to_s][1] += failures
        end
      end
    end
  end
end
