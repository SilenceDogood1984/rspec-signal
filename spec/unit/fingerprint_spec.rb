# frozen_string_literal: true

RSpec.describe RSpec::Signal::Fingerprint do
  def fingerprint(**overrides)
    described_class.new({ exception_class: "A", message: "B", culprit: "C", app_context: "D" }.merge(overrides))
  end

  # `to_a.join(" ")` would let text shift across a component boundary and
  # still produce byte-identical joined text -- and therefore the same
  # digest -- whenever a component itself contains a space. NUL never
  # appears in these components, so it closes that gap.
  it "does not collide when text shifts across a component boundary" do
    shifted_right = fingerprint(exception_class: "A", message: "b c")
    shifted_left = fingerprint(exception_class: "A b", message: "c")

    expect(shifted_right.digest).not_to eq(shifted_left.digest)
  end

  it "is deterministic" do
    first = fingerprint(culprit: "same")
    second = fingerprint(culprit: "same")

    expect(first.digest).to eq(second.digest)
  end

  it "changes when any single component changes" do
    baseline = fingerprint.digest

    expect(fingerprint(exception_class: "Other").digest).not_to eq(baseline)
    expect(fingerprint(message: "Other").digest).not_to eq(baseline)
    expect(fingerprint(culprit: "Other").digest).not_to eq(baseline)
    expect(fingerprint(app_context: "Other").digest).not_to eq(baseline)
  end
end
