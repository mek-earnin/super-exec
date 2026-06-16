# Core workflow

> Status: draft · Scope: shared (cross-repo) · Harnesses: Claude Code (primary), Cursor

A guided, gate-driven development workflow distributed as a Claude Code plugin. It carries a feature from shared understanding through to a pull request while enforcing the discipline the author repeatedly had to correct by hand: delegate heavy work to subagents, verify before claiming done, stay in scope, reuse before writing, respect each repo's own conventions, and never auto-commit or auto-reply where a human gate belongs.

## Problem / Why

Manual babysitting. Across ~2,627 past prompts in 7 EarnIn repos, the same corrections recurred: the agent ran builds/tests/wide searches inline and blew up context (forcing manual `/clear`), claimed "done" without verifying, over-reached scope, duplicated code instead of reusing utilities, used raw git instead of repo skills, auto-committed during review, and replied to PR comments without showing a draft. super-exec encodes those corrections as an enforced workflow so they stop happening.

## Goals

- A repeatable spec → plan → execute → verify → review → PR workflow with explicit human gates.
- Less babysitting: the agent self-delegates, self-verifies, and resolves ambiguity up front rather than mid-execution.
- Strong context hygiene: heavy work runs in throwaway subagent contexts; the controller stays lean.
- Respect every repo's own conventions by delegating convention-bearing actions to that repo's skills.
- Cross-harness: one portable skill set usable in Claude Code and Cursor.

## Non-goals (out of scope for v1)

- Post-PR bot-comment triage (CodeRabbit/Bugbot). Deferred to a separate `se-pr-triage` skill (see Fast-follow).
- Project-specific configuration layer (per-repo baked-in settings). Shared scope first; the tool detects per-repo conventions at runtime.
- Reinventing branch/commit/PR/dev-server/version logic. These are delegated to repo skills.
- Forced TDD everywhere, or plans containing copy-paste-ready code.

## Workflow (behavior / requirements)

Two sessions, one hard boundary at plan → execute.

### Session 1 — design

**`/se-shape`** drives the whole session:

1. **Branch/ticket gate** (runs only here). Inspect the current branch. If it is a feature branch matching the work, continue. Otherwise offer to create one: ask for the ticket, pull ticket info via the Atlassian MCP (fallback: ask the user to enable it, or supply a branch name). Branch convention precedence: **repo skill (e.g. `git-new-branch`) → detected repo pattern → default `<ticket-id>-<≤6-word-slug>` lowercase**. Always `git fetch --all --prune` first and branch off `origin/develop` (auto-detect develop vs main); create with no tracked upstream (`git checkout -b <name> origin/develop^0`).
2. **Shape (spec).** Interview the user relentlessly to reach shared understanding of the WHAT. Research the codebase via subagents instead of asking what can be discovered. Detect new-vs-update: glob `docs/specs[/<app>]`, match by ticket key + name, confirm with the user; an update interviews only the delta. Write/update the spec, sharpen terminology, update `CONTEXT.md` if it exists, offer an ADR only when the decision is hard to reverse + surprising + a real trade-off. **Human-review gate:** recommend the user commit the spec (and any ADR/CONTEXT change), type `docs`.
3. **Plan (architecture + verification).** Read the spec. Design the architecture, researching via subagents. Discover the full repo skill catalog and bind matching skills to tasks (see Repo skill catalog & task binding). **Resolve every risk and open question with the user up front** (grill like shape, but for HOW) — the plan carries no open items into execution. Design verification (see below) and reach agreement. If the feature involves UI work, ask about incorporating impeccable (default yes — see Optional: UI design). Write the plan. **Human-review gate:** the user reviews architecture + data flow.
4. End: instruct the user to start a fresh session and run `/se-exec`.

`/se-plan` is a re-entry point: re-plan or update an existing spec's plan without re-interviewing the spec.

### Session 2 — build

**`/se-exec`** drives the whole session:

1. Locate the relevant plan (match branch/ticket → feature → most recent plan dir; confirm). Read the plan; read the spec for acceptance.
2. **Present the two toggles once:**
   - *Review before each commit?* — default **off** (auto-commit).
   - *Auto-create PR when review is clean?* — default **off** (require human review first).
