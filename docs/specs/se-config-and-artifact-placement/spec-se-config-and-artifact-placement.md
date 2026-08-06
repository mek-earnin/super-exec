# se-config and configurable artifact placement
> Ticket: NO_TICKET  ·  Status: active  ·  Depends on: none

## Problem / Why
super-exec hard-codes WHERE artifacts live and WHETHER they are committed:
- Specs always land in `docs/specs/NNNN-<feature>.md` and are committed after approval.
- Plans and handoffs always stay local under `.super-exec/`, never committed.
- Whether a human reviews before each checkpoint commit, and whether a PR is auto-created, are asked fresh every `/se-exec` session with no way to record a durable preference.

Teams differ: some want plans committed for shared review, some want specs kept local, some always want human review, some always auto-PR. Today every run either re-prompts or offers no choice at all. There is no single, discoverable place (per repo or per user) to express these preferences, and no tooling to read, write, or inspect them.

## Goals
- Introduce a tiered `se-config.json` (local repo → user home → embedded plugin default) that controls commit/placement and review/PR behavior.
- Provide four config keys — `commitSpec`, `commitPlan`, `humanReviewBeforeCheckpointCommit`, `autoCreatePr` — controlling commit/placement and review/PR behavior.
- Parse, validate, and merge config deterministically via a script that any skill can call in real time.
- Ship a user-facing `/se-config` command to print, write, and migrate config, and a shared internal `/se-get-config` that returns the merged effective config for skills to consume.
- Adopt a symmetric artifact-placement scheme where commit status changes ONLY the root (`docs/specs/` vs `.super-exec/specs/`); the sub-structure is identical.
- Scope ADRs by reach: global/cross-cutting ADRs stay in `docs/adr/`, while feature-specific ADRs live under their spec's folder.
- Standardize artifact names (feature/spec/ADR slug, plan-name) via a caveman-compressed naming convention, captured once in a shared internal `/se-slug-naming` skill.
- Provide a manual, safe migration from the v0 layout to the v1 layout.
- Release as `1.0.0` (major) with a README "Migrate to v1" section.

## Non-goals (out of scope)
- Auto-relocating existing artifacts when a config VALUE changes. Value changes affect only newly-created artifacts; no tooling relocates files on value change.
- Migrating files across the `docs/` ↔ `.super-exec/` boundary. Migration is structural-only and preserves each file's current root.
- Config keys beyond the four listed (future work).
- A committed, team-shared "project" config tier (a future `<repo>/.super-exec/se-config.json` that git would track, requiring a targeted exclude exception). Deferred; this phase ships only the per-machine `local` (`se-config.local.json`) and `user` tiers plus the embedded `default`.
- A repo-root `CONTEXT.md` for the plugin itself (terms are captured in specs, matching the existing repo pattern).
- Any settings GUI.

## Behavior / Requirements

### Config file and tiers
- Config is resolved from three tiers by precedence (highest first):
  1. **local** — `<repo>/.super-exec/se-config.local.json` (per-machine; lives in the git-excluded `.super-exec/`, so it is never committed or team-shared)
  2. **user** — `~/.super-exec/se-config.json` (per-machine, all repos)
  3. **default** — embedded defaults shipped in the plugin (not a user-editable file)
- Each written config file carries a `$schema` field pointing to `https://raw.githubusercontent.com/mek-earnin/super-exec/main/plugin/skills/se-config/se-config.schema.json`. A JSON Schema is published at that path.
- Keys, allowed values, and defaults:

  | Key | Values | Default |
  |---|---|---|
  | `commitSpec` | `true` \| `false` \| `"ask"` | `"ask"` |
  | `commitPlan` | `"inheritSpec"` \| `false` \| `"ask"` | `"ask"` |
  | `humanReviewBeforeCheckpointCommit` | `true` \| `false` \| `"ask"` | `"ask"` |
  | `autoCreatePr` | `true` \| `false` \| `"ask"` | `"ask"` |

