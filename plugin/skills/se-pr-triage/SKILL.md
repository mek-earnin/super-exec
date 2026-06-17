---
name: se-pr-triage
description: Use after se-pr has opened a PR and reviewers or CI have reported — runs one loop-safe triage round over two independent tracks (Track A: review comments gated by human approval; Track B: CI failures resolved autonomously) then exits. Triggers on "triage the PR", "handle review comments", "fix CI", or any post-PR babysitting request. The fourth user-invokable super-exec entrypoint; invoke manually after reviewers or CI have reported, not automatically from se-pr.
---

# se-pr-triage — Post-PR Triage Orchestrator

se-pr-triage is the **controller for one triage round** after a PR is open and feedback has arrived. It processes two independent tracks in a single invocation: **Track A** (review comments — inline threads and review summaries) is triaged, presented to the human for batch approval, and then executed; **Track B** (CI failures) is investigated and resolved autonomously, with no approval gate and no PR replies. When the round finishes the skill reports on both tracks and exits. Continuous watching is achieved by wrapping invocations in `/loop` — there is no built-in polling.

The controller stays lean. It delegates all MCP calls, git operations, and heavy execution to subagents dispatched with the `Task` tool, following the tier discipline in the `se-subagent` skill. Nothing substantial — no MCP reads, no `gh` commands, no `git` inline — runs in the controller context.

se-pr-triage is **not** auto-chained from se-pr. The human runs it explicitly, after reviewers or CI have had a chance to report.

---

## Session activation (do this FIRST)

Invoking this skill — typed `/se-pr-triage` or model auto-invoked for post-PR triage — means a triage session is starting. As the very first action, **write the session marker** `.super-exec/active` in the repo root (create `.super-exec/` if needed), e.g. `phase: pr-triage` and `started: <current UTC ISO-8601>`. This makes the enforcement guards live. Existence + mtime are what the hooks read; the stale-marker decision is a model-judged heuristic with no fixed TTL. **Do not commit it** — `.super-exec/` is gitignored. Clear `.super-exec/active` at the very end of the round, after the report is delivered.

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder steps. Do not advance past a step until it is confirmed done.

- [ ] **1. Detect the target PR.** The skill accepts an optional PR-number argument (e.g. `/se-pr-triage 42`). If a PR number is given, use it. Otherwise, auto-detect the open PR for the current branch via the GitHub MCP (`list_pull_requests` filtered to the current branch head, state: open) or `gh pr view` as a fallback. If no open PR is found and none was given, report that to the human and exit. Clear `.super-exec/active` before exiting.

- [ ] **2. Read triage state (state reader subagent).** Dispatch a **finder/runner subagent (cheap tier — see the `se-subagent` skill)** using the `Task` tool to gather the full triage snapshot. The state reader must use the **GitHub MCP as the primary access path** and fall back to `gh` only when MCP is unavailable. If neither MCP nor `gh` is available, report the access failure to the human and exit (clear `.super-exec/active` first).

  The state reader calls the following GitHub MCP methods on `pull_request_read` (plus the standalone `get_me` tool for identity):

  - `get` — PR metadata and current head SHA.
  - `get_review_comments` — inline review threads; each thread carries `isResolved` and `isOutdated` flags, and the list of comments within it (used to detect whether we have already replied).
  - `get_reviews` — top-level review summaries (approve / request-changes / comment bodies).
  - `get_comments` — top-level issue/PR comments (status bot comments, which serve as the human-readable "why" for CI failures).
  - `get_check_runs` + `get_status` — CI signals: which jobs passed, failed, or are pending.
  - `get_me` (standalone top-level MCP tool, no params) — our own identity (login), so "a reply from us" can be detected reliably in `get_review_comments` results. This is not a `pull_request_read` sub-method; it is called directly at the top level.

  The state reader also notes which MCP methods are available so the controller knows whether to use `add_reply_to_pull_request_comment` (in-thread reply) for Track A execution.

  The state reader returns a structured snapshot — thread list, CI check list, our identity — and nothing else. Raw API payloads do not cross back into the controller.

