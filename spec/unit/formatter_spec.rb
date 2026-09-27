# frozen_string_literal: true

RSpec.describe RSpec::Signal::Formatter do
  let(:output) { StringIO.new }
  let(:config) { signal_config }
  let(:formatter) { described_class.new(output) }

  before do
    allow(formatter).to receive(:config).and_return(config)
  end

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

  def start_notification(count)
    instance_double(RSpec::Core::Notifications::StartNotification, count: count)
  end

  def drive(*notifications, seed: 1234, seed_used: true)
    formatter.start(start_notification(10))
    notifications.each { |notification| formatter.example_failed(notification) }
    (10 - notifications.size).times { formatter.example_passed(nil) }
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

    it "puts distinct problems and exact actions ahead of the report" do
      expect(output.string).to include("Signal problems: 2 failures, 2 distinct problems")
      expect(output.string).to include("Problem #1:", "Exact rerun: bundle exec rspec")
      expect(output.string.index("Exact rerun:")).to be < output.string.index("Report:")
    end

    it "keeps frame-count trivia out of the terminal" do
      expect(output.string).not_to include("frames omitted")
    end

    it "carries the seed into the report" do
      expect(File.read(File.join(config.output_path, "signal.md"))).to include("seed `1234`")
    end
  end

  describe "a run with no failures" do
    let(:quiet_mode) { false }

    before do
      allow(RSpec::Signal).to receive(:quiet_mode?).and_return(quiet_mode)
      drive
    end

    it "writes nothing" do
      expect(File).not_to exist(File.join(config.output_path, "signal.md"))
    end

    it "says nothing" do
      expect(output.string).to eq("")
    end

    context "when in quiet mode" do
      let(:quiet_mode) { true }

      it "prints the RSpec result without a report path" do
        expect(output.string).to include("10 examples, 0 failures, 0 pending")
        expect(output.string).not_to include("Report:", "rspec-signal:")
      end
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

  describe "quiet progress" do
    before do
      allow(RSpec::Signal).to receive(:quiet_mode?).and_return(true)
      allow(output).to receive(:tty?).and_return(tty)
    end

    context "when output is a TTY" do
      let(:tty) { true }

      it "repaints a bounded single-line bar from completed-example events" do
        formatter.start(start_notification(4))
        formatter.example_passed(nil)
        formatter.example_pending(nil)

        expect(output.string).to include("\rsignal [██████████░░░░░░░░░░] 50% 2/4")
        expect(output.string).not_to include("passed", "pending")
      end

      it "counts failures without rendering their text" do
        formatter.start(start_notification(2))
        formatter.example_failed(failure_notification(message: "giant failure " * 1_000))

        expect(output.string).to include("50% 1/2")
        expect(output.string).not_to include("giant failure")
      end
    end

    context "when stdout is not a TTY" do
      let(:tty) { false }

      it "emits no live repaint output" do
        formatter.start(start_notification(100))
        100.times { formatter.example_passed(nil) }

        expect(output.string).to eq("")
      end
    end
  end

  describe "run-start invalidation" do
    before do
      FileUtils.mkdir_p(config.output_path)
      RSpec::Signal::Writer::MANAGED.each do |name|
        File.write(File.join(config.output_path, name), "previous generation")
      end
    end

    it "removes a previous generation before execution can abort" do
      formatter.start(start_notification(1))

      expect(RSpec::Signal::Writer::MANAGED).to all(
        satisfy { |name| !File.exist?(File.join(config.output_path, name)) }
      )
    end

    it "does not mutate artifacts during a dry run" do
      allow(RSpec.configuration).to receive(:dry_run?).and_return(true)

      formatter.start(start_notification(1))

      expect(File.read(File.join(config.output_path, "signal.md"))).to eq("previous generation")
    end

    it "does not mutate artifacts when disabled" do
      allow(config).to receive(:enabled?).and_return(false)

      formatter.start(start_notification(1))

      expect(File.read(File.join(config.output_path, "signal.md"))).to eq("previous generation")
    end

    it "leaves no generation when report rendering later fails" do
      formatter.start(start_notification(1))
      formatter.example_failed(failure_notification)
      allow(RSpec::Signal::Reporters::JsonReport).to receive(:new).and_raise("render failed")

      formatter.close(nil)

      expect(RSpec::Signal::Writer::MANAGED).to all(
        satisfy { |name| !File.exist?(File.join(config.output_path, name)) }
      )
    end
  end

  # The formatter must never be the reason a suite blows up.
  describe "resilience" do
    it "survives a notification it cannot read" do
      broken = Object.new
      def broken.example
        raise(NoMethodError, "nope")
      end

      expect { drive(broken) }.not_to raise_error
    end

    it "reports internal errors rather than hiding them" do
      broken = Object.new
      def broken.example
        raise(NoMethodError, "nope")
      end
      drive(broken)

      expect(output.string).to include("rspec-signal: 1 internal error")
    end

    it "still writes a report for the failures it could read" do
      broken = Object.new
      def broken.example
        raise(NoMethodError, "nope")
      end
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

  describe "history eligibility" do
    it "records a run only after every selected example reaches a summary" do
      drive(failure_notification)
      baseline = File.read(File.join(config.output_path, "history.json"))
      interrupted = described_class.new(output)
      allow(interrupted).to receive(:config).and_return(config)
      interrupted.start(start_notification(2))
      interrupted.example_failed(failure_notification)

      interrupted.close(nil)

      expect(output.string).to include("comparison skipped (run incomplete)")
      expect(File.read(File.join(config.output_path, "history.json"))).to eq(baseline)
    end
  end
end
