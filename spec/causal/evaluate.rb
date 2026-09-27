# frozen_string_literal: true

# Prints the causal-analysis evaluation: every corpus scenario run as a real
# `rspec` process, scored against its ground truth and against what the
# existing layers already say.
#
#   bundle exec ruby spec/causal/evaluate.rb            # table
#   bundle exec ruby spec/causal/evaluate.rb --verbose  # plus terminal output

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require "rspec/core"
require_relative "corpus"
require_relative "scenarios"
require_relative "dogfood"

Encoding.default_external = Encoding::UTF_8
verbose = ARGV.include?("--verbose")
totals = Hash.new(0)
rows = (CausalScenarios.all + CausalDogfood.all).map do |scenario|
  outcome = CausalCorpus.run(scenario)
  score = CausalCorpus.score(outcome)
  if verbose
    puts "\n### #{scenario[:name]}"
    lines = CausalCorpus.relationship_lines(outcome)
    puts(lines.empty? ? "(no relationship output: nothing beyond the signatures)" : lines)
  end
  %i[truth_pairs causal_groups impure_causal_groups merged_independents independents failures scope_groups
     impure_scope_groups].each do |key|
    totals[key] += score[key]
  end
  %i[signature all_layers new].each do |layer|
    %i[predicted correct wrong].each { |key| totals[:"#{layer}_#{key}"] += score[layer][key] }
    totals[:"#{layer}_solvable_found"] += score[layer][:found] if scenario[:solvable]
  end
  totals[:solvable_truth_pairs] += score[:truth_pairs] if scenario[:solvable]
  totals[:unaccounted] += 1 unless score[:accounted]
  [scenario, score]
end

def ratio(numerator, denominator)
  denominator.zero? ? "  n/a" : format("%5.2f", numerator.to_f / denominator)
end

puts "\n#{"scenario".ljust(46)} fail true  sig(r) all(r) new(r)  causal impure scope acct"
rows.each do |scenario, score|
  recall = ->(layer) { ratio(score[layer][:correct], score[:truth_pairs]) }
  puts "#{scenario[:name][0, 45].ljust(46)} #{score[:failures].to_s.rjust(4)} #{score[:truth_pairs].to_s.rjust(4)}  " \
       "#{recall.call(:signature)}  #{recall.call(:all_layers)}  #{recall.call(:new)}  " \
       "#{score[:causal_groups].to_s.rjust(6)} #{score[:impure_causal_groups].to_s.rjust(6)} " \
       "#{score[:scope_groups].to_s.rjust(5)} #{score[:accounted] ? " yes" : "  NO"}"
end

puts "\nPairwise \"same cause\" relation over #{totals[:failures]} failures (#{totals[:truth_pairs]} true pairs)"
%i[signature all_layers new].each do |layer|
  puts "  #{layer.to_s.ljust(11)} precision #{ratio(totals[:"#{layer}_correct"], totals[:"#{layer}_predicted"])}  " \
       "recall #{ratio(totals[:"#{layer}_correct"], totals[:truth_pairs])}  " \
       "solvable recall #{ratio(totals[:"#{layer}_solvable_found"], totals[:solvable_truth_pairs])}  " \
       "wrong pairs #{totals[:"#{layer}_wrong"]}"
end
puts "  causal groups #{totals[:causal_groups]}, impure #{totals[:impure_causal_groups]}; " \
     "independent failures #{totals[:independents]}, merged into a causal group #{totals[:merged_independents]}; " \
     "scenarios not fully accounted for #{totals[:unaccounted]}"
puts "  scope groups #{totals[:scope_groups]}, of which contain more than one true cause " \
     "#{totals[:impure_scope_groups]} (scope claims concentration, not a shared cause)"
