# frozen_string_literal: true

RSpec.describe RSpec::Signal::Report do
  describe "#worker_h" do
    let(:failure) { build_failure(backtrace: Backtraces.pure_ruby, raw: "  1) the original unreduced output") }
    let(:report) { described_class.new(failures: [failure]) }

    it "omits the unreduced raw output by default" do
      serialized = report.worker_h.fetch(:failures).first

      expect(serialized).not_to have_key(:raw)
    end

    it "includes the unreduced raw output when write_full is requested" do
      serialized = report.worker_h(write_full: true).fetch(:failures).first

      expect(serialized[:raw]).to eq("  1) the original unreduced output")
    end

    it "carries its own schema, distinct from the published one" do
      expect(report.worker_h[:schema]).to eq(described_class::WORKER_SCHEMA)
      expect(report.worker_h[:schema]).not_to eq(described_class::SCHEMA)
    end
  end

  describe "#to_h" do
    let(:long_message) { ["Failure/Error: x", ""] + Array.new(60) { |i| "line #{i}" } }
    let(:failure) { build_failure(backtrace: Backtraces.pure_ruby, message: long_message) }
    let(:report) { described_class.new(failures: [failure]) }

    def serialized_message(config)
      report.to_h(config).dig(:signatures, 0, :representative, :message)
    end

    # The Markdown renderer has always honoured these budgets. The JSON did
    # not, so a project that tightened them to control artifact size got a
    # smaller signal.md and an unchanged signal.json.
    it "honours the configured message budget" do
      expect(serialized_message(signal_config(max_message_lines: 5)).size).to be <= 6
    end

    it "honours a widened message budget too" do
      wide = serialized_message(signal_config(max_message_lines: 80)).size
      narrow = serialized_message(signal_config(max_message_lines: 5)).size

      expect(wide).to be > narrow
    end

    it "falls back to the documented defaults with no configuration" do
      expect(report.to_h.dig(:signatures, 0, :representative, :message).size).to be <= 31
    end

    it "publishes the current schema" do
      expect(report.to_h[:schema]).to eq(2)
    end

    it "publishes a run id when it has one" do
      expect(described_class.new(failures: [failure], run_id: "abc").to_h[:run_id]).to eq("abc")
    end

    it "omits the comparison entirely when there was no previous run" do
      expect(report.to_h).not_to have_key(:since_last_run)
    end

    it "keeps the analysis sections present but empty, so consumers see a stable shape" do
      expect(report.to_h).to include(related: [], code_paths: [], outside_examples: [])
    end
  end

  describe "#reportable?" do
    it "is false for a run with nothing wrong" do
      expect(described_class.new(failures: []).reportable?).to be(false)
    end

    it "is true for a run whose only problem was outside every example" do
      expect(described_class.new(failures: [], errors_outside_examples: 1).reportable?).to be(true)
    end
  end
end
