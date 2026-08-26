# frozen_string_literal: true

RSpec.describe "related failure clustering" do
  let(:config) { signal_config }

  # A request spec asserting on a response. The matcher raises at the spec line,
  # so each of these is a genuinely distinct exact signature.
  def request_failure(spec:, line:, message:, exception_class: "RSpec::Expectations::ExpectationNotMetError")
    build_failure(config: config, backtrace: Backtraces.expectation_not_met(spec: spec, line: line),
                  exception_class: exception_class, description: "#{spec}:#{line}", message: message)
  end

  def system_failure(spec:, line:, message:, exception_class: "Capybara::ElementNotFound")
    build_failure(config: config, backtrace: Backtraces.capybara_element_not_found(spec: spec, line: line),
                  exception_class: exception_class, description: "#{spec}:#{line}", message: message)
  end

  describe "a suite full of unexpected 404s" do
    let(:failures) do
      [
        request_failure(spec: "spec/requests/checkpoint_responses_controller_spec.rb", line: 31,
                        message: Messages.http_status(expected: 200, actual: 404)),
        request_failure(spec: "spec/requests/reader_completion_spec.rb", line: 18,
                        message: Messages.http_status(expected: 200, actual: 404)),
        request_failure(spec: "spec/requests/reader_layout_spec.rb", line: 44,
                        message: Messages.http_status_class(expected: "redirect", actual: 404)),
        request_failure(spec: "spec/requests/reader_sentence_anchor_spec.rb", line: 9,
                        message: Messages.http_status_class(expected: "redirect", actual: 404))
      ]
    end

    it "leaves the exact signatures alone: these are four different failures" do
      expect(RSpec::Signal::Grouper.call(failures).size).to eq(4)
    end

    it "still tells the reader they are probably one problem" do
      clusters = build_clusters(failures)

      expect(clusters.size).to eq(1)
      expect(clusters.first.size).to eq(4)
      expect(clusters.first.label).to eq("unexpected 404 (Not Found) responses")
    end

    it "records that the cluster spans more than one signature" do
      expect(build_clusters(failures).first.signature_count).to eq(4)
    end

    it "keeps both symptom variants, rather than picking one" do
      expect(build_clusters(failures).first.symptom_counts)
        .to eq({ "expected 200, got 404" => 2, "expected redirect, got 404" => 2 })
    end

    it "lists every affected spec file" do
      expect(build_clusters(failures).first.spec_files).to contain_exactly(
        "spec/requests/checkpoint_responses_controller_spec.rb",
        "spec/requests/reader_completion_spec.rb",
        "spec/requests/reader_layout_spec.rb",
        "spec/requests/reader_sentence_anchor_spec.rb"
      )
    end

    it "does not pull in a failure that got a different status" do
      others = failures + [request_failure(spec: "spec/requests/admin_spec.rb", line: 12,
                                           message: Messages.http_status(expected: 200, actual: 500))]

      expect(build_clusters(others).map(&:size)).to eq([4])
    end
  end

  describe "one missing selector reported two different ways" do
    let(:selector) { '[data-testid="reader-progress"] span' }
    let(:failures) do
      [system_failure(spec: "spec/system/reader_progress_spec.rb", line: 22,
                      message: Messages.element_not_found(selector)),
       system_failure(spec: "spec/system/reader_layout_spec.rb", line: 61,
                      exception_class: "RSpec::Expectations::ExpectationNotMetError",
                      message: Messages.no_matches(selector))]
    end

    it "keeps them as separate signatures, because they are separate failures" do
      expect(RSpec::Signal::Grouper.call(failures).size).to eq(2)
    end

    it "relates them anyway" do
      clusters = build_clusters(failures)

      expect(clusters.size).to eq(1)
      expect(clusters.first.label).to include("[data-testid=\"reader-progress\"] span")
    end
  end

  describe "safeguards against over-clustering" do
    it "does not relate different selectors" do
      failures = [
        system_failure(spec: "spec/system/a_spec.rb", line: 1, message: Messages.element_not_found("#reader-shelf")),
        system_failure(spec: "spec/system/b_spec.rb", line: 2,
                       exception_class: "RSpec::Expectations::ExpectationNotMetError",
                       message: Messages.no_matches("#reader-shelf")),
        system_failure(spec: "spec/system/c_spec.rb", line: 3, message: Messages.element_not_found("#checkout")),
        system_failure(spec: "spec/system/d_spec.rb", line: 4,
                       exception_class: "RSpec::Expectations::ExpectationNotMetError",
                       message: Messages.no_matches("#checkout"))
      ]
      clusters = build_clusters(failures)

      expect(clusters.size).to eq(2)
      expect(clusters.map(&:spec_files)).to contain_exactly(
        ["spec/system/a_spec.rb", "spec/system/b_spec.rb"],
        ["spec/system/c_spec.rb", "spec/system/d_spec.rb"]
      )
    end

    # The whole reason the fallback extractor refuses generic classes.
    it "does not relate unrelated expectation failures by exception class" do
      failures = [
        request_failure(spec: "spec/models/user_spec.rb", line: 27,
                        message: Messages.comparison(expected: "true", actual: "false")),
        request_failure(spec: "spec/models/order_spec.rb", line: 88,
                        message: Messages.comparison(expected: "3", actual: "4")),
        request_failure(spec: "spec/models/invoice_spec.rb", line: 12,
                        message: Messages.comparison(expected: '"paid"', actual: '"draft"'))
      ]

      expect(build_clusters(failures)).to be_empty
    end

    # If every failure with the symptom is already one signature, the signature
    # section says it better, and repeating it is pure noise.
    it "says nothing when a symptom does not span more than one signature" do
      failures = Array.new(3) do |i|
        system_failure(spec: "spec/system/s#{i}_spec.rb", line: i, message: Messages.element_not_found("#shelf"))
      end

      expect(RSpec::Signal::Grouper.call(failures).size).to eq(1)
      expect(build_clusters(failures)).to be_empty
    end

    it "needs more than one failure" do
      failures = [request_failure(spec: "spec/requests/a_spec.rb", line: 1,
                                  message: Messages.http_status(expected: 200, actual: 404))]

      expect(build_clusters(failures)).to be_empty
    end

    it "does not relate different missing methods on nil" do
      failures = [
        request_failure(spec: "spec/a_spec.rb", line: 1, exception_class: "NoMethodError",
                        message: ["undefined method 'progress' for nil"]),
        request_failure(spec: "spec/b_spec.rb", line: 2, exception_class: "NoMethodError",
                        message: ["undefined method `progress' for nil:NilClass"]),
        request_failure(spec: "spec/c_spec.rb", line: 3, exception_class: "NoMethodError",
                        message: ["undefined method 'title' for nil"])
      ]
      clusters = build_clusters(failures)

      expect(clusters.size).to eq(1)
      expect(clusters.first.size).to eq(2)
    end
  end

  describe "determinism" do
    let(:failures) do
      Array.new(8) do |i|
        request_failure(spec: "spec/requests/s#{i}_spec.rb", line: i + 1,
                        message: Messages.http_status(expected: 200, actual: [404, 500][i % 2]))
      end
    end

    it "orders clusters largest first, then by run order" do
      expect(build_clusters(failures).map(&:key)).to eq(["http-status:404", "http-status:500"])
    end

    it "produces the same result twice" do
      expect(build_clusters(failures.dup).map(&:to_h)).to eq(build_clusters(failures).map(&:to_h))
    end
  end

  describe "the report" do
    let(:failures) do
      [request_failure(spec: "spec/requests/a_spec.rb", line: 1,
                       message: Messages.http_status(expected: 200, actual: 404)),
       request_failure(spec: "spec/requests/b_spec.rb", line: 2,
                       message: Messages.http_status_class(expected: "redirect", actual: 404))]
    end

    it "counts clusters alongside signatures" do
      report = build_report(failures)

      expect(report.group_count).to eq(2)
      expect(report.cluster_count).to eq(1)
    end

    it "can be switched off" do
      expect(build_report(failures, relate_failures: false).clusters).to be_empty
    end

    # The newest stage, and the least essential one: a report without clusters
    # is still worth having.
    it "still produces a report when clustering blows up" do
      allow(RSpec::Signal::Clusterer).to receive(:call).and_raise(ArgumentError, "boom")
      report = build_report(failures)

      expect(report.clusters).to be_empty
      expect(report.group_count).to eq(2)
    end

    it "publishes clusters in the JSON artifact" do
      json = JSON.parse(RSpec::Signal::Reporters::JsonReport.new(build_report(failures), config).render)

      expect(json["summary"]["related_clusters"]).to eq(1)
      expect(json["related"].first["label"]).to eq("unexpected 404 (Not Found) responses")
    end
  end
end
