# frozen_string_literal: true

RSpec.describe RSpec::Signal::Reporters::Markdown do
  let(:config) { signal_config }

  def capybara_failure(spec: "spec/system/reader_spec.rb", line: 104, description: "Reader shelf shows the shelf",
                       **rest)
    build_failure(
      config: config,
      backtrace: Backtraces.capybara_element_not_found(spec: spec, line: line),
      exception_class: "Capybara::ElementNotFound",
      description: description,
      message: ['Failure/Error: expect(page).to have_css("#reader-shelf")', "",
                "Capybara::ElementNotFound:", '  Unable to find css "#reader-shelf"'],
      **rest
    )
  end

  describe "the whole document" do
    subject(:markdown) do
      render_markdown(
        build_report([capybara_failure], example_count: 936, failure_count: 1,
                                         duration: 41.2, seed: 12_345, seed_used: true,
                                         environment: { "ruby" => "3.3.10", "rspec" => "3.13.6" }),
        config: config
      )
    end

    it "opens with the counts that matter" do
      expect(markdown).to include("936 examples", "1 failure", "1 distinct signature")
    end

    it "states how much was removed" do
      expect(markdown).to match(/Backtraces reduced from \d+ to \d+ frames/)
    end

    it "records the seed so the run can be reproduced" do
      expect(markdown).to include("seed `12345`")
    end

    it "explains its own conventions so nothing has to be guessed" do
      expect(markdown).to include("innermost first")
    end

    it "contains no instructions to a model" do
      expect(markdown).not_to match(/you are an?|please fix|as an AI|your task/i)
    end

    it "warns that artifacts should be reviewed before being shared" do
      expect(markdown).to include("Review this file before sharing")
    end
  end

  describe "a signature section" do
    subject(:markdown) { render_markdown(build_report([capybara_failure]), config: config) }

    it "names the exception" do
      expect(markdown).to include("## 1. Capybara::ElementNotFound")
    end

    it "includes the full example description" do
      expect(markdown).to include("Reader shelf shows the shelf")
    end

    it "includes the failure message" do
      expect(markdown).to include('Unable to find css "#reader-shelf"')
    end

    it "points at the example, then at the code that raised" do
      expect(markdown).to include("- Example `spec/system/reader_spec.rb:104`")
      expect(markdown).to include("- Raised in `capybara/node/finders.rb:312` (capybara)")
    end

    it "includes the reduced trace" do
      expect(markdown).to include("capybara/node/finders.rb:60 in `find'")
      expect(markdown).to match(%r{\[\d+ framework/runtime frames omitted\]})
    end

    it "includes a runnable rerun command" do
      expect(markdown).to include("bundle exec rspec spec/system/reader_spec.rb:104")
    end
  end

  describe "grouped failures" do
    subject(:markdown) do
      failures = [
        capybara_failure(spec: "spec/system/reader_spec.rb", line: 104),
        capybara_failure(spec: "spec/system/foo_spec.rb", line: 27),
        capybara_failure(spec: "spec/system/bar_spec.rb", line: 81)
      ]
      render_markdown(build_report(failures, failure_count: 3), config: config)
    end

    it "shows the group size in the heading" do
      expect(markdown).to include("-- 3 examples")
    end

    it "lists every other affected example" do
      expect(markdown).to include("**Also failing identically (2)**",
                                  "spec/system/foo_spec.rb:27",
                                  "spec/system/bar_spec.rb:81")
    end

    it "renders one trace, not three" do
      expect(markdown.scan("**Trace**").size).to eq(1)
    end

    it "caps the affected list" do
      failures = Array.new(40) { |i| capybara_failure(spec: "spec/system/s#{i}_spec.rb", line: i + 1) }
      markdown = render_markdown(build_report(failures), config: signal_config(max_affected_examples: 5))

      expect(markdown).to include("... and 34 more locations")
    end

    # Parameterised examples all report the same `it` line, and repeating it
    # once per example is exactly the noise this gem exists to remove.
    it "collapses examples that share a location" do
      failures = Array.new(12) do |i|
        capybara_failure(spec: "spec/system/loop_spec.rb", line: 4, description: "case #{i}")
      end
      markdown = render_markdown(build_report(failures), config: config)

      expect(markdown).to include("**Also failing identically (11)**", "spec/system/loop_spec.rb:4  (11 examples)")
      expect(markdown.scan("spec/system/loop_spec.rb:4  (").size).to eq(1)
    end
  end

  describe "the signature index" do
    it "is omitted for a single signature" do
      expect(render_markdown(build_report([capybara_failure]), config: config)).not_to include("## Signatures")
    end

    it "summarises every signature when there is more than one" do
      failures = [capybara_failure,
                  build_failure(config: config, backtrace: Backtraces.pure_ruby,
                                exception_class: "ArgumentError", message: ["wrong number of arguments"])]
      markdown = render_markdown(build_report(failures), config: config)

      expect(markdown).to include("## Signatures", "`Capybara::ElementNotFound`", "`ArgumentError`")
    end

    it "escapes pipes so the table cannot be broken by a message" do
      failure = build_failure(config: config, backtrace: Backtraces.pure_ruby,
                              exception_class: "ArgumentError", message: ["a | b | c"])
      markdown = render_markdown(build_report([failure, capybara_failure]), config: config)

      expect(markdown).to include("a \\| b \\| c")
    end
  end

  describe "system spec diagnostics" do
    subject(:markdown) do
      failure = capybara_failure(diagnostics: { url: "https://app.test/library", title: "Library",
                                                screenshot: "tmp/screenshots/failures_reader.png",
                                                console: ["SEVERE: Uncaught TypeError: x is not a function"] })
      render_markdown(build_report([failure]), config: config)
    end

    it "reports the browser location" do
      expect(markdown).to include("- URL: `https://app.test/library`")
    end

    it "reports where the screenshot was saved" do
      expect(markdown).to include("- Screenshot: `tmp/screenshots/failures_reader.png`")
    end

    it "reports console output, which often holds the real cause" do
      expect(markdown).to include("Uncaught TypeError")
    end

    it "omits the section entirely when there is nothing to say" do
      expect(render_markdown(build_report([capybara_failure]), config: config)).not_to include("Browser state")
    end
  end

  describe "edge cases" do
    it "says so when a backtrace had no first-party frames" do
      failure = build_failure(config: config, backtrace: Backtraces.library_only,
                              exception_class: "Errno::ECONNREFUSED", message: ["Connection refused"],
                              spec_location: "spec/clients/api_spec.rb:9")

      expect(render_markdown(build_report([failure]), config: config))
        .to include("No first-party frames in this backtrace")
    end

    it "renders a failure with no backtrace at all" do
      failure = build_failure(config: config, backtrace: [], exception_class: "RuntimeError",
                              message: ["boom"], spec_location: "spec/a_spec.rb:1")

      expect(render_markdown(build_report([failure]), config: config)).to include("(no backtrace available)")
    end

    it "renders a report with no failures" do
      expect(render_markdown(build_report([]), config: config)).to include("0 failures")
    end

    it "notes shared example groups" do
      failure = capybara_failure(shared_group_locations: ['"a paginated list" at spec/support/shared.rb:12'])

      expect(render_markdown(build_report([failure]), config: config))
        .to include("Via shared example group \"a paginated list\" at spec/support/shared.rb:12")
    end

    it "truncates the rendered signatures when asked" do
      failures = Array.new(5) do |i|
        build_failure(config: config, backtrace: Backtraces.pure_ruby,
                      exception_class: "Error#{i}", message: ["boom #{i}"])
      end
      markdown = render_markdown(build_report(failures), config: signal_config(max_groups: 2))

      expect(markdown).to include("3 further signatures not rendered")
    end
  end

  describe "a signature spanning several files" do
    it "offers a command that reruns the whole signature" do
      failures = [capybara_failure(spec: "spec/system/a_spec.rb", line: 1),
                  capybara_failure(spec: "spec/system/b_spec.rb", line: 2)]

      expect(render_markdown(build_report(failures), config: config))
        .to include("bundle exec rspec spec/system/a_spec.rb:1 spec/system/b_spec.rb:2")
    end

    it "does not offer an unusably long command" do
      failures = Array.new(30) { |i| capybara_failure(spec: "spec/system/s#{i}_spec.rb", line: i + 1) }
      markdown = render_markdown(build_report(failures), config: config)

      expect(markdown.scan("bundle exec rspec ").size).to eq(1)
    end
  end

  describe "errors outside examples" do
    # A `before(:suite)` blow-up produces zero failed examples, so without this
    # the run would leave nothing behind at all.
    it "is reported even with no failures" do
      markdown = render_markdown(build_report([], errors_outside_examples: 2), config: config)

      expect(markdown).to include("## Errors outside examples", "2 errors occurred outside of any example")
    end

    it "is counted in the header" do
      markdown = render_markdown(build_report([], errors_outside_examples: 1), config: config)

      expect(markdown).to include("1 error outside examples")
    end
  end

  describe "size" do
    it "keeps a large, highly repetitive run small" do
      failures = Array.new(43) do |i|
        capybara_failure(spec: "spec/system/s#{i % 7}_spec.rb", line: (i % 7) * 10)
      end
      markdown = render_markdown(build_report(failures, example_count: 936, failure_count: 43), config: config)

      expect(markdown.lines.size).to be < 200
    end
  end
end
