# Changelog

## Unreleased

- Add `rspec-signal-parallel`, a quiet `parallel_tests` wrapper that isolates
  worker JSON by run and test-process number, then globally merges failures into
  the normal top-level artifacts without changing the parallel test exit status.

## Unreleased

- Add opt-in quiet agent mode through `--format RSpec::Signal::Formatter`, preserving RSpec exit status while suppressing verbose failure rendering.
- Make `signal.md` the primary Markdown artifact, retain `summary.md` as a compatibility copy, and make `full.txt` opt-in.
- Recognize generic `expected`/`got` HTTP status mismatches when the failing expression explicitly reads `response.status`.

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Related failure clustering.** A second, looser grouping layer beside the exact
  signatures. Failures are clustered on one shared diagnostic symptom — the HTTP
  status that actually came back, a missing Capybara selector, a route that does
  not exist, an ActiveRecord model or schema shape, an undefined method and its
  receiver, an uninitialized constant, or a namespaced exception class with nothing
  finer to go on. Reported as a short `## Related failures` section, in `signal.json`
  as `related`, and counted on the terminal summary. Exact signatures remain the
  authoritative grouping; a cluster only ever claims a likely common cause.
- A cluster is only reported when it spans more than one exact signature, so the
  layer never restates what the signature section already said.
- **HTML response reduction.** When a failure's actual value is a large HTML
  document — most often a Rails exception page — the markup is replaced by its
  size, `<title>`, headings and leading visible text. The expected value is left
  untouched, and the original is still written verbatim to `full.txt`.
- `config.relate_failures`, `config.max_clusters`, `config.max_cluster_specs`,
  `config.reduce_html` and `config.max_html_chars`.

### Changed

- Diff hunk headers and HTML summary sizes are normalized out of the fingerprint,
  so a page one line longer is no longer a different failure.

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
