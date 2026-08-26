# frozen_string_literal: true

RSpec.describe "failure grouping" do
  let(:config) { signal_config }

  def capybara_failure(spec:, line:, selector: "#reader-shelf", description: nil)
    build_failure(
      config: config,
      backtrace: Backtraces.capybara_element_not_found(spec: spec, line: line),
      exception_class: "Capybara::ElementNotFound",
      description: description || "#{spec}:#{line} finds the shelf",
      message: ["Failure/Error: expect(page).to have_css(#{selector.inspect})", "",
                "Capybara::ElementNotFound:", "  Unable to find css #{selector.inspect}"]
    )
  end

  def matcher_failure(spec:, line:, expected:, actual:)
    build_failure(
      config: config,
      backtrace: Backtraces.expectation_not_met(spec: spec, line: line),
      exception_class: "RSpec::Expectations::ExpectationNotMetError",
      description: "#{spec}:#{line} matches",
      message: ["Failure/Error: expect(value).to eq(#{expected})", "",
                "  expected: #{expected}", "       got: #{actual}"]
    )
  end

  describe "many examples with one root cause" do
    let(:failures) do
      [
        capybara_failure(spec: "spec/system/reader_spec.rb", line: 104),
        capybara_failure(spec: "spec/system/foo_spec.rb", line: 27),
        capybara_failure(spec: "spec/system/bar_spec.rb", line: 81)
      ]
    end
    let(:groups) { RSpec::Signal::Grouper.call(failures) }

    it "collapses them into a single signature" do
      expect(groups.size).to eq(1)
      expect(groups.first.size).to eq(3)
    end

    it "does not lose any of the affected examples" do
      expect(groups.first.affected_locations).to contain_exactly(
        "spec/system/reader_spec.rb:104",
        "spec/system/foo_spec.rb:27",
        "spec/system/bar_spec.rb:81"
      )
    end

    it "keeps every failure reachable from the group" do
      expect(groups.first.failures.size).to eq(3)
      expect(groups.first.others.size).to eq(2)
    end

    it "picks a representative that is one of the failures" do
      expect(failures).to include(groups.first.representative)
    end
  end

  describe "failures that look similar but are not" do
    it "keeps different missing selectors apart" do
      groups = RSpec::Signal::Grouper.call([
                                             capybara_failure(spec: "spec/system/a_spec.rb", line: 10,
                                                              selector: "#reader-shelf"),
                                             capybara_failure(spec: "spec/system/b_spec.rb", line: 20,
                                                              selector: "#checkout-button")
                                           ])

      expect(groups.size).to eq(2)
    end

    it "keeps the same exception raised from different application code apart" do
      first = build_failure(
        config: config,
        backtrace: Backtraces.active_record_invalid(service: "app/services/subscription_creator.rb",
                                                    service_line: 42, spec: "spec/a_spec.rb", spec_line: 3),
        exception_class: "ActiveRecord::RecordInvalid",
        message: ["ActiveRecord::RecordInvalid:", "  Validation failed: Email has already been taken"]
      )
      second = build_failure(
        config: config,
        backtrace: Backtraces.active_record_invalid(service: "app/services/invite_creator.rb",
                                                    service_line: 17, spec: "spec/b_spec.rb", spec_line: 9),
        exception_class: "ActiveRecord::RecordInvalid",
        message: ["ActiveRecord::RecordInvalid:", "  Validation failed: Email has already been taken"]
      )

      expect(RSpec::Signal::Grouper.call([first, second]).size).to eq(2)
    end

    it "keeps identical matcher failures in different specs apart" do
      groups = RSpec::Signal::Grouper.call([
                                             matcher_failure(spec: "spec/models/user_spec.rb", line: 27,
                                                             expected: "true", actual: "false"),
                                             matcher_failure(spec: "spec/models/order_spec.rb", line: 88,
                                                             expected: "true", actual: "false")
                                           ])

      expect(groups.size).to eq(2)
    end

    it "keeps different exception classes apart even with the same message" do
      groups = RSpec::Signal::Grouper.call([
                                             build_failure(config: config, backtrace: Backtraces.pure_ruby,
                                                           exception_class: "ArgumentError", message: ["boom"]),
                                             build_failure(config: config, backtrace: Backtraces.pure_ruby,
                                                           exception_class: "TypeError", message: ["boom"])
                                           ])

      expect(groups.size).to eq(2)
    end
  end

  describe "message normalization" do
    def error(message)
      build_failure(config: config, backtrace: Backtraces.pure_ruby,
                    exception_class: "ActiveRecord::RecordNotFound", message: [message])
    end

    it "treats record ids as interchangeable" do
      groups = RSpec::Signal::Grouper.call([
                                             error("Couldn't find User with 'id'=48213"),
                                             error("Couldn't find User with 'id'=91055")
                                           ])

      expect(groups.size).to eq(1)
    end

    it "treats object addresses as interchangeable" do
      groups = RSpec::Signal::Grouper.call([
                                             error("undefined method `name' for #<User:0x00007f9a1c0b2d48>"),
                                             error("undefined method `name' for #<User:0x00007fbb220c9910>")
                                           ])

      expect(groups.size).to eq(1)
    end

    it "does not treat different classes as interchangeable" do
      groups = RSpec::Signal::Grouper.call([
                                             error("Couldn't find User with 'id'=48213"),
                                             error("Couldn't find Order with 'id'=48213")
                                           ])

      expect(groups.size).to eq(2)
    end

    it "does not merge small numeric differences" do
      groups = RSpec::Signal::Grouper.call([error("expected 3 items, got 4"), error("expected 7 items, got 2")])

      expect(groups.size).to eq(2)
    end
  end

  describe "ordering" do
    it "puts the largest signature first" do
      failures = [
        capybara_failure(spec: "spec/a_spec.rb", line: 1, selector: "#one"),
        capybara_failure(spec: "spec/b_spec.rb", line: 2, selector: "#two"),
        capybara_failure(spec: "spec/c_spec.rb", line: 3, selector: "#two")
      ]

      expect(RSpec::Signal::Grouper.call(failures).map(&:size)).to eq([2, 1])
    end

    it "is stable across runs" do
      failures = Array.new(6) { |i| capybara_failure(spec: "spec/#{i}_spec.rb", line: i, selector: "##{i % 3}") }
      digests = ->(list) { RSpec::Signal::Grouper.call(list).map { |group| group.fingerprint.digest } }

      first_run = digests.call(failures)
      second_run = digests.call(failures.dup)

      expect(second_run).to eq(first_run)
    end
  end

  describe "the representative" do
    it "prefers the failure carrying the most first-party frames" do
      thin = build_failure(config: config, backtrace: Backtraces.expectation_not_met,
                           exception_class: "RuntimeError", message: ["boom"],
                           description: "thin", spec_location: "spec/models/user_spec.rb:27")
      rich = RSpec::Signal::Failure.new(
        description: "rich",
        spec_location: "spec/models/user_spec.rb:27",
        exception_class: "RuntimeError",
        message: build_message(["boom"], config: config),
        reduced: config.reducer.call(parse_frames(Backtraces.pure_ruby, config: config)),
        frames: parse_frames(Backtraces.expectation_not_met, config: config)
      )

      group = RSpec::Signal::Grouper.call([thin, rich]).first
      expect(group.representative.description).to eq("rich")
    end
  end
end
