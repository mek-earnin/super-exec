---
name: se-plan
description: Use when a spec is agreed and it's time to decide HOW — architecture, file structure, verification, and repo-skill reuse — before code — "plan this", "design the implementation", "how should we build it"; also to re-plan an existing spec without re-discussing.
---

# se-plan — Plan Phase

Drives the **Plan (architecture + verification)** phase of super-exec's gate-driven workflow: read spec → design architecture via codebase research + user risk-grilling → bind repo skills to tasks → design verification → write the plan file (`plan-<plan-name>.md`). Runs **automatically after /se-discuss** (auto-chains once the spec is approved — for the first-chosen feature when a session produced multiple specs), so in the normal flow the user does **not** invoke `/se-plan` manually. `/se-plan` is also a **manual re-entry point**: re-plan an existing spec, or — with no argument — pick up the **next unplanned spec** from a multi-feature split (step 1 auto-discovery). When the selected spec has no feature branch yet (features 2..N of a split, or manual re-entry from a base branch), **se-plan owns creating that branch** off the current base. The spec lives under a config-driven root — `docs/specs/` (committed) or `.super-exec/specs/` (local) per `commitSpec` — either is fine; se-plan reads the on-disk spec from either root.

**Models.** Use a **strong non-fast model** (opus; see `/se-subagent` for tier guidance) for architecture design, risk-grilling, and verification judgment. Dispatch **finder subagents** (cheap / haiku tier; see `/se-subagent`) via the `Task` tool for all codebase research and catalog enumeration.

---

## Session activation (do this FIRST, before the checklist)

Invoking this skill — typed `/se-plan` or model auto-invoked to plan/re-plan a committed spec —
**means a super-exec design session is active**. As the very first action, **write the session
marker** `.super-exec/active` in the repo root (create `.super-exec/` if needed), e.g. `phase: plan`
and `started: <current UTC ISO-8601>`. Existence + mtime make the hooks/guards live. After the plan file (`plan-<plan-name>.md`)
is written, this same marker is updated immediately with `active_plan: <repo-relative path to the plan file, e.g. <root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md>`;
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

Auto-chained from /se-discuss → plan the spec /se-discuss **selected and passed as the argument** (in a multi-feature split, the first-chosen feature, not "whatever was written last"). Trust the passed slug/path.

**Manual re-entry:**

- **Feature slug / ticket argument** → locate that spec at `<root>/[<app>/]<feature>/spec-<feature>.md`, scanning BOTH roots (`docs/specs/` and `.super-exec/specs/`). Match by feature slug (slug-only; no numeric prefix). Confirm the match.
- **No argument** → auto-discover unplanned specs. Scan BOTH roots (`docs/specs/` and `.super-exec/specs/`) for specs. In a monorepo, scope discovery to **one app** (infer the app from context or ask which app) so only that app's specs are considered. A spec is "already planned" if a `plans/` directory exists for its feature under EITHER root (`commitSpec` and `commitPlan` are independent — the spec and its plan may sit under different roots). LIST all specs with NO plan folder, using each spec's `Depends on:` header for ordering context, and ASK the user via `AskUserQuestion` which to plan. This is how the remaining specs of a multi-feature split (see /se-discuss) get picked up one at a time. **Caveat:** `.super-exec/` is local-only (gitignored), so this signal reflects *this machine* — on a fresh clone or a teammate's box every local-only artifact looks absent, so always confirm before planning.

**Dependency check.** If the selected spec's header has a `Depends on: <slug>` line other than `none` (a **missing** line also means no dependency), resolve that slug to its sibling spec by scanning BOTH roots for `<root>/[<app>/]<slug>/spec-<slug>.md`, then check whether that sibling has a plan directory under EITHER root (ideally a completed build). If it does not, WARN the user via `AskUserQuestion` — state that the dependency is not built yet and ask whether to plan this spec anyway or switch to the dependency first. Non-blocking; the user decides.

