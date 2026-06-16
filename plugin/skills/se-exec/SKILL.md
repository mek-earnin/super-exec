---
name: se-exec
description: Use this when a reviewed plan exists and it's time to BUILD — executes the plan task by task with verification and code review running in subagents, then opens a PR. Triggers on "implement the plan", "start building", "execute", "build it", or starting a fresh session after planning. The third step of the super-exec workflow; it keeps the controller lean, never claims done without evidence, and hands off to se-pr when the branch is review-clean.
---

# se-exec — Build Session Orchestrator

se-exec is the **controller** for the entire execute session. It locates the plan, records the session toggles once, and then drives two nested loops — the **outer review loop** (se-review) wrapping the **inner verify loop** (se-verify) — until the branch is review-clean and handed to se-pr. It delegates every heavy operation to subagents or sibling skills. Nothing substantial runs inline in the controller.

---

## Session activation (do this FIRST)

Invoking this skill — typed `/se-exec` or model auto-invoked to build a planned feature — **means
a build session is starting**. As the very first action, **write the session marker**
`.super-exec/active` in the repo root (create `.super-exec/` if needed), e.g. `phase: exec` and
`started: <current UTC ISO-8601>`. This makes the enforcement guards live for the session —
including the hard commit-block while a review gate is open. Existence + mtime are what the hooks
read; the stale-marker decision is a model-judged heuristic with no fixed TTL. **Do not commit it**
— `.super-exec/` is gitignored. Behavior is identical for manual and auto invocation. If invoked
with `--worktree`, run the build in an isolated worktree (load `${CLAUDE_SKILL_DIR}/worktree.md`
on demand); any other argument is a feature slug / ticket to help locate the plan — still confirm.
`.super-exec/active` is cleared by se-pr on PR completion, or by se-exec itself on the no-PR exit
(final review with *Auto-PR* OFF and the user declines the PR — step 10);
se-handoff never clears it.

---

## Loop Structure

```
SESSION START
  └─ locate + confirm plan (+ handoff resume if handoff.md present)
  └─ read plan.md + spec
  └─ present 2 toggles ONCE
  └─ (re-ask impeccable ONCE if UI plan + record missing)

  FOR EACH TASK (sequential unless file-disjoint):

    ┌──────────────────────────────────────────────────┐
    │  OUTER LOOP  (se-review)                         │
    │                                                  │
    │  ┌────────────────────────────────────────────┐  │
    │  │  INNER LOOP  (se-verify)                   │  │
    │  │                                            │  │
    │  │  implementer subagent                      │  │
    │  │    └─ invoke bound repo skill first        │  │
    │  │    └─ impeccable craft (if UI + enabled)   │  │
    │  │  → se-verify (runner → judge)              │  │
    │  │    └─ FAIL (bug) → fixer → re-verify → loop│  │
    │  │    └─ FAIL (limitation) → escalate (6e)    │  │
    │  │    └─ PASS → inner-loop-green              │  │
    │  └────────────────────────────────────────────┘  │
    │                                                  │
    │  COMMIT STEP                                     │
    │    └─ (if review-before-commit ON):              │
    │         write .super-exec/gate-open              │
    │         show diff + proposed commit msg          │
    │         WAIT for human                           │
    │         clear .super-exec/gate-open              │
    │    └─ commit via se-commit (pass implementer     │
    │         file list; se-commit owns the rest)      │
    │                                                  │
    │  se-review (arch-gate → deep-review → severity) │
    │    └─ Critical/Important → re-enter inner loop   │
    │    └─ Minor → reported, non-blocking             │
    │    └─ fresh reviewer re-reviews after fixes      │
    │    └─ CLEAN → exit outer loop for this task      │
    └──────────────────────────────────────────────────┘

  ALL TASKS CLEAN
    └─ reviewer final spec-match assertion (built behavior still matches spec?)
    └─ AUTO-PR ON  → invoke se-pr (opens PR, no review)
    └─ AUTO-PR OFF → write gate-open → final human review → WAIT
         └─ "Create a draft PR?"  NO  → clear gate-open + active → DONE (no PR)
                                  YES → clear gate-open → invoke se-pr

  LIMITATION ESCALATION (step 6e — no fix, spec unachievable as written):
    └─ try a workaround meeting spec intent → found? apply, continue
    └─ no workaround:
         AUTO-PR OFF → ask human (requirement + limitation + recommendation)
         AUTO-PR ON  → amend spec to closest achievable + note limitation
                          → commit spec via se-commit → rebuild to revised spec → re-verify

  CONTEXT LOW (model-judged) → invoke se-handoff → pause
```

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder steps.

