# frozen_string_literal: true

# EXPERIMENTAL -- out-of-sample validation (docs/research/green-suite-signal-validation.md).
#
#   ruby research/green_signal/validation/summary.rb
#
# Rebuilds the per-app, per-rule and model-filter tables from the manual
# classification in classifications.json: one entry per shown (example, rule)
# finding of the frozen v2.1 rules, with its class and the frozen judge's
# verdict (nil = not judged; see the report for the sampling).
require "json"

PASSING = { "C" => 1737, "D" => 1035, "E" => 55 }.freeze
RANK = ["VERIFIED", "PROBABLE", "INTERESTING", "INTENTIONAL", "FALSE POSITIVE"].freeze
KEPT = %w[SUSPICIOUS UNCLEAR].freeze

data = JSON.parse(File.read(File.join(__dir__, "classifications.json")))
rows = data.flat_map { |app, list| list.map { |finding| finding.merge("app" => app) } }

def count(list, klass)
  list.count { |finding| finding["class"] == klass }
end

puts "## Per rule (one row per shown (example, rule) finding)"
puts
puts "| rule | shown | judged | kept by model | verified | interesting | intentional | false positive |"
puts "|---|---:|---:|---:|---:|---:|---:|---:|"
rows.group_by { |finding| finding["rule"] }.sort.each do |rule, list|
  judged = list.count { |finding| finding["model"] }
  kept = list.count { |finding| KEPT.include?(finding["model"]) }
  cells = [list.size, judged, kept, count(list, "VERIFIED"), count(list, "INTERESTING"),
           count(list, "INTENTIONAL"), count(list, "FALSE POSITIVE")]
  puts "| #{rule} | #{cells.join(" | ")} |"
end

# An example's class is the best class among its findings; its model verdict
# is the judge's verdict on the example.
examples = rows.group_by { |finding| [finding["app"], finding["id"]] }.map do |(app, _id), list|
  { "app" => app, "class" => list.map { |f| f["class"] }.min_by { |c| RANK.index(c) },
    "model" => list.map { |f| f["model"] }.compact.first }
end

puts
puts "## Model filter (example level, judged examples only)"
puts
puts "| class | judged | kept (SUSPICIOUS/UNCLEAR) | suppressed (CONSISTENT) |"
puts "|---|---:|---:|---:|"
RANK.each do |klass|
  judged = examples.select { |e| e["class"] == klass && e["model"] }
  next if judged.empty?

  kept = judged.count { |e| KEPT.include?(e["model"]) }
  puts "| #{klass} | #{judged.size} | #{kept} | #{judged.size - kept} |"
end

puts
puts "## Per app, shown examples per 1,000 passing"
puts
puts "| app | passing | shown before model | per 1,000 | kept after model | per 1,000 | verified |"
puts "|---|---:|---:|---:|---:|---:|---:|"
PASSING.each do |app, passing|
  list = examples.select { |e| e["app"] == app }
  # Unjudged examples are the unsampled remainder of a group whose sample was
  # suppressed in full; they are counted as suppressed (see the report).
  kept = list.count { |e| KEPT.include?(e["model"]) }
  verified = list.count { |e| e["class"] == "VERIFIED" }
  puts format("| %s | %d | %d | %.1f | %d | %.1f | %d |", app, passing, list.size, 1000.0 * list.size / passing,
              kept, 1000.0 * kept / passing, verified)
end
total = PASSING.values.sum
kept_total = examples.count { |e| KEPT.include?(e["model"]) }
puts format("| all | %d | %d | %.1f | %d | %.1f | %d |", total, examples.size, 1000.0 * examples.size / total,
            kept_total, 1000.0 * kept_total / total, examples.count { |e| e["class"] == "VERIFIED" })
