# frozen_string_literal: true

RSpec.describe RSpec::Signal::Backtrace::Parser do
  def parse_one(line)
    described_class.parse_line(line)
  end

  it "parses the classic Ruby backtrace shape" do
    frame = parse_one("/srv/app/app/models/user.rb:42:in `full_name'")

    expect(frame.path).to eq("/srv/app/app/models/user.rb")
    expect(frame.line).to eq(42)
    expect(frame.label).to eq("full_name")
  end

  it "parses the Ruby 3.4 quoting style" do
    frame = parse_one("/srv/app/app/models/user.rb:42:in 'User#full_name'")

    expect(frame.line).to eq(42)
    expect(frame.label).to eq("User#full_name")
  end

  it "parses a line with no method label" do
    frame = parse_one("./spec/models/user_spec.rb:12")

    expect(frame.path).to eq("spec/models/user_spec.rb")
    expect(frame.line).to eq(12)
    expect(frame.label).to be_nil
  end

  it "parses a line with no line number" do
    frame = parse_one("/srv/app/Rakefile")

    expect(frame.path).to eq("/srv/app/Rakefile")
    expect(frame.line).to be_nil
  end

  it "handles labels containing brackets and quotes" do
    frame = parse_one("/x/y.rb:3:in `block (2 levels) in <top (required)>'")

    expect(frame.label).to eq("block (2 levels) in <top (required)>")
  end

  it "ignores blank lines" do
    expect(parse_one("")).to be_nil
    expect(parse_one("    ")).to be_nil
  end

  it "keeps text it cannot fully parse rather than discarding it" do
    frame = parse_one("something unexpected")

    expect(frame.path).to eq("something unexpected")
  end

  it "classifies while parsing" do
    frames = described_class.parse(
      ["/srv/app/app/models/user.rb:1:in `a'",
       "/usr/local/bundle/gems/capybara-3.40.0/lib/capybara.rb:2:in `b'",
       "/usr/local/bundle/gems/rspec-core-3.13.6/lib/rspec/core/example.rb:3:in `c'"],
      signal_config.classifier
    )

    expect(frames.map(&:kind)).to eq(%i[project external framework])
  end

  it "returns an empty array for nil" do
    expect(described_class.parse(nil, signal_config.classifier)).to eq([])
  end
end
