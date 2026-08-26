# frozen_string_literal: true

require_relative "lib/rspec/signal/version"

Gem::Specification.new do |spec|
  spec.name    = "rspec-signal"
  spec.version = RSpec::Signal::VERSION
  spec.authors = ["Chad Snow"]
  spec.email   = ["chaddsnow@gmail.com"]

  spec.summary = "Turn noisy RSpec failures into compact, high-signal reports for AI coding agents."
  spec.description = <<~DESC
    rspec-signal is a deterministic context-reduction layer between RSpec and an AI
    coding agent. It collapses framework and runtime backtrace plumbing, keeps
    first-party frames plus the small amount of library context that explains the
    failing operation, groups repeated failures into distinct signatures, and writes
    a compact Markdown report you can hand straight to a coding agent.
  DESC

  spec.homepage = "https://github.com/SilenceDogood1984/rspec-signal"
  spec.license  = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

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
