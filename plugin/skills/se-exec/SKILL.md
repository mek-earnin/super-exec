---
name: se-exec
description: Use this when a reviewed plan exists and it's time to BUILD — executes the plan task by task with verification and code review running in subagents, then opens a PR. Triggers on "implement the plan", "start building", "execute", "build it", or starting a fresh session after planning. The third step of the super-exec workflow; it keeps the controller lean, never claims done without evidence, and hands off to se-pr when the branch is review-clean.
---

# se-exec — Build Session Orchestrator

> **Reference paths:** every `references/*.md` cited lives at the plugin root — read it as `${CLAUDE_PLUGIN_ROOT}/references/<file>` on Claude Code, or `${CURSOR_PLUGIN_ROOT}/references/<file>` on Cursor.

se-exec is the **controller** for the entire execute session. It locates the plan, records the session toggles once, and then drives two nested loops — the **outer review loop** (se-review) wrapping the **inner verify loop** (se-verify) — until the branch is review-clean and handed to se-pr. It delegates every heavy operation to subagents or sibling skills. Nothing substantial runs inline in the controller.

---

## Session activation (do this FIRST)

Invoking this skill — typed `/se-exec` or model auto-invoked to build a planned feature — **means
a super-exec build session is starting**. As the very first action, **write the session marker**
`.super-exec/active` in the repo root (create `.super-exec/` if needed), e.g. `phase: exec` and
`started: <current UTC ISO-8601>`. This makes the enforcement guards live for the session —
including the hard commit-block while a review gate is open. Existence + mtime are what the hooks
read; the stale-marker decision is a model-judged heuristic with no fixed TTL. **Do not commit it**
— `.super-exec/` is gitignored. Behavior is identical for manual and auto invocation. If invoked
with `--worktree`, run the build in an isolated worktree (load `references/worktree.md` on demand);
any other argument is a feature slug / ticket to help locate the plan — still confirm. se-pr clears
`.super-exec/active` on PR completion; se-handoff never clears it.

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
    │  │    └─ FAIL → fixer → re-verify → loop      │  │
    │  │    └─ PASS → inner-loop-green              │  │
    │  └────────────────────────────────────────────┘  │
    │                                                  │
    │  COMMIT STEP                                     │
    │    └─ (if review-before-commit ON):              │
    │         write .super-exec/gate-open              │
    │         show diff + proposed commit msg          │
    │         WAIT for human                           │
    │         clear .super-exec/gate-open              │
    │    └─ commit via repo git-commit-message skill   │
    │         (runner subagent — never inline)         │
    │                                                  │
    │  se-review (arch-gate → deep-review → severity) │
    │    └─ Critical/Important → re-enter inner loop   │
    │    └─ Minor → reported, non-blocking             │
    │    └─ fresh reviewer re-reviews after fixes      │
    │    └─ CLEAN → exit outer loop for this task      │
    └──────────────────────────────────────────────────┘

  ALL TASKS CLEAN → invoke se-pr
  CONTEXT LOW (model-judged) → invoke se-handoff → pause