- [ ] **3. Determine what is actionable in each track.** The controller reads the snapshot and classifies items:

  - **Track A in-scope:** an unresolved inline review thread OR a top-level review summary, from any author (bot or human), that has no reply from us yet. Resolved threads, outdated threads, status/CI bot comments, and free-floating PR conversation (issue) comments are out of scope and counted as skipped.
  - **Track B in-scope:** check runs or status checks with a failing conclusion. Passing checks and purely informational signals (changeset present, preview URL, green checks) are ignored. Track B detail — the CI investigation and resolution procedure — is fully described in [`ci-triage.md`](./ci-triage.md); the controller delegates Track B execution to a subagent following that document.

  If both tracks are empty (nothing actionable), report that and exit immediately. Clear `.super-exec/active` before exiting.

- [ ] **4. Triage Track A items.** For each in-scope Track A item, the controller assigns exactly one decision:

  - **Fix** — the comment identifies a valid defect; the code should change.
  - **Decline** — the comment is invalid, out of scope, or requests needless complexity for a case the code cannot actually reach. The reply explains why; no code change.
  - **Answer** — a human question or discussion point that warrants a reply but no code change.
  - **Defer** — a valid suggestion that is out of scope for this PR; the reply acknowledges it as a future follow-up. No ticket or file is created.

  Two standing rules apply to every triage decision:

  - **Realism rule.** Bots do not know the full data flow or whether an end user can reach a given path. A comment that adds defensive complexity for a case the system cannot receive is a Decline, not a Fix.
  - **Spec authority.** A comment requesting behavior that contradicts the committed spec defaults to Decline, with a citation of the relevant spec section. The skill never silently changes spec-defined behavior. The human may override the decision at the approval gate.

  For each Fix, the controller also drafts a short summary of what the fix will change (one to two sentences), which the human reviews at the gate. For each item of any decision, the controller drafts the exact reply text to be posted in-thread.

- [ ] **5. Mandatory batch approval gate (Track A only).** Present ALL Track A items together in a single prompt to the human before posting any reply or pushing any fix. For each item the presentation includes: the original comment, the triage decision, the draft reply text, and — for Fix items — the short fix summary. The human approves or edits in one shot; they may change reply text, change a decision, or both. **No reply is posted and no Track A fix is pushed until this gate is explicitly approved.** There is no auto-approve mode, even when se-pr-triage is wrapped in `/loop`.

- [ ] **6. Execute Track A after approval.** Process each Track A item using the approved decisions and reply text:

  - **Fix items:** dispatch an **implementer subagent (mid tier, pinned to `sonnet` on Claude Code)** using the `Task` tool to make the code change. Then clear the **inner verification loop** by invoking `se-verify`, and the **outer review loop** by invoking `se-review`, exactly as a normal build task in se-exec. Once the work is inner-loop-green and outer-loop-clean, commit via `se-commit` (pass the explicit list of files the implementer touched — se-commit owns staging isolation and the message). Push the commit. Only after the commit is pushed, post the approved reply: for an inline review-comment thread, reply in-thread via the GitHub MCP `add_reply_to_pull_request_comment`; for a top-level review summary (which has no inline `commentId`), post a top-level PR comment via `add_issue_comment` referencing the review and the pushed commit SHA or URL.

    If a Fix cannot be made green — the inner/outer loops remain red after the fixer's attempts — abort that item: do not push, do not post a reply, leave the thread untouched, and flag it in the round report as needing human attention. The remaining approved items still complete.

  - **Decline / Answer / Defer items:** dispatch a **runner subagent (cheap tier)** using the `Task` tool to post the approved reply. For an inline review-comment thread, post in-thread via the GitHub MCP `add_reply_to_pull_request_comment`; for a top-level review summary, post a top-level PR comment via `add_issue_comment` referencing the review. No code change. Do not auto-resolve the thread; the reviewer or bot resolves once satisfied.

- [ ] **7. Execute Track B (autonomous, parallel with Track A execution).** Dispatch a **runner/implementer subagent** using the `Task` tool to work through every in-scope CI failure following the full procedure in [`ci-triage.md`](./ci-triage.md). In summary: Track B reads check runs and maps each failure to its mirror status comment for the human-readable reason, reads the raw failure log only when the comment lacks enough detail, and resolves per signal type — flaky tests are rerun once, real failures are fixed through the same se-verify + se-review loops and pushed, non-test failures (lint, type-check, PR-title, SonarCloud, Cycode) are fixed at the source. Track B never posts a PR reply; the resolution is a green check. It escalates to the round report — and only to the round report — when the situation is unusual and the agent is unsure what to do.

  Track A execution (step 6) and Track B execution (step 7) are independent. They may run in parallel if no file overlap exists between Track A fixes and Track B fixes; otherwise run sequentially. When in doubt, run sequentially.

