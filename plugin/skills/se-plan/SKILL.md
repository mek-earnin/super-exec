---
name: se-plan
description: Use this when a spec is agreed and it's time to decide HOW — architecture, file structure, verification, and which existing repo skills to reuse — before writing any code. Triggers on "plan this", "design the implementation", "how should we build it", or moving from a spec toward code. Produces a reviewed plan.md. The second step of the super-exec workflow; invoke after se-shape, or to re-plan an existing spec without re-shaping.
---

# se-plan — Plan Phase

se-plan drives the **Plan (architecture + verification)** phase of the super-exec gate-driven workflow. It reads the committed spec, designs the architecture through codebase research and user risk-grilling, binds repo skills to tasks, designs verification, and writes a `plan.md`. It runs **after se-shape** (a committed spec is required). `/se-plan` is also a re-entry point: invoke it to re-plan an existing spec without re-shaping.

> **Reference paths:** every `references/*.md` cited below lives at the plugin root — read it as `${CLAUDE_PLUGIN_ROOT}/references/<file>` on Claude Code, or `${CURSOR_PLUGIN_ROOT}/references/<file>` on Cursor.

Use a **strong non-fast model** (see `references/model-tiers.md`, "Plan" row) for architecture design, risk-grilling, and verification judgment. Dispatch **finder subagents** (cheap / investigator tier) for all codebase research and catalog enumeration. For harness-specific tool names, resolve against `references/tool-map.md`.

---

## Session activation (do this FIRST, before the checklist)

Invoking this skill — typed `/se-plan` or model auto-invoked to plan/re-plan a committed spec —
**means a super-exec design session is active**. As the very first action, **write the session
marker** `.super-exec/active` in the repo root (create `.super-exec/` if needed), e.g. `phase: plan`
and `started: <current UTC ISO-8601>`. Existence + mtime are what the hooks read; the stale-marker
decision is a model-judged heuristic with no fixed TTL. **Do not commit it** — `.super-exec/` is
gitignored. Behavior is identical for manual and auto invocation. If invoked with a feature slug or
ticket argument, use it to locate the spec — still confirm the match.

---

## Mandatory Ordered Checklist

Work through every item in order. Do NOT skip any item, even for simple work.

- [ ] **1. Read the spec** — Locate the spec at `docs/specs/<feature>.md` (or `docs/specs/<app>/<feature>.md` in monorepos). Read it in full. Identify all acceptance criteria. Do NOT proceed if no committed spec is found — tell the user to run `/se-shape` first.
- [ ] **2. Research the architecture via subagents** — Dispatch finder subagents to explore the codebase: existing patterns for the touched area, data models, service/module boundaries, naming conventions, relevant source files, and any existing tests covering the area. Do NOT guess at structure. Do NOT ask the user what a subagent can discover.
- [ ] **3. Map file structure first** — Before defining tasks, decide which files/units will be created or modified and the single responsibility of each. Apply these rules: units have clear boundaries and well-defined interfaces; files are small and focused; files that change together live together; follow existing patterns in the codebase. This file map drives task decomposition.
- [ ] **4. Enumerate the full repo skill catalog** — Dispatch a finder subagent to read every `.claude/skills/*/SKILL.md` (collect: name, description, argument-hint). **Semantically bind matching skills to tasks.** Record each binding explicitly in the plan — e.g., a task "query a new endpoint" → "**MUST invoke `create-api-service` before creating files**". Repo skills are a first-class reuse target for any task they cover; never hand-roll what a skill provides.
- [ ] **5. UI classification → impeccable opt-in** — Classify whether the feature involves UI work (a frontend app, or the change touches components/styles).
  - **No UI work** → never ask about impeccable. Skip to the next step.
  - **UI work present** → ask the user ONCE: "This involves UI changes. Should I incorporate impeccable for design direction and state coverage? (default: yes)". **Default is YES**. Persist the answer in the plan.
  - **When opted in:** detect whether impeccable is installed (glob `.claude/skills/impeccable*/SKILL.md` or equivalent). **If absent:** skip the UI design pass, report that it was skipped and why, suggest installing impeccable, and continue — never block. **If present:** dispatch impeccable `shape` via a subagent to establish design direction and identify states the design system does not cover (empty / loading / error / edge). Capture output as design INTENT + planned tasks — NO code (the no-code task rule applies here too).
