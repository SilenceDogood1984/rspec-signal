# Research spike: green tests that should make us nervous

**Question.** RSpec says whether the assertions passed. Is there useful, differentiated signal in
what a *passing* example made the application do, the things it never asserted?

**Status.** Research only. All code is under `research/green_signal/`, outside `lib/`, outside the
gemspec's `files`, and excluded from RuboCop. Nothing is wired into rspec-signal.

**Repositories.** One synthetic Rails 8.0 fixture written for this spike, and two real, private Rails
applications, called **App A** and **App B** here. rspec-signal is public, so their names, paths and
code are kept out of this document. A git-ignored appendix
(`research/green_signal/private/`) holds the named evidence on the machine that ran the spike.

---

## 1. Executive conclusion

**Yes, there is real signal, and it found two passing tests that a competent developer would
have read as coverage they did not provide.** Both were verified by mutation.

- **App A:** a request spec asserted the "you already acknowledged this" message. A callback had
  raised `ActiveRecord::RecordInvalid`, and Rails rendered its 422 *debug exception page*. That page
  prints source extracts of every application frame, **including the spec file**, so the asserted
  sentence was present: it was the spec's own `expect(...)` line. With the message copy deleted from the
  app, the example still passes.
- **App B:** "denies reader and author access" signed in a reader, then called `sign_in(author)`
  **without signing out**. Devise refused the second sign-in. The "author" request ran as the same
  reader. With the admin gate mutated to admit authors, the example still passes.

Neither failure would ever surface in RSpec output, coverage, or any CI dashboard. The runtime
evidence that exposes them costs about **9 % more suite runtime** (median of five paired runs, both
orders; mostly extra GC) and about **+72 MB** peak memory. It comes from official Rails notifications, TracePoint, and four one-method
prepends.

But the yield is low and the noise is the whole problem:

- Raw "unusual" runtime facts are common in passing tests: 7 % of App A's passing examples rescue an
  exception in app code. Nearly all of it is deliberate.
- The first rule set flagged 4.8 % of App A's request examples. **59 of 61 distinct findings
  were intentional behaviour.**
- After calibration (v2.1), a fresh repository (App B) shows **12 of 1,869 examples** (0.6 %).
  **1 is a real misleading test, 11 are intentional.**
- The two real finds came from two narrow rules: *body assertions against Rails' exception page*, and
  *a setup sign-in that failed while later requests carried on*. The broad rules (swallowed exceptions,
  rollbacks, halts, zero writes) produced almost only intentional behaviour on real code.
- An LLM reading the deterministic evidence was an excellent second filter. Across 112 examples it
  marked every verified misleading test suspicious and **none of the 95 intentional or clean ones**.

**Decision: WEAK GO.** The signal is real and differentiated, the cost is acceptable, and two
real misleading tests were found and proven. But the rules were calibrated on the same suites they
were evaluated on, apart from App B, and the real-world yield is about one misleading test per 2,000
passing examples. The next step is a bounded experiment on more unseen suites with the rules frozen,
not a product (section 18).

## 2. Existing rspec-signal primitives

rspec-signal today is built entirely around **failures**. For a passing example it records nothing
except, with `causal_analysis` on, a pass/fail count in `Causal::Census`.

| Primitive | Where | Reusable here? |
|---|---|---|
| Formatter + notification registration | `formatter.rb` | **Yes.** `example_passed` already fires; the spike used `example_finished` on a listener |
| Reading rspec-core frames to tell body vs `before` vs `let` | `causal/phase.rb` | **Yes, the idea.** Re-implemented standalone in `observer.rb#call_site` to tell setup requests from the request under test |
| First-party / library / framework classification | `project.rb`, `backtrace/classifier.rb` | **Yes.** Same need: "raised in app code", "rescued in app code", "injected by rspec-mocks" |
| Best-effort per-example diagnostics hook | `integrations/capybara.rb` | **Yes, as a pattern.** Rescue everything, never change the outcome |
| HTML title/heading extraction | `html_summary.rb` | **Yes.** It already recognises the Rails exception page *for failures*; the strongest new rule is that recognition applied to passes |
| Redaction | `redactor.rb` | **Required.** Evidence carries flash, log lines, exception messages, request paths |
| Worker payloads, `signal.json`, history | `parallel_*`, `writer.rb`, `history.rb` | Yes, later: per-example facts are plain JSON and merge like failures |
| Fingerprints, grouping, related clusters, code paths, causal relationships | most of `lib/` | **No.** These group failure exceptions; a passing example has none |
| Outside-example error parsing, message and diff budgets | `outside_example.rb`, `message.rb` | No |

Nothing in rspec-signal observes the application while an example runs. Every runtime fact below
is new.

## 3. Taxonomy of green-but-suspicious behaviour

Each category with what is *objectively* observable. "Intent" can only come from the example's own
assertions, the description (low confidence), or a reader.

| Category | Observable fact | Needs intent to judge? |
|---|---|---|
| **A. Response contradictions** | 2xx with `{"error": ...}`; 2xx rendering an error template; exception text in a 2xx page; body assertions answered by **Rails' exception page** | Mostly no: a success status with an error body is a contradiction by itself |
| **B. Exception signals** | `rescue_from` handled X; app code rescued X and did not re-raise; exception escaped the controller and middleware answered; job `discard_on`; thread died unjoined; ERROR log line | **Yes.** Rescuing is how apps are written. Programming errors (`NoMethodError`, `NameError`) are the exception, and even they are rescued on purpose |
| **C. Database contradictions** | rollback inside a request; **writes discarded** by that rollback; mutating verb with zero writes; strong-params dropped keys | Partly. "Discarded writes, then a success response" is objective; "zero writes" needs intent |
| **D. Authentication / authorization** | `before_action :x` halted; actor at each request; a setup sign-in that failed or was refused; actor unchanged across a sign-in | Partly. A halt in an anonymous example is either the test or a forgotten sign-in; a *failed sign-in attempt* is objective |
| **E. Execution path** | controller/action reached vs halted; request that reached **no controller** (router 404, Rack endpoint); rendered templates | Yes for routing; no for "action never ran" |
| **F. Assertion weakness** | zero expectations; only a generic status class; negated-only checks; content checks that matched only printed source | Partly; "zero expectations" is objective but already covered statically (section 12) |

