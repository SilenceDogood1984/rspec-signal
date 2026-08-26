# frozen_string_literal: true

# Helpers for assembling the pipeline against synthetic input, without booting
# a real RSpec run.
module Builders
  def signal_config(**overrides)
    config = RSpec::Signal::Configuration.new
    # Never inherit the ambient enable/disable switch: these configs are the
    # subject under test, not the one running the suite.
    config.enabled = true
    config.project_root = Backtraces::ROOT
    config.output_dir = Dir.mktmpdir("rspec-signal-spec")
    overrides.each { |key, value| config.public_send(:"#{key}=", value) }
    config.reset_memoized!
    config
  end

  def parse_frames(backtrace, config: signal_config)
    RSpec::Signal::Backtrace::Parser.parse(backtrace, config.classifier)
  end

  def reduce(backtrace, config: signal_config)
    config.reducer.call(parse_frames(backtrace, config: config))
  end

  def build_message(lines, config: signal_config)
    RSpec::Signal::Message.new(Array(lines), redactor: config.redactor, project: config.project,
                                             html_threshold: config.html_threshold)
  end

  # Builds a {RSpec::Signal::Failure} the same way {RSpec::Signal::FailureBuilder}
  # would, but from literal values.
  def build_failure(backtrace:, message: ["boom"], exception_class: "RuntimeError",
                    description: "an example", spec_location: nil, config: signal_config, **rest)
    frames = parse_frames(backtrace, config: config)
    spec_frame = frames.reverse.find { |frame| frame.project? && frame.display_path.include?("_spec.rb") }
    spec_location ||= spec_frame&.location || frames.find(&:project?)&.location || "spec/example_spec.rb:1"

    RSpec::Signal::Failure.new(
      description: description,
      spec_location: spec_location,
      exception_class: exception_class,
      message: build_message(message, config: config),
      reduced: config.reducer.call(frames),
      frames: frames,
      **rest
    )
  end

  def build_clusters(failures) = RSpec::Signal::Clusterer.call(failures)

  def build_report(failures, **rest)
    RSpec::Signal::Report.new(
      failures: failures,
      example_count: rest.delete(:example_count) || failures.size,
      **rest
    )
  end

  def render_markdown(report, config: signal_config)
    RSpec::Signal::Reporters::Markdown.new(report, config).render
  end

  # Every location mentioned anywhere in a rendered trace.
  def trace_locations(reduced)
    reduced.frames.map(&:location)
  end
end
