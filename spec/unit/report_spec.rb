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
  end
end