Description-derived expectations ("updates", "admin", "unauthenticated") were kept as **LOW hints
only**. On real code they were pure noise: 12/12 App A actor hints were intentional.

## 4. Candidate signals ranked by quality

Ranking from **measured** behaviour on 4,221 real passing examples, not from expectation. "Rails"
means request/system specs; "monkeypatch" counts the four prepends the spike uses.

| Signal | Captured via | Version deps | Cost | False positives seen | False negatives | Inference? | Without Rails? | Patch? | Changes behaviour? | **Rank** |
|---|---|---|---|---|---|---|---|---|---|---|
| Body assertion answered by Rails' exception page; literal matched only inside printed source | Integration session response + expectation probe | Rails ≥ 7.1 `:rescuable` default; `consider_all_requests_local` | tiny | 0 real (2 negated-check cases, now handled) | page variants other than DebugExceptions | no | no | yes (2) | no | **HIGH** |
| Setup sign-in failed / refused, later requests continued | `halted_callback` + status of helper/`before` requests + actor per request | any | tiny | 0 real | sign-in by stub or token (actor unknown) | no | no | yes (1) | no | **HIGH** |
| Authentication halt **after a sign-in attempt** | `halted_callback` + earlier actor | any | tiny | 0 | — | no | no | no | no | **HIGH** (rare) |
| Rescued exception (rescue_from) behind a **2xx** the example asserted as success | `rescue_with_handler` prepend | any | tiny | 0 real (0 occurrences) | handlers that call `super` oddly | no | no | yes (1) | no | **HIGH** (rare) |
| Rollback that **discarded writes** behind a success response with no failure flash | `sql.active_record` savepoint accounting | any | low | 0 after accounting (v1: 17/17 App A rollbacks intentional) | rollbacks with no SQL issued | no | no | no | no | **HIGH** (rare) |
| Thread died, never joined | TracePoint `:raise`/`:rescue`/`:thread_end` | Ruby 3.3 for `:rescue` | low | 0 | pooled threads that rescue | no | **yes** | no | no | **HIGH** (rare) |
| 2xx JSON with conventional error object | response body | any | low | 1/1 real intentional (polling endpoint; suppressed once regex assertions were read) | non-conventional shapes | no | no | no | no | **MEDIUM** |
| Error/fallback template served with 2xx | `render_template.action_view` | any | low | 0 real occurrences | custom names | weak (name pattern) | no | no | no | **MEDIUM** |
| Job discarded (`discard_on`) | `discard.active_job` | Rails ≥ 6 | tiny | 1 real occurrence (App B), suppressed by the example's own assertions | apps that `rescue` inside `perform` | no | no | no | no | **MEDIUM** |
| Exception escaped controller, middleware answered, status not asserted | `process_action` payload + issued status | Rails ≥ 7.1 | tiny | 2 real: the App A finding (now reported by the exception-page rule) and 1 ambiguous | — | no | no | yes (1) | no | **MEDIUM** |
| Rescued exception behind non-2xx, outcome not asserted | prepend | any | tiny | v1: 7/7 intentional | — | no | no | yes | no | **LOW** |
| App code swallowed a *programming* error (or logged what it swallowed) | TracePoint `:rescue` | Ruby ≥ 3.3 | low | 16/16 intentional across both apps (`Integer()`/date parsing, a documented fallback, fail-closed checks, error-to-message mapping) | — | no | **yes** | no | no | **LOW** |
| App code swallowed a *domain* exception | TracePoint `:rescue` | Ruby ≥ 3.3 | low | 570/570 intentional, from 31 distinct rescue sites, every site read (idempotency, races, parsing, control flow) | — | no | **yes** | no | no | **TOO NOISY** |
| Mutating request, zero writes | SQL counts | any | low | App A 1 MEDIUM + 41 LOW; App B 3 MEDIUM + 15 LOW; every MEDIUM intentional (idempotent retries, refused signups) | — | yes (intent) | no | no | no | **LOW** |
| Unpermitted parameters | `unpermitted_parameters.action_controller` | Rails ≥ 7, `:log` in test | tiny | 5.1 % of App B passes; path params dominate | — | no | no | no | no | **TOO NOISY** alone |
| Request reached no controller | integration probe | any | tiny | 15 findings in 5 examples, all intentional (route-retirement specs) | — | yes (intent) | no | yes | no | **LOW** |
| Description vs actor ("admin" but not admin) | actor + description | — | tiny | 12/12 intentional | everything | **yes** | — | no | no | **TOO NOISY** |
| ERROR log line not explained by another fact | broadcast logger | Rails ≥ 7.1 | low | 2/2 intentional until log text was matched to observed exceptions | — | no | no | no | no | **LOW** |
| Zero expectations | expectation probe | — | tiny | 1 real occurrence | — | no | yes | yes | no | **LOW** (static tools already do it) |

The pattern is the finding: **the precise rules are the ones that say something about the test,
not the application.** Swallowed and rescued exceptions describe the application. They are almost
always deliberate, and only the test's intent could say otherwise.

## 5. Experimental fixture

`research/green_signal/fixture/`: a 4-model, 12-controller Rails 8.0 app (SQLite, inline ActiveJob,
`show_exceptions = :rescuable` and `consider_all_requests_local = true`, as `rails new` writes them)
and **37 passing examples** (36 request specs, 1 service spec), organised by feature as a real suite would be. Ground truth lives in
`fixture/truth.rb`. The rules never read it, and the specs carry no comments that reveal it.

