---
name: se-pr-triage
description: Use to fix and improve a PR that has review comments or CI failures — "triage the PR", "there's a comment on the PR…", "fix PR comments", "fix PR CI failure".
---

# se-pr-triage — Post-PR Triage Orchestrator

Controller for **one triage round** after a PR is open with feedback. Processes two independent tracks per invocation:

- **Track A** (review comments — inline threads + review summaries): two mandatory human gates — first approve/steer decisions + Fix scope, then, after successful fixes are pushed, approve the exact final replies.
- **Track B** (CI failures): investigated + resolved autonomously — no approval gate, no PR replies.

Round finishes → report both tracks → exit. Continuous watching = wrap in `/loop`; no built-in polling.

Controller stays lean. Delegate all MCP calls, git ops, and heavy execution to subagents via the `Task` tool, per the tier discipline in `/se-subagent`. Nothing substantial runs inline in the controller — no MCP reads, no `gh`, no `git`.

**Not** auto-chained from `/se-pr`. The human runs it explicitly, after reviewers or CI have reported.

---

## Session activation (do this FIRST)

Invoking this skill (typed `/se-pr-triage` or model auto-invoked for post-PR triage) starts a triage session. As the very first action, **write the session marker** `.super-exec/active` in the repo root (create `.super-exec/` if needed), e.g. `phase: pr-triage` and `started: <current UTC ISO-8601>`. This makes the enforcement guards live. Hooks read existence + mtime; the stale-marker decision is a model-judged heuristic with no fixed TTL. **Immediately after writing the marker, invoke `/se-local-ignore`.** Clear `.super-exec/active` at every early exit and at the end of the round.

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder. Do not advance past a step until it is confirmed done.

- [ ] **1. Detect the target PR**
- [ ] **2. Read triage state (state reader subagent)**
- [ ] **3. Determine what is actionable in each track**
- [ ] **4. Triage Track A decisions**
- [ ] **5. Mandatory decision approval gate (Gate 1)**
- [ ] **6. Execute approved Track A fixes**
- [ ] **7. Compose exact final replies**
- [ ] **8. Mandatory final reply approval gate (Gate 2)**
- [ ] **9. Post exact approved replies**
- [ ] **10. Execute Track B (autonomous)**
- [ ] **11. End-of-round report**
- [ ] **12. Clear `.super-exec/active`**

---

## 1. Detect the target PR

Accepts an optional PR-number arg (e.g. `/se-pr-triage 42`). If given, use it. Otherwise auto-detect the open PR for the current branch via GitHub MCP (`list_pull_requests` filtered to the current branch head, state: open), or `gh pr view` as fallback. If no open PR is found and none was given, report that to the human and exit. Clear `.super-exec/active` before exiting.

## 2. Read triage state (state reader subagent)

Dispatch a **finder/runner subagent (cheap tier — see `/se-subagent`)** via the `Task` tool to gather the full triage snapshot. The state reader must use **GitHub MCP as the primary access path**, falling back to `gh` only when MCP is unavailable. If neither MCP nor `gh` is available, report the access failure to the human and exit (clear `.super-exec/active` first).

The state reader calls these GitHub MCP methods on `pull_request_read` (plus the standalone `get_me` tool for identity):

- `get` — PR metadata + current head SHA.
- `get_review_comments` — inline review threads; each carries `isResolved` + `isOutdated` flags and its comment list (used to detect whether we already replied).
- `get_reviews` — top-level review summaries (approve / request-changes / comment bodies).
- `get_comments` — top-level issue/PR comments (status bot comments = human-readable "why" for CI failures).
- `get_check_runs` + `get_status` — CI signals: which jobs passed, failed, or are pending.
- `get_me` (standalone top-level MCP tool, no params) — our own identity (login), so "a reply from us" is reliably detected in `get_review_comments` results. Not a `pull_request_read` sub-method; called directly at the top level.

The state reader also notes which MCP methods are available, so the controller knows whether to use `add_reply_to_pull_request_comment` (in-thread reply) for Track A execution.

Returns a structured snapshot — thread list, CI check list, our identity — and nothing else. Raw API payloads do not cross back into the controller.

## 3. Determine what is actionable in each track

The controller reads the snapshot and classifies items:

- **Track A in-scope:** an unresolved inline review thread OR a top-level review summary, from any author (bot or human), with no reply from us yet. Out of scope (counted as skipped): resolved threads, outdated threads, status/CI bot comments, free-floating PR conversation (issue) comments.
- **Track B in-scope:** check runs or status checks with a failing conclusion. Ignored: passing checks and purely informational signals (changeset present, preview URL, green checks). Track B detail — the CI investigation + resolution procedure — is fully described in [`ci-triage.md`](./ci-triage.md); the controller delegates Track B execution to a subagent following that document.

If both tracks are empty (nothing actionable), report that and exit immediately. Clear `.super-exec/active` before exiting.

## 4. Triage Track A decisions

For each in-scope Track A item, the controller assigns exactly one decision:

