# rspec-signal

[![CI](https://github.com/SilenceDogood1984/rspec-signal/actions/workflows/ci.yml/badge.svg)](https://github.com/SilenceDogood1984/rspec-signal/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/rspec-signal.svg)](https://rubygems.org/gems/rspec-signal)

**Your test suite has 43 failures. RSpec gives your coding agent 22,000 lines. `rspec-signal` gives it the parts that matter.**

RSpec's failure output is written for a human staring at a terminal, scrolling to the
one line they recognise. Hand the same output to an AI coding agent and you spend
thousands of tokens on `rspec-core/hooks.rb`, Bundler, and Thor before the agent
reaches a single line of your code — and you pay that cost forty-three times over,
even when all forty-three failures are one bug.

`rspec-signal` is a deterministic context-reduction layer between RSpec and a coding
agent. It writes `tmp/rspec-signal/summary.md`: a compact, model-neutral report you
can paste into any assistant or point an agent at.

It is not a prettier formatter. Your terminal output stays exactly as it was.

---

## Before and after

A run with 17 failures caused by 2 bugs. This is one failure out of the seventeen,
as RSpec prints it:

```text
  1) Shelf renders row set 0
     Failure/Error: @rows.map { |r| r.fetch(:title) }.join(", ")

     KeyError:
       key not found: :title
     # ./app/models/shelf.rb:4:in `fetch'
     # ./app/models/shelf.rb:4:in `block in render'
     # ./app/models/shelf.rb:4:in `map'
     # ./app/models/shelf.rb:4:in `render'
     # ./spec/models/shelf_spec.rb:5:in `block (3 levels) in <top (required)>'
     # /usr/local/bundle/gems/rspec-core-3.13.6/lib/rspec/core/example.rb:263:in `instance_exec'
     # /usr/local/bundle/gems/rspec-core-3.13.6/lib/rspec/core/example.rb:263:in `block in run'
     # /usr/local/bundle/gems/rspec-core-3.13.6/lib/rspec/core/example.rb:511:in `block in with_around_and_singleton_context_hooks'
     # /usr/local/bundle/gems/rspec-core-3.13.6/lib/rspec/core/hooks.rb:486:in `block in run'
     # ... 22 more frames of rspec-core, Bundler, Thor and bin/bundle ...

  2) Shelf renders row set 1
     ... the same 31 lines again ...

  3) Shelf renders row set 2
     ... and again, fifteen more times ...
```

677 lines. 72 KB. And here is what `rspec-signal` writes for the whole run:

````markdown
# RSpec Signal

**17 examples | 17 failures | 2 distinct signatures**
Backtraces reduced from 535 to 65 frames (470 framework/library frames omitted).

## 1. KeyError -- 12 examples

> Shelf renders row set 0

```text
Failure/Error: @rows.map { |r| r.fetch(:title) }.join(", ")

KeyError:
  key not found: :title
```

- Example `spec/models/shelf_spec.rb:4`
- Your code `app/models/shelf.rb:4`

**Trace**

```text
app/models/shelf.rb:4 in `fetch'
app/models/shelf.rb:4 in `block in render'
app/models/shelf.rb:4 in `map'
app/models/shelf.rb:4 in `render'
spec/models/shelf_spec.rb:5 in `block (3 levels) in <top (required)>'
[25 framework/runtime frames omitted]
```

**Rerun**

```bash
bundle exec rspec spec/models/shelf_spec.rb:4
```

**Also failing identically (11)**

```text
spec/models/shelf_spec.rb:4  (11 examples)
```
````

105 lines. 3 KB. Nothing an agent needs was removed: the failing expression, the
exception, the message, every frame of your own code, the exact file to open, and
the command to reproduce it.

Those numbers come from one synthetic run. Your ratio depends on how noisy your
backtraces are and how much your failures repeat — a suite of genuinely distinct
failures reduces far less, and that is correct behaviour.

## Installation

```ruby
# Gemfile
group :test do
  gem "rspec-signal"
end
```

Then require it from `spec_helper.rb` (or `rails_helper.rb`):

```ruby
require "rspec/signal"
```

That is the whole setup. Requiring the gem registers the formatter and puts RSpec's
default formatter back, so your terminal output is unchanged.

If you would rather be explicit, or you need it only in CI, skip the require and
name the formatter instead:

```bash
bundle exec rspec --format progress --format RSpec::Signal::Formatter
```