| # | Misleading green (14) | Defect | The weak assertion |
|---|---|---|---|
| 1 | wrong redirect | `sign_in(User.new(...))`: unsaved user, sign-in 401, PATCH bounced to `/login` | `have_http_status(:redirect)` |
| 2 | rescued exception | `NoMethodError` in a service, `rescue_from StandardError` renders 200 | `be_successful` |
| 3 | API error with 200 | `{error: "not authorized"}` with 200 | `have_http_status(:ok)` |
| 4 | authorization never reached | no sign-in; `authenticate_user!` halts before `require_admin!` | `have_http_status(:redirect)`, `not_to be_archived` |
| 5 | wrong actor | signs in the member, not the admin | `be_successful`, layout text |
| 6 | rollback | second row invalid, transaction rolled back, same success notice | `redirect_to(projects_path)`, notice |
| 7 | zero mutation | strong params permit `:display_name`, form sends `:name` | `redirect_to`, notice |
| 8 | unexpected template | non-owner gets `shared/not_found` with 200 | `be_successful`, layout text |
| 9 | swallowed job error | `discard_on` swallows the provider rejection | `redirect_to`, notice |
| 10 | thread error | fire-and-forget thread dies with `NameError` | `have_http_status(:accepted)` |
| 11 | wrong route | typo `/sumary`: router 404, scoping never ran | `have_http_status(:not_found)` |
| 12 | no assertions | none | — |
| 13 | swallowed inline error | `NoMethodError` rescued and logged; "Forecast unavailable" | `be_successful`, text |
| 14 | self-satisfying assertion | missing param, 400 debug page **prints the spec's own source** | `include("All systems operational")` |

Controls (14) exercise the same paths on purpose: anonymous redirect asserted with `redirect_to("/login")`,
asserted error JSON, `not_to change` around a rollback, `and_raise` into a rescue, member-denied with
target and alert asserted, asserted 404 from `RecordNotFound`, a real and a stubbed job failure
asserted through their failure records, a no-op update with `not_to change`, an asserted not-found
page, a thread joined under `raise_error`, an asserted routing 404, an asserted 401 and an asserted 400.
Nine clean examples do ordinary things correctly.

## 6. Instrumentation approach

`research/green_signal/observer.rb`, loaded only with `rspec -r`. It writes one JSON line per example.
It only observes: no response, exception, or return value is changed, and it never calls a real
`current_user`.

| Fact | Source | Kind |
|---|---|---|
| controller, action, format, status, redirect, params dropped | `start_processing` / `process_action` / `unpermitted_parameters.action_controller` | official notification |
| callback that halted the chain | `halted_callback.action_controller` | official notification |
| templates, layout, partial count | `render_*.action_view` | official notification |
| INSERT/UPDATE/DELETE per table; BEGIN/SAVEPOINT/RELEASE/ROLLBACK; writes kept vs discarded | `sql.active_record` (savepoint stack), `transaction.active_record` | official notification |
| job enqueue/perform/retry/discard with error | `*.active_job` | official notification |
| WARN+ log lines | `Rails.logger.broadcast_to` | official API (Rails ≥ 7.1) |
| handled error reports | `Rails.error.subscribe` | official API (Rails ≥ 7.0) |
| exception raised in / rescued in app code, re-raised or wrapped later; thread death; join re-raise | `TracePoint(:raise, :rescue, :thread_end)` | core Ruby (`:rescue` needs 3.3) |
| `rescue_from` handled X, by which declaration | prepend `rescue_with_handler` | **monkeypatch** |
| the action method actually ran | prepend `send_action` | **monkeypatch** |
| what the test issued (path, phase, spec line, helper line), final status/body, exception page | prepend `ActionDispatch::Integration::Session#process` | **monkeypatch** |
| every passing/failing expectation: matcher, negation, description, what the actual was (response, body, parsed JSON, status, record, block), whether a body literal matched only printed source | prepend `PositiveExpectationHandler.handle_matcher` / `NegativeExpectationHandler.handle_matcher` | **monkeypatch** (rspec-expectations `@private` API; nothing public publishes passing expectations) |
| actor per request | the controller's `@current_user`, or a `current_user` stubbed by rspec-mocks | instance-variable read |

Two Rails facts shaped the design:

1. `ActionController::Instrumentation#process_action` wraps `ActionController::Rescue#process_action`.
   An exception handled by `rescue_from` therefore **never appears in any notification payload**.
   A prepend is the only way to see it.
2. rspec-expectations publishes nothing for a *passing* expectation. Without the handler prepend,
   "what did this example actually constrain" is unanswerable at runtime. Answering it is what makes
   suppression possible (section 9).

The expectation probe answers that question well: 100 % of fixture suppressions and every sampled
real suppression rested on it. It goes through a single chokepoint that has been stable across
rspec-expectations 3.x.

## 7. Detection rules

`research/green_signal/rules.rb` (v2.1). `rules_v1.rb` is frozen as first run on real code. Every
rule emits observed facts, why it might matter, a confidence, and the example's own assertions. None
says "bug".

A finding is **suppressed** when the example demonstrably asserted the unusual outcome, at two
strengths:

- *outcome asserted*: the redirect target, the exact error status, or the flash. Used for halts and
  `rescue_from`, because the handler *chooses* the target.
- *failure asserted*: a negated `change`, an exact error status, or an alert flash. Used for rollbacks,
  swallowed errors and jobs, because those usually redirect exactly where success does.

Two more suppressions apply: an exception injected by rspec-mocks `and_raise` (detected from the
backtrace), and assertions that quote the exception's class or message. Rollbacks and swallowed errors
are also suppressed when *the application itself* told the user it failed (alert flash or a ≥ 400
status).

