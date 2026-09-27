# frozen_string_literal: true

RSpec.describe RSpec::Signal::History do
  let(:config) { signal_config }
  let(:history) { described_class.new(config) }
  let(:failure) do
    build_failure(config: config, backtrace: Backtraces.pure_ruby, message: ["key not found: :price"],
                  exception_class: "KeyError")
  end

  let(:full_selection) do
    RSpec::Signal::Selection.new(%w[./spec/a_spec.rb[1:1] ./spec/b_spec.rb[1:1]])
  end

  def report_with(failures, selection: full_selection)
    build_report(failures, example_count: 10, failure_count: failures.size, selection: selection)
  end

  it "has nothing to compare against on the first run" do
    expect(history.compare(report_with([failure]), run_id: "first")).to be_nil
  end

  it "compares the second run against the first" do
    history.record(report_with([failure]), run_id: "first")

    comparison = described_class.new(config).compare(report_with([]), run_id: "second")

    expect(comparison.resolved.size).to eq(1)
    expect(comparison.previous_run_id).to eq("first")
  end

  it "does not compare a one-example rerun with a full-suite run" do
    history.record(report_with([failure]), run_id: "full")
    targeted = RSpec::Signal::Selection.new(["./spec/a_spec.rb[1:1]"])

    expect(described_class.new(config).compare(report_with([], selection: targeted), run_id: "targeted")).to be_nil
  end

  it "compares the same targeted example on later runs" do
    targeted = RSpec::Signal::Selection.new(["./spec/a_spec.rb[1:1]"])
    history.record(report_with([failure], selection: targeted), run_id: "first-targeted")

    comparison = described_class.new(config).compare(report_with([], selection: targeted), run_id: "again")

    expect(comparison.previous_run_id).to eq("first-targeted")
    expect(comparison.resolved.size).to eq(1)
  end

  it "finds the previous equivalent full run across an intervening targeted run" do
    targeted = RSpec::Signal::Selection.new(["./spec/a_spec.rb[1:1]"])
    history.record(report_with([failure]), run_id: "full")
    described_class.new(config).record(report_with([], selection: targeted), run_id: "targeted")

    comparison = described_class.new(config).compare(report_with([]), run_id: "next-full")

    expect(comparison.previous_run_id).to eq("full")
  end

  it "does not compare different file selections" do
    file_a = RSpec::Signal::Selection.new(["./spec/a_spec.rb[1:1]"])
    file_b = RSpec::Signal::Selection.new(["./spec/b_spec.rb[1:1]"])
    history.record(report_with([failure], selection: file_a), run_id: "a")

    expect(described_class.new(config).compare(report_with([], selection: file_b), run_id: "b")).to be_nil
  end

  it "treats the same files and examples in different order as equivalent" do
    reversed = RSpec::Signal::Selection.new(full_selection.example_ids.reverse)
    history.record(report_with([failure]), run_id: "ordered")

    expect(described_class.new(config).compare(report_with([], selection: reversed), run_id: "reversed"))
      .not_to be_nil
  end

  it "does not compare reports without selection metadata" do
    history.record(build_report([failure]), run_id: "unknown")

    expect(described_class.new(config).compare(build_report([]), run_id: "also-unknown")).to be_nil
  end

  # The run that deletes the report is exactly the run that should be able to
  # say "42 became 0", so the history must not be an artifact.
  it "records a green run so the next one can say what was fixed" do
    history.record(report_with([failure]), run_id: "first")
    described_class.new(config).record(report_with([]), run_id: "second")

    comparison = described_class.new(config).compare(report_with([failure]), run_id: "third")

    expect(comparison.previous_failures).to eq(0)
    expect(comparison.new_signatures.size).to eq(1)
  end

  it "keeps only the most recent runs" do
    (described_class::MAX_RUNS + 5).times { |i| described_class.new(config).record(report_with([]), run_id: "r#{i}") }

    expect(described_class.new(config).runs.size).to eq(described_class::MAX_RUNS)
  end

  # Artifacts are handed to third-party services; the history is not an
  # artifact, but it lives beside them and must survive that scrutiny.
  it "stores digests and counts, never message or source text" do
    history.record(report_with([failure]), run_id: "first")

    expect(File.read(history.path)).not_to include("key not found", "calculator.rb")
  end

  it "survives a corrupt file rather than taking the run down" do
    FileUtils.mkdir_p(File.dirname(history.path))
    File.write(history.path, "{not json")

    expect(described_class.new(config).runs).to eq([])
    expect(described_class.new(config).compare(report_with([failure]), run_id: "x")).to be_nil
  end

  # Older schemas either used incompatible signature digests or had no
  # selection identity. Comparing would report every signature as resolved and
  # new; saying nothing for one run is the honest outcome.
  it "ignores a schema 1 history, whose digests are not comparable" do
    FileUtils.mkdir_p(File.dirname(history.path))
    File.write(history.path, JSON.generate("schema" => 1, "runs" => [{ "run_id" => "old", "failures" => 3,
                                                                       "signatures" => [] }]))

    expect(described_class.new(config).compare(report_with([failure]), run_id: "new")).to be_nil
  end

  it "ignores schema 2 history, which has no selection identity" do
    FileUtils.mkdir_p(File.dirname(history.path))
    File.write(history.path, JSON.generate("schema" => 2, "runs" => [{ "run_id" => "old" }]))

    expect(described_class.new(config).compare(report_with([failure]), run_id: "new")).to be_nil
  end

  it "ignores a history written by an incompatible future schema" do
    FileUtils.mkdir_p(File.dirname(history.path))
    File.write(history.path, JSON.generate({ "schema" => 99, "runs" => [{ "run_id" => "x" }] }))

    expect(described_class.new(config).runs).to eq([])
  end

  it "can be turned off" do
    quiet = signal_config(track_history: false)

    expect(quiet.track_history).to be(false)
  end
end
