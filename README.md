# super-exec

super-exec is a guided agent workflow for taking software work from a vague idea to a reviewable pull request. It ships as a Claude Code and Cursor plugin, and gives the agent a disciplined path instead of leaving each session to improvise.

Core flow:

```text
discuss -> plan -> exec -> PR / triage
```

You keep the approval points. super-exec does the research, planning, verification, review, and PR prep in between.

## Why Use It

super-exec is built for teams that want agent speed without constant babysitting:

- Turns loose intent into a reviewed spec before implementation starts.
- Separates WHAT from HOW, then builds from that agreed plan.
- Keeps heavy searches, builds, tests, and reviews out of the main session when possible.
- Verifies with real evidence before claiming work is done.
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

Run `/se-discuss` when starting a new feature or behavior change. The agent interviews you until the problem, goals, non-goals, requirements, domain terms, and key decisions are clear. The output is one or more specs (one per cohesive feature) you review before the workflow moves on — when a single conversation covers several distinct features, super-exec proposes splitting it into a spec per feature and plans them one at a time.

### 2. Plan

Planning turns the approved spec into an implementation and verification plan. It covers architecture, task shape, reuse opportunities, repo skills to invoke, and the evidence needed to prove the work. You review the plan before build work begins.

### 3. Exec

Run `/se-exec` in a fresh session when ready to build. The agent works task by task through implementation, verification, review, fixes, and PR preparation. It keeps the spec and plan as the source of truth for scope.

### 4. PR / Triage

The workflow can open a draft PR when the build is ready. After a PR exists, `/se-pr-triage` helps process review comments and CI failures without mixing post-PR work back into the build session. Review-comment decisions and fixes are approved first; exact final replies are previewed and approved separately after fixes are pushed.

## Entrypoints

| Entrypoint | Use it for |
|---|---|
| `/se-discuss` | Start from an idea, ticket, or desired change and produce a reviewed spec. |
| `/se-plan` | Re-enter or revise planning for an existing spec. |
| `/se-exec` | Build from a reviewed plan, verify the work, review it, and prepare the PR. |
| `/se-pr-triage` | Handle review comments through separate fix and final-reply approvals, plus autonomous CI triage. |
| `/se-config` | Inspect or set placement and behavior config (tiered), and migrate a v0 repo to the v1 layout. |

Most users start with `/se-discuss`, then follow the prompts. You can also describe the work naturally and let the agent choose the matching entrypoint.

## Configuration & migrating to v1

Artifact placement and two workflow gates are controlled by a small tiered config, `se-config`. Four keys:

| Key | Controls | Values |
|---|---|---|
| `commitSpec` | New-spec root — committed `docs/specs/` (team) vs. local `.super-exec/specs/`. Existing updates keep their current root. | - `"ask"` (default) — prompt when creating a spec<br>- `true` — commit new specs under `docs/specs/`<br>- `false` — keep new specs local under `.super-exec/specs/` |
| `commitPlan` | Plan root. | - `"ask"` (default) — prompt at plan-write time<br>- `false` — keep the plan local<br>- `"inheritSpec"` — follow the spec's root (never commits a plan whose spec is local) |
| `humanReviewBeforeCheckpointCommit` | Human approval before each task's checkpoint commit. | - `"ask"` (default) — prompt at `/se-exec` start<br>- `true` — always require approval<br>- `false` — never require it |
| `autoCreatePr` | Auto-open a PR when the build is done. | - `"ask"` (default) — prompt at `/se-exec` start<br>- `true` — always open a PR<br>- `false` — never open one |

Values merge over three tiers: repo-local `.super-exec/se-config.local.json` > user `~/.super-exec/se-config.json` > shipped defaults. Manage them with `/se-config print` (the effective config plus any local and user overrides) and `/se-config set <local|user> <key> <value>`.

**v1 layout** is slug-only and per-feature (no running numbers):

- Spec — `<root>/[<app>/]<feature>/spec-<feature>.md`
- Plan — `<root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md`
- Global ADRs stay in `docs/adr/<slug>.md`.

**Upgrading a v0 repo** (numbered `docs/specs/NNNN-*.md`, `.super-exec/NNNN-*/…`): run `/se-config migrate` to preview the moves (dry-run, changes nothing), then `/se-config migrate --apply` to move the files (`git mv` for tracked files, `mv` for untracked), strip the running numbers, and rewrite the `Spec:` / `Plan:` cross-pointers and the active session marker.

## Artifacts

Specs and plans use a slug-only, per-feature layout. `se-config` chooses new-artifact roots: committed under `docs/specs/` for the team, or kept local under `.super-exec/specs/` (gitignored). Existing spec updates stay in their current root without another placement prompt. Handoffs follow the plan's root, while session state (the active marker and gate files) always stays under `.super-exec/`.

Detailed workflow contracts and implementation-specific behavior live in the source-of-truth files:

- `docs/specs/core-workflow/spec-core-workflow.md`
- `plugin/skills/*/SKILL.md`
- skill-owned templates and reference files under `plugin/skills/`

Keep this README as a landing page. If workflow details change, update the spec and skills first.
