# PR triage watch bot (se-pr-triage)
> Ticket: NO_TICKET  ·  Status: active

## Problem / Why

After `se-pr` opens a PR, two streams of feedback arrive asynchronously and update on every push: review comments (CodeRabbit and human reviewers) and CI status (Playwright e2e, Cycode, lint/type/unit, SonarCloud, PR-title validation, changeset, preview deploy). Today the author hand-scripts the whole babysit loop per PR — collect, decide, fix, push, reply, watch CI — costing many turns and risking premature or unapproved replies. `se-pr-triage` packages it into one repeatable, loop-safe round: review-comment decisions and fixes are approved first, exact post-fix replies are approved separately, and CI failures are investigated and resolved autonomously.

## Goals

- One command processes a PR's current review comments **and** CI failures in a single round.
- Review comments (bot and human) use two separate human gates: approve or steer the decisions and fixes first, then approve the exact final replies after fixes are pushed.
- CI failures are investigated and fixed or rerun autonomously, with no replies.
- Every code fix clears the same verification and review bar as a normal build task.
- Safe to re-run under `/loop` — never double-replies, double-fixes, or re-acts on a settled signal.

## Non-goals (out of scope)

- A built-in continuous watch / internal polling loop (watching comes from wrapping single rounds in `/loop`).
- Replying to status or CI bot comments — they are never replied to.
- Acting on purely informational status (changeset present, preview URL, green checks) — ignored.
- Free-floating PR conversation (issue) comments from humans.
- Changing spec-defined behavior to satisfy a reviewer (that is a separate `se-discuss` amendment).
- Creating Jira tickets or other external follow-up artifacts for deferred items.
- Auto-resolving comment threads.

## Behavior / Requirements

**Invocation & target**
1. `se-pr-triage` is a user-invokable entrypoint — the fourth, alongside `se-discuss` / `se-plan` / `se-exec`. The human runs it after reviewers, bots, or CI have reported.
2. It auto-detects the open PR for the current branch. An optional PR-number argument overrides detection. If no open PR is found and none is given, it reports that and exits.
3. It is not auto-chained from `se-pr`.

**Round model**
4. Each invocation performs exactly one triage round, then exits. Continuous watching is achieved by the user wrapping it in `/loop`.
5. A round runs two independent tracks — **Track A (review comments)** and **Track B (CI failures)** — and reports on both. Either track may be empty.
6. Loop-safety: each track derives its handled/unhandled state live from the PR and its checks every round — there is no local processed-list. A round with nothing actionable in either track exits immediately.

**Track A — review comments**
7. In scope: unresolved inline code-review comment threads and top-level review summaries, from any author (bot or human), that have no reply from us yet. Status/CI bot comments and free-floating human conversation are not Track-A comments.
8. Each in-scope comment is assigned exactly one **triage decision**:
   - **Fix** — valid; the code should change.
   - **Decline** — invalid, or needless complexity for an unreachable/impossible case; the reply explains why, no code change.
   - **Answer** — a human question or discussion point; reply only, no code change.
   - **Defer** — valid but out of scope for this PR; the reply acknowledges it as a separate follow-up. No ticket or file is created.
9. Realism rule: bots do not know the full data flow or whether end-users can reach a path. A comment that adds needless complexity for an impossible case is Declined, not fixed.
10. Spec authority: a comment requesting behavior that contradicts the committed spec defaults to **Decline**, citing the spec. The skill never silently changes spec-defined behavior. The human may override the decision at Gate 1.
11. **Decision approval gate (mandatory):** after triage, every Track-A item is presented together with the original comment, its proposed triage decision and rationale, and a short fix summary for Fix items. The rationale is internal analysis for the human, not message copy addressed to the reviewer. During triage and Gate 1, the controller must not draft, generate, suggest, outline, or present any reply body — provisional, sample, or final — for any decision. The human approves or steers the decisions and Fix scope in one shot. Gate-1 approval authorizes only the approved Fix work; it never authorizes a PR reply. No Track-A fix is pushed before this gate is explicitly approved. There is no auto-approve mode, even under `/loop`.
12. After Gate 1, each approved Fix uses explicit `standalone-triage` `/se-verify` and `/se-review` with PR-comment acceptance inputs, changed paths, and immutable identity; it does not use active-increment artifacts or normal build loops. It then follows **fix flow**: fix → verify → review → commit → push. If the actual fix must materially differ from the approved fix summary, that item returns to Gate 1 before commit or push. A Fix that cannot be made green, reviewed clean, or confirmed pushed is aborted: no reply candidate is created, the thread is left untouched, and the item is reported as needing human attention. Other items still complete.
13. **Final reply approval gate (mandatory):** reply composition begins only here, after the step-12 Fix phase has completed and all successful Fix commits are confirmed pushed. If the round has no Fix items, step 12 is a no-op after Gate 1; reply text is still not composed during initial triage. Every postable Track-A item is then presented together with its exact target comment or review, final triage decision, and exact final reply text. A Fix reply includes the actual result and pushed commit SHA or URL; placeholders and provisional wording are forbidden. The human approves, edits, or skips each reply. Gate-2 approval is independent of Gate 1. No reply is posted until this exact final batch is explicitly approved, including rounds with no Fix items. There is no auto-approve mode, even under `/loop`.
14. After Gate 2, each approved target is revalidated immediately before posting; if it is no longer unresolved/in-scope or already has a reply from us, it is skipped untouched and reported. Every still-valid approved reply is posted to the approved target with the exact approved text. Any target or text change after approval invalidates Gate 2 and requires the changed batch to be presented again. Skipped replies and aborted Fixes remain untouched and may resurface in a later stateless round; threads are never auto-resolved. The reviewer or bot resolves once satisfied.