3. **Outer loop — review / fix**, wrapping an **inner loop — execute / verify**:
   - **Inner loop:** dispatch implementer subagents per task; each invokes the task's bound repo skill before hand-rolling. A **verifier subagent** then runs the repo verification **baseline** (always) plus the task's **task-specific** verification, and confirms the output works and matches the spec + plan. Not verified → fix → re-verify, until green. Independent, file-disjoint tasks run in parallel; dependent or same-file tasks run sequentially. No worktrees by default; `--worktree` opt-in. When impeccable is enabled, UI tasks are built via `/impeccable craft` (see Optional: UI design).
   - On each task going green, **commit** via the repo commit skill (`git-commit-message`, conventional, per task). If review-before-commit is on, show the diff + proposed message and wait.
   - **Code review:** an arch-gate pass first — does the implementation match the agreed architecture? Deviation → fix (re-enters the inner loop) → re-gate. Once the shape is sound, a deep-review pass: data-flow bugs → reuse-existing-utility check → pattern/consistency, plus an impeccable UI-critique lens when enabled. Findings are severity-tagged (Critical / Important / Minor). Critical/Important block and re-enter the inner loop; Minor is reported, non-blocking. A fresh reviewer re-reviews after fixes. Loop until clean.
4. **Optional final human review** (auto-commit is paused while it is open).
5. **PR:** if auto-PR is on, create it; otherwise present the PR draft and wait for approval. Creation delegates to the repo `create-pr` skill (which chains version bump, draft-first creation, evidence capture, and `pull_request_template.md`). Fallback when no repo skill exists: strictly follow `pull_request_template.md` (N primary sections → N primary sections, no extra; sub-sections and detail allowed), draft mode, evidence for UI changes when available.

