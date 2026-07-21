# Config-driven artifact placement: symmetric roots, slug-only identity, scoped ADRs

super-exec v1 makes artifact placement configurable per repo/user through `se-config` (`commitSpec`, `commitPlan`; each `true | false | "ask"`, merged local > user > default). A spec or plan lives under one of two **symmetric roots** with identical per-feature sub-structure — `docs/specs/` (committed, team-shared) or `.super-exec/specs/` (local, gitignored) — chosen by the resolved config value; every locator scans BOTH roots. Identity is **slug-only** (no running `NNNN-` number): `<root>/[<app>/]<feature>/spec-<feature>.md` and `<root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md`. ADRs are likewise slug-only and **routed by scope**: global/cross-cutting → `docs/adr/<slug>.md`, feature-specific → `<root>/[<app>/]<feature>/adr/<slug>.md` (inherits the spec's root). Slugs are named per `/se-slug-naming` (caveman-compressed, `[a-z0-9-]` only).

This supersedes `local-only-plans-specs-are-the-shared-contract`, which fixed a single layout (spec committed to `docs/specs/`, plan gitignored under `.super-exec/`, both with a running number).

## Why

- **Configurable commit status.** Teams disagree on whether specs and plans belong in the repo. A tiered `se-config` lets each repo/user decide instead of hard-coding "spec committed, plan local". `commitSpec`/`commitPlan` choose the root only.
- **Symmetric roots.** Because commit status picks only the root and the per-feature sub-structure is identical on both sides, one set of locators works wherever an artifact lives, and moving an artifact between committed and local is a plain move, never a reshape.
- **Slug-only identity (no running numbers).** A global `NNNN-` sequence collides under parallel agents and adds churn on every new artifact. A slug is stable, parallel-safe, and self-describing; dependency order is carried by a spec's `Depends on:` header, not by a number.
- **Scoped ADRs.** A decision local to one feature belongs beside that feature (and may stay local); only cross-cutting decisions belong in the global `docs/adr/`.

## Consequences

- The old fixed layout (`docs/specs/NNNN-<feature>.md`, gitignored `.super-exec/NNNN-<feature>/…/plan.md`, sibling `handoff.md`) is replaced. A one-time `/se-config migrate` converts v0 artifacts — stripping the leading number and rewriting `Spec:` / `Plan:` / `active_plan` pointers — while preserving the docs↔.super-exec boundary and staying idempotent.
- The spec-never-references-a-plan rule still holds: a plan may now also be committed (under `docs/specs/`), but a spec must not link a plan that could be local for a teammate.
