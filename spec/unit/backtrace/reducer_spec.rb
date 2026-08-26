# frozen_string_literal: true

RSpec.describe RSpec::Signal::Backtrace::Reducer do
  # The whole point of the gem: a grotesque backtrace must come out small
  # without losing the frames that explain the failure.
  describe "a system spec drowning in framework frames" do
    let(:backtrace) { Backtraces.capybara_element_not_found }
    let(:reduced) { reduce(backtrace) }
    let(:locations) { trace_locations(reduced) }

    it "starts from a backtrace no human would read" do
      expect(backtrace.size).to be > 60
    end

    it "collapses to a handful of frames" do
      expect(reduced.kept_count).to be_between(3, 8)
      expect(reduced.to_a.size).to be <= 10
    end

    it "keeps the first-party spec location" do
      expect(locations).to include("spec/system/reader_self_reading_integrity_spec.rb:104")
    end

    it "keeps the Capybara call the spec made" do
      expect(reduced.to_a.join("\n")).to include("capybara/node/finders.rb:60 in `find'")
    end

    it "keeps the frame that actually raised" do
      expect(locations.first).to eq("capybara/node/finders.rb:312")
    end

    it "drops every rspec-core, bundler and thor frame" do
      expect(locations.join("\n")).not_to match(%r{rspec-core|bundler|thor|bin/bundle})
    end

    it "reports how many frames it dropped" do
      expect(reduced.omitted[:framework]).to be > 40
      expect(reduced.to_a.last).to match(%r{\[\d+ framework/runtime frames omitted\]})
    end

    it "does not claim to be a fallback" do
      expect(reduced).not_to be_fallback
    end
  end

  describe "application frames mixed with ActiveRecord internals" do
    let(:reduced) { reduce(Backtraces.active_record_invalid) }
    let(:locations) { trace_locations(reduced) }

    it "keeps every application frame" do
      expect(locations).to include("app/services/subscription_creator.rb:42",
                                   "app/services/subscription_creator.rb:12",
                                   "spec/models/subscription_spec.rb:18")
    end

    it "keeps the ActiveRecord frame that raised" do
      expect(locations).to include("activerecord/validations.rb:80")
    end

    it "keeps the ActiveRecord call the application made" do
      expect(locations).to include("activerecord/transactions.rb:313")
    end

    it "drops the transaction plumbing in between" do
      expect(locations).not_to include("activerecord/connection_adapters/abstract/transaction.rb:606")
    end

    it "identifies the innermost application frame" do
      expect(reduced.primary_location.location).to eq("app/services/subscription_creator.rb:42")
    end
  end

  describe "a plain matcher failure" do
    let(:reduced) { reduce(Backtraces.expectation_not_met) }

    it "reduces to just the spec line" do
      expect(trace_locations(reduced)).to eq(["spec/models/user_spec.rb:27"])
    end

    it "drops rspec-expectations internals, which explain nothing" do
      expect(reduced.to_a.join).not_to include("rspec-expectations")
    end

    it "does not leave a dangling gap above the first useful frame" do
      expect(reduced.entries.first).to be_a(RSpec::Signal::Backtrace::Frame)
    end
  end

  describe "a pure Ruby project with no Rails and no Capybara" do
    let(:reduced) { reduce(Backtraces.pure_ruby) }

    it "keeps the whole first-party call chain" do
      expect(trace_locations(reduced)).to eq(["lib/invoicer/calculator.rb:31",
                                              "lib/invoicer/calculator.rb:12",
                                              "spec/calculator_spec.rb:14"])
    end
  end

  describe "application code sandwiched between gem layers" do
    let(:reduced) { reduce(Backtraces.rack_middleware_stack) }
    let(:locations) { trace_locations(reduced) }

    it "keeps both application frames" do
      expect(locations).to include("app/controllers/checkout_controller.rb:22",
                                   "app/controllers/concerns/authentication.rb:18")
    end

    it "keeps the library frame that called into application code" do
      expect(locations).to include("activesupport/callbacks.rb:121")
    end

    it "stays within the frame budget" do
      expect(reduced.kept_count).to be <= 12
    end
  end

  # Edge case: filtering must never be able to produce an empty trace.
  describe "when aggressive filtering would remove everything" do
    context "with a failure entirely inside third-party code" do
      let(:reduced) { reduce(Backtraces.library_only) }

      it "falls back to the innermost non-framework frames" do
        expect(trace_locations(reduced)).to start_with("net-http/net/http.rb:1610")
        expect(reduced).to be_fallback
      end

      it "still drops the framework tail" do
        expect(trace_locations(reduced).join).not_to include("rspec-core")
      end
    end

    context "with a backtrace that is nothing but framework frames" do
      let(:reduced) { reduce(Backtraces.framework_only) }

      it "shows something rather than nothing" do
        expect(reduced).not_to be_empty
        expect(reduced).to be_fallback
      end
    end

    context "with an empty backtrace" do
      it "returns an empty result instead of raising" do
        expect(reduce([])).to be_empty
      end
    end

    context "with a nil backtrace" do
      it "returns an empty result instead of raising" do
        expect(reduce(nil)).to be_empty
      end
    end

    context "with unparseable garbage" do
      it "keeps what it can" do
        reduced = reduce(["", "   ", "not a backtrace line at all"])
        expect(reduced.to_a).to eq(["not a backtrace line at all"])
      end
    end
  end

  describe "runaway recursion" do
    let(:reduced) { reduce(Backtraces.recursive(depth: 200)) }

    it "collapses the repeated frame into one entry with a count" do
      expect(reduced.kept_count).to eq(2)
      expect(reduced.to_a.first).to include("app/models/tree_node.rb:14", "(x200)")
    end
  end

  describe "budgets" do
    it "honours max_frames" do
      config = signal_config(max_frames: 3)
      expect(reduce(Backtraces.rack_middleware_stack, config: config).kept_count).to eq(3)
    end

    it "honours max_external_context" do
      config = signal_config(max_external_context: 1)
      locations = trace_locations(reduce(Backtraces.capybara_element_not_found, config: config))
      expect(locations.count { |location| location.start_with?("capybara/") }).to eq(1)
    end

    it "keeps the innermost first-party frame even when the project cap is hit" do
      config = signal_config(max_project_frames: 1, max_frames: 2)
      reduced = reduce(Backtraces.active_record_invalid, config: config)
      expect(trace_locations(reduced)).to include("app/services/subscription_creator.rb:42")
    end
  end

  describe "measured reduction" do
    # A guard against future changes quietly letting noise back in.
    {
      "capybara_element_not_found" => 8,
      "active_record_invalid" => 10,
      "expectation_not_met" => 3,
      "pure_ruby" => 5,
      "rack_middleware_stack" => 15
    }.each do |fixture, max_lines|
      it "renders #{fixture} in at most #{max_lines} lines" do
        backtrace = Backtraces.public_send(fixture)
        rendered = reduce(backtrace).to_a

        expect(rendered.size).to be <= max_lines,
                                 "expected <= #{max_lines} lines, got #{rendered.size}:\n#{rendered.join("\n")}"
        expect(rendered.size).to be < backtrace.size / 4
      end
    end
  end
end
