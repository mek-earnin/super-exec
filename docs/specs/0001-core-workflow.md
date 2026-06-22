# Core workflow

> Ticket: NO_TICKET  ·  Status: active

A guided, gate-driven development workflow distributed as a Claude Code plugin. It carries a feature from shared understanding through to a pull request while enforcing the discipline the author repeatedly had to correct by hand: delegate heavy work to subagents, verify before claiming done, stay in scope, reuse before writing, respect each repo's own conventions, never commit while a human-review gate is open, and never reply to a PR comment without an approved draft. The spec is the contract: implementation must match it, and the human's real gate is the PR review + manual squash-merge — every change (code and any spec amendment) lands there for review before it merges.

## Problem / Why

Manual babysitting. Across ~2,627 past prompts in 7 EarnIn repos, the same corrections recurred: the agent ran builds/tests/wide searches inline and blew up context (forcing manual `/clear`), claimed "done" without verifying, over-reached scope, duplicated code instead of reusing utilities, used raw git instead of repo skills, auto-committed during review, and replied to PR comments without showing a draft. super-exec encodes those corrections as an enforced workflow so they stop happening.

## Goals

- A repeatable spec → plan → execute → verify → review → PR workflow with explicit human gates.
- Less babysitting: the agent self-delegates, self-verifies, and resolves ambiguity up front rather than mid-execution.
- Strong context hygiene: heavy work runs in throwaway subagent contexts; the controller stays lean.
- Respect every repo's own conventions by delegating convention-bearing actions to that repo's skills.
- Cross-harness: one portable skill set usable in Claude Code and Cursor.

## Non-goals (out of scope for v1)

- Continuous post-PR polling as a built-in daemon. `se-pr-triage` provides one explicit triage round; `/loop` can wrap it for watching.
- Project-specific configuration layer (per-repo baked-in settings). Shared scope first; the tool detects per-repo conventions at runtime.
- Reinventing branch/commit/PR/dev-server/version logic. These are delegated to repo skills.
- Forced TDD everywhere, or plans containing copy-paste-ready code.

## Workflow (behavior / requirements)

Two sessions, one hard boundary at plan → execute.

super-exec ships as **skills only** — the four entrypoints (`se-discuss`, `se-plan`, `se-exec`, `se-pr-triage`) are skills invoked as `/se-discuss`, `/se-plan`, `/se-exec`, and `/se-pr-triage` (or auto-invoked by the model when the work matches); there is no separate slash-command layer. Each writes the `.super-exec/active` session marker on entry, so the behavior is identical whether invoked manually or automatically (see ADR 0003).

### Session 1 — design

**`/se-discuss`** drives the whole session:

1. **Branch context warm-up** (read-only, background). Start a lightweight branch-context helper immediately, but do not wait on it before interviewing. The helper reads the current branch, infers any ticket key from the prompt/current branch, samples branch naming conventions, detects the preferred base (`origin/develop` when present, else `origin/main`), and returns JSON inputs for the later branch decision. If a ticket is already known and Atlassian MCP is available, the agent may fetch the ticket title/description in parallel and use it to seed the discussion. No branch is created in this step.
2. **Discuss (spec).** Interview the user relentlessly to reach shared understanding of the WHAT. Research the codebase via subagents instead of asking what can be discovered. Detect new-vs-update: glob `docs/specs[/<app>]`, match by ticket key in the spec header + feature slug after the numeric prefix, confirm with the user; an update interviews only the delta. Sharpen terminology, but do not write the final spec file until the ticket value is resolved for its header.
3. **Ticket + branch confirmation.** After the last WHAT question and before writing the spec file, resolve traceability. If no ticket was provided or inferred, ask once: "Do you have a Jira ticket for this task?" If the user provides a ticket and Atlassian MCP is available, fetch the ticket data and derive the branch name from the repo convention plus the ticket title/final feature slug. If there is no ticket, use `NO_TICKET` in the spec and derive a no-ticket branch from the final feature slug. Present the ticket value and proposed branch name once for confirmation or edit.
4. **Write review artifacts.** Write/update the uncommitted spec in `docs/specs/`, update `CONTEXT.md` when new terms need review, and offer/write an ADR only when the decision is hard to reverse + surprising + a real trade-off. The written files are the review artifacts; do not commit them before approval.
5. **Spec-approval gate, then branch + commit.** Present the finalized spec file and ask the user to review — "Everything look good? Proceed to planning?". A change request loops back to editing the written file and re-presenting; repeat until the user explicitly approves. On approval, create/switch to the already-confirmed branch, then **commit the approved artifacts** (`docs/specs/`, `CONTEXT.md`, ADRs as needed) via `se-commit` — *unless* the user asks not to commit, or `docs/specs/` is gitignored. The approval is authorization to create the confirmed branch and commit; do not ask again unless branch creation fails, facts changed, or checkout conflicts with the approved uncommitted files. In that conflict case, stop and ask; never stash, discard, or rewrite approved review artifacts silently.
6. **Plan (architecture + verification).** Once the spec is approved, **se-discuss auto-chains into the Plan phase in the same session — the user never has to invoke `/se-plan` manually.** Read the spec. Design the architecture, researching via subagents. Discover the full repo skill catalog and bind matching skills to tasks (see Repo skill catalog & task binding). **Resolve every risk and open question with the user up front** (grill like discuss, but for HOW) — the plan carries no open items into execution. Design verification (see below) and reach agreement. If the feature involves UI work, ask about incorporating impeccable (default yes — see Optional: UI design). Write the plan with plan frontmatter (`title`, `feature`, confirmed `branch`, `status: pending`) before `## Execution Checklist` as the first section, then immediately record `active_plan: .super-exec/<feature>/<plan-dir>/plan.md` in `.super-exec/active`. **Human-review gate:** the user reviews architecture + data flow. At approval, `se-plan` may add/update `approved:` metadata, but approval is not the first time `active_plan` is recorded; the plan status stays `pending` until execution starts.
7. End: instruct the user to start a fresh session and run `/se-exec`. The discuss→plan transition auto-chains; the **plan→execute transition is a hard fresh-session boundary** and is never auto-chained.

