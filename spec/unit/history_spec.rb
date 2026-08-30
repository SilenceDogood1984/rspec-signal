# frozen_string_literal: true

RSpec.describe RSpec::Signal::History do
  let(:config) { signal_config }
  let(:history) { described_class.new(config) }
  let(:failure) do
    build_failure(config: config, backtrace: Backtraces.pure_ruby, message: ["key not found: :price"],
                  exception_class: "KeyError")
  end

  def report_with(failures)
    build_report(failures, example_count: 10, failure_count: failures.size)
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
