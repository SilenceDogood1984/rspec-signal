# frozen_string_literal: true

RSpec.describe RSpec::Signal::Message do
  describe "structure" do
    it "keeps the blank lines RSpec uses to separate sections" do
      message = build_message(["Failure/Error: expect(a).to eq(b)", "", "  expected: 1", "       got: 2"])

      expect(message.lines).to eq(["Failure/Error: expect(a).to eq(b)", "", "  expected: 1", "       got: 2"])
    end

    it "splits embedded newlines" do
      expect(build_message(["a\nb"]).lines).to eq(%w[a b])
    end

    it "collapses runs of blank lines" do
      expect(build_message(["a", "", "", "", "b"]).lines).to eq(["a", "", "b"])
    end

    it "trims leading and trailing blank lines" do
      expect(build_message(["", "a", ""]).lines).to eq(["a"])
    end

    it "strips ANSI colour codes" do
      expect(build_message(["\e[31mred\e[0m"]).lines).to eq(["red"])
    end

    it "redacts secrets" do
      expect(build_message(["password: 'hunter2'"]).text).to include("[REDACTED]")
    end
  end

  describe "#headline" do
    it "is the first meaningful line" do
      expect(build_message(["", "Unable to find css", "more"]).headline).to eq("Unable to find css")
    end

    it "is truncated" do
      expect(build_message(["x" * 300]).headline(50).length).to eq(50)
    end
  end

  describe "#body" do
    it "returns everything when the message is small" do
      expect(build_message(%w[a b c]).body).to eq(%w[a b c])
    end

    it "truncates long messages and says so" do
      body = build_message(Array.new(100) { |i| "line #{i}" }).body(max_lines: 10)

      expect(body.size).to eq(11)
      expect(body.last).to eq("[90 more message lines omitted]")
    end

    it "trims oversized diffs, which are the biggest source of bloat" do
      lines = ["Failure/Error: expect(a).to eq(b)", "", "Diff:"] + Array.new(200) { |i| "-  row #{i}" }
      body = build_message(lines).body(max_lines: 100, max_diff_lines: 8)

      expect(body.count { |line| line.start_with?("-  row") }).to eq(7)
      expect(body.last).to include("more message lines omitted")
    end

    it "keeps the cause chain even when the wrapper message alone exceeds the line budget" do
      huge = Array.new(100) { |i| "line #{i}" }
      cause = ["", "Caused by ArgumentError:", "  duplicate key value violates a constraint"]
      body = build_message(huge, cause_lines: cause).body(max_lines: 10)

      expect(body).to include("[90 more message lines omitted]")
      expect(body.last(2)).to eq(["Caused by ArgumentError:", "  duplicate key value violates a constraint"])
    end
  end

  describe "#normalized" do
    def normalized(text)
      build_message([text]).normalized
    end

    it "masks object addresses" do
      expect(normalized("#<User:0x00007f9a1c0b2d48>")).to eq(normalized("#<User:0x00007fbb220c9910>"))
    end

    it "masks uuids" do
      expect(normalized("id 3f2504e0-4f89-11d3-9a0c-0305e82c3301"))
        .to eq(normalized("id 8a1b2c3d-4f89-11d3-9a0c-0305e82c3301"))
    end

    it "masks timestamps" do
      expect(normalized("at 2026-08-26T11:30:00Z")).to eq(normalized("at 2026-01-02T03:04:05Z"))
    end

    it "masks record ids" do
      expect(normalized("Couldn't find User with 'id'=48213")).to eq(normalized("Couldn't find User with 'id'=91055"))
    end

    it "masks temporary directories" do
      expect(normalized("wrote /tmp/d20260826-1-abcdef/out")).to eq(normalized("wrote /tmp/d20260101-9-ffffff/out"))
    end

    it "leaves small numbers alone, because they are usually the point" do
      expect(normalized("expected 3, got 4")).not_to eq(normalized("expected 7, got 9"))
    end

    it "is bounded in length" do
      expect(normalized("x" * 5000).length).to be <= described_class::MAX_FINGERPRINT_CHARS
    end

    it "keeps the cause distinguishable even once the main text is truncated" do
      huge = ["x" * 5000]

      with_cause_a = build_message(huge, cause_lines: ["Caused by ArgumentError:", "  connection reset"]).normalized
      with_cause_b = build_message(huge, cause_lines: ["Caused by ArgumentError:", "  constraint violated"]).normalized
      without_cause = build_message(huge).normalized

      expect(with_cause_a).not_to eq(with_cause_b)
      expect(with_cause_a).not_to eq(without_cause)
      expect(with_cause_a).to start_with(without_cause)
    end
  end

  it "reports emptiness" do
    expect(build_message([])).to be_empty
    expect(build_message(["a"])).not_to be_empty
  end

  describe "#summary" do
    # RSpec opens every failure by echoing the source expression, which the
    # reader can already see and which is identical for every example sharing
    # a line. The line worth showing is the one after it.
    it "skips the Failure/Error source echo and the bare exception label" do
      message = build_message([
                                "Failure/Error: def render; @rows.map { |r| r.fetch(:title) }.join(\", \"); end",
                                "",
                                "KeyError:",
                                "  key not found: :title"
                              ])

      expect(message.summary).to eq("key not found: :title")
    end

    it "finds the diagnosis when a matcher appends it to the echo without a blank line" do
      message = build_message([
                                "Failure/Error: expect(response).to have_http_status(:ok)",
                                "  expected the response to have status code 200 but it was 404"
                              ])

      expect(message.summary).to eq("expected the response to have status code 200 but it was 404")
    end

    it "prefers the expectation over the source for a matcher failure" do
      message = build_message(["Failure/Error: expect(a).to eq(b)", "", "  expected: 1", "       got: 2"])

      expect(message.summary).to eq("expected: 1")
    end

    it "falls back to the echo when there is nothing else" do
      message = build_message(["Failure/Error: expect(a).to be_truthy"])

      expect(message.summary).to eq("Failure/Error: expect(a).to be_truthy")
    end

    it "is empty for an empty message" do
      expect(build_message([]).summary).to eq("")
    end

    it "truncates to the requested width" do
      message = build_message(["Failure/Error: x", "", "y" * 200])

      expect(message.summary(40).length).to eq(40)
    end
  end
end
