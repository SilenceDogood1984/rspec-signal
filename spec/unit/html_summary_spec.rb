# frozen_string_literal: true

RSpec.describe RSpec::Signal::HtmlSummary do
  let(:config) { signal_config }
  let(:page) { Messages.rails_exception_page }
  let(:sentence) { "You've finished this document." }

  describe "a Rails exception page as the actual value" do
    subject(:body) do
      build_message(Messages.body_include(expected: sentence, actual: page), config: config).body
    end

    it "keeps the expected value, which is the small and useful half" do
      expect(body.join("\n")).to include(sentence)
    end

    it "says what the actual value was and how big it was" do
      expect(body.join("\n")).to match(/\[HTML document: [\d,]+ lines, \d+ KB -- markup omitted\]/)
    end

    it "reports the page title" do
      expect(body).to include("  Title: Action Controller: Exception caught")
    end

    it "reports the exception heading and message" do
      expect(body).to include("  Heading: NoMethodError in ReaderController#show")
      expect(body).to include("  Message: undefined method 'progress' for nil")
    end

    it "prints none of the CSS that happened to come first" do
      expect(body.join("\n")).not_to include("font-family", "<style", "padding: 0")
    end

    it "stays short" do
      expect(body.size).to be <= 10
    end
  end

  describe "a Rails exception page arriving as a diff" do
    subject(:body) do
      build_message(Messages.body_include_with_diff(expected: sentence, actual: page), config: config).body
    end

    it "replaces the added side with the summary" do
      expect(body).to include("  Title: Action Controller: Exception caught")
      expect(body.join("\n")).not_to include("font-family")
    end

    it "leaves the removed side -- the expected value -- in place" do
      expect(body.join("\n")).to include("-#{sentence}")
    end

    it "stays short" do
      expect(body.size).to be <= 15
    end
  end

  describe "HTML small enough to read" do
    it "is left exactly as it was" do
      markup = '<div class="card"><h3>Total</h3><p>$14.00</p></div>'
      body = build_message(Messages.body_include(expected: "Subtotal", actual: markup), config: config).body

      expect(body.join("\n")).to include("<h3>Total</h3>")
      expect(body.join("\n")).not_to include("HTML document")
    end
  end

  describe "what it refuses to touch" do
    it "leaves a long non-HTML value alone" do
      csv = (["id,name,total"] + Array.new(400) { |i| "#{i},row #{i},#{i * 3}" }).join("\n")
      body = build_message(Messages.body_include(expected: "header", actual: csv), config: config).body

      expect(body.join("\n")).not_to include("HTML document")
    end

    it "can be switched off" do
      quiet = signal_config(reduce_html: false)
      body = build_message(Messages.body_include(expected: sentence, actual: page), config: quiet).body

      expect(body.join("\n")).not_to include("HTML document")
    end
  end

  describe "pages that are not Rails exception pages" do
    it "reads a plain Rails 404 page" do
      markup = "<!DOCTYPE html><html><head><title>The page you were looking for doesn't exist (404)" \
               "</title><style>#{"body{background:#EFEFEF;}" * 200}</style></head><body>" \
               "<h1>The page you were looking for doesn't exist.</h1></body></html>"
      body = build_message(Messages.body_include(expected: "Reader", actual: markup), config: config).body

      expect(body).to include("  Title: The page you were looking for doesn't exist (404)")
      expect(body).to include("  Heading: The page you were looking for doesn't exist.")
    end

    it "falls back to visible text when there is no title or heading" do
      markup = "<div class=\"wrapper\"><section><p>Sorry, something went wrong.</p>" \
               "<p>#{"filler " * 400}</p></section></div>"
      body = build_message(Messages.body_include(expected: "Reader", actual: markup), config: config).body

      expect(body.join("\n")).to include("Text: Sorry, something went wrong.")
    end
  end

  describe "the effect on fingerprinting" do
    def failure_for(markup, diff: false)
      builder = diff ? :body_include_with_diff : :body_include
      build_failure(config: config, backtrace: Backtraces.expectation_not_met,
                    exception_class: "RSpec::Expectations::ExpectationNotMetError",
                    message: Messages.public_send(builder, expected: sentence, actual: markup))
    end

    # Before reduction both messages began with the same hundred lines of CSS
    # and were truncated to the same 400 characters, so two genuinely different
    # exception pages looked identical.
    it "tells two different exception pages apart" do
      first = failure_for(Messages.rails_exception_page(error: "NoMethodError", detail: "undefined method 'progress'"))
      second = failure_for(Messages.rails_exception_page(error: "ActiveRecord::RecordNotFound",
                                                         detail: "Couldn't find Reader"))

      expect(RSpec::Signal::Grouper.call([first, second]).size).to eq(2)
    end

    # The size of the rendered page is not a diagnostic fact; the title and the
    # exception message are.
    it "collapses the same page rendered at two different sizes" do
      first = failure_for(Messages.rails_exception_page(css_rules: 300))
      second = failure_for(Messages.rails_exception_page(css_rules: 340))

      expect(RSpec::Signal::Grouper.call([first, second]).size).to eq(1)
    end

    # The hunk header counts lines, and a page one line longer is not a
    # different failure.
    it "collapses them through a diff too" do
      first = failure_for(Messages.rails_exception_page(css_rules: 300), diff: true)
      second = failure_for(Messages.rails_exception_page(css_rules: 340), diff: true)

      expect(RSpec::Signal::Grouper.call([first, second]).size).to eq(1)
    end
  end

  describe "failing soft" do
    it "returns the lines unchanged when reduction blows up" do
      allow(described_class).to receive(:reduce).and_raise(ArgumentError, "boom")
      lines = Messages.body_include(expected: sentence, actual: page)

      expect(build_message(lines, config: config).body.join("\n")).to include("<!DOCTYPE html>")
    end
  end
end
