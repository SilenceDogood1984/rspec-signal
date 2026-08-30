# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Shared code paths.** A third analysis layer that reads the *stack* rather than
  the message, and reports the first-party lines that more than one signature runs
  through. This relates failures whose messages have nothing in common — a `KeyError`
  and the `expect { }.not_to raise_error` that swallowed it — which no message-based
  extractor can do. Two rules hold it back: only the innermost first-party frames
  outside the spec suite are indexed (`config.code_path_depth`, default 5), and a
  line is reported only when two or more distinct signatures cross it. It claims a
  measured fact, never a cause. Configure with `config.max_code_paths`.
- **Run-to-run comparison.** `tmp/rspec-signal/history.json` records the last ten
  runs as signature digests and counts — no messages, no paths. Each run then reports
  what changed: `28 resolved, 3 new, 14 still failing, 3 changed signature`. The
  fourth bucket is what makes the rest trustworthy: an edit that only shifts line
  numbers reads as *changed*, never as a fix. The history survives the green run that
  deletes every other artifact. Turn it off with `config.track_history = false`.
- **Errors outside examples are captured, not just counted.** A spec file that fails
  to load, or a `before(:suite)` hook that blows up, now reaches the report with its
  exception, message, reduced trace and a rerun command. Previously only a count was
  possible. The formatter registers RSpec's `:message` notification and re-emits
  anything no other formatter is listening for, so nothing is lost or duplicated.
- Stdout in quiet mode is now a triage view: counts, what changed since the last run,
  and the top shared code paths. Enough to decide whether to open the report.
- `signal.json` gains `run_id`, `since_last_run`, `code_paths`, `outside_examples`,
  and per-signature `summary`, `rerun`, `rerun_ids` and `loose_signature`. The
  contract is documented in the README.

### Changed

- **Rerun commands now name RSpec example ids rather than locations**, shell-quoted.
  A location selects every example defined on that line, so the printed command could
  rerun ten examples for a loop-generated `it`, and the *same* command could be
  printed for two different signatures. Reruns are now exact. The human-readable
  location remains on the `Example` line above.
- The signature index shows the exception message rather than RSpec's
  `Failure/Error:` source echo, which was identical on every row.
- `signal.json` is `schema: 2`. Every schema 1 field keeps its name and meaning.

### Fixed

- `signal.json` ignored `max_message_lines` and `max_diff_lines`, so configuring
  them changed `signal.md` and left the JSON at the built-in defaults.
- The parallel merger dropped `shared_group_locations`, so the "Via shared example
  group" locator was missing from every parallel report.
- A run whose only problem was outside every example wrote no report.
- The terminal summary printed "0 failures" beside a report link when a spec file
  failed to load.
- `--dry-run` deleted the report written by the previous real run.

## [0.2.0] - 2026-08-27

### Added

- Ruby 2.7 support. `rspec-signal` now installs and runs on Ruby 2.7, 3.0, 3.1,
  3.2, 3.3 and 3.4; CI exercises the full matrix, including `rspec-signal-parallel`
  under `parallel_tests` on Ruby 2.7 with the last `parallel_tests` release that
  still supports it (4.7.1 — 4.7.2 and later, and all of the 5.x series, require
  Ruby 3.0+ or 3.1+).

### Changed

- `spec.required_ruby_version` lowered from `>= 3.1.0` to `>= 2.7.0`.
- Endless method definitions (a Ruby 3.0+ feature) were rewritten as ordinary
  `def...end` methods throughout the library and spec suite, with no behavior
  change.
- Gemspec summary and description now emphasize token-efficient RSpec output for
  AI coding agents.

## [0.1.0] - 2026-08-26

Initial release.

### Added

- `rspec-signal-parallel`, a quiet `parallel_tests` wrapper that isolates worker
  JSON by run and test-process number, then globally merges failures into the
  normal top-level artifacts without changing the parallel test exit status.
- Opt-in quiet agent mode through `--format RSpec::Signal::Formatter`, preserving
  RSpec exit status while suppressing verbose failure rendering.
- `signal.md` as the primary and sole Markdown artifact, with `full.txt` opt-in.
- Generic `expected`/`got` HTTP status mismatch recognition when the failing
  expression explicitly reads `response.status`.

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

- `RSpec::Signal::Formatter`, installed automatically by `require "rspec/signal"`,
  which writes a compact failure report without displacing RSpec's default
  terminal formatter.
- Three-way backtrace classification (project / library / framework) with
  first-party detection that covers Bundler `path:` gems and local Rails engines.
- Backtrace reduction that keeps every first-party frame plus the library frames
  adjacent to them, and never produces an empty trace.
- Deterministic failure fingerprinting and grouping on exception class,
  normalized message, culprit frame and application context.
- Artifacts in `tmp/rspec-signal/`: `signal.md`, `signal.json`, `full.txt`, and a
  `.gitignore`. Artifacts are removed when a run has no failures.
- Exception `cause` chains folded into the failure message, including the
  first-party frame each cause came from.
- Recovery of message and backtrace for `:aggregate_failures`, which RSpec exposes
  only through formatter-only callbacks.
- Capybara and Rails system-test diagnostics: URL, path, page title, status code,
  browser console output, and the screenshot path Rails writes.
- Credential scrubbing for auth headers, credential-shaped assignments, URL
  userinfo, and well-known token formats, with hooks for project-specific patterns.

### Changed

- Diff hunk headers and HTML summary sizes are normalized out of the fingerprint,
  so a page one line longer is no longer a different failure.

[Unreleased]: https://github.com/SilenceDogood1984/rspec-signal/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/SilenceDogood1984/rspec-signal/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/SilenceDogood1984/rspec-signal/releases/tag/v0.1.0
