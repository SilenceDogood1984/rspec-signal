# frozen_string_literal: true

require_relative "../support/sandbox_project"

RSpec.describe "a real rspec run", :integration do
  let(:project) { SandboxProject.new }

  after { project.cleanup }

  describe "RSpec CLI compatibility" do
    before do
      project.install_spec_helper(<<~RUBY)
        RSpec.configure do |config|
          config.filter_run_excluding excluded_by_project: true
        end
      RUBY
      project.write(".rspec", "--require ./spec/spec_helper.rb\n--no-color\n")
      project.write("spec/example_spec.rb", <<~RUBY)
        RSpec.describe "CLI behavior" do
          it("runs the first example", :some_tag) { File.write("executed.txt", "tagged\\n", mode: "a") }
          it("runs the second example") { File.write("executed.txt", "untagged\\n", mode: "a") }
          it("honors project configuration", :excluded_by_project) { raise "must not run" }
        end
      RUBY
    end

    it "discovers the same examples as ordinary RSpec with no positional arguments" do
      ordinary = project.run
      ordinary_examples = project.recorded_examples
      project.clear_recorded_examples
      signal = project.run_signal

      expect(ordinary.status).to eq(0)
      expect(signal.status).to eq(0)
      expect(ordinary.output).to include("2 examples, 0 failures")
      expect(project.recorded_examples).to contain_exactly(*ordinary_examples)
    end

    it "runs an explicit spec path" do
      run = project.run_signal("spec/example_spec.rb")

      expect(run.status).to eq(0)
      expect(project.recorded_examples).to contain_exactly("tagged", "untagged")
    end

    it "supports file and line targeting" do
      run = project.run_signal("spec/example_spec.rb:2")

      expect(run.status).to eq(0)
      expect(project.recorded_examples).to eq(["tagged"])
    end

    it "passes ordinary RSpec options through unchanged" do
      run = project.run_signal("--tag", "some_tag")

      expect(run.status).to eq(0)
      expect(project.recorded_examples).to eq(["tagged"])
    end

    it "does not change ordinary RSpec failure status or output" do
      project.write("spec/failing_spec.rb", 'RSpec.describe("failure") { it("fails") { expect(1).to eq(2) } }')

      run = project.run

      expect(run.status).to eq(1)
      expect(run.output).to include("Failures:", "3 examples, 1 failure")
    end
  end

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
      expect(run.stdout).to include("Report: tmp/rspec-signal/signal.md")
    end

    it "writes the artifacts" do
      run
      expect(project).to be_artifact("signal.md")
      expect(project).to be_artifact("signal.json")
      expect(project).not_to be_artifact("full.txt")
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
      expect(project).to be_artifact("signal.md")

      FileUtils.rm(File.join(project.root, "spec/broken_spec.rb"))
      run = project.run

      expect(run.stdout).to include("0 failures")
      expect(project).not_to be_artifact("signal.md")
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
      expect(project).not_to be_artifact("signal.md")
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
      expect(project).to be_artifact("signal.md")
    end
  end

  describe "quiet agent mode" do
    before do
      project.install_spec_helper
      project.write("spec/noisy_spec.rb", <<~RUBY)
        RSpec.describe "a noisy failure" do
          it "retains the useful exception" do
            noise = (1..2_000).map { |number| "framework/runtime noise line \#{number}" }.join("\\n")
            raise ArgumentError, "useful diagnostic: invalid reader state\\n\#{noise}"
          end
        end
      RUBY
    end

    it "keeps process output compact, preserves failure status, and writes compact artifacts" do
      run = project.run_signal

      expect(run.status).to eq(1)
      expect(run.output.bytesize).to be < 2_000
      expect(run.output).to include("1 examples, 1 failures", "Report: tmp/rspec-signal/signal.md")
      expect(run.output).not_to include("framework/runtime noise line 1000", "useful diagnostic")
    end

    it "writes compact artifacts without the full output by default" do
      project.run_signal

      expect(project).to be_artifact("signal.md")
      expect(project).to be_artifact("signal.json")
      expect(project).not_to be_artifact("full.txt")
      expect(project.read("signal.md")).to include("ArgumentError", "useful diagnostic: invalid reader state")
    end

    it "does not register a duplicate formatter or verbose output" do
      run = project.run_signal

      expect(run.output.scan("rspec-signal:").size).to eq(1)
      expect(run.output).not_to include("Failures:", "Failed examples:")
    end

    it "preserves a passing suite's zero exit status" do
      project.write("spec/noisy_spec.rb", 'RSpec.describe("green") { it("passes") { expect(1).to eq(1) } }')

      expect(project.run_signal.status).to eq(0)
    end

    it "allows full output to be opted in" do
      project.install_spec_helper("RSpec::Signal.configuration.write_full = true")
      project.run_signal

      expect(project.read("full.txt")).to include("framework/runtime noise line 1000")
    end

    it "keeps the fully qualified formatter interface quiet" do
      run = project.run("--format", "RSpec::Signal::Formatter")

      expect(run.output.bytesize).to be < 2_000
      expect(run.output).not_to include("Failures:", "Failed examples:")
    end

    it "leaves normal mode verbose and failing" do
      run = project.run

      expect(run.status).to eq(1)
      expect(run.output).to include("Failures:", "framework/runtime noise line 1000")
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

      expect(project.read("signal.md")).to include("[REDACTED]")
      expect(project.read("signal.md")).not_to include("ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
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
      expect(project.read("signal.md")).to include("import failed", "Caused by KeyError:", "key not found: :price")
    end

    it "points at the first-party frame inside the cause" do
      expect(project.read("signal.md")).to include("at lib/importer.rb:8")
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

      summary = project.read("signal.md")
      expect(summary).to include("MultipleExpectationsNotMetError")
      expect(summary).to include("got: 2").or include("expected: 2")
      expect(summary).to include('"b"')
    end
  end

  # The behaviour the real-world run exposed: a handful of specs failing for
  # obviously connected reasons, which are nevertheless not the same failure.
  describe "failures that are related but not identical" do
    let(:run) do
      project.install_spec_helper
      project.write("app/reader.rb", <<~RUBY)
        class Reader
          def self.current = nil
        end
      RUBY
      project.write("spec/reader_progress_spec.rb", <<~RUBY)
        require "reader"

        RSpec.describe "reader progress" do
          it "shows a percentage" do
            Reader.current.progress
          end
        end
      RUBY
      project.write("spec/reader_layout_spec.rb", <<~RUBY)
        require "reader"

        RSpec.describe "reader layout" do
          it "renders the bar" do
            value = Reader.current
            value.progress
          end
        end
      RUBY
      project.run("-I", "app")
    end

    it "keeps them as separate signatures" do
      expect(run.stdout).to include("2 failures in 2 distinct signatures")
    end

    it "reports one related cluster on the terminal too" do
      expect(run.stdout).to include("1 related cluster")
    end

    it "explains the shared symptom in the report" do
      expect(run.summary).to include("## Related failures", "Undefined method `progress` on nil")
    end

    it "points the reader from the cluster back at the signatures" do
      expect(run.summary).to match(/- Signatures: #\d+, #\d+/)
    end

    it "publishes the cluster in the JSON artifact" do
      run
      related = project.json.fetch("related")

      expect(related.size).to eq(1)
      expect(related.first["signatures"].size).to eq(2)
    end
  end

  describe "an enormous HTML response body" do
    let(:run) do
      project.install_spec_helper
      project.write("spec/reader_completion_spec.rb", <<~'RUBY')
        RSpec.describe "reader completion" do
          def error_page
            css = Array.new(400) { |i| "  .line-#{i} { font-family: monospace; padding: 0; }" }.join("\n")
            <<~HTML
              <!DOCTYPE html>
              <html>
              <head><title>Action Controller: Exception caught</title>
              <style>
              #{css}
              </style></head>
              <body><h1>NoMethodError in ReaderController#show</h1>
              <h2>undefined method 'progress' for nil</h2></body>
              </html>
            HTML
          end

          it "shows the finished notice" do
            expect(error_page).to include("You've finished this document.")
          end
        end
      RUBY
      project.run
    end

    it "keeps the expected value" do
      expect(run.summary).to include("You've finished this document.")
    end

    it "says the actual value was HTML, and how much of it there was" do
      expect(run.summary).to match(/\[HTML document: [\d,]+ lines, \d+ KB -- markup omitted\]/)
    end

    it "extracts the facts that diagnose it" do
      expect(run.summary).to include("Title: Action Controller: Exception caught",
                                     "Message: undefined method 'progress' for nil")
    end

    it "prints none of the exception page's CSS" do
      expect(run.summary).not_to include("font-family", ".line-1")
    end

    it "leaves the report small, where RSpec's own output is not" do
      expect(run.summary.lines.size).to be < 60
      expect(run.stdout.lines.size).to be > 400
    end

    it "does not write the untouched output by default" do
      run
      expect(project).not_to be_artifact("full.txt")
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
