---
name: se-plan
description: Use this when a spec is agreed and it's time to decide HOW — architecture, file structure, verification, and which existing repo skills to reuse — before writing any code. Triggers on "plan this", "design the implementation", "how should we build it", or moving from a spec toward code. Produces a reviewed plan.md. The second step of the super-exec workflow; invoke after se-discuss, or to re-plan an existing spec without re-discussing.
---

# se-plan — Plan Phase

se-plan drives the **Plan (architecture + verification)** phase of the super-exec gate-driven workflow. It reads the spec, designs the architecture through codebase research and user risk-grilling, binds repo skills to tasks, designs verification, and writes a `plan.md`. It runs **automatically after se-discuss** — se-discuss auto-chains into se-plan once the spec is approved (for the first-chosen feature when a session produced multiple specs), so the user does **not** invoke `/se-plan` manually in the normal flow. `/se-plan` is also a **manual re-entry point**: invoke it to re-plan an existing spec, or — with no argument — to pick up the **next unplanned spec** from a multi-feature split (see step 1 auto-discovery). When the selected spec has no feature branch yet (features 2..N of a split, or a manual re-entry from a base branch), se-plan **owns creating that branch** off the current base. (The spec is normally committed by se-discuss, but may be uncommitted on disk if the user declined the commit or `docs/specs/` is gitignored — either is fine; se-plan reads the on-disk spec.)

Use a **strong non-fast model** (opus; see the `se-subagent` skill for tier guidance) for architecture design, risk-grilling, and verification judgment. Dispatch **finder subagents** (cheap / haiku tier; see the `se-subagent` skill) for all codebase research and catalog enumeration using the `Task` tool.

---

## Session activation (do this FIRST, before the checklist)

Invoking this skill — typed `/se-plan` or model auto-invoked to plan/re-plan a committed spec —
**means a super-exec design session is active**. As the very first action, **write the session
marker** `.super-exec/active` in the repo root (create `.super-exec/` if needed), e.g. `phase: plan`
and `started: <current UTC ISO-8601>`. Existence + mtime make the hooks/guards live. After `plan.md`
is written, this same marker is updated immediately with `active_plan: <repo-relative path to plan.md>`;
approval is not the first time `active_plan` is recorded. The plan frontmatter is the source of truth
for branch metadata; `.super-exec/active` may carry `branch:` only as local convenience, never as the
authoritative branch contract. The stale-marker decision is a model-judged heuristic with no fixed TTL.
**Immediately after writing the marker, invoke `/se-local-ignore`.** Behavior is identical for manual and auto invocation.
If invoked with a feature slug or ticket argument, use it to locate the spec — still confirm the match. If invoked with no argument (and not auto-chained), auto-discover the next unplanned spec (step 1).

---

## Mandatory Ordered Checklist

Work through every item in order. Do NOT skip any item, even for simple work.

- [ ] **1. Locate (auto-discovery) + read the spec**
- [ ] **2. Research the architecture via subagents**
- [ ] **3. Map file structure first**
- [ ] **4. Enumerate the full repo skill catalog**
- [ ] **5. UI classification → impeccable auto-use (never ask)**
- [ ] **6. Resolve every risk and open question with the user**
- [ ] **7. Design verification**
- [ ] **8. Prepare the plan using the exact template**
- [ ] **9. Reuse the spec's feature slug + collision gate**
- [ ] **10. Plan self-review**
- [ ] **11. Plan-review gate**

---

## 1. Locate the spec (with auto-discovery) and read it

When auto-chained from se-discuss, plan the spec se-discuss **selected and passed as the argument** — in a multi-feature split that is the first-chosen feature, not "whatever was written last." Trust the passed slug/path.

On a **manual re-entry**:

