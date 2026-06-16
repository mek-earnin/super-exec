# Model Tiers

Skills read this file to resolve abstract role names (e.g. "strong non-fast reviewer",
"cheap script-runner") to concrete model identifiers per harness. Never hardcode a model
name in a skill — quote the role name and let this table drive the lookup.

## Role → Model Table

| Role | Claude Code (CC) | Cursor |
|---|---|---|
| **Shape interview · Plan · Review** (arch-gate / deep-review / impeccable-critique) · **verifier judgment** | `claude-opus-4-5` (strong, non-fast) | Default / inherit (non-fast) |
| **Implementer · Fixer** · mid tasks | `claude-sonnet-4-5` (PINNED — see policy below) | latest composer non-fast (e.g. `composer-2.5`) |
| **Script-runner** · Finder / Investigator (run lint/build/tests, locate code, enumerate catalog) | `claude-haiku-4-5` | latest composer non-fast |

> **Alias reference used in skill prose**
>
> | Prose alias | Resolves to (CC) | Resolves to (Cursor) |
> |---|---|---|
> | strong non-fast / arch model / judge | Opus | Default / inherit |
> | implementer / mid | Sonnet | composer non-fast |
> | cheap script-runner / runner / investigator | Haiku | composer non-fast |

---

## Runner → Judge Verify Split

All verification is **split into two separate contexts**; nothing runs inline in the
controller task.

1. **Runner (cheap)** — Haiku on CC / composer-non-fast on Cursor.
   Executes the verification scripts (baseline suite + task-specific checks) in its own
   throwaway subagent context. Returns only structured **EVIDENCE** (exit codes, counts,
   relevant log excerpts) to the primary context. Raw build/test output never enters the
   controller's context window.

2. **Verifier / Judge (strong)** — Opus on CC / default-inherit on Cursor.
   Evaluates the EVIDENCE returned by the runner against the spec and the execution plan.
   Renders the pass/fail judgment and surfaces actionable findings. This is the only role
   that reasons about correctness — the runner never interprets results.

**Rule: no verification logic runs inline in the controller.** The controller dispatches,
waits for the runner's evidence summary, then dispatches the judge if needed.

---

## CC Implementer / Fixer — Pinned-to-Sonnet Policy

On Claude Code the implementer and fixer tiers are **pinned to Sonnet** regardless of the
model the user has selected for their session. This is a deliberate role-based policy:

- The session model may be Opus (used for planning/review/judgment) or Haiku (used for
  script-running). Neither is appropriate for editing code at mid-task scope.
- Pinning prevents accidental cost blowout (Opus writing every file) and context
  degradation (Haiku making structural decisions it cannot reason through).
- Skills that spawn an implementer or fixer subagent on CC **must** set the model
  explicitly to Sonnet; they must not inherit or omit the model field.

On Cursor the equivalent constraint is expressed as "use the latest composer non-fast
model" — Cursor's composer model selection is less granular, so inheritance from the
non-fast tier is acceptable.