```

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder steps.

- [ ] **1. Locate the plan.** Match the plan directory by the current branch name or ticket number → then by feature name → then by the most-recent plan dir under `.super-exec/<feature>/`. **Confirm the match with the user before proceeding.** Do not assume silently.

- [ ] **2. Check for a handoff.** If `handoff.md` exists in the plan dir, read it. Resume from the **next unstarted task** — skip all tasks marked completed. Do NOT redo completed tasks, re-litigate decisions, or reset toggle state. The handoff is authoritative.

- [ ] **3. Read the plan and spec.** Read `plan.md` in full. Read the linked spec under `docs/specs/...` in full. Understand the acceptance criteria and the verification design recorded in the plan before dispatching anything.

- [ ] **4. Present the two session toggles — ONCE, together, at the start.** Do not ask them separately. Do not ask again mid-session.
  - *Review before each commit?* — default **OFF** (auto-commit on inner-loop-green).
  - *Auto-create PR when review is clean?* — default **OFF** (require explicit human approval).
  Record both answers. They are immutable for the session.

- [ ] **5. If the plan is a UI plan and the impeccable opt-in was never recorded, re-ask ONCE** (default yes). Persist the answer. This question is only asked when the record is genuinely absent — never re-ask if the answer is already recorded (including a "no" from a prior session or from the handoff).

- [ ] **6. Per task — inner loop.** For each task in plan order (respecting the parallelism rule below):

  - **6a. Dispatch an implementer subagent (implementer/mid tier — see `references/model-tiers.md`).** The implementer MUST:
    1. Check the plan's recorded binding and **invoke the task's bound repo skill BEFORE hand-rolling any logic**.
    2. Re-check the repo skill catalog for any unplanned work the task requires — use a skill if one covers it.
    3. When impeccable is enabled and the task is UI, build via impeccable `craft`.
    The implementer reports back a summary. Raw file diffs do not enter the controller's context.

  - **6b. Parallelism rule.** Independent tasks that touch **completely disjoint file sets** may be dispatched in parallel. Any two tasks that share even one file MUST run sequentially. When in doubt, run sequentially.

  - **6c. Invoke se-verify.** Pass the task description and the plan's verification design (baseline commands + task-specific method). se-verify owns the runner→judge loop and reports either inner-loop-green or a continued failure requiring escalation to se-exec.

  - **6d. Inner-loop-green is confirmed — proceed to the commit step.**

- [ ] **7. Commit step.**

  - If **review-before-commit is ON**:
    1. Write `.super-exec/gate-open`.
    2. Show the diff (dispatched to a runner subagent — never `git diff` inline in the controller) and the proposed commit message.
    3. **WAIT** for human approval.
    4. Clear `.super-exec/gate-open` before proceeding.

  - Commit via the repo **`git-commit-message`** skill: conventional format, no scope, one logical change per commit, one commit per task. All git commands run in a **runner subagent** (cheap/script-runner tier, see `references/model-tiers.md`). The controller issues no git commands inline, ever.

- [ ] **8. Outer loop — invoke se-review.** se-review performs the arch-gate, deep-review, and severity-tagging pass on the committed task.
  - **Critical or Important** findings → re-enter the inner loop (step 6) to fix; a **fresh reviewer** re-reviews from scratch after fixes.
  - **Minor** findings → reported, non-blocking.
  - Loop until a fresh reviewer declares the task clean.

- [ ] **9. Context hygiene — monitor throughout.** The controller monitors its own context depth continuously using a **model-judged heuristic** (no fixed token count). When the controller judges it is approaching a context limit mid-build, invoke **se-handoff** immediately to write `handoff.md`, then pause and instruct the user to `/clear` and re-run `/se-exec`. Do NOT continue past the limit hoping to finish.

- [ ] **10. All tasks clean — invoke se-pr.** When every task in the plan is inner-loop-green, committed, and outer-loop-clean, invoke **se-pr**. se-pr handles the optional final human review gate, PR creation, and clears `.super-exec/active` on completion.

---

## Scope Guard (YAGNI)

Implement **only** what the plan specifies. Do not add extra tests, helper utilities, documentation sections, or any logic not required by a plan task. Do not edit `plan.md` or any other plan file during execution — the plan is read-only once execution begins.

---

## Worktree Mode

No worktrees by default. If and only if the user passed **`--worktree`** at invocation: load `references/worktree.md` on demand, then follow it for worktree creation, subagent path-passing, and teardown. The `.super-exec/` markers always live in the main repo (`CLAUDE_PROJECT_DIR`/`CURSOR_PROJECT_DIR`), not the worktree.

---

## Model Tiers and Tool Assignments

Resolve all model names and subagent dispatch primitives from the reference files.

| Role | Prose alias | Reference |
|---|---|---|
| Implementer / Fixer | implementer / mid tier | `references/model-tiers.md` → "Implementer · Fixer" row (PINNED to Sonnet on CC) |
| Runner | cheap / script-runner tier | `references/model-tiers.md` → "Script-runner" row |
| Judge / Reviewer | strong non-fast tier | `references/model-tiers.md` → "Shape interview · Plan · Review" row |
| Handoff writer | controller / strong tier | `references/model-tiers.md` → strong non-fast row |
| Subagent dispatch | `Task` tool (CC) / composer subagent (Cursor) | `references/tool-map.md` → "Subagent Dispatch" section |

---

## Red-Flag Table

| Red flag | What you were about to do | Correction |
|---|---|---|
| "I'll run the build/tests here to save a hop." | Execute any build, lint, test, or git command inline in the controller. | Delegate to a runner subagent (cheap/script-runner tier). The controller dispatches, waits, and reads a summary. Nothing heavy runs inline. |
| "I'll ask the toggles again later — I forgot to record them." | Re-present the session toggles after the session has started, or ask them one at a time. | Present both toggles together, once, at step 4. Record the answers. They are immutable. |
| "These two tasks are quick — I'll run them in parallel." | Parallelize tasks that share at least one file. | Parallel dispatch is valid **only** for tasks with completely disjoint file sets. A single shared file makes the pair sequential. |
| "The implementer can hand-roll the API call — it's simpler." | Let the implementer bypass the plan's bound repo skill and write the logic from scratch. | The implementer MUST invoke the bound repo skill first, every time, before writing any hand-rolled logic. |
| "I'll tweak the plan to fit what I actually built." | Edit plan.md or any plan file to match the implementation after the fact. | The plan is read-only during execution. Never edit it. If the implementation diverges from the plan, surface the divergence to the user — do not silently update the plan. |
| "I'll add a couple of extra tests / a helper utility while I'm here." | Add unrequested tests, helpers, documentation, or any code not specified in the plan. | YAGNI. Only what the plan specifies. Extra additions go into a follow-up task or a new plan — not this session. |
| "I'll commit now and show the diff after." | Commit during the review-before-commit gate without writing `.super-exec/gate-open` first and waiting for human approval. | Write `.super-exec/gate-open`, show the diff and proposed message, WAIT for explicit approval, then clear `.super-exec/gate-open`, then commit. The gate is not optional when review-before-commit is ON. |
| "I'll just keep going — I can probably finish before context runs out." | Continue past the model-judged context limit without invoking se-handoff. | When the controller judges it is approaching a context limit, invoke se-handoff immediately, pause, and tell the user to `/clear` and re-run `/se-exec`. |
| "I'll use a worktree to be safe — it can't hurt." | Create a git worktree without the user having passed `--worktree`. | No worktrees unless `--worktree` was explicitly passed at invocation. Load `references/worktree.md` on demand only when that flag is present. |
| "The impeccable question keeps coming up — I'll re-ask each session." | Re-ask the impeccable opt-in even though an answer is already recorded in the plan or handoff. | Re-ask ONCE, only if the record is genuinely absent. A prior "no" is a record. A handoff carrying the answer is a record. Do not re-ask. |
