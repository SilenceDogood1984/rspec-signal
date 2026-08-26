# frozen_string_literal: true

require_relative "../support/sandbox_project"

RSpec.describe "parallel_tests support", :integration do
  let(:project) { SandboxProject.new }

  after { project.cleanup }

  before do
    project.install_spec_helper
    project.write("lib/shared_failure.rb", <<~RUBY)
      module SharedFailure
        def self.call(message = "shared failure")
          raise ArgumentError, message
        end
      end
    RUBY
  end

  it "merges distinct workers globally, remains quiet, and preserves failure status" do
    write_failure("a", "shared failure")
    write_failure("b", "shared failure")
    write_failure("c", "unrelated failure")

    run = project.run_signal_parallel("-n", "3", "spec")

    expect(run.status).not_to eq(0)
    expect(run.output.bytesize).to be < 8_000
    expect(run.output).not_to include("ArgumentError: shared failure")
    expect(project.json.dig("summary", "examples")).to eq(3)
    expect(project.json.dig("summary", "failures")).to eq(3)
    expect(project.json.fetch("signatures").map { |group| group.fetch("count") }).to contain_exactly(2, 1)
    expect(Dir[File.join(project.root, "tmp/rspec-signal/workers/*/*/signal.json")].size).to eq(3)
  end

  it "exits zero for a passing two-worker run and excludes stale failures" do
    write_failure("old", "old failure")
    project.run_signal_parallel("-n", "2", "spec")
    FileUtils.rm(File.join(project.root, "spec/old_spec.rb"))
    2.times { |index| write_passing(index) }

    run = project.run_signal_parallel("-n", "2", "spec")

    expect(run.status).to eq(0)
    expect(run.output).to include("2 examples, 0 failures across 2 workers")
    expect(project).not_to be_artifact("signal.md")
  end

  def write_failure(name, message)
    project.write("spec/#{name}_spec.rb", <<~RUBY)
      require "shared_failure"
      RSpec.describe #{name.inspect} do
        it("fails") { SharedFailure.call(#{message.inspect}) }
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
end
