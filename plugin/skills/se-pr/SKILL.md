---
name: se-pr
description: Use when se-exec has finished code review and is ready to handle optional final human review and create the pull request — manages the gate-open marker, delegates PR creation to the repo skill or template, enforces draft-first and auto-PR toggle, and clears .super-exec/active on completion.
---

# se-pr

> **Reference paths:** every `references/*.md` cited lives at the plugin root — read it as `${CLAUDE_PLUGIN_ROOT}/references/<file>` on Claude Code, or `${CURSOR_PLUGIN_ROOT}/references/<file>` on Cursor.

se-pr is invoked by se-exec once the outer review loop exits clean. It owns two final responsibilities: (1) an optional human review gate, and (2) PR creation. Both must be handled in order. On PR completion the `.super-exec/active` marker is cleared, which inerts all guards for the session.

All git and `gh` execution runs inside a runner subagent — never inline in the controller. Raw `git`/`gh` calls in the controller trip the workflow nudge; the runner is the only safe execution context for them.

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder steps. Do not advance past a step until it is confirmed done.

- [ ] **1. Determine whether the final human review gate is enabled.** The se-exec toggles presented at session start govern this. If the gate is off, skip to step 4. If it is on, continue to step 2.

- [ ] **2. WRITE `.super-exec/gate-open`.** Create the file before presenting anything to the human. This marker activates the commit-block guard — no commit can land while the gate is open. The guard is enforced by the `PreToolUse` hook on Claude Code; on Cursor it is enforced via `beforeShellExecution` with `failClosed`. Writing the marker is what makes the block real; never skip it and proceed as if the gate were open.

- [ ] **3. Present the work for final human review and WAIT.** Show the human: the branch name and commit list, a summary of what changed, and any evidence (screenshots, test output) already captured. Do not create the PR. Do not commit. Do not advance. Wait for the human to explicitly resolve the gate — either approving ("looks good", "proceed") or requesting changes. If the human requests changes, hand control back to se-exec's inner loop, but **keep `.super-exec/gate-open` written** until the gate is resolved. Once the human explicitly approves, continue to step 4 and CLEAR `.super-exec/gate-open` by deleting the file.

- [ ] **4. Choose the PR creation path.** Inspect the repo's `.claude/skills/` directory (via a finder subagent) for a `create-pr` skill. Two paths:
  - **Path A — repo `create-pr` skill exists:** proceed to step 5.
  - **Path B — no repo `create-pr` skill:** proceed to step 6.

- [ ] **5. PATH A — Delegate entirely to the repo `create-pr` skill.** Invoke it and follow it 100%, every word. The repo skill owns version bump, draft-first creation, evidence capture, and `pull_request_template.md` population. Do not add sections, steps, or opinions on top of it. After the repo skill completes, skip to step 9.

- [ ] **6. PATH B — Build the PR draft using `pull_request_template.md`.** Locate the template (typically `.github/pull_request_template.md`). Count its primary sections (top-level `##` headings). Your draft must mirror those sections **1:1**: exactly that many primary sections, with the same headings, in the same order. No extra primary sections are permitted. Sub-sections and detail content within a section are allowed. If there is no template at all, write a concise structured description with the minimum sections needed to convey: what changed, why, how to test — still draft mode, still with evidence for UI changes.