- [ ] **8. End-of-round report.** After both tracks complete, report on the full round:

  - **Track A:** for each in-scope comment — triage decision, action taken (reply posted / fix pushed / aborted), link to the posted reply, and link to any pushed commit. For each aborted Fix — flagged as needing human attention.
  - **Track B:** for each in-scope CI failure — verdict (flaky-rerun / fixed / escalated), link to the check run, and link to any pushed commit.
  - **Skipped items:** count of items in both tracks that were already-handled (resolved threads, passing checks, informational signals).
  - **Escalations and aborts:** every item flagged as needing human attention, listed together at the end.

- [ ] **9. Clear `.super-exec/active`.** Delete `.super-exec/active`. This is the final act of the round. Do not leave the marker set after the report is delivered.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "I'll post the reply now and show the human later." | Post a Track A reply or push a Track A fix before the batch approval gate. | The gate is mandatory. Present every Track A item together, wait for explicit human approval, then execute. No reply is ever posted before approval. |
| "Auto-PR is off so I'll just skip `/loop` — it's a one-off." | Run MCP calls or `gh` commands inline in the controller to save a hop. | The controller never runs MCP or `gh` inline. All reads and mutations are dispatched to subagents via the `Task` tool. |
| "The bot is wrong but it's a CI bot — I'll reply to explain." | Post a reply on a status/CI bot comment or any Track B item. | Track B never posts replies. The resolution is a green check. If escalation is needed, it goes in the round report only. |
| "I'll fix the spec to satisfy the reviewer — it's a small change." | Silently change spec-defined behavior to satisfy a review comment. | A comment contradicting the committed spec defaults to Decline + cite the spec. Only the human can override. If the spec genuinely needs amendment, that is a separate se-discuss session. |
| "I'll auto-approve under `/loop` to keep the round moving." | Skip or bypass the Track A approval gate in loop mode. | There is no auto-approve mode. Every triage round that has Track A items must present the batch gate and wait for a human, even when wrapped in `/loop`. |
| "Never reply or push a Track A fix without an approved draft." | Post a reply or push code for a Track A item before the human has approved the batch. | Write the draft, present the full batch, wait for approval. This rule has no exceptions. |
| "The fix looks clean — I'll push it and post the reply at the same time." | Post the reply before the commit is confirmed pushed. | Triage flow is: fix → commit → push → then reply. The reply references the pushed commit. The order is strict. |
| "I'll silently rerun the CI job to clear a flaky failure." | Rerun a CI job without surfacing it in the round report. | All Track B verdicts — including flaky-rerun — appear in the end-of-round report with links. Nothing is silently handled. |
| "I'll leave `.super-exec/active` set — someone else will clear it." | Complete the round without clearing `.super-exec/active`. | Step 9 is mandatory: clear `.super-exec/active` as the final act. Leaving it set keeps guards armed on a dead session. |

---

## Model and Tool Assignments

Resolve all concrete model IDs and dispatch details from the `se-subagent` skill. Never hardcode a version-pinned model ID in skill prose; always use the tier aliases below.

| Role | Prose alias | Access / Notes |
|---|---|---|
| State reader | cheap / finder tier | Dispatched via `Task` tool. GitHub MCP primary (`pull_request_read`, `get_me`); `gh` fallback when MCP unavailable. Returns structured snapshot only — no raw payloads. |
| Track A implementer / fixer | mid tier (pinned to `sonnet` on CC) | Dispatched via `Task` tool. Applies the code fix for a single approved Fix item. |
| Track A verification (inner loop) | runner → judge split per `se-verify` | `se-verify` owns the runner (cheap) → judge (strong) cycle. |
| Track A review (outer loop) | strong / reviewer tier per `se-review` | `se-review` owns the arch-gate + deep-review cycle. |
| Track A reply poster | cheap / runner tier | Dispatched via `Task` tool. Posts approved replies via GitHub MCP `add_reply_to_pull_request_comment` (inline review-comment threads) or `add_issue_comment` (review-summary / top-level replies). |
| Track B executor | cheap → mid as needed, per `ci-triage.md` | Dispatched via `Task` tool. Follows the full Track B procedure in `ci-triage.md`. Uses `gh run rerun --failed` for flaky reruns; uses `gh run view --log-failed` when the status comment lacks detail. |
| Commit | `se-commit` (runner subagent) | se-commit owns staging isolation, message, and dispatch. Controller passes the implementer's explicit file list. |
