---
name: se-subagent
description: Internal reference for super-exec skills — the canonical Claude Code model tier for each subagent role (strong / mid / cheap) and the subagent-dispatch discipline (the Task tool, the runner→judge verify split, file-disjoint parallelism, and keeping the controller lean). Load this whenever a super-exec skill is about to dispatch a subagent or pick a model. Not user-invokable.
user-invocable: false
---

# se-subagent — subagent dispatch & model tiers (super-exec internal)

super-exec skills name a model **tier** in prose — "a strong-tier reviewer", "a cheap runner", "a mid-tier implementer". This file resolves those tiers to a concrete model and defines how to dispatch. It is written in **Claude Code language**; under Cursor, translate the models and the dispatch primitive via [cursor-tools.md](../using-super-exec/references/cursor-tools.md).

## Role → model (Claude Code)

Set the model with the family **alias**, not a pinned version string. Aliases (`opus` / `sonnet` / `haiku`) always resolve to the latest model in that family, so this table never goes stale — there is intentionally no `-x-y` version suffix to maintain.

| Tier (prose alias) | Roles | Model alias |
|---|---|---|
| **strong** (strong non-fast / arch model / judge) | discuss interview, plan, arch-gate & deep review, impeccable-critique, verifier judgment, handoff authoring | `opus` (non-fast) |
| **mid** (implementer / fixer) | implementer, fixer, mid-scope edits | `sonnet` (**pinned — see below**) |
| **cheap** (script-runner / runner / finder / investigator) | run lint/build/tests, locate code, enumerate the skill catalog, run git/`gh` | `haiku` |

Dispatch every subagent with the **`Task` tool**, setting `model` explicitly to the tier's alias. A general-purpose subagent uses `Task` with no `subagent_type`; a typed agent passes `subagent_type`.

## Runner → judge verify split

All verification splits into **two separate subagent contexts** — nothing runs inline in the controller:

1. **Runner (cheap / `haiku`)** — executes the baseline suite + task-specific checks in its own throwaway context and returns only structured **EVIDENCE** (exit codes, pass/fail counts, relevant log excerpts, screenshot paths). It never interprets results; raw build/test output never enters the controller's context.
2. **Judge / verifier (strong / `opus`)** — evaluates that EVIDENCE against the spec + plan and renders an explicit PASS/FAIL with specific findings. This is the only role that reasons about correctness.

Rule: the controller dispatches, waits for the runner's evidence summary, then dispatches the judge. No verification logic runs inline.

## Pinned-to-Sonnet policy (implementer / fixer)

On Claude Code the implementer and fixer tiers are **pinned to `sonnet`** regardless of the user's session model. Skills that spawn an implementer or fixer **must set `model` explicitly to `sonnet`** — never inherit or omit it. Rationale: the session model may be `opus` (planning/review) or `haiku` (script-running); neither is right for editing code at mid-task scope. Pinning prevents cost blowout (Opus writing every file) and context degradation (Haiku making structural calls it can't reason through). On Cursor the equivalent is "latest composer non-fast" (its model selection is less granular, so non-fast inheritance is acceptable).

## Dispatch discipline

- **Delegate by default.** Build, test, wide search, long review, and git/`gh` run in subagents that report a summary — never inline in the controller.
- **Parallelism rule.** Independent tasks that touch **completely disjoint file sets** may be dispatched in parallel. Any two tasks sharing even one file run sequentially. When in doubt, sequential.
- **Targeted context.** Give a fixer only the specific finding + the relevant acceptance criteria + the plan's architectural context — never the full review.
- **Controller stays lean.** Raw file diffs and raw command output stay in the subagent; only summaries and evidence cross back.
