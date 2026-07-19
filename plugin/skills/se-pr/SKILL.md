---
name: se-pr
description: Use whenever a PR is to be created, updated, corrected, or fixing an already-open PR.
---

# se-pr

/se-exec invokes se-pr **whenever a PR is to be created, updated, or corrected** — because *Auto-PR* was ON (no review), because the user answered **"Yes"** to "Create a draft PR?" at /se-exec's final-review gate, or because an already-open PR needs refreshing/fixing. **The final human-review gate lives in /se-exec, not here.** By the time se-pr runs, the decision is made and any review gate resolved and cleared — se-pr owns **PR creation and updates/corrections**. On completion, clearing `.super-exec/active` inerts all guards for the session.

All git and `gh` execution runs in a runner subagent — never inline in the controller. Raw `git`/`gh` calls in the controller trip the workflow nudge; the runner is the only safe execution context.

se-pr does **not** write or clear `.super-exec/gate-open` — that marker is owned by /se-exec (per-commit review and the final-review gate). se-pr only ever clears `.super-exec/active`, as its last act.

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder. Do not advance past a step until it is confirmed done.

- [ ] **1. Choose the PR creation path**
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

## 2. PATH A — Delegate to repo `create-pr` skill

Invoke it and follow it 100%, every word. The repo skill owns version bump, draft-first creation, evidence capture, `pull_request_template.md` population, **and its own PR-title format**. Do not add sections, steps, opinions, or a different title format on top. After it completes, skip to step 6.

## 3. PATH B — Build the PR draft

The fallback template file [pr-template.md](./pr-template.md) is copy-pasteable markdown only: the default fallback body artifact, no title/rule prose, no examples, no fenced wrapper. The default title format and body-source priority live here in this skill. Summary:

- **Title** — `<type>(<optional-scope>): <brief summary> - <TICKET-a>, <TICKET-b>`. Types: `feat`, `fix`, `ci`, `test`, `chore`, `perf`. Scope: in a monorepo include the changed app/package scope only when **exactly one** app changed (omit when multiple changed); in a **standalone repo omit the scope entirely**. Tickets: comma-separated; `NO_TICKET` if none.
- **Body** — first locate repo `pull_request_template.md` (typically `.github/pull_request_template.md`). If present, mirror its primary `##` sections **1:1**: exactly that many primary sections, same headings, same order. No extra primary sections. Sub-sections within a section are allowed. If no repo template exists, use built-in [pr-template.md](./pr-template.md) exactly as the starting body and fill its placeholders; under `## Jira tickets:`, write each ticket ID, or `NO_TICKET` if no ticket is available.

## 4. PATH B — Attach evidence for UI changes

If the feature has any frontend, component, or style changes and screenshots were captured during the verify phase, embed them in the appropriate draft section. No UI changes → skip this step.

## 5. PATH B — Create the draft PR

The decision to open the PR was already made upstream (Auto-PR ON, or the human's "Yes" at /se-exec's final review) — do **not** present the body and wait for a second approval. Dispatch a **runner subagent** (cheap / script-runner tier — see the `/se-subagent` skill) using the `Task` tool: pass it the title, body, and the `--draft` flag. The runner executes `gh pr create` in draft mode; the controller never runs `gh` inline. If creation fails, surface the exact failure and ask whether to retry or repair PR creation; do not restart plan execution or mark the completed plan incomplete.

## 6. Confirm PR creation

The runner returns the PR URL. Surface it to the human.

## 7. Clear `.super-exec/active`

Delete `.super-exec/active`. This is the final act of the session. Once cleared, all guards go inert. Do not leave this marker set if the PR was created successfully.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "I'll add a 'Testing' section the template doesn't have" | Add a primary `##` section not present in `pull_request_template.md` | Count the template's primary sections. Mirror 1:1 — same headings, count, order. No extra primary sections. Sub-sections within an existing section are allowed. |
| "I'll present the draft and wait for another approval" | Block Path-B PR creation to ask the human to approve the body again | The decision to open the PR was already made upstream — Auto-PR ON, or the human's "Yes" at /se-exec's final review. Path B creates the draft **directly** (draft mode is safe and editable). Do not add a second approval wait. (A repo `create-pr` skill that prompts on its own is Path A — follow it 100%.) |
| "I'll write or clear `.super-exec/gate-open` myself" | Manage the gate-open marker inside se-pr | gate-open is owned by **/se-exec** (per-commit review + the final-review gate). se-pr never writes or clears it. se-pr's only marker action is clearing `.super-exec/active` at the very end. |
| "I'll run `gh pr create` inline" | Execute `gh`, `git`, or any shell command directly in the controller | All git/gh execution runs in a runner subagent dispatched via the `Task` tool. Inline execution in the controller trips the workflow nudge. Dispatch a runner and wait for its evidence. |
| "I'll reply to the bot comment now" | Post a response to an automated PR comment from the PR-creation flow | Never reply from se-pr. Route review comments through /se-pr-triage: approve the decision/Fix scope at Gate 1, finish and push any Fix, then present the exact final target/body and receive explicit Gate-2 approval before posting. |
| "I'll leave `.super-exec/active` set" | Complete the PR and move on without deleting `.super-exec/active` | Clearing `.super-exec/active` is step 7 and is mandatory. Leaving it set keeps guards armed on a dead session. Always delete it on successful PR completion. |
| "PR creation failed, so the plan isn't done" | Reopen plan execution or unmark plan completion because `gh pr create` failed | Wrong boundary. /se-exec already completed the plan before invoking se-pr. Surface the PR creation failure and retry/repair PR creation with the user; do not restart the build plan. |
| "No repo skill, so I'll wing the PR title/format" | Write a free-form PR description or an ad-hoc title when no `create-pr` skill is present | Path B uses repo `pull_request_template.md` when present (mirror primary sections 1:1) and otherwise uses built-in [pr-template.md](./pr-template.md) exactly as the starting body. The default title format still applies (scope omitted entirely in a standalone repo). |
| "The repo `create-pr` skill says X but I'll do Y instead" | Deviate from or supplement the repo's `create-pr` skill | Follow the repo skill 100%, every word — including its PR-title format. It owns the full PR creation sequence when present. Your only job is to invoke it. |

---

## Model and Tool Assignments

Consult the `/se-subagent` skill for the canonical role → model mapping and harness-specific tool names. The summary below uses prose tier aliases — never hardcode a model identifier in skill prose.

| Task | Tier | Notes |
|---|---|---|
| Orchestrating the gate, building the PR draft, deciding which path to take | Controller (current session) | PR drafting judgment needs the strong non-fast tier; runs in controller context dispatched by /se-exec |
| Executing `gh pr create`, running git commands, finding the repo `create-pr` skill | Runner (cheap / script-runner) | Dispatch via `Task`; runner returns PR URL and exit code only |
| Finding `.github/pull_request_template.md`, locating `.claude/skills/create-pr` | Runner (cheap / script-runner) | Read-only filesystem inspection; a finder subagent dispatched via `Task` is acceptable |

The controller never runs git or `gh` inline. The runner never interprets results or drafts prose — it executes and returns evidence.
