# frozen_string_literal: true

# EXPERIMENTAL -- research spike, Phase 11.
#
#   ruby research/green_signal/llm/packets.rb FACTS.jsonl --root APP_ROOT \
#        [--ids IDS.txt] [--prefix F] > packets.md
#
# Builds one compact, blind evidence packet per example for a model to read:
# description, the example's own source (plus the let/before lines of its
# enclosing groups), the expectations that ran, normalized runtime facts, and
# the deterministic rule output. No application source, no ground truth.
require "json"
require "optparse"
require_relative "../rules"

options = { root: Dir.pwd, ids: nil, prefix: "C", rules: true }
OptionParser.new do |opts|
  opts.on("--root DIR") { |value| options[:root] = value }
  opts.on("--ids FILE") { |value| options[:ids] = File.readlines(value, chomp: true).reject(&:empty?) }
  opts.on("--prefix P") { |value| options[:prefix] = value }
  opts.on("--no-rules", "evidence only: omit the deterministic rule output") { options[:rules] = false }
end.parse!

# The example block, plus the setup statements of the groups that enclose it.
# A forward scan keeps a stack of open blocks, so a sibling group's setup is
# never mistaken for an enclosing one.
module Source
  SETUP = /\A\s*(?:let!?|subject!?|before|include_context|include|def)\b/.freeze
  GROUP = /\A\s*(?:RSpec\.)?(?:describe|context|feature)\b/.freeze
  OPENS = /\bdo\s*(?:\|[^|]*\|)?\s*(?:#.*)?\z/.freeze

  module_function

  def for(root, location)
    file, line = location.split(":")
    lines = File.readlines(File.join(root, file))
    start = line.to_i - 1
    [enclosing(lines, start), statement(lines, start, 40)].reject(&:empty?).join("\n  # ...\n")
  rescue StandardError
    "(source unavailable)"
  end

  # One statement: a single line, or a do...end block up to its matching end.
  def statement(lines, start, limit = 8)
    text = lines[start]
    method = text =~ /\A\s*def\s/ && text !~ /\bend\s*\z/
    return text.rstrip unless method || OPENS.match?(text.rstrip)

    limit = 15 if method
    indent = text[/\A */].size
    out = [text]
    lines[(start + 1)..].each do |following|
      out << following
      break if following =~ /\A {#{indent}}end\b/ || out.size >= limit
    end
    out.join.rstrip
  end

  def enclosing(lines, stop)
    stack = []
    lines.first(stop).each_with_index do |text, index|
      depth = text[/\A */].size
      stripped = text.rstrip
      if stripped =~ /\A\s*end\b/ && stack.any? && stack.last[:indent] == depth
        stack.pop
        next
      end
      group = stack.reverse.find { |frame| frame[:group] }
      if SETUP.match?(text) && group && stack.last.equal?(group)
        group[:setups] << statement(lines, index)
      end
      next unless OPENS.match?(stripped) || (stripped =~ /\A\s*def\s/ && stripped !~ /\bend\z/)

      stack << { indent: depth, group: GROUP.match?(text), header: stripped, setups: [] }
    end
    stack.select { |frame| frame[:group] }.flat_map { |frame| [frame[:header], *frame[:setups]] }.join("\n")
  end
end

def request_line(request, issued)
  origin = request["issued_index"] && issued[request["issued_index"]]
  parts = ["#{request["method"]} #{request["path"]} -> #{request["controller"]}##{request["action"]}"]
  parts << "(issued from #{origin["helper_site"] ? "a spec helper" : "the example"}, #{origin["phase"]})" if origin
  parts << "halted by before_action :#{request["halted_by"]} (action did not run)" if request["halted_by"]
  parts << "action did not run" if !request["halted_by"] && !request["action_reached"]
  parts << "status #{request["status"]}#{" -> #{request["location"]}" if request["location"]}"
  if (actor = request["actor"])
    attrs = (actor["attrs"] || {}).map { |k, v| "#{k}=#{v}" }.join(" ")
    parts << "actor #{actor["class"]}##{actor["id"]} #{attrs}".strip
  elsif request["actor_source"] == "ivar"
    parts << "actor: anonymous"
  end
  db = request["db"] || {}
  writes = %w[insert update delete].filter_map { |v| "#{db[v]} #{v}" if db[v].to_i.positive? }
  parts << "db writes: #{writes.empty? ? "none" : writes.join(", ")}"
  parts << "writes rolled back: #{db["writes_rolled_back"]}" if db["writes_rolled_back"].to_i.positive?
  parts << "flash #{request["flash"].to_json}" if request["flash"]
  parts << "templates #{request["templates"].join(", ")}" if request["templates"]
  parts << "json error field #{request["json_error"].to_json}" if request["json_error"]
  Array(request["rescued"]).each { |e| parts << "rescue_from handled #{e["class"]}: #{e["message"]} (raised at #{e["raised_at"]}, origin #{e["origin"]})" }
  Array(request["app_rescues"]).each { |e| parts << "app code rescued #{e["class"]}: #{e["message"]} at #{e["rescued_at"]}" }
  parts << "exception escaped the controller: #{request["exception"]["class"]}: #{request["exception"]["message"]}" if request["exception"]
  Array(request["jobs"]).each { |j| parts << "job #{j["job"]} #{j["event"]}#{" (#{j["error"]["class"]}: #{j["error"]["message"]})" if j["error"]}" }
  Array(request["logs"]).first(3).each { |l| parts << "log #{l["severity"]}: #{l["message"].lines.first.to_s.strip[0, 160]}" }
  parts.join("; ")
end

def packet(id, record, findings, root, with_rules: true)
  issued = Array(record["issued"])
  lines = ["### #{id}", "", "Example: #{record["full_description"].inspect}", "", "```ruby",
           Source.for(root, record["location"]), "```", "", "Expectations that ran (all passed):"]
  expectations = Array(record["expectations"])
  lines << "- (none)" if expectations.empty?
  expectations.each { |e| lines << "- #{"NOT " if e["negated"]}#{e["description"]}" }
  lines << "" << "Runtime evidence:"
  issued.each_with_index do |origin, index|
    next unless origin["controllers"].to_i.zero? || origin["exception_page"]

    lines << "- issued #{origin["method"]} #{origin["path"]} answered #{origin["status"].inspect}" \
             "#{" with Rails' exception page" if origin["exception_page"]}" \
             "#{" without reaching any controller" if origin["controllers"].to_i.zero?} (request #{index + 1})"
  end
  Array(record["requests"]).each { |request| lines << "- #{request_line(request, issued)}" }
  Array(record["app_rescues"]).each { |e| lines << "- app code rescued #{e["class"]}: #{e["message"]} at #{e["rescued_at"]}" }
  Array(record["thread_deaths"]).each { |d| lines << "- a thread died with #{d["class"]}: #{d["message"]}#{" (re-raised by join)" if d["propagated"]}" }
  Array(record["jobs"]).each { |j| lines << "- job #{j["job"]} #{j["event"]}#{" (#{j["error"]["class"]})" if j["error"]}" }
  lines << "- (no requests or notable runtime events)" if lines.last == "Runtime evidence:"
  return lines.join("\n") unless with_rules

  lines << "" << "Deterministic rule output:"
  lines << "- (none)" if findings.empty?
  findings.each do |finding|
    state = finding.suppressed ? "suppressed: #{finding.suppressed}" : finding.confidence
    lines << "- #{finding.rule} [#{state}] #{finding.evidence.first}"
  end
  lines.join("\n")
end

rules = GreenSignal::Rules.new(root: options[:root])
records = ARGV.flat_map { |path| File.foreach(path).map { |line| JSON.parse(line) } }
records.select! { |record| options[:ids].include?(record["id"]) } if options[:ids]
records.select! { |record| record["status"] == "passed" }
index = []
records.each_with_index do |record, number|
  id = format("%<prefix>s%<n>02d", prefix: options[:prefix], n: number + 1)
  index << { "case" => id, "id" => record["id"], "description" => record["full_description"] }
  puts packet(id, record, rules.call(record), options[:root], with_rules: options[:rules])
  puts
end
File.write(ENV.fetch("PACKET_INDEX", "/dev/null"), JSON.pretty_generate(index))