| Rule | Fires when (passed examples only) | Confidence |
|---|---|---|
| `GREEN_EXCEPTION_PAGE` | the response the example's body assertions ran against was Rails' exception page; positive checks always, negated ones only if no error status was asserted | HIGH |
| `GREEN_SETUP_REQUEST_FAILED` | a request from a `before`/`let`/helper returned ≥ 400 or was halted, and the example carried on | MEDIUM |
| `GREEN_AUTH_HALT` | a `before_action` halted the request under test | HIGH if anonymous after a sign-in attempt; MEDIUM; LOW if the description says signed-out |
| `GREEN_RESCUED_EXCEPTION` | `rescue_from` handled an exception | HIGH behind 2xx, else MEDIUM |
| `GREEN_ROLLBACK` | a rollback **discarded writes** and the response looked successful | HIGH if no write survived, else MEDIUM |
| `GREEN_ERROR_PAYLOAD` / `GREEN_ERROR_TEMPLATE` / `GREEN_ERROR_TEXT` | 2xx carrying an error object / error template / exception text | HIGH / HIGH / MEDIUM |
| `GREEN_JOB_FAILURE` | `discard_on`, or a perform error a request swallowed | HIGH (retries LOW) |
| `GREEN_THREAD_DIED` | a thread died and was never joined | HIGH |
| `GREEN_EXCEPTION_RENDERED` / `GREEN_EXAMPLE_RESCUED` | exception escaped the controller; middleware answered an unasserted status / the spec rescued it | MEDIUM |
| `GREEN_SWALLOWED_EXCEPTION` | app code rescued and did not re-raise | HIGH for programming errors or logged, else LOW |
| `GREEN_NO_MUTATION`, `GREEN_NO_CONTROLLER`, `GREEN_NO_ASSERTIONS`, `GREEN_LOGGED_ERROR`, `HINT_ACTOR_MISMATCH` | as named | MEDIUM-LOW |

Only MEDIUM and HIGH are shown; LOW and suppressed findings are counted.

## 8. Synthetic results

```text
PASS -- but: Projects PATCH /projects/:id redirects after updating the project
  [MEDIUM] GREEN_SETUP_REQUEST_FAILED  POST /session -> SessionsController#create
      setup request from spec/support/sign_in_helper.rb:6 (body) returned 401
  [HIGH] GREEN_AUTH_HALT  PATCH /projects/1 -> ProjectsController#update
      before_action :authenticate_user! halted the request (authentication); ProjectsController#update never ran
      response: 302 -> /login; actor: anonymous
      an earlier request in this example signed in / set up a user
      asserted: respond with a redirect status code (3xx)

PASS -- but: Status page shows the regional status banner
  [HIGH] GREEN_EXCEPTION_PAGE  GET /status -> StatusController#show
      GET /status answered 400 with Rails' exception page ("Action Controller: Exception caught")
      1 passing body assertion(s) ran against that page: include "All systems operational"
      1 of them match only inside the page's printed source code, not anything the application rendered
      exception: ActionController::ParameterMissing "param is missing ...: region"
```

| Rule set | Misleading flagged (MEDIUM+) | …by the expected rule | Controls with a shown finding | Clean with a shown finding |
|---|---|---|---|---|
| v1, first run (34-example fixture) | 11/13 | 11/13 | **5/13** | 0/8 |
| v1 after splitting suppression strength (same 34) | 12/13 | 12/13 | 2/13 | 0/8 |
| v1 on the final 37-example fixture | 13/14 | 12/14 | 2/14 | 0/9 |
| **v2.1** (calibrated on real code) | **12/14** | 12/14 | **1/14** | **0/9** |

