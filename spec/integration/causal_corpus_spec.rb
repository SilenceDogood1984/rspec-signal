# frozen_string_literal: true

require_relative "../causal/corpus"
require_relative "../causal/scenarios"

# The causal-analysis evaluation corpus as a test. Every scenario is a real
# `rspec` run with known causes; see spec/causal/scenarios.rb, and
# `bundle exec ruby spec/causal/evaluate.rb --verbose` for the full table.
#
# The bar, from docs/design/causal-failure-intelligence.md:
#   * no causal group ever contains two different true causes
#   * no genuinely independent failure is ever merged into a causal group
#   * every failure is accounted for
#   * on structurally solvable scenarios, recall of at least 0.8 and a clear
#     improvement over exact signatures alone
RSpec.describe "causal analysis corpus", :integration do
  CausalScenarios.all.each do |scenario|
    describe scenario[:name] do
      let(:outcome) { CausalCorpus.cached(scenario) }
      let(:score) { CausalCorpus.score(outcome) }

      def keys_labelled(label)
        outcome.keys.select { |key| outcome.label(key) == label }
      end

      it "never merges different causes into one causal group" do
        expect(score[:impure_causal_groups]).to eq(0)
        expect(score[:merged_independents]).to eq(0)
      end

      it "accounts for every failure" do
        expect(score[:accounted]).to be(true)
      end

      scenario.fetch(:expect, {}).each do |label, verdict|
        it "reaches the expected verdict for #{label}: #{verdict}" do
          keys = keys_labelled(label)
          case verdict
          when "causal" then expect(outcome.groups("causal")).to include(a_collection_including(*keys))
          when "scope" then expect(outcome.groups("scope")).to include(a_collection_including(*keys))
          when "unlinked" then expect(outcome.groups("causal").flatten & keys).to be_empty
          end
        end
      end

      scenario.fetch(:evidence, {}).each do |label, types|
        it "backs #{label} with #{types.join(" and ")}" do
          group = outcome.analysis.fetch("groups").find do |item|
            (item["kind"] == "causal" && item["members"].any? do |member|
              (member["ids"] & keys_labelled(label)).any?
            end) ||
              (item["kind"] == "causal" && keys_labelled(label).all? { |key| key.start_with?("load:") })
          end

          expect(group&.fetch("evidence")&.map { |item| item["type"] }).to include(*types)
        end
      end

      it "produces exactly the expected hints" do
        expect(outcome.analysis.fetch("hints").map { |hint| hint["type"] }.uniq)
          .to match_array(scenario.fetch(:hints, []))
      end
    end
  end

  describe "across the corpus" do
    let(:scores) do
      CausalScenarios.all.map do |scenario|
        [scenario, CausalCorpus.score(CausalCorpus.cached(scenario))]
      end
    end

    def solvable_recall(scores, layer)
      solvable = scores.select { |scenario, _| scenario[:solvable] }
      found = solvable.sum { |_, score| score[layer][:correct] }
      found.to_f / solvable.sum { |_, score| score[:truth_pairs] }
    end

    it "reaches the recall target on structurally solvable scenarios" do
      expect(solvable_recall(scores, :new)).to be >= 0.8
    end

    it "materially improves on exact signatures alone" do
      expect(solvable_recall(scores, :new) - solvable_recall(scores, :signature)).to be >= 0.2
    end

    it "adds no wrong pair beyond those the exact signatures already make" do
      wrong = ->(layer) { scores.sum { |_, score| score[layer][:wrong] } }

      expect(wrong.call(:new)).to eq(wrong.call(:signature))
    end
  end

  # The parent of a parallel run must reach the same conclusions from the
  # evidence its workers serialized.
  describe "under parallel_tests" do
    it "reaches the same groups as a serial run" do
      scenario = CausalScenarios.mixed_run
      serial = CausalCorpus.cached(scenario)
      parallel = CausalCorpus.cached(scenario, parallel: true)
      shape = ->(outcome) { outcome.analysis.fetch("groups").map { |group| group.values_at("kind", "failures") }.sort }

      expect(shape.call(parallel)).to eq(shape.call(serial))
      expect(parallel.analysis.fetch("accounted")).to eq(serial.analysis.fetch("accounted"))
    end
  end
end
