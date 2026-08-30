# frozen_string_literal: true

require_relative "../support/sandbox_project"

# The loop the gem exists to serve, exercised against real `rspec` processes:
#
#   run -> understand -> fix -> rerun exactly -> verify what changed
#
# Everything here shells out, because the properties under test -- that a
# printed command reruns precisely the examples it names, that a second run
# knows what the first one found -- cannot be observed from inside the process
# that produced them.
RSpec.describe "the agent workflow", :integration do
  let(:project) { SandboxProject.new }

  after { project.cleanup }

  describe "rerunning exactly one signature" do
    before do
      project.install_spec_helper
      # Ten examples generated in a loop share one source line, and two
      # unrelated failures share another. A location-based rerun command
      # cannot distinguish any of them.
      project.write("spec/generated_spec.rb", <<~RUBY)
        RSpec.describe "generated" do
          10.times do |i|
            it("fails identically \#{i}") { expect(1).to eq(2) }
          end
        end
      RUBY
      project.write("spec/mixed_spec.rb", <<~RUBY)
        RSpec.describe "mixed" do
          [404, 404, 500].each do |code|
            it("returns \#{code}") { raise "the response was \#{code}" }
          end
        end
      RUBY
    end

    it "prints a command that reruns one example, not every example on its line" do
      project.run_signal

      rerun = project.run(*project.first_rerun_arguments)

      expect(rerun.stdout).to include("1 example, 1 failure")
    end

    it "prints a whole-signature command that reruns that signature and nothing else" do
      project.run_signal
      # The largest signature is the ten generated examples; its second
      # command lists all of them.
      arguments = project.rerun_arguments(1)
      rerun = project.run(*arguments)

      expect(arguments.size).to eq(10)
      expect(rerun.stdout).to include("10 examples, 10 failures")
    end

    it "never prints the same rerun command for two different signatures" do
      project.run_signal
      representatives = project.json.fetch("signatures").map { |signature| signature.fetch("rerun") }

      expect(representatives.uniq.size).to eq(representatives.size)
    end

    it "publishes the exact ids for every affected example" do
      project.run_signal
      signature = project.json.fetch("signatures").max_by { |item| item.fetch("count") }

      expect(signature.fetch("rerun_ids").size).to eq(signature.fetch("count"))
      expect(signature.fetch("rerun_ids")).to all(match(/\[\d+:\d+\]\z/))
    end
  end

  describe "knowing what changed since the last run" do
    before do
      project.install_spec_helper
      project.write("lib/pricing.rb", <<~RUBY)
        module Pricing
          RATES = { monthly: 10 }.freeze
          def self.rate_for(plan) = RATES.fetch(plan)
        end
      RUBY
      project.write("spec/pricing_spec.rb", <<~RUBY)
        $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
        require "pricing"
        RSpec.describe Pricing do
          it("prices annual") { expect(Pricing.rate_for(:annual)).to eq(120) }
          it("prices weekly") { expect(Pricing.rate_for(:weekly)).to eq(3) }
        end
      RUBY
    end

    it "says nothing about a previous run on the first run" do
      run = project.run_signal

      expect(run.stdout).not_to include("Since last run")
    end

    it "reports what a fix resolved and what still fails" do
      project.run_signal
      project.write("lib/pricing.rb", <<~RUBY)
        module Pricing
          RATES = { monthly: 10, annual: 120 }.freeze
          def self.rate_for(plan) = RATES.fetch(plan)
        end
      RUBY

      run = project.run_signal

      expect(run.stdout).to include("Since last run: Signatures: 1 resolved, 1 persistent; failures: 2 -> 1")
    end

    # The property that makes the other buckets trustworthy. An edit that
    # shifts line numbers must not read as "you fixed one and broke one".
    it "reports a moved raise site as a changed signature, not as a fix" do
      project.run_signal
      project.write("lib/pricing.rb", <<~RUBY)
        # frozen_string_literal: true

        module Pricing
          RATES = { monthly: 10 }.freeze
          def self.rate_for(plan) = RATES.fetch(plan)
        end
      RUBY

      run = project.run_signal

      expect(run.stdout).to include("Signatures: 2 changed")
      expect(run.stdout).not_to include("resolved")
    end

    it "survives the green run that deletes every other artifact" do
      project.run_signal
      project.write("spec/pricing_spec.rb", "RSpec.describe('ok') { it('passes') { expect(1).to eq(1) } }\n")

      green = project.run_signal

      expect(green.status).to eq(0)
      expect(green.stdout).to include("Signatures: 2 resolved; failures: 2 -> 0")
      expect(project.artifact?("signal.md")).to be(false)
      expect(project.artifact?("history.json")).to be(true)
    end

    it "records digests and counts, never message or source text" do
      project.run_signal

      expect(File.read(project.artifact("history.json"))).not_to include("key not found", "pricing.rb")
    end

    it "can be turned off" do
      project.install_spec_helper("RSpec::Signal.configure { |c| c.track_history = false }")

      project.run_signal

      expect(project.artifact?("history.json")).to be(false)
    end
  end

  describe "a spec file that will not load" do
    before do
      project.install_spec_helper
      project.write("spec/broken_spec.rb", %(require "definitely_not_a_real_gem"\n))
      project.write("spec/fine_spec.rb", "RSpec.describe('fine') { it('passes') { expect(1).to eq(1) } }\n")
    end

    it "does not report a suite with an unloadable file as having zero problems" do
      run = project.run_signal

      expect(run.stdout).to include("1 error outside examples")
    end

    it "writes a report even though no example failed" do
      project.run_signal

      expect(project.artifact?("signal.md")).to be(true)
    end

    it "recovers the exception, the message and the file" do
      project.run_signal

      expect(project.summary_text).to include("LoadError",
                                              "cannot load such file -- definitely_not_a_real_gem",
                                              "spec/broken_spec.rb:1")
    end

    it "gives a command that reruns the file that would not load" do
      project.run_signal

      expect(project.summary_text).to include("bundle exec rspec ./spec/broken_spec.rb")
    end

    it "publishes it as structured data too" do
      project.run_signal
      outside = project.json.fetch("outside_examples")

      expect(outside.size).to eq(1)
      expect(outside.first).to include("exception" => "LoadError")
    end

    # Registering for RSpec's message stream removes its fallback message
    # formatter, so anything we intercept and do not re-emit disappears.
    it "still prints RSpec's own account of it" do
      run = project.run_signal

      expect(run.output).to include("An error occurred while loading ./spec/broken_spec.rb")
    end

    it "does not print it twice when another formatter is also listening" do
      run = project.run_signal("--format", "progress")

      expect(run.output.scan("cannot load such file -- definitely_not_a_real_gem").size).to eq(1)
    end
  end

  describe "a dry run" do
    before do
      project.install_spec_helper
      project.write("spec/failing_spec.rb", "RSpec.describe('x') { it('fails') { expect(1).to eq(2) } }\n")
    end

    # A dry run executes nothing, so it has neither failures to report nor the
    # standing to delete the report of the run that did.
    it "leaves the previous report in place" do
      project.run_signal
      before_dry = project.read("signal.md")

      project.run_signal("--dry-run")

      expect(project.read("signal.md")).to eq(before_dry)
    end

    it "does not record itself as a run with no failures" do
      project.run_signal
      project.run_signal("--dry-run")
      history = JSON.parse(File.read(project.artifact("history.json")))

      expect(history.fetch("runs").size).to eq(1)
    end
  end

  describe "failures that share a code path but nothing else" do
    before do
      project.install_spec_helper
      project.write("lib/presenter.rb", <<~RUBY)
        class Presenter
          def initialize(record) = @record = record
          def render = { money: money, date: date }
          def money = format("%.2f", @record.amount)
          def date = @record.at.year
        end
      RUBY
      project.write("spec/presenter_spec.rb", <<~RUBY)
        $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
        require "presenter"
        Order = Struct.new(:amount, :at)
        RSpec.describe Presenter do
          it("renders without an amount") { Presenter.new(Order.new(nil, Time.now)).render }
          it("renders without a date") { Presenter.new(Order.new(1.0, nil)).render }
        end
      RUBY
    end

    it "keeps them as the two distinct failures they are" do
      project.run_signal

      expect(project.json.dig("summary", "signatures")).to eq(2)
    end

    it "reports the line both stacks run through" do
      project.run_signal

      expect(project.summary_text).to include("## Shared code paths", "lib/presenter.rb:3")
    end

    it "names it on stdout, so an agent need not open the report to know where to look" do
      run = project.run_signal

      expect(run.stdout).to include("Shared code paths: lib/presenter.rb:3 (2 signatures)")
    end

    it "publishes it as structured data" do
      project.run_signal
      shared = project.json.fetch("code_paths").find { |path| path.fetch("location") == "lib/presenter.rb:3" }

      expect(shared).to include("signature_count" => 2, "examples" => 2)
    end

    it "says nothing when the failures share no code path" do
      project.write("spec/presenter_spec.rb", <<~RUBY)
        RSpec.describe "unrelated" do
          it("one") { expect(1).to eq(2) }
          it("two") { raise ArgumentError, "different entirely" }
        end
      RUBY

      project.run_signal

      expect(project.summary_text).not_to include("Shared code paths")
    end
  end
end