- [ ] **1. Locate the plan.** Match the plan directory by the current branch name or ticket number → then by feature name → then by the most-recent plan dir under `.super-exec/<feature>/`. **Confirm the match with the user before proceeding.** Do not assume silently.

- [ ] **2. Check for a handoff.** If `handoff.md` exists in the plan dir, read it. Resume from the **next unstarted task** — skip all tasks marked completed. Do NOT redo completed tasks, re-litigate decisions, or reset toggle state. The handoff is authoritative.

- [ ] **3. Read the plan and spec.** Read `plan.md` in full. Read the linked spec under `docs/specs/...` in full. Understand the acceptance criteria and the verification design recorded in the plan before dispatching anything.

- [ ] **4. Present the two session toggles — ONCE, together, at the start.** Use the `AskUserQuestion` tool to ask both toggles in a single prompt. Do not ask them separately. Do not ask again mid-session.
  - *Review before each commit?* — default **OFF** (auto-commit on inner-loop-green).
  - *Auto-PR?* — default **OFF**. This is the **"human in the loop?"** signal that governs the final review, the limitation-escalation branch, and PR creation.
    - **OFF** → human in the loop: pause for a final work review, ask before opening a draft PR, and ask the user on any blocker that cannot be worked around.
    - **ON** → no human in the loop: no final review; self-resolve unworkable blockers by amending the spec to the closest achievable behavior + a limitation note; open the PR automatically. (The PR review + manual merge stay the human's gate.)
  Record both answers. They are immutable for the session.

- [ ] **5. If the plan is a UI plan and the impeccable opt-in was never recorded, re-ask ONCE** (default yes) using `AskUserQuestion`. Persist the answer. This question is only asked when the record is genuinely absent — never re-ask if the answer is already recorded (including a "no" from a prior session or from the handoff).

- [ ] **6. Per task — inner loop.** For each task in plan order (respecting the parallelism rule below):

  - **6a. Dispatch an implementer subagent using the `Task` tool (implementer / mid tier — see the `se-subagent` skill).** The implementer MUST:
    1. Check the plan's recorded binding and **invoke the task's bound repo skill BEFORE hand-rolling any logic**.
    2. Re-check the repo skill catalog for any unplanned work the task requires — use a skill if one covers it.
    3. When impeccable is enabled and the task is UI, build via impeccable `craft`.
    The implementer reports back a summary **including the explicit list of files it created or modified** — the controller passes that list to the commit step so the commit stages only those paths. Raw file diffs do not enter the controller's context.

  - **6b. Parallelism rule.** Independent tasks that touch **completely disjoint file sets** may be dispatched in parallel using the `Task` tool. Any two tasks that share even one file MUST run sequentially. When in doubt, run sequentially.

  - **6c. Invoke se-verify.** Pass the task description and the plan's verification design (baseline commands + task-specific method). se-verify owns the runner→judge loop and reports one of: **inner-loop-green**, or **limitation-blocked** (the spec is not achievable as written — a real constraint, not a fixable bug — see step 6e).

  - **6d. Inner-loop-green is confirmed — proceed to the commit step.**

  - **6e. Limitation escalation (only when se-verify reports limitation-blocked).** The divergence is an *implementation limitation*, not an ordinary bug. The spec is authoritative — do NOT silently rewrite it. Resolve in this order:
    1. **Try a workaround** that still satisfies the spec's *intent* (dispatch an implementer with the `Task` tool, passing the limitation + the intent to preserve). If a workaround passes verification, apply it and return to the commit step — the spec is unchanged.
    2. **No workaround** → branch on the *Auto-PR* toggle:
       - **Auto-PR OFF (human in the loop):** STOP and use `AskUserQuestion` to ask the user — state the spec requirement, the limitation, and your recommendation. The answer may change the spec (WHAT-only) and the implementation. If the change is architectural, recommend `/se-plan` re-entry; otherwise update the spec and the code inline, then re-verify. On approval, commit the spec change via **`se-commit`** (pass the spec / ADR paths), unless declined / gitignored.
       - **Auto-PR ON (no human in the loop):** the agent amends the spec **itself** to the **closest achievable** behavior and annotates the spec's *Decisions* section — *"Due to `<limitation>`, cannot achieve `<original behavior>`; closest achievable is `<X>`."* — WHAT-only, no code. Commit the spec change via **`se-commit`** (pass the spec file path), rebuild the task to the revised spec, and re-verify. No interrupt. The amendment lands in the PR the human reviews.

- [ ] **7. Commit step.**

  - If **review-before-commit is ON**:
    1. Write `.super-exec/gate-open`.
    2. Show the diff (dispatched to a runner subagent via `Task` — never `git diff` inline in the controller) and the proposed commit message.
    3. **WAIT** for human approval.
    4. Clear `.super-exec/gate-open` before proceeding.

  - Commit via **`se-commit`**, passing the explicit list of files this task's implementer reported touching (one commit per task). se-commit owns all commit mechanics — staging isolation, the message, and the runner-subagent dispatch; the controller issues no git commands inline.

- [ ] **8. Outer loop — invoke se-review.** se-review performs the arch-gate, deep-review, and severity-tagging pass on the committed task.
  - **Critical or Important** findings → re-enter the inner loop (step 6) to fix; a **fresh reviewer** re-reviews from scratch after fixes.
  - **Minor** findings → reported, non-blocking.
  - Loop until a fresh reviewer declares the task clean.

- [ ] **9. Context hygiene — monitor throughout.** The controller monitors its own context depth continuously using a **model-judged heuristic** (no fixed token count). When the controller judges it is approaching a context limit mid-build, invoke **se-handoff** immediately to write `handoff.md`, then pause and instruct the user to `/clear` and re-run `/se-exec`. Do NOT continue past the limit hoping to finish.

- [ ] **10. All tasks clean — final spec-match assertion, then the PR decision.** When every task is inner-loop-green, committed, and outer-loop-clean, first confirm the reviewer's **final spec-match assertion** (does the whole built behavior still match the spec? — a cross-task-drift backstop; a mismatch re-enters the inner loop or, if a limitation, step 6e). Then branch on the **Auto-PR** toggle:
  - **Auto-PR ON** → no final review. Invoke **se-pr** directly; it creates the PR and clears `.super-exec/active` on completion.
  - **Auto-PR OFF** → run the final human review:
    1. Write `.super-exec/gate-open` (commits are blocked while it exists).
    2. Present the work for final review (branch + commit list + summary + any captured evidence — via a runner subagent dispatched with `Task`, never `git` inline) and **WAIT** for the human to resolve the review.
    3. Once resolved, use `AskUserQuestion` to ask: **"Create a draft PR?"**
       - **No** → clear `.super-exec/gate-open`, then clear `.super-exec/active`. The session ends: the work stays committed on the branch, no PR. (se-exec owns clearing `active` on this no-PR exit.)
       - **Yes** → clear `.super-exec/gate-open`, then invoke **se-pr** (which creates the draft PR and clears `.super-exec/active` on completion).

---

## Scope Guard (YAGNI)

Implement **only** what the plan specifies. Do not add extra tests, helper utilities, documentation sections, or any logic not required by a plan task. Do not edit `plan.md` or any other plan file during execution — the plan is read-only once execution begins.

---

## Worktree Mode

No worktrees by default. If and only if the user passed **`--worktree`** at invocation: load [`worktree.md`](./worktree.md) on demand (read via `${CLAUDE_SKILL_DIR}/worktree.md`), then follow it for worktree creation, subagent path-passing, and teardown. The `.super-exec/` markers always live in the main repo (`CLAUDE_PROJECT_DIR`), not the worktree.

---

## Model Tiers and Subagent Dispatch

Dispatch all subagents with the `Task` tool. Resolve tier aliases from the `se-subagent` skill.

| Role | Prose alias | Notes |
|---|---|---|
| Implementer / Fixer | implementer / mid tier | PINNED to `sonnet` on CC |
| Runner | cheap / script-runner tier | git commands, diff display, spec commits |
| Judge / Reviewer | strong non-fast tier | arch-gate, deep-review, spec-match assertion |
| Handoff writer | controller / strong tier | invoked when context limit approached |

---

## Red-Flag Table

| Red flag | What you were about to do | Correction |
|---|---|---|
| "I'll run the build/tests here to save a hop." | Execute any build, lint, test, or git command inline in the controller. | Delegate to a runner subagent dispatched with `Task` (cheap / script-runner tier). The controller dispatches, waits, and reads a summary. Nothing heavy runs inline. |
| "I'll ask the toggles again later — I forgot to record them." | Re-present the session toggles after the session has started, or ask them one at a time. | Present both toggles together using `AskUserQuestion`, once, at step 4. Record the answers. They are immutable. |
| "These two tasks are quick — I'll run them in parallel." | Parallelize tasks that share at least one file. | Parallel dispatch via `Task` is valid **only** for tasks with completely disjoint file sets. A single shared file makes the pair sequential. |
| "The implementer can hand-roll the API call — it's simpler." | Let the implementer bypass the plan's bound repo skill and write the logic from scratch. | The implementer MUST invoke the bound repo skill first, every time, before writing any hand-rolled logic. |
| "I'll tweak the plan to fit what I actually built." | Edit plan.md or any plan file to match the implementation after the fact. | The plan is read-only during execution. Never edit it. If the implementation diverges from the plan, surface the divergence to the user — do not silently update the plan. |
| "The code can't quite meet the spec — I'll just relax the spec." | Rewrite the committed spec to match whatever the code happened to do. | A divergence is a **bug by default** — fix the code (the spec is authoritative). The spec is amended ONLY for a genuine implementation limitation with no workaround, and ONLY via step 6e: use `AskUserQuestion` to ask the user when Auto-PR is OFF; amend to the closest achievable + a limitation note when Auto-PR is ON. Never rewrite the spec to paper over an ordinary bug. |
| "Auto-PR is OFF but I'll just open the PR — it's clean." | Skip the final review / the "Create a draft PR?" question and open the PR anyway when Auto-PR is OFF. | Auto-PR OFF means a human is in the loop: write `gate-open`, present the work, WAIT, then use `AskUserQuestion` to ask whether to create a draft PR. "No" ends the session with no PR (clear `gate-open` + `active`). Only Auto-PR ON opens the PR without asking. |
| "I'll add a couple of extra tests / a helper utility while I'm here." | Add unrequested tests, helpers, documentation, or any code not specified in the plan. | YAGNI. Only what the plan specifies. Extra additions go into a follow-up task or a new plan — not this session. |
| "I'll commit now and show the diff after." | Commit during the review-before-commit gate without writing `.super-exec/gate-open` first and waiting for human approval. | Write `.super-exec/gate-open`, show the diff and proposed message, WAIT for explicit approval, then clear `.super-exec/gate-open`, then commit. The gate is not optional when review-before-commit is ON. |
| "I'll just keep going — I can probably finish before context runs out." | Continue past the model-judged context limit without invoking se-handoff. | When the controller judges it is approaching a context limit, invoke se-handoff immediately, pause, and tell the user to `/clear` and re-run `/se-exec`. |
| "I'll use a worktree to be safe — it can't hurt." | Create a git worktree without the user having passed `--worktree`. | No worktrees unless `--worktree` was explicitly passed at invocation. Load [`worktree.md`](./worktree.md) on demand only when that flag is present. |
| "The impeccable question keeps coming up — I'll re-ask each session." | Re-ask the impeccable opt-in even though an answer is already recorded in the plan or handoff. | Re-ask ONCE using `AskUserQuestion`, only if the record is genuinely absent. A prior "no" is a record. A handoff carrying the answer is a record. Do not re-ask. |
