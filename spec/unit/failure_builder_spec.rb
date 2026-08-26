# frozen_string_literal: true

RSpec.describe RSpec::Signal::FailureBuilder do
  let(:config) { signal_config }
  let(:builder) { described_class.new(config) }

  # A stand-in for RSpec's FailedExampleNotification, carrying only the parts
  # the builder actually reads.
  def notification(exception:, message_lines:, metadata: {}, location: "./spec/models/user_spec.rb:27",
                   description: "User#full_name joins the parts", raw: "  1) raw output")
    example = instance_double(
      RSpec::Core::Example,
      full_description: description,
      location: location,
      location_rerun_argument: location.sub("./", ""),
      id: "#{location.sub(/:\d+\z/, "")}[1:1]",
      metadata: { rspec_signal_diagnostics: nil }.merge(metadata)
    )

    instance_double(
      RSpec::Core::Notifications::FailedExampleNotification,
      example: example, exception: exception, message_lines: message_lines,
      fully_formatted: raw
    )
  end

  def error(klass, message, backtrace)
    klass.new(message).tap { |e| e.set_backtrace(backtrace) }
  end

  describe "a normal failure" do
    subject(:failure) do
      builder.call(
        notification(
          exception: error(ArgumentError, "wrong number of arguments", Backtraces.pure_ruby),
          message_lines: ["Failure/Error: calculator.total", "", "ArgumentError:", "  wrong number of arguments"]
        ),
        position: 1
      )
    end

    it "captures the full example description" do
      expect(failure.description).to eq("User#full_name joins the parts")
    end

    it "captures the spec location relative to the project" do
      expect(failure.spec_location).to eq("spec/models/user_spec.rb:27")
    end

    it "captures the exception class" do
      expect(failure.exception_class).to eq("ArgumentError")
    end

    it "captures the message" do
      expect(failure.message.text).to include("wrong number of arguments")
    end

    it "reduces the backtrace" do
      expect(failure.reduced.kept_count).to be < 5
      expect(failure.reduced.omitted_count).to be > 40
    end

    it "captures a rerun argument" do
      expect(failure.rerun).to eq("spec/models/user_spec.rb:27")
    end

    it "preserves the original output" do
      expect(failure.raw).to eq("  1) raw output")
    end
  end

  describe "an anonymous exception class" do
    it "does not blow up" do
      failure = builder.call(
        notification(exception: error(Class.new(StandardError), "boom", []), message_lines: ["boom"]),
        position: 1
      )

      expect(failure.exception_class).to eq("(anonymous error class)")
    end
  end

  describe "an exception with no backtrace" do
    it "still produces a usable failure" do
      exception = ArgumentError.new("boom")
      failure = builder.call(notification(exception: exception, message_lines: ["boom"]), position: 1)

      expect(failure.reduced).to be_empty
      expect(failure.spec_location).to eq("spec/models/user_spec.rb:27")
    end
  end

  describe "Rails system test screenshots" do
    # Stands in for Capybara::ElementNotFound without depending on Capybara.
    subject(:failure) do
      builder.call(
        notification(
          exception: error(element_not_found_class, "Unable to find css",
                           Backtraces.capybara_element_not_found),
          message_lines: ["Failure/Error: expect(page).to have_css", "", "Unable to find css", "",
                          "[Screenshot Image]: /srv/app/tmp/screenshots/failures_reader.png", ""],
          metadata: { extra_failure_lines: ["", "[Screenshot Image]: /srv/app/tmp/screenshots/failures_reader.png",
                                            ""] }
        ),
        position: 1
      )
    end

    let(:element_not_found_class) { stub_const("Capybara::ElementNotFound", Class.new(StandardError)) }

    it "extracts the screenshot path as a diagnostic" do
      expect(failure.diagnostics[:screenshot]).to eq("tmp/screenshots/failures_reader.png")
    end

    it "keeps the screenshot noise out of the message body" do
      expect(failure.message.text).not_to include("[Screenshot Image]")
      expect(failure.message.text).to include("Unable to find css")
    end
  end

  describe "diagnostics captured by the Capybara integration" do
    it "are carried through and scrubbed" do
      failure = builder.call(
        notification(
          exception: error(RuntimeError, "boom", []),
          message_lines: ["boom"],
          metadata: { rspec_signal_diagnostics: { url: "https://app.test/x?access_token=SEKRET" } }
        ),
        position: 1
      )

      expect(failure.diagnostics[:url]).to eq("https://app.test/x?access_token=[REDACTED]")
    end
  end

  describe "redaction" do
    it "scrubs the message" do
      failure = builder.call(
        notification(exception: error(RuntimeError, "boom", []), message_lines: ["password: 'hunter2'"]),
        position: 1
      )

      expect(failure.message.text).to include("[REDACTED]")
    end

    it "scrubs the preserved original output too" do
      failure = builder.call(
        notification(exception: error(RuntimeError, "boom", []), message_lines: ["boom"],
                     raw: "  1) token = ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        position: 1
      )

      expect(failure.raw).to include("[REDACTED]")
    end
  end
end
