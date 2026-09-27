# frozen_string_literal: true

RSpec.describe RSpec::Signal::Selection do
  it "identifies a default invocation as a full suite" do
    selection = described_class.from_arguments([])

    expect(selection.mode).to eq("full_suite")
    expect(selection.paths).to eq(["spec"])
  end

  it "keeps full-suite identity stable when the example population changes" do
    before_edit = described_class.from_arguments([])
    after_edit = described_class.from_arguments([])

    expect(before_edit).to be_equivalent(after_edit)
  end

  it "normalizes path and filter order" do
    first = described_class.from_arguments(%w[spec/b_spec.rb spec/a_spec.rb --tag focus --tag fast])
    second = described_class.from_arguments(%w[--tag fast spec/a_spec.rb --tag focus spec/b_spec.rb])

    expect(first).to be_equivalent(second)
    expect(first.to_h).to include("paths" => %w[spec/a_spec.rb spec/b_spec.rb],
                                  "filters" => { "tag" => %w[fast focus] })
  end

  it "distinguishes a full suite from a targeted example" do
    full = described_class.from_arguments([])
    targeted = described_class.from_arguments(["spec/a_spec.rb:42"])

    expect(full).not_to be_equivalent(targeted)
  end

  it "distinguishes file and tag scopes" do
    file_a = described_class.from_arguments(["spec/a_spec.rb"])
    file_b = described_class.from_arguments(["spec/b_spec.rb"])
    focused = described_class.from_arguments(%w[--tag focus])

    expect(file_a).not_to be_equivalent(file_b)
    expect(file_a).not_to be_equivalent(focused)
  end

  it "ignores non-selection options" do
    ordinary = described_class.from_arguments([])
    configured = described_class.from_arguments(%w[--format progress --seed 1234 --require helper])

    expect(ordinary).to be_equivalent(configured)
  end

  it "uses the parent invocation transported to a parallel worker" do
    parent = described_class.from_arguments([])
    worker_arguments = %w[spec/a_spec.rb spec/b_spec.rb]
    environment = { described_class::ENV_KEY => JSON.generate(parent.to_h) }

    expect(described_class.from_rspec(worker_arguments, environment)).to be_equivalent(parent)
  end
end