**Track B — CI failures (autonomous)**
15. Track B is the source of truth on CI: it reads check runs / workflow job conclusions directly to find which jobs failed. For a failed job it consults that job's mirror status comment (e.g. the Playwright report, PR-title validation) for the human-readable reason, and reads the raw failure log only when the comment lacks enough detail.
16. Passing or purely informational signals (green checks, changeset present, preview URL) are ignored.
17. Track B acts **autonomously** — no approval gate and no PR reply. It escalates to the human only when the situation is unusual **and**, after investigation, the agent is unsure what to do; the escalation is surfaced in the round report as needing human attention.
18. For a failing **test** job, the agent runs the failing test(s) locally:
    - Passes locally → treat as **flaky** → rerun the CI job **once**. Still red while local passes → escalate.
    - Fails locally → **real failure** → fix the code through `standalone-triage` verification/review with CI acceptance inputs, then commit → push (CI re-runs). Cannot be made green → escalate.
    - Cannot run locally (environment unavailable) → escalate rather than guess.
19. For a **non-test** CI failure, the agent fixes it at the source, autonomously, then pushes (CI re-runs): lint / type-check / unit failures → fix the code; PR-title validation → correct the PR title; SonarCloud quality gate → fix the flagged issues; Cycode (secrets / SAST / vulnerable-deps) → fix when the remedy is clear, escalate when ambiguous or when resolution requires a human action such as rotating a credential.
20. Track B never posts a reply; the resolution is a green check, not a comment.

**End-of-round report**
21. When the round finishes the skill reports both tracks: per review comment — its triage decision, Fix result, reply action (posted / skipped at Gate 2 / withheld after live-state revalidation / non-postable because Fix aborted), and links to any posted reply and pushed commit; per CI failure — the verdict (flaky-rerun / fixed / escalated) and links to the job and any pushed commit; the count of items skipped as already-handled; and every item escalated or aborted as needing human attention.

## Domain terms

- **Triage round** — one full invocation of `se-pr-triage`: read → triage → Gate 1 decisions/fixes → fix/verify/review/commit/push → Gate 2 exact replies → post → report, then exit.
- **Track A / review comments** — inline review threads and review summaries that need a triage decision and a reply.
- **Track B / CI failures** — failing check runs / jobs that the bot investigates and resolves autonomously, without replies.
- **Triage decision** — the Track-A decision assigned to a comment: Fix | Decline | Answer | Defer.
- **Decision approval gate / Gate 1** — human approval or steering of comment decisions and Fix scope; it authorizes Fix execution only, never replies.
- **Final reply approval gate / Gate 2** — post-fix approval of each exact reply target and body after real results and commit references are known.
- **Fix flow** — for a Track-A Fix: fix → verify → review → commit → push; only then can an exact reply enter Gate 2.
- **Flaky verdict** — a failing test that passes when run locally; resolved by rerunning the CI job once, not by a code change.
- **Realism rule** — bots lack full data-flow / reachability knowledge; do not fix comments that add needless complexity for impossible cases.
- **In-scope comment** — an unresolved inline review thread or a top-level review summary, from any author, with no reply from us yet.

## Decisions

- **Single round + `/loop` over a built-in watch loop** — keeps the skill stateless and composable; the existing `/loop` skill provides watching. Trade-off: no autonomous background watch.
- **Two Track-A gates with different authority** — Gate 1 approves decisions and Fix scope only; Gate 2 separately approves the exact final replies after fixes are pushed. Trade-off: every comment round requires a second human interaction, but no provisional or post-fix-rewritten reply can be posted under an earlier decision approval.
- **Two tracks with different authority** — review-comment decisions, fixes, and replies are human-gated; CI failures are resolved autonomously. Trade-off: the CI track pushes code with no human gate, bounded by the same verify/review loops as a build task and by the escalate-when-unsure valve.
- **Loop-safety from live PR and CI state** — idempotent by construction, no local processed-list. Trade-off: a comment edited after we already replied is not re-processed.
- **Read CI directly, use the status comment for the "why", read the log only if needed** — authoritative and covers check-only signals like Cycode, while avoiding raw-log digging when a comment already summarizes the failure.
- **Flaky → rerun once → escalate** — one rerun distinguishes flakiness from a stuck job without masking a real failure.
- **Status/informational comments ignored; CI/status bots never replied to** — resolution for CI is a green check, not a thread reply.
- **Defer creates no external artifact (reply only)** — keeps the skill focused; follow-up tracking is the human's call.
