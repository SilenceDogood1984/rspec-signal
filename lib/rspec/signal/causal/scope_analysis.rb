# frozen_string_literal: true

module RSpec
  module Signal
    module Causal
      # Failure concentration: where the failures that nothing structural
      # related are unusually dense. Evidence about *where*, never *why*, so it
      # is kept apart from the causal analysis and never carries a confidence:
      # "9 of 11 examples in this file failed" is exactly what it claims.
      #
      # It sees only what the causal pass left unrelated, and only the census.
      class ScopeAnalysis
        # The only thresholds in the relationship analysis. Internal constants
        # while the layer is experimental, never configuration.
        MIN_FAILURES = 3
        INSIDE = Rational(2, 3)   # at least this share of the scope failed
        OUTSIDE = Rational(1, 20) # and less than this share of the rest did
        DIMENSIONS = %w[file type].freeze

        # @param residual [Array<Unit>] units no causal relation claimed
        # @param census [Census, nil]
        # @return [Array(Array<Relation>, Array<Unit>)] scope groups, and what is left
        def self.call(residual, census)
          return [[], residual] if census.nil? || census.empty?

          new(census).call(residual)
        end

        def initialize(census)
          @census = census
        end

        # Most specific scope first, until none qualifies.
        def call(residual)
          scoped = []
          loop do
            best = candidates(residual).min_by { |candidate| candidate.values_at(:run, :order, :value) }
            break unless best

            scoped << Relation.new(kind: :scope, units: best[:units], scope: best[:stats])
            residual -= best[:units]
          end
          [scoped, residual]
        end

        private

        def candidates(residual)
          examples = residual.reject(&:outside)
          DIMENSIONS.each_with_index.flat_map do |dimension, order|
            @census.values(dimension).filter_map do |value|
              inside = examples.select { |unit| within?(unit, dimension, value) }
              stats = concentration(dimension, value)
              next unless stats && inside.size >= 2 && inside.sum(&:size) >= MIN_FAILURES

              { units: inside, stats: stats, run: stats["examples"], order: order, value: value }
            end
          end
        end

        def within?(unit, dimension, value)
          evidence = unit.evidence
          evidence.size == unit.size && evidence.all? { |item| item.public_send(dimension).to_s == value }
        end

        def concentration(dimension, value)
          run, failed = @census.count(dimension, value)
          elsewhere_run = @census.total - run
          elsewhere_failed = @census.failed - failed
          return nil if run.zero? || elsewhere_run < run
          return nil if Rational(failed, run) < INSIDE
          return nil unless Rational(elsewhere_failed, elsewhere_run) < OUTSIDE

          { "dimension" => dimension, "value" => value, "failed" => failed, "examples" => run,
            "failed_elsewhere" => elsewhere_failed, "examples_elsewhere" => elsewhere_run }
        end
      end
    end
  end
end
