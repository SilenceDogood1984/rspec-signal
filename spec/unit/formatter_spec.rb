# frozen_string_literal: true

RSpec.describe RSpec::Signal::Formatter do
  let(:output) { StringIO.new }
  let(:config) { signal_config }
  let(:formatter) { described_class.new(output) }

  before { allow(formatter).to receive(:config).and_return(config) }

  after { FileUtils.rm_rf(config.output_path) }

  def failure_notification(message: "boom", backtrace: Backtraces.pure_ruby, location: "./spec/a_spec.rb:3")
    exception = RuntimeError.new(message).tap { |e| e.set_backtrace(backtrace) }
    example = instance_double(
      RSpec::Core::Example,
      full_description: "an example", location: location,
      location_rerun_argument: location.sub("./", ""), id: "#{location}[1:1]", metadata: {}
    )
    instance_double(
      RSpec::Core::Notifications::FailedExampleNotification,
      example: example, exception: exception, message_lines: [message], fully_formatted: "raw"
    )
  end

  def summary_notification(examples: 10, failures: 1, pending: 0, errors: 0)
    instance_double(
      RSpec::Core::Notifications::SummaryNotification,
      example_count: examples, failure_count: failures, pending_count: pending,
      duration: 1.5, errors_outside_of_examples_count: errors
    )
  end

  def drive(*notifications, seed: 1234, seed_used: true)
    notifications.each { |notification| formatter.example_failed(notification) }
    formatter.dump_summary(summary_notification(failures: notifications.size))
    formatter.seed(instance_double(RSpec::Core::Notifications::SeedNotification,
                                   seed: seed, seed_used?: seed_used))
    formatter.close(nil)
  end

  describe "a run with failures" do
    before { drive(failure_notification, failure_notification(message: "different")) }

    it "writes the report" do
      expect(File).to exist(File.join(config.output_path, "signal.md"))
    end

    it "prints a two-line terminal summary" do
      expect(output.string).to include("rspec-signal: 2 failures in 2 distinct signatures")
      expect(output.string).to include("Report:")
    end

    it "reports the reduction it achieved" do
      expect(output.string).to match(/\(\d+ backtrace frames omitted\)/)
    end

    it "carries the seed into the report" do
      expect(File.read(File.join(config.output_path, "signal.md"))).to include("seed `1234`")
    end
  end

  describe "a run with no failures" do
    before { drive }

    it "writes nothing" do
      expect(File).not_to exist(File.join(config.output_path, "signal.md"))
    end

    it "says nothing" do
      expect(output.string).to eq("")
    end
  end

  describe "when disabled" do
    let(:config) { signal_config(enabled: false) }

    before { drive(failure_notification) }

    it "collects nothing and writes nothing" do
      expect(output.string).to eq("")
      expect(File).not_to exist(File.join(config.output_path, "signal.md"))
    end
  end

  describe "when the terminal summary is turned off" do
    let(:config) { signal_config(terminal_summary: false) }

    before { drive(failure_notification) }

    it "still writes the artifact but stays quiet" do
      expect(output.string).to eq("")
      expect(File).to exist(File.join(config.output_path, "signal.md"))
    end
  end

  # The formatter must never be the reason a suite blows up.
  describe "resilience" do
    it "survives a notification it cannot read" do
      broken = Object.new
      def broken.example = raise(NoMethodError, "nope")

      expect { drive(broken) }.not_to raise_error
    end

    it "reports internal errors rather than hiding them" do
      broken = Object.new
      def broken.example = raise(NoMethodError, "nope")
      drive(broken)

      expect(output.string).to include("rspec-signal: 1 internal error")
    end

    it "still writes a report for the failures it could read" do
      broken = Object.new
      def broken.example = raise(NoMethodError, "nope")
      drive(broken, failure_notification)

      expect(File.read(File.join(config.output_path, "signal.md"))).to include("an example")
    end

    it "survives a run where dump_summary never arrives" do
      formatter.example_failed(failure_notification)

      expect { formatter.close(nil) }.not_to raise_error
      expect(File).to exist(File.join(config.output_path, "signal.md"))
    end
  end

  describe "#report" do
    it "exposes the collected data" do
      formatter.example_failed(failure_notification)
      formatter.dump_summary(summary_notification(examples: 936, failures: 1))

      report = formatter.report
      expect(report.example_count).to eq(936)
      expect(report.failure_count).to eq(1)
      expect(report.group_count).to eq(1)
    end

    it "notes errors that happened outside examples" do
      formatter.dump_summary(summary_notification(failures: 0, errors: 2))

      expect(formatter.report.errors_outside_examples).to eq(2)
    end
  end
end
