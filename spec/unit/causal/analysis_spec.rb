# frozen_string_literal: true

RSpec.describe RSpec::Signal::Causal::Analysis do
  let(:census) { RSpec::Signal::Causal::Census.new }

  # A failure with its own signature (distinct message and raise site), in
  # `file`, carrying the given evidence.
  def failure(name, file: "spec/#{name}_spec.rb", **evidence)
    build_failure(backtrace: [Backtraces.app("lib/#{name}.rb", 3, "call")], message: ["#{name} broke"],
                  example_id: "./#{file}[1:#{name.hash.abs % 1000}]")
      .tap { |item| item.evidence = RSpec::Signal::Causal::Evidence.new(file: file, identities: [], entities: [], **evidence) }
  end

  def analyse(failures, outside: [])
    report = build_report(failures, census: census, outside_example_failures: outside,
                                    errors_outside_examples: outside.size)
    report.analysis
  end

  def kinds(analysis)
    analysis.relations.map { |relation| [relation.kind, relation.failures] }
  end

  it "links signatures that share a missing definition, with high confidence" do
    analysis = analyse([failure("payments", entities: ["env:STRIPE_KEY"]),
                        failure("webhooks", entities: ["env:STRIPE_KEY"])])

    expect(kinds(analysis)).to eq([[:causal, 2]])
    expect(analysis.relations.first.confidence).to eq("high")
  end

  it "does not link different missing definitions" do
    analysis = analyse([failure("payments", entities: ["env:STRIPE_KEY"]),
                        failure("monitoring", entities: ["env:SENTRY_DSN"])])

    expect(kinds(analysis)).to eq([[:independent, 1], [:independent, 1]])
  end

  it "links on a shared exception object only when RSpec shared it, in a before(:context) hook" do
    shared = { identities: ["e1"], phase: "setup", phase_detail: "before(:context) hook" }
    reused = { identities: ["e2"], phase: "body" }

    expect(kinds(analyse([failure("a", **shared), failure("b", **shared)]))).to eq([[:causal, 2]])
    expect(kinds(analyse([failure("c", **reused), failure("d", **reused)])).map(&:first)).to all(eq(:independent))
  end

  it "does not form a group from one plain signature: that is already a signature" do
    repeated = Array.new(3) { failure("cart") }

    expect(kinds(analyse(repeated))).to eq([[:independent, 3]])
  end

  describe "scope" do
    before do
      11.times { |i| census.add({ "file" => "spec/parallel_spec.rb" }, failed: i < 9) }
      493.times { census.add({ "file" => "spec/other_spec.rb" }, failed: false) }
    end

    let(:concentrated) { %w[a b c].map { |name| failure(name, file: "spec/parallel_spec.rb") } }

    it "reports concentration as a fact about where, with no confidence" do
      relation = analyse(concentrated).relations.first

      expect([relation.kind, relation.confidence]).to eq([:scope, nil])
      expect(relation.scope).to include("failed" => 9, "examples" => 11, "failed_elsewhere" => 0,
                                        "examples_elsewhere" => 493)
    end

    it "needs failures elsewhere to be rare" do
      40.times { census.add({ "file" => "spec/other_spec.rb" }, failed: true) }

      expect(kinds(analyse(concentrated)).map(&:first)).to all(eq(:independent))
    end

    it "needs more than one signature: one signature is already one thing" do
      expect(kinds(analyse(Array.new(3) { failure("a", file: "spec/parallel_spec.rb") }))).to eq([[:independent, 3]])
    end

    it "never absorbs failures a causal group already explains" do
      linked = %w[x y].map { |name| failure(name, file: "spec/parallel_spec.rb", entities: ["const:Billing::Invoice"]) }

      expect(kinds(analyse(concentrated + linked))).to eq([[:causal, 2], [:scope, 3]])
    end
  end

  it "accounts for every failure, and says when RSpec reported more than it captured" do
    report = build_report([failure("a"), failure("b")], census: census, failure_count: 3)

    expect([report.analysis.accounted, report.analysis.not_captured]).to eq([2, 1])
  end

  it "is switched off entirely by configuration" do
    expect(build_report([failure("a")], causal_analysis: false).analysis).to be_nil
  end
end