RSpec resolves `--format` names to constants, so `--format signal` is not something
RSpec can do for a third-party gem. That is why the require-based install exists.

## Usage

Run your specs as you always do:

```bash
bundle exec rspec
```

At the end you get two extra lines:

```text
936 examples, 43 failures

rspec-signal: 43 failures in 7 distinct signatures (1842 backtrace frames omitted)
AI report: tmp/rspec-signal/summary.md
```

Then hand the file to an agent:

```bash
claude "fix the failures in tmp/rspec-signal/summary.md"
```

Or paste its contents into any chat. The report contains no instructions to a model
— it is a diagnostic document, so it reads the same to Claude, Codex, Cursor, or a
human.

## Generated artifacts

```text
tmp/rspec-signal/
  summary.md    the report -- this is the one you hand over
  signal.json   the same data, machine readable, for CI and tooling
  full.txt      the original unreduced RSpec output, kept as an escape hatch
  .gitignore    written automatically; artifacts can contain application data
```

A run with **no** failures deletes these files. A stale report describing failures
you already fixed is worse than no report at all, because an agent will go and
"fix" them again.

`full.txt` exists so reduction is never lossy in practice. If the compact report
ever drops the one frame you needed, the original is in the same directory. Turn
it off with `config.write_full = false`.

Individual per-failure files are deliberately **not** written. With failures
collapsed into a handful of signatures, `summary.md` is already the unit you want
to paste, and a directory of near-duplicate fragments is just more to sift through.

## Filtering philosophy

The goal is not the shortest possible output. It is **the minimum context that
preserves diagnostic usefulness**. A 50-line report containing the clue beats a
10-line report that removed it.

Every backtrace frame is classified as one of three things:

| Kind | What it is | What happens to it |
|------|-----------|--------------------|
| **project** | Code in your repository, plus Bundler `path:` gems and local engines | Always kept |
| **library** | Third-party code: Capybara, ActiveRecord, Rack, Net::HTTP, the standard library | Kept only where it touches your code |
| **framework** | The test runner, the loader, the CLI: rspec-core, rspec-expectations, Bundler, Thor, Rake, binstubs, `<internal:>` | Always dropped |

The distinction that matters is the middle row. Library frames are not noise — a
Capybara `find` or an ActiveRecord `save!` is often the only thing that tells you
*what operation failed*. So for each run of library frames that directly touches
first-party code, `rspec-signal` keeps:

- the **entry point**: the outermost library frame with a real method name, which is
  the call your code actually made. Delegation shims whose frames are anonymous
  blocks (`capybara/dsl.rb:52 in block (2 levels) in <module:DSL>`) are skipped in
  favour of the frame that names the operation (`capybara/node/finders.rb:60 in find`).
- the **raise site**: the innermost frame of that run.
- one or two neighbours, budget permitting.

Library frames that touch no first-party code at all — a gem calling another gem
five layers down — are dropped and counted.

A worked example. Sixty-four frames in, six lines out:

```text
capybara/node/finders.rb:312 in `synced_resolve'
[2 library frames omitted]
capybara/node/finders.rb:60 in `find'
[1 library frame omitted]
capybara/dsl.rb:52 in `block (2 levels) in <module:DSL>'
spec/system/reader_self_reading_integrity_spec.rb:104 in `block (3 levels) in <top (required)>'
[47 framework/runtime frames omitted]
```

Two more rules keep the reduction honest:

- **First-party beats everything.** A frame in your repository is never classified as
  framework plumbing, whatever it is named. A checkout in `~/src/rspec-signal-demo/`
  does not lose all its own frames to a pattern match. The only exception is
  binstubs (`bin/rspec`, `bin/bundle`), which are plumbing wherever they live.
- **The trace is never empty.** If a failure happens entirely inside a gem, or
  entirely inside RSpec itself, the report falls back to the innermost non-framework
  frames and says so: *"No first-party frames in this backtrace; innermost frames
  shown instead."* Filtering that hides the only available evidence is a bug.

Two other things RSpec loses that `rspec-signal` keeps:

- **Exception causes.** RSpec puts the `Caused by:` chain in the *backtrace*, which
  is exactly what gets reduced away. A `PG::UniqueViolation` behind a bland
  `RuntimeError` is usually the answer, so the chain is folded into the message,
  with the first-party frame it came from.
- **Aggregated failures.** For `:aggregate_failures`, RSpec deliberately empties the
  message and moves the sub-failures into formatter-only callbacks, and the
  exception's own backtrace is the aggregator's internals. `rspec-signal` recovers
  both the sub-failures and the real backtrace from the first sub-exception.

