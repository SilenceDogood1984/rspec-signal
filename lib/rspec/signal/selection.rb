# frozen_string_literal: true

require "digest"

module RSpec
  module Signal
    # Stable identity for the examples RSpec selected after applying paths,
    # locations, tags, and other filters. Invocation syntax is deliberately not
    # part of the identity: two commands are comparable when they select the
    # same examples, regardless of argument order or how that set was named.
    class Selection
      attr_reader :example_ids, :files

      def self.from_rspec(world = ::RSpec.world)
        examples = world.filtered_examples.values.flatten
        new(examples.map(&:id))
      rescue StandardError
        nil
      end

      def self.from_h(value)
        return nil unless value.is_a?(Hash) && value["digest"] && value["count"]

        new([], digest: value["digest"], count: value["count"], files: value["files"])
      end

      def self.merge(selections)
        values = selections.compact
        return nil if values.empty?

        new(values.flat_map(&:example_ids))
      end

      def initialize(example_ids, digest: nil, count: nil, files: nil)
        @example_ids = Array(example_ids).map(&:to_s).uniq.sort.freeze
        @files = Array(files || @example_ids.map { |id| id.sub(/\[.*\z/, "") }).uniq.sort.freeze
        @count = count || @example_ids.size
        @digest = digest || Digest::SHA256.hexdigest(@example_ids.join("\0"))
      end

      def equivalent?(other)
        other && digest == other.digest && count == other.count
      end

      def digest
        @digest
      end

      def count
        @count
      end

      def to_h(include_ids: false)
        value = { "digest" => digest, "count" => count, "files" => files }
        include_ids ? value.merge("example_ids" => example_ids) : value
      end
    end
  end
end