### Merge / effective config
- Effective config is a per-key merge: for each key, use the highest-priority tier that supplies a VALID value; otherwise fall through to the next tier and ultimately the embedded default, so every key always resolves.
- A malformed tier file (invalid JSON) causes the ENTIRE tier to be skipped during the merge.
- A well-formed tier with an invalid value for a key treats that key as absent (falls through to a lower tier); other valid keys in the same file still apply.
- Validation is deterministic and performed by a script, never by agent inference.

### Meaning of each value
- `commitSpec`: applies only when creating a new spec. `true` → the new spec is committed (lives under `docs/`); `false` → the new spec is local (under `.super-exec/`); `"ask"` → prompt at new-spec write time (during discuss), which decides both commit and root. Updating an existing spec preserves its exact on-disk root and does not prompt again; only an explicit user request may move it between roots.
- `commitPlan`: decided at plan-write time (during plan), and resolves against the governing spec's on-disk root (the root `commitSpec` set when that spec was written):
  - `"inheritSpec"` → the plan lands in the same root as its spec (committed spec → committed plan; local spec → local plan).
  - `false` → the plan lands in the local root.
  - `"ask"` (default) → the plan lands in the local root when the spec is local; when the spec is committed, the tool prompts the human to choose the plan's location, recommending local (a plan is usually a one-off for a single implementation, so it needn't be committed) with committing alongside the spec as the alternative.
  - Invariant: a local spec always yields a local plan — every value above places a local spec's plan in the local root.
  - Legacy `commitPlan: true` (from the earlier value set) is treated as absent per the merge rule above and falls through to the `"ask"` default. No migration rewrites it.
- `humanReviewBeforeCheckpointCommit`: `true`/`false` fix the review-before-each-checkpoint-commit behavior; `"ask"` → prompt at `/se-exec` start (current behavior).
- `autoCreatePr`: `true`/`false` fix PR auto-creation; `"ask"` → prompt at `/se-exec` start (current behavior).

### Artifact placement scheme (v1)
Commit status changes ONLY the root; the sub-structure is identical.
- Committed root: `docs/specs/` (monorepo: `docs/specs/<app>/`)
- Uncommitted root: `.super-exec/specs/` (monorepo: `.super-exec/specs/<app>/`)

With `<root>` = the chosen root (including the optional `<app>` segment):
- Spec: `<root>/<feature>/spec-<feature>.md`
- Plan: `<root>/<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md`
- Handoff: the SAME folder as its plan → `handoff-<plan-name>.md`
- Feature-specific ADR: `<root>/<feature>/adr/<slug>.md`

Rules:
- A spec/feature is identified by its `<feature>` slug ALONE — there are no running numbers anywhere in the layout. The slug is unique within a specs tree. Removing the shared numeric counter is deliberate: parallel agents in one worktree can never collide on a "next number".
- Because commit status varies per artifact, any skill that locates or auto-discovers a spec/plan MUST scan BOTH roots (union), regardless of the current config value.
- Ordering and dependencies between features are expressed via the spec's `Depends on:` header, not by a numeric sequence. Auto-discovery (e.g. se-plan) lists unplanned specs (those with no plan folder) and asks which to plan rather than picking a numeric "lowest".

### ADR placement (scoped by reach)
- The ADR author routes by scope at write time: a general/global/cross-cutting decision is a **global ADR**; a decision that only concerns one feature is a **feature-specific ADR**.
- Global ADR: stored at `docs/adr/<slug>.md` (slug-only; no running number, so parallel authors never contend for the next number).
- Feature-specific ADR: lives under the spec's folder at `<root>/<feature>/adr/<slug>.md` (slug-only).
- A feature-specific ADR inherits its spec's root: a committed spec's ADRs live under `docs/specs/...`, a local spec's ADRs under `.super-exec/specs/...`.

