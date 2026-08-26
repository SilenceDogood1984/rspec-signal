# frozen_string_literal: true

require "json"

RSpec.describe RSpec::Signal::ParallelMerger do
  let(:registry) { Dir.mktmpdir("registry") }
  let(:output) { Dir.mktmpdir("output") }

  after do
    FileUtils.rm_rf(registry)
    FileUtils.rm_rf(output)
  end

  it "combines totals and regroups identical failures from different workers" do
    config = RSpec::Signal.configuration
    config.output_dir = output
    config.reset_memoized!
    write_worker("1", examples: 2, failures: [failure("spec/a_spec.rb:2", "same")])
    write_worker("2", examples: 3, failures: [failure("spec/b_spec.rb:2", "same")])

    result = described_class.new(registry: registry, config: config).call

    expect(result.report.example_count).to eq(5)
    expect(result.report.failure_count).to eq(2)
    expect(result.report.group_count).to eq(1)
    expect(result.report.groups.first.affected_locations).to contain_exactly("spec/a_spec.rb:2", "spec/b_spec.rb:2")
  end

  it "does not read unregistered stale worker files" do
    write_worker("1", examples: 1, failures: [])
    File.write(File.join(registry, "stale.json"), JSON.generate(summary: { examples: 99 }))

    result = described_class.new(registry: registry).call

    expect(result.report.example_count).to eq(1)
  end

  it "rejects corrupt worker JSON" do
    path = File.join(registry, "worker-1.json")
    File.write(path, "{corrupt")
    File.write(File.join(registry, "1.path"), path)

    expect { described_class.new(registry: registry).call }.to raise_error(JSON::ParserError)
  end

  it "rejects inconsistent worker configuration" do
    write_worker("1", examples: 1, failures: [], configuration: { "max_groups" => 1 })
    write_worker("2", examples: 1, failures: [], configuration: { "max_groups" => 2 })

    expect { described_class.new(registry: registry).call }
      .to raise_error(ArgumentError, /inconsistent rspec-signal configuration/)
  end

  def write_worker(worker, examples:, failures:, configuration: {})
    path = File.join(registry, "worker-#{worker}.json")
    data = { "schema" => 2, "summary" => { "examples" => examples, "failures" => failures.size,
                                           "pending" => 0 }, "failures" => failures,
             "configuration" => configuration, "environment" => {} }
    File.write(path, JSON.generate(data))
    File.write(File.join(registry, "#{worker}.path"), path)
  end

  def failure(location, digest)
    { "description" => location, "location" => location, "exception" => "RuntimeError",
      "message" => ["broken"], "trace" => [{ "location" => location, "kind" => "project" }],
      "omitted_frames" => 3,
      "fingerprint" => { "exception" => "RuntimeError", "culprit" => location, "digest" => digest } }
  end
end
