# frozen_string_literal: true

require "digest"
require "json"

module RSpec
  module Signal
    # Identity for what the user asked RSpec to run, rather than the examples
    # that happened to exist. This keeps two full-suite runs comparable after
    # tests are added or removed while separating paths, locations and filters.
    class Selection
      ENV_KEY = "RSPEC_SIGNAL_SELECTION"
      VALUE_OPTIONS = %w[--require -r --format -f --out -o --order --seed --color-mode
                         --failure-exit-code --error-exit-code --drb-port --options -I
                         -n --count --type --group-by --only-group].freeze
      FILTER_OPTIONS = { "--tag" => "tag", "-t" => "tag", "--example" => "example",
                         "-e" => "example", "--pattern" => "pattern",
                         "-P" => "pattern", "--exclude-pattern" => "exclude_pattern" }.freeze
      FILTER_FLAGS = %w[--only-failures --next-failure].freeze

      attr_reader :digest, :mode, :paths, :filters

      def self.from_rspec(arguments = ARGV, environment = ENV)
        encoded = environment[ENV_KEY]
        return from_h(JSON.parse(encoded)) unless encoded.to_s.empty?

        from_arguments(arguments)
      rescue StandardError
        nil
      end

      def self.from_arguments(arguments)
        paths, filters = parse_arguments(Array(arguments))
        new(paths: paths.empty? ? ["spec"] : paths, filters: filters)
      end

      def self.from_h(value)
        return nil unless value.is_a?(Hash) && value["digest"] && value["mode"]

        new(paths: value["paths"], filters: value["filters"], digest: value["digest"], mode: value["mode"])
      end

      def self.parse_arguments(arguments)
        paths = []
        filters = Hash.new { |hash, key| hash[key] = [] }
        index = 0
        while index < arguments.length
          argument = arguments[index]
          consumed = capture_argument(argument, arguments[index + 1], paths, filters)
          index += consumed + 1
        end
        [paths, filters]
      end
      private_class_method :parse_arguments

      def self.capture_argument(argument, following, paths, filters)
        return capture_filter(argument, following, filters) if FILTER_OPTIONS.key?(argument)

        equals_filter = FILTER_OPTIONS.keys.any? { |option| argument.start_with?("#{option}=") }
        return capture_equals_filter(argument, filters) if equals_filter

        short_filter = FILTER_OPTIONS.find { |option, _| option.length == 2 && argument.start_with?(option) }
        return capture_short_filter(argument, short_filter, filters) if short_filter

        if FILTER_FLAGS.include?(argument)
          filters["flag"] << argument
          return 0
        end
        return 1 if VALUE_OPTIONS.include?(argument)
        return 0 if argument.start_with?("-")

        paths << argument
        0
      end
      private_class_method :capture_argument

      def self.capture_short_filter(argument, option, filters)
        name, filter_name = option
        filters[filter_name] << argument.delete_prefix(name)
        0
      end
      private_class_method :capture_short_filter

      def self.capture_filter(argument, value, filters)
        filters[FILTER_OPTIONS.fetch(argument)] << value.to_s
        1
      end
      private_class_method :capture_filter

      def self.capture_equals_filter(argument, filters)
        option, value = argument.split("=", 2)
        filters[FILTER_OPTIONS.fetch(option)] << value
        0
      end
      private_class_method :capture_equals_filter

      def initialize(paths:, filters: {}, digest: nil, mode: nil)
        @paths = Array(paths).map(&:to_s).uniq.sort.freeze
        @filters = normalize_filters(filters).freeze
        @mode = (mode || infer_mode).to_s
        @digest = digest || Digest::SHA256.hexdigest(JSON.generate(identity_h))
      end

      def equivalent?(other)
        other && digest == other.digest
      end

      def to_h
        identity_h.merge("digest" => digest)
      end

      private

      def normalize_filters(values)
        (values || {}).each_with_object({}) do |(name, entries), result|
          normalized = Array(entries).map(&:to_s).uniq.sort
          result[name.to_s] = normalized unless normalized.empty?
        end.sort.to_h
      end

      def infer_mode
        paths == ["spec"] && filters.empty? ? "full_suite" : "targeted"
      end

      def identity_h
        { "mode" => mode, "paths" => paths, "filters" => filters }
      end
    end
  end
end
