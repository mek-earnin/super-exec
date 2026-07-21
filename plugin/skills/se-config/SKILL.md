---
name: se-config
description: User-facing command to print, write, and migrate tiered se-config — inspect effective/local/user preferences for commit/placement/review/PR, and run the manual v0→v1 artifact migration. Model invocation disabled; humans invoke /se-config only.
disable-model-invocation: true
---

# se-config — print / set / migrate se-config (user-facing)

Human read/write surface for tiered `se-config`. No other skill references `/se-config`. This skill MAY reference `/se-get-config`.

**Invoke `@./se-config-cli` (see [@./se-config-cli](./se-config-cli))** via the Bash tool for `print`, `set`, and `migrate`. Do not invent merge logic in the agent — validation, raw-tier I/O, and migration live in the script.

## Print (no args / `print`)

When the user runs `/se-config` (or `/se-config print`), show config in this **exact order**:

1. **Effective (merged)** — invoke `/se-get-config` and pretty-print its JSON. The CLI does **not** compute this block.
2. **local** — if `<repo>/.super-exec/se-config.local.json` exists, run `@./se-config-cli print` (or use its local section) and show the raw local block.
3. **user** — if `~/.super-exec/se-config.json` exists, show the raw user block (same `print` output).

The **default** tier is NEVER shown as its own block (defaults only appear inside Effective via `/se-get-config`).

Malformed tier files and invalid values for known keys are surfaced as **diagnostics** in the CLI `print` output so the human can see what merge ignores.

Practical sequence:

1. Invoke `/se-get-config` → format as `Effective (merged)`.
2. Run `@./se-config-cli print` → append its local/user raw blocks + diagnostics.

## Set

```
/se-config set <local|user> <key> <value>
```

Runs `@./se-config-cli set <local|user> <key> <value>`.

- Keys: `commitSpec`, `commitPlan`, `humanReviewBeforeCheckpointCommit`, `autoCreatePr`
- Values: `true` | `false` | `ask` (script writes JSON boolean or `"ask"`)
- Target `default` is **not writable**
- Creates the tier file (and parent dir) when missing and injects `$schema` pointing at the published schema URL
- Preserves existing sibling keys on update
- Rejects invalid key/value with a clear message and non-zero exit

## Tiers

| Tier | Path | Writable |
|---|---|---|
| local | `<repo>/.super-exec/se-config.local.json` | yes |
| user | `~/.super-exec/se-config.json` | yes |
| default | embedded in plugin (via `/se-get-config`) | no |

## Migrate

Manual v0→v1 structural migration. Root-preserving: files under `docs/` stay in `docs/`; files under `.super-exec/` stay in `.super-exec/` (into `.super-exec/specs/...`). Never crosses the docs↔.super-exec boundary. Never recompresses names (number-strip only). Idempotent — already-v1 / already-unnumbered artifacts are skipped; re-running after a successful apply is a no-op.

```
/se-config migrate          # DRY-RUN preview (default) — prints planned moves + pointer rewrites; changes NOTHING
/se-config migrate --apply  # execute moves + pointer rewrites
```

Practical sequence (always):

1. Run `@./se-config-cli migrate` (dry-run) and show the preview to the user.
2. Confirm with the user before mutating.
3. Only after explicit confirmation, run `@./se-config-cli migrate --apply`.

Mapping (every path also strips the leading `NNNN-`):

- Spec FILE `docs/specs/[<app>/]NNNN-<slug>.md` → `docs/specs/[<app>/]<slug>/spec-<slug>.md`
- Plan `.super-exec/[<app>/]NNNN-<feature>/<YYYY-MM-DD>-<plan-name>/plan.md` → `.super-exec/specs/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md`
- Handoff sibling → same new plan folder → `handoff-<plan-name>.md`
- Global ADR `docs/adr/NNNN-<slug>.md` → `docs/adr/<slug>.md` (stays global in `docs/adr/`; NOT reclassified as feature-specific)

Also rewrites internal pointers: plan `Spec:`, handoff `Plan:`, and `.super-exec/active` `spec:` + `active_plan:`.

Uses `git mv` for tracked files and plain `mv` for untracked. Creates destination parent dirs as needed.

## References

- `/se-get-config` — merged effective config (JSON). Used only for the Effective block on print.
- No other skill references `/se-config`.
