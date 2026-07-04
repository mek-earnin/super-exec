---
name: se-commit
description: The universal commit chokepoint — load and follow this BEFORE creating ANY git commit, in any repo or workflow (super-exec or not). Triggers whenever you are about to run `git commit`, stage and commit changes, "make a commit", or checkpoint work. Makes any agent route the commit through here instead of committing directly. se-commit owns three things for every commit — the pre-commit review floor (only reviewed changes may be committed; se-commit is the gate, the caller does the reviewing), staging isolation (stage only the files the change touched, never `git add -A`), and the commit message (the repo's own commit skill first, else the conventional fallback).
---

# se-commit — the universal commit skill (any agent, any commit)

se-commit is the single chokepoint for **every** git commit — inside the super-exec workflow or any ad-hoc commit in any repo or workflow. Any agent about to create a commit loads this skill first and follows it; **never run `git commit` directly.** se-commit owns three things for one commit: the **pre-commit review floor** (only reviewed changes may be committed — se-commit is the gate, the caller does the reviewing), **staging isolation** (only the files this change touched), and the **message** (the repo's own commit skill, else the bundled fallback).

A commit must contain **only the files the current change touched** — nothing else in the working tree. This matters most when work is parallel: several implementer subagents editing disjoint files in one repo at the same time. If any commit runs `git add -A` / `git add .` / `git commit -a`, it sweeps in every other agent's in-flight edits, and the commits no longer map one-to-one to the changes that produced them.

## Pre-commit review floor (only reviewed changes may be committed)

se-commit is the **gate, not the reviewer.** Before it stages and commits, the exact files being committed must already have been **reviewed** — but se-commit does **not** perform that review and does **not** decide what to look for. It has no visibility into the change's intent, so only the **caller** (the controller or step that made the change and holds its context) can review it or direct the review.

**On every commit, the caller must have review evidence for exactly the staged paths.** "Review evidence" is a **model-judged, in-context signal** — there is **no durable marker** for it (nothing like `.super-exec/gate-open`). It exists only when the caller can tie these staged paths to a review that already covered them:

- **Already cleared by an `se-review` pass.** A commit whose staged paths were run through an `se-review` outer-loop pass needs no re-review — `se-review` already blocked on Critical/Important and re-reviewed after fixes. This covers **se-exec's per-task build loop** and **se-pr-triage's fix flow** (Track A / Track B fixes clear `se-verify` + `se-review` before the commit — see `plugin/skills/se-pr-triage/SKILL.md` and `plugin/skills/se-pr-triage/ci-triage.md`). Note the ordering in se-exec's per-task build loop is **commit → review**, so the review is not literally finished at commit time; what makes these safe is that the loop **wraps** a blocking `se-review` around every commit and does not hand the branch to `se-pr` until Critical/Important are resolved and a fresh reviewer is clean. se-commit does not re-review those paths.
- **Human-approved artifacts.** A commit of human-approved review artifacts — e.g. se-discuss committing an approved, WHAT-only spec (`plugin/skills/se-discuss/SKILL.md`) — is already reviewed: the human's spec approval **is** the review evidence. se-commit proceeds; do **not** spin up a code-style reviewer over an approved prose spec.

**No review evidence → STOP; hand the review back to the caller.** If the staged paths have not been reviewed — a direct / standalone `/se-commit`, an ad-hoc checkpoint commit (a `CLAUDE.md` "commit finished task" checkpoint), a docs/spec commit made outside a review loop, or any commit the caller cannot tie to one of the cases above — se-commit does **not** commit. It stops and instructs the **caller** (which holds the change's intent) to:

1. Spawn **one or two fresh reviewer subagents** (strong / reviewer tier — see the `se-subagent` skill) with the `Task` tool over the **staged diff** — one for a small, low-risk diff; two for a larger or higher-risk one. This is the **caller's** job: se-commit cannot do it because it does not know what the change was meant to do. The review needs no `plan.md` — it checks the staged diff for correctness, consistency, security, and repo conventions.
2. Apply **se-review's severity model** with the realism filter: **Critical / Important BLOCK**, Minor is reported non-blocking. Resolve every Critical/Important (fix, then re-review with a **fresh** reviewer) until a fresh reviewer returns clean.
3. Re-invoke `/se-commit` with the now-reviewed paths.

**When unsure, review.** A fresh standalone `/se-commit` with no surrounding context has no review evidence, so it falls to "must review first." Always fail safe toward reviewing — never toward an unreviewed commit.

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
- Types: `feat` (new feature), `fix` (other behavior change), `refactor` (no behavior change: rename/move/rewrite/performance-only improvement), `style` (whitespace/format), `test` (tests/test-utils only), `docs` (docs/comments/README only), `ci` (CI tooling), `chore` (build/deps/dev tooling).
- Local commits only — the PR merge squashes to the PR title.

## Dispatch

All git commands run in a **runner subagent** (cheap / script-runner tier — see the `se-subagent` skill), dispatched with the `Task` tool. The runner is given the explicit path list, stages exactly those paths, runs the isolation check, and commits. The controller issues no `git` commands inline, and the runner is told explicitly: stage only the listed paths, never add-all.

## Boundaries

- **Three owners, kept distinct.** se-commit owns the **review-floor enforcement gate** — it refuses to commit unreviewed paths and hands the review back to the caller. It does **not** own the **human-approval** gate (the `.super-exec/gate-open` timing on se-exec's review-before-commit ON toggle) — se-exec's commit step opens/clears that around the commit. And it does **not** spawn reviewers itself — the **caller**, which holds the change's intent, owns actually running (or dispatching) the review when evidence is missing.
- When a repo commit skill exists, se-commit follows it **100%** for the message and never overrides repo wording conventions; the bundled fallback applies only when no repo commit skill is present.
- One invocation = one logical change = one commit. Unrelated changes are separate invocations with separate path lists.