### Naming convention (caveman-compressed)
- Every author-chosen name — feature slug, spec name, ADR slug, plan-name — is caveman-compressed: lowercase, hyphen-joined words, with filler dropped so only technical substance remains. This is the SAME drop logic as caveman full, minus symbols.
- Drop: articles (`a`/`an`/`the`), be-verbs/copulas (`is`/`are`/`was`/`were`/`be`/`been`/`being`), filler (`just`/`really`/`basically`/`actually`/`simply`), pleasantries, and hedging. Keep technical terms exact; prefer short synonyms. Characters limited to `[a-z0-9-]` (no symbols).
- Example: `local-only-plans-specs-are-the-shared-contract` → `local-only-plans-specs-shared-contract`.
- The convention is FORWARD-ONLY: it governs newly-created names. Migration never recompresses existing names (it only strips the leading number); an author may compress an old name by hand if desired.
- The rule lives once in the shared internal `/se-slug-naming` skill (`user-invocable: false`, prose-only, no script); every authoring skill references it rather than restating it.
- Self-contained: `/se-slug-naming` EMBEDS the drop list; it borrows caveman-full's logic but does NOT depend on the optional external `caveman` skill (consistent with super-exec's self-contained posture).

### `/se-config` command (user-invoke only; model-invocation disabled)
- No other skill may reference `/se-config`; `/se-config` MAY reference other skills.
- `/se-config` with no args pretty-prints config:
  - the `Effective (merged)` block first (the resolved config),
  - then the `local` tier block if that file exists,
  - then the `user` tier block if that file exists,
  - the `default` tier is NEVER shown as its own block.
  - Malformed files and invalid values are surfaced here as marked diagnostics, so the human can see what was ignored.
- `/se-config set <local|user> <key> <value>` writes `<value>` for `<key>` into the named tier. The script validates the value against the schema and rejects an invalid key/value. It creates the tier file (and injects `$schema`) when missing. The `default` tier is not writable.
- `/se-config migrate` runs the v0→v1 migration described below.

### `/se-get-config` (shared, internal; `user-invocable: false`)
- Returns the merged effective config as JSON on stdout for skills to consume in real time.
- Applies the lenient merge above (skip a malformed tier, drop invalid values). Because it is internal-only it always returns a fully-resolved result and does not surface diagnostics.
- Skills that make commit, placement, review, or PR decisions consult `/se-get-config` at the relevant step.

### Migration (`/se-config migrate`)
- Manual and user-invoked only. Migrates existing artifacts from the v0 layout to the v1 layout.
- Structural-only and root-preserving: files under `docs/` migrate within `docs/`; files under `.super-exec/` migrate within `.super-exec/`. It never crosses the boundary and never relocates based on config values.
- v0 → v1 mapping (every mapping also drops the leading `NNNN-` running number):
  - Spec `docs/specs/[<app>/]NNNN-<feature>.md` → `docs/specs/[<app>/]<feature>/spec-<feature>.md` (stays in `docs/`, whether tracked or untracked).
  - Plan `.super-exec/[<app>/]NNNN-<feature>/<YYYY-MM-DD>-<plan-name>/plan.md` → `.super-exec/specs/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md`.
  - Handoff `.../<YYYY-MM-DD>-<plan-name>/handoff.md` → the same new plan folder → `handoff-<plan-name>.md`.
  - Global ADR `docs/adr/NNNN-<slug>.md` → `docs/adr/<slug>.md` (drops the number; stays a global ADR in `docs/adr/`, NOT reclassified as feature-specific, because scope cannot be reliably inferred).
  - `<feature>` and `<plan-name>` are derived from the existing v0 directory/file names with the leading `NNNN-` stripped.
- Also rewrites internal pointers to the new paths: each plan's `Spec:` reference, each handoff's `Plan:` reference, and `.super-exec/active`'s `spec:` and `active_plan:` fields.
- Safety: prints a dry-run preview of the planned moves, requires explicit confirmation, then executes using `git mv` for tracked files and plain `mv` for untracked files. It is idempotent and safe to re-run (already-migrated artifacts are left alone).

