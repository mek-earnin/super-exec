---
name: using-super-exec
description: Use when starting any new feature, fix, or task — super-exec orients you on the gate-driven workflow and its three entrypoint skills.
---

# super-exec

super-exec is a gate-driven `spec → plan → execute → verify → review → PR` workflow plugin for Claude Code. It enforces discipline at every stage so sessions produce shippable work, not half-finished attempts.

## The three entrypoint skills

super-exec ships as **skills only** — no separate slash commands. Each entrypoint is a skill you
invoke as `/se-shape`, `/se-plan`, or `/se-exec` (or that the model auto-invokes when the work
matches); on entry each writes the `.super-exec/active` session marker that makes the guards live.
Behavior is identical whether invoked manually or automatically.

- `/se-shape` — **Design session.** Shape a spec from a raw idea or task description. Produces a structured spec document that gates entry to planning.
- `/se-plan` — **Plan / re-plan / re-entry.** Turn a spec into an architecture + verification plan, or re-enter an in-progress plan mid-session. Gates entry to execution.
- `/se-exec` — **Build session.** Execute the current plan task by task, with verification checkpoints between tasks. Does not proceed past a failing gate.

## Core enforced discipline

- **Delegate heavy work to subagents.** Exploration, research, and parallel file edits go to agents — keep the main thread for decisions and verification.
- **Verify before claiming done.** Run the actual check (tests, linter, type-check, build) and paste the output. Assertions without evidence are rejected.
- **Scope guard.** Each session works only the steps in the current plan. Out-of-scope changes are deferred, not sneaked in.
- **Reuse before writing.** Search the codebase for existing patterns, utilities, and conventions before adding new ones.
- **Repo conventions win.** Follow the project's existing style, tooling, and structure — do not impose external preferences.
- **No auto-commit, no PR without a draft.** Commits and PRs are explicit user actions, not automatic session epilogues.

## Workflow is gate-driven

Each stage produces an artifact. The next stage checks that artifact before proceeding. A stage cannot be skipped. If a gate fails, the workflow returns to the previous stage rather than continuing.
