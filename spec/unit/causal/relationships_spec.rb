# frozen_string_literal: true

RSpec.describe RSpec::Signal::Reporters::Relationships do
  def failure(name, **evidence)
    build_failure(backtrace: [Backtraces.app("lib/#{name}.rb", 3, "call")], message: ["#{name} broke"],
                  example_id: "./spec/#{name}_spec.rb[1:1]")
      .tap { |item| item.evidence = RSpec::Signal::Causal::Evidence.new(identities: [], entities: [], **evidence) }
  end

  def lines(failures)
    described_class.new(build_report(failures).analysis).terminal_lines
  end

  it "prints nothing when it has nothing to add to the signatures" do
    expect(lines([failure("a"), failure("b")])).to be_empty
  end

  it "prints a bounded view: at most three groups, two lines each, and the accounting" do
    failures = (1..5).flat_map do |i|
      [failure("x#{i}", entities: ["env:KEY_#{i}"]), failure("y#{i}", entities: ["env:KEY_#{i}"])]
    end
    output = lines(failures + [failure("lonely")])

    expect(output.size).to be <= (3 * 3) + 3
    expect(output).to include("(2 more related groups in signal.json)")
    expect(output.last).to eq("11/11 failures accounted for: 10 causal, 0 scope, 1 independent")
  end

  it "names the missing definition and never the word cause" do
    output = lines([failure("a", entities: ["env:STRIPE_KEY"]), failure("b", entities: ["env:STRIPE_KEY"])])

    expect(output.join("\n")).to include("CAUSAL · HIGH · 2 failures in 2 signatures", "missing ENV key STRIPE_KEY")
    expect(output.join("\n")).not_to match(/\bcause\b|root/i)
  end

  describe "when rendering fails" do
    let(:report) { build_report([build_failure(backtrace: [Backtraces.app("lib/a.rb", 1, "call")])]) }

    before do
      %i[to_h markdown terminal_lines].each do |method|
        allow_any_instance_of(described_class) # rubocop:disable RSpec/AnyInstance
          .to receive(method).and_raise(NoMethodError, "boom")
      end
    end

    it "cannot cost the report its JSON, its Markdown or its terminal lines" do
      expect(report.to_h).not_to include(:analysis)
      expect(render_markdown(report)).to include("# RSpec Signal")
      expect(report.relationship_lines).to eq([])
    end
  end
end
