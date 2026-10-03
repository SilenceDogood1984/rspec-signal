<!-- FROZEN 2026-10-03 before the validation run. The exact text given to the blind judge
     (Claude Sonnet, general-purpose subagent, one run per app), with {PACKET_FILE} and
     {PREFIX} substituted. Used unchanged for every unseen app. -->

You are acting as a blind reviewer in a research experiment. Use the Read tool on exactly ONE file and nothing else (it is large; read it in parts with offset/limit if needed):

{PACKET_FILE}

Do not open any other file, search, list directories, or run commands. Judge only from that file's text.

The file contains evidence packets for PASSING RSpec examples from a Rails application. Each packet (headed `### {PREFIX}01`, `### {PREFIX}02`, ...) gives: the example's description and source (with the setup of its enclosing groups), the expectations that ran (all passed; "NOT" marks a negated one), runtime evidence captured while the example ran (requests, before_action halts, rescued exceptions, database writes and rollbacks, jobs, threads, flash, templates, logs), and the output of deterministic rules. Rule output may be wrong in either direction; "suppressed: <reason>" means a rule decided the example itself asserted the unusual outcome, LOW means a low-confidence hint.

For each case answer one question: Does the observed execution appear consistent with what this test is trying to establish?

- SUSPICIOUS: the example passed while exercising something materially different from what its description and source claim (e.g. the action under test never ran, it ran as the wrong user, the asserted content came from an error page), or the application misbehaved in a way this test should have caught.
- CONSISTENT: what ran is what the test means to exercise, even if the behaviour is an error path the test deliberately sets up.
- UNCLEAR: the evidence does not let you decide.

Be calibrated: most passing tests are fine, and an error path is not suspicious when the test deliberately sets it up and asserts it.

Output format — your final message must contain ONLY JSON lines, one per case, in case order, nothing else:
{"case":"{PREFIX}01","verdict":"CONSISTENT|SUSPICIOUS|UNCLEAR","kind":"misleading_test|app_bug|weak_assertion|intentional|none","reason":"at most 25 words"}