## Grouping behaviour

Forty-three failures that are one bug should read as one bug. Failures are collapsed
by a deterministic fingerprint of four components:

| Component | What it is |
|-----------|-----------|
| **exception class** | `Capybara::ElementNotFound`, `ActiveRecord::RecordInvalid`, ... |
| **normalized message** | The message with volatile parts masked: object addresses, UUIDs, timestamps, record ids, temp paths. Small numbers are left alone — `expected 3, got 4` and `expected 7, got 2` are different failures. |
| **culprit** | The innermost frame that is not test-runner plumbing: the code that actually raised. |
| **app context** | The innermost first-party frame outside your spec suite. `nil` for a plain matcher failure; decisive when the same error comes from two different call sites. |

Deliberately **not** in the fingerprint: the example description, and the example's
own location. Fourteen specs in six files that all trip over the same missing DOM
node are one problem, not fourteen.

The four components are what stop over-collapsing:

- Two `Capybara::ElementNotFound` failures for **different selectors** stay apart —
  the message differs.
- Two `ActiveRecord::RecordInvalid` failures with the **same message** from
  `SubscriptionCreator` and `InviteCreator` stay apart — the app context differs.
- Two identical `expect(x).to be true` failures in **different specs** stay apart —
  a matcher failure raises at the spec line, so the culprit differs.
- The same missing record id in twenty specs collapses to one — ids are masked.

Each group renders one full trace, from the failure carrying the most first-party
frames, plus every affected example's location. Groups are ordered largest first,
with ties broken by run order, so two runs of the same suite produce byte-identical
reports.

## Configuration

None is required. Everything below is optional, in `spec_helper.rb`:

```ruby
RSpec::Signal.configure do |config|
  # Where artifacts go (relative to the project root, or absolute).
  config.output_dir = "tmp/rspec-signal"

  # Reduction budgets.
  config.max_frames           = 12  # frames kept per trace
  config.max_external_context = 3   # library frames kept per adjacent run
  config.max_project_frames   = 8   # first-party frames kept per trace
  config.fallback_frames      = 6   # frames shown when nothing else survives

  # Message budgets. Diffs are the biggest source of bloat.
  config.max_message_lines = 30
  config.max_diff_lines    = 20

  # Report budgets.
  config.max_affected_examples = 25   # locations listed per group
  config.max_groups            = nil  # signatures rendered in full (nil = all)

  # Artifacts.
  config.write_json      = true
  config.write_full      = true
  config.write_gitignore = true

  # Behaviour.
  config.enabled          = true
  config.terminal_summary = true

  # Secret scrubbing (see Privacy).
  config.redact             = true
  config.redaction_patterns = [/INTERNAL-[A-Z0-9]+/]
  config.redaction_filter   = ->(text) { text.gsub(customer_name, "[CUSTOMER]") }

  # Classification.
  config.project_root      = Rails.root.to_s
  config.extra_first_party = ["../billing-engine"]   # a sibling checkout
  config.ignore_patterns   << %r{/lib/my_test_harness/}  # your code, but plumbing
  config.framework_patterns << /vendor_test_runner-/     # a gem, but plumbing
  config.spec_patterns     << %r{\Aexamples/}            # where your specs live

  # Capybara.
  config.capture_capybara  = true
  config.capture_page_html = false
end
```

Two environment variables are honoured, which is usually what you want in CI:

```bash
RSPEC_SIGNAL_DISABLE=1        # turn the gem off entirely
RSPEC_SIGNAL_OUTPUT_DIR=...   # override the output directory
```

Note the two classification lists. `ignore_patterns` is checked **before**
first-party detection — it is how you say "this is my code, but treat it as
plumbing". `framework_patterns` is checked **after** — it is for third-party code
and cannot accidentally swallow your repository.

## Rails and Capybara

`rspec-signal` depends on `rspec-core` and nothing else. Rails, Capybara and
ActiveRecord are all optional; the gem gets richer when they are present.

**Rails.** The project root defaults to `Rails.root` when Rails is loaded, and the
report header records the Rails version. `app/`, `lib/`, `spec/`, and local engines
are first-party; `vendor/bundle` is not.

**System and feature specs.** For a failing example with `type: :system`,
`type: :feature`, or `js: true`, an `after(:each)` hook captures browser state into
the report:

```markdown
**Browser state**

- URL: `https://app.test/library`
- Page title: `Library`
- Status: `200`
- Console: `SEVERE: Uncaught TypeError: shelf.render is not a function`
- Screenshot: `tmp/screenshots/failures_reader_shelf.png`
```

Rails writes the screenshot itself on a system-test failure; `rspec-signal` finds the
path in `metadata[:extra_failure_lines]` and surfaces it as a link rather than
leaving it buried in the message. Browser console output is small and frequently
contains the real cause of a JavaScript-driven failure.

The whole capture is best effort and wrapped in rescues: a driver that cannot report
a status code just contributes less detail. It never asks Capybara for
`current_session`, which would *create* a session and possibly boot a browser — it
only reads a session that the test already opened.

Page HTML is **not** saved by default. It is frequently the clue, and it is also
100 KB of exactly the bloat this gem exists to remove. Enable it deliberately with
`config.capture_page_html = true`, and the report will link to the saved file.

## Privacy

Failure output contains whatever your tests put in it: fixture data, request bodies,
headers, environment values. These artifacts are explicitly meant to be handed to
external AI systems, so `rspec-signal` scrubs obvious credentials by default —
`Authorization` headers, credential-shaped assignments (`password:`, `api_key=`,
`?access_token=`), URL userinfo, and well-known token formats (AWS, GitHub, Slack,
Stripe, GitLab, Google, JWTs, PEM private key blocks).

It targets shapes that are unambiguous and deliberately does not guess at arbitrary
values, because false positives destroy the diagnostic value of a report:
`expected 3 items, got 4` and `undefined method 'password_digest' for nil` are left
exactly as they are.

**This is a safety net, not a guarantee. Review artifacts before sending them
somewhere you do not control.** `tmp/rspec-signal/.gitignore` is written
automatically so they do not reach version control by accident.

You can add your own patterns with `config.redaction_patterns`, post-process
everything with `config.redaction_filter`, or turn scrubbing off with
`config.redact = false`.

## Limitations

- **Errors outside examples.** A `before(:suite)` blow-up, or a spec file that fails
  to load, produces no failed examples. RSpec reports those only through its message
  stream, which a formatter cannot subscribe to without swallowing every other
  message. `rspec-signal` reports the count and says where to look, but cannot
  capture the text.
- **Parallel test runners.** Under `parallel_tests`, `knapsack` or similar, each
  process writes to the same directory and the last one wins. Give each process its
  own via `RSPEC_SIGNAL_OUTPUT_DIR=tmp/rspec-signal-$TEST_ENV_NUMBER`.
- **Grouping is a heuristic.** It is deterministic and explained above, but two
  genuinely different bugs that raise the same exception with the same message from
  the same line will collapse into one signature. The affected-example list always
  shows you everything that was merged.
- **No source packaging.** `rspec-signal` names files and lines; it does not embed
  source code. Agents working inside a repository can open the files themselves, and
  in v1 that is a better division of labour than guessing which snippets to inline.
- **Reduction depends on your suite.** Failures that are already distinct and already
  shallow reduce very little. That is the correct outcome, not a failure of the gem.

## Compatibility

- Ruby 3.1+
- RSpec 3.10+ (via `rspec-core`)
- Rails, Capybara, ActiveRecord: optional

The only runtime dependency is `rspec-core`.

## Development

```bash
bin/setup           # or: bundle install
bundle exec rake    # specs + RuboCop
bundle exec rspec
bundle exec rubocop
```

The test suite runs `rspec-signal` on itself, so a failing run writes its own
report to `tmp/rspec-signal/summary.md`.

Most of the gem is plain Ruby with no RSpec dependency. Only `Formatter` and
`FailureBuilder` touch RSpec's notification API, which is what lets the reduction,
grouping and rendering stages be tested directly against synthetic fixtures in
`spec/fixtures/backtraces.rb`. `spec/integration/end_to_end_spec.rb` shells out to
real `rspec` processes in generated throwaway projects.

Tests deliberately assert on output *size* as well as content, so a future change
cannot quietly let noise back in.

## Contributing

Bug reports and pull requests are welcome at
<https://github.com/SilenceDogood1984/rspec-signal>.

If you are reporting a case where reduction removed something important, the most
useful thing you can attach is the raw backtrace — a new fixture in
`spec/fixtures/backtraces.rb` is the ideal shape for it.

## License

MIT. See [LICENSE](LICENSE).