v2.1 still finds 12 of 14. The two it no longer shows: **wrong actor** (#5) was only ever a LOW
description hint, and **wrong route** (#11) was lowered after real suites showed router-404 tests are
nearly always deliberate.

This fixture was written alongside the rules, by the same author. It shows that the facts are
capturable and the rules are mechanically right. It says nothing about real-world yield.

## 9. Control false-positive results

| Control | First run (v1) | Final (v2.1) | Suppressed by |
|---|---|---|---|
| intended auth redirect | quiet | quiet | `redirect_to("/login")` asserted |
| intended error JSON | quiet | quiet | error body asserted |
| intended rollback | **FP** (swallowed `RecordInvalid`) | quiet | negated `change` |
| intended rescue (stubbed) | **FP** (log line) | quiet | `and_raise` origin; the log line names an observed exception |
| intended authorization halt | quiet | quiet | redirect target + alert asserted |
| intended `RecordNotFound` → 404 | quiet | quiet | 404 asserted |
| intended job failure, stubbed | **FP** (log line) | quiet | `and_raise` origin |
| **intended job failure, real data** | **FP** | **FP** | none: asserted via `change { Delivery.where(status: "failed").count }`, which no rule can read as awareness |
| intended routing 404 | **FP** | quiet (LOW) | rule lowered: indistinguishable from the wrong-route case by runtime facts |
| no-op update, not-found page, joined thread, 401, 400 | quiet | quiet | negated `change`; text in the rendered template's source; `Thread#join` re-raise seen; asserted statuses |

Can runtime context suppress false positives deterministically? **Mostly yes, through the
expectation probe.** Asserted status, redirect target, flash, negated `change`, `and_raise` origin,
quoted messages, regex literals, and template source all came from observed expectations, never from
descriptions.

**What it cannot do:** tell "this test is *about* the failure" from "this test passed *despite* the
failure" when the example asserts a downstream effect, as in the real-data job failure. On real code,
that is most of the residue.

## 10. Real-repository results

Two private Rails applications, run unmodified with `rspec -r observer.rb`. App A was run from its
clean working tree. App B was run from a `git archive` export of HEAD against a throwaway database,
because its working tree carries uncommitted changes that load another tool's test observer.

| | App A | App B |
|---|---|---|
| Stack | Rails 8.0, Pundit, Postgres, inline ActiveJob in specs | Rails 8.1, Devise, Postgres |
| Examples (passed / pending / failed) | 2,358 (2,352 / 6 / 0) | 1,869 (1,869 / 0 / 0) |
| Request + controller + integration | 924 (calibration set) | 572 |
| Other (models, services, jobs, system, features, …) | 1,428 (held-out for v2) | 1,297 |
| Controller requests observed | 1,906 | 2,231 |

**How often the raw facts occur in passing examples, before any rule:**

| Fact | App A | App B |
|---|---:|---:|
| example made a controller request | 41.4 % | 39.8 % |
| app code rescued an exception (TracePoint) | **7.0 %** | 3.7 % |
| `unpermitted_parameters` | 0.9 % | **5.1 %** |
| a `before_action` halted | 1.2 % | 5.0 % |
| any rollback inside a request | 1.6 % | 3.9 % |
| `rescue_from` handled an exception | 2.3 % | 2.0 % |
| ERROR/FATAL log line | 2.7 % | 0.7 % |
| exception escaped a controller → Rails exception page | 1.4 % | 0.3 % |
| request reached no controller | 1.1 % | 0.6 % |
| job error event | 0.6 % | 0.3 % |
| **rollback discarded writes** | 0.1 % | 0.3 % |
| **body assertion matched only printed source** | **1 example** | 0 |

**Rule output and manual classification.** A finding counts once per (example, rule). Every
shown finding was classified by reading the spec, controller, callbacks, services, models and routes.

| Set | Rules | Shown examples | Interesting | Ambiguous | Intentional | Wrong fact |
|---|---|---:|---:|---:|---:|---:|
| App A calibration (924) | v1 | 44 (4.8 %), 61 distinct findings | 1 | 1 | 59 findings | 0 |
| App A held-out (1,428) | v1 | 65 (4.6 %), 474 findings | — | — | dominated by 448 swallowed domain exceptions, 431 of them at one designed idempotency site; every rescue site read, all intentional | 0 |
| App A held-out (1,428) | **v2** (frozen before seeing it) | 17 (1.2 %) | **0** | 0 | 17 | 0 |
| App A calibration | v2.1 | 6 (0.6 %) | 1 | 1 | 4 | 0 |
| App A held-out | v2.1 (tuned after the v2 errors above; not independent) | 5 (0.4 %) | 0 | 0 | 5 | 0 |
| **App B, fresh** (1,869) | **v2.1** (frozen) | **12 (0.6 %)** | **1** | 0 | **11** | 0 |
| App B | v1, for comparison | 39 (2.1 %) | ≥ 1 | — | — | — |

Suppression did most of the work. v2.1 suppressed 171 findings on App A's calibration set and 232 on
App B. 137 of App B's were authentication halts whose outcome the example asserted: 84 by
`redirect_to` target, 27 by status 401, 15 by 404, 5 by 410, and 6 other. A random sample of 14 App A suppressions was 14/14 correctly
intentional.

**Every observed fact that was checked was true.** No finding came from a wrong fact. All error was
interpretation: deciding that a true, unusual fact was unintended.

### Calibration: what the real code taught (v1 → v2.1)

| Change | Why (measured) |
|---|---|
| Rollbacks count only if they **discarded successful writes**; failed statements are not writes | v1: 17 App A rollbacks, all intentional, none discarding a write (uniqueness-validation savepoints, `RecordNotUnique` webhook dedupe, a deliberate `ActiveRecord::Rollback`) |
| Swallowed *domain* exceptions → LOW | 570 across both apps at 31 rescue sites, 0 interesting: idempotency, validation-by-exception, job control flow |
| Authentication halt is HIGH only after a sign-in attempt, and needs an anonymous actor | anonymous "rejects unauthenticated" specs are the common case; a signed-in "redirect away from /login" guard is not authentication |
| Negated status assertions and compound `or` matchers parsed; regex literals and Capybara `have_current_path` read | "`not_to have_http_status(:ok)`" and "`redirect or 403`" are how real authorization specs are written |
| Router 404 → LOW | 15 findings in 5 examples, all route-retirement or method-hardening specs |
| Job failure only for `discard_on` or a perform error a request swallowed | an error escaping `perform` reaches whoever performed it; scheduled retries are design |
| Exception page: negated checks pass if the error status was asserted | "`not_to include(token)`" on an asserted 404 is the intent |
| Log lines quoting an observed exception's message are that exception | duplicates of handled payment-provider failures |

## 11. Most interesting real findings

### App A: an assertion satisfied by its own source code (`GREEN_EXCEPTION_PAGE`, HIGH)

A request spec titled roughly *"tells a user who already acknowledged a document that they need not
acknowledge again"*:

1. creates an acknowledged record with a factory trait,
2. GETs the page,
3. asserts `response.body` includes the acknowledgement sentence and does not include the prompt.

What actually ran: a `before_action` called a model method that lazily records which language version
was served. That column is on an *immutable once acknowledged* list, and the factory had acknowledged
the record without ever resolving it. So `update!` raised `ActiveRecord::RecordInvalid`, the action
never ran, and `show_exceptions = :rescuable` rendered Rails' **422 debug page**: 260 KB, 180
"Extracted source" blocks. One of those blocks is the spec file, lines 240–245, which contains
`expect(response.body).to include("<the sentence>")`. With the source blocks removed, the sentence is
absent. The negated check passes because the page HTML-escapes the apostrophe in its own echo.

**Proof:** replacing the sentence's translation at runtime with "THIS COPY WAS DELETED"
(`rspec -r <scratch script>`, repository untouched) leaves the example passing.

**Classification:** **B + C** (misleading test; it exercises a crash path, not the message). Possibly
**A**: the column was added with no backfill four days after acknowledgment shipped, and is now frozen.
Any record acknowledged in that window would get a 422 on revisit. Current code always resolves the
column before acknowledging, so whether this bites depends on production data the spike cannot see.

The fixture's case 14 reproduces the mechanism in a stock Rails 8.0 app with default test settings
(`get "/status"` without its required param; `include("All systems operational")` passes). **It is a
general trap of Rails ≥ 7.1 request specs**, not a quirk of App A.

### App B: a sign-in that never happened (`GREEN_SETUP_REQUEST_FAILED`, MEDIUM)

"Denies reader and author access" signs in a reader, checks the admin page redirects, then calls the
suite's `sign_in(author)` helper (a `POST` to the session endpoint) and checks again.

What ran:

| # | Request | Halted by | Actor |
|---|---|---|---|
| 1 | `POST /sign-in` | — | (signs in reader #202) |
| 2 | `GET /admin/...` | `require_admin` | reader #202 |
| 3 | `POST /sign-in` | **Devise `require_no_authentication`** | — |
| 4 | `GET /admin/...` | `require_admin` | **reader #202** |

**Proof:** with the admin gate mutated to admit authors, the example still passes. With
`delete "/sign-out"` added before the second sign-in, the same mutation fails it, as it should.

**Classification:** **B + D** (misleading test; missing coverage of "authors are denied"). This is
the brief's "test setup accidentally authenticated the wrong actor", found without reading the
description. The evidence is a refused setup request and an actor id that did not change.

### Also worth knowing

- **App A, ambiguous:** a logging-redaction spec for "a normal authenticated route" actually got a
  404 (`RecordNotFound`; the reader could not see that document). The log assertion still holds, but
  the route never served normally.
- **The noise is instructive.** App A's top v1 pattern was an analytics writer that is *designed*
  to swallow duplicate-key validation failures (94 findings, 13 examples). App B's v2.1 residue is
  `Integer("abc")` fallbacks, JSON-parse error mapping, idempotent retries, and a quota race.
  Every one is a rescue the authors meant.

## 12. Existing-tool comparison

| Tool / practice | What it sees | Overlap with this spike |
|---|---|---|
| **rubocop-rspec `RSpec/NoExpectationExample`** | static: examples with no expectation call | covers `GREEN_NO_ASSERTIONS` (statically, with helper-name heuristics). Nothing else |
| **Mutation testing** (`mutant`; commercial licence for private code) | whether tests notice code changes | could expose App B's case (mutate `require_admin`) given a mutation in the right method. It cannot mutate translations or test data, so not App A's. Costs a test run per mutation, and says nothing about *why* a test is weak |
| **Coverage** (SimpleCov line/branch) | which lines ran | sees that the action ran or not, never what was asserted. App A's acknowledgement view simply shows as uncovered among thousands of lines |
| **Rails `show_exceptions = :none` in test** | turns rescuable exceptions back into raised errors | **would have made App A's spec fail.** But Rails 7.1 deliberately made `:rescuable` the default so request specs can assert 404s |
| **Rails `action_on_unpermitted_parameters = :raise`** | unpermitted params raise | would catch fixture case 7; real suites show why apps keep `:log` (path params) |
| **`Capybara.raise_server_errors`** | re-raises unrescued server errors in system specs | unrescued only; not rescued or swallowed ones |
| **Bullet, strict_loading** | runtime N+1 / lazy loading in tests | same "runtime detector in the test process" shape, different question |
| **Error monitoring** (Sentry, Honeybadger, `Rails.error`) | reported errors, usually disabled in test | rspec-rails has no matcher culture around it; the spike subscribes to `Rails.error` |
| **Datadog Test Optimization** (`datadog-ci` + auto-instrumentation) | test results plus APM spans per test | **closest data**: spans for requests, SQL and errors exist per test. Its documentation describes flaky detection, test impact analysis and timing. It does not describe evaluating a *passing* test's spans against what the test asserted, and it needs a SaaS account |
| **CircleCI Test Insights, Buildkite Test Engine, BuildPulse, Trunk** | outcomes, timings, flakiness across runs | none: a consistently green misleading test is invisible to them |
| **Research: rotten green tests** (Delplanque et al., ICSE 2019) | passing tests whose assertions never executed | same family ("green but wrong"), narrower question. Pharo/Java/Python tooling only |
| **Research: checked coverage** (Schuler & Zeller, ICST 2011) | statements whose results reach an oracle (dynamic slicing) | the rigorous version of "did the test check what ran". Too expensive for routine use; no Ruby tooling |
| **AI test review / generation tools** | test source, statically | no runtime evidence, so they would have to guess what App A's page or App B's actor actually were |

**What rspec-signal would produce that developers cannot easily get today:** for a passing example,
*what the application actually did* (halts, rescues, actor, discarded writes, the page actually
served), placed next to *what the example actually asserted*, plus the specific contradictions
between the two. The two real findings needed exactly that pairing: neither is visible from source
alone, from coverage, or from outcomes.

The strongest single rule, "content assertions ran against Rails' exception page", is narrow and
general enough that it may be **better upstreamed** (as an rspec-rails warning) than productized.

## 13. Optional LLM interpretation results

**Setup.** A model (Claude Sonnet, as a blind subagent) read one packet file per run. Each packet
held the example's description, its source with enclosing `let`/`before`/helpers, the expectations
that ran, the normalised runtime evidence, and, in some runs, the deterministic rule output. It saw
no application source and no labels, and was told to read nothing else. Question: *"Does the
observed execution appear consistent with what this test is trying to establish?"* Packets run
250–700 tokens per example; the whole App A set was about 45k tokens. Packet builder: `research/green_signal/llm/packets.rb`.

| Packets | Examples | Truly suspicious → SUSPICIOUS | Intentional/clean → SUSPICIOUS | UNCLEAR |
|---|---|---:|---:|---:|
| Fixture, evidence + rules | 37 | **14/14** | **0/23** | 0 |
| Fixture, evidence only | 37 | **14/14** | **0/23** | 0 |
| App A, evidence + rules (all 63 examples any rule version showed) | 63 | **1/1** | **0/61** | 3 (the ambiguous one + 2 intentional) |
| App A, evidence only | 63 | **1/1** | **0/61** | 2 (+ the ambiguous one called SUSPICIOUS) |
| App B, evidence + rules (v2.1 shown) | 12 | **1/1** | **0/11** | 0 |

What this says:

- **As a second-stage filter it removes nearly all the noise the rules cannot.** On App A it
  dismissed every intentional pattern correctly from evidence plus source alone, including the
  idempotent analytics writer, the webhook dedupe, the failure-corpus jobs and the route retirements.
  That is the job the v1 → v2.1 calibration did by hand.
- **It catches what rules cannot:** fixture wrong actor (#5) and wrong route (#11) were judged
  correctly from the description and source.
- **It depends on the deterministic evidence, not the other way round.** Every SUSPICIOUS verdict
  cited a fact only the observer could supply: "the second sign-in was halted", "422 exception page",
  "thread died", "rollback". No packet, no judgment.
- Its UNCLEARs on intentional App A examples (2 in each condition) were the documented fallback whose
  explaining comment it could not see. That is a fair call.

Caveats: one model, one run per condition. The prompt's examples of "suspicious" (wrong user,
error page, action never ran) overlap the fixture's categories. The real sets contain only examples
some rule already showed, so this measures precision as a filter, not recall over a whole suite.

## 14. Performance measurements

App A, request + controller + integration subset (924 examples), alternating baseline and
instrumented runs on the same machine (`research/green_signal/bench.sh`). Both include the app's own
SimpleCov, JUnit formatter and rspec-signal 0.2.0.

| Pair | Order | Baseline (RSpec "Finished in") | Instrumented | Δ time | Peak RSS |
|---|---|---:|---:|---:|---|
| 1 | baseline first | 155.9 s | 165.6 s | +6.2 % | 396 → 472 MB |
| 2 | baseline first | 157.2 s | 170.8 s | +8.7 % | 399 → 474 MB |
| 3 | baseline first | 178.1 s | 197.8 s | +11.1 % | 398 → 474 MB |
| 4 | instrumented first | 160.1 s | 173.7 s | +8.5 % | 399 → 470 MB |
| 5 | instrumented first | 159.2 s | 173.0 s | +8.7 % | 403 → 471 MB |
| **median** | | | | **+8.7 % (~+14 s on 924 examples)** | **~+72 MB (+18 %)** |

This WSL machine drifts (one later baseline took 232 s), so only adjacent pairs are compared, in
both orders.

Largest cost, from the observer's own counters on the full App A run (2,358 examples, 399 s):

| Component | ms | Share of observer time |
|---|---:|---:|
| `sql.active_record` subscriber | 1,992 | 42 % |
| expectation probe (mostly `matcher.description`) | 1,423 | 30 % |
| controller notifications + body/flash/actor | 751 | 16 % |
| TracePoint (`raise`/`rescue`/`thread_end`) | 181 | 4 % |
| JSON serialization | 156 | 3 % |
| integration probe (caller locations) | 106 | 2 % |
| render / job | 109 | 2 % |
| **total in observer callbacks** | **4,719** | **1.2 % of suite time** |

So the callbacks account for only about 1.2 points of the ~9 % measured. Where the rest goes:

- **It is concentrated, not spread.** Per-test JUnit timings for one pair show 12 of 924 examples
  carrying 12.7 s of the 13.2 s difference, each a jump of +1–2.4 s.
- **It is mostly garbage collection.** Allocations rose 9 % (84 M → 92 M objects), GC time rose from
  13.4 s to 16.3–17.1 s, and major GCs from 25 to 31. A per-example GC log shows the slowest examples
  absorbing 0.7–1.9 s of GC each.
- On a 147-example subset with five configurations interleaved and rotated (`results/overhead_ablation_interleaved.txt`),
  the observer's overhead was **within noise** (median 32.8 s vs 32.8 s), and disabling TracePoint,
  the expectation probe or SQL accounting changed nothing measurable.

The cost to remove first is therefore allocation (retained response bodies and exception-page text,
payload copies, `caller_locations`), not any one hook. A production version should keep facts
smaller, rather than drop a source.

App B's full suite reported 4.0 s of observer time over 203 s (2.0 %), again led by SQL (2.3 s).
The subscriber cost is dominated by `ActiveSupport::Notifications` dispatch and SQL classification on
every statement. Counting only writes and transaction statements would cut most of it.

## 15. Technical risks

- **Four prepends on non-public API**: `rescue_with_handler` and `send_action` (Rails),
  `Integration::Session#process` (Rails), and `handle_matcher` (rspec-expectations, marked `@private`).
  All are small and stable today, but each is a compatibility promise.
- **The best rules are Rails-only, and one is Rails ≥ 7.1-only** (`:rescuable` exception pages).
  Without Rails, only thread deaths and swallowed exceptions remain, and swallowed exceptions are the
  noisiest signal there is.
- **TracePoint `:rescue` needs Ruby 3.3**; rspec-signal supports 2.7.
- **Actor detection relies on `@current_user`** (or an rspec-mocks stub). Token-authenticated API
  controllers read as "unknown": App B's API specs did.
- **Attribution across threads is global.** Puma threads in system specs worked. A background thread
  outliving its example would be charged to the next one.
- **Evidence is sensitive.** Flash text, log lines, exception messages and request paths must go
  through the Redactor before any artifact is written.
- **Overfitting.** v2.1 was tuned on App A, including after its held-out errors. App B is the only
  clean evaluation, and it contains one positive.
- **Recall on real code is unknown.** There is no ground truth for what the rules missed. The LLM
  only ever saw rule-selected examples.
- **Matcher descriptions** are computed for every passing expectation. A custom matcher whose
  `description` has side effects would be affected; none was seen.

## 16. Product differentiation

- **Differentiated:** pairing per-example runtime facts with the example's own passing expectations.
  No mainstream Ruby tool does this. The nearest (Datadog's in-test APM spans) collects similar data
  but does not, as documented, judge a green test against it. Static linters and AI reviewers cannot
  see the runtime facts that made both real findings obvious.
- **Natural home:** rspec-signal already owns "a compact report an agent reads after a run". "Three
  passing examples did not test what they say" fits that report, deterministic and bounded.
- **Not differentiated:** zero-assertion detection (rubocop-rspec); routing/404 and unpermitted-params
  hygiene (Rails config); swallowed exceptions in general (error trackers, and mostly intentional
  anyway).
- **The honest shape:** a small number of high-precision runtime rules plus an optional model pass.
  It is not a broad "suspicious behaviour" detector. The broad version was measured, and it is noise.

## 17. Decision: **WEAK GO**

| STRONG GO criterion | Result |
|---|---|
| several objectively suspicious green cases detected | synthetic: 12/14 shown, 14/14 with the model. Real: **2 proven misleading tests** in ~4,200 passing examples |
| low false-positive rate for the strongest rules | **yes for the two that found things** (0 false positives each). **No** for the rule set overall: 1 of 12 shown examples on the fresh repository was interesting |
| at least one meaningful real-world misleading test | **yes, two, each verified by mutation** |
| acceptable runtime overhead | **yes for an opt-in or CI-only mode** (~9 %, ~+72 MB, mostly GC); not free enough to be always on |
| clear differentiation | **yes**, for the pairing of runtime facts and assertions |

Not STRONG GO because the evidence for precision rests on one fresh repository with one positive,
and the rules were shaped by the very suite that produced the other positive. Not NO-GO because
nothing that would kill the idea held true. Rails exposes enough, reliably. The instrumentation is
light. Expectation semantics *are* observable, through one prepend. Intentional behaviour dominates
the raw facts, but it can be filtered, deterministically for most of it and with a model for the rest.

## 18. Smallest next step (the bounded experiment)

Before any product work:

1. **Freeze** `observer.rb` + `rules.rb` v2.1 and the packet builder. No rule edits during the run.
2. Run them on **three or more Rails suites not yet seen**, ideally one using Devise with system specs,
   one API-only, and one with Pundit/CanCan, with as little manual tuning as possible.
3. Measure, per suite: shown findings per 1,000 passing examples, verified misleading tests (with a
   mutation proof as here), and model-filter agreement.
4. **STRONG GO if**: at least one verified misleading test in at least two of the three suites, at
   most 5 shown findings per 1,000 examples after the model pass, and no rule with more than 50 %
   intentional findings among the rules kept.

If that passes, the smallest implementation inside rspec-signal is:

- an **opt-in, experimental** `config.green_signal = true` (off by default, like `causal_analysis`),
  installing the observer only for request/system specs on Rails ≥ 7.1 / Ruby ≥ 3.3;
- **four rules only**: `GREEN_EXCEPTION_PAGE`, `GREEN_SETUP_REQUEST_FAILED` (with the
  sign-in-attempt halt), rollback-that-discarded-writes behind success, and `rescue_from` behind an
  asserted 2xx. All are deterministic, and each carries its evidence and the example's rerun id;
- a bounded **"Passing, but"** section in `signal.md` (at most 5 entries) and an `experimental` block
  in `signal.json`, written only when there is something to say;
- the model pass as a separate, optional command over the JSON, never in the default path.

Separately, and cheaply: propose the exception-page check to rspec-rails, or document it. It is a
general Rails ≥ 7.1 trap that needs nothing from rspec-signal.

## 19. What would have killed it

Recorded for completeness, since NO-GO was not chosen. Any of these would have:

- `rescue_from` or passing expectations being unobservable without invasive patching. Each needed
  exactly one method prepend.
- Wrong facts: a halt attributed to the wrong request, an actor misread. None were found.
- Overhead above ~25 %.
- Zero verifiable real-world misleading tests. There were two.

---

## Reproduction

```bash
# Synthetic fixture
cd research/green_signal/fixture
bundle install --local
bundle exec rspec -r ../observer.rb
ruby ../analyze.rb tmp/green_signal/facts.jsonl --root . --truth truth.rb --low --suppressed

# Any Rails app, unmodified
cd /path/to/app
GREEN_SIGNAL_OUT=/tmp/facts.jsonl bundle exec rspec -r /abs/path/research/green_signal/observer.rb
ruby /abs/path/research/green_signal/analyze.rb /tmp/facts.jsonl --root . [--rules v1]

# LLM packets (evidence + rules, or --no-rules)
ruby research/green_signal/llm/packets.rb /tmp/facts.jsonl --root /path/to/app > packets.md

# Overhead
research/green_signal/bench.sh /path/to/app /tmp/bench 3 -- spec/requests
```

Files: `observer.rb` (instrumentation), `rules.rb` (v2.1), `rules_v1.rb` (frozen), `analyze.rb` (report
and scoring), `llm/packets.rb`, `bench.sh`, `fixture/` (app, 37 specs, `truth.rb`, `report_v21.txt`),
`llm/out/` (fixture packets and both sets of model judgments), `results/` (overhead runs and observer
cost counters). App A and App B facts, packets and judgments are not committed: those repositories
are private.
