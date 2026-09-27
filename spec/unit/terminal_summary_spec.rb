# frozen_string_literal: true

RSpec.describe RSpec::Signal::TerminalSummary do
  def failure(message, location)
    build_failure(backtrace: ["#{Backtraces::ROOT}/#{location}:3:in `work'"], message: [message],
                  example_id: "./#{location}[1:1]")
  end

  it "adds only an exact action and report pointer to native output for one failure" do
    report = build_report([failure("expected 2, got 1", "spec/one_spec.rb")], failure_count: 1)
    lines = described_class.new(report, report_path: "tmp/rspec-signal/signal.md").lines

    expect(lines).to eq([
      "Exact rerun: bundle exec rspec './spec/one_spec.rb[1:1]'",
      "Report: tmp/rspec-signal/signal.md"
    ])
    expect(lines.join("\n")).not_to include("1 distinct", "frames omitted", "expected 2")
  end

  it "leads a collapsed cascade with totals, its representative, and exact rerun" do
    failures = Array.new(20) do |index|
      build_failure(
        backtrace: ["#{Backtraces::ROOT}/spec/cascade_spec.rb:3:in `work'"],
        message: ["shared break"], example_id: "./spec/cascade_spec.rb[1:#{index + 1}]"
      )
    end
    report = build_report(failures, failure_count: 20)
    lines = described_class.new(report, quiet: true).lines

    expect(lines.first).to eq("RSpec totals: 20 examples, 20 failures, 0 pending")
    expect(lines[1]).to eq("Signal problems: 20 failures, 1 distinct problem")
    expect(lines[2]).to start_with("Top problem (20 failures): RuntimeError: shared break")
    expect(lines.grep(/^Problem|^Top problem/).size).to eq(1)
    expect(lines.grep(/^Exact rerun:/).size).to eq(1)
  end

  it "labels independent failures without making causal claims" do
    report = build_report([
      failure("first break", "spec/first_spec.rb"),
      failure("second break", "spec/second_spec.rb")
    ], failure_count: 2)
    text = described_class.new(report, quiet: true).lines.join("\n")

    expect(text).to include("2 distinct problems", "Problem #1", "Problem #2")
    expect(text).not_to include("root cause", "caused by")
  end

  it "bounds a large mixed cascade by top distinct problems" do
    failures = 10.times.flat_map do |group|
      Array.new(10) do |index|
        build_failure(
          backtrace: ["#{Backtraces::ROOT}/spec/mixed_#{group}_spec.rb:3:in `work'"],
          message: ["break #{group}"], example_id: "./spec/mixed_#{group}_spec.rb[1:#{index + 1}]"
        )
      end
    end
    report = build_report(failures, failure_count: 100)
    lines = described_class.new(report, quiet: true).lines

    expect(lines).to include("Signal problems: 100 failures, 10 distinct problems")
    expect(lines.grep(/^Problem/).size).to eq(3)
    expect(lines.size).to be <= 9
  end

  it "keeps an outside-example error and its action visible" do
    load_failure = failure("cannot load such file -- missing", "spec/broken_spec.rb")
    report = build_report([], failure_count: 0, errors_outside_examples: 1,
                          outside_example_failures: [load_failure])
    text = described_class.new(report, quiet: true, workers: 2).lines.join("\n")

    expect(text).to include("Outside examples: 1 error", "Load problem: RuntimeError",
                            "Exact rerun: bundle exec rspec")
    expect(text).to include("across 2 workers")
  end
end
