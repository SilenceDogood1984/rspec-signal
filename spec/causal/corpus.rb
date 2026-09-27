# frozen_string_literal: true

require "set"
require_relative "../support/sandbox_project"

# Runs the causal-analysis evaluation corpus: real `rspec` processes over
# throwaway projects whose failures have known causes, scored against that
# ground truth.
#
# Ground truth is written beside each scenario as `example description =>
# cause label` (errors outside examples are `"load:<spec file>"`). Two
# failures share a cause exactly when they share a label. A label used once is
# a genuinely independent failure.
module CausalCorpus
  Outcome = Struct.new(:scenario, :stdout, :json, :keys, :labels, keyword_init: true) do
    def analysis
      json.fetch("analysis", "groups" => [], "accounted" => {})
    end

    def groups(kind)
      analysis.fetch("groups").select { |group| group["kind"] == kind }.map { |group| member_keys(group) }
    end

    def signature_groups
      json.fetch("signatures", []).map { |signature| affected_keys(signature) } +
        json.fetch("outside_examples", []).map { |item| [outside_key(item["rerun"])] }
    end

    # Every existing layer read as a grouping: exact signatures, related
    # clusters and shared code paths, merged transitively. This is the most
    # generous reading of what the product already says.
    def all_layer_groups
      by_digest = json.fetch("signatures", []).to_h { |signature| [signature["signature"], affected_keys(signature)] }
      links = json.fetch("related", []).map { |cluster| cluster["signatures"] } +
              json.fetch("code_paths", []).map { |path| path["signatures"] }
      CausalCorpus.merge(signature_groups + links.map { |digests| digests.flat_map { |d| by_digest.fetch(d, []) } })
    end

    def new_groups
      CausalCorpus.merge(signature_groups + groups("causal"))
    end

    def label(key)
      labels.fetch(key)
    end

    private

    def member_keys(group)
      group.fetch("members").flat_map do |member|
        if member["signature"]
          signature = json.fetch("signatures").find { |item| item["signature"] == member["signature"] }
          affected_keys(signature)
        else
          member.fetch("ids").map { |file| outside_key(file) }
        end
      end
    end

    def affected_keys(signature)
      signature.fetch("affected").map { |item| item.fetch("id") }
    end

    def outside_key(file)
      "load:#{file.to_s.sub(%r{\A\./}, "")}"
    end
  end

  module_function

  # One real run per scenario however many examples inspect it.
  def cached(scenario, parallel: false)
    (@cached ||= {})[[scenario[:name], parallel]] ||= run(scenario, parallel: parallel)
  end

  def run(scenario, parallel: false)
    project = SandboxProject.new
    project.install_spec_helper("RSpec::Signal.configure { |c| c.causal_analysis = true }\n#{scenario.fetch(:helper,
                                                                                                            "")}")
    scenario.fetch(:files).each { |path, contents| project.write(path, contents) }
    run = if parallel
            project.run_signal_parallel(*scenario.fetch(:parallel_args,
                                                        ["spec", "-n",
                                                         "2"]))
          else
            project.run_signal(*scenario.fetch(:args,
                                               []))
          end
    json = project.json
    outcome = Outcome.new(scenario: scenario, stdout: run.stdout.dup.force_encoding(Encoding::UTF_8), json: json)
    resolve_truth(outcome)
  ensure
    project&.cleanup
  end

  # Maps every failing example (by RSpec id) and every load error (by file)
  # to its ground-truth label, and refuses a scenario whose truth does not
  # describe exactly what failed.
  def resolve_truth(outcome)
    truth = outcome.scenario.fetch(:truth)
    keys = {}
    outcome.json.fetch("signatures", []).each do |signature|
      signature.fetch("affected").each { |item| keys[item.fetch("id")] = item.fetch("description") }
    end
    outcome.json.fetch("outside_examples", []).each do |item|
      file = item.fetch("rerun").sub(%r{\A\./}, "")
      keys["load:#{file}"] = "load:#{file}"
    end
    unknown = keys.values - truth.keys
    missing = truth.keys - keys.values
    raise ArgumentError, "#{outcome.scenario[:name]}: unlabelled failures #{unknown}" unless unknown.empty?
    raise ArgumentError, "#{outcome.scenario[:name]}: expected failures did not fail #{missing}" unless missing.empty?

    outcome.keys = keys.keys
    outcome.labels = keys.transform_values { |description| truth.fetch(description) }
    outcome
  end

  # ---- scoring --------------------------------------------------------

  def merge(groups)
    parent = {}
    find = lambda do |key|
      parent[key] ||= key
      parent[key] = find.call(parent[key]) unless parent[key] == key
      parent[key]
    end
    groups.each do |group|
      group.each_cons(2) { |a, b| parent[find.call(a)] = find.call(b) unless find.call(a) == find.call(b) }
      group.each { |key| find.call(key) }
    end
    parent.keys.group_by { |key| find.call(key) }.values
  end

  def pairs(groups)
    groups.each_with_object(Set.new) do |group, set|
      group.uniq.combination(2) { |a, b| set << [a, b].sort }
    end
  end

  def truth_pairs(outcome)
    pairs(outcome.keys.group_by { |key| outcome.label(key) }.values)
  end

  def score(outcome)
    truth = truth_pairs(outcome)
    singletons = outcome.keys.group_by { |key| outcome.label(key) }.values.select { |group| group.size == 1 }.flatten
    causal = outcome.groups("causal")
    impure = causal.reject { |group| group.map { |key| outcome.label(key) }.uniq.size == 1 }
    accounted = outcome.analysis.fetch("accounted", {})
    {
      failures: outcome.keys.size,
      truth_pairs: truth.size,
      signature: pair_stats(pairs(outcome.signature_groups), truth),
      all_layers: pair_stats(pairs(outcome.all_layer_groups), truth),
      new: pair_stats(pairs(outcome.new_groups), truth),
      causal_groups: causal.size,
      impure_causal_groups: impure.size,
      merged_independents: causal.flatten.count { |key| singletons.include?(key) },
      independents: singletons.size,
      scope_groups: outcome.groups("scope").size,
      impure_scope_groups: outcome.groups("scope").count do |group|
        group.map do |key|
          outcome.label(key)
        end.uniq.size > 1
      end,
      accounted: accounted["failures"] == outcome.keys.size && accounted["not_captured"].to_i.zero?
    }
  end

  def pair_stats(predicted, truth)
    hits = (predicted & truth).size
    { predicted: predicted.size, correct: hits, wrong: predicted.size - hits, found: hits }
  end

  # Terminal lines rspec-signal printed about relationships, for the report.
  def relationship_lines(outcome)
    lines = outcome.stdout.lines.map(&:rstrip)
    first = lines.index { |line| line.start_with?("CAUSAL", "SCOPE") }
    last = lines.index { |line| line.include?("failures accounted for") }
    first && last ? lines[first..last] : []
  end
end
