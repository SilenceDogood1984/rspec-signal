# frozen_string_literal: true

require "benchmark"

# A guard, not a benchmark. It exists so a change that makes per-failure
# processing ten times slower cannot land unnoticed, and the budgets are set
# far enough above the measured cost that ordinary machine-to-machine variance
# and CI noise never trip it.
#
# Measured on the development machine at the time of writing: well under a
# millisecond per failure for the whole pipeline (parse, classify, reduce,
# normalize, fingerprint), and a fraction of a second to analyse and render a
# four-hundred-failure run.
RSpec.describe "processing cost", :performance do
  let(:config) { signal_config }

  # A realistic worst case: a deep stack with library frames in the middle,
  # which is the shape that exercises every scoring rule in the reducer.
  def deep_backtrace(index)
    Backtraces.active_record_invalid(service_line: 40 + (index % 7),
                                     spec: "spec/models/subscription_#{index % 25}_spec.rb",
                                     spec_line: 10 + (index % 30))
  end

  def build_failures(count)
    Array.new(count) do |index|
      build_failure(config: config, backtrace: deep_backtrace(index),
                    exception_class: index.even? ? "ActiveRecord::RecordInvalid" : "KeyError",
                    message: ["Failure/Error: subject.call", "",
                              "ActiveRecord::RecordInvalid:",
                              "  Validation failed: Email has already been taken (#{index % 5})"],
                    description: "example #{index}")
    end
  end

  # A fixed number of distinct problems, however many examples manifest them.
  # This is the shape a real suite takes when one bug breaks a hundred specs.
  def repeated_failures(count, problems: 5)
    Array.new(count) do |index|
      problem = index % problems
      build_failure(config: config, backtrace: Backtraces.active_record_invalid(service_line: 40 + problem),
                    exception_class: "ActiveRecord::RecordInvalid",
                    message: ["Failure/Error: subject.call", "",
                              "ActiveRecord::RecordInvalid:",
                              "  Validation failed: field #{problem} is required"],
                    description: "example #{index}")
    end
  end

  def render(failures)
    RSpec::Signal::Reporters::Markdown.new(build_report(failures), config).render
  end

  it "builds a failure in well under a millisecond" do
    build_failures(50) # warm up the caches the pipeline memoizes
    elapsed = Benchmark.realtime { build_failures(400) }

    expect(elapsed / 400).to be < 0.005
  end

  it "analyses and renders a four-hundred-failure run in well under a second" do
    failures = build_failures(400)

    elapsed = Benchmark.realtime do
      report = build_report(failures)
      RSpec::Signal::Reporters::Markdown.new(report, config).render
      RSpec::Signal::Reporters::JsonReport.new(report, config).render
    end

    expect(elapsed).to be < 1.0
  end

  # Grouping, clustering and code paths are all indexed rather than pairwise.
  # Quadratic behaviour here would be invisible on a small suite and fatal on
  # a large one.
  it "scales roughly linearly rather than quadratically with failure count" do
    small = build_failures(100)
    large = build_failures(800)
    # Both sets must be warm: the pipeline memoizes fingerprints and symptoms
    # on first use, and measuring a cold set against a warm one measures the
    # memoization rather than the analysis.
    [small, large].each { |set| build_report(set) }

    small_time = Benchmark.realtime { build_report(small) }
    large_time = Benchmark.realtime { build_report(large) }

    expect(large_time).to be < (small_time * 8 * 4)
  end

  # The central claim of the product: a hundred times the failures is not a
  # hundred times the report, as long as they are the same handful of problems.
  it "keeps the report bounded by the number of problems, not the number of failures" do
    ten = render(repeated_failures(10))
    thousand = render(repeated_failures(1_000))

    expect(thousand.lines.size).to be < (ten.lines.size * 3)
  end

  it "grows with distinct problems, because that is the honest outcome" do
    five_problems = render(repeated_failures(200, problems: 5))
    fifty_problems = render(repeated_failures(200, problems: 50))

    expect(fifty_problems.lines.size).to be > (five_problems.lines.size * 3)
  end
end
