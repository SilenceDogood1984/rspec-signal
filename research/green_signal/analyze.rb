# frozen_string_literal: true

# EXPERIMENTAL -- research spike.
#
#   ruby research/green_signal/analyze.rb FACTS.jsonl [--root APP_ROOT] [--truth TRUTH.rb]
#        [--json FINDINGS.json] [--suppressed] [--low] [--quiet] [--rules v1|v2]
#
# Reads observer facts, applies rules.rb, prints "PASS -- but:" blocks for
# findings at MEDIUM or above, then summary tables. With --truth, scores the
# findings against hand-written ground truth.
require "json"
require "optparse"
require_relative "rules"
require_relative "rules_v1"

options = { root: nil, truth: nil, json: nil, suppressed: false, low: false, quiet: false, rules: "v2" }
OptionParser.new do |opts|
  opts.on("--root DIR") { |value| options[:root] = value }
  opts.on("--truth FILE") { |value| options[:truth] = value }
  opts.on("--json FILE") { |value| options[:json] = value }
  opts.on("--suppressed") { options[:suppressed] = true }
  opts.on("--low") { options[:low] = true }
  opts.on("--quiet") { options[:quiet] = true }
  opts.on("--rules VERSION", %w[v1 v2]) { |value| options[:rules] = value }
end.parse!

facts = ARGV.flat_map { |path| File.foreach(path).map { |line| JSON.parse(line) } }
rules = (options[:rules] == "v1" ? GreenSignalV1::Rules : GreenSignal::Rules).new(root: options[:root])
by_example = facts.to_h { |record| [record["id"], rules.call(record)] }
findings = by_example.values.flatten

def block(record, findings)
  lines = ["PASS -- but: #{record["full_description"]}  (#{record["location"]})"]
  findings.each do |finding|
    label = finding.suppressed ? "suppressed: #{finding.suppressed}" : finding.confidence
    lines << "  [#{label}] #{finding.rule}#{"  #{finding.request}" if finding.request}"
    finding.evidence.each { |line| lines << "      #{line}" }
    lines << "      why: #{finding.why}"
  end
  lines << "      asserted: #{findings.first.example["asserted"]}"
  lines.join("\n")
end

unless options[:quiet]
  facts.each do |record|
    list = by_example[record["id"]].select do |finding|
      finding.shown? || (options[:suppressed] && finding.suppressed) ||
        (options[:low] && finding.confidence == "LOW" && !finding.suppressed)
    end
    next if list.empty?

    puts block(record, list)
    puts
  end
end

passed = facts.count { |record| record["status"] == "passed" }
shown = findings.select(&:shown?)
low = findings.select { |finding| finding.confidence == "LOW" && !finding.suppressed }
suppressed = findings.select(&:suppressed)
flagged = by_example.count { |_, list| list.any?(&:shown?) }

puts "## Summary"
puts
puts "| | count |"
puts "|---|---:|"
puts "| examples observed | #{facts.size} |"
puts "| passed | #{passed} |"
puts "| passed examples with a shown finding (MEDIUM+) | #{flagged} (#{passed.zero? ? 0 : (100.0 * flagged / passed).round(1)}%) |"
puts "| shown findings (MEDIUM+) | #{shown.size} |"
puts "| LOW hints (not shown) | #{low.size} |"
puts "| suppressed by assertion context | #{suppressed.size} |"
puts
puts "| rule | HIGH | MEDIUM | LOW | suppressed |"
puts "|---|---:|---:|---:|---:|"
findings.group_by(&:rule).sort.each do |rule, list|
  active = list.reject(&:suppressed)
  counts = %w[HIGH MEDIUM LOW].map { |level| active.count { |finding| finding.confidence == level } }
  puts "| #{rule} | #{counts.join(" | ")} | #{list.count(&:suppressed)} |"
end
puts

if options[:truth]
  load options[:truth]
  truth = GreenSignalTruth::EXAMPLES
  rows = facts.filter_map do |record|
    expected = truth[record["full_description"]] or next
    list = by_example[record["id"]]
    shown_rules = list.select(&:shown?).map(&:rule).uniq
    low_rules = list.select { |finding| finding.confidence == "LOW" && !finding.suppressed }.map(&:rule).uniq
    suppressed_rules = list.select(&:suppressed).map(&:rule).uniq
    hit = (shown_rules & Array(expected[:expect])).any?
    [record["full_description"], expected, shown_rules, low_rules, suppressed_rules, hit]
  end
  missing = truth.keys - facts.map { |record| record["full_description"] }
  warn "truth entries with no facts: #{missing.inspect}" unless missing.empty?

  puts "## Scoring against ground truth"
  puts
  puts "| case | kind | shown (MEDIUM+) | LOW hints | suppressed | verdict |"
  puts "|---|---|---|---|---|---|"
  rows.sort_by { |_, expected, *| [%i[bad control clean].index(expected[:kind]), expected[:case].to_s] }.each do |name, expected, shown_rules, low_rules, suppressed_rules, hit|
    verdict =
      case expected[:kind]
      when :bad
        if hit then "DETECTED"
        elsif shown_rules.any? then "detected (other rule)"
        elsif (low_rules & Array(expected[:expect])).any? then "LOW hint only"
        else "MISSED"
        end
      else shown_rules.empty? ? "quiet" : "FALSE POSITIVE"
      end
    label = expected[:case] || name
    cells = [shown_rules, low_rules, suppressed_rules].map { |list| list.empty? ? "-" : list.join(", ") }
    puts "| #{label} | #{expected[:kind]} | #{cells.join(" | ")} | #{verdict} |"
  end
  puts
  %i[bad control clean].each do |kind|
    subset = rows.select { |_, expected, *| expected[:kind] == kind }
    next if subset.empty?

    if kind == :bad
      detected = subset.count { |*, shown_rules, _l, _s, _h| shown_rules.any? }
      expected_hit = subset.count { |*, hit| hit }
      puts "bad: #{detected}/#{subset.size} flagged at MEDIUM+, #{expected_hit}/#{subset.size} by the expected rule"
    else
      noisy = subset.count { |_, _, shown_rules, *| shown_rules.any? }
      puts "#{kind}: #{noisy}/#{subset.size} with a shown finding (false positives)"
    end
  end
end

File.write(options[:json], JSON.pretty_generate(findings.map(&:to_h))) if options[:json]