- **With a feature slug / ticket argument** → locate that spec at `docs/specs/NNNN-<feature>.md` (or `docs/specs/<app>/NNNN-<feature>.md` in monorepos), matching the unnumbered feature slug after the four-digit prefix.
- **With no argument** → auto-discover the next unplanned spec. In a monorepo, scope discovery to **one app's** `docs/specs/<app>/` (numbering is per-app, so each app has its own `0001`) — infer the app from the current context or ask which app. Within that directory, pick the **lowest-numbered spec that has no plan directory** matching its numbered name under `.super-exec/`. Plan-dir existence is the implicit "already planned" marker — there is no separate tracker file. Confirm the match with the user via `AskUserQuestion` ("Next unplanned spec is `0002-profile` — plan this?") before proceeding. This is how the remaining specs of a multi-feature split (see se-discuss) get picked up one at a time. **Caveat:** `.super-exec/` is local-only (gitignored), so this signal reflects *this machine* — on a fresh clone or a teammate's box every spec looks unplanned, so always confirm before planning.

**Dependency check.** If the selected spec's header has a `Depends on: <feature-slug>` line other than `none` (a **missing** line also means no dependency), resolve that slug to its sibling spec `docs/specs/[<app>/]NNNN-<slug>.md`, then check whether that sibling has a plan directory (ideally a completed build). If it does not, WARN the user via `AskUserQuestion` — state that the dependency is not built yet and ask whether to plan this spec anyway or switch to the dependency first. This is a non-blocking warning; the user decides.

Use the `Read` tool to read the selected spec in full. Identify all acceptance criteria. Do NOT proceed if no spec file is found on disk — tell the user to run `/se-discuss` first. (A spec that exists but is uncommitted is acceptable; only a genuinely missing spec blocks.)

**Branch ownership.** Decide the working branch by signal, in this order:

