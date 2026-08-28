---
name: using-super-exec
description: Use when starting any new feature, fix, or task — orientation to the super-exec workflow and its entrypoints.
---

# super-exec

Full workflow vague idea → PR — less babysitting, enforced discipline, repo conventions preserved. Runs `spec → [plan] → execute → verify → review → PR` → sessions ship real work, not half-finished attempts. Plan is optional: **skip-plan** when work is already small and clear, so architecture/data-flow planning would not improve implementation.

**Reach for these proactively.** User starts feature work — "let's build X", "add Y", "change how Z works" — invoke `/se-discuss`, don't dive into code. Then either skip-plan → `/se-exec` in the same session, or `/se-plan` → `/se-exec` in a fresh session. Don't need user to name the skill. Match work to stage, use it. (Trivial one-line fixes skip the full workflow — judge when it fits.)

## The four entrypoint skills

Ships as **skills only** — no separate slash commands. Invoke each as `/se-discuss`, `/se-plan`, `/se-exec`, or `/se-pr-triage` (or the model auto-invokes on match). On entry each writes the `.super-exec/active` session marker → guards live. Behavior identical whether invoked manually or automatically.

- `/se-discuss` — **Design session.** From a raw idea or task description, interview to one or more reviewed specs (one per cohesive feature — a multi-feature session splits into separate specs with your confirmation). After the first approval it shows the next step: skip-plan → `/se-exec` in this same session, or `/se-plan`. Work too small to record a spec is **skip-spec**: settled interview answers are the task spec, and `/se-exec` auto-invokes in this session with no plan and no spec gate. Specs land under a config-driven root (`docs/specs/` committed or `.super-exec/specs/` local) as `<root>/[<app>/]<feature>/spec-<feature>.md` (slug-only).
- `/se-plan` — **Plan / re-plan / re-entry.** Turn a spec into an architecture + verification plan, revise an existing plan, or (no argument) pick up the next unplanned spec from a split. Plans land under either root as `<root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md`. The **plan → execute boundary stays a hard fresh-session step** — never auto-chained.
- `/se-exec` — **Build session.** Builds from a reviewed plan, or on skip-plan from the approved spec or task spec — a ready plan and ledger are not the only entry. Select smallest working increments from those outcomes, prove them through normal user paths, and use supporting checkpoints for focused progress. Owns resume, durable increment state, commit cadence, and final PR/no-PR decision.
- `/se-pr-triage` — **Post-PR triage session.** Manual entrypoint; not auto-chained from `/se-pr`. Runs one loop-safe triage round: Track A first gates review-comment decisions and Fix scope, then after successful pushes separately gates the exact final replies before posting; Track B investigates and resolves CI failures autonomously with no PR replies. Neither Track A gate auto-approves under `/loop`.

## Config & support skills

- `/se-config` — **User-facing config command.** Print, write, and migrate the tiered `se-config.json` (local / user / default). Model-invocation disabled; no other skill references it.
- `/se-get-config` — **Internal merge authority** (`user-invocable: false`). Returns the merged effective config as JSON; skills that decide commit, placement, review, or PR consult it.
- `/se-slug-naming` — **Internal naming convention** (`user-invocable: false`). Caveman-compressed slug rule for feature/spec/ADR slug and plan-name; authoring skills reference it rather than restating.

## Precedence (if superpowers is also loaded)

<EXTREMELY_IMPORTANT>
If the `superpowers` plugin is also loaded this session, super-exec and superpowers overlap and compete for the same triggers ("let's build X", "add Y", "change Z"). super-exec is self-contained and owns the development workflow: **wherever the two overlap, drive the work through the super-exec spine, not superpowers' equivalent.** This binds you as the controller AND every subagent you dispatch.

Use super-exec, not superpowers, for:
- discussing → `/se-discuss` (not `superpowers:brainstorming`)
- planning → `/se-plan` (not `superpowers:writing-plans`)
- building → `/se-exec` (not `superpowers:executing-plans` / `superpowers:subagent-driven-development`)
- verifying → `/se-verify` (not `superpowers:verification-before-completion`)
- reviewing → `/se-review` (not `superpowers:requesting-code-review` / `superpowers:receiving-code-review`)
- worktree isolation → `/se-exec` (not `superpowers:using-git-worktrees`)
- finishing / PR → `/se-pr` (not `superpowers:finishing-a-development-branch`)
- subagent dispatch → `/se-subagent` (not `superpowers:dispatching-parallel-agents`)

TDD is a technique used *inside* `/se-verify` / `/se-exec`, not a competing driver.

superpowers stays available for needs super-exec does not cover — e.g. `superpowers:systematic-debugging`, `superpowers:find-skills`, `superpowers:writing-skills`. Use them freely there; the override is scoped to the overlap above, not a blanket "ignore superpowers".

This is a **best-effort** override that wins by **specificity, not volume**: it names superpowers and the exact mapping. Do not try to out-rank superpowers by escalating wrapper names (`EXTREMELY_IMPORTANT_PRO_MAX`, `_ULTRA`, …) — the tag name is a delimiter, not a priority dial. When superpowers is absent, this section is a no-op.
</EXTREMELY_IMPORTANT>

## Core enforced discipline

- **Delegate heavy work to subagents.** Exploration, research, parallel file edits go to agents — keep the main thread for decisions and verification.
- **Verify before claiming done.** Working increments need full baseline plus normal user/distributable-path evidence; lower-layer, mocked, and scripted checks remain supporting evidence.
- **Scope guard.** Each session works only what the current plan — or on skip-plan the governing spec or task spec — covers. Out-of-scope changes are deferred, not sneaked in.
- **Reuse before writing.** Search the codebase for existing patterns, utilities, conventions before adding new ones.
- **Repo conventions win.** Follow the project's existing style, tooling, structure — don't impose external preferences.
- **Commit routinely; pending human review is the only block.** Supporting-checkpoint commits are part of the workflow, but never commit while a human review is pending (`.super-exec/gate-open`). The detailed toggle and host-policy resolution lives in `/se-exec` and the harness reference docs.

## Staged workflow

Each stage produces durable evidence. Supporting checkpoints stay focused; working-increment and final boundaries prove behavior end-to-end. User corrections override stale in-flight work immediately.

## Authoring & cross-harness note

Skills authored in **Claude Code language** — CC tool names (`Read`, `Edit`, `Write`, `Task`, `AskUserQuestion`, `TodoWrite`), model aliases (`opus` / `sonnet` / `haiku`), hook event names. Individual skills don't branch by harness; non-CC environments translate through `references/cursor-tools.md`.

- **Model tiers** resolve through the `/se-subagent` skill (`user-invocable: false`), which holds the canonical role → tier table and subagent-dispatch discipline. Skills name a tier ("strong", "mid", "cheap") in prose; `/se-subagent` maps it to a model alias.
- **Keeping `.super-exec/` out of git** is owned by the `/se-local-ignore` skill (`user-invocable: false`); each driver skill applies it at session activation, right after writing `.super-exec/active`. It updates the repo-local, uncommitted `.git/info/exclude` (never the team `.gitignore`). The SessionStart hook is only a best-effort redundant pass.
- **Running under Cursor?** The SessionStart hook injects [references/cursor-tools.md](./references/cursor-tools.md), the single CC→Cursor map. Apply it.
