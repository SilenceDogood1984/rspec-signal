# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-10-03

RSpec Signal now tells an agent what changed since the last run, gives it an exact
command to rerun each problem, and refuses to leave a stale report behind. No
configuration is required; every addition below is on by default except the
experimental relationships layer.

### Added

- **"Since last run" comparison.** `tmp/rspec-signal/history.json` records the last
  ten runs as signature digests, counts and the run's selection. Each run then
  reports what changed: `Signatures: 28 resolved, 3 new, 14 persistent, 3 changed; failures: 42 -> 17`.
  The *changed signature* bucket keeps an edit that merely shifts line numbers from
  reading as a fix. History survives the green run that clears the report, so
  "42 failures became 0" is still reported. Disable with `config.track_history = false`.
- **Comparisons only between like runs.** A run is compared with the most recent run
  of an equivalent selection — same paths and filters (`--tag`, `-e`, `--pattern`,
  `--only-failures`, ...). A targeted rerun of one file is never measured against a
  full-suite run, and a full suite is never reported as "resolved" because a narrower
  run came in between. Runs that did not finish — a load error, an aborted run, fewer
  examples executed than selected — are neither compared nor recorded, and the
  terminal says `Since last run: comparison skipped (run incomplete)` rather than
  staying silent. `rspec-signal-parallel` merges its workers' selections and
  compares only when they agree.
- **Exact reruns.** Every signature carries a copy-pasteable `rerun` command that runs
  its representative example and nothing else, plus `rerun_ids` for every affected
  example. Commands name RSpec example ids (shell-quoted), not file:line locations,
  which select every example defined on that line.
- **Shared code paths.** Reports the first-party lines that more than one signature
  runs through, found from the stack rather than the message — so a `KeyError` and
  the `expect { }.not_to raise_error` that swallowed it are related. It claims a
  measured fact, never a cause. Configure with `config.code_path_depth` and
  `config.max_code_paths`.
- **Errors outside examples are captured, not just counted.** A spec file that fails
  to load, or a `before(:suite)` hook that raises, now reaches the report with its
  exception, message, reduced trace and a rerun command. A run whose only problem is
  outside every example now writes a report.
- **Experimental relationships (off by default).** With `config.causal_analysis = true`,
  signatures are related by structural evidence only — a shared `before(:context)`
  exception, one exception at one first-party line, a missing `ENV` key, constant or
  method, or one failing setup step — and grouped as CAUSAL, SCOPE or INDEPENDENT.
  Published in `signal.json` as an `analysis` block marked `"experimental": true`,
  whose fields may change in any release.
- **Quiet-mode progress line.** A quiet run shows one repainted progress line so a
  long suite is distinguishable from a hang. It is drawn only on a terminal; redirected
  output contains no control sequences.
- `signal.json` is now `schema: 2` and adds `run_id`, `since_last_run`, `code_paths`,
  `outside_examples`, and per-signature `summary`, `rerun`, `rerun_ids` and
  `loose_signature`. Every schema 1 field keeps its name and meaning. The contract
  is documented in the README.
- `rspec-signal` and `rspec-signal-parallel` clear the previous `signal.md`,
  `signal.json` and `full.txt` before RSpec boots, so even a run that aborts before
  the formatter loads cannot leave an earlier run's report looking current. Set
  `RSPEC_SIGNAL_DISABLE=1` to leave artifacts untouched, and
  `RSPEC_SIGNAL_OUTPUT_DIR` when a custom directory needs this early guarantee.

### Changed

- **The terminal summary is rewritten to lead with the next action.** It now reads
  `RSpec totals`, `Signal problems`, the top three problems each with an `Exact rerun`
  command, any outside-example errors, `Since last run`, and `Report:`. The old
  `rspec-signal: N failures in N distinct signatures, ... (N backtrace frames omitted)`
  line is gone, and `rspec-signal-parallel` prints the same summary as `rspec-signal`.
  **Anything that parses the terminal text will need updating**; `signal.json` is the
  stable interface.
- **Reports are published atomically.** `signal.md`, `signal.json` and `full.txt` are
  staged together and renamed into place with `signal.md` last, so `signal.md` is the
  marker that its companions belong to the same completed run. A rendering failure
  leaves no current report rather than a mixed one. `--dry-run` no longer deletes the
  report written by the previous real run.
- **RSpec's `Failure/Error:` source echo is no longer part of a signature.** A broken
  factory used to become one signature per `create` call site; now it is one. The echo
  is still shown, and the signature index shows the exception message instead.
- `history.json` records the run's selection — normalized spec paths and filter
  values — in addition to digests and counts. It still contains no failure messages,
  backtraces or source.

### Fixed

- In a parallel run, every signature's loose digest came from a placeholder message,
  so unrelated failures of the same exception class could be paired as one *changed*
  signature. Workers now carry the real digest.
- One error outside examples repeated across many spec files — a helper every file
  requires failing at boot — rendered one identical section per file. It now renders
  once, naming every file it stopped from loading.
- `signal.json` ignored `max_message_lines` and `max_diff_lines`; configuring them
  changed `signal.md` and left the JSON at the built-in defaults.
- The parallel merger dropped `shared_group_locations`, so the "Via shared example
  group" locator was missing from every parallel report.
- The terminal summary printed "0 failures" beside a report link when a spec file
  failed to load.
- A stale `signal.md` from a previous run could survive an aborted run or a failed
  report write.

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

[Unreleased]: https://github.com/SilenceDogood1984/rspec-signal/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/SilenceDogood1984/rspec-signal/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/SilenceDogood1984/rspec-signal/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/SilenceDogood1984/rspec-signal/releases/tag/v0.1.0