- **Fix** — comment identifies a valid defect; code should change.
- **Decline** — comment is invalid, out of scope, or requests needless complexity for a case the code cannot actually reach. Reply explains why; no code change.
- **Answer** — a human question or discussion point that warrants a reply but no code change.
- **Defer** — a valid suggestion out of scope for this PR; reply acknowledges it as a future follow-up. No ticket or file is created.

Two standing rules apply to every triage decision:

- **Realism rule.** Bots do not know the full data flow or whether an end user can reach a given path. A comment that adds defensive complexity for a case the system cannot receive is a Decline, not a Fix.
- **Spec authority.** A comment requesting behavior that contradicts the committed spec defaults to Decline, with a citation of the relevant spec section. The skill never silently changes spec-defined behavior. The human may override the decision at Gate 1.

For each Fix, the controller drafts a short summary (one to two sentences) of what the fix will change, which the human reviews at Gate 1. This summary is a work plan, not reviewer-facing message copy. **Do not draft, generate, suggest, outline, or present any reply body — provisional, sample, or final — for any decision before step 7.**

## 5. Mandatory decision approval gate (Gate 1)

Present ALL Track A items together in a single prompt to the human before pushing any Fix. For each item include the original comment (with permalink or stable ID), proposed triage decision + rationale, and — for Fix items — the short fix summary. The rationale is internal analysis for the human, not a draft addressed to the reviewer. Include no proposed, suggested, sample, provisional, or final reply message. The human approves or steers the decisions and Fix scope in one shot.

**Gate-1 approval authorizes only the approved Fix work. It never authorizes a PR reply.** No Track A Fix is pushed until this gate is explicitly approved. There is no auto-approve mode, even when se-pr-triage is wrapped in `/loop`.

## 6. Execute approved Track A fixes

Process only the Gate-1-approved Fix items. Decline / Answer / Defer items wait untouched for the final-reply steps; do not dispatch any reply poster yet.

- **Fix items:** dispatch an **implementer subagent (mid tier, pinned to `sonnet` on Claude Code)** via the `Task` tool to make the code change. Then clear the **inner verification loop** via `/se-verify` and the **outer review loop** via `/se-review`, exactly as a normal build task in `/se-exec`. Once inner-loop-green and outer-loop-clean, commit via `/se-commit` (pass the explicit list of files the implementer touched — `/se-commit` owns staging isolation and the message), push the commit, and confirm the push succeeded.

  If the actual implementation must materially differ from the Gate-1-approved fix summary, return that item to Gate 1 before committing or pushing. If a Fix cannot be made green, reviewed clean, or confirmed pushed, abort that item: do not create a reply candidate, leave the thread untouched, and flag it in the round report as needing human attention. The remaining approved items still complete.

## 7. Compose exact final replies

First step where any reply text may be drafted. Only after every successful Fix is confirmed pushed, compose the final reply batch. If there are no Fix items, step 6 is a no-op after Gate 1; do not move reply composition into initial triage. For each non-aborted Track A item include:

- the exact target comment/review permalink and stable ID;
- the final triage decision; and
- the **exact final reply body** that would be posted.

A Fix reply must describe the actual implemented result and include its real pushed commit SHA or URL. Placeholders such as `<SHA>` and provisional implementation wording are forbidden. An aborted or unpushed Fix is shown as non-postable for visibility but excluded from reply candidates. A round with only Decline / Answer / Defer items still performs this step after Gate 1.

## 8. Mandatory final reply approval gate (Gate 2)

Present ALL final reply candidates together and wait. The human may approve, edit, or skip each reply. **Gate 2 is independent of Gate 1: no PR reply is authorized until the human explicitly approves this exact post-fix target-and-body batch.** There is no auto-approve mode, even under `/loop`.

Content-only edits can be approved in this gate. A requested decision or Fix-scope change returns that item to Gate 1. Any reply target or body change after Gate-2 approval invalidates that approval; re-present the changed batch and wait again. If every reply is skipped, post nothing and continue to the round report.

## 9. Post exact approved replies

Immediately before posting, revalidate each approved target: it must still be unresolved/in-scope and have no reply from us. If live state changed, skip it untouched and report why; new comments belong to the next round.

Dispatch a **runner subagent (cheap tier)** with only the immutable target ID and exact Gate-2-approved body for each still-valid reply. The poster must post the body verbatim — never rewrite, expand, summarize, or substitute any text. For an inline review-comment thread, post in-thread via GitHub MCP `add_reply_to_pull_request_comment`; for a top-level review summary, post a top-level PR comment via `add_issue_comment` referencing the review. Do not auto-resolve threads. A Gate-2-skipped reply remains untouched and may resurface as actionable in a later stateless round.

## 10. Execute Track B (autonomous)

Dispatch a **runner/implementer subagent** via the `Task` tool to work through every in-scope CI failure following the full procedure in [`ci-triage.md`](./ci-triage.md). In summary: Track B reads check runs, maps each failure to its mirror status comment for the human-readable reason, reads the raw failure log only when the comment lacks enough detail, and resolves per signal type — flaky tests rerun once, real failures fixed through the same `/se-verify` + `/se-review` loops and pushed, non-test failures (lint, type-check, PR-title, SonarCloud, Cycode) fixed at the source. Track B never posts a PR reply; the resolution is a green check. It escalates to the round report — and only to the round report — when the situation is unusual and the agent is unsure what to do.

