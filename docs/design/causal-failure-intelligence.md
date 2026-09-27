# Relationships between signatures (experimental)

**Status:** experimental, **off by default** (`config.causal_analysis = true` turns it on).
Merged so that it can be dogfooded and deleted cleanly if it does not earn its keep.
The original research and proposal, including the parts this spike overturned, are in
this file's history at commit `487d460`.

## What it is

Signatures say which failures are *the same failure*. This layer relates **signatures to
each other**, from structural facts only, and classifies every failure into exactly one
group:

| Kind | Claim | Confidence |
|---|---|---|
| CAUSAL | the member signatures share an origin | always HIGH |
| SCOPE | failures are concentrated in one file or one `type:` -- *where*, never *why* | none |
| INDEPENDENT | no relationship found -- not "proven unrelated" | none |

Hints (`same_origin_different_message`, `reused_exception_instance`) appear in JSON only
and never change grouping. `n/n failures classified` is bookkeeping, not a count of root
causes. Nothing in the output names a root cause.

## Its dependency on signature identity

The layer treats exact signatures as its units. It is therefore only as good as they
are. Dogfooding found signatures fragmenting one failure: RSpec's `Failure/Error:` echo of
the failing source line reached the fingerprint, and when an error is raised inside a gem
that line is each example's own call site. One broken factory reached from seventeen spec
lines became ten signatures.

That is fixed underneath this layer (`496fae1`): the echo is no longer identity, and
`history.json` moved to schema 2 so older, incomparable digests are ignored for one run
rather than reported as resolved and new. On the factory reproduction below the fix turns
seven `RecordInvalid` fragments into one signature of fourteen -- with this layer off.

Identity limits that remain, and that this layer does not repair:

- Assertion failures raised at different spec lines are different signatures by design,
  even when one regression caused them all.
- A signature merges everything with the same class, message and raise site, including a
  shared example failing identically in two independently broken hosts, and a reused
  exception instance raised from two places (Ruby keeps its first backtrace).

## Evidence (frozen for the experiment)

Captured in `FailureBuilder` from the full backtrace, before reduction, and carried in
worker payloads so a parallel run reasons over the same facts:

| Evidence | Source | Links signatures? |
|---|---|---|
| shared exception object | the one object RSpec hands every example of a failed `before(:context)` | yes |
| same underlying exception | innermost cause's class, the exception's *own* normalized message, first-party origin | yes |
| missing definition | `KeyError#receiver` is `ENV`; `NameError#name` qualified by `#receiver`; `NoMethodError` on a class whose source is first-party | yes |
| phase | rspec-core frames outside the failing code, matched to the loaded `BeforeHook#run`/`AfterHook#run`/`AroundHook#execute_with` | no -- a fact about one signature |
| repeated error outside examples | the same fingerprint while loading several spec files | no -- a fact about one signature |
| concentration | a pass/fail census per file and `type:` | scope only |

A signature on its own forms a causal group only when it carries a fact its fingerprint
does not: a shared `before(:context)` object, every member failing in setup, a `let` or
teardown, a missing definition, or one error outside examples in several files.

Scope thresholds are internal constants in `Causal::ScopeAnalysis`: at least three
failures in at least two otherwise-unrelated signatures, at least two thirds of the scope
failing, fewer than one in twenty elsewhere, and the rest at least as large as the scope.

