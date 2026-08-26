# frozen_string_literal: true

RSpec.describe RSpec::Signal::Writer do
  let(:config) { signal_config }
  let(:writer) { described_class.new(config) }
  let(:failure) do
    build_failure(config: config, backtrace: Backtraces.capybara_element_not_found,
                  exception_class: "Capybara::ElementNotFound", message: ["Unable to find css"],
                  raw: "  1) the original unreduced output\n     # a/b.rb:1")
  end

  after { FileUtils.rm_rf(config.output_path) }

  def contents(name) = File.read(File.join(writer.dir, name))

  describe "with failures" do
    let!(:result) { writer.write(build_report([failure])) }

    it "writes the summary" do
      expect(File).to exist(File.join(writer.dir, "signal.md"))
      expect(contents("signal.md")).to include("Capybara::ElementNotFound")
    end

    it "keeps summary.md as a compatibility copy" do
      expect(contents("summary.md")).to eq(contents("signal.md"))
    end

    it "returns the summary path" do
      expect(result.summary_path).to end_with("signal.md")
    end

    it "writes machine-readable JSON alongside it" do
      parsed = JSON.parse(contents("signal.json"))

      expect(parsed["summary"]["failures"]).to eq(1)
      expect(parsed["signatures"].first["exception"]).to eq("Capybara::ElementNotFound")
    end

    it "does not preserve the original unreduced output by default" do
      expect(File).not_to exist(File.join(writer.dir, "full.txt"))
    end

    it "keeps artifacts out of version control by default" do
      expect(contents(".gitignore")).to include("*")
    end
  end

  describe "optional artifacts" do
    it "can skip the JSON report" do
      writer = described_class.new(signal_config(write_json: false, output_dir: config.output_dir))
      writer.write(build_report([failure]))

      expect(File).not_to exist(File.join(writer.dir, "signal.json"))
    end

    it "can write the full output explicitly" do
      writer = described_class.new(signal_config(write_full: true, output_dir: config.output_dir))
      writer.write(build_report([failure]))

      expect(contents("full.txt")).to include("the original unreduced output")
    end

    it "can skip the gitignore" do
      writer = described_class.new(signal_config(write_gitignore: false, output_dir: config.output_dir))
      writer.write(build_report([failure]))

      expect(File).not_to exist(File.join(writer.dir, ".gitignore"))
    end
  end

  # A stale report is worse than no report: an agent would go and "fix"
  # failures that no longer exist.
  describe "a green run after a red one" do
    it "removes the artifacts from the previous run" do
      writer.write(build_report([failure]))
      result = writer.write(build_report([]))

      expect(File).not_to exist(File.join(writer.dir, "signal.md"))
      expect(File).not_to exist(File.join(writer.dir, "signal.json"))
      expect(result.summary_path).to be_nil
      expect(result.cleaned.size).to eq(3)
    end

    it "still writes a report when the suite broke outside of any example" do
      result = writer.write(build_report([], errors_outside_examples: 1))

      expect(result.summary_path).not_to be_nil
      expect(contents("signal.md")).to include("Errors outside examples")
    end

    it "does nothing when there was nothing to clean" do
      expect { writer.write(build_report([])) }.not_to raise_error
    end
  end

  describe "#relative" do
    it "renders paths the way you would type them" do
      expect(writer.relative(File.join(config.root, "tmp/rspec-signal/signal.md")))
        .to eq("tmp/rspec-signal/signal.md")
    end

    it "leaves paths outside the project alone" do
      expect(writer.relative("/elsewhere/signal.md")).to eq("/elsewhere/signal.md")
    end
  end

  it "creates the output directory if it does not exist" do
    nested = File.join(config.output_path, "deep", "nested")
    writer = described_class.new(signal_config(output_dir: nested))
    writer.write(build_report([failure]))

    expect(File).to exist(File.join(nested, "signal.md"))
  end
end
