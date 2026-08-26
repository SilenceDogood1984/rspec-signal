# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-26

Initial release.

### Added

- `RSpec::Signal::Formatter`, installed automatically by `require "rspec/signal"`,
  which writes a compact failure report without displacing RSpec's default
  terminal formatter.
- Three-way backtrace classification (project / library / framework) with
  first-party detection that covers Bundler `path:` gems and local Rails engines.
- Backtrace reduction that keeps every first-party frame plus the library frames
  adjacent to them, and never produces an empty trace.
- Deterministic failure fingerprinting and grouping on exception class,
  normalized message, culprit frame and application context.
- Artifacts in `tmp/rspec-signal/`: `summary.md`, `signal.json`, `full.txt`, and a
  `.gitignore`. Artifacts are removed when a run has no failures.
- Exception `cause` chains folded into the failure message, including the
  first-party frame each cause came from.
- Recovery of message and backtrace for `:aggregate_failures`, which RSpec exposes
  only through formatter-only callbacks.
- Capybara and Rails system-test diagnostics: URL, path, page title, status code,
  browser console output, and the screenshot path Rails writes.
- Credential scrubbing for auth headers, credential-shaped assignments, URL
  userinfo, and well-known token formats, with hooks for project-specific patterns.

[Unreleased]: https://github.com/SilenceDogood1984/rspec-signal/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/SilenceDogood1984/rspec-signal/releases/tag/v0.1.0