Track A Fix execution (step 6) and Track B execution (step 10) are independent. Run in parallel only if no file overlap exists between Track A fixes and Track B fixes; otherwise run sequentially. Track B never bypasses, auto-approves, or delays either Track A gate. When in doubt, run sequentially.

## 11. End-of-round report

After both tracks complete, report on the full round:

- **Track A:** per in-scope comment — triage decision, Fix result, reply action (posted / skipped at Gate 2 / withheld after live-state revalidation / non-postable because Fix aborted), link to any posted reply, link to any pushed commit. Each aborted Fix is flagged as needing human attention.
- **Track B:** per in-scope CI failure — verdict (flaky-rerun / fixed / escalated), link to the check run, link to any pushed commit.
- **Skipped items:** count of already-handled items in both tracks (resolved threads, passing checks, informational signals).
- **Escalations and aborts:** every item flagged as needing human attention, listed together at the end.

## 12. Clear the session marker

Delete `.super-exec/active`. This is the final act of the round. Do not leave the marker set after the report is delivered.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "Gate 1 approved the batch, so replies are approved too." | Treat decision/Fix approval as reply authorization. | Gate 1 never authorizes replies. Finish approved fixes, compose exact post-fix replies, present Gate 2, and wait for explicit final-reply approval. |
| "I'll fetch PR state myself to save a subagent hop." | Run MCP calls or `gh` commands inline in the controller. | The controller never runs MCP or `gh` inline. All reads and mutations are dispatched to subagents via the `Task` tool. |
| "The bot is wrong but it's a CI bot — I'll reply to explain." | Post a reply on a status/CI bot comment or any Track B item. | Track B never posts replies. The resolution is a green check. If escalation is needed, it goes in the round report only. |
| "I'll fix the spec to satisfy the reviewer — it's a small change." | Silently change spec-defined behavior to satisfy a review comment. | A comment contradicting the committed spec defaults to Decline + cite the spec. Only the human can override. If the spec genuinely needs amendment, that is a separate `/se-discuss` session. |
| "I'll auto-approve under `/loop` to keep the round moving." | Skip or bypass either Track A gate in loop mode. | There is no auto-approve mode. Every round with Track A items must wait at Gate 1 and Gate 2, even when wrapped in `/loop`. |
| "I'll draft a provisional reply during triage and finalize it after the fix." | Generate reviewer-facing message copy before the actual result and commit reference exist. | Gate 1 contains only the original comment, decision/rationale, and Fix summary. Draft no reply text before step 7; compose exact Fix replies only after confirmed push. |
| "The final reply is close enough to the approved draft." | Rewrite, expand, retarget, or substitute text after Gate 2. | Post the exact approved target/body verbatim. Any change invalidates approval and reopens Gate 2. |
| "The fix is pushed, so I'll reply automatically." | Dispatch a reply poster immediately after fixing. | A pushed fix creates a Gate-2 reply candidate, not authorization. Present exact mapped replies and wait for explicit approval before posting. |
| "I'll silently rerun the CI job to clear a flaky failure." | Rerun a CI job without surfacing it in the round report. | All Track B verdicts — including flaky-rerun — appear in the end-of-round report with links. Nothing is silently handled. |
| "I'll leave the session marker set — someone else will clear it." | Complete the round without clearing `.super-exec/active`. | Step 12 is mandatory: clear the marker as the final act. Leaving it set keeps guards armed on a dead session. |

---

## Model and Tool Assignments

Resolve all concrete model IDs and dispatch details from `/se-subagent`. Never hardcode a version-pinned model ID in skill prose; always use the tier aliases below.

| Role | Prose alias | Access / Notes |
|---|---|---|
| State reader | cheap / finder tier | Dispatched via `Task` tool. GitHub MCP primary (`pull_request_read`, `get_me`); `gh` fallback when MCP unavailable. Returns structured snapshot only — no raw payloads. |
| Track A implementer / fixer | mid tier (pinned to `sonnet` on CC) | Dispatched via `Task` tool. Applies the code fix for a single approved Fix item. |
| Track A verification (inner loop) | runner → judge split per `/se-verify` | `/se-verify` owns the runner (cheap) → judge (strong) cycle. |
| Track A review (outer loop) | strong / reviewer tier per `/se-review` | `/se-review` owns the arch-gate + deep-review cycle. |
| Track A reply poster | cheap / runner tier | Dispatched only after Gate 2. Receives immutable target IDs + exact approved bodies, posts them verbatim via GitHub MCP `add_reply_to_pull_request_comment` (inline threads) or `add_issue_comment` (review-summary / top-level replies), and never rewrites content. |
| Track B executor | cheap → mid as needed, per `ci-triage.md` | Dispatched via `Task` tool. Follows the full Track B procedure in `ci-triage.md`. Uses `gh run rerun --failed` for flaky reruns; uses `gh run view --log-failed` when the status comment lacks detail. |
| Commit | `/se-commit` (runner subagent) | `/se-commit` owns staging isolation, message, and dispatch. Controller passes the implementer's explicit file list. |