**Resume:** the controller monitors its own context. At a threshold it auto-writes `handoff.md` (via super-exec's own `se-handoff` skill, into `.super-exec/`) and pauses; the user runs `/clear` and re-runs `/se-exec`, which detects the in-progress plan + handoff and resumes from the next unstarted task.

## Verification design

- **Baseline (always runs):** detected per repo from package scripts / `AGENTS.md` / a repo skill. Examples: frontend → `lint:fix` + `type-check`; `svc-ccc-backend` → `dotnet build` passes.
- **Task-specific (adaptive, agreed in the plan):** if a test suite already covers the touched area → write tests first (TDD) for new code; if no tests exist there → do **not** scaffold unit tests — use browser-real verification (playwright via the repo dev-server skill), endpoint calls, or a custom script. UI changes require a real-browser check with evidence.
- Verification runs as a **runner/judge split**: a cheap runner subagent executes baseline + task-specific verification in its own throwaway context and reports evidence; a strong, non-fast judge (the verifier/reviewer) evaluates that evidence against the spec + plan. No verification runs inline in the controller, and no "done" claim is made without shown evidence (test output, screenshots).
- **Subagent model tiers are assigned by role, per harness** (the plan records the concrete table). Claude Code: strong/non-fast (Opus) for shape, plan, review, and verifier judgment; mid (Sonnet) for implementers/fixers; cheap (Haiku) for script-runners and finders. Cursor: default/inherit (non-fast) for the strong roles; latest composer non-fast (e.g. composer-2.5) for implementers, mid tasks, runners, and finders.

## Optional: UI design via impeccable

`se-shape`/`se-plan` first classifies whether the feature involves UI work (a frontend app, or the change touches components/styles). **If there is no UI work, it never asks.** If there is UI work, it asks once whether to incorporate the `impeccable` skill — **default YES**. The answer is persisted in the plan and honored across three touchpoints; `se-exec` re-asks only if a UI plan never recorded it.

- **Plan** — use impeccable `shape` to establish design direction and identify the states the design system doesn't cover (empty, loading, error, edge cases). Captured as design *intent* + planned tasks. No code — the plan rule holds.
- **Execute** — implementer subagents building UI tasks invoke `/impeccable craft` to build to production standard (design-system reuse, contrast/a11y, motion, responsive), rather than hand-rolling UI.
- **Review** — a reviewer subagent runs `/impeccable critique` (or `audit`) as an additional UI lens; findings feed the fix loop under the same realism filter as other reviewers.

**Availability:** impeccable may not be installed on every machine. super-exec detects it; if absent, it skips the UI passes gracefully, reports that it skipped and why, and suggests installing it — it never blocks the workflow. All three touchpoints invoke impeccable via a subagent to keep the controller lean; interactive `craft` iteration is surfaced to the user when needed.

## Enforced discipline (the rules the tool forces)

1. **Delegate by default.** Build, test, wide search, and long review run in subagents that report a summary — never inline in the controller.
2. **Verify before done.** No completion claim without baseline + task verification evidence.
3. **Scope guard (YAGNI).** Implement only what the plan specifies. No unrequested tests, sections, or scope. Do not edit the plan during execution.
4. **Reuse before writing.** Check the repo skill catalog and existing utilities/patterns before adding new code; invoke a covering skill (e.g. `create-api-service`) rather than hand-rolling. Skills are bound to tasks at plan time (see Repo skill catalog & task binding).
5. **Repo conventions first.** super-exec ships complete, opinionated default conventions so it works in a bare repo, but they are fallbacks: for any convention-bearing action, follow the repo's own skill 100% (every word) → then a detected repo pattern → then the tool default. The repo always wins; defaults only fill silence. This precedence is what makes the tool drop-in and adaptable to every repo. Prefer repo abstractions (e.g. RTK) over raw shell.
6. **No auto-commit during human review; no PR reply without an approved draft.**
7. **Realism filter on review findings.** Never flag impossible cases (e.g. a negative index into an internally-controlled array the user cannot influence).

Enforcement layers: strong directive language + red-flag tables + flowcharts in skill bodies; a mandatory TodoWrite checklist per phase; and selective Claude Code `PreToolUse` hooks active only during a super-exec session (marker `.super-exec/active`) — **nudge** (non-blocking) on heavy build/test run in the controller and on raw git/gh commands; **block** (hard) on commit while a human-review gate is open and on PR-comment replies without an approved draft. Cursor enforces hard blocks natively where its hook API supports `deny` (commit-while-gate-open, via `beforeShellExecution` + `failClosed`); the nudges degrade to prose on Cursor — its pre-execution hooks expose no allow-path context injection and no controller-vs-subagent signal.

## Artifacts & locations

| Artifact | Location | Committed? | Visibility |
|---|---|---|---|
| Spec | `docs/specs/<feature>.md` (monorepo app-specific: `docs/specs/<app>/<feature>.md`) | yes (recommended at gate) | team |
| ADR | `docs/adr/NNNN-<slug>.md` (app-specific: `docs/adr/<app>/…`) | yes, sparingly | team |
| Glossary | `CONTEXT.md` / `CONTEXT-MAP.md` | yes, lazy | team |
| Plan(s) | `.super-exec/<feature>/<YYYY-MM-DD>-<plan-name>/plan.md` | **no (gitignored)** | local |
| Handoff / scratch | `.super-exec/<feature>/<…>/{handoff.md,scratch/}` | no | local |

One long-lived spec per feature; many dated plans per feature (≈ one plan ≈ one execute session ≈ one PR). **The spec never references the plan** (plans are local; teammates have only specs). `<feature>` is the work's feature name — the same slug as the branch (a ≤6-word summary of the change), lowercase-kebab; it is **never** the repo/project/package name, and the tool halts to confirm with the user if a candidate slug collides with the project name. The tool adds `.super-exec/` (and `research/`) to `.gitignore`.

### Spec template

```
# <Feature>
> Ticket: INTCOMP-####  ·  Status: active
## Problem / Why
## Goals
## Non-goals (out of scope)
## Behavior / Requirements      (acceptance criteria, no HOW)
## Domain terms                 (→ CONTEXT.md)
## Decisions                    (→ ADRs / resolved)
```

### Plan template

```
# <Plan name>
## Goal              (+ link to spec)
## Architecture      components / responsibilities / data flow — prose +
                     mermaid/ASCII diagrams (HTML used only to render diagrams) +
                     folder/file structure as ASCII tree;
                     signatures/pseudo-code only where they clarify architecture
## Data flow         diagram
## Tasks             overview-level; dependency notes; each states its own verification
## Verification      how to verify the whole plan works (baseline + acceptance)
```

No change-files manifest, no copy-paste-ready code, no output mockups. Risks/open questions are resolved with the user before the plan is finalized.

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

**Commit** (from `git-commit-message`): conventional, **no scope**, single line — `<type>: <brief summary>`. One logical change per commit; unrelated changes split into separate commits; no ticket number. Types: `feat` (new feature), `fix` (other behavior change, incl. adding `data-testid`), `refactor` (no behavior change: rename/move/rewrite), `style` (whitespace/format), `test` (tests/test-utils only), `docs` (comments/README/storybook/docs only), `ci` (`.github/` or CI tooling), `chore` (build/deps/dev tooling, incl. AI config/MCP/skills). Local commits only — PR merge squashes to the PR-title format.

## Packaging & distribution

`super-exec` is a Claude Code plugin marketplace. `.claude-plugin/marketplace.json` at the repo root points `source` at the `./plugin` subfolder; only `plugin/` installs. Everything else (`research/`, `docs/`, dev notes) stays in the repo and never loads as plugin content; `research/` is additionally gitignored from any shared repo because it is mined from internal conversations.

```
super-exec/
├── .claude-plugin/marketplace.json   # source: ./plugin
├── plugin/                           # the installed plugin
│   ├── .claude-plugin/plugin.json
│   ├── skills/  se-{shape,plan,exec,verify,review}/ + helpers (se-branch-gate, se-pr, se-handoff)
│   ├── commands/                     # /se-shape, /se-plan, /se-exec
│   ├── hooks/                        # PreToolUse guards + SessionStart marker
│   ├── .cursor-plugin/               # Cursor config
│   └── references/tool-map.md        # CC↔Cursor tool-name mapping
├── docs/specs/core-workflow.md       # this spec (dogfood)
├── research/                         # gitignored, local-only
└── README.md
```

Install per repo: `/plugin marketplace add <git-url>` then `/plugin install super-exec`.

super-exec is **self-contained**: it bundles its own workflow discipline (taking only useful inspiration from existing skills like superpowers where relevant, never depending on them) and assumes a teammate has installed **only super-exec**. It has no runtime dependency on superpowers or any non-bundled skill; the sole optional external is `impeccable`, which degrades gracefully. Repo-skill delegation is detection-based (ADR 0001), not a hard dependency.

## Portability

Authored and dogfooded on Claude Code; skill bodies use harness-neutral prose ("spawn a subagent and report a summary", "use a strong non-fast model") and never hardcode CC-only orchestration primitives, so Cursor runs the same skills via its own subagent mechanism (e.g. composer-2.5 non-fast). A tool-name mapping reference and a `.cursor-plugin` config ship with the plugin. CC-only *nudge* hooks degrade to prose on Cursor; hard *blocks* run natively via Cursor's `beforeShellExecution` (`deny` + `failClosed`).

## Domain terms

- **Shape** — the spec phase: interview to shared understanding of the WHAT.
- **Plan** — the architecture + verification design phase, and its local `plan.md` artifact. One feature has many plans over time.
- **Feature** — a long-lived unit of work with one committed spec.
- **Controller** — the main session/agent that orchestrates and delegates; stays lean.
- **Inner loop** — execute/verify, until a task is verified.
- **Outer loop** — review/fix, until code review is clean.
- **Baseline** — the per-repo verification that always runs.
- **Gate** — a human checkpoint (spec review, plan review, the two execute toggles, final review).
- **Repo skill** — a `.claude/skills/*` in the target repo whose conventions override tool defaults.

## Decisions

See `docs/adr/` for: repo-skill delegation precedence; local-only plans / spec-plan visibility boundary. (Created on acceptance.)

## Fast-follow (post-v1)

- **`se-pr-triage`** — watch the PR, collect bot (CodeRabbit/Bugbot) comments, draft replies, get human approval, reply in-thread. Two rules captured from the author: (1) sequencing — fix → commit → **push** → *then* reply (never reply before the fix is pushed); (2) realism — bots don't know the full data flow or whether end-users can reach a path; do not fix comments that add needless complexity for impossible cases.
