---
name: se-commit
description: Internal reference for super-exec skills — the single owner of everything about making a commit: staging only the files a change touched (never the whole working tree), respecting the repo's own commit skill for the message, and the conventional fallback. Load this whenever a super-exec step is about to create a commit. No other skill restates commit rules. Not user-invokable.
user-invocable: false
---

# se-commit — staging isolation for one commit (super-exec internal)

A commit must contain **only the files the current change touched** — nothing else in the working tree. This matters most when work is parallel: several implementer subagents editing disjoint files in one repo at the same time. If any commit runs `git add -A` / `git add .` / `git commit -a`, it sweeps in every other agent's in-flight edits, and the commits no longer map one-to-one to the changes that produced them.

## The rule

1. **The caller passes an explicit file list** — the exact paths this one logical change touched. A commit always knows its own files (the implementer subagent reports what it modified; the spec commit names the spec/ADR/`CONTEXT.md` paths).
2. **Stage only those paths**: `git add -- <path1> <path2> …`. Never `git add -A`, `git add .`, `git add :/`, or `git commit -a`.
3. **No file list → do not commit.** If the caller did not pass the changed paths, STOP and get them. Never fall back to staging the whole tree.
4. **Verify isolation before committing.** After staging, run `git status --short` and confirm the staged set (`A`/`M`/`D` in the left column) is exactly the intended paths and nothing more. If anything unexpected is staged, or expected files are missing, surface it to the caller and stop — do not commit a surprise.
5. **Message — the repo commit skill wins.** se-commit owns the message too. If the repo ships a commit skill (e.g. `git-commit-message`), follow it **100%** — it derives the type and summary from the staged diff; repo conventions always win. If the repo has no commit skill, use the bundled fallback below.

## The commit message (bundled fallback)

Used only when the repo ships no commit skill — a repo commit skill always wins:

- Conventional, **no scope**, single line: `<type>: <summary>`.
- One logical change per commit; unrelated changes are separate commits; no ticket number.
- Types: `feat` (new feature), `fix` (other behavior change), `refactor` (no behavior change: rename/move/rewrite), `style` (whitespace/format), `test` (tests/test-utils only), `docs` (docs/comments/README only), `ci` (CI tooling), `chore` (build/deps/dev tooling).
- Local commits only — the PR merge squashes to the PR title.

## Dispatch

All git commands run in a **runner subagent** (cheap / script-runner tier — see the `se-subagent` skill), dispatched with the `Task` tool. The runner is given the explicit path list, stages exactly those paths, runs the isolation check, and commits. The controller issues no `git` commands inline, and the runner is told explicitly: stage only the listed paths, never add-all.

## Boundaries

- se-commit does **not** own the review-before-commit gate or the `.super-exec/gate-open` timing — the calling step (e.g. se-exec's commit step) opens/clears that gate around the commit. se-commit runs only when it is clear to commit.
- When a repo commit skill exists, se-commit follows it **100%** for the message and never overrides repo wording conventions; the bundled fallback applies only when no repo commit skill is present.
- One invocation = one logical change = one commit. Unrelated changes are separate invocations with separate path lists.
