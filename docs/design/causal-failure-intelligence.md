# Design: Causal Failure Intelligence

Status: **spike implemented**, experimental and **off by default**
(`config.causal_analysis = true` turns it on). Not ready for production; see
[Before production](#before-production). The spike changed several assumptions below; [§0](#0-spike-results) is
authoritative where it and the original proposal disagree, and the superseded passages
are marked in place.

Question this answers: can `rspec-signal`, given a red run with many failures, say which
failures are probably one problem, which are symptoms of it, which are unrelated, where to
look first, and how sure it is — **without** becoming an opaque AI product, and without
replacing RSpec noise with rspec-signal noise?

Short answer: **yes, for a well-defined band of cases, provided the gem's job is to
observe and not to conclude.** The gem can see evidence that never reaches the rendered
text: exception object identity, execution phase, passing examples, per-worker timelines,
structured exception attributes. A coding agent reading text can do semantic inference
on its own; it cannot recover any of that. The design below leans on that asymmetry.

---

## 0. Spike results

The spike implements capture (phase, place of raising, missing definitions, exception
identity), a pass/fail census, the relationship analysis, terminal and Markdown output,
and an `analysis` block in `signal.json`, and evaluates them on a corpus of 16 real
`rspec` runs with known causes (`spec/causal/`). Run it with
`bundle exec ruby spec/causal/evaluate.rb --verbose`.

### What the implementation changed

1. **Concentration is not a cause.** The original §2/§4/§8 called the 9-failure run "one
   likely cause, MEDIUM". The spike reports it as **SCOPE**: a fact about *where*, with no
   confidence label and no cause wording. Nothing upgrades a scope group: any second
   structural signal strong enough to do so would already have linked the failures.
2. **Causal groups are HIGH only.** No evidence type available to the spike met a genuine
   "two independent supporting signals" bar for MEDIUM without also being structural. The
   JSON keeps `"confidence": "high"` so a weaker level can be added later if earned.
3. **Exception identity links only inside `before(:context)`.** Ruby keeps the *first*
   raise's backtrace when one exception instance is raised again, so a reused instance
   (`raise NOT_FOUND` from two places) reaches RSpec as one object with one stale origin.
   RSpec shares an object across examples only when a `before(:context)` hook fails; any
   other sharing is reported as a `reused_exception_instance` hint, never a link.
4. **Origin linking is narrower than §5 Layer 2 proposed.** "Same raise site and class"
   admits chokepoints that raise different messages. The spike links only when the
   *underlying* exception (innermost cause) has the same class, the same normalized
   message **of the exception itself** (not RSpec's rendering, which opens with the
   failing source line and so differs at every call site), and the same first-party
   origin. That relates a wrapped exception to its bare twin, and nothing else. Same site
   with different messages is a `same_origin_different_message` hint.
5. **Worker concentration was removed.** In the corpus, `parallel_tests` put a 40-example
   passing file alone on worker 1 and every failing file on worker 2, producing a true but
   meaningless "13/13 failed on worker 2". Workers are assigned by file size, so worker
   concentration mostly restates file assignment.
6. **Missing definitions come only from exception attributes**: `env:` (`KeyError#receiver`
   is `ENV`), `const:` (`NameError#name`, qualified by `#receiver`), and `method:`
   (`NoMethodError` on a class whose source is first-party, via
   `Object.const_source_location`). Never a nil receiver, never a core class. Tables,
   columns, routes and embedded error lines would need message regexes and are deferred.
7. **A lazily evaluated `let` is the body.** The body had begun; "body never reached" is
   claimed only for `before` and `before(:context)` failures.
8. **A lone signature forms a causal group only with a fact its fingerprint lacks**:
   shared `before(:context)` object, failing in setup/`let`/teardown, a missing definition,
   or the same error outside examples in several files. A plain repeated signature stays
   independent -- it is already a signature.
9. **Phase detection is version-robust by construction**: hook frames are classified by
   the `source_location` of `BeforeHook#run`, `AfterHook#run` and `AroundHook#execute_with`
   in the *loaded* rspec-core (Ruby 3.4 labels are matched by name first). Verified on
   rspec-core 3.10.2 and 3.13.6 by specs that raise inside real hooks.

### Taxonomy as built

| Kind | Meaning | Confidence |
|---|---|---|
| CAUSAL | every member shares one `before(:context)` exception object, one underlying exception at one line, one missing definition, or one failing setup step | HIGH |
| SCOPE | ≥ 3 failures in ≥ 2 otherwise-unlinked signatures, all inside one file or one `type:`, where ≥ 2/3 of that scope failed and < 1/20 of the rest did, and the rest is at least as large | none |
| INDEPENDENT | no relationship found -- not "proven unrelated" | none |
| hint | `same_origin_different_message`, `reused_exception_instance`; JSON only, never changes grouping | none |

Every failure (and every captured error outside examples) is in exactly one group;
`n/n failures accounted for` is printed, and failures RSpec counted but rspec-signal
could not capture are reported as `not captured`.

### Results

Pairwise "same cause" relation over 91 failures in 16 scenarios (123 true pairs):

| Layer | Precision | Recall | Recall, structurally solvable | Wrong pairs |
|---|---|---|---|---|
| exact signatures (today) | 0.97 | 0.55 | 0.75 | 2 |
| signatures + related clusters + shared code paths (today) | 0.95 | 0.59 | 0.81 | 4 |
| signatures + causal groups (spike) | 0.98 | 0.72 | **1.00** | 2 |

- 10 causal groups, **0 impure**; 28 genuinely independent failures, **0 merged**; all 16
  scenarios fully accounted for.
- Both remaining wrong pairs are inherited from exact signatures (a shared example failing
  identically in two independently broken hosts; a reused exception instance). The causal
  layer adds none, and declines to promote either to a causal group.
- Unsolved by design: one regression seen by three assertions, order-dependent
  pollution, and the environment replica (reported as SCOPE). Nothing structural relates
  them, and the spike says nothing rather than guess.
- **Caveat:** the corpus was written by the same person who wrote the rules. It proves the
  rules do what they claim and refuse what they should; it is not evidence of how often
  real suites contain structurally solvable failures.

This repository's own run in a container without the `rspec` binstub, previously
"9 failures in 6 distinct signatures, 0 related clusters, 0 shared code paths", now adds:

```text
SCOPE · 9 failures in 6 signatures
  failure concentration: 9/11 examples failed in spec/integration/parallel_tests_spec.rb; 0/529 elsewhere
9/9 failures accounted for: 0 causal, 9 scope, 0 independent
```

### Known gaps found by the spike

- A signature joins a scope group only if *all* its failures are inside the scope. With
  the corpus spec also failing for the same environmental reason, one `Errno::ENOENT`
  signature spans two files and stays independent, so the scope group reads "5 failures"
  beside a "9/11" statistic. Truthful, but not tidy.
- A browser-driver failure reached partly from `before` hooks and partly from example
  bodies is one signature with mixed phases, so the spike adds nothing to it.
- Errors outside examples are grouped by the analysis and in `signal.md`, but
  `signal.json`'s `outside_examples` stays a flat list for compatibility.

### Costs

About 0.1 ms of capture per failure (the existing per-failure pipeline is about 1.5 ms),
about 3 µs of counting per example (7 KB of counters for 10,000 examples in 300 files),
and about 25 ms of analysis for 400 signatures. Worker payloads gain one small `evidence`
hash per failure and a `census`; no backtraces or exception objects cross processes.

### Before production

Review of the spike raised a sequencing problem that outranks everything above.

**This layer treats signatures as authoritative, and signature identity is currently
wrong in important real-world cases.** RSpec's rendered `Failure/Error:` source echo
reaches the fingerprint, so the same failure reached from different spec lines splits
into different signatures. A separate audit measured one broken factory becoming 9
signatures and one wrong constant becoming 61. Relating those fragments afterwards is a
repair of damage the signature layer should not have done. Order of work:

1. Fix fingerprint identity so rendered `Failure/Error:` text cannot fragment one
   problem. (The spike's link key already avoids this by normalizing the exception's own
   message; the fingerprint should too.)
2. Fix the stale-report lifecycle.
3. Make stdout answer-first.
4. Re-run the audit's dogfood corpus.
5. Only then measure what this layer adds *beyond improved signatures*. Several corpus
   wins (the missing constant referenced from two spec lines, for instance) may simply
   disappear into correct signatures, and that is the result to hope for.

Until then the layer stays off by default: its selling point is trust, and a default-on
experiment spends trust it has not earned.

**Size constraint.** `Causal::Analysis` already owns union-find, evidence semantics,
scope rules, hints, confidence, accounting and ordering. That is acceptable for a
spike. For production it must not become the place every new heuristic lands. Evidence
types should be separable, and every one should arrive with corpus scenarios that
attack it.

**What stands on its own.** The parallel loose-digest fix and boot-error deduplication
are independent of this layer and should ship separately.

---

## 1. What exists today (repository evidence)

`rspec-signal` already has three analysis layers, and a clear, explicitly stated
philosophy: deterministic, byte-identical, "a hint, never a diagnosis", "a silence, not a
wrong answer".

| Layer | Code | Keyed on | Claims |
|---|---|---|---|
| Signatures | `Fingerprint`, `Grouper`, `Group` | exception class + normalized message (incl. cause chain) + culprit frame + app context | "these are the same failure" (authoritative) |
| Related clusters | `Symptoms::*`, `Clusterer`, `Cluster` | *one* symptom per failure from message text (HTTP status, route, selector, record, Ruby error, namespaced class) | "share a symptom" |
| Shared code paths | `CodePaths` | innermost 5 first-party, non-spec frames | "these execute this line"; "claims nothing about causation" |
| Run comparison | `History`, `Comparison` | signature digest + loose digest | resolved / new / persistent / changed |

What a failure carries (`Failure`, built by `FailureBuilder`): description, spec location,
example id, exception class, `Message` (with cause chain folded in), **the full parsed
frame list** plus the reduced trace, Capybara diagnostics, shared-group inclusion
locations. What it does **not** carry: execution order or timing, the phase that raised,
exception identity, structured exception attributes, worker id. Passing examples are
counted by the progress bar and then forgotten.

Constraints that shape the design:

1. **Only `FailureBuilder` and `Formatter` touch RSpec** (CONTRIBUTING). New capture goes
   there; analysis stays plain Ruby, testable on fixtures.
2. **The parallel merger only sees reduced traces.** `ParallelMerger#load_failure`
   rebuilds `frames` from `reduced.entries`; framework frames are gone. Anything derived
   from the full backtrace (phase, test-infra frames) must be computed in the worker and
   serialized.
3. **`Fingerprint.spec_frame?` treats everything under `spec/` as the spec suite.** So
   `spec/support/*.rb`, `spec/factories/*.rb` and `rails_helper.rb` are excluded from
   `app_context` and from code-path indexing — exactly the frames that locate broken
   shared setup. This must not be changed (it would change every digest and break
   history); the causal layer needs its own notion of *test infrastructure*.
4. **Signature digests are a public identity** (`signal.json` schema 2, history). The new
   layer must build on signatures, never re-cut them.
5. **Output size is asserted in tests.** Any new section must be bounded by the number
   of problems, not failures.

Two findings made along the way, independent of this feature:

- In a parallel run, `ParallelMerger#load_fingerprint` builds the fingerprint with
  `message: "worker"` and `Fingerprint#to_h` does not serialize the loose digest, so
  `loose_digest` becomes `sha(exception_class + "worker")`. Every signature with the same
  exception class shares a loose key, and the "changed signature" bucket in parallel
  runs can pair unrelated failures. (Worth its own fix: serialize `loose_digest`.)
- `Reporters::OutsideExamples` renders one section per captured error, ungrouped. A
  boot-time failure (`ENV.fetch` in an initializer) that breaks 300 spec files renders
  300 identical sections — verified below with 3 files.

## 2. A real specimen from this repository

Running this repository's own suite in a fresh cloud container produced:

```text
504 examples, 9 failures
rspec-signal: 9 failures in 6 distinct signatures (270 backtrace frames omitted)
```

Related clusters: **0**. Shared code paths: **0**. The report presents six problems.
There is one: `parallel_rspec` could not find the `rspec` binstub in that container.

| Signature | n | What it says | Mentions the cause? |
|---|---|---|---|
| `Errno::ENOENT` reading `tmp/rspec-signal/signal.json` | 4 | the artifact was never written | no |
| expectation: output to include "…aggregation failed…" | 3 (3 sigs) | actual value contains `bundler: command not found: rspec` | **yes, embedded in the actual value** |
| expectation: `expected: 0 got: 1` (exit status) | 1 | | no |
| expectation: `expected [].empty? to be falsey` | 1 | no worker artifacts | no |

Evidence that *was* available and unused:

- All 9 failures are in one file, one top-level group: `parallel_tests_spec.rb[1:*]`.
- That group has 11 examples: **9 failed, 2 passed** — the two that passed assert that
  worker artifacts get cleaned up, and pass vacuously because none were created.
  493 examples elsewhere: **0 failed**.
- `git status` was clean: no code change explains new failures.
- Three failure messages contain the same low-level error line.

This case exercises nearly every hard part of the problem: one cause, four exception
shapes, a cause that appears only inside actual values, vacuous passes that break a
naive "100% of the group failed" rule, and an environmental cause that no code edit
would fix. It is corpus scenario #1 in the spike.

## 3. Signals: verified behaviour and causal value

Behaviour below was verified with probe formatters against rspec-core 3.13.6 on
Ruby 3.3.6, not recalled.

### 3.1 Verified RSpec facts

| Situation | What a formatter receives |
|---|---|
| `before(:context)` raises | every example in the group fails with **the same exception object** (identical `object_id`), `run_time ≈ 0`, same `started_at`. Frames outside the hook: `hooks.rb 'instance_exec'` → `hooks.rb 'run'` → `hooks.rb 'block in run_owned_hooks_for'` |
| `before(:each)` raises | a fresh exception per example. Frames: `example.rb 'instance_exec'` → `hooks.rb 'run'` |
| `after(:each)` raises | same shape as `before(:each)`; the two differ only by the line number inside `hooks.rb` on Ruby < 3.4 (Ruby 3.4 labels include `BeforeHook#run` / `AfterHook#run`) |
| body raises, and `after` raises too | `RSpec::Core::MultipleExceptionError` with both sub-exceptions |
| example body (including a `let` evaluated from it) | `example.rb 'instance_exec'` → `example.rb 'block in run'` |
| `let` raises | the above plus `memoized_helpers.rb 'block (2 levels) in let'`; the frame inward of it is the `let` definition line |
| hook defined in `include_context` | **no** metadata trace (`shared_group_inclusion_backtrace` is empty); only a `spec/support/...` frame in the backtrace |
| `it_behaves_like` | metadata carries the shared group name; ids nest (`[6:1:1]`) |
| `ENV.fetch("X")` missing | `KeyError#key == "X"` and `KeyError#receiver.equal?(ENV)` — exact, no regex |
| missing constant / method | `NameError#name` (`:Billing`), `NoMethodError#name` (`:nickname=`) and `#receiver` class (`User`) — immune to Ruby 3.4's message-format change |
| exception raised in another thread and re-raised (Capybara server errors) | backtrace contains **no rspec-core frames** |
| boot failure in a helper every spec file requires | one "error outside examples" **per spec file**, 0 examples run |

### 3.2 Which signals help causal inference, and which only look like they do

Strength vocabulary, used everywhere below and in the confidence rules:
**proof** (cannot be two causes) · **strong** (links on its own) · **supporting**
(changes confidence, never links alone) · **weak** (never used to link).

| Signal | Available | Strength | Why / trap |
|---|---|---|---|
| Exception object identity | in-process, per worker | **proof** | Only `before(:context)`-style cascades produce it. Already one signature, but it upgrades "same fingerprint" to "one raise" and proves those examples never ran. |
| Execution phase (context hook / hook / let / body / other thread) | full frames, in-process | **strong** as a *qualifier*, supporting alone | Setup-phase failures never reached their assertions: they say nothing about the code under test and they *mask* its real status. |
| Raise site in test infrastructure (`spec/support`, `spec/factories`, `*_helper.rb`, shared contexts) | full frames | **strong** | Currently invisible: `spec_frame?` discards it. Two failures raising at the same helper line are one problem. |
| First-party raise site (innermost app frame) | reduced frames | **strong** if the exception is not a wrapper | Trap: generic chokepoints (`BaseService#call` re-raising `ServiceError`, `ActionView::Template::Error`). If the exception has a `cause`, link on the cause's origin instead. |
| Deeper shared app frames (depth 2–5) | reduced frames | supporting | Outer frames are plumbing (`application_controller.rb`). No passing-example stacks exist to measure base rate, so never strong. |
| Definitional entity: env key, constant, `Model#attribute`, `table.column`, route, HTTP host, driver | structured attrs + message | **strong** | Things that are *defined* somewhere. One missing definition breaks everything that uses it, through any exception shape. |
| Receiver-less entities: `undefined method 'name' for nil` | message | **weak** | Different nils. The existing `RubyError` symptom keys on `(name, nil)` and will over-cluster; the causal layer must not inherit that. |
| Embedded error: a lower-level error inside an actual value (Rails error page title/heading from `HtmlSummary`, `command not found`, `ECONNREFUSED host:port`) | message | **strong** when it equals another failure's primary error; supporting otherwise | The only thing linking an assertion failure to the exception that caused it. |
| Library entry point → operation (factory_bot create, AR connection, selenium, capybara finders, net/http, webmock) | reduced frames (entry point is kept) | supporting | Names *what operation* failed. "Every failure raised inside the WebDriver session" is an environment tell. |
| Environmental exception families (connection refused/bad, pool timeout, deadlock, driver session, pending migration, `Errno::*`) | class + cause class | supporting → environment kind | Says the raise site is probably *not* the cause. |
| Exception class alone | always | weak | `NoMethodError` links nothing. |
| Exception message similarity | always | weak | `expected 3 got 4` vs `expected 5 got 6`. The gem's "no similarity, ever" rule stands. |
| Spec file / example group | example id encodes ancestry (`[1:2:3]`) | supporting, **only with saturation** | Files hold many independent examples. Meaningful only as "confined here and most of this group failed". |
| Pass/fail census per group, type, worker, shared group | **not captured today**; cheap | supporting (contrast) | The base rate every other signal lacks. "9/11 in this group, 0/493 elsewhere" vs "9/400". |
| Shared example group | metadata | supporting only with saturation | 3 of 30 hosts failing a shared example = 3 host bugs, not a shared-example bug. |
| Timestamps / order | `execution_result` | weak, except onset | Random order makes "A before B" meaningless. Useful only as a per-process *onset*: everything from example k onward failed (browser crashed, DB went away, time frozen and never restored). |
| Worker / process | `TEST_ENV_NUMBER` | supporting (confinement) | "All failures on worker 3" explains failures that share no code (worker 3's database unmigrated). Timelines must stay per worker; merging by wall clock invents order. |
| Changed files (git) | subprocess, fail-soft | **annotation only** | Base-rate confounded: a changed `user.rb` sits in half of all stacks. Useful for localisation tie-breaks, for mapping a `Gemfile.lock` diff onto library frames, and for "nothing changed ⇒ environment". Never a link. |
| Previous runs | `history.json` | supporting | Co-onset: signatures that appeared together, in a run where the previous run had none of them, are candidates for one cause; pre-existing signatures are probably unrelated to the latest change. Co-*resolution* later is retrospective ground truth. |
| Rerun ids | exact ids | **experiments** | The only way to answer order-dependence: run one member alone. The tool recommends; the agent runs. |
| Factory names, test descriptions, durations, spec line numbers, process ids in a serial run | | weak / useless | Look causal, aren't (`:user` is used by everything). |

Per-example coverage (spectrum-based fault localisation: lines executed by all failing
examples and few passing ones) is the principled answer for assertion-only failures, and
it is deterministic and explainable. It is also expensive. It belongs in a later, opt-in
mode, not in this feature.

## 4. Scenarios

For each: what the run looks like, what today's layers do, the evidence that says *one
cause*, and what would say *independent* instead.

**S1 — Environment breaks one area (this repo, §2).** 9 failures, 4 shapes, 6
signatures. Today: 6 items. One cause: confinement + saturation (9/11 vs 0/493), clean
tree, embedded `command not found` in 3 members. Independent would look like: failures
spread across groups, a non-empty diff touching the code each one exercises. Verdict:
~~one cluster, **MEDIUM**~~ *(superseded, see §0: a SCOPE group, no confidence, no cause
wording; the embedded-error clue is deferred)*.

**S2 — Missing ENV var at call time.** `ENV.fetch("STRIPE_SECRET_KEY")` in a service;
14 failures across request, job and model specs, raised from two call sites. Today: 2
signatures (different culprits), a `KeyError` isn't a clusterable symptom. One cause:
`KeyError#receiver == ENV` and the same key in both. Independent: different keys *and*
different raise sites. Verdict: **HIGH**, headline "ENV key STRIPE_SECRET_KEY missing",
kind environment. Variant — at boot: N "errors outside examples", 0 examples run; the
fix here is grouping outside-example errors by signature.

**S3 — Shared auth helper raises.** `sign_in_admin` in `spec/support/auth.rb` raises for
every admin request spec (via `include_context`, so no metadata). Today: 1 signature
(same culprit), fine — but nothing says the examples never ran. Causal adds: phase =
hook, raise site = test infrastructure, masked count. **HIGH**. Silent variant: the
helper *does nothing* → request specs get `302 → /users/sign_in`, system specs raise
`ElementNotFound` while Capybara diagnostics show path `/users/sign_in`. Link via the
redirect target entity. Independent would look like: 403s on specific resources, scoped
to specific controllers, no redirect to sign-in.

**S4 — Broken factory, loud.** `association :organization` removed; `create(:user)` in
`let`s raises `RecordInvalid: Organization must exist` from factory_bot. Today: 1
signature. Causal adds: phase = let, operation = factory_bot create, masked count.
**HIGH**.

**S5 — Broken factory, quiet.** The factory now builds users with no organization.
Views raise `undefined method 'name' for nil`, a policy spec raises
`Pundit::NotAuthorizedError`, a system spec can't find `.org-name`. No shared frame, no
shared entity, nil receivers (weak). Only co-onset (all new this run) and a changed
`spec/factories/users.rb` that appears in no stack. Verdict: **not merged**; hint line
"12 signatures appeared together since the last run; test infrastructure changed:
spec/factories/users.rb". This is the honest outcome; claiming more would be guessing.

**S6 — Schema drift.** Column `users.nickname` missing from the test DB. Queries raise
`StatementInvalid (PG::UndefinedColumn) column users.nickname does not exist`; factories
raise `NoMethodError nickname= for User`; `User.new(nickname:)` raises
`ActiveModel::UnknownAttributeError`; request specs render a 500 page whose heading is
`ActionView::Template::Error`. Today: 4+ signatures, at most two clusters (each failure
joins one symptom). One cause: entity `User#nickname` from all four shapes (table→model
via `ActiveSupport::Inflector` when loaded, exact otherwise). **HIGH**. If two *different*
columns are missing: separate entities, but a family rule ("≥2 missing-column errors")
links them as "test schema behind", **MEDIUM**. Pending-migration variant:
`maintain_test_schema!` aborts before any example; rspec-signal sees nothing and the
previous report survives — a stale-artifact gap worth fixing separately.

**S7 — Browser driver mismatch.** Chrome auto-updated; every system spec raises
`Selenium::WebDriver::Error::SessionNotCreatedError` at its first `visit`. Today: 1
signature (raise site inside selenium). Causal adds: census says 100% of `type: :system`
examples failed and 0% of everything else; operation = webdriver; kind = environment.
**HIGH**. Crash-midway variant: the first failure in time is
`UnknownError: Chrome crashed`, every later one on that worker is `InvalidSessionIdError`
— per-worker onset makes the first one the primary.

**S8 — One regression, many legitimate assertions.** `Order#total` drops tax. Model,
invoice, mailer and checkout specs each fail an `eq`/`include` assertion at their own
spec line. No exceptions, no app frames (matchers raise at the spec line), different
messages. Only co-onset and a changed `app/models/order.rb`, which none of the stacks
contain. Verdict: **not merged**, co-onset hint. Coverage would crack this; nothing else
honest will.

**S9 — Order-dependent pollution.** A spec does `Timecop.freeze` without returning, or
sets `I18n.locale = :fr`, or leaves `Sidekiq::Testing.inline!` on. (rspec-mocks stubs do
*not* leak across examples.) Failures in unrelated files, varying with the seed; the
polluter passes. In one run there is no structural evidence except, sometimes, onset.
Verdict: not merged; for any cluster-less failure set that is *new with no code change*,
suggest the experiment: rerun one member alone; if it passes,
`rspec --bisect --seed <seed>`. Independent would look like: members that fail in
isolation.

**S10 — Pool exhaustion / deadlock.** `ActiveRecord::ConnectionTimeoutError` and
`PG::TRDeadlockDetected` scattered across unrelated specs, count varies run to run.
Raise sites inside AR connection code, no first-party raise site. Verdict: one cluster by
environmental family, **MEDIUM**, kind environment, with the explicit note "the raise
site is not the cause; something is holding connections". The leaker may be a passing
example; the tool cannot name it and says so.

**S11 — Global `before` hook in `rails_helper`.** `config.before(:each, type: :request)`
raises for every request spec. Today: 1 signature. Causal: phase = hook, raise site
`spec/rails_helper.rb:40`, census = 100% of request specs. **HIGH**, with a masked
warning: after the fix, previously hidden failures will appear.

**S12 — Worker-confined.** Under `parallel_tests`, worker 3's database was never
migrated. 23 failures across arbitrary files, all on worker 3; other workers 0%. Today:
several signatures (whatever DB errors those files hit). Causal: worker confinement +
saturation. **MEDIUM**, kind environment, "all failures ran on worker 3".

**S13 — Dependency upgrade.** `Gemfile.lock` bumps rack; 12 request specs fail on header
casing; frames in `rack-3.1` in every stack; app code unchanged. Causal: operation/gem
shared by all members + lockfile diff names that gem. **MEDIUM**, headline "all members
run through rack (upgraded in Gemfile.lock)".

**S14 — Blocked outbound HTTP.** `WebMock::NetConnectNotAllowedError` for
`api.stripe.com` from three call sites. Entity: HTTP host. **HIGH** if one host, split by
host otherwise.

**S15 — Mixed run (the realistic one).** S3 + S6 + five genuinely independent
assertion failures. The test of the design is not the clusters; it is that the five
independent failures remain visibly independent.

## 5. Algorithm

The unit of analysis is the **signature** (existing, authoritative). Clusters are sets of
signatures. Every step is deterministic; there are no weights, probabilities or
similarity thresholds.

### Layer 0 — capture (worker side, serialized)

In `FailureBuilder`, per failure, as plain data on `Failure` and in `Failure#to_h` so the
parallel merger receives it:

- `phase`: `context_hook | hook | let | body | foreign_thread | unknown`, from the
  rspec-core frames just outside the outermost first-party frame (§3.1 patterns; accept
  both `run` and `…Hook#run` labels). Unknown is the fail-soft default and yields no
  evidence.
- `raise_locus`: innermost first-party frame, *including* test infrastructure; if the
  exception has a `cause`, the cause's first-party origin (already computed for the
  message). Plus `raise_locus_kind`: `app | test_infra | spec_body`.
- `identity`: `"#{worker}:#{exception.object_id}"` only when phase is `context_hook`.
- `entities`: a small typed set — `env:KEY` (`KeyError#receiver.equal?(ENV)`),
  `const:Name` (`NameError#name`), `attr:Class#name` (`NoMethodError` on a non-nil
  receiver, `UnknownAttributeError`, missing column), `route:…`, `host:…`,
  `redirect:path`, `driver`. Entities with a nil receiver are not created.
- `embedded_error`: from the reduced HTML summary (title/heading/message) or a curated
  short list of lower-level error lines (`command not found`, `Connection refused`,
  `No such file or directory`).
- `operation`: gem of the library entry point, if on a short list.
- `seq`, `run_time`, `worker`.

In `Formatter`, a **census**: per top-level group id, per spec type, per worker, per
shared group — examples run and failed; and per worker a compact status string. Counters
only, no messages or paths beyond group ids.

### Layer 1 — per-signature evidence

Aggregate member failures' fields; an evidence item records `members/of` so it is
checkable ("11 of 11 members raised here").

### Layer 2 — links (union-find over signatures)

Link two signatures if they share, across *all* their members:

1. identity (proof), or
2. the same raise locus with the same exception class, where the exception is not a
   wrapper (strong), or
3. the same definitional entity (strong), or
4. an embedded error equal to the other's primary error (strong).

Never link on: exception class, HTTP status, nil-receiver method, message similarity,
spec file, shared example group, changed files, time adjacency.

### Layer 3 — scope clusters (only for what Layer 2 left alone)

A group of ≥ 3 unlinked failures becomes a **scope cluster** if it is *confined and
saturated*: every one of them lies inside one example group / spec type / worker, at
least ⅔ of that scope's examples failed, and fewer than 1 in 20 examples outside it did.
(These three numbers are the only thresholds in the design, and the spike must show they
don't need tuning per scenario.) Also: environmental families (≥ 2 signatures of
connection/pool/deadlock/driver errors) and per-worker onset (every example from k to the
end of a worker failed, spanning ≥ 3 groups).

### Layer 4 — split check

Within any cluster, if two members have first-party raise loci in *app* code, with
different exception classes and no shared entity, the link that joined them is scope-only
→ split them, or downgrade the cluster. Shared hook *definition* never outranks
different raise sites: two different bugs in one `before` block are two clusters with a
note "same setup hook".

### Layer 5 — roles and primary

- **origin** members raised at the shared locus / carry the entity as a definition error;
  **symptom** members only observed it (assertion failures carrying an embedded error, a
  500 page, a sign-in redirect).
- **primary** = an origin member; prefer an error over an assertion, setup phase over
  body, then the fastest `run_time` (cheapest verification: a model spec before a system
  spec), then run order.
- **inspect first** = the shared locus (file:line) or, for an entity, its definition
  hint; annotated "changed in working tree" if git says so — annotation only.

### Layer 6 — independents

Every signature not in a cluster is listed as independent. "Independent" means *no shared
evidence found*, not "proven unrelated". Co-onset among independents is a one-line hint,
never a merge.

### Layer 7 — semantics: outside the gem

The optional "semantic model for ambiguous cases" is the coding agent that reads the
output. The gem makes no model call, keeps "no model, no network, no API key", and
instead hands the agent structured evidence, falsifiers and experiments (§8).

## 6. Confidence

*Superseded by §0: the spike has HIGH causal groups only, and scope carries no confidence.*

Three words, defined by rules, published in the README, printed with their evidence.
No percentages: there is no calibration data that would make a number honest.

| Level | Rule | Wording |
|---|---|---|
| **HIGH** | a proof link, or a strong link shared by *every* member, and the split check found nothing | "same cause" |
| **MEDIUM** | a scope cluster, an environmental family, per-worker onset, or a strong link that covers most but not all members | "likely related" |
| *(LOW)* | co-onset or any single supporting signal | never a cluster; one hint line under Independent |

Downgrades by one level: a cluster built on a locus that is plumbing by location
(`application_controller.rb`, a global `rails_helper` hook — still reported, since it is
where to look); a member with foreign-thread phase (may belong to the previous example).

Run-level invariant, always printed: `27/27 accounted for` — every failure is in exactly
one cluster or in the independent list. Nothing is hidden, ever.

## 7. Adversarial cases

**False collapse of real, separate failures.**

- *Same hook, two bugs.* `before { sign_in create(:user) }`: a User validation bug and a
  broken sign-in helper both fail in that hook. Linking on the hook's line merges them.
  → Link on the raise locus, never on the hook definition (Layer 2, rule 2; Layer 4).
- *Generic chokepoint.* `BaseService#call` wraps every error in `ServiceError` at one
  line. → Wrapper exceptions link on their cause's origin.
- *Nil receivers.* `undefined method 'name' for nil` in a view and in a PDF: different
  nils. → nil-receiver entities are never created. (Today's related-cluster layer does
  merge these.)
- *HTTP 500 for two reasons.* 12 from a missing column, 8 from a serializer nil. Today's
  `HttpStatus` symptom merges all 20. → Status never links; the embedded error page
  heading splits them.
- *Shared examples.* 3 of 30 hosts fail `it_behaves_like "an api endpoint"` for 3
  unrelated reasons. → Shared group is scope evidence and needs saturation.
- *TDD.* A new spec file with 10 examples, none implemented: confined and saturated →
  scope cluster. Harmless if the headline describes the evidence ("confined to
  spec/services/new_feature_spec.rb, 10/10 failed") rather than claiming a cause — which
  is why headlines describe evidence.
- *Tiny groups.* 2/2 failing is not saturation → minimum of 3.

**One cause, completely different exceptions.** S1 (four shapes), S5, S6, S3-silent,
S8. Handled: S6 via entities, S3-silent via the redirect entity, S1 via scope, the 500
page via embedded errors. Not handled, by design: S5 and S8 stay independent with a
co-onset hint. A layer that merged them would be right in those two scenarios and wrong
every time two unrelated regressions land in the same commit.

**Changed-code relevance that misleads.** A comment edit in `user.rb` during a DB
outage: user.rb is in 30 stacks and blameless. A `Gemfile.lock` bump: the cause is in
unchanged app code's dependency. A CI diff against main with 100 files: everything is
"changed". A factory edit that appears in no stack (S5). → Changed files annotate the
inspect-first line, are suppressed when a cluster is environmental, are dropped when the
changed set covers most first-party frames in failing stacks, and never link or raise
confidence.

**Ordering that fakes causation.** Random order puts A before B by chance. Defined order
makes adjacent related files fail in a burst. Parallel workers interleave by wall clock.
Capybara re-raises a server error from example k during example k+1's `visit` or its
teardown, attributing it to the wrong example. → Time is used only as per-worker onset
spanning ≥ 3 groups; a foreign-thread backtrace (no rspec-core frames) is flagged "may
belong to the previous example on this worker".

**Masking.** Fixing a setup cluster reveals the assertions it hid; an agent then
believes its fix broke seven things. → Setup clusters print "N examples never reached
their assertions", and history can label next run's new failures in those same examples
as *previously masked* (store hashed example ids per signature).

### How the UI stays honest

- Headlines describe **evidence**, never a diagnosis: "setup raises at
  spec/support/auth.rb:14", not "the root cause is authentication".
- Every cluster has a `Why:` line made of checkable facts with counts.
- MEDIUM clusters carry the experiment that would refute them.
- The independent bucket is always shown, with its count, and the accounted-for line.
- The legend is one sentence: "HIGH: every member shares one raise site, setup path or
  missing definition. MEDIUM: shared scope or environment, corroborated. Independent: no
  shared evidence found — not proven unrelated."

## 8. UX

### Terminal (quiet mode stdout)

*Superseded by §0: the spike prints `CAUSAL · HIGH`, `SCOPE` and `INDEPENDENT` groups and
never the words "likely cause". The mock-ups below are the original proposal.*

Replaces the "Shared code paths" line. Hard budget: 3 clusters, 2 lines each, 10 lines
total.

```text
2085 examples, 27 failures, 6 pending

rspec-signal: 27 failures → 2 likely causes + 8 independent (27/27 accounted for)
  A  HIGH    11  setup raises at spec/support/auth_helpers.rb:14 — KeyError: ENV "ADMIN_TOKEN"
                 never reached their assertions · verify: bundle exec rspec './spec/requests/admin_spec.rb[1:1]'
  B  MEDIUM   8  column users.nickname (StatementInvalid ×5, NoMethodError nickname= ×3)
                 inspect: app/models/user.rb:42 · db/schema.rb changed · verify: bundle exec rspec './spec/models/user_spec.rb[1:4]'
     8 independent · 4 appeared together this run
Since last run: Signatures: 19 new, 5 persistent; failures: 5 -> 27
Report: tmp/rspec-signal/signal.md
```

For the repository's own §2 run:

```text
rspec-signal: 9 failures → 1 likely cause + 0 independent (9/9 accounted for)
  A  MEDIUM   9  confined to spec/integration/parallel_tests_spec.rb (9/11 failed, 0/493 elsewhere)
                 clue ×3: "bundler: command not found: rspec" · no code changed
```

### `signal.md`

A `## Likely causes` section at the top, ≤ 6 lines per cluster: headline, `Why`,
`Inspect first`, members (as `#n` links to signature sections), `Verify` (primary) and
`Rerun cluster` (all ids ≤ 10), and for MEDIUM an `If wrong` line
(e.g. "if `[1:4]` passes alone, this is order-dependent: `rspec --bisect --seed 1234`").

To avoid a fourth themes section, **Likely causes absorbs Related failures and Shared
code paths in the Markdown**: both become evidence types inside clusters. Their JSON keys
stay (schema promise). Expanding is reading the signature sections the cluster links
to; rerunning is the printed commands.

## 9. Agents

**Does structured causal evidence beat dumping raw output into context? Yes — for four
reasons that are specific, not generic:**

1. **It prevents symptom-patching.** The common agent failure on a red suite is editing
   assertions until they pass. Knowing that 8 failures are symptoms of one setup error
   removes the temptation to "fix" them one by one.
2. **It separates environment from code.** "Every system spec failed in the WebDriver
   session; no code changed" stops an agent from rewriting application code around a
   broken chromedriver or a missing env var.
3. **It anticipates masking.** An agent told "11 examples never ran" does not mistake
   newly revealed failures for regressions it caused.
4. **It contains evidence text cannot.** Exception identity, phase, passing-example
   census and worker timelines are not in RSpec's output at all. An LLM can infer
   similarity from text; it cannot infer what was never printed.

The risk is automation bias: an agent will believe HIGH. Mitigation: every claim is
checkable (locations, ids, counts), and every cluster carries falsifiers and a
verification command whose result the next run's comparison confirms.

### Schema (`signal.json` schema 3, additive)

```json
"causes": {
  "version": 1,
  "accounted": { "failures": 27, "in_clusters": 19, "independent": 8 },
  "clusters": [
    {
      "id": "A",
      "key": "c-3f9a1b2c4d5e",
      "confidence": "high",
      "kind": "setup",
      "headline": "setup raises at spec/support/auth_helpers.rb:14",
      "signatures": ["a1b2c3d4e5f6"],
      "failures": 11,
      "evidence": [
        { "type": "raise_locus", "strength": "strong", "value": "spec/support/auth_helpers.rb:14", "members": 11, "of": 11 },
        { "type": "entity", "strength": "strong", "value": "env:ADMIN_TOKEN", "members": 11, "of": 11 },
        { "type": "phase", "strength": "supporting", "value": "hook", "members": 11, "of": 11 }
      ],
      "counter_evidence": [],
      "roles": { "origin": ["a1b2c3d4e5f6"], "symptom": [] },
      "masked_examples": 11,
      "inspect_first": { "location": "spec/support/auth_helpers.rb:14", "changed": false },
      "primary": { "signature": "a1b2c3d4e5f6", "id": "./spec/requests/admin_spec.rb[1:1]", "run_time": 0.04 },
      "verify": "bundle exec rspec './spec/requests/admin_spec.rb[1:1]'",
      "rerun_all": "bundle exec rspec ...",
      "falsifiers": ["After defining ADMIN_TOKEN, any member still failing in setup was merged wrongly"],
      "experiments": []
    }
  ],
  "independent": [ { "signature": "…", "summary": "…", "rerun": "…" } ],
  "hints": [ { "type": "co_onset", "signatures": ["…"] } ],
  "context": { "changed_files": 3, "environmental": false }
}
```

Design rules: signatures joined by digest; evidence typed with `members/of`; confidence
an enum with published meaning; `key` is a digest of the linking evidence so history can
track a cluster across runs and record whether its members **resolved together** — the
tool's own ground truth.

## 10. Architecture

**Reuse unchanged:** `Fingerprint`/`Grouper`/`Group` (units), `Rerun`, `Report#safely`,
`Writer`, the redactor, `SandboxProject` (corpus), `History`/`Comparison` (new-signature
sets for co-onset).

**Modify:**

- `FailureBuilder` — phase, raise locus (incl. test infra, cause-aware), identity,
  entities from structured attributes, `seq`/`run_time`/worker. All inside the existing
  fail-soft pattern.
- `Failure` — carry those fields; serialize them in `to_h` for workers.
- `Formatter` — census counters in `example_passed`/`example_pending`/`example_failed`;
  stdout lines.
- `ParallelMerger` — rehydrate the new fields, sum census, keep per-worker sequences;
  `WORKER_SCHEMA` 4. (Fix the loose-digest bug in the same change.)
- `Report` — `causes` computed after `groups`, inside `safely`; JSON schema 3.
- `Reporters::Markdown` — Likely causes section; Related / Shared code paths sections
  folded in.
- `Reporters::OutsideExamples` — group identical errors (small, separate).

**New (small):** `Causes` (one module: evidence extraction, a strength table, union-find,
scope rule, split check, roles, confidence — a few hundred lines), `Cause` (value object
like `Cluster`), `Census` (counters), `TestInfra.frame?` (path patterns alongside, not
replacing, `spec_frame?`), `Reporters::Causes`.

**Do not introduce:** a scoring engine, weights, probabilities or Bayesian networks
(fake precision, unauditable); similarity/embeddings/LLM calls; a plugin framework for
extractors; per-example coverage by default; telemetry; a CLI subcommand that would
shadow RSpec arguments; any change to existing digests; a graph library.

**Performance:** capture is O(frames) on already-parsed frames per failure (sub-µs next
to existing parsing); census is one hash increment per example; analysis is linear in
signatures × entities with hash joins; git (optional) is one `git status --porcelain`
call when there are failures. The existing performance guard applies unchanged.

**Compatibility:** phase patterns must be proven on rspec-core 3.10 and 3.13 (both in
CI) and on Ruby 3.4's `Class#method` labels; failure to match yields `unknown`, never a
wrong phase. `object_id` identity is per process only. `KeyError#receiver` needs Ruby
2.6+ (fine: 2.7+ supported). Rails differences (`show_exceptions` in 7.1, template error
wrapping) only affect which evidence is present, not correctness.

## 11. Spike

**Question:** does deterministic causal clustering find true shared-cause clusters
without hiding independent failures — and does it beat what the existing layers already
achieve?

**Scope:** Layer 0 capture (phase, raise locus, identity, env/const/attr entities,
embedded error), census by group and type, Layers 2–6, stdout rendering and the JSON
block. Out: git, history co-onset, Markdown restructuring, parallel merger, onset,
worker confinement.

**Corpus:** 12 sandbox projects via `SandboxProject` (plain Ruby that raises the same
classes and messages Rails would, as the existing "Rails-shaped" specs already do), each
with `truth.json` mapping example ids to a cause label or `independent`, and a labelled
origin location per cause. Every project mixes 1–2 shared causes with 2–5 independent
failures. Scenarios: S1 (replicated), S2, S3, S3-silent, S4, S5, S6, S8, S9, S11, S14,
S15. Plus the repository's own suite run in a container without the binstub, as the one
real-world case.

**Metrics:**

- pairwise precision and recall of the "same cause" relation over failures;
- **independent failures merged into any cluster** (count);
- purity of HIGH clusters and of MEDIUM clusters;
- inspect-first equals the labelled origin (per resolvable cause);
- stdout line count; byte-identical JSON across two runs;
- the same metrics for the **baseline**: signatures ∪ related clusters ∪ shared code
  paths, union-found.

**Success:**

1. 0 independent failures merged, across all runs.
2. HIGH clusters 100% pure; MEDIUM ≥ 80% pure.
3. Recall ≥ 0.8 on the scenarios declared structurally resolvable in advance (S1–S4,
   S6, S11, S14, S15), and ≥ 30 points above baseline.
4. Inspect-first correct for ≥ 9 of 10 resolvable causes.
5. S5, S8, S9 produce no merges and a co-onset/experiment hint.
6. The §2 real run yields one MEDIUM cluster of 9 with the `command not found` clue.
7. Stdout ≤ 10 lines everywhere.

**Failure (stop or rethink):** any HIGH false merge; recall < 0.5 or < +30 over
baseline; passing requires tuning more than the three published thresholds; phase
detection cannot be made reliable on rspec-core 3.10.

---

## Why this could be killer

The costly part of a red suite is not reading failures; it is choosing what to do first.
Most many-failure runs are one to three causes plus a tail of symptoms, and today every
tool — RSpec, other formatters, and an agent reading either — handles them in O(failures).
rspec-signal already cut the reading cost; this cuts the *deciding* cost to O(causes). It
does it with evidence nothing else surfaces: RSpec hands the formatter proof (the same
exception object) that twenty failures are one raise, and throws it away; it knows which
examples never reached an assertion, and doesn't say; it ran 493 passing examples that
make "9 failures in one group" meaningful, and forgets them. For agents it is a control
signal, not a convenience: environment-versus-code and symptom-versus-origin are exactly
the distinctions that stop an agent from rewriting working code or weakening assertions.
And it closes a loop the gem already half-built: exact verification commands, then
history recording whether a cluster resolved together — ground truth, for free, every run.

## Why this could be a bad idea

The easy cases are already solved and the hard cases may be unsolvable. When structural
evidence is strong — same raise site, same message, same hook — the existing signature
already groups the failures (the `before(:context)` cascade, the loud factory, the global
hook are each *one signature today*). The cases the feature exists for — one cause
through different exceptions, assertion-only regressions — are exactly where evidence is
weakest, so the layer either stays silent there or guesses. The real value may live in a
narrow band (entities across shapes, setup vs. body, confinement), and a wrong HIGH in
that band costs more than every right one earns: it misdirects agents with authority, and
a section users learn to distrust is just new noise. Add maintenance against rspec-core
internals and Rails message formats, and an agent that could read the six signatures in
§2 and guess "one environment problem" unaided, and the honest counter-proposal is: expose
the hidden evidence, skip the clustering.

## Smallest useful version

Three evidence types nothing else shows, and one rule:

1. **Setup vs. body**, with the raise locus in test infrastructure — "11 failed in setup
   at spec/support/auth_helpers.rb:14; they never reached their assertions."
2. **Confinement from a pass/fail census** — "confined to parallel_tests_spec.rb: 9/11
   failed, 0/493 elsewhere", "every system spec failed, nothing else did".
3. **Entities from structured exception attributes** — ENV key, constant, `Model#attr`.

Rule: merge signatures that share a raise locus or an entity (HIGH); make a MEDIUM scope
cluster from confinement only when nothing linked; list everything else as independent;
print `n/n accounted for`. Two stdout lines per cluster, one JSON block. That already
turns §2 from six problems into one, and the auth/env/driver/schema scenarios into one
line each — which is the part that feels like magic.

## One-day spike

1. **Harness (0.5 h).** `spec/causal/corpus.rb`: a scenario DSL over `SandboxProject`
   that writes files plus `truth.json`; `spec/causal/evaluate.rb` that runs each
   scenario with `run_signal`, reads `signal.json`, and scores it.
2. **Scenarios (1.5 h).** The twelve listed in §11, each 20–40 lines, each with ≥ 2
   independent failures.
3. **Capture (1 h).** In `FailureBuilder`: `phase` from frame labels, `raise_locus`
   (+ kind, cause-aware), `identity` for context hooks, entities from
   `KeyError#receiver`/`NameError#name`/`NoMethodError#receiver`, embedded error from
   the HTML summary and a three-phrase list, `run_time`. Unit tests on 3.13 **and** 3.10
   (`RSPEC_VERSION=3.10`) for phase.
4. **Census (0.5 h).** Counters by top-level group id and `type`, in `Formatter`.
5. **Analysis (2 h).** `Causes.call(groups, census)`: evidence per signature, union-find
   on strong links, split check, scope rule with the three published thresholds, roles,
   primary, confidence, independents, accounted-for invariant.
6. **Output (0.5 h).** Stdout lines and `causes` in `signal.json`.
7. **Evaluate (1 h).** Metrics table for causes vs. baseline; determinism check (two
   runs, diff).
8. **Real run (0.5 h).** This repository's suite without the binstub on PATH; record
   the output next to today's 6-signature report.
9. **Decide (0.5 h).** Write the table and a go/no-go against §11's criteria.

## Moat

Thin in data, real in position. The data that would matter is labelled
(failure set → actual cause → fixing diff) triples, and the history mechanism produces
labels locally for free: signatures that resolve in the same run after one edit were one
cause, and the edit says where. Aggregated across many suites, that would calibrate which
evidence types are reliable (is a shared `spec/support` raise site 99% pure? a confined
group 70%?) and grow the catalogue of environmental and definitional error shapes. But
the rules are MIT-licensed and easy to copy; the error-shape catalogue is mostly public
knowledge; and collecting labels means telemetry, which contradicts the project's privacy
stance and which enterprises would refuse. At most, an opt-in stream of *structural*
outcomes (evidence type, linked or not, co-resolved or not — no messages, no paths) could
turn the confidence words into measured ones. The stronger advantage is not data: it is
being trusted never to overclaim, and having the `causes` schema become what coding
agents expect a test runner to hand them — a standard rather than a dataset. Per-repo
learning ("failures here usually cascade from spec/support/stripe.rb") is a good
feature, not a moat.