### Versioning and docs
- This is a breaking change, so the version bumps to `1.0.0` (major) via `devtools/bump-version.sh`.
- README gains a "Migrate to v1" section explaining the new layout, the config, and `/se-config migrate`.
- Every skill, hook, template, and dogfood doc that references the old paths or fixed behavior is updated to the v1 scheme and to consult config (the exact file list is a planning concern).

## Domain terms
- **se-config.json**: the tiered configuration file controlling super-exec commit/placement and review/PR behavior.
- **Config tier**: one of `local` (`<repo>/.super-exec/se-config.local.json`, per-machine), `user` (`~/.super-exec/se-config.json`, per-machine), or `default` (embedded plugin defaults), in descending precedence.
- **Effective config**: the per-key merge of all tiers; every key always resolves because the default backstops it.
- **Committed root / Uncommitted root**: `docs/specs/` and `.super-exec/specs/` — the two mirrored roots an artifact may occupy; commit status changes only the root, not the sub-structure.
- **Global ADR**: a cross-cutting architecture decision stored at `docs/adr/<slug>.md` (slug-only, no running number).
- **Feature-specific ADR**: an architecture decision scoped to one feature, stored under that spec's folder (`<root>/<feature>/adr/<slug>.md`, slug-only), inheriting the spec's root.
- **`/se-config`**: the user-facing command to print, write, and migrate config; model-invocation is disabled and no other skill references it.
- **`/se-get-config`**: the internal shared command returning the merged effective config as JSON for skills.
- **`/se-slug-naming`**: the internal shared skill (`user-invocable: false`, prose-only) holding the caveman-compressed naming convention that authoring skills apply to feature/spec/ADR slug and plan-name.
- **Migrate (v0→v1)**: the manual, structural-only, root-preserving relocation of existing artifacts to the v1 layout.

## Decisions
- **Placement is config-driven, superseding the "local-only plans" ADR.** The local-only-plans ADR ("local-only plans; specs are the shared contract") fixed placement; v1 makes both spec and plan placement configurable. That ADR must be updated or superseded during planning.
- **ADRs are scoped by reach.** Decisions differ in blast radius, so a cross-cutting one and a feature-local one should not share a home. Existing ADRs are not auto-reclassified because an old file's scope cannot be reliably inferred.
- **Symmetric roots.** Committed and uncommitted layouts are identical except for the root prefix, keeping migration and cross-root lookup simple.
- **No running numbers — slug-only identity.** A shared numeric counter would force parallel agents in one worktree to contend for the "next number"; slug-only identity removes that contention. (The `.super-exec/active` marker's single-session assumption is a separate concern, deferred.)
- **Names are caveman-compressed, forward-only.** Compression is a semantic author choice, so it lives as a prose convention rather than a script (unlike deterministic config parsing). It is forward-only — migration never recompresses — to avoid churning stable pointers.
- **Value changes never relocate existing files.** Config changes apply only to new artifacts; the only relocation tooling is the v0→v1 structural migration.
- **Deterministic, script-based validation and merge.** Config parsing, validation, and merge live in a script rather than agent inference, for reproducibility across sessions and harnesses.
- **`/se-get-config` is lenient; `/se-config` is diagnostic.** Internal consumers always receive a resolved merged result (bad input silently dropped to default); the human print path surfaces malformed or invalid input.
- **`commitPlan` is derived from the spec, not independent.** A plan depends on its spec, so a committed plan over a local spec would strand teammates with a plan and no spec to read. Avoiding that is why `commitPlan` drops `true`, adds `"inheritSpec"`, and defaults to `"ask"` — no value can commit a plan whose spec is local. This supersedes the earlier "`commitSpec` and `commitPlan` are independent" stance.