1. **Auto-chained from se-discuss** → you are already on the branch se-discuss created for the first-chosen feature; use it, do NOT create another.
2. **A plan directory already exists for this spec** (a re-plan) → reuse that plan's frontmatter `branch`; do NOT derive a fresh name (that would spawn a divergent branch) unless the user explicitly wants a new plan/branch.
3. **Otherwise** (a fresh feature with no plan dir — features 2..N of a split, or a manual re-entry) → **se-plan owns branch creation**: run [@../se-discuss/branch-gate.md](../se-discuss/branch-gate.md) **Phase B** now to confirm the branch name (seed the ticket from the spec's own `Ticket:` header), used in the plan frontmatter (step 8); create it after plan approval (step 11, Phase C).

Never assume the current branch belongs to this spec just because it is not a base branch. If the current branch is neither the auto-chained branch nor the recorded plan `branch`, confirm/create rather than planning onto an unrelated feature branch.

**Spec-availability guard (multi-feature split).** A split commits every spec on the **first** feature's branch, so specs 2..N reach the base only when that first PR merges. Before se-plan creates a feature-2..N branch off the base, verify the selected spec file exists on that base. If it does not (the carrying PR has not merged yet), **STOP and ask** — the user must either wait for the prior feature's PR to merge into the base, or branch this feature off the previous feature's branch. Never silently create a branch whose base lacks the spec: that leaves `/se-exec` with no spec to read and silently breaks the spec-is-the-contract invariant.

## 2. Research the architecture via subagents

Dispatch finder subagents using the `Task` tool to explore the codebase: existing patterns for the touched area, data models, service/module boundaries, naming conventions, relevant source files, and any existing tests covering the area. Do NOT guess at structure. Do NOT ask the user what a subagent can discover.

## 3. Map file structure first

Before defining tasks, decide which files/units will be created or modified and the single responsibility of each. Apply these rules: units have clear boundaries and well-defined interfaces; files are small and focused; files that change together live together; follow existing patterns in the codebase. This file map drives task decomposition.

## 4. Enumerate the full repo skill catalog

Dispatch a finder subagent (via the `Task` tool) to read every `.claude/skills/*/SKILL.md` (collect: name, description, argument-hint). **Semantically bind matching skills to tasks.** Record each binding explicitly in the plan — e.g., a task "query a new endpoint" → "**MUST invoke `create-api-service` before creating files**". Repo skills are a first-class reuse target for any task they cover; never hand-roll what a skill provides.

## 5. UI classification → impeccable auto-use (never ask)

Classify whether the feature involves UI work (a frontend app, or the change touches components/styles). **Never ask the user whether to use impeccable — use it automatically when it is installed, skip it when it is not.**

- **No UI work** → impeccable is never used. Skip to the next step.
- **UI work present** → note the UI classification in the plan, then detect whether impeccable is installed (glob `.claude/skills/impeccable*/SKILL.md` or equivalent).
  - **If absent:** skip the UI design pass, report that it was skipped and why, suggest installing impeccable, and continue — never block, never ask.
  - **If present:** dispatch impeccable `shape` via a subagent (using the `Task` tool) to establish design direction and identify states the design system does not cover (empty / loading / error / edge). Capture output as design INTENT + planned tasks — NO code (the no-code task rule applies here too).

## 6. Resolve every risk and open question with the user

Use the `AskUserQuestion` tool to interview the user one question at a time, walking each branch of the decision tree. For each question, provide your recommended answer. If a question is answerable by exploring the codebase, explore it via a subagent (using the `Task` tool) instead of asking. **The plan carries zero open items into execution.** Do not defer anything to "figure it out during execution."

## 7. Design verification

Record the full verification strategy in the plan:

- **Baseline (always runs):** detect per repo from `package.json` scripts, `AGENTS.md`, or a repo skill via a `Task` subagent. Examples: frontend → `lint:fix` + `type-check`; .NET service → `dotnet build` passes. Record the exact commands.
- **Task-specific (adaptive):** if a test suite already covers the touched area → write tests first (TDD) for new code. If NO tests exist there → do NOT scaffold unit tests; use browser-real verification (playwright via the repo dev-server skill), endpoint calls, or a custom script instead. UI changes require a real-browser check with evidence.
- **Playwright / e2e preflight:** for any playwright, e2e, or browser check, scan the repo skill catalog (`.claude/skills/*/SKILL.md`, `.cursor/skills/*/SKILL.md`, `plugin/skills/*/SKILL.md`, or the harness's native skill-discovery output) for a local dev-server skill (`local-dev-server`, `dev-server`, or equivalent) and bind it in the plan. If no skill exists, detect the repo's dev-server command from project scripts/docs (`package.json`, `Makefile`, `AGENTS.md`, README, or equivalent) and record that fallback. If neither a skill nor command can be found, do not choose playwright/e2e until the user resolves the server startup path. Record the dev-server skill or fallback command, readiness signal (URL/port/log line), test command, and teardown/reuse rule. Browser/e2e verification must start or confirm the local dev server before running the test command.
- **Runner → judge split:** a cheap runner subagent (dispatched with the `Task` tool) executes baseline + task-specific verification in its own throwaway context and returns structured EVIDENCE (exit codes, counts, relevant log excerpts). A strong non-fast judge (opus) evaluates that evidence against spec + plan. No verification runs inline in the controller. "Done" requires shown evidence. See the `se-subagent` skill for tier guidance.

## 8. Prepare the plan using the exact template

See [plan-template.md](./plan-template.md) — the canonical example for plan output shape.

The template file is copy-pasteable markdown only: it starts directly with YAML frontmatter, has no outer explanatory heading/prose, and has no fenced code-block wrapper. Frontmatter is metadata, not a top-level section. Include YAML frontmatter before all sections: `title`, `feature`, `branch`, and `status`. Use the plan title, the spec feature slug, the confirmed branch name (from the discuss branch gate when auto-chained, or from se-plan's own Phase B confirmation in step 1 when se-plan owns the branch), and status: `pending`; if a value is genuinely unavailable, keep the field but leave the value blank rather than inventing it.

Sections must appear in this exact order with no additional top-level sections: `## Execution Checklist`, `## Goal`, `## Architecture`, `## Data Flow`, `## Tasks`, `## Verification`, then one `## <Task name>` section per executable task. The first section after frontmatter is `## Execution Checklist`: one checkbox per executable task (task name only), plus the fixed literal `Final review / PR decision`. That final item is session bookkeeping for se-exec step 10, not an executable task, and must not appear under `## Tasks`.

**Todo/checklist format (mandatory in generated plans):** `## Execution Checklist` and `## Tasks` list **brief task names only** — no Outcome, Skills, Dependencies, Verification, or implementation detail on checklist lines. Put all task detail in separate `## <Task name>` body sections immediately after `## Verification` (or after `## Tasks` if you prefer grouping, but every task section must exist). [plan-template.md](./plan-template.md) is the canonical shape. Checklist task names for executable tasks must exactly match the task names in `## Tasks` and in each `## <Task name>` heading.

Tasks are OVERVIEW-LEVEL in their detail sections: they describe what to accomplish and why, NOT how to write it. No copy-paste-ready code. No change-files manifest. No output mockups. Architecture may include signatures or pseudo-code ONLY where they clarify architecture. No placeholders in the completed plan: replace every template placeholder; never write "TBD", "TODO", "add error handling", "handle edge cases", or "similar to Task N".

## 9. Reuse the spec's numbered name + collision gate

Write the plan to `.super-exec/NNNN-<feature>/<YYYY-MM-DD>-<plan-name>/plan.md`. The `NNNN-<feature>` directory MUST reuse the spec's full name — the four-digit `NNNN` prefix and the `<feature>` slug exactly as they appear in the spec file `docs/specs/NNNN-<feature>.md` (the ≤6-word lowercase-kebab feature summary). In a **monorepo** (specs at `docs/specs/<app>/NNNN-<feature>.md`, where numbering is per-app), include the `<app>` segment in the plan path too — `.super-exec/<app>/NNNN-<feature>/…` — so two apps sharing a number/slug do not collide, and the spec↔plan-dir mapping (used by next-unplanned discovery in step 1) stays unambiguous. The `<feature>` slug is NEVER the repo basename, the `package.json` `name`, or the app name. Apply the collision gate: if the candidate slug matches the repo basename or `package.json` `name`, **HALT** and use `AskUserQuestion` to confirm the real feature with the user. Use today's date for `<YYYY-MM-DD>`. Immediately after `plan.md` is written, update `.super-exec/active` with `phase: plan` and `active_plan: .super-exec/NNNN-<feature>/<YYYY-MM-DD>-<plan-name>/plan.md` (repo-relative). This write happens before plan approval so resume/session orientation has a concrete plan path as soon as the plan file exists.

## 10. Plan self-review

Before presenting the plan, scan it for: (a) **spec coverage** — point each spec requirement to a task; list any gaps; (b) **consistency** — names, signatures, and module boundaries used in later tasks match earlier ones; (c) **scope** — focused enough for one plan; (d) **status tracking** — every executable task has a matching unchecked item in `## Execution Checklist` and `## Tasks`, each with a matching `## <Task name>` detail section, and the final `Final review / PR decision` item is present exactly once outside `## Tasks`; (e) **checklist brevity** — no implementation detail on checklist lines. Fix all findings inline. A plan with gaps, inconsistencies, missing checklist items, verbose checklist lines, or open items must not advance to the gate.

## 11. Plan-review gate

Present the architecture + data flow + task bindings + verification design. The user reviews. If the user requests changes, edit the plan and re-run self-review before presenting again. Only after the user approves the plan, keep the existing `active_plan` and update `.super-exec/active` with `approved: <current UTC ISO-8601>` if approval metadata is present/used. The plan frontmatter status remains `pending` after approval; se-exec changes it to `in_progress` only when execution starts, then `completed` at the PR/no-PR exit after the final checklist item is complete.

**If se-plan owns the branch** (step 1 branch ownership — the spec had no feature branch yet), now run [@../se-discuss/branch-gate.md](../se-discuss/branch-gate.md) **Phase C: create/switch** the confirmed branch off the current base, so the session ends on the feature branch ready for `/se-exec`. When auto-chained from se-discuss, the branch already exists — skip creation. `plan.md` is local (gitignored), so there is no commit tied to this branch here; branch creation only sets up the build session.

Approval gates the fresh-session execution handoff: then instruct the user to start a **FRESH session** and run `/se-exec`. **Do NOT auto-start execution. Do NOT invoke `/se-exec`.**

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "I'll write copy-paste code in tasks" | Add code blocks, file diffs, or implementation scaffolding to task descriptions | Tasks are overview-level only. Describe what to accomplish. Remove the code. Architecture may have signatures only where they clarify boundaries — not as scaffolding. |
| "I'll cram task detail into the checklist" | Put Outcome, Skills, Verification, or commands on `## Execution Checklist` or `## Tasks` lines | Checklist lines are brief task names only. Details belong in separate `## <Task name>` sections. See [plan-template.md](./plan-template.md). |
| "I'll hand-roll the API call / git op / scaffold" | Implement something directly without checking the skill catalog | Enumerate the full catalog first. If a skill covers it, bind it to the task explicitly. Never hand-roll what a skill provides. |
| "No tests here, so I'll scaffold some unit tests" | Add a `__tests__/` dir and stub files when no test suite exists in the touched area | Do NOT scaffold. Use browser-real verification, endpoint calls, or a custom script instead. Scaffolding untested tests is noise. |
| "I'll ask impeccable even though there's no UI" | Invoke impeccable when the feature has no frontend / component / style changes | Never use impeccable when there is no UI work. |
| "I'll ask the user whether to use impeccable on this UI work" | Prompt the user to opt in/out of impeccable for a UI feature | Never ask. On UI work, use impeccable automatically when installed; skip silently (with a note) when absent. There is no opt-in question. |
| "I'll run playwright without starting the app" | Record a browser/e2e command but omit the local dev-server setup | Bind the repo's local dev-server skill if present; otherwise record the repo's fallback dev-server command. Record start, readiness, command, and teardown/reuse evidence before any browser/e2e command. |
| "impeccable isn't installed, I can't proceed" | Block or pause the workflow because impeccable is absent | Skip the UI design pass, report that it was skipped and why, suggest installing impeccable, and continue. Never block on an optional external. |
| "I'll leave this risk open for execution to resolve" | Write "TBD", "decide during implementation", or leave an unanswered question in the plan | Resolve everything now. Use `AskUserQuestion` to grill the user. Explore the codebase via `Task` subagent. The plan carries zero open items. |
| "I'll name the plan dir after the project / app" | Use the repo basename, `package.json` name, or app name as the `<feature>` slug | Reuse the spec's full numbered name (`NNNN-<feature>`) as the plan directory; the `<feature>` slug matches the spec's exactly. Collision gate halts on a mismatch with the repo basename. |
| "No argument, so I'll just re-plan the last spec" | Re-plan an already-planned spec on a no-arg invocation | No-arg discovery picks the lowest-numbered spec with NO plan directory (the next unplanned one). Confirm it before planning. Only re-plan an already-planned spec when the user explicitly asks. |
| "The spec has no branch — se-exec can sort it out" | Write the plan and hand off, leaving se-exec to hit a branch mismatch | If se-plan owns the branch (spec had none), create it after approval via branch-gate Phase C so the session ends on the feature branch. Do not push branch creation onto se-exec. |
| "This spec depends on an unbuilt feature, I'll proceed silently" | Ignore a `Depends on` whose dependency has no plan/build yet | Warn the user (non-blocking) and let them choose: plan anyway or switch to the dependency first. |
| "I'll start executing after the plan is done" | Invoke `/se-exec`, write implementation code, or continue beyond the gate | Stop at the plan-review gate. Instruct the user to start a fresh session and run `/se-exec`. |
| "I'll research the codebase by asking the user" | Ask the user about directory layout, existing patterns, naming, related code | Dispatch a `Task` subagent. Ask only what is not discoverable by reading the codebase. |
| "I'll define tasks before mapping file structure" | Jump into task decomposition without first deciding which files/units exist and what each owns | Map file structure first (step 3). Tasks flow from units with clear single responsibilities. |

---

## Architecture Design Discipline

**Map files before tasks.** Decide which files and units will be created or modified and the single responsibility of each before writing a single task. Units with clear boundaries and well-defined interfaces. Smaller, focused files. Files that change together live together. Follow existing patterns — dispatch a `Task` subagent if patterns are not obvious.

**No placeholders.** Every task, every component, every interface in the plan must be fully resolved. "TBD", "TODO", "add error handling", "handle edge cases", and "similar to Task N" are all forbidden. If something cannot be resolved, it is an open question — use `AskUserQuestion` to grill the user and resolve it before writing.

**No code in tasks.** Task detail sections explain what to accomplish and why, which repo skills to invoke, and how to verify. They do not contain code blocks, file diffs, import lists, or implementation scaffolding. Architecture sections may contain signatures and pseudo-code only where they illuminate component boundaries.

**Brief checklists, detailed body sections.** Generated `plan.md` files must mirror [plan-template.md](./plan-template.md): `## Execution Checklist` and `## Tasks` carry task names only; each task's Outcome, Skills, Dependencies, and Verification live under a dedicated `## <Task name>` section.

---

## Risk-Grilling Discipline

**One question at a time.** After every answer, decide the next most important unresolved risk or decision. Never batch questions. Always use the `AskUserQuestion` tool for each question.

**Provide a recommended answer.** For every question, state what you believe the answer is and why, then ask the user to confirm or correct. This surfaces hidden assumptions early.

**Walk the full decision tree.** For each architectural decision, enumerate the branches: "Should X be synchronous or asynchronous? I recommend async because `payments/retry.ts` already uses SQS — confirm, or is this a deliberate departure?"

**Research before asking.** If the answer can be found by reading the codebase, dispatch a `Task` subagent and bring the finding to the user rather than asking blindly.

**Resolve everything.** The plan carries zero open items into execution. If a risk cannot be resolved without a user decision, use `AskUserQuestion` now and record the decision.

---

## Verification Design Rules

1. **Baseline is detected, not assumed.** Run a `Task` subagent to identify the actual test/lint/build commands for the repo before recording them in the plan.
2. **Tests exist → TDD.** If the touched area already has test coverage, the plan must include writing tests first for new behavior — not retrofitting them after.
3. **No tests exist → do not scaffold.** Use real verification: playwright against a dev-server skill, direct endpoint calls, or a purposeful custom script. Document exactly what command will be run.
4. **Playwright/e2e needs a local server first.** Scan local repo skills for `local-dev-server`, `dev-server`, or equivalent instructions; bind the skill when present. If absent, detect a repo script/docs fallback and record it. If neither exists, resolve the startup path with the user before choosing browser/e2e verification. Record how the runner starts or reuses the server, waits for readiness, runs the browser/e2e command, and tears down any server it started.
5. **UI changes require a browser check with evidence.** A screenshot or DOM assertion from a real browser run. "It compiles" is not sufficient evidence for UI work.
6. **Runner/judge split is mandatory.** The runner subagent (cheap / haiku tier) executes and returns structured EVIDENCE. The judge subagent (strong non-fast / opus tier) evaluates correctness against spec + plan. No inline verification in the controller. No "done" claim without shown evidence. See the `se-subagent` skill for tier guidance.

---

## Model and Tool Assignments

| Role | Model tier |
|---|---|
| Architecture design, risk-grilling, plan judgment (this skill) | Strong non-fast (opus) — see `se-subagent` skill |
| Codebase finder subagents, skill catalog enumeration | Cheap investigator (haiku) — see `se-subagent` skill |
| Verification runner subagent | Cheap script-runner (haiku) — see `se-subagent` skill |
| Verification judge subagent | Strong non-fast (opus) — see `se-subagent` skill |

Dispatch subagents with the `Task` tool. Use `Read` / `Edit` / `Write` for file operations. Use `AskUserQuestion` for all interactive questions to the user. Use `TodoWrite` to track checklist progress.
