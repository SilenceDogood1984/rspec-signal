# frozen_string_literal: true

RSpec.describe RSpec::Signal::Causal::Census do
  subject(:census) { described_class.new }

  def example(file, type: nil)
    metadata = { rerun_file_path: "./#{file}" }
    metadata[:type] = type if type
    instance_double(RSpec::Core::Notifications::ExampleNotification,
                    example: instance_double(RSpec::Core::Example, metadata: metadata))
  end

  # Recording is fail-soft, which once hid a bug that left every census empty.
  # These assert the counts themselves.
  it "counts examples run and failed per file and per type" do
    census.record(example("spec/a_spec.rb", type: :system), failed: true)
    census.record(example("spec/a_spec.rb", type: :system), failed: false)
    census.record(example("spec/b_spec.rb"), failed: false)

    expect([census.total, census.failed]).to eq([3, 1])
    expect(census.count("file", "spec/a_spec.rb")).to eq([2, 1])
    expect(census.count("type", "system")).to eq([2, 1])
    expect(census.values("type")).to eq(["system"])
  end

  it "adds worker censuses into one" do
    worker = described_class.new.record(example("spec/a_spec.rb"), failed: true)
    merged = described_class.new.merge(JSON.parse(JSON.generate(worker.to_h))).merge(worker.to_h)

    expect([merged.total, merged.failed]).to eq([2, 2])
    expect(merged.count("file", "spec/a_spec.rb")).to eq([2, 2])
  end

  it "never raises on a notification it cannot read" do
    expect { census.record(nil, failed: true) }.not_to raise_error
    expect(census.total).to eq(0)
  end

  it "ignores a worker that sent no census" do
    expect(census.merge(nil).total).to eq(0)
  end
end
