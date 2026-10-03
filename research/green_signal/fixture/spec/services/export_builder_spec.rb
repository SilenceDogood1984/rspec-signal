# frozen_string_literal: true

RSpec.describe ExportBuilder do
  it "fails loudly when its thread is joined" do
    thread = Thread.new { described_class.new(1).call }
    thread.report_on_exception = false
    expect { thread.join }.to raise_error(NameError, /ProjectCsvSerializer/)
  end
end
