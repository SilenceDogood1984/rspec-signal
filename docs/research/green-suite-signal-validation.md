# Validation: green-suite signal on unseen Rails apps

**Question.** The spike ([green-suite-signal-spike.md](green-suite-signal-spike.md)) ended at
WEAK GO: two misleading green tests were proven by mutation, but only one repository was held out of
rule tuning. Does the frozen detector find real misleading tests in Rails suites it has never seen,
without drowning them in noise?

**Short answer.** It found **7 verified misleading tests in 2 of 3 unseen apps**, and the frozen model
pass kept all 7 while suppressing every intentional finding it judged. But one frozen rule flagged
**99 % of one app's passing examples** from a single `method_missing` line. A rule the spike had picked
for production was **95 % intentional**. Neither of the spike's two headline mechanisms recurred in its
original form. The most productive out-of-sample class was one the spike had set aside: examples in
which **nothing was actually checked**. Most of those are already caught by a static linter.
**Verdict: WEAK GO** (section 14), and one pre-registered experiment would settle it (section 15).

---

## 1. Frozen detector

Frozen in commit `188181a`, pushed before any unseen repository was opened. The
`research/green_signal/validation/check_frozen.sh` script proves the files used are these files.

| File | sha256 |
|---|---|
| `observer.rb` | `bbb318093905bee8730d5db741177fb39d2ab7c9d7198b4a37032b374aa7d345` |
| `rules.rb` (v2.1) | `42bd8701c269449a8e8bd1e53a71a9472801041282ee0bb01c418f00365d698c` |
| `rules_v1.rb` | `19affec38099ead601274849db3b86673df689f8961465b9b51a23e9442c7d67` |
| `analyze.rb` | `c84df55716aa6b1c32790b80032169c1c7341c2f44bec6939b31bbafaaa075bb` |
| `llm/packets.rb` | `cf5db34341cf872844c7a7922d16017a2c2dc5d05becfc1e8a82ec3e1464948e` |
| `llm/judge_prompt.md` (verbatim judge prompt) | `1a2575bea64d97709aff7cc37a4d1d5b260f0587a2329c663681ab109280362c` |
| `bench.sh` | `99aeda739ad091d79575d90f1abee9cedc1b8d3a70d0dbb922c0222cce522d38` |

Nothing was added, removed, re-thresholded or special-cased during the run. The verification was
re-run before every analysis and passed each time.

## 2. Experiment design

The procedure is written down in `research/green_signal/FROZEN.md` and was followed per app:

1. Green baseline without the observer. Examples that fail without it are excluded.
2. Observed run, `rspec -r observer.rb`, with the app unmodified or a throwaway export of it.
3. Frozen rules. *Shown* means MEDIUM or HIGH and not suppressed, counted once per (example, rule).
4. Frozen model pass. Claude Sonnet, as a blind subagent, read the packets with the verbatim prompt.
   SUSPICIOUS or UNCLEAR keeps an example; CONSISTENT suppresses it.
5. Manual classification of every shown finding (sampling rules in section 4).
6. Mutation proof of every candidate, applied only at runtime (`rspec -r <mutation>.rb`) or in a
   scratch copy. Every clone was clean afterwards.

Deviations, none of which touch the rules or the prompt:

- **Ruby version.** Two public apps pin Ruby versions not installed here (4.0.2 and 4.0.7). Both ran
  on Ruby 3.4.4, which their Gemfiles allow, overridden through the environment and never by editing
  the app.
- **Judge sample in App C.** One rescue site produced 1,722 flagged examples, so the model judged
  every example flagged by any *other* rule (125) plus a seeded random sample (`Random.new(42)`) of 40
  of the 1,597 examples flagged only by that site. All 40 sampled examples were suppressed. The
  unjudged remainder is counted as suppressed and called out wherever it matters.
- **Packet size.** The 165 App C packets (~670 KB) were split at packet boundaries into four files,
  each judged by its own instance with the same prompt.

## 3. Apps

Nine apps were attempted. Three ran green enough to count.