**No other evidence may be added during the experiment.** Candidates belong under
[Future experiments](#future-experiments).

## What it refuses to infer

- A relationship from exception class, message similarity, file, timing or test order.
- Anything from a method missing on `nil` or a core class.
- Shared identity outside `before(:context)`.
- Concentration per parallel worker: `parallel_tests` assigns files by size, and the
  corpus produced a true but meaningless "13/13 failed on worker 2".
- "Example body never reached" for a lazily evaluated `let`: the body had begun.

## Verified RSpec behaviour it relies on

Checked on rspec-core 3.10.2 and 3.13.6 by specs that raise inside real hooks
(`spec/unit/causal/capture_spec.rb`), and in CI on Ruby 2.7 to 3.4:

| Failure in | Frames just outside the failing code |
|---|---|
| example body (and a `let` evaluated from it) | `Example#instance_exec` then `block in Example#run` |
| `before` / `after` hook | `Example#instance_exec` then `BeforeHook#run` / `AfterHook#run` |
| `before(:context)` | `BasicObject#instance_exec` then `BeforeHook#run` -- no `Example` involved |
| `let` | a `memoized_helpers.rb` frame inside the anchor |

## Evaluation

`bundle exec ruby spec/causal/evaluate.rb --verbose`. Pairwise "same cause" relation;
"solvable" scenarios were declared when written.

**Authored corpus** (16 scenarios, written alongside the rules, including adversarial
ones): 10 causal groups, 0 containing two true causes, 0 of 28 independent failures
merged, every failure classified; recall on solvable scenarios 1.00 against 0.75 for
signatures alone and 0.81 for all existing layers. Serial and parallel runs produce the
same groups. None of these scenarios raised inside a gem from several call sites, so the
corpus never exercised the fragmentation that dogfooding found.

**Dogfood reproductions** (`spec/causal/dogfood.rb`), rebuilt from failures seen on a
Rails application, truth fixed before the first run, nothing tuned after:

| Case | True causes | Signatures before the identity fix | After | Causal groups | Scope | Independent |
|---|---|---|---|---|---|---|
| factory cascade: 17 failures through `subject`, `let`, `let!`, `before`, bodies, a `raise_error` matcher and a rescued 422 | 1 shared + 2 unrelated | 12 | 6 | 0 | 0 | 6 signatures, 19 failures |
| renamed constant referenced from four app files and a wrapping job, plus a date regression, a missing ENV key, a nil and a different missing constant | 2 shared + 3 unrelated | 9 | 9 | 1 (6 failures, 4 signatures: missing `Billing::TaxRate`) | 0 | 5 |

What they show:

- **The factory cascade is fixed by signature identity, not by this layer.** Its members
  failed in mixed phases, so no setup fact holds for all of them and the layer is silent.
  The matcher-wrapped and 422 symptoms stay separate: nothing structural relates them.
- **The renamed constant is where the layer adds something** -- a HIGH, structural
  statement naming the missing constant across four signatures and a wrapped job. The
  existing related-cluster and code-path layers already *hinted* at the same links
  (pairwise recall 0.94 either way), so the gain is in the strength of the claim, not in
  recall.
- No wrong merge in either case; the decoy `NameError` stayed independent.

## Costs

Disabled: one flag check per example (~0.2 µs), no census, no evidence, no new data in
worker payloads. Enabled: ~0.1 ms capture per failure (the existing per-failure pipeline
is ~1.5 ms), ~3 µs per example for the census (7 KB for 10,000 examples in 300 files),
~25 ms of analysis for 400 signatures, guarded as roughly linear by
`spec/performance/processing_cost_spec.rb`.

## Known gaps

- Scope requires a whole signature inside the scope, so a signature spanning two files
  keeps a scope group smaller than its own "9/11" statistic.
- A driver or factory failure reached partly from hooks and partly from bodies gets no
  phase fact.
- `signal.json`'s `outside_examples` stays a flat list; grouping is in the analysis and
  in `signal.md`.

## Before graduation

1. Dogfood on several real suites with it switched on; record every causal group and
   whether it was right.
2. Measure what it adds *beyond improved signatures and the existing layers*. On the two
   dogfood cases so far: stronger claims, no extra recall.
3. Fix the stale-report lifecycle and make stdout answer-first first; neither belongs here.
4. Keep `Causal::Analysis` small: new evidence types need their own home and adversarial
   corpus scenarios, or they do not land.
5. Graduate or delete. If it graduates, give `analysis` a real schema.

## Future experiments

Not implemented, and not to be added during this experiment:

- Embedded errors inside actual values (a Rails error page title, `command not found`) as
  links between assertion failures and the error behind them.
- Table, column and route entities -- they need message parsing.
- Per-example coverage (spectrum-based fault localisation) for regressions seen only
  through assertions.
- Co-resolution from history: signatures that resolve in the same run were one cause.
