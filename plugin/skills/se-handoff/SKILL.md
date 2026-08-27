---
name: se-handoff
description: Use when /se-exec is approaching a context limit mid-build and must hand off to a fresh session.
---

# se-handoff

Use when continuation risks losing coherence or evidence. Plan-backed: write `handoff-<plan-name>.md` in the plan folder. Skip-plan: no plan folder exists — write `.super-exec/handoff-<feature>.md`. Fresh session resumes active increment, not plan-task order. Controller/strong tier writes it.

---

## Mandatory Ordered Checklist

1. **Detect threshold.** Model judgment, no fixed token count. Handoff before evidence/coherence loss.

2. **Gather the resume state.**
   Collect the following from the current session:
   - Active increment: outcome, requirements, state, review/delivery identity, normal-path demonstration, evidence.
   - Supporting checkpoints: status, focused evidence, focused review, and commit/revision.
   - Pending requirements: traceability IDs and reason.
   - Ledger reference/path/status only; never rows; skip-plan with no ledger records none.
   - Skip-plan: the governing spec path from `.super-exec/active` `spec:`. If that value is the `task-spec` sentinel or names no existing file, the work is crossing a session boundary with nothing durable — write the session-boundary spec under `.super-exec/specs/` now (no approval needed, never commit it), repoint marker `spec:` at it, and record that path here. `/se-exec` resume reads it.
   - The two session toggles: **review-before-commit** (on/off) and **Auto-PR** (on/off).
   - UI-plan state, branch/base, corrections, cancellation, re-slicing, dependencies, in-flight work.
   Reconcile outcome status, todos, checkboxes, plan/terminal state. Check only completed work packages.

3. **Write the handoff file.**
   Plan-backed path: plan folder, `handoff-<plan-name>.md`, under plan root. Skip-plan path: `.super-exec/handoff-<feature>.md`, feature slug from the governing spec or task spec. Use template; write `None.` when empty; omit plan-only rows on skip-plan.

4. **Pause and instruct the user.**
   After writing, output exactly these two instructions:
   > Handoff written. Run `/clear` to start a fresh session, then run `/se-exec` to resume. The next session will restore **[active working increment outcome]**.

   Do not continue executing plan tasks after writing the handoff.

5. **Do NOT clear `.super-exec/active`.**
   The session is resuming, not ending. `active` must remain set so the session-start hook and /se-exec can detect the in-progress plan and load the handoff. Skip-plan must additionally leave `mode: skip-plan` and the resolved `spec:` in place — dropping `mode: skip-plan` makes the next session read the marker as plan-backed and hunt a stale plan on disk. Active-marker lifecycle: **/se-pr** clears `active` on PR completion; **/se-exec** clears it on the no-PR exit (Auto-PR OFF + human declines the draft PR); **/se-pr-triage** writes and clears `active` for its separate post-PR triage round; **se-handoff never clears `active`.**

---

## Red-Flag Table

| If you observe this… | The correct action |
|---|---|
| "I'll just keep going past the context limit" | Write the handoff and pause. Coherence lost mid-task is worse than a clean resume. |
| "Plan-backed run, so I'll write the handoff to `.super-exec/` root" | Wrong path. Must go into the active plan dir: `<root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/handoff-<plan-name>.md`. |
| "Skip-plan run, so I'll invent a plan dir for the handoff" | Never fabricate a plan folder or plan name. Skip-plan MUST write `.super-exec/handoff-<feature>.md`. |
| "Skip-spec run with no spec file — the handoff can just describe the agreed task" | The interview does not survive `/clear`. Write the session-boundary spec under `.super-exec/specs/`, repoint marker `spec:` at it, then hand off. |
| "I'll clear `active` so the next session starts clean" | Never, plan-backed or skip-plan. `active` must stay set; se-handoff never clears it. The resume flow depends on `active` pointing to the in-progress work. |
| "The next agent can infer state from task order or git log" | No. Record active increment, checkpoints, runtime evidence, pending requirements, deferred-ledger reference/status, and corrections explicitly. |
| "I'll wait for a fixed token count before triggering" | No fixed number. The threshold is model-judged. Trigger when you judge that continuing risks losing coherence or truncating evidence — not at a predetermined count. |
| "I'll summarize the handoff from memory without checking the plan" | Open the plan file (`plan-<plan-name>.md`) with `Read` and verify task names and order before writing; skip-plan reads the governing spec or task spec instead. Stale or misremembered names break the resume. |

---

## Model and Tool Assignments

| Role | Assignment |
|---|---|
| Controller / handoff author (judgment, state capture) | strong / controller tier (see the `/se-subagent` skill) |

Writing the handoff is controller work — same judgment tier that drives the build session. Do not delegate handoff authoring to a cheaper tier.
