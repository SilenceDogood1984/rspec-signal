# rspec-signal

[![CI](https://github.com/SilenceDogood1984/rspec-signal/actions/workflows/ci.yml/badge.svg)](https://github.com/SilenceDogood1984/rspec-signal/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/rspec-signal.svg)](https://rubygems.org/gems/rspec-signal)

**In one real-world run, 42 failures produced roughly 22,000 lines of raw RSpec output. `rspec-signal` reduced that to roughly 1,100 lines of focused diagnostics.**

RSpec's failure output is written for a human staring at a terminal, scrolling to the
one line they recognise. Hand the same output to an AI coding agent and you spend
thousands of tokens on `rspec-core/hooks.rb`, Bundler, and Thor before the agent
reaches a single line of your code — and you pay that cost repeatedly,
even when many failures stem from one bug.

`rspec-signal` is a deterministic failure-intelligence layer between RSpec and a
coding agent. It answers one question -- *what actually failed, and what is it
really?* -- in a bounded number of tokens, with an exact command to verify each fix.

In normal mode your terminal output stays as it was. In opt-in agent mode it also
becomes a quiet formatter that prevents verbose failures from entering an autonomous
agent's context.

No model, no network, no API key. Two runs of the same suite produce byte-identical
reports.

## Quickstart

```ruby
# Gemfile
group :test do
  gem "rspec-signal"
end
```

```ruby
# spec/spec_helper.rb (or rails_helper.rb)
require "rspec/signal"
```

```bash
bundle exec rspec-signal
```

That is the whole setup. Your terminal output is unchanged by the require; the
`rspec-signal` command is the quiet wrapper for agents. Either way you get
`tmp/rspec-signal/signal.md`.

## Vocabulary

Six words the report uses, defined once.

| Term | Meaning |
|------|---------|
| **signature** | A set of failures that *are* the same failure, by an exact four-part fingerprint. Authoritative |
| **related cluster** | Failures across more than one signature that share one strong diagnostic *symptom*. A hint, never a diagnosis |
| **symptom** | The one characteristic a cluster is keyed on: an HTTP status, a missing selector, a route, a model, a constant |
| **shared code path** | A line of *your* code that more than one signature runs through. A measured fact about stacks, not messages |
| **culprit** | The innermost frame that is not test-runner plumbing: the code that actually raised |
| **app context** | The innermost first-party frame outside your spec suite: the file to open first |

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
bundle exec rspec './spec/models/shelf_spec.rb[1:1]'
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

See [Quickstart](#quickstart) for the two lines. Requiring the gem registers the
formatter and puts RSpec's default formatter back, so your terminal output is
unchanged.

If you would rather be explicit, or you need it only in CI, skip the require and
name the formatter instead:

```bash
bundle exec rspec --require rspec/signal --format progress --format RSpec::Signal::Formatter
```

## Autonomous-agent workflow (quiet mode)

Run the gem's quiet wrapper for an autonomous agent. It forwards every argument to
RSpec and exits with RSpec's status:

```bash
bundle exec rspec-signal
bundle exec rspec-signal spec/models/user_spec.rb:42
```

The wrapper selects Signal as RSpec's only formatter, so no verbose failure formatter
is added. On an interactive terminal, a bounded single-line progress bar is repainted
in place; redirected stdout contains no live progress or control sequences. A failing
suite remains non-zero; a passing suite remains zero. The
low-level `bundle exec rspec --format RSpec::Signal::Formatter` interface remains
available after requiring `rspec/signal` from the spec helper.

Stdout is a tool call's return value, so stdout is the triage view — enough to decide
whether to open the report at all:

```text
2085 examples, 42 failures, 6 pending

rspec-signal: 42 failures in 35 distinct signatures, 4 related clusters (2767 backtrace frames omitted)
Since last run: 28 resolved, 3 new, 14 still failing (42 -> 17 failures)
Shared code paths: app/models/reader.rb:88 (9 signatures), app/api/serializer.rb:31 (4 signatures)
Report: tmp/rspec-signal/signal.md
```

```text
RSpec runs the full suite
↓
verbose failure bodies and framework backtraces are not printed
↓
rspec-signal writes tmp/rspec-signal/signal.md and prints five lines of triage
↓
the agent reads signal.md only if the triage is not enough
↓
the agent reruns one signature by its exact example ids
↓
the next run reports what that fix resolved, and what it did not
```

### Parallel suites (`parallel_tests`)

For suites normally launched with `parallel_rspec`, use the dedicated wrapper:

```bash
bundle exec rspec-signal-parallel spec -n 8
```

All arguments are forwarded unchanged to `parallel_rspec`, so its file selection,
process-count, grouping, and runtime-log options continue to work. The wrapper adds
Signal as the quiet RSpec formatter through `SPEC_OPTS`; individual workers therefore
do not print failure bodies or backtraces. `parallel_tests` may still print its own
bounded process and progress output.

The wrapper gives every invocation a random run ID. Workers use
`TEST_ENV_NUMBER` (with the first process numbered `1`) and write structured files to:

```text
tmp/rspec-signal/workers/<run-id>/<test-process-number>/signal.json
```

After `parallel_rspec` returns, the parent reads those worker files, reconstructs all
failures, and performs exact grouping and related-failure clustering globally. It then
writes the usual top-level `signal.md` and `signal.json` (subject to the normal
artifact configuration). Thus identical or related failures in different
partitions appear together in the final report. If `write_full` is enabled, the parent
deterministically builds one top-level `full.txt` from the worker payloads; workers
never share that file.

Workers also record the aggregation-relevant configuration used to reduce and render
their results. The parent requires these settings to match across every worker rather
than silently applying whichever worker happens to finish first. A mismatch fails the
aggregation with a concise error, which usually indicates conditional configuration in
the project's spec helper.

Each run has a new ID and the merger only reads paths registered for that invocation,
so abandoned or stale worker reports cannot enter a later report. Once a run's worker
payloads have been merged into the top-level report, that run's worker directory is
removed; a run whose merge fails leaves its worker directory in place for diagnosis.
Missing registered artifacts and merge errors produce concise warnings. A merge error
makes an otherwise successful command fail, while a failing `parallel_rspec` status is
always preserved.

This first implementation supports local filesystem execution through
`parallel_tests`. Other parallel RSpec runners, multiple hosts, and distributed CI
workers are not yet guaranteed. Add `parallel_tests` to the application's test bundle;
it is deliberately a development/test dependency of this gem rather than a runtime
dependency.

In that observed run, 2,085 examples produced 42 failures, 35 exact signatures,
4 related clusters, and omitted 2,767 backtrace frames. The raw output was roughly
22,000 lines; the final compact parallel artifact was roughly 1,100 lines. These
figures describe that run, not a universal benchmark. Its quiet terminal summary
ended like this:

```text
2085 examples, 42 failures, 6 pending

rspec-signal: 42 failures in 35 distinct signatures, 4 related clusters (2767 backtrace frames omitted)
Report: tmp/rspec-signal/signal.md
```

The parent merger owns the run comparison, because it is the only process that has
seen the whole run.

### Human and CI modes

For a human, run RSpec normally:

```bash
bundle exec rspec
```

Requiring the gem auto-installs its collector and restores RSpec's default formatter.
Normal progress, failure bodies, backtraces, and summary remain visible, followed by
the short rspec-signal artifact notice. This preserves existing behavior.

For CI, choose deliberately: use normal mode when logs are the primary diagnostic,
or use the quiet formatter above when `signal.md` and `signal.json` are uploaded as
artifacts. In both modes RSpec owns the process status and test execution semantics.

Then hand the primary artifact to an agent, for example:

```bash
claude "fix the failures in tmp/rspec-signal/signal.md"
```

## Generated artifacts

```text
tmp/rspec-signal/
  signal.md     primary compact report -- hand this to the agent
  signal.json   the same data, machine readable, for CI and tooling
  history.json  digests and counts of recent runs, so a run can say what changed
  full.txt      optional original output; off by default
  .gitignore    written automatically; artifacts can contain application data
```

A run with **no** failures deletes the report files. A stale report describing
failures you already fixed is worse than no report at all, because an agent will go
and "fix" them again.

`history.json` deliberately survives that cleanup — "42 failures became 0" is the
most valuable thing a run can say, and the run that deletes the report is exactly the
run that should be able to say it. See
[Knowing what changed](#knowing-what-changed).

The large `full.txt` artifact is off by default. Enable it only when you need the
original unreduced formatter rendering:

```ruby
RSpec::Signal.configure do |config|
  config.write_full = true
end
```

Individual per-failure files are deliberately **not** written. With failures
collapsed into a handful of signatures, `signal.md` is already the unit you want
to paste, and a directory of near-duplicate fragments is just more to sift through.

### `signal.json`

`schema: 2`. Stable, and safe to build tooling on:

| Key | What it is |
|-----|-----------|
| `run_id` | Identifies this run |
| `summary` | Counts: examples, failures, pending, signatures, related clusters, shared code paths |
| `since_last_run` | `resolved` / `new` / `persistent` / `changed`, each a list of signatures. Absent on a first run |
| `signatures[]` | One per exact signature, largest first |
| `signatures[].signature` | The digest. **This is the stable identity of a failure** — key on it |
| `signatures[].summary` | The one line that says what went wrong |
| `signatures[].rerun` | A copy-pasteable command that reruns the representative and nothing else |
| `signatures[].rerun_ids` | Every affected example's RSpec id |
| `signatures[].culprit` / `.app_context` | Where it raised, and the first-party line to open |
| `signatures[].representative` | The one failure rendered in full: message, reduced trace, diagnostics |
| `signatures[].affected[]` | Every example in the signature: location, id, description |
| `related[]` | Symptom clusters |
| `code_paths[]` | Lines of your code crossed by more than one signature |
| `outside_examples[]` | Failures RSpec reported without an example |

Only the representative carries a full trace. That is the size trade-off the whole
gem is built on: the other members of a signature are, by definition, the same
failure.

## Rerunning exactly what failed

Every `Rerun` block names **RSpec example ids**, not locations:

```bash
bundle exec rspec './spec/models/shelf_spec.rb[1:1]'
```

A location (`spec/models/shelf_spec.rb:4`) is what a human types, but it selects
every example defined on that line — which for a loop-generated `it` is all of them,
and for two failures that share a line is both of them. An agent that fixes a
signature, reruns the printed command and still sees failures cannot then tell
whether its fix failed or whether it caught something unrelated.

The ids are shell-quoted because `[` and `]` are glob metacharacters: bash passes an
unmatched glob through unchanged, but zsh fails the command outright. The
human-readable location is still on the `Example` line directly above.

RSpec's own `--only-failures` keys on the same ids. The two go together:

```bash
# spec/spec_helper.rb
RSpec.configure { |c| c.example_status_persistence_file_path = "spec/examples.txt" }
```

```bash
bundle exec rspec-signal --only-failures   # just what broke last time
bundle exec rspec-signal --next-failure    # one at a time, in defined order
```

## Knowing what changed

An agent has no memory between turns. The tool has a filesystem, so it keeps one:

```text
2085 examples, 42 failures, 6 pending

rspec-signal: 42 failures in 35 distinct signatures, 4 related clusters
Since last run: 28 resolved, 3 new, 14 still failing (42 -> 17 failures)
Shared code paths: app/models/reader.rb:88 (9 signatures)
Report: tmp/rspec-signal/signal.md
```

Four buckets, from two keys per signature — the full fingerprint, and a **loose** key
of exception and normalized message alone, independent of line numbers:

| Bucket | Rule |
|--------|------|
| **still failing** | The digest is in both runs |
| **resolved** | The digest is gone, and its loose key is gone too |
| **new** | The digest appeared, and its loose key is new too |
| **changed signature** | The digest changed but the loose key survived — same failure, moved or reworded |

The fourth bucket is what makes the other three trustworthy. Editing the file that
raises shifts every culprit line; without it, one such edit turns every persistent
failure into a spurious resolved/new pair, and being told "28 resolved" when you
resolved nothing is worse than being told nothing.

`history.json` holds the last ten runs as **digests and counts only** — no messages,
no paths, nothing the redactor exists to protect. A missing, unreadable or corrupt
history means the run has nothing to compare against, which is exactly how every run
behaved before this existed. CI that discards `tmp/` simply gets no comparison, and
needs no configuration to say so.

```ruby
RSpec::Signal.configure { |config| config.track_history = false }
```

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

Failures that are clearly connected but correctly *not* identical are handled by a
separate, looser layer — see [Related failure clustering](#related-failure-clustering).

## Related failure clustering

Exact signatures are conservative on purpose: they never claim two failures are
the same failure unless they really are. That leaves a gap the real world fills
constantly — a dozen request specs that each wanted a different thing and all got
a 404, or one missing `data-testid` reported by `find` in one spec and by
`have_css` in another. Different signatures, obviously one problem.

So there is a second, deliberately looser layer. Each failure is scanned for **one
strong diagnostic symptom**, and failures sharing a symptom are reported together:

```markdown
## Related failures

Failures sharing one diagnostic symptom across more than one signature. Weaker than
a signature: a likely common cause, not a proven identical failure. The signatures
below remain authoritative.

### R1. Unexpected 404 (Not Found) responses -- 12 examples across 12 signatures

- Symptoms: `expected 200, got 404` (6), `expected redirect, got 404` (6)
- Specs: `spec/requests/checkpoint_responses_controller_spec.rb`, ... and 6 more
- Signatures: #3, #4, #5, #6, #7, #8, #9, #10, and 4 more

### R2. Missing css selector `[data-testid="reader-progress"] span` -- 4 examples across 2 signatures

- Specs: `spec/system/reader_progress_spec.rb`, `spec/system/reader_layout_spec.rb`, ...
- Signatures: #1, #2
```

The symptoms, in the order they are tried:

| Symptom | Cluster key | Example |
|---------|-------------|---------|
| **HTTP status** | the status that actually came back | `expected 200, got 404` and `expected redirect, got 404` cluster together; `got 500` does not |
| **Route** | the path with identifiers masked, or the `_path` helper | `No route matches [GET] "/readers/:id/progress"` |
| **Selector / page text** | the selector, compared exactly | `Unable to find css "x"` and `expected to find css "x" but there were no matches` cluster together |
| **ActiveRecord** | the model, the validation sentence, or the missing column/table | `Couldn't find User` clusters with `Couldn't find User`, never with `Couldn't find Order` |
| **Ruby error** | the method *and* its receiver, or the constant | `undefined method 'progress' for nil` |
| **Exception class** | the class, only when namespaced | `PG::ConnectionBad`, `Errno::ECONNREFUSED` |

### What stops it over-clustering

Clusters are a hint, and a hint that fires too often is worse than none. Five rules
hold the line:

1. **A cluster needs two or more failures.**
2. **A cluster needs two or more exact signatures.** If everything sharing a symptom
   is already one signature, the signature section said it better, and repeating it
   is pure noise. This is what keeps the section short.
3. **Each failure joins at most one cluster** — the first symptom that matches, in
   the order above. Nothing appears twice.
4. **No similarity, ever.** Every symptom is anchored on a specific phrase from a
   specific library. There is no fuzzy matching, no embedding, no threshold. A
   failure that matches nothing has no symptom and joins nothing, which is the safe
   direction to be wrong in.
5. **Exception class is a last resort, and a narrow one.** It fires only for a
   *namespaced* class, never for `RuntimeError`, `ArgumentError` or anything under
   `RSpec::`, and never for a class an earlier symptom is responsible for — so a
   `Capybara::ElementNotFound` whose message could not be parsed can never drag
   unrelated selectors into one cluster.

Ordering is deterministic: largest cluster first, then most signatures spanned, then
run order.

## Shared code paths

Both layers above read the failure **message**. Neither can relate two failures whose
messages have nothing in common — and the most valuable question is not "which
failures look alike" but **"which line of my code is behind the most failures"**.

So a third layer reads the **stack**:

```markdown
## Shared code paths

First-party lines that more than one signature runs through, most signatures first.
A measured fact, not a diagnosis: these examples all execute this line. The
signatures below remain authoritative.

- `app/serializers/order.rb:5` in `call` -- 2 signatures, 12 examples (#1, #4)
- `app/models/reader.rb:88` in `progress` -- 9 signatures, 21 examples (#2, #3, #5, ...)
```

A worked case. One missing hash key in a pricing module, reached through three call
paths from three spec files, produces two signatures:

```text
KeyError: key not found: :annual
RSpec::Expectations::ExpectationNotMetError: expected no Exception, got #<KeyError...>
```

No symptom extractor can relate those — correctly, because their messages really do
have almost nothing in common. Both stacks run through `app/pricing.rb:4`, and that
fact was in the backtrace all along.

### What stops it over-reporting

The same two rules as the cluster layer, for the same reasons:

1. **Only first-party frames outside the spec suite, and only the innermost few.**
   The outer end of a stack is shared plumbing — every request spec passes through
   `application_controller.rb` — while the inner end is the bug. Depth is
   `config.code_path_depth`, default 5.
2. **Two or more distinct signatures, or it is not reported.** One signature crossing
   a line is already reported as that signature's `app_context`; saying it twice is
   noise.

And one rule of its own: **it claims nothing about causation.** The section states a
measured fact — these signatures execute this line — and says so in those words. When
no line is shared, the section does not appear.

Ordering is deterministic: most signatures spanned, then most examples, then run
order.

## Large HTML responses

A request spec expecting one sentence and receiving a Rails exception page produces
a diff several thousand lines long, and its first hundred lines are the exception
page's own CSS — the one part of the response guaranteed to be identical for every
failure in the suite. Capping it still spends the report's opening on stylesheet.

When the actual value is bulk HTML, `rspec-signal` replaces it:

```text
Failure/Error: expect(response.body).to include("You've finished this document.")

expected [HTML document] to include "You've finished this document."

[HTML document: 6,371 lines, 284 KB -- markup omitted]
  Title: Action Controller: Exception caught
  Heading: NoMethodError in ReaderController#show
  Message: undefined method 'progress' for nil
```

- The **expected value is never touched** — it is the small, useful half.
- Detection is by shape: a `<!doctype html>`/`<html>` opening, or five or more tags
  around structural elements. Both the one-enormous-inspected-line form and the
  unified-diff form are handled.
- `<script>`, `<style>` and comments are stripped **before** any text is read, so
  CSS can never be mistaken for content.
- Signals extracted: `<title>`, `<h1>`, `<h2>` or the first `<pre>`, falling back to
  the leading visible text when a page has neither. On a Rails error page those are
  the exception class and its message. Capybara's own `status_code` still appears
  under **Browser state**.
- HTML small enough to read is left exactly as it was (`config.max_html_chars`,
  default 1500 characters).
- No DOM parser, and no new dependency: regex only. It never has to be correct, only
  useful, and it is handed broken markup by definition.
- If `write_full` is enabled, the untouched original is written to `full.txt`.

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

  # Large HTML responses (see "Large HTML responses").
  config.reduce_html    = true
  config.max_html_chars = 1500  # smallest HTML blob replaced by a summary

  # Report budgets.
  config.max_affected_examples = 25   # locations listed per group
  config.max_groups            = nil  # signatures rendered in full (nil = all)

  # Related failure clustering (see "Related failure clustering").
  config.relate_failures   = true
  config.max_clusters      = 10  # clusters rendered in full (nil = all)
  config.max_cluster_specs = 6   # spec files listed per cluster

  # Shared code paths (see "Shared code paths").
  config.code_path_depth = 5   # first-party frames indexed, from the raise site in
  config.max_code_paths  = 5   # paths rendered in full (nil = all)

  # Artifacts.
  config.write_json      = true
  config.write_full      = true
  config.write_gitignore = true
  config.track_history   = true  # history.json, for "since last run"

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

- **Errors outside examples are recovered, but from rendered text.** A spec file that
  fails to load, or a `before(:suite)` blow-up, produces no failed example; RSpec
  reports it on its message stream instead. `rspec-signal` captures those, parses
  RSpec's own rendering back apart, and reports them under **Errors outside
  examples** with the exception, the message, the file and a rerun command — but it
  is reading formatted text rather than an exception object, so an unusual RSpec
  rendering could reduce it to a count. Whatever it cannot parse it still re-emits
  verbatim.
- **Parallel test runners.** Use `rspec-signal-parallel` for suites launched with
  `parallel_tests` (see [Parallel suites](#parallel-suites-parallel_tests)); it isolates
  each worker and merges the results deterministically. Do not set a per-worker
  `RSPEC_SIGNAL_OUTPUT_DIR` with the wrapper -- it requires every worker to report the
  same configuration and fails the merge if the output directory differs between them.
  Running `parallel_rspec` directly, with the gem only required from `spec_helper.rb`
  and no wrapper, is not supported: every worker writes to the same `signal.md` with a
  non-atomic write, and a worker that finishes green can delete a sibling worker's
  still-relevant report.
- **Grouping is a heuristic.** It is deterministic and explained above, but two
  genuinely different bugs that raise the same exception with the same message from
  the same line will collapse into one signature. The affected-example list always
  shows you everything that was merged.
- **Related clusters are a hint, not a diagnosis.** They say two failures share a
  symptom, never that they share a cause; the report says so in those words. The
  symptom list is finite, so a suite whose failures are worded in a way no extractor
  recognises simply gets no clusters — a silence, not a wrong answer.
- **HTML reduction reads markup with regexes.** It extracts the title, headings and
  leading text of a page; it does not understand the page. A response whose useful
  content is buried deep in the body will be summarised as an HTML document and
  little more. Enable `write_full` temporarily if you need the original markup.
- **No source packaging.** `rspec-signal` names files and lines; it does not embed
  source code. Agents working inside a repository can open the files themselves, and
  in v1 that is a better division of labour than guessing which snippets to inline.
- **Shared code paths are a measurement, not a diagnosis.** "These signatures execute
  this line" is exactly what is claimed and no more. A line every failure happens to
  pass through — a shared serializer, a base controller — will be reported, and
  judging whether it is the cause is the reader's job.
- **Run comparison needs the previous run's `history.json`.** CI that starts from a
  clean `tmp/` gets no comparison. That degrades to the behaviour of every run before
  the feature existed; it does not degrade to a wrong answer.
- **Reduction depends on your suite.** Failures that are already distinct and already
  shallow reduce very little. That is the correct outcome, not a failure of the gem.

## Compatibility

- Ruby 2.7, 3.0, 3.1, 3.2, 3.3, 3.4
- RSpec 3.10+ (via `rspec-core`)
- Rails, Capybara, ActiveRecord: optional

The only runtime dependency is `rspec-core`.

If you use `rspec-signal-parallel`, note that `parallel_tests` itself dropped
Ruby 2.7 support after its 4.7.1 release; on Ruby 2.7, Bundler resolves it (and
`rubocop`) to the newest release that still supports your Ruby version. Ruby
3.0+ can use any current `parallel_tests` release.

## Development

```bash
bin/setup           # or: bundle install
bundle exec rake    # specs + RuboCop
bundle exec rspec
bundle exec rubocop
```

The test suite runs `rspec-signal` on itself, so a failing run writes its own
report to `tmp/rspec-signal/signal.md`.

Most of the gem is plain Ruby with no RSpec dependency. Only `Formatter` and
`FailureBuilder` touch RSpec's notification API, which is what lets the reduction,
grouping and rendering stages be tested directly against synthetic fixtures in
`spec/fixtures/backtraces.rb`. `spec/integration/end_to_end_spec.rb` shells out to
real `rspec` processes in generated throwaway projects.

Tests deliberately assert on output *size* as well as content, so a future change
cannot quietly let noise back in. `spec/integration/agent_workflow_spec.rb` runs real
`rspec` processes through the whole loop — run, fix, rerun exactly, verify what
changed — because a rerun command that reruns the wrong examples cannot be caught
from inside the process that printed it. `spec/performance` is a guard rather than a
benchmark: it fails on an order-of-magnitude regression in per-failure cost, on the
analysis ceasing to be roughly linear, or on the report ceasing to be bounded by the
number of problems rather than the number of failures.

## Contributing

Bug reports and pull requests are welcome at
<https://github.com/SilenceDogood1984/rspec-signal>.

If you are reporting a case where reduction removed something important, the most
useful thing you can attach is the raw backtrace — a new fixture in
`spec/fixtures/backtraces.rb` is the ideal shape for it.

## License

MIT. See [LICENSE](LICENSE).
