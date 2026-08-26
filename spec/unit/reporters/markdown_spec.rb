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

  describe "the related failures section" do
    def request_failure(spec:, line:, message:)
      build_failure(config: config, backtrace: Backtraces.expectation_not_met(spec: spec, line: line),
                    exception_class: "RSpec::Expectations::ExpectationNotMetError",
                    description: "#{spec}:#{line}", message: message)
    end

    subject(:markdown) { render_markdown(build_report(failures), config: config) }

    let(:failures) do
      [request_failure(spec: "spec/requests/checkpoint_spec.rb", line: 31,
                       message: Messages.http_status(expected: 200, actual: 404)),
       request_failure(spec: "spec/requests/reader_completion_spec.rb", line: 18,
                       message: Messages.http_status(expected: 200, actual: 404)),
       request_failure(spec: "spec/requests/reader_layout_spec.rb", line: 44,
                       message: Messages.http_status_class(expected: "redirect", actual: 404))]
    end

    it "names the shared symptom" do
      expect(markdown).to include("### R1. Unexpected 404 (Not Found) responses -- 3 examples across 3 signatures")
    end

    it "shows the variants the symptom took" do
      expect(markdown).to include("- Symptoms: `expected 200, got 404` (2), `expected redirect, got 404` (1)")
    end

    it "lists the affected spec files" do
      expect(markdown).to include("`spec/requests/checkpoint_spec.rb`", "`spec/requests/reader_layout_spec.rb`")
    end

    it "points at the signature sections that carry it" do
      expect(markdown).to include("- Signatures: #1, #2, #3")
    end

    # A cluster is a hint, not a verdict, and the report has to say which.
    it "says plainly that a cluster is weaker than a signature" do
      expect(markdown).to include("not a proven identical failure", "remain authoritative")
    end

    it "counts clusters in the header" do
      expect(markdown).to include("1 related cluster")
    end

    it "comes before the signature index, because it is the higher-level view" do
      expect(markdown.index("## Related failures")).to be < markdown.index("## Signatures")
    end

    it "is omitted entirely when nothing relates" do
      quiet = render_markdown(build_report([capybara_failure]), config: config)

      expect(quiet).not_to include("## Related failures", "related cluster")
    end

    it "caps how many clusters are rendered" do
      many = (0..12).flat_map do |i|
        [request_failure(spec: "spec/requests/a#{i}_spec.rb", line: 1,
                         message: Messages.http_status(expected: 200, actual: 400 + i)),
         request_failure(spec: "spec/requests/b#{i}_spec.rb", line: 2,
                         message: Messages.http_status(expected: 201, actual: 400 + i))]
      end
      markdown = render_markdown(build_report(many), config: signal_config(max_clusters: 3))

      expect(markdown).to include("10 further related clusters not rendered")
    end

    it "caps how many spec files it lists" do
      many = (0..9).map do |i|
        request_failure(spec: "spec/requests/s#{i}_spec.rb", line: i + 1,
                        message: Messages.http_status(expected: 200 + i, actual: 404))
      end
      markdown = render_markdown(build_report(many), config: signal_config(max_cluster_specs: 4))

      expect(markdown).to include("and 6 more")
    end
  end

  describe "a giant HTML response" do
    subject(:markdown) do
      failure = build_failure(
        config: config, backtrace: Backtraces.rack_middleware_stack,
        exception_class: "RSpec::Expectations::ExpectationNotMetError",
        description: "Reader completion shows the finished notice",
        message: Messages.body_include_with_diff(expected: "You've finished this document.",
                                                 actual: Messages.rails_exception_page)
      )
      render_markdown(build_report([failure]), config: config)
    end

    it "keeps the expected value" do
      expect(markdown).to include("You've finished this document.")
    end

    it "replaces the markup with what it was" do
      expect(markdown).to include("Title: Action Controller: Exception caught",
                                  "Message: undefined method 'progress' for nil")
    end

    it "shows none of the page's CSS" do
      expect(markdown).not_to include("font-family", "<style")
    end

    it "leaves the whole report short" do
      expect(markdown.lines.size).to be < 60
    end
  end

  describe "size" do
    # The related section exists to save the reader from reading every
    # signature. It would be a poor trade if it cost a section's worth of prose.
    it "spends only a small part of a large report on related failures" do
      failures = (0..19).map do |i|
        build_failure(config: config, exception_class: "RSpec::Expectations::ExpectationNotMetError",
                      backtrace: Backtraces.expectation_not_met(spec: "spec/r#{i}_spec.rb", line: i + 1),
                      description: "example #{i}", message: Messages.http_status(expected: 200 + i, actual: 404))
      end
      lines = render_markdown(build_report(failures), config: config).lines
      section = lines.index { |line| line.start_with?("## Signatures") } -
                lines.index { |line| line.start_with?("## Related failures") }

      expect(section).to be < (lines.size / 10)
    end

    it "keeps a large, highly repetitive run small" do
      failures = Array.new(43) do |i|
        capybara_failure(spec: "spec/system/s#{i % 7}_spec.rb", line: (i % 7) * 10)
      end
      markdown = render_markdown(build_report(failures, example_count: 936, failure_count: 43), config: config)

      expect(markdown.lines.size).to be < 200
    end
  end
end