- [ ] **6. Resolve every risk and open question with the user** — Interview the user one question at a time, walking each branch of the decision tree. For each question, provide your recommended answer. If a question is answerable by exploring the codebase, explore it via a subagent instead of asking. **The plan carries zero open items into execution.** Do not defer anything to "figure it out during execution."
- [ ] **7. Design verification** — Record the full verification strategy in the plan:
  - **Baseline (always runs):** detect per repo from `package.json` scripts, `AGENTS.md`, or a repo skill. Examples: frontend → `lint:fix` + `type-check`; .NET service → `dotnet build` passes. Record the exact commands.
  - **Task-specific (adaptive):** if a test suite already covers the touched area → write tests first (TDD) for new code. If NO tests exist there → do NOT scaffold unit tests; use browser-real verification (playwright via the repo dev-server skill), endpoint calls, or a custom script instead. UI changes require a real-browser check with evidence.
  - **Runner → judge split:** a cheap runner subagent executes baseline + task-specific verification in its own throwaway context and returns structured EVIDENCE (exit codes, counts, relevant log excerpts). A strong non-fast judge evaluates that evidence against spec + plan. No verification runs inline in the controller. "Done" requires shown evidence. Resolve concrete model names from `references/model-tiers.md`.
- [ ] **8. Write the plan using the exact template** — Tasks are OVERVIEW-LEVEL: they describe what to accomplish and why, NOT how to write it. No copy-paste-ready code. No change-files manifest. No output mockups. Architecture may include signatures or pseudo-code ONLY where they clarify architecture. No placeholders — never write "TBD", "TODO", "add error handling", "handle edge cases", or "similar to Task N".
- [ ] **9. Reuse the spec's feature slug + collision gate** — Write the plan to `.super-exec/<feature>/<YYYY-MM-DD>-<plan-name>/plan.md`. The `<feature>` directory MUST reuse the same slug as the spec (the ≤6-word lowercase-kebab feature summary). It is NEVER the repo basename, the `package.json` `name`, or the app name. Apply the collision gate: if the candidate slug matches the repo basename or `package.json` `name`, **HALT** and confirm the real feature with the user. Use today's date for `<YYYY-MM-DD>`.
- [ ] **10. Plan self-review** — Before presenting the plan, scan it for: (a) **spec coverage** — point each spec requirement to a task; list any gaps; (b) **consistency** — names, signatures, and module boundaries used in later tasks match earlier ones; (c) **scope** — focused enough for one plan. Fix all findings inline. A plan with gaps, inconsistencies, or open items must not advance to the gate.
- [ ] **11. Plan-review gate** — Present the architecture + data flow + task bindings + verification design. The user reviews. End by instructing the user to start a **FRESH session** and run `/se-exec`. **Do NOT auto-start execution. Do NOT invoke se-exec.**

---

## Plan Template

Write the plan file using exactly this structure. Sections must appear in this order. No additional top-level sections.

```markdown
# <Plan name>

## Goal
<1-3 sentences. Link to the spec: `docs/specs/<feature>.md`>

## Architecture
<Components, responsibilities, data flow — prose + mermaid or ASCII diagrams.
Folder/file structure as ASCII tree. Signatures or pseudo-code only where they
clarify architecture — never as implementation scaffolding.>

## Data Flow
<Diagram (mermaid or ASCII) showing how data moves through the system for the
primary happy path and the main error path.>

## Tasks
<Overview-level tasks. Each task states: what to accomplish, which repo skills
to invoke (MUST invoke `<skill-name>` before ...), dependency notes, and its
own verification step. No copy-paste code. No file manifests.>

## Verification
<Baseline commands (exact). Task-specific checks. Runner/judge split.
Evidence format expected from the runner.>
```

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "I'll write copy-paste code in tasks" | Add code blocks, file diffs, or implementation scaffolding to task descriptions | Tasks are overview-level only. Describe what to accomplish. Remove the code. Architecture may have signatures only where they clarify boundaries — not as scaffolding. |
| "I'll hand-roll the API call / git op / scaffold" | Implement something directly without checking the skill catalog | Enumerate the full catalog first. If a skill covers it, bind it to the task explicitly. Never hand-roll what a skill provides. |
| "No tests here, so I'll scaffold some unit tests" | Add a `__tests__/` dir and stub files when no test suite exists in the touched area | Do NOT scaffold. Use browser-real verification, endpoint calls, or a custom script instead. Scaffolding untested tests is noise. |
| "I'll ask impeccable even though there's no UI" | Invoke or ask about impeccable when the feature has no frontend / component / style changes | Never mention impeccable when there is no UI work. |
| "impeccable isn't installed, I can't proceed" | Block or pause the workflow because impeccable is absent | Skip the UI design pass, report that it was skipped and why, suggest installing impeccable, and continue. Never block on an optional external. |
| "I'll leave this risk open for execution to resolve" | Write "TBD", "decide during implementation", or leave an unanswered question in the plan | Resolve everything now. Grill the user. Explore the codebase. The plan carries zero open items. |
| "I'll name the plan dir after the project / app" | Use the repo basename, `package.json` name, or app name as the `<feature>` slug | Reuse the exact slug from the spec. Collision gate halts on a mismatch with the repo basename. |
| "I'll start executing after the plan is done" | Invoke se-exec, write implementation code, or continue beyond the gate | Stop at the plan-review gate. Instruct the user to start a fresh session and run `/se-exec`. |
| "I'll research the codebase by asking the user" | Ask the user about directory layout, existing patterns, naming, related code | Dispatch a finder subagent. Ask only what is not discoverable by reading the codebase. |
| "I'll define tasks before mapping file structure" | Jump into task decomposition without first deciding which files/units exist and what each owns | Map file structure first (step 3). Tasks flow from units with clear single responsibilities. |

