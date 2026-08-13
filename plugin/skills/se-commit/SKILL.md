---
name: se-commit
description: Use BEFORE creating ANY git commit, in any repo or workflow — about to run `git commit`, stage and commit changes, "make a commit", checkpoint work, or any ad-hoc commit.
---

# se-commit — the universal commit skill (any agent, any commit)

Single checkpoint for **every** git commit — super-exec workflow or any ad-hoc commit, any repo. Any agent about to commit loads it first; **never run `git commit` directly.**

## Overview (decision spine — read this first)

se-commit runs **2 steps, in order** — never skip step 1:

1. **Review gate** — review evidence for exactly the staged paths? **No → STOP**, hand review back to caller (do not commit). **Yes →** step 2. *(details + what counts as evidence: §1)*
2. **Make the commit** — branch on the repo:
   - Repo **ships a commit skill** (e.g. `git-commit-message`) → run it, follow **100%**; it owns staging + message + commit → **STOP, skip the rest of this skill.** *(§2)*
   - **No** repo commit skill → se-commit's own rules: caller-supplied file list → stage only those paths (never add-all) → verify isolation → bundled fallback message; all git via a runner subagent. *(§2 → Own rules)*

Sections below are the detail behind each step — read the one your branch lands in.

## 1. Pre-commit review floor (only reviewed changes may be committed)

se-commit is the **gate, not the reviewer.** Files must already be **reviewed**; se-commit neither performs nor scopes that review — no visibility into the change's intent — so only the **caller** (the controller or step that made the change) reviews or directs it.

**Caller supplies review evidence for exactly staged paths/current review identity.** In se-exec, prove staging equals reviewed snapshot before commit; then prove new delivery tree equals it. Changed content invalidates review; changed SHA alone does not. Evidence must cover staged paths:

- **Already cleared by an `/se-review` pass** — valid only if **no change** followed the clean pass. Inside active `/se-exec`, a supporting checkpoint needs focused checkpoint review evidence for its exact staged paths/revision; a working-increment boundary needs scoped architecture/deep review evidence after runtime proof. se-commit accepts either declared se-exec evidence and does not duplicate it. `/se-pr-triage` retains its existing fix → verify → review → commit flow. Standalone commit behavior is unchanged.
- **Human-approved artifacts** — e.g. `/se-discuss` committing an approved, WHAT-only spec (`plugin/skills/se-discuss/SKILL.md`): the human's spec approval **is** the review evidence. Do **not** spin up a code-style reviewer over an approved prose spec.

**No review evidence → STOP; hand the review back to the caller.** Unreviewed staged paths — a standalone `/se-commit`, an ad-hoc checkpoint commit (a `CLAUDE.md` "commit finished task"), a docs/spec commit outside a review loop, or any commit the caller can't tie to a case above — do not get committed. se-commit stops and instructs the **caller** (holds the intent) to:

1. Spawn **one or two fresh reviewer subagents** (strong / reviewer tier — see `/se-subagent`) via `Task` over the **staged diff** — one for a small, low-risk diff, two for a larger or higher-risk one. Caller's job; se-commit can't do it. No plan file needed — check the staged diff for correctness, consistency, security, and repo conventions.
2. Apply `/se-review`'s realism and evidence standard. Outside active se-exec, preserve existing standalone severity behavior: Critical / Important block and Minor is non-blocking; fix-created changes require fresh review.
3. Re-invoke `/se-commit` with the now-reviewed paths.

**When unsure, review.** A fresh standalone `/se-commit` has no evidence → must review first. Always fail safe toward reviewing.

## 2. Make the commit

**Repo commit skill wins outright.** If the repo ships one (e.g. `git-commit-message`), follow it **100%** — it owns staging, message, and the commit; se-commit adds nothing past the gate. The **Own rules** below apply **only** when the repo ships no commit skill.

### Own rules (no repo commit skill)

A commit must contain **only the files the current change touched** — nothing else in the working tree. Matters most under parallel work: several implementer subagents editing disjoint files in one repo at once. Any add-all sweeps in every other agent's in-flight edits, breaking the one-commit-to-one-change mapping.

1. **Caller passes an explicit file list** — the exact paths this one logical change touched. A commit always knows its own files (the implementer reports what it modified; the spec commit names the v1 paths it touched — spec at `<root>/[<app>/]<feature>/spec-<feature>.md` where `<root>` ∈ {`docs/specs/`, `.super-exec/specs/`}, global ADR at `docs/adr/<slug>.md`, feature-specific ADR at `<root>/[<app>/]<feature>/adr/<slug>.md`, and any `GLOSSARY.md` / `GLOSSARY-MAP.md` written this change; `CONTEXT.md` / `CONTEXT-MAP.md` only if the user asked).
2. **Stage only those paths**: `git add -- <path1> <path2> …`. Never `git add -A`, `git add .`, `git add :/`, or `git commit -a`.
3. **No file list → do not commit.** STOP and get the paths; never fall back to the whole tree.
4. **Verify isolation before committing.** Run `git status --short`; confirm the staged set (`A`/`M`/`D` left column) is exactly the intended paths — nothing more, nothing missing. Otherwise surface it to the caller and stop.
5. **Message** — use the bundled fallback below.

### Commit message (bundled fallback)

- Conventional, **no scope**, single line: `<type>: <summary>`.
- One logical change per commit; unrelated changes are separate commits; no ticket number.
- Types: `feat` (new feature), `fix` (other behavior change), `refactor` (no behavior change: rename/move/rewrite/performance-only), `style` (whitespace/format), `test` (tests/test-utils only), `docs` (docs/comments/README only), `ci` (CI tooling), `chore` (build/deps/dev tooling).
- Local commits only — the PR merge squashes to the PR title.

### Dispatch

All git commands run in a **runner subagent** (cheap / script-runner tier — see `/se-subagent`) via `Task`, never inline. The runner gets the explicit path list, stages exactly those, runs the isolation check, commits — told explicitly: only the listed paths, never add-all.

## Boundaries

se-commit owns the **review-floor gate**, not the **human-approval** gate (the `.super-exec/gate-open` timing on `/se-exec`'s review-before-commit toggle — `/se-exec`'s commit step manages that). And it does **not** spawn reviewers itself — the **caller** does.