`/se-plan` is also a manual re-entry point: re-plan or update an existing spec's plan without re-interviewing the spec.

### Session 2 — build

**`/se-exec`** drives the whole session:

1. Locate the relevant plan. `/se-exec` activation reads any existing `.super-exec/active` first and refreshes it with `phase: exec` while preserving any existing `active_plan` (and convenience `branch`) until plan resolution replaces it. If `/se-exec` was manually invoked with an explicit plan path (`plan.md` or a directory containing it), use that plan without asking for confirmation; the path is the confirmation. If no path was specified, check `.super-exec/active` for `active_plan`, resolve it, and ask the user to confirm that plan. If there is no active-plan marker, match branch/ticket → feature → most recent plan dir, then confirm the inferred match. If no plan exists, or the marker points at a missing plan, tell the user and stop. Once selected, refresh `.super-exec/active` with `phase: exec` and the selected `active_plan`. Read plan frontmatter, checklist, and spec for acceptance; if frontmatter has `branch`, the current git branch must match in normal mode, while `--worktree` validates the main checkout before creating the worktree and then lets worktree setup own branch checkout. A missing checklist is never treated as completed: completion requires frontmatter `status: completed`, or the first `## Execution Checklist` exists, has at least one item, and all items are checked. If no checklist exists and status is not completed, resume from `## Tasks` / handoff evidence or ask the user to confirm the resume point. At execution start, update plan `status` from `pending` to `in_progress`. Seed or sync the harness-native task/todo list from the plan's `## Execution Checklist` when available, using the CC `TodoWrite` primitive or its translated equivalent. The native task/todo tool is operational session state; plan frontmatter + checklist are durable local resume state.
2. **Present the two toggles once:**
   - *Review before each commit?* — default **off** (auto-commit per task).
   - *Auto-PR?* — default **off**. This is the "human in the loop?" switch.
     - **Off** → human in the loop: pause for a final work review, ask before opening a draft PR, and ask the user on any blocker that cannot be worked around.
     - **On** → no human in the loop: no further review; self-resolve blockers (amend the spec to the closest achievable behavior + note the limitation), and open the PR automatically. The PR review + manual merge remain the human's gate.
   With review-before-commit **off**, the user's toggle answer is explicit standing authorization to auto-commit per task — each per-task commit is a user-requested commit, not a proactive one — reconciling super-exec auto-commit with a host agent policy that otherwise forbids committing without an explicit per-action user request; this is a prose-level resolution (no host hook forces a commit). With the toggle **on**, that host policy still governs (per-task commits wait for approval; B1 hard-blocks commits while `.super-exec/gate-open` is open).
3. **Outer loop — review / fix**, wrapping an **inner loop — execute / verify**:
   - **Inner loop:** dispatch implementer subagents per task; each invokes the task's bound repo skill before hand-rolling. A **verifier subagent** then runs the repo verification **baseline** (always) plus the task's **task-specific** verification, and confirms the output works and matches the spec + plan. Not verified → fix → re-verify, until green. The verifier is the **first catch for spec divergence**: a result that does not match the spec is a **bug by default** — fix the code, never silently rewrite the spec (see Divergence & spec authority). Independent, file-disjoint tasks run in parallel; dependent or same-file tasks run sequentially. No worktrees by default; `--worktree` opt-in. When impeccable is enabled, UI tasks are built via `/impeccable craft` (see Optional: UI design).
   - On inner-loop-green, **commit** via `se-commit` (per task). If review-before-commit is on, show the diff + proposed message and wait. The plan checklist is marked only after the task is committed and outer-loop-clean; task-level completion is post-review, not pre-review.
   - **Code review:** an arch-gate pass first — does the implementation match the agreed architecture? Deviation → fix (re-enters the inner loop) → re-gate. Once the shape is sound, a deep-review pass: data-flow bugs → reuse-existing-utility check → pattern/consistency, plus an impeccable UI-critique lens when enabled. Findings are severity-tagged (Critical / Important / Minor). Critical/Important block and re-enter the inner loop; Minor is reported, non-blocking. A fresh reviewer re-reviews after fixes. Loop until clean.