- [ ] **7. PATH B — Attach evidence for UI changes.** If the feature includes any frontend, component, or style changes and screenshots were captured during the verify phase, embed them in the appropriate section of the draft (the template's testing or screenshots section, or — absent a template — a dedicated sub-section). If no UI changes were made, skip this step.

- [ ] **8. PATH B — Check the auto-PR toggle.** The auto-PR toggle was presented by se-exec at the start of the session. Default is **OFF**.
  - **Auto-PR OFF (default):** Present the complete PR draft to the human and WAIT for explicit approval before creating anything. Do not call `gh pr create` until the human says to proceed. Show the full draft body so the human can read and approve it.
  - **Auto-PR ON:** Proceed directly to PR creation without waiting.

  In both cases, PR creation is delegated to a **runner subagent** (cheap / script-runner tier — see `references/model-tiers.md` for the concrete model and `references/tool-map.md` for the subagent dispatch primitive). Pass the runner the approved draft title, body, and `--draft` flag. The runner executes `gh pr create`; the controller never runs `gh` inline.

- [ ] **9. Confirm PR creation.** The runner returns the PR URL. Surface it to the human.

- [ ] **10. CLEAR `.super-exec/active`.** Delete `.super-exec/active`. This is the final act of the session. Once cleared, all guards go inert. Do not leave this marker in place if the PR was created successfully.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "I'll add a 'Testing' section the template doesn't have" | Add a primary `##` section not present in `pull_request_template.md` | Count the template's primary sections. Mirror them 1:1 — same headings, same count, same order. No extra primary sections. Sub-sections within an existing section are allowed. |
| "I'll create the PR without asking" | Call `gh pr create` or delegate to a runner before the human approves the draft | Auto-PR is OFF by default. Present the full draft and wait for explicit human approval before any PR creation. Only skip the wait when auto-PR was toggled ON at session start. |
| "I'll commit during the final review" | Stage, commit, or amend while `.super-exec/gate-open` exists | The gate-open marker exists precisely to block this. The commit-block guard enforces it. Do not attempt to work around it. Keep the gate open until the human resolves the review. |
| "I'll run `gh pr create` inline" | Execute `gh`, `git`, or any shell command directly in the controller | All git/gh execution runs in a runner subagent. Inline execution in the controller trips the workflow nudge. Dispatch a runner subagent and wait for its evidence. |
| "I'll reply to the bot comment now" | Post a response to an automated PR comment without showing the human a draft | Never reply to PR comments without first presenting the draft reply to the human and receiving explicit approval. Full bot-comment triage is a fast-follow; the discipline rule holds today. |
| "I'll leave `.super-exec/active` set" | Complete the PR and move on without deleting `.super-exec/active` | Clearing `.super-exec/active` is step 10 and is mandatory. Leaving it set keeps guards armed on a dead session. Always delete it on successful PR completion. |
| "No repo skill, so I'll wing the PR format" | Write a free-form PR description when no `create-pr` skill is present | Path B always follows `pull_request_template.md` strictly. Mirror its primary sections 1:1. No template at all → use the minimum structured description (what / why / how to test), draft mode, with evidence. |
| "I'll skip writing `gate-open` since I'm just presenting" | Present the review to the human without first writing the marker file | The marker is what makes the block real. Write `.super-exec/gate-open` before presenting anything. The sequence is: write marker → present → wait → resolve → clear marker. |
| "The repo `create-pr` skill says X but I'll do Y instead" | Deviate from or supplement the repo's `create-pr` skill | Follow the repo skill 100%, every word. It owns the full PR creation sequence when present. Your only job is to invoke it. |

---

## Model and Tool Assignments

Consult `references/model-tiers.md` for the canonical role → model mapping and `references/tool-map.md` for the harness-specific tool names. The summary below uses the prose aliases from those references — never hardcode a model identifier in skill prose.

| Task | Tier | Notes |
|---|---|---|
| Orchestrating the gate, building the PR draft, deciding which path to take | Controller (current session) | PR drafting judgment requires the strong non-fast tier; this skill runs in the controller context dispatched by se-exec |
| Executing `gh pr create`, running git commands, finding the repo `create-pr` skill | Runner (cheap / script-runner) | Dispatch via the subagent primitive in `references/tool-map.md`; runner returns the PR URL and exit code only |
| Finding `.github/pull_request_template.md`, locating `.claude/skills/create-pr` | Runner (cheap / script-runner) | Read-only filesystem inspection; a finder subagent is acceptable |

The controller never runs git or `gh` inline. The runner never interprets results or drafts prose — it executes and returns evidence.
