---
name: se-exec
description: Use this when a reviewed plan exists and it's time to BUILD — executes the plan task by task with verification and code review running in subagents, then opens a PR. Triggers on "implement the plan", "start building", "execute", "build it", or starting a fresh session after planning. The third step of the super-exec workflow; it keeps the controller lean, never claims done without evidence, and hands off to se-pr when the branch is review-clean.
---

# se-exec — Build Session Orchestrator

se-exec is the **controller** for the entire execute session. It locates the plan, records the session toggles once, and then drives two nested loops — the **outer review loop** (se-review) wrapping the **inner verify loop** (se-verify) — until the branch is review-clean and handed to se-pr. It delegates every heavy operation to subagents or sibling skills. Nothing substantial runs inline in the controller.

---

## Session activation (do this FIRST)

Invoking this skill — typed `/se-exec` or model auto-invoked to build a planned feature — **means
a build session is starting**. As the very first action, **activate without clobbering resume
state**: read `.super-exec/active` if it exists, then write or update the marker with `phase: exec`
and `started: <current UTC ISO-8601>` while you **preserve any existing `active_plan`** and
**preserve `branch` if present**. Create `.super-exec/` if needed. If the marker cannot be read or
merged safely, defer the marker write until step 1 selects the plan; do not replace the file with a
minimal marker that drops `active_plan`. This makes the enforcement guards live for the session —
including the hard commit-block while a review gate is open. Existence + mtime are what the hooks
read; the stale-marker decision is a model-judged heuristic with no fixed TTL. **Immediately after
writing the marker, invoke `/se-local-ignore`.** Behavior is identical for manual and auto
invocation. If invoked
with `--worktree`, run the build in an isolated worktree (load [@./worktree.md](./worktree.md)
on demand). If manual invocation includes an explicit plan path — either a `plan.md` file path or a
plan directory containing `plan.md` — use that exact plan and skip the plan-confirmation prompt. If
the path cannot be resolved to `plan.md`, stop and ask for the corrected path. If no explicit path is
provided, first check the preserved `.super-exec/active` for `active_plan:` and ask the user to
confirm that plan. If the marker has no active plan, fall back to latest-plan discovery and ask the
user to confirm. Any other argument is a feature slug / ticket to help locate the plan — still
confirm.
`.super-exec/active` is cleared by se-pr on PR completion, or by se-exec itself on the no-PR exit
(final review with *Auto-PR* OFF and the user declines the PR — step 10);
se-handoff never clears it.

---

## Loop Structure

```
SESSION START
  └─ locate + confirm plan (+ handoff resume if handoff.md present)
  └─ read plan frontmatter + checklist + spec
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

- [ ] **1. Locate the plan.** Resolve in this order:
  1. **Explicit path from manual invocation** — if the user provided an absolute or relative `plan.md`, or a directory containing `plan.md`, use that plan directory without asking for confirmation; the path itself is the confirmation. If the path cannot be resolved to `plan.md`, stop and ask for the corrected path.
  2. **Active marker** — if no explicit path was provided, read `.super-exec/active`. If it contains `active_plan: <path>`, resolve that path to `plan.md` and ask the user to confirm this plan before proceeding. If `active_plan` exists but cannot be resolved, tell the user the marker points at a missing plan and stop; do not silently choose a different plan.
  3. **Latest plan fallback** — if there is no explicit path and no `active_plan`, match the plan directory by the current branch name or ticket number → then by feature name → then by the most-recent plan dir under `.super-exec/<feature>/`. Ask the user to confirm this inferred match before proceeding.
  If no plan is found, tell the user no executable plan was found and stop. Once a plan is selected by any path above, update `.super-exec/active` with `phase: exec`, `active_plan: <repo-relative path to plan.md>`, `started: <current UTC ISO-8601>`, and the existing `branch` value if one was present and still matches the selected plan. Do not assume silently.

- [ ] **2. Check frontmatter, status, checklist, and handoff.** Read the plan's YAML frontmatter before or with the first `## Execution Checklist`. If frontmatter has `branch`, branch validation depends on mode: normal mode must verify the current git branch matches `branch`; `--worktree` mode validates the main checkout before worktree creation, then the worktree setup checks out or creates the worktree branch. Do not fail a worktree run merely because the main checkout no longer matches after the worktree exists. On a real mismatch, stop and ask the user whether to switch branches, choose a different plan, or continue via the explicit worktree path — do not silently continue.

  **Completion guard:** treat the plan as already completed only when either frontmatter `status: completed` is present, or the checklist exists, has at least one item, and every item in the first `## Execution Checklist` is checked, with no `handoff.md` pointing at unfinished work. In either completed case, tell the user the plan is already completed and stop before steps 3-10. A missing checklist is never completed. If there is no checklist and status is not completed, fall back to `## Tasks` plus any handoff-based resume evidence; if that is ambiguous, ask the user to update or confirm the resume point rather than declaring the plan completed.

  If `handoff.md` exists in the plan dir, read it. Resume from the **next unstarted task** — skip all tasks marked completed in the handoff or checked in the plan checklist. Do NOT redo completed tasks, re-litigate decisions, or reset toggle state. The handoff is authoritative when present. Once the selected plan is not already complete and the branch check passes, update `status` from `pending` to `in_progress`; if status is blank or absent, set `in_progress` without changing other metadata.

