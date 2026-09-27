# frozen_string_literal: true

# Defined here so it is first-party to a config rooted at this repository.
class CaptureSpecAccount
  def self.boom
    raise ArgumentError, "unknown plan: gold"
  end
end

class CaptureSpecWrapper < StandardError; end

RSpec.describe RSpec::Signal::Causal::Capture do
  let(:config) { signal_config(project_root: File.expand_path("../../..", __dir__)) }

  def capture(error, identities: {}.compare_by_identity)
    frames = RSpec::Signal::Backtrace::Parser.parse(error.backtrace, config.classifier)
    described_class.call(error, frames: frames, config: config, identities: identities)
  end

  def raised
    yield
    raise "expected an error"
  rescue StandardError, ScriptError, RSpec::Expectations::ExpectationNotMetError => e
    e
  end

  # Phase is read from the rspec-core frames on the real stack, so these run
  # against whichever rspec-core is installed -- the oldest and newest in CI.
  # They have to raise inside real hooks and carry the error out of them,
  # which is exactly what these cops exist to discourage elsewhere.
  # rubocop:disable-next RSpec/InstanceVariable, RSpec/BeforeAfterAll, RSpec/LeakyLocalVariable
  describe "phase" do
    context "when raised in the example body" do
      it "is the body, and the body was reached" do
        evidence = capture(raised { raise "in the body" })

        expect(evidence.to_h.values_at("phase", "body_reached")).to eq(["body", true])
      end
    end

    context "when raised in a before hook" do
      before { @error = raised { raise "in a hook" } }

      it "is setup, and the body was never reached" do
        evidence = capture(@error)

        expect(evidence.to_h.values_at("phase", "phase_detail", "body_reached"))
          .to eq(["setup", "before hook", false])
      end
    end

    context "when raised in a before(:context) hook" do
      before(:context) { @context_error = raised { raise "in a context hook" } }

      it "is a before(:context) failure" do
        expect(capture(@context_error).phase_detail).to eq("before(:context) hook")
      end
    end

    context "when raised while evaluating a let" do
      let_line = __LINE__ + 1
      let(:error) { raised { raise "in a let" } }

      it "is still the body -- the body had begun -- and says it was a let" do
        evidence = capture(error)

        expect(evidence.to_h.values_at("phase", "phase_detail")).to eq(%w[body let])
        expect(evidence.site).to eq("spec/unit/causal/capture_spec.rb:#{let_line}")
      end
    end

    context "when raised in an after hook" do
      phases = []
      after { phases << capture(raised { raise "in teardown" }).to_h.values_at("phase", "phase_detail") }

      after(:context) do
        raise "teardown was classified as #{phases.inspect}" unless phases == [["teardown", "after hook"]]
      end

      it("is teardown (checked in an after(:context) hook)") { expect(phases).to be_empty }
    end

    it "is unknown, never guessed, without runner frames" do
      error = RuntimeError.new("elsewhere").tap { |e| e.set_backtrace(["/srv/app/lib/thread.rb:3:in `run'"]) }

      expect(capture(error).to_h.values_at("phase", "body_reached")).to eq(["unknown", nil])
    end
  end

  describe "missing entities, read from exception attributes" do
    it "names a missing ENV key" do
      expect(capture(raised { ENV.fetch("RSPEC_SIGNAL_CAPTURE_SPEC_UNSET") }).entities)
        .to eq(["env:RSPEC_SIGNAL_CAPTURE_SPEC_UNSET"])
    end

    it "does not treat an ordinary Hash#fetch as an environment problem" do
      expect(capture(raised { {}.fetch(:plan) }).entities).to be_empty
    end

    it "qualifies a missing constant by the namespace it was looked up in" do
      expect(capture(raised { RSpec::Signal::CaptureSpecMissing }).entities)
        .to eq(["const:RSpec::Signal::CaptureSpecMissing"])
    end

    it "names a missing method on a class defined in the project" do
      expect(capture(raised { CaptureSpecAccount.new.nickname }).entities)
        .to eq(["method:CaptureSpecAccount#nickname"])
    end

    it "never names a method missing on nil, or on a core class" do
      expect(capture(raised { nil.nickname }).entities).to be_empty
      expect(capture(raised { "text".nickname }).entities).to be_empty
    end

    it "reads entities from a wrapped cause too" do
      error = raised do
        ENV.fetch("RSPEC_SIGNAL_CAPTURE_SPEC_UNSET")
      rescue KeyError
        raise CaptureSpecWrapper, "configuration failed"
      end

      expect(capture(error).entities).to eq(["env:RSPEC_SIGNAL_CAPTURE_SPEC_UNSET"])
    end
  end

  describe "link key" do
    let(:bare) { capture(raised { CaptureSpecAccount.boom }) }
    let(:wrapped) do
      capture(raised do
        CaptureSpecAccount.boom
      rescue ArgumentError
        raise CaptureSpecWrapper, "import aborted"
      end)
    end

    it "is the same for an exception and the same exception wrapped" do
      expect(wrapped.link_key).to eq(bare.link_key)
      expect(wrapped.wrapped).to eq("ArgumentError")
    end

    it "differs when the message differs, even from the same line" do
      other = capture(raised { raise ArgumentError, "unknown plan: gold" })

      expect(other.link_key).not_to eq(bare.link_key)
    end

    it "is absent for an assertion failure, which never links on origin" do
      failure = raised { expect(1).to eq(2) } # rubocop:disable RSpec/ExpectActual

      expect(capture(failure).link_key).to be_nil
    end
  end

  it "gives one exception object one token, and another object another" do
    identities = {}.compare_by_identity
    error = raised { raise "shared" }

    tokens = [error, error, raised { raise "other" }].map { |item| capture(item, identities: identities).identities }

    expect(tokens[0]).to eq(tokens[1])
    expect(tokens[2]).not_to eq(tokens[0])
  end
end
