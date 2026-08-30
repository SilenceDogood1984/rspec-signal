# frozen_string_literal: true

RSpec.describe RSpec::Signal::OutsideExample do
  let(:config) { signal_config }

  # Captured verbatim from a real `rspec` process. RSpec renders these through
  # its own ExceptionPresenter and sends them down the message stream, so the
  # exact shape -- leading blank line, "Did you mean?" suffix, suggestion line,
  # `# ` backtrace prefixes -- is what has to survive parsing.
  let(:load_error) do
    <<~TEXT
      #{" "}
      An error occurred while loading ./spec/broken_spec.rb. - Did you mean?
                          rspec ./spec/other_spec.rb

      Failure/Error: require "definitely_not_a_real_gem"

      LoadError:
        cannot load such file -- definitely_not_a_real_gem
      # ./spec/broken_spec.rb:1:in `<top (required)>'
    TEXT
  end

  let(:suite_hook_error) do
    <<~TEXT
      #{" "}
      An error occurred in a `before(:suite)` hook.
      Failure/Error: RSpec.configure { |c| c.before(:suite) { raise ArgumentError, "boom" } }

      ArgumentError:
        boom
      # ./spec/spec_helper.rb:4:in `block (2 levels) in <top (required)>'
    TEXT
  end

  describe ".failure?" do
    it "recognises a spec file that would not load" do
      expect(described_class.failure?(load_error)).to be(true)
    end

    it "recognises a suite hook that blew up" do
      expect(described_class.failure?(suite_hook_error)).to be(true)
    end

    # Registering for `:message` means we see filter announcements and any
    # `reporter.message` a project makes. None of those are failures.
    it "ignores RSpec's filter announcements" do
      expect(described_class.failure?("Run options: include {:focus=>true}")).to be(false)
    end

    it "ignores an arbitrary project message" do
      expect(described_class.failure?("Seeding the test database")).to be(false)
    end
  end

  describe ".build, for a spec file that would not load" do
    subject(:failure) { described_class.build(load_error, config, position: 1) }

    it "recovers the exception class" do
      expect(failure.exception_class).to eq("LoadError")
    end

    it "recovers the message" do
      expect(failure.message.summary).to eq("cannot load such file -- definitely_not_a_real_gem")
    end

    it "points at the file and line, not at rspec-core" do
      expect(failure.spec_location).to eq("spec/broken_spec.rb:1")
    end

    it "reruns the file RSpec named" do
      expect(failure.rerun_argument).to eq("./spec/broken_spec.rb")
    end

    # The suggestion is advice about a *different* file and would otherwise
    # open the message.
    it "drops the Did-you-mean suggestion from the description and the body" do
      expect(failure.description).to eq("An error occurred while loading ./spec/broken_spec.rb.")
      expect(failure.message.text).not_to include("other_spec")
    end

    it "keeps the backtrace out of the message body" do
      expect(failure.message.text).not_to include("<top (required)>")
    end
  end

  describe ".build, for a suite hook" do
    subject(:failure) { described_class.build(suite_hook_error, config) }

    it "recovers the exception and message" do
      expect(failure.exception_class).to eq("ArgumentError")
      expect(failure.message.summary).to eq("boom")
    end

    # A `before(:suite)` hook is not on the line you would target, so rerunning
    # the line would report zero examples.
    it "reruns the whole file rather than a line that defines no example" do
      expect(failure.rerun_argument).to eq("spec/spec_helper.rb")
    end
  end

  it "returns nil rather than raising on text it cannot parse" do
    expect(described_class.build(nil, config)).to be_nil
  end
end
