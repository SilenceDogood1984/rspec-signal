# frozen_string_literal: true

RSpec.describe RSpec::Signal::Integrations::Capybara do
  let(:config) { signal_config }

  def example_double(exception: RuntimeError.new("boom"), metadata: { type: :system })
    metadata = metadata.dup
    instance_double(RSpec::Core::Example, exception: exception, metadata: metadata)
  end

  # Capybara is not a dependency of this gem, so both the session and the
  # module itself are stood up by hand.
  def session_double(**overrides)
    defaults = {
      current_url: "https://app.test/library", current_path: "/library",
      title: "Library", status_code: 200, html: "<html></html>", driver: nil
    }
    double("Capybara::Session", **defaults, **overrides) # rubocop:disable RSpec/VerifiedDoubles
  end

  def fake_capybara(pool: {}, session: nil)
    stub_const("Capybara", Module.new do
      class << self
        attr_accessor :stub_session

        def current_session = stub_session
        def current_driver = :selenium_chrome_headless
      end
    end)
    Capybara.stub_session = session
    Capybara.instance_variable_set(:@session_pool, pool)
    Capybara
  end

  def with_session(session)
    fake_capybara(pool: { default: session }, session: session)
    yield
  end

  describe ".relevant?" do
    it "applies to system specs" do
      expect(described_class).to be_relevant(example_double(metadata: { type: :system }))
    end

    it "applies to feature specs" do
      expect(described_class).to be_relevant(example_double(metadata: { type: :feature }))
    end

    it "applies to anything marked js" do
      expect(described_class).to be_relevant(example_double(metadata: { js: true }))
    end

    it "does not apply to model specs" do
      expect(described_class).not_to be_relevant(example_double(metadata: { type: :model }))
    end
  end

  describe ".capture" do
    it "records the browser state on a failing system spec" do
      example = example_double
      session = session_double

      with_session(session) { described_class.capture(example, config) }

      expect(example.metadata[:rspec_signal_diagnostics]).to include(
        url: "https://app.test/library", path: "/library", title: "Library", status_code: 200
      )
    end

    it "does nothing when the example passed" do
      example = example_double(exception: nil)

      with_session(session_double) { described_class.capture(example, config) }

      expect(example.metadata[:rspec_signal_diagnostics]).to be_nil
    end

    it "does nothing for a non-browser spec" do
      example = example_double(metadata: { type: :model })

      with_session(session_double) { described_class.capture(example, config) }

      expect(example.metadata[:rspec_signal_diagnostics]).to be_nil
    end

    it "skips values the driver cannot provide" do
      example = example_double
      session = session_double
      allow(session).to receive(:status_code).and_raise(NotImplementedError)

      with_session(session) { described_class.capture(example, config) }

      expect(example.metadata[:rspec_signal_diagnostics]).not_to have_key(:status_code)
      expect(example.metadata[:rspec_signal_diagnostics]).to include(url: "https://app.test/library")
    end

    it "never raises, whatever the driver does" do
      example = example_double
      session = session_double
      allow(session).to receive(:current_url).and_raise("driver exploded")

      expect { with_session(session) { described_class.capture(example, config) } }.not_to raise_error
    end

    it "saves the page HTML only when asked" do
      example = example_double
      config = signal_config(capture_page_html: true)

      with_session(session_double) { described_class.capture(example, config) }

      saved = example.metadata[:rspec_signal_diagnostics][:saved_page]
      expect(File.read(File.expand_path(saved, config.root))).to eq("<html></html>")
    ensure
      FileUtils.rm_rf(config.output_path)
    end
  end

  describe ".existing_session" do
    it "returns nil when Capybara is not loaded" do
      expect(described_class.existing_session).to be_nil
    end

    # Asking Capybara for `current_session` creates one, which can boot a
    # browser. Never do that just to write a report.
    it "does not create a session when the pool is empty" do
      capybara = fake_capybara(pool: {})
      allow(capybara).to receive(:current_session)

      expect(described_class.existing_session).to be_nil
      expect(capybara).not_to have_received(:current_session)
    end
  end
end
