---
name: se-handoff
description: Use when /se-exec is approaching a context limit mid-build and must hand off to a fresh session.
---

# se-handoff

Use when continuation risks losing coherence or evidence. Write `handoff-<plan-name>.md`; fresh session resumes active increment, not plan-task order. Controller/strong tier writes it.

---

## Mandatory Ordered Checklist

1. **Detect threshold.** Model judgment, no fixed token count. Handoff before evidence/coherence loss.

2. **Gather the resume state.**
   Collect the following from the current session:
   - Active increment: outcome, requirements, state, review/delivery identity, normal-path demonstration, evidence.
   - Supporting checkpoints: status, focused evidence, focused review, and commit/revision.
   - Pending requirements: traceability IDs and reason.
   - Ledger reference/path/status only; never rows.
   - The two session toggles: **review-before-commit** (on/off) and **Auto-PR** (on/off).
   - UI-plan state, branch/base, corrections, cancellation, re-slicing, dependencies, in-flight work.
   Reconcile outcome status, todos, checkboxes, plan/terminal state. Check only completed work packages.

3. **Write the handoff file.**
   Path: plan folder, `handoff-<plan-name>.md`, under plan root. Use template; write `None.` when empty.

4. **Pause and instruct the user.**
   After writing, output exactly these two instructions:
   > Handoff written. Run `/clear` to start a fresh session, then run `/se-exec` to resume. The next session will restore **[active working increment outcome]**.

   Do not continue executing plan tasks after writing the handoff.

5. **Do NOT clear `.super-exec/active`.**
   The session is resuming, not ending. `active` must remain set so the session-start hook and /se-exec can detect the in-progress plan and load the handoff. Active-marker lifecycle: **/se-pr** clears `active` on PR completion; **/se-exec** clears it on the no-PR exit (Auto-PR OFF + human declines the draft PR); **/se-pr-triage** writes and clears `active` for its separate post-PR triage round; **se-handoff never clears `active`.**

---

## Red-Flag Table

| If you observe this… | The correct action |
|---|---|
| "I'll just keep going past the context limit" | Write the handoff and pause. Coherence lost mid-task is worse than a clean resume. |
| "I'll write the handoff to `.super-exec/` root" | Wrong path. Must go into the active plan dir: `<root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/handoff-<plan-name>.md`. |
| "I'll clear `active` so the next session starts clean" | Never. `active` must stay set; se-handoff never clears it. The resume flow depends on `active` pointing to the in-progress plan. |
| "The next agent can infer state from task order or git log" | No. Record active increment, checkpoints, runtime evidence, pending requirements, deferred-ledger reference/status, and corrections explicitly. |
| "I'll wait for a fixed token count before triggering" | No fixed number. The threshold is model-judged. Trigger when you judge that continuing risks losing coherence or truncating evidence — not at a predetermined count. |
| "I'll summarize the handoff from memory without checking the plan" | Open the plan file (`plan-<plan-name>.md`) with `Read` and verify task names and order before writing. Stale or misremembered task names break the resume. |

---

## Model and Tool Assignments

| Role | Assignment |
|---|---|
| Controller / handoff author (judgment, state capture) | strong / controller tier (see the `/se-subagent` skill) |

Writing the handoff is controller work — same judgment tier that drives the build session. Do not delegate handoff authoring to a cheaper tier.
