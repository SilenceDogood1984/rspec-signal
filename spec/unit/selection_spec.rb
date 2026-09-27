# frozen_string_literal: true

RSpec.describe RSpec::Signal::Selection do
  it "normalizes example order and retains concise debugging context" do
    first = described_class.new(%w[./spec/b_spec.rb[1:2] ./spec/a_spec.rb[1:1]])
    second = described_class.new(first.example_ids.reverse)

    expect(first).to be_equivalent(second)
    expect(first.to_h).to include("count" => 2, "files" => %w[./spec/a_spec.rb ./spec/b_spec.rb])
    expect(first.to_h).not_to have_key("example_ids")
  end

  it "distinguishes selections produced by tag filters" do
    all = described_class.new(%w[./spec/a_spec.rb[1:1] ./spec/a_spec.rb[1:2]])
    tagged = described_class.new(["./spec/a_spec.rb[1:1]"])

    expect(all).not_to be_equivalent(tagged)
  end

  it "unions parallel worker selections deterministically" do
    worker_two = described_class.new(["./spec/b_spec.rb[1:1]"])
    worker_one = described_class.new(["./spec/a_spec.rb[1:1]"])

    expect(described_class.merge([worker_two, worker_one]))
      .to be_equivalent(described_class.new(worker_one.example_ids + worker_two.example_ids))
  end
end