4. **End-of-build → PR decision** (governed by the *Auto-PR* toggle):
   - **Auto-PR ON:** no final human review. Mark the final item complete in the native task/todo tool first, sync the plan checklist, update plan `status` to `completed`, and invoke `se-pr` directly to open the PR.
   - **Auto-PR OFF:** write `.super-exec/gate-open`, present the work for a final human review (commits are blocked while the gate is open), and **wait**. Once the human resolves the review, **ask "Create a draft PR?"** — **No** → mark the final item complete in the native task/todo tool first, sync the plan checklist, update plan `status` to `completed`, clear `gate-open`, clear `.super-exec/active`, end the session (the work stays committed on the branch, no PR); **Yes** → mark the final item complete in the native task/todo tool first, sync the plan checklist, update plan `status` to `completed`, clear `gate-open` and invoke `se-pr`.
5. **PR (`se-pr`):** create the pull request. **If the repo has a `create-pr` skill, follow it 100%** (it owns version bump, draft-first creation, evidence capture, and any PR template rules). Fallback when no repo skill exists: use the repo `pull_request_template.md` when present (N primary sections → N primary sections, no extra; sub-sections and detail allowed), otherwise use the built-in `plugin/skills/se-pr/pr-template.md`; draft mode, evidence for UI changes when available, and the default PR-title format (see Default conventions). The PR is created directly — the decision to create it was already made (Auto-PR ON, or the human's "Yes" at step 4); no second draft-approval wait in the fallback path. If PR creation fails, surface the failure and ask whether to retry or repair PR creation; do not restart plan execution or mark the plan incomplete. Once a PR exists, review comments and CI failures belong to `se-pr-triage` or explicit user action, not plan execution. `se-pr` clears `.super-exec/active` on PR completion.

`/se-pr-triage` is the fourth entrypoint and owns post-PR review/CI triage only. It writes `.super-exec/active` with `phase: pr-triage` on activation, processes one triage round, and clears `.super-exec/active` at every exit path (no PR/access failure/nothing actionable/end-of-round). It is not auto-chained from `se-pr`; the human invokes it explicitly or wraps it in `/loop`.

**Resume:** the controller monitors its own context. At a threshold it auto-writes `handoff.md` (via super-exec's own `se-handoff` skill, into `.super-exec/`) and pauses; the user runs `/clear` and re-runs `/se-exec`, which detects the active plan marker + handoff and resumes from the next unstarted task. Each outer-loop-clean task is also marked in the plan's first `## Execution Checklist` section; if every checklist item is complete, `/se-exec` tells the user the plan is already completed instead of restarting it.

## Verification design

- **Baseline (always runs):** detected per repo from package scripts / `AGENTS.md` / a repo skill. Examples: frontend → `lint:fix` + `type-check`; `svc-ccc-backend` → `dotnet build` passes.
- **Task-specific (adaptive, agreed in the plan):** if a test suite already covers the touched area → write tests first (TDD) for new code; if no tests exist there → do **not** scaffold unit tests — use browser-real verification (playwright/e2e via the repo dev-server skill), endpoint calls, or a custom script. UI changes require a real-browser check with evidence. For any playwright, e2e, or browser check, the plan records the local dev-server skill or fallback command, readiness signal, browser command, and teardown/reuse rule; the verification runner scans local repo skills and starts or confirms the local dev server before running the browser/e2e command. If no skill or fallback command is known, browser/e2e verification is blocked until the startup path is resolved.
- Verification runs as a **runner/judge split**: a cheap runner subagent executes baseline + task-specific verification in its own throwaway context and reports evidence; a strong, non-fast judge (the verifier/reviewer) evaluates that evidence against the spec + plan. No verification runs inline in the controller, and no "done" claim is made without shown evidence (test output, screenshots).
- **Subagent model tiers are assigned by role, per harness** — named by family alias (never a pinned version), resolved through the internal `se-subagent` skill. Claude Code: `opus` (strong, non-fast) for discuss, plan, review, and verifier judgment; `sonnet` (mid, pinned) for implementers/fixers; `haiku` (cheap) for script-runners and finders. Cursor mapping (one-way, in `using-super-exec/references/cursor-tools.md`): for the strong roles, the strongest available reasoning model at high effort (e.g. latest GPT or Opus), falling back to default/inherit; latest composer non-fast for implementers, mid tasks, runners, and finders.
- **Final spec-match assertion.** Before the outer review loop reports a task — or the whole build — clean, the reviewer (which already holds the full diff + spec) makes one explicit assertion: *does the built behavior still match the spec?* This is a cheap cross-task-drift backstop on top of the per-task verifier; no extra subagent.

## Divergence & spec authority

**The spec is authoritative. Implementation must match it.** When implementation diverges from the spec, resolve it by this tree — never by silently rewriting the spec:

1. **Bug first (the default).** A divergence is assumed to be a defect in the implementation. Fix the code to match the spec. The verifier catches it per task; the reviewer catches cross-diff divergence as a Critical finding. No human needed.
2. **Implementation limitation** — the spec, as written, is not achievable (a real technical constraint blocks it, not a code mistake):
   - **a. Try a workaround** that still satisfies the spec's *intent*. If one exists, apply it — the spec is unchanged. No human needed (works even in Auto-PR mode).
   - **b. No workaround exists** — branch on whether a human is in the loop (the *Auto-PR* toggle is the signal):
     - **Human in the loop (Auto-PR OFF):** stop and ask the user — state the spec requirement, the limitation, and a recommendation. The human's answer may change **both** the spec (WHAT-only) and the implementation. If the change is architectural, recommend re-planning via `/se-plan`; otherwise update the spec + code inline.
     - **No human in the loop (Auto-PR ON):** the agent **amends the spec itself** to the **closest achievable** behavior and **annotates the reason** in the spec's *Decisions* section — e.g. *"Due to `<limitation>`, cannot achieve `<original behavior>`; closest achievable is `<X>`."* It then builds to the revised spec and continues — no interrupt. The amendment is WHAT-only (no code) and is committed (`docs:`); it lands in the same PR the human reviews and merges.

The **only** paths that change a committed spec during a build are a human decision (2b human-in-loop) or an Auto-PR-mode limitation-amend (2b Auto-PR). Both keep the spec a truthful, code-free statement of intent; neither edits the spec to paper over an ordinary bug.

## Optional: UI design via impeccable

`se-discuss`/`se-plan` first classifies whether the feature involves UI work (a frontend app, or the change touches components/styles). **If there is no UI work, it never asks.** If there is UI work, it asks once whether to incorporate the `impeccable` skill — **default YES**. The answer is persisted in the plan and honored across three touchpoints; `se-exec` re-asks only if a UI plan never recorded it.

- **Plan** — use impeccable `shape` to establish design direction and identify the states the design system doesn't cover (empty, loading, error, edge cases). Captured as design *intent* + planned tasks. No code — the plan rule holds.
- **Execute** — implementer subagents building UI tasks invoke `/impeccable craft` to build to production standard (design-system reuse, contrast/a11y, motion, responsive), rather than hand-rolling UI.
- **Review** — a reviewer subagent runs `/impeccable critique` (or `audit`) as an additional UI lens; findings feed the fix loop under the same realism filter as other reviewers.

**Availability:** impeccable may not be installed on every machine. super-exec detects it; if absent, it skips the UI passes gracefully, reports that it skipped and why, and suggests installing it — it never blocks the workflow. All three touchpoints invoke impeccable via a subagent to keep the controller lean; interactive `craft` iteration is surfaced to the user when needed.

## Enforced discipline (the rules the tool forces)

1. **Delegate by default.** Build, test, wide search, and long review run in subagents that report a summary — never inline in the controller.
2. **Verify before done.** No completion claim without baseline + task verification evidence.
3. **Scope guard (YAGNI).** Implement only what the plan specifies. No unrequested tests, sections, or scope. During execution, the only allowed plan edits are marking items complete in the first `## Execution Checklist` section and updating frontmatter `status` (`pending` / `in_progress` / `completed`).
4. **Reuse before writing.** Check the repo skill catalog and existing utilities/patterns before adding new code; invoke a covering skill (e.g. `create-api-service`) rather than hand-rolling. Skills are bound to tasks at plan time (see Repo skill catalog & task binding).
5. **Repo conventions first.** super-exec ships complete, opinionated default conventions so it works in a bare repo, but they are fallbacks: for any convention-bearing action, follow the repo's own skill 100% (every word) → then a detected repo pattern → then the tool default. The repo always wins; defaults only fill silence. This precedence is what makes the tool drop-in and adaptable to every repo. Prefer repo abstractions (e.g. RTK) over raw shell.
6. **No commit while a human-review gate is open; no PR reply without an approved draft.** Routine commits are expected (per-task auto-commit, the spec commit on approval, an Auto-PR-mode `docs:` amend); what is forbidden is committing while a review gate (`.super-exec/gate-open`) is open, and replying to a PR comment without an approved draft.
7. **Realism filter on review findings.** Never flag impossible cases (e.g. a negative index into an internally-controlled array the user cannot influence).
8. **Spec is WHAT-only — no code.** A spec carries high-level goals, requirements, and intentions, never implementation code. Code, file layout, and scaffolding belong to the plan. A spec changes only when a decision or documented behavior changes (see Divergence & spec authority).

Enforcement layers: strong directive language + red-flag tables + flowcharts in skill bodies; a mandatory TodoWrite checklist per phase; and selective Claude Code `PreToolUse` hooks active only during a super-exec session (marker `.super-exec/active`) — **nudge** (non-blocking) on heavy build/test run in the controller (N1), on raw git/gh commands (N2), and on writing fenced code into a spec under `docs/specs/` (N3 — "spec is WHAT-only; move code to the plan"); and one **block** (hard) — B1, on commit while a human-review gate is open. The "no PR reply without an approved draft" rule is enforced by skill-prose discipline (the se-pr red-flag), not a hook-level block — `gh pr comment` only trips the N2 nudge. Cursor enforces the B1 hard block natively where its hook API supports `deny` (via `beforeShellExecution` + `failClosed`); the nudges degrade to prose on Cursor — its pre-execution hooks expose no allow-path context injection, no controller-vs-subagent signal, and no generic pre-tool (file-write) event, so N1/N2/N3 cannot fire there.

## Artifacts & locations

| Artifact | Location | Committed? | Visibility |
|---|---|---|---|
| Branch context | `.super-exec/branch-context.json` or in-memory worker result | no | local |
| Spec | `docs/specs/NNNN-<feature>.md` (monorepo app-specific: `docs/specs/<app>/NNNN-<feature>.md`) | yes, after approval | team |
| ADR | `docs/adr/NNNN-<slug>.md` (app-specific: `docs/adr/<app>/…`) | yes, sparingly | team |
| Glossary | `CONTEXT.md` / `CONTEXT-MAP.md` | yes, lazy | team |
| Active marker | `.super-exec/active` (`phase`, `active_plan` immediately after `plan.md` write; optional `approved`; optional convenience `branch`) | no (gitignored) | local |
| Plan(s) | `.super-exec/<feature>/<YYYY-MM-DD>-<plan-name>/plan.md` with plan frontmatter (`title`, `feature`, `branch`, `status`) | **no (gitignored)** | local |
| Handoff / scratch | `.super-exec/<feature>/<…>/{handoff.md,scratch/}` | no | local |

One long-lived spec per feature; many dated plans per feature (≈ one plan ≈ one execute session ≈ one PR). **The spec never references the plan** (plans are local; teammates have only specs). `NNNN` is the next available four-digit number in that specs directory (find the highest existing prefix and increment), while `<feature>` is the work's feature name — the same slug as the branch and `.super-exec/<feature>/` plan directory (a ≤6-word summary of the change), lowercase-kebab; it is **never** the repo/project/package name, and the tool halts to confirm with the user if a candidate slug collides with the project name. For build sessions, the branch source of truth is plan frontmatter `branch`; `.super-exec/active` is only the local resume pointer. The tool keeps `.super-exec/` out of git via the repo-local, **uncommitted** `.git/info/exclude` — written idempotently by the SessionStart hook on every session, so the local-only artifact gets a local-only ignore with no edit to the team-shared `.gitignore`. (See ADR 0002.)

### Spec template

```
# <Feature>
> Ticket: <TICKET-ID | NO_TICKET>  ·  Status: <draft | active | superseded>
## Problem / Why
## Goals
## Non-goals (out of scope)
## Behavior / Requirements      (acceptance criteria, no HOW, no code)
## Domain terms                 (→ CONTEXT.md)
## Decisions                    (→ ADRs / resolved + limitation-driven amendments)
```

The spec is **WHAT-only**: no code blocks, no file layout, no scaffolding — those belong to the plan. A `PreToolUse` nudge (N3) reminds the agent when fenced code is written into a `docs/specs/` file during a session. (This dogfood spec is itself *about* a workflow, so it legitimately quotes templates and trees in fences — the nudge is a reminder, not a hard block, precisely so spec-about-a-spec cases are not walled off.)

### Plan template

```
---
title: <Plan title>
feature: <feature slug>
branch: <confirmed branch name>
status: pending
---
# <Plan name>
## Execution Checklist
- [ ] <Task 1 name>
- [ ] <Task 2 name>
- [ ] Final review / PR decision
## Goal              (+ link to spec)
## Architecture      components / responsibilities / data flow — prose +
                     mermaid/ASCII diagrams (HTML used only to render diagrams) +
                     folder/file structure as ASCII tree;
                     signatures/pseudo-code only where they clarify architecture
## Data Flow         diagram
## Tasks             overview-level; dependency notes; each states its own verification
## Verification      how to verify the whole plan works (baseline + acceptance)
### Browser/E2E Preflight
```

No change-files manifest, no copy-paste-ready code, no output mockups. Risks/open questions are resolved with the user before the plan is finalized. The `Final review / PR decision` checklist item is fixed bookkeeping for se-exec step 10, not an executable implementation task and not a task dispatched in step 6.

All plugin template files are pure copy-pasteable artifact templates. They start directly with the final artifact shape, without wrapper prose, "how to use this" instructions, or a fenced markdown block around the whole template. Fill/use rules live in the owning `SKILL.md` or nearby instruction docs.

## Convention delegation map

| super-exec step | repo skill (if present) |
|---|---|
| branch gate | `git-new-branch` |
| commit | `git-commit-message` |
| PR | `create-pr` (+ `pr-evidence-create`, `pr-upload-attachment`, `version-plan`) |
| UI verify / dev server | `local-dev-server` + playwright |
| spec interview | repo `grill-with-docs` if present, else bundled |
| handoff | bundled `se-handoff` (super-exec's own; writes to `.super-exec/`) |

### Repo skill catalog & task binding

Repo skills are a first-class reuse target for *any* task they cover, not only the convention actions above. During the **plan** phase a subagent enumerates the entire repo skill catalog (every `.claude/skills/*/SKILL.md` — name, description, argument-hint) and semantically matches each planned task to applicable skills. The plan records each binding explicitly — e.g. a frontend task "query a new API endpoint" is bound to **MUST invoke `create-api-service` before creating files**, never hand-rolled. The human reviews these bindings as part of plan review.

At **execute** time, implementer subagents are required to invoke a task's bound skill before writing code, and to re-check the catalog for any unplanned work a skill covers. A `PreToolUse` nudge on new-file creation during a super-exec session points back to the catalog as a backstop. Hard per-domain blocks (e.g. "never create a file under `services/` without `create-api-service`") are deferred to project scope (see Non-goals).

### Default conventions (fallbacks)

Used only when the target repo has no skill/pattern for the action (per ADR 0001). super-exec ships these so it works in a bare repo.

**Branch** (from `git-new-branch`): all-lowercase, `-` separated. With ticket → `<ticket-id>-<≤6-word-summary>` (e.g. `intcomp-1234-new-headline-note-banner`); no ticket → `<feat|fix|chore|ci|docs|test|style|refactor|perf>-<≤6-word-summary>`. Always `git fetch --all --prune` first; base `origin/develop`; create with `git checkout -b <name> origin/develop^0` (`^0` = no tracked upstream, set on first push).

**Commit**: owned entirely by the `se-commit` skill — staging isolation plus the message (the repo commit skill, e.g. `git-commit-message`, else a conventional fallback). The fallback conventional types include `feat`, `fix`, `refactor`, `style`, `test`, `docs`, `ci`, and `chore`; performance-only changes are `refactor` when they do not change behavior. The spec does not duplicate the full commit rules; see the `se-commit` skill for the authoritative definition.

**PR title** (used only in the `se-pr` fallback path when the repo has no `create-pr` skill): `<type>(<optional-scope>): <brief summary> - <TICKET-a>, <TICKET-b>`. Types: `feat`, `fix`, `ci`, `test`, `chore`, `perf`. Scope: in a **monorepo**, include the changed app/package scope when **exactly one** app changed, and omit it when **multiple** apps changed; in a **standalone repo**, omit the scope entirely. Tickets: comma-separated; use `NO_TICKET` when there is none. When a repo `create-pr` skill exists, its title format wins (the repo always wins — see Enforced discipline rule 5).

**PR body** (used only in the `se-pr` fallback path when the repo has no `create-pr` skill): mirror the repo `pull_request_template.md` when present. If the repo has no PR template, use the shipped built-in `plugin/skills/se-pr/pr-template.md` exactly as the starting body.

## Packaging & distribution

`super-exec` is a Claude Code plugin marketplace. `.claude-plugin/marketplace.json` at the repo root points `source` at the `./plugin` subfolder; only `plugin/` installs. Everything else (`research/`, `docs/`, dev notes) stays in the repo and never loads as plugin content; `research/` is additionally gitignored from any shared repo because it is mined from internal conversations.

```
super-exec/
├── .claude-plugin/marketplace.json   # source: ./plugin
├── plugin/                           # the installed plugin
│   ├── .claude-plugin/plugin.json
│   ├── .cursor-plugin/plugin.json    # Cursor config
│   ├── hooks/                        # PreToolUse guards + SessionStart marker
│   └── skills/
│       ├── using-super-exec/         # bootstrap; references/cursor-tools.md = the one-way CC→Cursor translation
│       ├── se-discuss/                 # + branch-gate.md, branch-context, spec-template.md
│       ├── se-plan/                  # + plan-template.md
│       ├── se-exec/                  # + worktree.md
│       ├── se-verify/, se-review/    # inner & outer loops
│       ├── se-pr/                    # + pr-template.md
│       ├── se-pr-triage/              # + ci-triage.md; post-PR review/CI triage
│       ├── se-handoff/               # + handoff-outline.md
│       ├── se-subagent/              # internal: model tiers + dispatch discipline (user-invocable: false)
│       └── se-commit/                # internal: staging-isolated commits (user-invocable: false)
├── docs/specs/0001-core-workflow.md  # this spec (dogfood)
├── research/                         # gitignored, local-only
└── README.md
```

Install per repo: `/plugin marketplace add <git-url>` then `/plugin install super-exec`.

super-exec is **self-contained**: it bundles its own workflow discipline (taking only useful inspiration from existing skills like superpowers where relevant, never depending on them) and assumes a teammate has installed **only super-exec**. It has no runtime dependency on superpowers or any non-bundled skill; the optional externals are `impeccable` (UI design/build/critique) and `caveman` (concise discuss-interview phrasing), both detect-and-skip and degrading gracefully. Repo-skill delegation is detection-based (ADR 0001), not a hard dependency. When the `superpowers` plugin happens to be co-installed, the two overlap and super-exec asserts a best-effort precedence — see **Coexistence with superpowers**.

## Coexistence with superpowers (skill precedence)

super-exec and the `superpowers` plugin both ship an always-injected bootstrap that claims the development workflow: superpowers injects `using-superpowers` wrapped in `<EXTREMELY_IMPORTANT>` ("if there is even a 1% chance a skill applies you MUST invoke it"); super-exec injects `using-super-exec` via its SessionStart hook. When both are installed they compete for the same triggers ("let's build X", "add Y", "change Z"), with no tiebreaker — so the model may drive feature work through superpowers' `brainstorming → writing-plans → executing-plans` instead of super-exec's `se-discuss → se-plan → se-exec`. This is observed, not theoretical.

**Resolution: a best-effort scoped override — super-exec wins the *driver* role wherever the two overlap; superpowers stays available for needs super-exec does not cover.**

- **Overlap (super-exec wins, do not invoke the superpowers equivalent as the driver):** discuss → `se-discuss` (not `brainstorming`); plan → `se-plan` (not `writing-plans`); build → `se-exec` (not `executing-plans` / `subagent-driven-development`); verify → `se-verify` (not `verification-before-completion`); review → `se-review` (not `requesting-code-review` / `receiving-code-review`); worktree isolation → `se-exec` (not `using-git-worktrees`); finish / PR → `se-pr` (not `finishing-a-development-branch`); subagent dispatch → `se-subagent` (not `dispatching-parallel-agents`). TDD is treated as a *technique inside* `se-verify` / `se-exec`, not a competing driver.
- **Gap (superpowers stays available, use it freely):** skills super-exec has no equivalent for — e.g. `systematic-debugging`, `find-skills`, `writing-skills`. The override never tells the model to ignore these.

**Best-effort, not deterministic — and stated plainly as such.** super-exec does not require disabling superpowers and does not claim to fully neutralise its forceful bootstrap. The override wins by **specificity, not volume**: a clause that explicitly names superpowers and states the overlap mapping out-ranks a generic loud block, because a specific instruction about a named competitor beats generic urgency. Escalating the wrapper *name* (`EXTREMELY_IMPORTANT_PRO_MAX`, `_ULTRA`, …) is rejected — the tag name is a delimiter, not a priority dial; the model does not rank suffixes, so an invented superlative buys no authority and reads as noise. The clause therefore uses the same `<EXTREMELY_IMPORTANT>` register as superpowers (parity) and carries its weight in the content. The deterministic lever (a precedence line in the repo's `AGENTS.md`, which superpowers' own priority ladder obeys above its skills) is **out of scope** — the chosen posture is best-effort, no repo-file writes.

**The override applies to the controller AND every dispatched subagent** ("make agents ignore superpowers" on overlap), so a finder / implementer / verifier / reviewer subagent does not drift into a superpowers skill for work the super-exec spine owns.

**Delivery (single layer).** `using-super-exec` carries a `<EXTREMELY_IMPORTANT>`-wrapped precedence section, **conditionally worded** ("*if superpowers is also loaded*"). Because the SessionStart hook already injects the full `using-super-exec` content, this clause is always in context; it is a no-op when superpowers is absent, so the self-contained / "assume only super-exec" posture is preserved. **There is no detection step and no user-facing output** — no greeting, no disable prompt, no SessionStart probe for superpowers; the clause is model-facing only and the model applies it when it observes superpowers' skills in context. (A detection-gated present-tense emphasis in the SessionStart hook was considered and cut — see ADR 0004 — as not worth the added hook code, cross-harness fragility, and test surface for a marginal salience gain over the always-present clause.)

**Acceptance:**
- With superpowers co-installed, a "let's build / fix / change X" prompt routes to `se-discuss` (then the super-exec spine), not to `superpowers:brainstorming`.
- A standalone debugging request (no super-exec spine work) still reaches `superpowers:systematic-debugging` — the override does not suppress gap skills.
- With superpowers absent, behavior is unchanged: the clause is a no-op and nothing superpowers-related is surfaced.
- `superpowers` appears under `plugin/` only in `using-super-exec` — enforced by the self-containment test's allowlist.

This decision is recorded in ADR 0004.

## Portability

Authored and dogfooded on Claude Code. Skills are written in **Claude Code language** — CC tool names (`Read`, `Edit`, `Write`, `Task`, `AskUserQuestion`, `TodoWrite`), model aliases (`opus` / `sonnet` / `haiku`, never pinned version strings), and hook event names. Cross-harness support is a **single one-way translation table** at `using-super-exec/references/cursor-tools.md`; individual skills do not branch by harness or spell alternate tool APIs inline. The table maps CC primitives — tools, model aliases (strong → best high-effort reasoning model; mid/cheap → latest composer non-fast), hook events, env vars — to each harness equivalent. Model tiers resolve through the internal `se-subagent` skill. Because Cursor runs had skipped the soft-referenced table and inherited the session model for every subagent, the SessionStart hook injects `cursor-tools.md` on Cursor. The table stays tier-named and slug-free; the actual slug is picked from the dispatch tool's allowlist at dispatch time. A `.cursor-plugin` config ships with the plugin. CC-only *nudge* hooks (N1/N2/N3) degrade to prose on Cursor; the hard *block* (B1, no commit while the review gate is open) runs natively via Cursor's `beforeShellExecution` (`deny` + `failClosed`).

## Domain terms

- **Discuss** — the spec phase: interview to shared understanding of the WHAT.
- **Plan** — the architecture + verification design phase, and its local `plan.md` artifact. One feature has many plans over time.
- **Feature** — a long-lived unit of work with one committed spec.
- **Controller** — the main session/agent that orchestrates and delegates; stays lean.
- **Inner loop** — execute/verify, until a task is verified.
- **Outer loop** — review/fix, until code review is clean.
- **Baseline** — the per-repo verification that always runs.
- **Gate** — a human checkpoint (spec-approval review/fix loop, plan review, the two execute toggles, the final-review + create-PR decision).
- **Repo skill** — a `.claude/skills/*` in the target repo whose conventions override tool defaults.
- **Auto-PR mode** — the state when the *Auto-PR* toggle is ON: no human in the loop after the build starts; blockers self-resolve and the PR is opened automatically. The toggle is the canonical "human in the loop?" signal.
- **Final-review gate** — the human work-review at end-of-build, run only when Auto-PR is OFF; opens `.super-exec/gate-open` and is followed by the "Create a draft PR?" decision (No → done, no PR; Yes → `se-pr`).
- **Implementation limitation** — a divergence where the spec as written is genuinely not achievable (a real constraint, not a code bug). Triggers the workaround → ask-or-amend tree (see Divergence & spec authority).
- **Closest-achievable amendment** — an Auto-PR-mode, agent-authored spec change to the nearest behavior that *is* achievable, annotated with the limitation in the spec's Decisions section; WHAT-only, committed `docs:`, reviewed in the PR.
- **Spec authority** — the principle that the spec is the contract: implementation must match it, divergence is a bug by default, and the spec is amended only by a human decision or an Auto-PR-mode closest-achievable amendment.
- **Skill precedence** — super-exec's best-effort claim to the workflow-driver role when the superpowers plugin is co-installed: super-exec wins where the two overlap; superpowers stays available for gaps (see Coexistence with superpowers).
- **Overlap bucket** — workflow needs both plugins cover; super-exec's spine skill is the driver and the superpowers equivalent is not invoked as driver (discuss/plan/build/verify/review/worktree/PR/dispatch).
- **Gap bucket** — needs super-exec has no equivalent for (e.g. systematic-debugging, find-skills, writing-skills); superpowers stays available and is used freely.
- **Best-effort override** — precedence asserted by specific, named clause content (not by tag-name escalation, detection, or by disabling superpowers); the clause is always present and conditionally worded, a no-op when superpowers is absent.

## Decisions

See `docs/adr/` for: repo-skill delegation precedence (0001); local-only plans / spec-plan visibility boundary (0002); skills-only entrypoints, no thin commands (0003); superpowers co-install skill-precedence (0004).

## Related specs

- **`se-pr-triage`** — implemented as the fourth entrypoint and specced in [`0002-pr-triage-watch-bot.md`](0002-pr-triage-watch-bot.md). One loop-safe triage round per invocation over two tracks: review comments (CodeRabbit + human) triaged Fix/Decline/Answer/Defer and replied in-thread under a mandatory human approval gate, and CI failures (Playwright, Cycode, lint/type/unit, SonarCloud, PR-title) investigated and resolved autonomously (flaky → rerun once; real → fix via the build verify/review loops), never replied to. The author's two rules are carried into the spec: sequencing — fix → commit → **push** → *then* reply (never reply before the fix is pushed); realism — bots don't know the full data flow or reachability, so don't fix comments that add needless complexity for impossible cases.
