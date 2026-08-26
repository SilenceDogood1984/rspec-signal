# frozen_string_literal: true

require_relative "../support/sandbox_project"

RSpec.describe "a real rspec run", :integration do
  let(:project) { SandboxProject.new }

  after { project.cleanup }

  describe "a pure Ruby project with no Rails" do
    let(:run) do
      project.install_spec_helper
      project.write("lib/calculator.rb", <<~RUBY)
        class Calculator
          def total(items) = items.sum { |item| price_of(item) }
          def price_of(item) = item.fetch(:price)
        end
      RUBY
      project.write("spec/calculator_spec.rb", <<~RUBY)
        require "calculator"

        RSpec.describe Calculator do
          it "adds up prices" do
            expect(subject.total([{ price: 1 }, { price: 2 }])).to eq(4)
          end

          it "raises on a missing price" do
            subject.total([{ name: "no price" }])
          end

          it "passes" do
            expect(subject.total([{ price: 5 }])).to eq(5)
          end
        end
      RUBY
      project.run
    end

    it "still reports failures normally on the terminal" do
      expect(run.stdout).to include("3 examples, 2 failures")
      expect(run.status).to eq(1)
    end

    it "keeps the default progress formatter, which it displaced" do
      expect(run.stdout).to match(/^\.?F/)
    end

    it "adds its own two-line summary" do
      expect(run.stdout).to include("rspec-signal: 2 failures in 2 distinct signatures")
      expect(run.stdout).to include("AI report: tmp/rspec-signal/summary.md")
    end

    it "writes the artifacts" do
      run
      expect(project).to be_artifact("summary.md")
      expect(project).to be_artifact("signal.json")
      expect(project).to be_artifact("full.txt")
    end

    it "records the matcher failure with expected and actual" do
      expect(run.summary).to include("expected: 4", "got: 3")
    end

    it "records the exception failure with its class and message" do
      expect(run.summary).to include("KeyError", "key not found: :price")
    end

    it "points at first-party code, not at rspec internals" do
      expect(run.summary).to include("lib/calculator.rb:3")
      expect(run.summary).not_to match(/rspec-core|rspec-expectations|bundler/)
    end

    it "gives a rerun command that works" do
      run
      rerun = run.summary[/bundle exec rspec (\S+)/, 1]
      second = project.run(rerun)

      expect(second.stdout).to include("1 example, 1 failure")
    end
  end

  describe "a Rails-shaped project" do
    let(:run) do
      project.install_spec_helper
      project.write("app/services/subscription_creator.rb", <<~RUBY)
        class SubscriptionCreator
          def call(email) = validate!(email)

          def validate!(email)
            raise ArgumentError, "Validation failed: Email has already been taken" if email.to_s.empty?

            email
          end
        end
      RUBY
      project.write("spec/services/subscription_creator_spec.rb", <<~RUBY)
        require "services/subscription_creator"

        RSpec.describe SubscriptionCreator do
          %w[alpha beta gamma].each do |name|
            it "creates a subscription for \#{name}" do
              subject.call("")
            end
          end
        end
      RUBY
      project.write("spec/spec_helper_paths.rb", "")
      project.run("-I", "app")
    end

    it "collapses the repeated root cause into one signature" do
      expect(run.stdout).to include("rspec-signal: 3 failures in 1 distinct signature")
    end

    it "keeps every affected example" do
      run
      expect(run.summary).to include("**Also failing identically (2)**")
      expect(project.json["signatures"].first["affected"].size).to eq(3)
    end

    it "names the application code that raised" do
      expect(run.summary).to include("app/services/subscription_creator.rb:5")
    end

    it "shows the application call chain" do
      expect(run.summary).to include("app/services/subscription_creator.rb:2")
    end
  end

  describe "artifact hygiene" do
    before do
      project.install_spec_helper
      project.write("spec/flaky_spec.rb", <<~RUBY)
        RSpec.describe "conditionally failing" do
          it "fails only when asked" do
            expect(ENV["SHOULD_FAIL"]).to be_nil
          end
        end
      RUBY
    end

    it "removes a stale report once the suite goes green" do
      project.write("spec/broken_spec.rb", 'RSpec.describe("x") { it("fails") { expect(1).to eq(2) } }')
      project.run
      expect(project).to be_artifact("summary.md")

      FileUtils.rm(File.join(project.root, "spec/broken_spec.rb"))
      run = project.run

      expect(run.stdout).to include("0 failures")
      expect(project).not_to be_artifact("summary.md")
    end

    it "writes a gitignore so artifacts are not committed by accident" do
      project.write("spec/broken_spec.rb", 'RSpec.describe("x") { it("fails") { expect(1).to eq(2) } }')
      project.run

      expect(File.read(File.join(project.root, "tmp/rspec-signal/.gitignore"))).to include("*")
    end
  end

  describe "opting out" do
    before do
      project.install_spec_helper("RSpec::Signal.configuration.enabled = false")
      project.write("spec/broken_spec.rb", 'RSpec.describe("x") { it("fails") { expect(1).to eq(2) } }')
    end

    it "writes nothing and says nothing" do
      run = project.run

      expect(run.stdout).to include("1 example, 1 failure")
      expect(run.stdout).not_to include("rspec-signal:")
      expect(project).not_to be_artifact("summary.md")
    end
  end

  describe "an explicit --format" do
    before do
      project.install_spec_helper
      project.write("spec/broken_spec.rb", 'RSpec.describe("x") { it("fails") { expect(1).to eq(2) } }')
    end

    it "respects a documentation formatter instead of forcing progress" do
      run = project.run("--format", "documentation")

      expect(run.stdout).to include("fails")
      expect(run.stdout).not_to match(/^\.?F$/)
      expect(project).to be_artifact("summary.md")
    end
  end

  describe "secrets" do
    it "are scrubbed from the artifact" do
      project.install_spec_helper
      project.write("spec/secret_spec.rb", <<~RUBY)
        RSpec.describe "an api client" do
          it "sends the right header" do
            headers = { "Authorization" => "Bearer ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
            expect(headers).to eq({})
          end
        end
      RUBY
      project.run

      expect(project.read("summary.md")).to include("[REDACTED]")
      expect(project.read("summary.md")).not_to include("ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    end
  end

  describe "a wrapped exception" do
    before do
      project.install_spec_helper
      project.write("lib/importer.rb", <<~RUBY)
        class Importer
          def call
            parse
          rescue KeyError => e
            raise RuntimeError, "import failed"
          end

          def parse = { name: "x" }.fetch(:price)
        end
      RUBY
      project.write("spec/importer_spec.rb", <<~RUBY)
        require "importer"
        RSpec.describe Importer do
          it "imports" do
            subject.call
          end
        end
      RUBY
      project.run
    end

    it "keeps the root cause, which is usually the answer" do
      expect(project.read("summary.md")).to include("import failed", "Caused by KeyError:", "key not found: :price")
    end

    it "points at the first-party frame inside the cause" do
      expect(project.read("summary.md")).to include("at lib/importer.rb:8")
    end
  end

  describe "aggregated expectations" do
    it "keeps every sub-failure" do
      project.install_spec_helper
      project.write("spec/aggregate_spec.rb", <<~RUBY)
        RSpec.describe "a form" do
          it "validates", :aggregate_failures do
            expect(1).to eq(2)
            expect("a").to eq("b")
          end
        end
      RUBY
      project.run

      summary = project.read("summary.md")
      expect(summary).to include("MultipleExpectationsNotMetError")
      expect(summary).to include("got: 2").or include("expected: 2")
      expect(summary).to include('"b"')
    end
  end

  describe "reduction, measured against the real thing" do
    it "is dramatically smaller than RSpec's own failure output" do
      project.install_spec_helper
      project.write("spec/many_spec.rb", <<~RUBY)
        RSpec.describe "a suite with one broken helper" do
          def broken = raise(ArgumentError, "the shared helper is broken")

          20.times do |i|
            it "example \#{i}" do
              broken
            end
          end
        end
      RUBY

      run = project.run("--backtrace")
      signal_lines = run.summary.lines.size
      rspec_lines = run.stdout.lines.size

      expect(run.stdout).to include("20 examples, 20 failures")
      expect(signal_lines).to be < rspec_lines / 4
      expect(run.summary).to include("1 distinct signature")
    end
  end
end