| | **App C** | **App D** | **App E** |
|---|---|---|---|
| Repository | Fat Free CRM @ `91595c4` (public) | human-essentials @ `d6f8290` (public) | private |
| Shape | CRM, controller-spec heavy, Devise + **CanCanCan** | nonprofit inventory, request-spec heavy, Devise + **rolify** roles | small Rails 8 app, Devise |
| Rails / rspec-rails | 8.0.5 / 7.1.1 | 8.1.4 / 8.0.2 | 8.0.2 / 8.0.4 |
| `show_exceptions` in test | `false` | `false` | `:rescuable` |
| Subset | full suite | `spec/requests` + `spec/controllers` | full suite |
| Examples / passing | 1,773 / 1,737 (36 fail with and without the observer) | 1,036 / 1,035 | 58 / 55 |
| Passing request / controller / feature examples | 3 / 657 / 20 | 950 / 85 / 0 | 13 / 0 / 0 |

Excluded, with the reason recorded before any finding was looked at:

| App | Reason |
|---|---|
| Mastodon (API-heavy) | needs libvips ≥ 8.13 at boot; the ICU and libidn gems were built from source, but libvips needs glib headers, and this machine has no root |
| Forem (API-heavy) | schema requires the `pgvector` extension, which is not installed here |
| Chatwoot (API-heavy) | same `pgvector` requirement, found at screening |
| private Rails 6.1 / Pundit app | baseline **3,683 of 9,026 failing** in this environment (82 min); the observed run hit the 2-hour limit at 5,731 examples |
| private Rails 7.1 app | its own committed migrations do not run on its Rails version |

**The API-heavy slot is unfilled.** All three API-heavy candidates were blocked by system libraries,
not by anything in the detector. A supplementary note on the excluded Pundit app is in section 10.

## 4. Per-app metrics

Sampling: App D had 9 shown findings, all classified. App C had more than 30, so all HIGH findings
were classified by rescue site and handler and read individually where the site or handler differed,
and all 7 MEDIUM findings were read individually. App E showed nothing.

| | App C | App D | App E | **All** |
|---|---:|---:|---:|---:|
| passing examples | 1,737 | 1,035 | 55 | **2,827** |
| shown before model (examples) | 1,722 | 9 | 0 | 1,731 |
| per 1,000 passing | 991.4 | 8.7 | 0 | 612.3 |
| shown before model, excluding the one rescue site | 125 | 9 | 0 | 134 (47.4 / 1,000) |
| kept after model (examples) | 5 | 3 | 0 | **8** |
| per 1,000 passing | 2.9 | 2.9 | 0 | **2.8** |
| **verified misleading** | **4** | **3** | 0 | **7** |
| probable misleading | 0 | 0 | 0 | 0 |
| interesting | 8 | 0 | 0 | 8 |
| intentional | 113 | 6 | 0 | 119 |
| false positive (examples flagged only by the one site) | 1,597 | 0 | 0 | 1,597 |

## 5. Per-rule precision

One row per shown (example, rule) finding. Rules that showed nothing are listed below the table.

| Rule | Shown | Judged | Kept by model | Verified | Interesting | Intentional | False positive |
|---|---:|---:|---:|---:|---:|---:|---:|
| `GREEN_NO_ASSERTIONS` | 6 | 6 | 6 | **5** | 1 | 0 | 0 |
| `GREEN_EXCEPTION_RENDERED` | 1 | 1 | 1 | **1** | 0 | 0 | 0 |
| `GREEN_RESCUED_EXCEPTION` | 121 | 121 | 1 | **1** | 5 | **115 (95 %)** | 0 |
| `GREEN_AUTH_HALT` | 6 | 6 | 0 | 0 | 2 | 4 | 0 |
| `GREEN_SWALLOWED_EXCEPTION` | 1,722 | 165 | 5 * | 0 | 0 | 0 | **1,722 (100 %)** |

\* Only as a passenger: those 5 examples were kept for their other findings, and the model never
cited this rule.

Showed nothing on unseen apps: **`GREEN_EXCEPTION_PAGE`**, **`GREEN_SETUP_REQUEST_FAILED`**,
`GREEN_ROLLBACK` (5 suppressed in App D), `GREEN_ERROR_PAYLOAD`, `GREEN_ERROR_TEMPLATE`,
`GREEN_JOB_FAILURE`, `GREEN_THREAD_DIED`, `GREEN_LOGGED_ERROR`, `GREEN_EXAMPLE_RESCUED`.

`research/green_signal/validation/summary.rb` regenerates sections 4, 5 and 8 from
`validation/classifications.json`.

## 6. Verified misleading tests

Every one was proven by a runtime mutation that left the test green, with a control where one was
possible. Mutation scripts are in `research/green_signal/validation/mutations/`.

