# frozen_string_literal: true

require "json"
require_relative "../support/sandbox_project"

# Installing the experimental relationship layer must not change the product
# unless it is switched on.
#
# The baseline in spec/fixtures/disabled_mode/ was recorded by this spec at the
# commit before the layer existed (RSPEC_SIGNAL_RECORD_BASELINE=1). This spec
# runs the same suite with `causal_analysis` off and requires the same
# terminal summary, signal.md, signal.json and history.json, after
# normalizing only what varies by clock, run id, or Ruby and RSpec version.
module DisabledModeFixture
  BASELINE = File.expand_path("../fixtures/disabled_mode", __dir__)

  # Failures whose messages read the same on every Ruby and RSpec in CI: a
  # hook, an ENV key at two call sites, a missing constant, one error raised
  # inside a gem from three spec lines, and a plain assertion.
  FILES = {
    "vendor/gems/fakebot-6.4.0/lib/fakebot.rb" => <<~RUBY,
      module FakeBot
        class RecordInvalid < StandardError; end
        def self.create(_name, overrides = {})
          raise RecordInvalid, "Validation failed: Organization must exist" unless overrides[:organization]
        end
      end
    RUBY
    "lib/session.rb" => <<~RUBY,
      class Session
        def self.sign_in
          raise "session store is not configured"
        end
      end
    RUBY
    "lib/payments.rb" => <<~RUBY,
      module Payments
        def self.key
          ENV.fetch("RSPEC_SIGNAL_DISABLED_MODE_KEY")
        end
      end
    RUBY
    "lib/webhooks.rb" => <<~RUBY,
      module Webhooks
        def self.secret
          ENV.fetch("RSPEC_SIGNAL_DISABLED_MODE_KEY")
        end
      end
    RUBY
    "lib/billing.rb" => "module Billing\n  def self.rate\n    TaxRate.rate\n  end\nend\n",
    "spec/admin_spec.rb" => <<~RUBY,
      require "session"
      RSpec.describe "Admin" do
        before { Session.sign_in }
        it("lists") { expect(1).to eq(1) }
        it("exports") { expect(1).to eq(1) }
      end
    RUBY
    "spec/keys_spec.rb" => <<~RUBY,
      require "payments"
      require "webhooks"
      RSpec.describe "Keys" do
        it("charges") { expect(Payments.key).to be_a(String) }
        it("verifies") { expect(Webhooks.secret).to be_a(String) }
      end
    RUBY
    "spec/billing_spec.rb" => "require \"billing\"\nRSpec.describe \"Billing\" do\n  " \
                              "it(\"has a rate\") { expect(Billing.rate).to eq(0.1) }\nend\n",
    "spec/users_spec.rb" => <<~RUBY,
      $LOAD_PATH.unshift(File.expand_path("../vendor/gems/fakebot-6.4.0/lib", __dir__))
      require "fakebot"
      RSpec.describe "Users" do
        let(:user) { FakeBot.create(:user) }
        it("has a name") { expect(user).to be_truthy }
        it("signs in") { expect(FakeBot.create(:user, role: :admin)).to be_truthy }
        it("joins a team") { FakeBot.create(:user, team: 1) }
      end
    RUBY
    "spec/math_spec.rb" => "RSpec.describe \"Math\" do\n  it(\"adds\") { expect(1 + 1).to eq(3) }\nend\n",
    "spec/filler_spec.rb" => "RSpec.describe \"Filler\" do\n" \
                             "#{Array.new(12) { |i| "  it(\"passes #{i}\") { expect(#{i}).to eq(#{i}) }\n" }.join}end\n"
  }.freeze
end

RSpec.describe "with relationships switched off", :integration do
  def sandbox(causal)
    project = SandboxProject.new
    line = causal.nil? ? "" : "RSpec::Signal.configure { |config| config.causal_analysis = #{causal} }"
    project.install_spec_helper(line)
    DisabledModeFixture::FILES.each { |path, contents| project.write(path, contents) }
    yield project
  ensure
    project&.cleanup
  end

  def normalize_stdout(text)
    text.lines.map(&:rstrip).reject(&:empty?).map { |line| line.sub(/\(\d+ backtrace frames omitted\)/, "(N omitted)") }
  end

  # The meta line holds versions and a duration, the reduction line and the
  # traces count framework frames: all vary by Ruby and RSpec, none is ours.
  def normalize_markdown(text)
    text.gsub(/^seed .*$|^\d+(?:\.\d+)?s \| .*$|^ruby .* \| rspec-signal .*$/, "[meta]")
        .gsub(/^Backtraces reduced from .*$/, "[reduction]")
        .gsub(/\*\*Trace\*\*\n\n```text\n.*?```/m, "**Trace**\n\n[trace]")
  end

  def normalize_json(data)
    data = data.reject { |key, _| %w[environment backtrace_reduction run_id].include?(key) }
    data["summary"] = data["summary"].reject { |key, _| %w[duration_seconds seed].include?(key) }
    data["since_last_run"] = data["since_last_run"].reject { |key, _| key.start_with?("previous_run", "previous_at") } \
      if data["since_last_run"]
    data["signatures"] = data["signatures"].map do |signature|
      signature.merge("representative" => signature["representative"].reject do |key, _|
        %w[trace omitted_frames].include?(key)
      end)
    end
    data
  end

  def normalize_history(text)
    JSON.parse(text)["runs"].map { |run| run.reject { |key, _| %w[run_id at].include?(key) } }
  end

  # Two runs, so the second can say what changed since the first.
  def outputs(causal)
    sandbox(causal) do |project|
      project.run_signal
      project.write("spec/math_spec.rb", "RSpec.describe \"Math\" do\n  it(\"adds\") { expect(1 + 1).to eq(2) }\nend\n")
      second = project.run_signal
      { "stdout.json" => normalize_stdout(second.stdout),
        "signal.md" => normalize_markdown(project.read("signal.md")),
        "signal.json" => normalize_json(project.json),
        "history.json" => normalize_history(project.read("history.json")) }
    end
  end

  # JSON is compared as data: how a json gem lays out an empty array is not
  # the product's output.
  def baseline(name)
    text = File.read(File.join(DisabledModeFixture::BASELINE, name))
    name.end_with?(".json") ? JSON.parse(text) : text
  end

  def serialize(name, value)
    name.end_with?(".json") ? "#{JSON.pretty_generate(value)}\n" : value
  end

  it "reproduces the output of the product before the layer existed" do
    actual = outputs(ENV["RSPEC_SIGNAL_RECORD_BASELINE"] ? nil : false)

    if ENV["RSPEC_SIGNAL_RECORD_BASELINE"]
      FileUtils.mkdir_p(DisabledModeFixture::BASELINE)
      actual.each { |name, value| File.write(File.join(DisabledModeFixture::BASELINE, name), serialize(name, value)) }
    end

    actual.each do |name, value|
      expect(value).to eq(baseline(name)), "#{name} changed"
    end
  end

  it "adds nothing of its own to any artifact" do
    actual = outputs(false)

    expect(actual["signal.json"]).not_to have_key("analysis")
    expect(actual["signal.md"]).not_to include("Relationships")
    expect(actual["stdout.json"].join("\n")).not_to include("Relationships", "CAUSAL", "SCOPE", "classified")
  end

  it "is what a project gets without configuring anything" do
    expect(outputs(nil)).to eq(outputs(false))
  end

  it "adds nothing to a parallel run either" do
    sandbox(false) do |project|
      run = project.run_signal_parallel("spec", "-n", "2")

      expect(project.json).not_to have_key("analysis")
      expect(run.stdout).not_to include("Relationships")
    end
  end
end
