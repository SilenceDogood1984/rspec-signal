# frozen_string_literal: true

RSpec.describe "exception causes" do
  let(:config) { signal_config }
  let(:builder) { RSpec::Signal::FailureBuilder.new(config) }
  let(:root_cause) do
    raised(ArgumentError, 'duplicate key value violates unique constraint "index_users_on_email"',
           Backtraces.active_record_invalid)
  end
  let(:wrapper) { raised(RuntimeError, "could not create the subscription", Backtraces.pure_ruby, cause: root_cause) }

  def raised(klass, message, backtrace, cause: nil)
    error = klass.new(message)
    error.set_backtrace(backtrace)
    # `cause` is only set by `raise` inside a rescue, so it has to be forced.
    error.define_singleton_method(:cause) { cause }
    error
  end

  def build(exception, message_lines: ["Failure/Error: creator.call"])
    example = instance_double(
      RSpec::Core::Example,
      full_description: "an example", location: "./spec/a_spec.rb:3",
      location_rerun_argument: "spec/a_spec.rb:3", id: "spec/a_spec.rb[1:1]", metadata: {}
    )
    notification = instance_double(
      RSpec::Core::Notifications::FailedExampleNotification,
      example: example, exception: exception, message_lines: message_lines, fully_formatted: "raw"
    )
    builder.call(notification, position: 1)
  end

  # RSpec keeps the cause chain in the backtrace, which is exactly what gets
  # reduced away. It is usually the answer, so it has to survive.
  it "surfaces the root cause in the message" do
    expect(build(wrapper).message.text).to include("Caused by ArgumentError:",
                                                   "duplicate key value violates unique constraint")
  end

  it "points at the first-party frame inside the cause" do
    expect(build(wrapper).message.text).to include("at app/services/subscription_creator.rb:42")
  end

  it "keeps the original failure message too" do
    expect(build(wrapper).message.text).to include("Failure/Error: creator.call")
  end

  it "makes the cause part of the signature" do
    other_cause = raised(ArgumentError, "connection reset by peer", Backtraces.library_only)
    other = raised(RuntimeError, "could not create the subscription", Backtraces.pure_ruby, cause: other_cause)

    expect(RSpec::Signal::Grouper.call([build(wrapper), build(other)]).size).to eq(2)
  end

  it "follows a chain of causes" do
    middle = raised(IOError, "middle layer", Backtraces.pure_ruby, cause: root_cause)
    outer = raised(RuntimeError, "outer layer", Backtraces.pure_ruby, cause: middle)

    expect(build(outer).message.text).to include("Caused by IOError:", "Caused by ArgumentError:")
  end

  it "stops at a bounded depth" do
    deepest = raised(RuntimeError, "level 0", [])
    chained = (1..10).inject(deepest) { |cause, i| raised(RuntimeError, "level #{i}", [], cause: cause) }

    causes = build(chained).message.text.scan("Caused by").size
    expect(causes).to eq(RSpec::Signal::FailureBuilder::MAX_CAUSE_DEPTH)
  end

  it "survives a self-referential cause" do
    looping = raised(RuntimeError, "loop", [])
    looping.define_singleton_method(:cause) { self }

    expect { build(looping) }.not_to raise_error
  end

  it "adds nothing when there is no cause" do
    expect(build(raised(RuntimeError, "plain", Backtraces.pure_ruby)).message.text).not_to include("Caused by")
  end
end