| # | App | Spec | What the test claims | What actually ran | Mutation that stays green | Control | rubocop-rspec `NoExpectationExample`? |
|---|---|---|---|---|---|---|---|
| 1 | C | `spec/controllers/entities/contacts_controller_spec.rb:225` | field_group returns the existing tag | `assigns[:tag].name == @tag.name`: a bare comparison, no `expect` | `field_group` assigns a different tag | with `expect(...)` added, it fails | **flagged** |
| 2–3 | C | `spec/controllers/users_controller_spec.rb:164`, `:167` | destroy removes the user / redirects | empty bodies; no request is issued | `UsersController#destroy` raises | — | **flagged** |
| 4 | C | `spec/controllers/entities/leads_controller_spec.rb:731` | promote copies lead permissions to the new account and opportunity | CanCan **denied** the promote (the signed-in user has no access to the Shared lead); all 8 expectations check objects **the test itself built**, and `allow(@account).to receive(:new)` stubs an instance, not the class | `LeadsController#promote` raises | a sibling promote example fails | not flagged |
| 5 | D | `spec/requests/requests_requests_spec.rb:181` | a fulfilled request's page has no Cancel button | `requests_path(record)` (plural) hit **`#index` with format "26"** and got a **406**; the negative assertion ran against that error body | `RequestsController#show` always renders a Cancel button | with `request_path` it fails even unmutated: the selector also matches a layout dropdown button, so the test is broken twice | not flagged |
| 6 | D | `spec/requests/organization_requests_spec.rb:247` | admins see Promote/Remove links | `within(".content") do expect(...) end` resolves to an **`RSpec::Matchers` DSL method** that builds a matcher; the block never runs, so **0 expectations executed** | `OrganizationsController#show` renders an empty page | the sibling "Demote" example fails | not flagged (`expect` is lexically present) |
| 7 | D | `spec/requests/partners_requests_spec.rb:799` | reactivating an active partner fails with a flash error | issues the `put`, asserts nothing | reactivation "succeeds" with a success notice | — | **flagged** |

