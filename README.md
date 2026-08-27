# super-exec

super-exec is a guided agent workflow for taking software work from a vague idea to a reviewable pull request. It ships as a Claude Code and Cursor plugin, and gives the agent a disciplined path instead of leaving each session to improvise.

Core flow:

```text
discuss -> plan -> exec -> PR / triage
```

Planning is a step, not a tax. When the work is already small and clear, super-exec skips the plan and builds in the same session:

```text
discuss -> exec -> PR / triage
```

You keep the approval points. super-exec does the research, planning, verification, review, and PR prep in between.

## Why Use It

super-exec is built for teams that want agent speed without constant babysitting:

- Turns loose intent into a reviewed spec when the work deserves one, and lets tiny changes to an existing feature build straight from the settled interview answers.
- Separates WHAT from HOW, then builds from the agreed spec or plan.
- Keeps heavy searches, builds, tests, and reviews out of the main session when possible.
- Proves working increments through normal user or distributable paths; tests, mocks, and scripted states support that proof but do not replace it.
- Prefers the target repo's own skills and conventions for branches, commits, PRs, tests, and local dev.
- Keeps execution artifacts local by default, with per-feature placement — spec and plan, team or local — configurable via `se-config`.

## Install

Install it per repo:

```text
/plugin marketplace add mek-earnin/super-exec
/plugin install super-exec
```

Open a session in the target repo after install; super-exec orients itself from the repo and plugin context.

### Optional Plugins

super-exec is self-contained. These plugins improve specific workflows when present, and are skipped when absent:

| Plugin | Adds |
|---|---|
| `impeccable` | UI design, build, and critique help for frontend work. |
| `caveman` | Terse, high-signal agent communication. |

If `superpowers` is also installed, super-exec is intended to drive the feature workflow where the two overlap. superpowers remains useful for areas outside that workflow, such as standalone debugging.

## Workflow

### 1. Discuss

Run `/se-discuss` when starting a new feature or behavior change. The agent asks only questions that still change requested behavior, priority, or acceptance; “proceed,” “implement,” and corrections stop obsolete questions immediately. Specs distinguish core user requests from approved derived requirements and deferred concerns.

Not every change earns a durable spec. New features always get one, and an existing feature that already has a spec gets that spec updated — but tiny work on an existing feature can skip the spec entirely and execute from the settled interview answers, which govern the build in its place.

### 2. Plan (when it helps)

Planning turns the approved spec into architecture contracts, outcomes, dependencies, requirement traceability, and runtime proof paths. File maps remain design evidence; execution can choose working increments without changing approved behavior. When architecture and data flow would not improve the implementation, the agent recommends skipping the plan instead of spending tokens on it — you can always ask for one.

### 3. Exec

Run `/se-exec` in a fresh session after a plan, or in the same session right after discuss when the plan was skipped. The agent selects smallest coherent end-to-end working increments, uses focused checkpoint commits for enabling work, and runs full baseline/runtime proof plus deep review only at increment boundaries. Later approved requirements stay pending until their increment, then all remain required before final completion. A verified technical limitation stops completion and PR creation until a human approves the governing-spec resolution (and re-plans an architecture change); Auto-PR does not bypass that gate.

### 4. PR / Triage

The workflow can open a draft PR when the build is ready. After a PR exists, `/se-pr-triage` helps process review comments and CI failures without mixing post-PR work back into the build session. Review-comment decisions and fixes are approved first; exact final replies are previewed and approved separately after fixes are pushed.

## Entrypoints

| Entrypoint | Use it for |
|---|---|
| `/se-discuss` | Start from an idea, ticket, or desired change and produce a reviewed spec — or, for small work, go straight to building. |
| `/se-plan` | Re-enter or revise planning for an existing spec. |
| `/se-exec` | Build from a reviewed plan, or from the spec or agreed task when planning was skipped; verify the work, review it, and prepare the PR. |
| `/se-pr-triage` | Handle review comments through separate fix and final-reply approvals, plus autonomous CI triage. |
| `/se-config` | Inspect or set placement and behavior config (tiered), and migrate a v0 repo to the v1 layout. |

Most users start with `/se-discuss`, then follow the prompts. You can also describe the work naturally and let the agent choose the matching entrypoint.

## Configuration & migrating to v1

Artifact placement and two workflow gates are controlled by a small tiered config, `se-config`. Four keys:

| Key | Controls | Values |
|---|---|---|
| `commitSpec` | New-spec root — committed `docs/specs/` (team) vs. local `.super-exec/specs/`. Existing updates keep their current root. | - `"ask"` (default) — prompt when creating a spec<br>- `true` — commit new specs under `docs/specs/`<br>- `false` — keep new specs local under `.super-exec/specs/` |
| `commitPlan` | Plan root. | - `"ask"` (default) — prompt at plan-write time<br>- `false` — keep the plan local<br>- `"inheritSpec"` — follow the spec's root (never commits a plan whose spec is local) |
| `humanReviewBeforeCheckpointCommit` | Human approval before each supporting-checkpoint commit. | - `"ask"` (default) — prompt at `/se-exec` start<br>- `true` — always require approval<br>- `false` — commit after focused review without another prompt |
| `autoCreatePr` | Auto-open a PR after final completion. | - `"ask"` (default) — prompt at `/se-exec` start<br>- `true` — auto-open after final checks<br>- `false` — ask at final review; do not auto-create |

Values merge over three tiers: repo-local `.super-exec/se-config.local.json` > user `~/.super-exec/se-config.json` > shipped defaults. Manage them with `/se-config print` (the effective config plus any local and user overrides) and `/se-config set <local|user> <key> <value>`.

**v1 layout** is slug-only and per-feature (no running numbers):

- Spec — `<root>/[<app>/]<feature>/spec-<feature>.md`
- Plan — `<root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md`
- Global ADRs stay in `docs/adr/<slug>.md`.

**Upgrading a v0 repo** (numbered `docs/specs/NNNN-*.md`, `.super-exec/NNNN-*/…`): run `/se-config migrate` to preview the moves (dry-run, changes nothing), then `/se-config migrate --apply` to move the files (`git mv` for tracked files, `mv` for untracked), strip the running numbers, and rewrite the `Spec:` / `Plan:` cross-pointers and the active session marker.

## Artifacts

Specs and plans use a slug-only, per-feature layout. `se-config` chooses new-artifact roots: committed under `docs/specs/` for the team, or kept local under `.super-exec/specs/` (gitignored). Existing spec updates stay in their current root without another placement prompt. Handoffs and separate `deferred-findings-<plan-name>.md` ledgers follow the plan's root; with no plan, the handoff stays local. Session state (the active marker and gate files) always stays under `.super-exec/`.

Detailed workflow contracts and implementation-specific behavior live in the source-of-truth files:

- `docs/specs/core-workflow/spec-core-workflow.md`
- `plugin/skills/*/SKILL.md`
- skill-owned templates and reference files under `plugin/skills/`

Keep this README as a landing page. If workflow details change, update the spec and skills first.
