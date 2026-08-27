# frozen_string_literal: true

RSpec.describe "RSpec::Signal.install!" do
  # A throwaway RSpec configuration, so we never touch the one running us.
  let(:rspec_config) { RSpec::Core::Configuration.new.tap { |config| config.output_stream = StringIO.new } }
  let(:loader) { rspec_config.formatter_loader }

  around do |example|
    RSpec::Signal.reset!
    example.run
    RSpec::Signal.reset!
  end

  def formatter_classes
    loader.formatters.map(&:class)
  end

  it "registers the formatter" do
    RSpec::Signal.install!(rspec_config)

    expect(formatter_classes).to include(RSpec::Signal::Formatter)
  end

  it "is idempotent" do
    RSpec::Signal.install!(rspec_config)
    RSpec::Signal.install!(rspec_config)

    expect(formatter_classes.count(RSpec::Signal::Formatter)).to eq(1)
  end

  it "reports whether it did anything" do
    expect(RSpec::Signal.install!(rspec_config)).to be(true)
    expect(RSpec::Signal.install!(rspec_config)).to be(false)
  end

  it "does nothing when disabled" do
    RSpec::Signal.configure { |config| config.enabled = false }

    expect(RSpec::Signal.install!(rspec_config)).to be(false)
    expect(formatter_classes).not_to include(RSpec::Signal::Formatter)
  end

  # `prepend_after` so this runs before any example-group-level `after(:each)`
  # hook -- rspec-rails tears the Capybara session down at that level, and
  # capturing after teardown would find nothing.
  it "installs the Capybara diagnostics hook by default" do
    allow(rspec_config).to receive(:prepend_after)
    RSpec::Signal.install!(rspec_config)

    expect(rspec_config).to have_received(:prepend_after).with(:each)
  end

  it "skips the Capybara hook when asked" do
    allow(rspec_config).to receive(:prepend_after)
    RSpec::Signal.configure { |config| config.capture_capybara = false }
    RSpec::Signal.install!(rspec_config)

    expect(rspec_config).not_to have_received(:prepend_after)
  end

  describe "not stealing the developer's terminal output" do
    # Adding any formatter suppresses RSpec's default one. rspec-signal installs
    # itself, so it has to put the default back.
    it "restores the default formatter when it installed itself" do
      RSpec::Signal.install!(rspec_config)
      expect(RSpec::Signal).to be_auto_installed

      RSpec::Signal.restore_default_formatter!(rspec_config)

      expect(formatter_classes).to include(RSpec::Core::Formatters::ProgressFormatter)
    end

    it "leaves an explicitly chosen formatter alone" do
      rspec_config.add_formatter(:documentation)
      RSpec::Signal.install!(rspec_config)
      RSpec::Signal.restore_default_formatter!(rspec_config)

      expect(formatter_classes).to include(RSpec::Core::Formatters::DocumentationFormatter)
      expect(formatter_classes).not_to include(RSpec::Core::Formatters::ProgressFormatter)
    end

    it "does not add a second default if one is already present" do
      RSpec::Signal.install!(rspec_config)
      RSpec::Signal.restore_default_formatter!(rspec_config)
      RSpec::Signal.restore_default_formatter!(rspec_config)

      expect(formatter_classes.count(RSpec::Core::Formatters::ProgressFormatter)).to eq(1)
    end

    it "stays quiet when the user asked for rspec-signal explicitly" do
      rspec_config.add_formatter(RSpec::Signal::Formatter)
      RSpec::Signal.install!(rspec_config)

      expect(RSpec::Signal).not_to be_auto_installed
      expect(formatter_classes.count(RSpec::Signal::Formatter)).to eq(1)
    end
  end

  describe "configuration" do
    it "yields the configuration" do
      RSpec::Signal.configure { |config| config.max_frames = 3 }

      expect(RSpec::Signal.configuration.max_frames).to eq(3)
    end

    it "rebuilds memoized collaborators after a change" do
      before = RSpec::Signal.configuration.project
      RSpec::Signal.configure { |config| config.project_root = "/somewhere/else" }

      expect(RSpec::Signal.configuration.project).not_to equal(before)
      expect(RSpec::Signal.configuration.project.root).to eq("/somewhere/else")
    end

    it "resolves the output directory relative to the project root" do
      RSpec::Signal.configure do |config|
        config.project_root = "/srv/app"
        config.output_dir = "tmp/reports"
      end

      expect(RSpec::Signal.configuration.output_path).to eq("/srv/app/tmp/reports")
    end

    it "accepts an absolute output directory" do
      RSpec::Signal.configure { |config| config.output_dir = "/var/reports" }

      expect(RSpec::Signal.configuration.output_path).to eq("/var/reports")
    end
  end

  describe ".environment" do
    it "records the versions worth knowing" do
      expect(RSpec::Signal.environment).to include("ruby" => RUBY_VERSION, "rspec" => RSpec::Core::Version::STRING)
    end
  end
end
