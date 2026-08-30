# frozen_string_literal: true

RSpec.describe RSpec::Signal::Comparison do
  def run(failures:, signatures:)
    { "run_id" => "r", "failures" => failures, "signatures" => signatures }
  end

  def signature(digest, loose, exception: "KeyError", count: 1)
    { "digest" => digest, "loose" => loose, "exception" => exception, "count" => count }
  end

  it "counts a signature present in both runs as still failing" do
    comparison = described_class.new(
      previous: run(failures: 1, signatures: [signature("a", "la")]),
      current: run(failures: 1, signatures: [signature("a", "la")])
    )

    expect(comparison.persistent.map(&:digest)).to eq(["a"])
    expect(comparison.resolved).to be_empty
    expect(comparison.new_signatures).to be_empty
  end

  it "counts a signature that disappeared entirely as resolved" do
    comparison = described_class.new(
      previous: run(failures: 2, signatures: [signature("a", "la"), signature("b", "lb")]),
      current: run(failures: 1, signatures: [signature("a", "la")])
    )

    expect(comparison.resolved.map(&:digest)).to eq(["b"])
  end

  it "counts an unrecognised signature as new" do
    comparison = described_class.new(
      previous: run(failures: 1, signatures: [signature("a", "la")]),
      current: run(failures: 2, signatures: [signature("a", "la"), signature("c", "lc")])
    )

    expect(comparison.new_signatures.map(&:digest)).to eq(["c"])
    expect(comparison.resolved).to be_empty
  end

  # The bucket that makes the other three trustworthy. Editing the file that
  # raises shifts every culprit line, which changes the full digest while the
  # exception and message stay put. Without this, one edit turns every
  # persistent failure into a spurious resolved/new pair.
  describe "when an edit moves the raise site but fixes nothing" do
    let(:comparison) do
      described_class.new(
        previous: run(failures: 1, signatures: [signature("a", "shared")]),
        current: run(failures: 1, signatures: [signature("a-moved", "shared")])
      )
    end

    it "reports it as a changed signature" do
      expect(comparison.changed.map(&:digest)).to eq(["a-moved"])
    end

    it "does not claim anything was resolved" do
      expect(comparison.resolved).to be_empty
    end

    it "does not claim anything is new" do
      expect(comparison.new_signatures).to be_empty
    end
  end

  describe "#headline" do
    it "reads as a sentence and carries the failure counts" do
      comparison = described_class.new(
        previous: run(failures: 42, signatures: [signature("a", "la"), signature("b", "lb")]),
        current: run(failures: 17, signatures: [signature("a", "la"), signature("c", "lc")])
      )

      expect(comparison.headline).to eq("1 resolved, 1 new, 1 still failing (42 -> 17 failures)")
    end

    it "is nil when two identical runs have nothing to report" do
      comparison = described_class.new(previous: run(failures: 0, signatures: []),
                                       current: run(failures: 0, signatures: []))

      expect(comparison.headline).to be_nil
    end
  end

  it "serialises every bucket for tooling" do
    comparison = described_class.new(
      previous: run(failures: 1, signatures: [signature("b", "lb", exception: "TypeError", count: 3)]),
      current: run(failures: 0, signatures: [])
    )

    expect(comparison.to_h[:resolved]).to eq([{ signature: "b", exception: "TypeError", examples: 3 }])
  end
end
