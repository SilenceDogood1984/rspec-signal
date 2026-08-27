# frozen_string_literal: true

require_relative "lib/rspec/signal/version"

Gem::Specification.new do |spec|
  spec.name    = "rspec-signal"
  spec.version = RSpec::Signal::VERSION
  spec.authors = ["Chad Snow"]
  spec.email   = ["chaddsnow@gmail.com"]

  spec.summary = "Token-efficient RSpec failure output for AI coding agents."
  spec.description = <<~DESC
    rspec-signal turns noisy RSpec failures into compact, token-efficient diagnostic
    reports for AI coding agents. It removes repetitive framework backtraces, preserves
    the application and library context that matters, groups related failures, and
    writes a focused Markdown report instead of forcing an agent to consume thousands
    of lines of raw RSpec output.
  DESC

  spec.homepage = "https://github.com/SilenceDogood1984/rspec-signal"
  spec.license  = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["source_code_uri"]   = spec.homepage
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"]   = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "exe/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE"
  ]
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  spec.executables = %w[rspec-signal rspec-signal-parallel]

  spec.add_dependency "rspec-core", ">= 3.10", "< 4.0"
end
