---
name: se-pr
description: Use whenever a PR is to be created, updated, corrected, or fixing an already-open PR.
---

# se-pr

/se-exec invokes se-pr **whenever a PR is to be created, updated, or corrected** — because *Auto-PR* was ON (no final human review; that toggle is config-resolved from `autoCreatePr` via `/se-get-config` at /se-exec start), because the user answered **"Yes"** to "Create a draft PR?" at /se-exec's final-review gate, or because an already-open PR needs refreshing/fixing. **The final human-review gate lives in /se-exec, not here.** By the time se-pr runs, execution review is complete, delivery tree equals the reviewed content snapshot, working tree is clean, `HEAD` equals supplied final delivery identity, and any human review gate is resolved and cleared. A mismatch rejects PR preparation. On completion, clearing `.super-exec/active` inerts all guards for the session.

All git and `gh` execution runs in a runner subagent — never inline in the controller. Raw `git`/`gh` calls in the controller trip the workflow nudge; the runner is the only safe execution context.

se-pr does **not** write or clear `.super-exec/gate-open` — that marker is owned by /se-exec (per-commit review and the final-review gate). se-pr only ever clears `.super-exec/active`, as its last act.

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder. Do not advance past a step until it is confirmed done.
Use harness todo-list tool to load and track this checklist. Sync status as work changes; before delivery or completion claim, verify every applicable item complete.

- [ ] **1. Choose the PR creation path**
- [ ] **1a. Validate final identity and deferred summary**
- [ ] **2. PATH A — Delegate to repo `create-pr` skill**
- [ ] **3. PATH B — Build the PR draft**
- [ ] **4. PATH B — Attach evidence for UI changes**
- [ ] **5. PATH B — Create the draft PR**
- [ ] **6. Confirm PR creation**
- [ ] **7. Clear `.super-exec/active`**

---

## 1. Choose the PR creation path

Inspect the repo's `.claude/skills/` directory (via a finder subagent) for a `create-pr` skill. Strict priority: repo `create-pr` skill → repo `pull_request_template.md` → built-in [pr-template.md](./pr-template.md). Two paths:

- **Path A — repo `create-pr` skill exists:** proceed to step 2.
- **Path B — no repo `create-pr` skill:** proceed to step 3.

### 1a. Validate final identity and deferred summary

Receive final delivery identity, reviewed-snapshot/tree-equivalence proof, clean-working-tree evidence, and unresolved deferred summary from plan-folder `deferred-findings-<plan-name>.md`. Derive `<plan-name>` from active plan filename. Reject missing/mismatched identity or equivalence. Require and pass summary only when unresolved entries exist; neither PR path may omit a required summary.

## 2. PATH A — Delegate to repo `create-pr` skill

Invoke it and follow it 100%, every word. Pass final delivery identity, reviewed-snapshot/tree-equivalence proof, and unresolved deferred summary as required inputs. The repo skill owns version bump, draft-first creation, evidence capture, `pull_request_template.md` population, **and its own PR-title format**. Do not add sections, steps, opinions, or a different title format on top. After it completes, skip to step 6.

## 3. PATH B — Build the PR draft

The fallback template file [pr-template.md](./pr-template.md) is copy-pasteable markdown only: the default fallback body artifact, no title/rule prose, no examples, no fenced wrapper. The default title format and body-source priority live here in this skill. Summary:

- **Title** — `<type>(<optional-scope>): <brief summary> - <TICKET-a>, <TICKET-b>`. Types: `feat`, `fix`, `ci`, `test`, `chore`, `perf`. Scope: in a monorepo include the changed app/package scope only when **exactly one** app changed (omit when multiple changed); in a **standalone repo omit the scope entirely**. Tickets: comma-separated; `NO_TICKET` if none.
- **Body** — first locate repo `pull_request_template.md` (typically `.github/pull_request_template.md`). If present, mirror its primary `##` sections **1:1**: exactly that many primary sections, same headings, same order. No extra primary sections. Sub-sections within a section are allowed. If no repo template exists, use built-in [pr-template.md](./pr-template.md) exactly as the starting body and fill its placeholders; under `## Jira tickets:`, write each ticket ID, or `NO_TICKET` if no ticket is available. Include required unresolved deferred summary in an existing appropriate section or subsection.

## 4. PATH B — Attach evidence for UI changes

If the feature has any frontend, component, or style changes and screenshots were captured during the verify phase, embed them in the appropriate draft section. No UI changes → skip this step.

## 5. PATH B — Create the draft PR

The decision to open the PR was already made upstream (Auto-PR ON from config-resolved `autoCreatePr`, or the human's "Yes" at /se-exec's final review) — do **not** present the body and wait for a second approval. Dispatch a **runner subagent** (cheap / script-runner tier — see the `/se-subagent` skill) using the `Task` tool: pass it the title, body, and the `--draft` flag. The runner executes `gh pr create` in draft mode; the controller never runs `gh` inline. If creation fails, surface the exact failure and ask whether to retry or repair PR creation; do not restart plan execution or mark the completed plan incomplete.

## 6. Confirm PR creation

The runner returns the PR URL. Surface it to the human.

## 7. Clear `.super-exec/active`

Delete `.super-exec/active`. This is the final act of the session. Once cleared, all guards go inert. Do not leave this marker set if the PR was created successfully.

---

## Non-negotiables

Repo `create-pr` skill owns its path completely. Fallback mirrors repo template primary `##` headings 1:1 or uses [pr-template.md](./pr-template.md); never invent sections/title. Upstream already authorized Path B; do not seek second approval. `/se-exec` alone owns `gate-open`; se-pr clears only `active`, last and only after successful PR. Creation failure does not reopen plan execution. Never reply here—route comments to `/se-pr-triage` Gate 1 → fix/push → exact Gate 2.

Controller drafts/decides; cheap runner discovers, runs git/`gh`, and returns evidence/URL. See `/se-subagent`; no inline git/`gh`.
