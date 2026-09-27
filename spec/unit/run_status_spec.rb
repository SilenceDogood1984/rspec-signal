# frozen_string_literal: true

RSpec.describe RSpec::Signal::RunStatus do
  subject(:status) { described_class.new }

  def finish_run(selected: 2, executed: 2, summarized: executed)
    status.selected(selected)
    executed.times { status.example_executed }
    status.summarized(summarized) unless summarized.nil?
  end

  it "distinguishes completeness from history eligibility" do
    finish_run

    expect(status).to be_complete(outside_errors: 0)
    expect(status).not_to be_history_eligible(outside_errors: 0, targeted: true)
    expect(status.skipped_reason(outside_errors: 0, targeted: true)).to eq("targeted run")
  end

  it "calls a partially executed run incomplete" do
    finish_run(executed: 1, summarized: 1)

    expect(status).not_to be_complete(outside_errors: 0)
    expect(status.skipped_reason(outside_errors: 0, targeted: false)).to eq("run incomplete")
  end

  it "requires a summary and rejects errors outside examples" do
    finish_run(summarized: nil)
    expect(status).not_to be_complete(outside_errors: 0)

    status.summarized(2)
    expect(status).not_to be_complete(outside_errors: 1)
  end
end
