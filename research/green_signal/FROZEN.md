# Frozen detector for the out-of-sample validation run

Frozen 2026-10-03, before any unseen repository was opened. `FROZEN.sha256` holds the hashes;
`sha256sum -c research/green_signal/FROZEN.sha256` (run from `research/green_signal/`) proves the
files used for the validation are these files.

Nothing below may change during the run: no rule added, removed, re-thresholded or special-cased,
no prompt edited. A rule that performs badly is recorded, not fixed.

## Procedure, per app

1. **Baseline.** Run the chosen spec subset without the observer. Only a green baseline counts;
   examples that fail or are pending are excluded from analysis and reported.
2. **Observe.** `GREEN_SIGNAL_OUT=<facts> bundle exec rspec -r observer.rb <subset>` with the app
   unmodified (or a throwaway export of it).
3. **Rules.** `ruby analyze.rb <facts> --root <app> --json <findings>` (rules v2.1, the default).
   *Shown* = MEDIUM or HIGH and not suppressed. A finding is counted once per (example, rule).
4. **Model pass.** Packets (`llm/packets.rb --ids`, rule output included) for every example with a
   shown finding, judged once by Claude Sonnet as a blind subagent with `llm/judge_prompt.md`
   verbatim. SUSPICIOUS = keep, UNCLEAR = keep as uncertain, CONSISTENT = suppress.
5. **Manual classification** of every shown finding when an app has at most 30; otherwise every HIGH
   finding plus a seeded random sample of the rest. Classes: VERIFIED MISLEADING TEST, PROBABLE
   MISLEADING TEST, INTERESTING, INTENTIONAL, FALSE POSITIVE.
6. **Mutation proof** for every candidate misleading test, applied only at runtime
   (`rspec -r <scratch script>`) or in a throwaway export; nothing in an app is changed.
7. **Overhead** on at least two apps: paired baseline/observed runs in both orders.