- [ ] **3. Read the plan/spec and seed task state.** Read `plan.md` in full. Read the linked spec under `docs/specs/...` in full. Understand the acceptance criteria, execution checklist, and verification design recorded in the plan before dispatching anything. If the harness exposes native task/todo tooling, use the CC primitive `TodoWrite` or its translated equivalent from the harness translation table. Seed or sync the native list from `## Execution Checklist`, preserving checked items as completed and selecting the next unchecked item as in progress. The native task/todo list is the operational session state; plan frontmatter plus `## Execution Checklist` are the durable local resume state.

- [ ] **4. Present the two session toggles — ONCE, together, at the start.** Use the `AskUserQuestion` tool to ask both toggles in a single prompt. Do not ask them separately. Do not ask again mid-session.
  - *Review before each commit?* — default **OFF** (auto-commit on inner-loop-green). Choosing **OFF** is the user's explicit, standing authorization to commit each task automatically: every per-task commit is then a *user-requested* commit, not a proactive one. When OFF, never pause to re-ask for commit approval — the toggle already granted it. (This is what satisfies a host agent policy that otherwise forbids committing without an explicit per-action user request.)
  - *Auto-PR?* — default **OFF**. This is the **"human in the loop?"** signal that governs the final review, the limitation-escalation branch, and PR creation.
    - **OFF** → human in the loop: pause for a final work review, ask before opening a draft PR, and ask the user on any blocker that cannot be worked around.
    - **ON** → no human in the loop: no final review; self-resolve unworkable blockers by amending the spec to the closest achievable behavior + a limitation note; open the PR automatically. (The PR review + manual merge stay the human's gate.)
  Record both answers. They are immutable for the session.

- [ ] **5. If the plan is a UI plan and the impeccable opt-in was never recorded, re-ask ONCE** (default yes) using `AskUserQuestion`. Persist the answer. This question is only asked when the record is genuinely absent — never re-ask if the answer is already recorded (including a "no" from a prior session or from the handoff).

- [ ] **6. Per task — inner loop.** For each executable task in plan order (respecting the parallelism rule below). The `Final review / PR decision` checklist item is not an executable task, is never dispatched to an implementer, and belongs to step 10 only:

  - **Task transition sync.** Before starting a task, update the native task/todo tool first (mark previous outer-loop-clean task complete, current task in progress, future tasks pending), then sync `plan.md` only for durable state already earned: frontmatter `status` and completed checkboxes. On every task transition, keep the native tool and plan checklist aligned. If no native task/todo tool exists in the harness, use the plan checklist as the source of truth and state that the native sync step is unavailable.

  - **6a. Dispatch an implementer subagent using the `Task` tool (implementer / mid tier — see the `se-subagent` skill).** The implementer MUST:
    1. Check the plan's recorded binding and **invoke the task's bound repo skill BEFORE hand-rolling any logic**.
    2. Re-check the repo skill catalog for any unplanned work the task requires — use a skill if one covers it.
    3. When impeccable is enabled and the task is UI, build via impeccable `craft`.
    The implementer reports back a summary **including the explicit list of files it created or modified** — the controller passes that list to the commit step so the commit stages only those paths. Raw file diffs do not enter the controller's context.

  - **6b. Parallelism rule.** Independent tasks that touch **completely disjoint file sets** may be dispatched in parallel using the `Task` tool. Any two tasks that share even one file MUST run sequentially. When in doubt, run sequentially.

  - **6c. Invoke `/se-verify`.** Pass the task description and the plan's verification design (baseline commands + task-specific method). se-verify owns the runner→judge loop and reports one of: **inner-loop-green**, or **limitation-blocked** (the spec is not achievable as written — a real constraint, not a fixable bug — see step 6e).

  - **6d. Inner-loop-green is confirmed — proceed to the commit step.**

  - **6e. Limitation escalation (only when se-verify reports limitation-blocked).** The divergence is an *implementation limitation*, not an ordinary bug. The spec is authoritative — do NOT silently rewrite it. Resolve in this order:
    1. **Try a workaround** that still satisfies the spec's *intent* (dispatch an implementer with the `Task` tool, passing the limitation + the intent to preserve). If a workaround passes verification, apply it and return to the commit step — the spec is unchanged.
    2. **No workaround** → branch on the *Auto-PR* toggle:
       - **Auto-PR OFF (human in the loop):** STOP and use `AskUserQuestion` to ask the user — state the spec requirement, the limitation, and your recommendation. The answer may change the spec (WHAT-only) and the implementation. If the change is architectural, recommend `/se-plan` re-entry; otherwise update the spec and the code inline, then re-verify. On approval, commit the spec change via **`/se-commit`** (pass the spec / ADR paths), unless declined / gitignored.
       - **Auto-PR ON (no human in the loop):** the agent amends the spec **itself** to the **closest achievable** behavior and annotates the spec's *Decisions* section — *"Due to `<limitation>`, cannot achieve `<original behavior>`; closest achievable is `<X>`."* — WHAT-only, no code. Commit the spec change via **`/se-commit`** (pass the spec file path), rebuild the task to the revised spec, and re-verify. No interrupt. The amendment lands in the PR the human reviews.

- [ ] **7. Commit step.**

  - If **review-before-commit is ON**:
    1. Write `.super-exec/gate-open`.
    2. Show the diff (dispatched to a runner subagent via `Task` — never `git diff` inline in the controller) and the proposed commit message.
    3. **WAIT** for human approval.
    4. Clear `.super-exec/gate-open` before proceeding.

  - Commit via **`/se-commit`**, passing the explicit list of files this task's implementer reported touching (one commit per task). se-commit owns all commit mechanics — staging isolation, the message, and the runner-subagent dispatch; the controller issues no git commands inline.

  - When review-before-commit is **OFF**, commit immediately on inner-loop-green without seeking per-commit approval — the OFF toggle (step 4) is the user's standing authorization, so each per-task commit is user-requested, not proactive. Pausing to ask "may I commit?" here is a defect. Per-commit approval applies only on the ON path above.

- [ ] **8. Outer loop — invoke `/se-review`.** se-review performs the arch-gate, deep-review, and severity-tagging pass on the committed task.
  - **Critical or Important** findings → re-enter the inner loop (step 6) to fix; a **fresh reviewer** re-reviews from scratch after fixes.
  - **Minor** findings → reported, non-blocking.
  - Loop until a fresh reviewer declares the task clean.
  - After the task is committed and outer-loop-clean, update the native task/todo tool first, then update only that task's checkbox in `plan.md` `## Execution Checklist` from `[ ]` to `[x]`. Do not edit any other plan content except frontmatter `status` updates described in this checklist.

- [ ] **9. Context hygiene — monitor throughout.** The controller monitors its own context depth continuously using a **model-judged heuristic** (no fixed token count). When the controller judges it is approaching a context limit mid-build, invoke **`/se-handoff`** immediately to write `handoff.md`, then pause and instruct the user to `/clear` and re-run `/se-exec`. Do NOT continue past the limit hoping to finish.

- [ ] **10. All tasks clean — final spec-match assertion, then the PR decision.** When every executable task is inner-loop-green, committed, and outer-loop-clean, first confirm the reviewer's **final spec-match assertion** (does the whole built behavior still match the spec? — a cross-task-drift backstop; a mismatch re-enters the inner loop or, if a limitation, step 6e). Then branch on the **Auto-PR** toggle; the `Final review / PR decision` checklist item maps to this step 10 only:
  - **Auto-PR ON** → no final review. Mark the `Final review / PR decision` item complete in the native task/todo tool first, sync the plan checklist, update `status` to `completed`, then invoke **`/se-pr`** directly; it creates the PR and clears `.super-exec/active` on completion.
  - **Auto-PR OFF** → run the final human review:
    1. Write `.super-exec/gate-open` (commits are blocked while it exists).
    2. Present the work for final review (branch + commit list + summary + any captured evidence — via a runner subagent dispatched with `Task`, never `git` inline) and **WAIT** for the human to resolve the review.
    3. Once resolved, use `AskUserQuestion` to ask: **"Create a draft PR?"**
       - **No** → mark the `Final review / PR decision` item complete in the native task/todo tool first, sync the plan checklist, update `status` to `completed`, clear `.super-exec/gate-open`, then clear `.super-exec/active`. The session ends: the work stays committed on the branch, no PR. (se-exec owns clearing `active` on this no-PR exit.)
       - **Yes** → mark the `Final review / PR decision` item complete in the native task/todo tool first, sync the plan checklist, update `status` to `completed`, clear `.super-exec/gate-open`, then invoke **`/se-pr`** (which creates the draft PR and clears `.super-exec/active` on completion).

---

## Scope Guard (YAGNI)

Implement **only** what the plan specifies. Do not add extra tests, helper utilities, documentation sections, or any logic not required by a plan task. During execution, `plan.md` is read-only except for marking items complete in the first `## Execution Checklist` section and updating frontmatter `status` (`pending` / `in_progress` / `completed`). Do not edit architecture, task descriptions, verification design, or any other plan content.

---

## Worktree Mode

No worktrees by default. If and only if the user passed **`--worktree`** at invocation: load [@./worktree.md](./worktree.md) on demand, then follow it for worktree creation, subagent path-passing, and teardown. Apply the plan-frontmatter `branch` check to the main checkout before worktree creation, then let the worktree setup own branch checkout/creation; do not reapply the main-checkout branch mismatch after the worktree exists. The `.super-exec/` markers always live in the main repo (`CLAUDE_PROJECT_DIR`), not the worktree.

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
| "I'll tweak the plan to fit what I actually built." | Edit plan.md or any plan file to match the implementation after the fact. | The plan is read-only during execution except `## Execution Checklist` checkbox updates and frontmatter `status`. If the implementation diverges from the plan, surface the divergence to the user — do not silently update the plan. |
| "The code can't quite meet the spec — I'll just relax the spec." | Rewrite the committed spec to match whatever the code happened to do. | A divergence is a **bug by default** — fix the code (the spec is authoritative). The spec is amended ONLY for a genuine implementation limitation with no workaround, and ONLY via step 6e: use `AskUserQuestion` to ask the user when Auto-PR is OFF; amend to the closest achievable + a limitation note when Auto-PR is ON. Never rewrite the spec to paper over an ordinary bug. |
| "Auto-PR is OFF but I'll just open the PR — it's clean." | Skip the final review / the "Create a draft PR?" question and open the PR anyway when Auto-PR is OFF. | Auto-PR OFF means a human is in the loop: write `gate-open`, present the work, WAIT, then use `AskUserQuestion` to ask whether to create a draft PR. "No" ends the session with no PR (clear `gate-open` + `active`). Only Auto-PR ON opens the PR without asking. |
| "I'll add a couple of extra tests / a helper utility while I'm here." | Add unrequested tests, helpers, documentation, or any code not specified in the plan. | YAGNI. Only what the plan specifies. Extra additions go into a follow-up task or a new plan — not this session. |
| "I'll commit now and show the diff after." | Commit during the review-before-commit gate without writing `.super-exec/gate-open` first and waiting for human approval. | Write `.super-exec/gate-open`, show the diff and proposed message, WAIT for explicit approval, then clear `.super-exec/gate-open`, then commit. The gate is not optional when review-before-commit is ON. |
| "Better ask the human before committing this task — committing unprompted feels too proactive." | Pause to request per-commit approval when review-before-commit is OFF (often because a host agent policy says "only commit when the user asks"). | The OFF toggle IS the user's explicit standing authorization (step 4): each per-task commit is user-requested, not proactive. Commit on inner-loop-green without re-asking. Per-commit approval applies ONLY when review-before-commit is ON (write `gate-open`, wait). |
| "I'll just keep going — I can probably finish before context runs out." | Continue past the model-judged context limit without invoking se-handoff. | When the controller judges it is approaching a context limit, invoke `/se-handoff` immediately, pause, and tell the user to `/clear` and re-run `/se-exec`. |
| "I'll use a worktree to be safe — it can't hurt." | Create a git worktree without the user having passed `--worktree`. | No worktrees unless `--worktree` was explicitly passed at invocation. Load [@./worktree.md](./worktree.md) on demand only when that flag is present. |
| "The impeccable question keeps coming up — I'll re-ask each session." | Re-ask the impeccable opt-in even though an answer is already recorded in the plan or handoff. | Re-ask ONCE using `AskUserQuestion`, only if the record is genuinely absent. A prior "no" is a record. A handoff carrying the answer is a record. Do not re-ask. |