---

## Architecture Design Discipline

**Map files before tasks.** Decide which files and units will be created or modified and the single responsibility of each before writing a single task. Units with clear boundaries and well-defined interfaces. Smaller, focused files. Files that change together live together. Follow existing patterns — dispatch a finder subagent if patterns are not obvious.

**No placeholders.** Every task, every component, every interface in the plan must be fully resolved. "TBD", "TODO", "add error handling", "handle edge cases", and "similar to Task N" are all forbidden. If something cannot be resolved, it is an open question — grill the user and resolve it before writing.

**No code in tasks.** Task descriptions explain what to accomplish and why, which repo skills to invoke, and how to verify. They do not contain code blocks, file diffs, import lists, or implementation scaffolding. Architecture sections may contain signatures and pseudo-code only where they illuminate component boundaries.

---

## Risk-Grilling Discipline

**One question at a time.** After every answer, decide the next most important unresolved risk or decision. Never batch questions.

**Provide a recommended answer.** For every question, state what you believe the answer is and why, then ask the user to confirm or correct. This surfaces hidden assumptions early.

**Walk the full decision tree.** For each architectural decision, enumerate the branches: "Should X be synchronous or asynchronous? I recommend async because `payments/retry.ts` already uses SQS — confirm, or is this a deliberate departure?"

**Research before asking.** If the answer can be found by reading the codebase, dispatch a finder subagent and bring the finding to the user rather than asking blindly.

**Resolve everything.** The plan carries zero open items into execution. If a risk cannot be resolved without a user decision, ask now and record the decision.

---

## Verification Design Rules

1. **Baseline is detected, not assumed.** Run a finder subagent to identify the actual test/lint/build commands for the repo before recording them in the plan.
2. **Tests exist → TDD.** If the touched area already has test coverage, the plan must include writing tests first for new behavior — not retrofitting them after.
3. **No tests exist → do not scaffold.** Use real verification: playwright against a dev-server skill, direct endpoint calls, or a purposeful custom script. Document exactly what command will be run.
4. **UI changes require a browser check with evidence.** A screenshot or DOM assertion from a real browser run. "It compiles" is not sufficient evidence for UI work.
5. **Runner/judge split is mandatory.** The runner subagent (cheap tier) executes and returns structured EVIDENCE. The judge subagent (strong non-fast tier) evaluates correctness against spec + plan. No inline verification in the controller. No "done" claim without shown evidence.

---

## Model and Tool Assignments

| Role | Claude Code | Cursor |
|---|---|---|
| Architecture design, risk-grilling, plan judgment (this skill) | Strong non-fast (Opus) — see `references/model-tiers.md` | Default / inherit (non-fast) |
| Codebase finder subagents, skill catalog enumeration | Cheap investigator (Haiku) — see `references/model-tiers.md` | Composer non-fast |
| Verification runner subagent | Cheap script-runner (Haiku) — see `references/model-tiers.md` | Composer non-fast |
| Verification judge subagent | Strong non-fast (Opus) — see `references/model-tiers.md` | Default / inherit (non-fast) |

Resolve concrete model names from `references/model-tiers.md`. Resolve tool names (Read, Edit, Write, subagent dispatch) from `references/tool-map.md`.
