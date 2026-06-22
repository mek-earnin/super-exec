---
name: se-pr
description: Use when se-exec has decided a pull request should be created (Auto-PR ON, or the human answered "Yes" at se-exec's final-review gate). Owns PR creation only — the final review gate and the gate-open marker stay in se-exec. PR body priority is repo create-pr skill, then repo pull_request_template.md, then built-in pr-template.md; creates the PR draft-first via a runner subagent; clears .super-exec/active on completion.
---

# se-pr

se-pr is invoked by se-exec **when a pull request is to be created** — either because *Auto-PR* was ON (no review), or because the user answered **"Yes"** to "Create a draft PR?" at se-exec's final-review gate. **The final human-review gate now lives in se-exec, not here.** By the time se-pr runs, the decision to open the PR has already been made and any review gate has been resolved and cleared — se-pr owns **PR creation only**. On PR completion the `.super-exec/active` marker is cleared, which inerts all guards for the session.

All git and `gh` execution runs inside a runner subagent — never inline in the controller. Raw `git`/`gh` calls in the controller trip the workflow nudge; the runner is the only safe execution context for them.

se-pr does **not** write or clear `.super-exec/gate-open` — that marker is owned by se-exec (per-commit review and the final-review gate). se-pr only ever clears `.super-exec/active`, as its last act.

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder steps. Do not advance past a step until it is confirmed done.

- [ ] **1. Choose the PR creation path.** Inspect the repo's `.claude/skills/` directory (via a finder subagent) for a `create-pr` skill. The priority is strict: repo `create-pr` skill → repo `pull_request_template.md` → built-in [pr-template.md](./pr-template.md). Two paths:
  - **Path A — repo `create-pr` skill exists:** proceed to step 2.
  - **Path B — no repo `create-pr` skill:** proceed to step 3.

- [ ] **2. PATH A — Delegate entirely to the repo `create-pr` skill.** Invoke it and follow it 100%, every word. The repo skill owns version bump, draft-first creation, evidence capture, `pull_request_template.md` population, **and its own PR-title format**. Do not add sections, steps, opinions, or a different title format on top of it. After the repo skill completes, skip to step 6.

- [ ] **3. PATH B — Build the PR draft (no repo `create-pr` skill).** The PR fallback template file [pr-template.md](./pr-template.md) is copy-pasteable markdown only: it contains the default fallback body artifact, with no title/rule prose, no examples, and no fenced wrapper. The default title format and body-source priority live here in this skill. Summary:
  - **Title** — `<type>(<optional-scope>): <brief summary> - <TICKET-a>, <TICKET-b>`. Types: `feat`, `fix`, `ci`, `test`, `chore`, `perf`. Scope: in a monorepo include the changed app/package scope only when **exactly one** app changed (omit when multiple changed); in a **standalone repo omit the scope entirely**. Tickets: comma-separated; `NO_TICKET` if none.
  - **Body** — first locate repo `pull_request_template.md` (typically `.github/pull_request_template.md`). If present, mirror its primary `##` sections **1:1**: exactly that many primary sections, same headings, same order. No extra primary sections. Sub-sections within a section are allowed. If no repo template exists, use built-in [pr-template.md](./pr-template.md) exactly as the starting body and fill its placeholders; under `## Jira tickets:`, write each ticket ID, or write `NO_TICKET` if no ticket is available.

- [ ] **4. PATH B — Attach evidence for UI changes.** If the feature includes any frontend, component, or style changes and screenshots were captured during the verify phase, embed them in the appropriate section of the draft. If no UI changes were made, skip this step.

- [ ] **5. PATH B — Create the draft PR directly.** The decision to open the PR was already made upstream (Auto-PR ON, or the human's "Yes" at se-exec's final review) — do **not** present the body and wait for a second approval. Dispatch a **runner subagent** (cheap / script-runner tier — see the `se-subagent` skill) using the `Task` tool: pass it the title, body, and the `--draft` flag. The runner executes `gh pr create` in draft mode; the controller never runs `gh` inline. If creation fails, surface the exact failure and ask whether to retry or repair PR creation; do not restart plan execution or mark the completed plan incomplete.

- [ ] **6. Confirm PR creation.** The runner returns the PR URL. Surface it to the human.

- [ ] **7. CLEAR `.super-exec/active`.** Delete `.super-exec/active`. This is the final act of the session. Once cleared, all guards go inert. Do not leave this marker in place if the PR was created successfully.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "I'll add a 'Testing' section the template doesn't have" | Add a primary `##` section not present in `pull_request_template.md` | Count the template's primary sections. Mirror them 1:1 — same headings, same count, same order. No extra primary sections. Sub-sections within an existing section are allowed. |
| "I'll present the draft and wait for another approval" | Block Path-B PR creation to ask the human to approve the body again | The decision to open the PR was already made upstream — Auto-PR ON, or the human's "Yes" at se-exec's final review. Path B creates the draft **directly** (draft mode is safe and editable). Do not add a second approval wait. (A repo `create-pr` skill that prompts on its own is Path A — follow it 100%.) |
| "I'll write or clear `.super-exec/gate-open` myself" | Manage the gate-open marker inside se-pr | gate-open is owned by **se-exec** (per-commit review + the final-review gate). se-pr never writes or clears it. se-pr's only marker action is clearing `.super-exec/active` at the very end. |
| "I'll run `gh pr create` inline" | Execute `gh`, `git`, or any shell command directly in the controller | All git/gh execution runs in a runner subagent dispatched with the `Task` tool. Inline execution in the controller trips the workflow nudge. Dispatch a runner subagent and wait for its evidence. |
| "I'll reply to the bot comment now" | Post a response to an automated PR comment without showing the human a draft | Never reply to PR comments without first presenting the draft reply to the human and receiving explicit approval. Full bot-comment triage is a fast-follow; the discipline rule holds today. |
| "I'll leave `.super-exec/active` set" | Complete the PR and move on without deleting `.super-exec/active` | Clearing `.super-exec/active` is step 7 and is mandatory. Leaving it set keeps guards armed on a dead session. Always delete it on successful PR completion. |
| "PR creation failed, so the plan isn't done" | Reopen plan execution or unmark plan completion because `gh pr create` failed | Wrong boundary. se-exec already completed the plan before invoking se-pr. Surface the PR creation failure and retry/repair PR creation with the user; do not restart the build plan. |
| "No repo skill, so I'll wing the PR title/format" | Write a free-form PR description or an ad-hoc title when no `create-pr` skill is present | Path B uses repo `pull_request_template.md` when present (mirror primary sections 1:1) and otherwise uses built-in [pr-template.md](./pr-template.md) exactly as the starting body. The default title format still applies (scope omitted entirely in a standalone repo). |
| "The repo `create-pr` skill says X but I'll do Y instead" | Deviate from or supplement the repo's `create-pr` skill | Follow the repo skill 100%, every word — including its PR-title format. It owns the full PR creation sequence when present. Your only job is to invoke it. |

---

## Model and Tool Assignments

Consult the `se-subagent` skill for the canonical role → model mapping and harness-specific tool names. The summary below uses prose tier aliases — never hardcode a model identifier in skill prose.

| Task | Tier | Notes |
|---|---|---|
| Orchestrating the gate, building the PR draft, deciding which path to take | Controller (current session) | PR drafting judgment requires the strong non-fast tier; this skill runs in the controller context dispatched by se-exec |
| Executing `gh pr create`, running git commands, finding the repo `create-pr` skill | Runner (cheap / script-runner) | Dispatch via the `Task` tool; runner returns the PR URL and exit code only |
| Finding `.github/pull_request_template.md`, locating `.claude/skills/create-pr` | Runner (cheap / script-runner) | Read-only filesystem inspection; a finder subagent dispatched with `Task` is acceptable |

The controller never runs git or `gh` inline. The runner never interprets results or drafts prose — it executes and returns evidence.
