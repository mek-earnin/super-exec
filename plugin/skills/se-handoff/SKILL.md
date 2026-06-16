---
name: se-handoff
description: Use when se-exec judges it is approaching a context limit mid-build — writes a handoff.md into the active plan dir so a fresh session can resume from the next unstarted task with zero re-litigation.
---

# se-handoff

The established cross-harness resume mechanism. se-exec invokes se-handoff when the controller judges — through a **model-judged heuristic, not a fixed token count** — that continuing would risk losing coherence or truncating verification evidence. The output is a single `handoff.md` that captures every piece of state a fresh session needs to resume without re-litigating anything.

Writing the handoff is **controller/strong-tier work**: it requires judgment about what state matters, what evidence is trustworthy, and what decisions were made during the session. For tier definitions, see the `se-subagent` skill.

---

## Mandatory Ordered Checklist

Work through every step in order. Do not skip or reorder.

1. **Detect the threshold (model-judged).**
   Assess whether continuing the build would risk coherence, context truncation, or loss of verification evidence. There is no fixed token count or percentage — this is a judgment call. When in doubt, write the handoff rather than push through. A handoff written early is recoverable; a handoff written too late may lose evidence.

2. **Gather the resume state.**
   Before writing, collect the following from the current session:
   - Every task that is DONE, paired with its verification evidence summary (exit codes, test counts, key log excerpts — enough for the next session to trust it without re-running).
   - The **exact next unstarted task** (by name and position in the plan).
   - The two session toggles: **review-before-commit** (on/off) and **Auto-PR** (on/off).
   - The **impeccable opt-in** answer recorded at session start (opted-in / opted-out / not asked).
   - The **branch name** and **base branch**.
   - Any in-flight context or decisions made during the session that are not captured in committed code or the plan (e.g., a design choice that was resolved mid-task, a dependency discovered, a scope clarification from the user).
   - Any open follow-ups or deferred items that must not be forgotten.

3. **Write the handoff file.**
   Path: `.super-exec/<feature>/<plan-dir>/handoff.md` — the same directory that contains the `plan.md` being executed. Never write to `.super-exec/` root or anywhere else. Use the `Write` tool. See [handoff-outline.md](./handoff-outline.md) for the required sections.

4. **Pause and instruct the user.**
   After writing, output exactly these two instructions:
   > Handoff written. Run `/clear` to start a fresh session, then run `/se-exec` to resume. The next session will pick up from **[next unstarted task name]**.

   Do not continue executing plan tasks after writing the handoff.

5. **Do NOT clear `.super-exec/active`.**
   The session is resuming, not ending. `active` must remain set so the session-start hook and se-exec can detect the in-progress plan and load the handoff. Active-marker lifecycle: **se-pr** clears `active` on PR completion; **se-exec** clears it on the no-PR exit (Auto-PR OFF + the human declines the draft PR); **se-handoff never clears `active`.**

---

## Red-Flag Table

| If you observe this… | The correct action |
|---|---|
| "I'll just keep going past the context limit" | Write the handoff and pause. Coherence lost mid-task is worse than a clean resume. |
| "I'll write the handoff to `.super-exec/` root" | Wrong path. It must go into the active plan dir: `.super-exec/<feature>/<plan-dir>/handoff.md`. |
| "I'll clear `active` so the next session starts clean" | Never. `active` must stay set. se-handoff never clears it. The resume flow depends on `active` pointing to the in-progress plan. |
| "The next agent can figure out what's done from git log" | No. Record completed tasks and their verification evidence explicitly in the handoff. The next session must not re-run or re-litigate finished work. |
| "I'll wait for a fixed token count before triggering" | There is no fixed number. The threshold is model-judged. Trigger when you judge that continuing risks losing coherence or truncating evidence — not at a predetermined count. |
| "I'll summarize the handoff from memory without checking the plan" | Open `plan.md` with `Read` and verify task names and order before writing. Stale or misremembered task names break the resume. |

---

## Model and Tool Assignments

| Role | Assignment |
|---|---|
| Controller / handoff author (judgment, state capture) | strong / controller tier (see the `se-subagent` skill) |

Writing the handoff is controller work — it requires the same judgment tier that drives the build session. Do not delegate handoff authoring to a cheaper tier.
