# frozen_string_literal: true

require_relative "../support/sandbox_project"

RSpec.describe "parallel_tests support", :integration do
  let(:project) { SandboxProject.new }

  after { project.cleanup }

  before { project.install_spec_helper }

  it "merges exact signatures across three isolated workers" do
    write_shared_failure
    write_failure("a", "shared failure")
    write_failure("b", "shared failure")
    write_failure("c", "unrelated failure")

    run = project.run_signal_parallel("-n", "3", "spec")

    expect(run.status).not_to eq(0)
    expect(project.json.dig("summary", "examples")).to eq(3)
    expect(project.json.fetch("signatures").map { |group| group.fetch("count") }).to contain_exactly(2, 1)
    expect(worker_artifacts.size).to eq(3)
  end

  it "clusters related but non-identical failures from separate workers" do
    write_missing_method("a", prefix: "first")
    write_missing_method("b", prefix: "second")

    project.run_signal_parallel("-n", "2", "spec")

    related = project.json.fetch("related")
    expect(project.json.dig("summary", "failures")).to eq(2)
    expect(project.json.fetch("signatures").size).to eq(2)
    expect(related.size).to eq(1)
    expect(related.first.fetch("count")).to eq(2)
  end

  it "keeps a huge worker failure out of parent output" do
    project.write("spec/noisy_spec.rb", <<~RUBY)
      RSpec.describe "noise" do
        it "fails quietly" do
          noise = (1..2_000).map { |number| "parallel raw noise line \#{number}" }.join("\\n")
          raise ArgumentError, "useful parallel diagnostic\\n\#{noise}"
        end
      end
    RUBY
    write_passing(1)

    run = project.run_signal_parallel("-n", "2", "spec")

    expect(run.status).not_to eq(0)
    expect(run.output.bytesize).to be < 8_000
    expect(run.output).not_to include("parallel raw noise line 1000", "useful parallel diagnostic")
    expect(project.read("signal.md")).to include("useful parallel diagnostic")
  end

  it "fails aggregation and warns when a worker artifact disappears" do
    install_artifact_sabotage
    write_passing(1)
    write_passing(2)

    run = project.run_signal_parallel("-n", "2", "spec", env: { "SIGNAL_ARTIFACT_SABOTAGE" => "missing" })

    expect(run.status).not_to eq(0)
    expect(run.output).to include("worker artifacts were missing", "report is incomplete")
  end

  it "fails aggregation and warns when a worker artifact is corrupt" do
    install_artifact_sabotage
    write_passing(1)
    write_passing(2)

    run = project.run_signal_parallel("-n", "2", "spec", env: { "SIGNAL_ARTIFACT_SABOTAGE" => "corrupt" })

    expect(run.status).not_to eq(0)
    expect(run.output).to include("parallel report aggregation failed", "JSON::ParserError")
    expect(project).not_to be_artifact("signal.md")
  end

  it "merges full output in deterministic worker order when enabled" do
    project.install_spec_helper("RSpec::Signal.configuration.write_full = true")
    write_shared_failure
    write_failure("a", "first full failure")
    write_failure("b", "second full failure")

    project.run_signal_parallel("-n", "2", "spec")

    full = project.read("full.txt")
    expect(project).to be_artifact("full.txt")
    expect(full).to include("first full failure", "second full failure")
    expect(Dir[File.join(project.root, "tmp/rspec-signal/workers/*/*/full.txt")]).to be_empty
  end

  it "rejects inconsistent aggregation configuration between workers" do
    project.install_spec_helper(<<~RUBY)
      RSpec::Signal.configuration.max_groups = ENV.fetch("TEST_ENV_NUMBER", "1").to_i
    RUBY
    write_passing(1)
    write_passing(2)

    run = project.run_signal_parallel("-n", "2", "spec")

    expect(run.status).not_to eq(0)
    expect(run.output).to include("inconsistent rspec-signal configuration")
  end

  it "exits zero for a passing two-worker run and excludes stale failures" do
    write_shared_failure
    write_failure("old", "old failure")
    project.run_signal_parallel("-n", "2", "spec")
    FileUtils.rm(File.join(project.root, "spec/old_spec.rb"))
    2.times { |index| write_passing(index) }

    run = project.run_signal_parallel("-n", "2", "spec")

    expect(run.status).to eq(0)
    expect(run.output).to include("2 examples, 0 failures across 2 workers")
    expect(project).not_to be_artifact("signal.md")
  end

  def write_shared_failure
    project.write("lib/shared_failure.rb", <<~RUBY)
      module SharedFailure
        def self.call(message)
          raise ArgumentError, message
        end
      end
    RUBY
  end

  def write_failure(name, message)
    project.write("spec/#{name}_spec.rb", <<~RUBY)
      require "shared_failure"
      RSpec.describe #{name.inspect} do
        it("fails") { SharedFailure.call(#{message.inspect}) }
      end
    RUBY
  end

  def write_missing_method(name, prefix:)
    project.write("spec/#{name}_spec.rb", <<~RUBY)
      RSpec.describe #{name.inspect} do
        it("fails") do
          value = nil
          value.progress(#{prefix.inspect})
        end
      end
    RUBY
  end

  def write_passing(index)
    project.write("spec/pass_#{index}_spec.rb", <<~RUBY)
      RSpec.describe "pass #{index}" do
        it("passes") { expect(true).to be(true) }
      end
    RUBY
  end

  def worker_artifacts
    Dir[File.join(project.root, "tmp/rspec-signal/workers/*/*/signal.json")]
  end

  def install_artifact_sabotage
    project.install_spec_helper(<<~RUBY)
      module ArtifactSabotage
        def write_worker(report, config)
          super

          worker = RSpec::Signal::ParallelRun.worker_id
          pointer = File.join(ENV.fetch("RSPEC_SIGNAL_RUN_REGISTRY"), "\#{worker}.path")
          artifact = File.read(pointer).strip
          File.delete(artifact) if ENV["SIGNAL_ARTIFACT_SABOTAGE"] == "missing"
          File.write(artifact, "{corrupt") if ENV["SIGNAL_ARTIFACT_SABOTAGE"] == "corrupt"
        end
      end
      RSpec::Signal::ParallelRun.singleton_class.prepend(ArtifactSabotage)
    RUBY
  end
end