**4 of the 7 are already caught by rubocop-rspec's static `RSpec/NoExpectationExample`**, checked by
running that cop on the same files. **3 are visible only at runtime** (#4, #5, #6).

The 8 INTERESTING findings:

- a shared example whose only expectation is skipped for the Admin host, so it asserts nothing there;
- 5 examples named *"when unauthorized … should destroy the requested email"* whose bodies correctly
  assert the **denial**: the test is right and its name is wrong;
- 2 feature specs that begin with a stale signed-in state, which the sign-in helper then overrides.

## 7. Mutation-proof method

A mutation is a module prepended to one controller in `before(:suite)` and loaded with `rspec -r`. It
breaks exactly the behaviour the test claims to establish. A misleading test stays green. Where
possible, a **control** shows the mutation is effective: a corrected copy of the test, or a sibling
example that reaches the same code, fails under the same mutation. Corrected copies were written to a
scratch clone under a `zz_control_*` name and deleted afterwards. No private repository was mutated,
and no mutation persisted in any clone.

## 8. Model-filter performance

Example level, judged examples only:

| Class | Judged | Kept (SUSPICIOUS/UNCLEAR) | Suppressed |
|---|---:|---:|---:|
| verified misleading | 7 | **7** | 0 |
| interesting | 8 | 1 | 7 |
| intentional | 119 | 0 | **119** |
| false positive (sampled) | 40 | 0 | **40** |

- **Misleading tests retained:** 7 of 7. **Incorrectly suppressed:** 0.
- **Intentional suppressed:** 119 of 119. **False positives suppressed:** 40 of 40 sampled.
- It also suppressed 7 of 8 INTERESTING findings: the misnamed "when unauthorized … should destroy"
  examples (it noted "stale title"), and the stale-sign-in features.
- **Without the model**, the frozen rules show 612 examples per 1,000. Even excluding the one
  rescue site, it is 47 per 1,000. Only the model brings the total to 2.8 per 1,000.
- But the two clean rules alone, `GREEN_NO_ASSERTIONS` and `GREEN_EXCEPTION_RENDERED`, would have
  shown 7 findings (6 verified, 1 interesting, 0 intentional, **2.5 per 1,000**) **with no model at
  all**.

## 9. Runtime overhead

Paired runs on two unseen apps, both orders, nothing else running. The raw numbers are in
`research/green_signal/validation/overhead.txt`.

| App | Order | Baseline | Observed | Δ time | Peak RSS | Objects allocated | GC time |
|---|---|---:|---:|---:|---|---:|---|
| C | baseline first | 132.8 s | 140.4 s | **+5.7 %** | 511 → 530 MB | +11.4 % | 4.9 → 5.2 s |
| C | observed first | 146.4 s | 154.8 s | **+5.7 %** | 538 → 554 MB | +11.3 % | 4.5 → 5.9 s |
| D | observed first | 128.8 s | 131.3 s | **+1.9 %** | 584 → 625 MB | +7.0 % | 5.3 → 5.7 s |
| D | baseline first | excluded: the baseline overlapped mutation runs on the same app | | | | | |

What the cost is, from the observer's own counters on the same runs:

| | App C | App D |
|---|---|---|
| TracePoint (`raise`/`rescue`) | **3.0–3.2 s**: the app raises and rescues a `NoMethodError` on every settings lookup, 11,611 times, and each one is described | 0.03 s |
| SQL notification subscriber | 0.85–0.95 s | **1.29–1.36 s** |
| assertion interception (expectation probe) | 0.32–0.37 s | **0.96–1.16 s** |
| response and controller inspection | 0.16–0.19 s | 0.45 s |
| serialization | 0.12 s | 0.07 s |
| allocation volume | +11 % objects | +7 % objects |
| packet construction | offline, after the run; not part of suite time | same |

Overhead is **2–6 %**, below the spike's ~9 % on App A. Its size depends on how the app uses
exceptions, because TracePoint cost scales with raise/rescue traffic: the cost is spent recording the
very rule that produced only false positives. Without the swallowed-exception rule, TracePoint would
only be needed for thread deaths.

## 10. Cross-app generalization

- **What generalized:** checking what *actually ran* against what was asserted. All 7 verified
  findings are tests whose assertions could not fail: no expectation ran, the action under test never
  ran, or the asserted body was an error response.
- **What did not:** the broad application-behaviour rules. A rescue or swallow is how these apps are
  written. App C's settings model rescues a `NoMethodError` inside `method_missing` on every lookup,
  and a frozen rule turned that into 11,611 HIGH findings. App C answers every not-found and
  access-denied XHR with a 200 `window.location.reload();`. Its specs assert exactly that body, but
  the frozen suppression only reads redirect targets, statuses and flash.
- **Configuration matters.** Both larger apps run tests with `show_exceptions = false`, so
  exceptions raise into the example and the debug-page mechanism cannot occur. Apps generated by
  Rails ≥ 7.1 default to `:rescuable`. This sample, like many long-lived apps, predates that.
- **Supplementary, excluded app** (private Rails 6.1 / Pundit; red baseline, partial run, not
  classified, not used for any criterion): 319 of 3,295 observed passing examples were shown, 305 of
  them `GREEN_AUTH_HALT` at authorization guards in denial specs. Those specs assert a generic
  redirect, or the target via `include("/site/oops")` on the location, which the frozen suppression
  does not read. It is the same noise class the spike recorded for v1.

## 11. Strongest surviving signal

**"Nothing in this passing example could have failed"**, observed at runtime:

- zero expectations executed (`GREEN_NO_ASSERTIONS`: 5 verified, 1 interesting, 0 intentional);
- the content assertion ran against an error response (`GREEN_EXCEPTION_RENDERED`: 1 of 1 verified).

It is deterministic, needs no model, and was never wrong out of sample. Its weakness is overlap:
4 of its 5 verified finds are also flagged statically by rubocop-rspec. Its runtime-only value is
cases like #6, where `expect` is present in the source but never executes.

## 12. Strongest failed signal

**`GREEN_SWALLOWED_EXCEPTION`**: 1,722 shown, 1,722 false positives, all from one line. Runner-up:
**`GREEN_RESCUED_EXCEPTION`**, 115 of 121 intentional (95 %). It is one of the four rules the spike
proposed to ship. It also produced verified #4, but only the model could find that one among the
other 120.

## 13. Did the two original classes generalize?

| Class | Spike evidence | Out of sample | Verdict |
|---|---|---|---|
| **A. A green request spec asserted against an exception/debug page** | 1 proven (App A), Rails ≥ 7.1 `:rescuable` debug page echoing the spec's own source | `GREEN_EXCEPTION_PAGE`: **0 fires**; no app in the sample renders debug pages in test. The broader form, a content assertion run against an **error response**, appeared once (#5, a 406 from a wrong path helper) | **Generalized only in the broader form.** The specific debug-page echo is neither confirmed nor refuted |
| **B. The actor you think executed the request did not** | 1 proven (App B), a refused second sign-in | `GREEN_SETUP_REQUEST_FAILED`: **0 fires**; no failed sign-in observed. Nearest case: #4, where the signed-in actor lacked permission and the action never ran. It was found only through the 95 %-intentional rule plus the model | **Weakly generalized** (1 case, model-dependent) |
| *C. Nothing was checked (unanticipated)* | set aside in the spike as "covered by rubocop-rspec" | 5 of 7 verified finds; 4 of them are also static-detectable | **Generalized**, but mostly not differentiated |

A and B **are separate problems**. They need different evidence (the response actually returned
versus the actor and the action that actually ran) and fail in different ways, and the data supports
neither as a standalone product yet. Do not force them into one concept. If either becomes a product,
it is A in its broader form, joined with C's runtime cases: **"this example's assertions could not
have failed, and here is the runtime evidence why."**

## 14. Decision: **WEAK GO**

Against the criteria pre-registered in the spike report, unchanged:

| STRONG GO criterion | Result |
|---|---|
| 1. ≥ 1 verified misleading test in ≥ 2 unseen repositories | **Met.** App C: 4, App D: 3 |
| 2. ≤ ~5 shown per 1,000 passing after the model pass | **Met.** 2.8 overall (2.9, 2.9, 0) |
| 3. No retained rule > 50 % intentional | **Not met.** `GREEN_RESCUED_EXCEPTION`, one of the spike's four proposed rules, was 95 % intentional. Two of the other three (`GREEN_EXCEPTION_PAGE`, `GREEN_SETUP_REQUEST_FAILED`) never fired, so they cannot be shown to pass |
| 4. No verified finding suppressed by the model | **Met.** 7 of 7 kept |
| 5. Overhead acceptable for opt-in/CI | **Met.** +5.7 % (App C, both orders) and +1.9 % (App D); +4–7 % peak memory |

Failure criteria: "model filtering is required to rescue fundamentally noisy deterministic rules" is
**true** for the swallowed-exception and rescued-exception rules. The others are false: real
misleading tests were found in apps unlike the tuning set, filtered noise is low, the model hid no
verified finding, and the useful cases did **not** collapse to the debug-page edge case (that case
did not recur at all).

**Not STRONG GO**, because criterion 3 fails for a rule the spike had chosen to ship, and the
debug-page and setup-sign-in rules are untested out of sample. **Not NO-GO**, because 7 misleading
tests were verified in 2 of 3 unseen apps, at 2.8 shown per 1,000 after filtering. Three of them are
invisible to existing static tools.

## 15. The one missing experiment

**A deterministic-only run of the narrow rule set on three Rails ≥ 7.1 apps that use
`show_exceptions = :rescuable`, including one API-heavy app, counting only findings a static linter
cannot see.**

- Rules, unchanged from the frozen v2.1 code: `GREEN_EXCEPTION_PAGE`, `GREEN_EXCEPTION_RENDERED`,
  `GREEN_SETUP_REQUEST_FAILED`, `GREEN_NO_ASSERTIONS`. No model.
- Remove anything rubocop-rspec's `RSpec/NoExpectationExample` already flags.
- Run on a machine with libvips and pgvector (or the apps' own Docker setups), so the API-heavy
  candidates blocked here can run.
- **GO** if at least one *runtime-only* verified misleading test appears in at least two of the three
  apps, with at most 1 intentional finding per 1,000 passing examples. **NO-GO** otherwise.

That settles the one open question. Is there a runtime-only, deterministic, low-noise signal that
existing tools miss, at a rate worth shipping? Every other question in the brief has an answer above.

---

## Reproduction

```bash
research/green_signal/validation/check_frozen.sh              # proves the detector is the frozen one
ruby research/green_signal/validation/summary.rb              # rebuilds sections 4, 5 and 8

# Per app (public apps at the SHAs in section 3, Ruby 3.4.4):
GREEN_SIGNAL_OUT=facts.jsonl bundle exec rspec -r /abs/research/green_signal/observer.rb
ruby research/green_signal/analyze.rb facts.jsonl --root . --json findings.json
bundle exec rspec -r research/green_signal/validation/mutations/<mutation>.rb <spec>:<line>
```

Files under `research/green_signal/validation/`: `classifications.json` (one entry per shown finding
for Apps C and D, with class and model verdict), `judgments/` (frozen judge output and packet
indexes), `mutations/` (the six mutation modules), `summary.rb`, `check_frozen.sh`. Private-app
evidence stays in the git-ignored `research/green_signal/private/`.
