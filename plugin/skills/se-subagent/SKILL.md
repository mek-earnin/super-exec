---
name: se-subagent
description: MUST use BEFORE dispatching a subagent or picking a model tier. 
user-invocable: false
---

# se-subagent — subagent dispatch & model tiers (super-exec internal)

super-exec skills name a model **tier** in prose — "a strong-tier reviewer", "a cheap runner", "a mid-tier implementer". This file maps tiers → concrete model + how to dispatch. Written in **Claude Code language**; under Cursor, translate models + dispatch primitive via [cursor-tools.md](../using-super-exec/references/cursor-tools.md).

## Role → model (Claude Code)

Set model by family **alias**, not pinned version string. Aliases (`opus` / `sonnet` / `haiku`) resolve to latest in family → table never goes stale, no `-x-y` suffix to maintain.

| Tier (prose alias) | Roles | Model alias |
|---|---|---|
| **strong** (strong non-fast / arch model / judge) | discuss interview, plan, arch-gate & deep review, impeccable-critique, verifier judgment, handoff authoring | `opus` (non-fast) |
| **mid** (implementer / fixer) | implementer, fixer, mid-scope edits | `sonnet` (**pinned — see below**) |
| **cheap** (script-runner / runner / finder / investigator) | run lint/build/tests, locate code, enumerate the skill catalog, run git/`gh` | `haiku` |

Dispatch every subagent with the **`Task` tool**, setting `model` explicitly to the tier's alias. General-purpose subagent: `Task` with no `subagent_type`; typed agent passes `subagent_type`.

## Runner → judge verify split

`/se-verify` owns verification packet and verdict semantics. Dispatch preserves its canonical verdict unchanged; controller handles flow from that verdict, never re-labels it.

1. **Runner (cheap / `haiku`)** — runs `/se-verify` scope against review identity; returns structured evidence only.
2. **Judge (strong / `opus`)** — evaluates evidence against spec/plan; renders exact `PASS`, `FAIL`, or `LIMITATION`. Reject changed content. `/se-commit` decides delivery equivalence.

Controller dispatches runner, then judge; no inline verification. `PASS` and `FAIL` follow `/se-verify`; `LIMITATION` reaches `blocked-limitation` immediately and never enters fixer loop.

## Pinned-to-Sonnet policy (implementer / fixer)

On Claude Code the implementer and fixer tiers are **pinned to `sonnet`** regardless of the user's session model. Skills that spawn an implementer or fixer **must set `model` explicitly to `sonnet`** — never inherit or omit it. Rationale: the session model may be `opus` (planning/review) or `haiku` (script-running); neither is right for editing code at mid-task scope. Pinning prevents cost blowout (Opus writing every file) and context degradation (Haiku making structural calls it can't reason through). On Cursor the equivalent is latest cursor-grok-* high (e.g. `cursor-grok-4.5-high`; see `using-super-exec/references/cursor-tools.md` for the full tier mapping).

## Dispatch discipline

- **Delegate by default.** Build, test, wide search, long review, and git/`gh` → subagents that report a summary; never inline in the controller.
- **Parallelism rule.** Independent tasks that touch **completely disjoint file sets** may be dispatched in parallel. Any two tasks sharing even one file run sequentially. When in doubt, sequential.
- **Targeted context.** Fixer gets finding, acceptance, relevant architecture—not full review. Every packet includes review identity; other evidence is stale.
- **Controller stays lean.** Raw file diffs and raw command output stay in the subagent; only summaries and evidence cross back.
