# frozen_string_literal: true

RSpec.describe "shared code path analysis" do
  let(:config) { signal_config }
  let(:failures) do
    [
      through_serializer(raise_line: 11, exception_class: "TypeError",
                         message: ["can't convert nil into Float"],
                         spec: "spec/requests/orders_spec.rb", spec_line: 8),
      through_serializer(raise_line: 12, exception_class: "NoMethodError",
                         message: ["undefined method `iso8601' for nil"],
                         spec: "spec/requests/invoices_spec.rb", spec_line: 21)
    ]
  end

  # Two different exceptions raised from two different lines, both reached
  # through the same serializer. Nothing about their messages relates them --
  # only the stack does.
  def through_serializer(raise_line:, exception_class:, message:, spec:, spec_line:)
    backtrace = [
      Backtraces.app("app/presenters/order.rb", raise_line, "render"),
      Backtraces.app("app/serializers/order.rb", 5, "call"),
      Backtraces.app(spec, spec_line, "block (2 levels) in <top (required)>")
    ] + Backtraces.rspec_tail
    build_failure(config: config, backtrace: backtrace, exception_class: exception_class,
                  message: message, description: "#{spec}:#{spec_line}")
  end

  it "leaves the exact signatures alone: these really are two failures" do
    expect(RSpec::Signal::Grouper.call(failures).size).to eq(2)
  end

  it "finds no symptom relating them, because their messages have nothing in common" do
    expect(RSpec::Signal::Clusterer.call(failures)).to be_empty
  end

  it "relates them by the line both stacks run through" do
    paths = RSpec::Signal::CodePaths.call(failures)

    expect(paths.map(&:location)).to include("app/serializers/order.rb:5")
    shared = paths.find { |path| path.location == "app/serializers/order.rb:5" }
    expect(shared.signature_count).to eq(2)
    expect(shared.size).to eq(2)
  end

  it "records the method the line was reached under" do
    shared = RSpec::Signal::CodePaths.call(failures).find { |p| p.location == "app/serializers/order.rb:5" }

    expect(shared.labels).to eq(["call"])
  end

  # The same refusal rule the symptom clusterer uses. A line crossed by one
  # signature is already reported as that signature's app context.
  it "refuses a location crossed by only one signature" do
    single = [failures.first, failures.first]

    expect(RSpec::Signal::CodePaths.call(single)).to be_empty
  end

  it "ignores the spec suite itself, which every failure passes through" do
    locations = RSpec::Signal::CodePaths.call(failures).map(&:location)

    expect(locations).to all(start_with("app/"))
  end

  it "ignores framework and library frames" do
    locations = RSpec::Signal::CodePaths.call(failures).map(&:location)

    expect(locations).to all(satisfy { |location| !location.include?("rspec-") })
  end

  it "orders by signatures spanned, then examples, then first appearance" do
    paths = RSpec::Signal::CodePaths.call(failures)

    expect(paths.map(&:signature_count)).to eq(paths.map(&:signature_count).sort.reverse)
  end

  it "is deterministic across repeated analysis of the same failures" do
    first = RSpec::Signal::CodePaths.call(failures).map(&:to_h)
    second = RSpec::Signal::CodePaths.call(failures).map(&:to_h)

    expect(first).to eq(second)
  end

  it "stops looking beyond the configured depth" do
    deep = build_failure(config: config, backtrace: Backtraces.pure_ruby, message: ["a"])
    other = build_failure(config: config, backtrace: Backtraces.pure_ruby, message: ["b"])

    expect(RSpec::Signal::CodePaths.call([deep, other], depth: 1).map(&:location))
      .to eq(["lib/invoicer/calculator.rb:31"])
  end

  it "serialises the facts a consumer needs" do
    shared = RSpec::Signal::CodePaths.call(failures).find { |p| p.location == "app/serializers/order.rb:5" }

    expect(shared.to_h).to include(location: "app/serializers/order.rb:5", signature_count: 2, examples: 2)
    expect(shared.to_h[:signatures].size).to eq(2)
  end
end