Use `Read` to read the selected spec in full. Identify all acceptance criteria. Do NOT proceed if no spec file is found on disk — tell the user to run `/se-discuss` first. (A spec that exists but is uncommitted is acceptable; only a genuinely missing spec blocks.)

**Branch ownership.** Decide the working branch by signal, in this order:

1. **Auto-chained from /se-discuss** → you are already on the branch /se-discuss created for the first-chosen feature; use it, do NOT create another.
2. **A plan directory already exists for this spec** under either root at `<root>/[<app>/]<feature>/plans/` (a re-plan) → reuse that plan's frontmatter `branch`; do NOT derive a fresh name (that spawns a divergent branch) unless the user explicitly wants a new plan/branch.
3. **Otherwise** (a fresh feature with no plan dir — features 2..N of a split, or a manual re-entry) → **se-plan owns branch creation**: run [@../se-discuss/branch-gate.md](../se-discuss/branch-gate.md) **Phase B** now to confirm the branch name (seed the ticket from the spec's own `Ticket:` header), used in the plan frontmatter (step 8); create it after plan approval (step 11, Phase C).

Never assume the current branch belongs to this spec just because it is not a base branch. If the current branch is neither the auto-chained branch nor the recorded plan `branch`, confirm/create rather than planning onto an unrelated feature branch.

**Spec-availability guard (multi-feature split).** This guard applies only to a **committed** spec under `docs/specs/` — a local spec under `.super-exec/specs/` is per-machine and never travels via PR, so the base-availability concern does not apply. For a committed split, every spec lands on the **first** feature's branch, so specs 2..N reach the base only when that first PR merges. Before se-plan creates a feature-2..N branch off the base for a committed spec, verify the selected spec file exists on that base. If it does not (the carrying PR has not merged yet), **STOP and ask** — the user must either wait for the prior feature's PR to merge into the base, or branch this feature off the previous feature's branch. Never silently create a branch whose base lacks the committed spec: that leaves `/se-exec` with no spec to read and silently breaks the spec-is-the-contract invariant.

## 2. Research the architecture via subagents

Dispatch finder subagents (`Task` tool) to explore the codebase: existing patterns for the touched area, data models, service/module boundaries, naming conventions, relevant source files, existing tests covering the area. Don't guess structure. Don't ask the user what a subagent can discover.

## 3. Map file structure first

Before defining tasks, decide which files/units get created or modified and each one's single responsibility. Rules: clear boundaries + well-defined interfaces; small, focused files; files that change together live together; follow existing codebase patterns. This file map drives task decomposition.

## 4. Enumerate the full repo skill catalog

Dispatch a finder subagent (`Task` tool) to read every `.claude/skills/*/SKILL.md` (collect: name, description, argument-hint). **Semantically bind matching skills to tasks.** Record each binding explicitly in the plan — e.g. task "query a new endpoint" → "**MUST invoke `create-api-service` before creating files**". Repo skills are a first-class reuse target for any task they cover; never hand-roll what a skill provides.

## 5. UI classification → impeccable auto-use (never ask)

Classify whether the feature involves UI work (a frontend app, or the change touches components/styles). **Never ask the user whether to use impeccable — use it automatically when it is installed, skip it when it is not.**

- **No UI work** → impeccable is never used. Skip to the next step.
- **UI work present** → note the UI classification in the plan, then detect whether impeccable is installed (glob `.claude/skills/impeccable*/SKILL.md` or equivalent).
  - **If absent:** skip the UI design pass, report that it was skipped and why, suggest installing impeccable, and continue — never block, never ask.
  - **If present:** dispatch impeccable `shape` via a subagent (`Task` tool) to establish design direction and identify states the design system does not cover (empty / loading / error / edge). Capture output as design INTENT + planned tasks — NO code (the no-code task rule applies here too).

## 6. Resolve every risk and open question with the user

Use `AskUserQuestion` to interview the user one question at a time, walking each branch of the decision tree. For each question, provide your recommended answer. If a question is answerable by exploring the codebase, explore it via a subagent (`Task` tool) instead of asking. **The plan carries zero open items into execution.** Do not defer anything to "figure it out during execution."

## 7. Design verification

Record the full verification strategy in the plan:

- **Baseline (always runs):** detect per repo from `package.json` scripts, `AGENTS.md`, or a repo skill via a `Task` subagent. Examples: frontend → `lint:fix` + `type-check`; .NET service → `dotnet build` passes. Record the exact commands.
- **Task-specific (adaptive):** if a test suite already covers the touched area → write tests first (TDD) for new code. If NO tests exist there → do NOT scaffold unit tests; use browser-real verification (playwright via the repo dev-server skill), endpoint calls, or a custom script instead. UI changes require a real-browser check with evidence.
- **Playwright / e2e preflight:** for any playwright, e2e, or browser check, scan the repo skill catalog (`.claude/skills/*/SKILL.md`, `.cursor/skills/*/SKILL.md`, `plugin/skills/*/SKILL.md`, or the harness's native skill-discovery output) for a local dev-server skill (`local-dev-server`, `dev-server`, or equivalent) and bind it in the plan. If no skill exists, detect the repo's dev-server command from project scripts/docs (`package.json`, `Makefile`, `AGENTS.md`, README, or equivalent) and record that fallback. If neither a skill nor command can be found, do not choose playwright/e2e until the user resolves the server startup path. Record the dev-server skill or fallback command, readiness signal (URL/port/log line), test command, and teardown/reuse rule. Browser/e2e verification must start or confirm the local dev server before running the test command.
- **Runner → judge split:** a cheap runner subagent (`Task` tool) executes baseline + task-specific verification in its own throwaway context and returns structured EVIDENCE (exit codes, counts, relevant log excerpts). A strong non-fast judge (opus) evaluates that evidence against spec + plan. No verification runs inline in the controller. "Done" requires shown evidence. See `/se-subagent` for tier guidance.

## 8. Prepare the plan using the exact template

See [plan-template.md](./plan-template.md) — the canonical plan output shape.

The template file is copy-pasteable markdown only: it starts directly with YAML frontmatter, has no outer explanatory heading/prose, and no fenced code-block wrapper. Frontmatter is metadata, not a top-level section. Include YAML frontmatter before all sections: `title`, `feature`, `branch`, and `status`. Use the plan title, the spec feature slug, the confirmed branch name (from the discuss branch gate when auto-chained, or from se-plan's own Phase B confirmation in step 1 when se-plan owns the branch), and status: `pending`; if a value is genuinely unavailable, keep the field but leave it blank rather than inventing it.

Sections must appear in this exact order with no additional top-level sections: `## Execution Checklist`, `## Goal`, `## Architecture`, `## Data Flow`, `## Tasks`, `## Verification`, then one `## <Task name>` section per executable task. The first section after frontmatter is `## Execution Checklist`: one checkbox per executable task (task name only), plus the fixed literal `Final review / PR decision`. That final item is session bookkeeping for /se-exec step 10, not an executable task, and must not appear under `## Tasks`.

**Todo/checklist format (mandatory in generated plans):** `## Execution Checklist` and `## Tasks` list **brief task names only** — no Outcome, Skills, Dependencies, Verification, or implementation detail on checklist lines. Put all task detail in separate `## <Task name>` body sections immediately after `## Verification` (or after `## Tasks` if you prefer grouping, but every task section must exist). [plan-template.md](./plan-template.md) is the canonical shape. Checklist task names for executable tasks must exactly match the task names in `## Tasks` and in each `## <Task name>` heading.

Tasks are OVERVIEW-LEVEL in their detail sections: they describe what to accomplish and why, NOT how to write it. No copy-paste-ready code. No change-files manifest. No output mockups. Architecture may include signatures or pseudo-code ONLY where they clarify architecture. No placeholders in the completed plan: replace every template placeholder; never write "TBD", "TODO", "add error handling", "handle edge cases", or "similar to Task N".

## 9. Reuse the spec's feature slug + collision gate

**Consult config for placement.** Before writing, invoke `/se-get-config` and read `commitPlan` (`commitPlan` is independent of `commitSpec` — mixed states are allowed). Resolution: `true` → write under committed root `docs/specs/`; `false` → write under uncommitted root `.super-exec/specs/`; `"ask"` → prompt the user via `AskUserQuestion` which root they want, then use the chosen value. The effective value ALSO drives whether step 11 commits the approved plan (commit only when the plan lives under `docs/specs/`; a local `.super-exec/specs/` plan is intentionally uncommitted-by-design).

Write the plan to `<root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md` (where `<root>` is the chosen root above; monorepos insert the `<app>/` segment). The `<feature>` folder reuses the spec's slug EXACTLY (slug-only, no `NNNN` prefix). `<plan-name>` is named per `/se-slug-naming`. Use today's date for `<YYYY-MM-DD>`. The `<feature>` slug is NEVER the repo basename, the `package.json` `name`, or the app name. Apply the collision gate: if the candidate slug matches the repo basename or `package.json` `name`, **HALT** and use `AskUserQuestion` to confirm the real feature with the user. Immediately after the plan file (`plan-<plan-name>.md`) is written, update `.super-exec/active` with `phase: plan` and `active_plan: <root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md` (repo-relative). This write happens before plan approval so resume/session orientation has a concrete plan path as soon as the plan file exists.

## 10. Plan self-review

Before presenting the plan, scan it for: (a) **spec coverage** — point each spec requirement to a task; list any gaps; (b) **consistency** — names, signatures, and module boundaries used in later tasks match earlier ones; (c) **scope** — focused enough for one plan; (d) **status tracking** — every executable task has a matching unchecked item in `## Execution Checklist` and `## Tasks`, each with a matching `## <Task name>` detail section, and the final `Final review / PR decision` item is present exactly once outside `## Tasks`; (e) **checklist brevity** — no implementation detail on checklist lines. Fix all findings inline. A plan with gaps, inconsistencies, missing checklist items, verbose checklist lines, or open items must not advance to the gate.

## 11. Plan-review gate

Present the architecture + data flow + task bindings + verification design. The user reviews. If the user requests changes, edit the plan and re-run self-review before presenting again. Only after the user approves the plan, keep the existing `active_plan` and update `.super-exec/active` with `approved: <current UTC ISO-8601>` if approval metadata is present/used. The plan frontmatter status remains `pending` after approval; /se-exec changes it to `in_progress` only when execution starts, then `completed` at the PR/no-PR exit after the final checklist item is complete.

**If se-plan owns the branch** (step 1 branch ownership — the spec had no feature branch yet), now run [@../se-discuss/branch-gate.md](../se-discuss/branch-gate.md) **Phase C: create/switch** the confirmed branch off the current base, so the session ends on the feature branch ready for `/se-exec`. When auto-chained from /se-discuss, the branch already exists — skip creation.

**Commit (config-driven).** After the branch is ready — when the effective `commitPlan` placed the plan under `docs/specs/` — **commit the approved plan** (the `plan-<plan-name>.md` file) via **`/se-commit`**, passing that path. When the plan lives under `.super-exec/specs/` (local), do **not** commit it and say so — it is intentionally uncommitted-by-design (gitignored). Also skip the commit and say so when the user asked not to commit. Branch creation (when se-plan owns it) sets up the build session; the commit (when applicable) lands the approved plan on that branch.

Approval gates the fresh-session execution handoff: then instruct the user to start a **FRESH session** and run `/se-exec`. **Do NOT auto-start execution. Do NOT invoke `/se-exec`.**

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "I'll write copy-paste code in tasks" | Add code blocks, file diffs, or scaffolding to task descriptions | Tasks are overview-level only. Describe what to accomplish; remove the code. Architecture may have signatures only where they clarify boundaries — not scaffolding. |
| "I'll cram task detail into the checklist" | Put Outcome, Skills, Verification, or commands on `## Execution Checklist` or `## Tasks` lines | Checklist lines are brief task names only. Details belong in separate `## <Task name>` sections. See [plan-template.md](./plan-template.md). |
| "I'll hand-roll the API call / git op / scaffold" | Implement something directly without checking the skill catalog | Enumerate the full catalog first. If a skill covers it, bind it to the task explicitly. Never hand-roll what a skill provides. |
| "No tests here, so I'll scaffold some unit tests" | Add a `__tests__/` dir and stub files when no test suite exists in the touched area | Do NOT scaffold. Use browser-real verification, endpoint calls, or a custom script instead. Scaffolding untested tests is noise. |
| "I'll ask impeccable even though there's no UI" | Invoke impeccable when the feature has no frontend / component / style changes | Never use impeccable when there is no UI work. |
| "I'll ask the user whether to use impeccable on this UI work" | Prompt the user to opt in/out of impeccable for a UI feature | Never ask. On UI work, use impeccable automatically when installed; skip silently (with a note) when absent. There is no opt-in question. |
| "I'll run playwright without starting the app" | Record a browser/e2e command but omit the local dev-server setup | Bind the repo's local dev-server skill if present; otherwise record the repo's fallback dev-server command. Record start, readiness, command, and teardown/reuse evidence before any browser/e2e command. |
| "impeccable isn't installed, I can't proceed" | Block or pause the workflow because impeccable is absent | Skip the UI design pass, report that it was skipped and why, suggest installing impeccable, and continue. Never block on an optional external. |
| "I'll leave this risk open for execution to resolve" | Write "TBD", "decide during implementation", or leave an unanswered question in the plan | Resolve everything now. Grill via `AskUserQuestion`. Explore the codebase via `Task` subagent. The plan carries zero open items. |
| "I'll name the plan dir after the project / app" | Use the repo basename, `package.json` name, or app name as the `<feature>` slug | Reuse the spec's feature slug (slug-only, no number) as the plan directory folder; the `<feature>` slug matches the spec's exactly. Collision gate halts on a mismatch with the repo basename. |
| "No argument, so I'll just re-plan the last spec" | Re-plan an already-planned spec on a no-arg invocation | No-arg discovery lists ALL specs with NO plan folder (scanning both roots) and ASKS which to plan (ordering via `Depends on:`). Confirm before planning. Only re-plan an already-planned spec when the user explicitly asks. |
| "The spec has no branch — /se-exec can sort it out" | Write the plan and hand off, leaving /se-exec to hit a branch mismatch | If se-plan owns the branch (spec had none), create it after approval via branch-gate Phase C so the session ends on the feature branch. Do not push branch creation onto /se-exec. |
| "The plan is always local — no commit" | Skip `/se-commit` even when the plan was written under `docs/specs/`, or claim every plan is gitignored | When `commitPlan` placed the plan under `docs/specs/`, commit the approved `plan-<plan-name>.md` via `/se-commit` after approval — unless the user declined. Only plans under `.super-exec/specs/` stay local/uncommitted-by-design. |
| "This spec depends on an unbuilt feature, I'll proceed silently" | Ignore a `Depends on` whose dependency has no plan/build yet | Warn the user (non-blocking) and let them choose: plan anyway or switch to the dependency first. |
| "I'll start executing after the plan is done" | Invoke `/se-exec`, write implementation code, or continue beyond the gate | Stop at the plan-review gate. Instruct the user to start a fresh session and run `/se-exec`. |
| "I'll research the codebase by asking the user" | Ask the user about directory layout, existing patterns, naming, related code | Dispatch a `Task` subagent. Ask only what is not discoverable by reading the codebase. |
| "I'll define tasks before mapping file structure" | Jump into task decomposition without first deciding which files/units exist and what each owns | Map file structure first (step 3). Tasks flow from units with clear single responsibilities. |

---

## Architecture Design Discipline

- **Map files before tasks** (step 3): decide files/units + single responsibility before writing any task. Clear boundaries, well-defined interfaces, small focused files, files that change together live together, follow existing patterns (dispatch a `Task` subagent if unclear).
- **No placeholders** (step 8): every task, component, interface fully resolved. "TBD", "TODO", "add error handling", "handle edge cases", "similar to Task N" forbidden. Unresolvable = open question → `AskUserQuestion`.
- **No code in tasks** (step 8): detail sections say what + why + which repo skills + how to verify — no code blocks, file diffs, import lists, scaffolding. Architecture may hold signatures/pseudo-code only where they illuminate boundaries.
- **Brief checklists, detailed body** (step 8): `## Execution Checklist` and `## Tasks` carry task names only; each task's Outcome, Skills, Dependencies, Verification live under a dedicated `## <Task name>` section. Mirror [plan-template.md](./plan-template.md).

---

## Risk-Grilling Discipline

- **One question at a time.** After each answer, pick the next most important unresolved risk/decision. Never batch. Always `AskUserQuestion`.
- **Provide a recommended answer.** State what you believe the answer is and why, then ask to confirm or correct — surfaces hidden assumptions early.
- **Walk the full decision tree.** Enumerate the branches, e.g. "Should X be sync or async? I recommend async because `payments/retry.ts` already uses SQS — confirm, or deliberate departure?"
- **Research before asking.** If the codebase answers it, dispatch a `Task` subagent and bring the finding rather than asking blindly.
- **Resolve everything.** The plan carries zero open items into execution; get user decisions via `AskUserQuestion` now and record them.

---

## Verification Design Rules

1. **Baseline is detected, not assumed.** Run a `Task` subagent to identify the actual test/lint/build commands before recording them.
2. **Tests exist → TDD.** If the touched area already has coverage, write tests first for new behavior — not retrofit.
3. **No tests exist → do not scaffold.** Use real verification: playwright against a dev-server skill, direct endpoint calls, or a purposeful custom script. Document the exact command.
4. **Playwright/e2e needs a local server first.** Scan local repo skills for `local-dev-server`, `dev-server`, or equivalent; bind the skill when present. If absent, detect a repo script/docs fallback and record it. If neither exists, resolve the startup path with the user before choosing browser/e2e. Record how the runner starts or reuses the server, waits for readiness, runs the browser/e2e command, and tears down any server it started.
5. **UI changes require a browser check with evidence.** A screenshot or DOM assertion from a real browser run. "It compiles" is not sufficient for UI work.
6. **Runner/judge split is mandatory.** The runner subagent (cheap / haiku tier) executes and returns structured EVIDENCE. The judge subagent (strong non-fast / opus tier) evaluates correctness against spec + plan. No inline verification in the controller. No "done" without shown evidence. See `/se-subagent` for tier guidance.

---

## Model and Tool Assignments

| Role | Model tier |
|---|---|
| Architecture design, risk-grilling, plan judgment (this skill) | Strong non-fast (opus) — see `/se-subagent` |
| Codebase finder subagents, skill catalog enumeration | Cheap investigator (haiku) — see `/se-subagent` |
| Verification runner subagent | Cheap script-runner (haiku) — see `/se-subagent` |
| Verification judge subagent | Strong non-fast (opus) — see `/se-subagent` |

Dispatch subagents with the `Task` tool. Use `Read` / `Edit` / `Write` for file operations. Use `AskUserQuestion` for all interactive questions to the user. Use `TodoWrite` to track checklist progress.
