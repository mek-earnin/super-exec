---
name: se-plan
description: Use when a spec is agreed and it's time to decide HOW — architecture, file structure, verification, and repo-skill reuse — before code — "plan this", "design the implementation", "how should we build it"; also to re-plan an existing spec without re-discussing.
---

# se-plan — Plan Phase

Design approved architecture, task bindings, traceability, and proof; write `plan-<plan-name>.md`. `/se-discuss` auto-chains first approved spec; manual re-entry may re-plan or choose next unplanned split spec. Tasks are evidence, never immutable increments—`/se-exec` re-slices without dropping requirements/contracts.

## Operational checklist

Use harness todo-list tool to load and track this checklist. Sync status as work changes; before approval, delivery, or completion claim, verify every applicable item complete.

- [ ] Activate and discover selected spec
- [ ] Resolve dependencies and branch ownership
- [ ] Research risks and reuse
- [ ] Define architecture and proof
- [ ] Write plan and ledger
- [ ] Move ledger pending to ready without losing history
- [ ] Review, approve, and publish paired artifacts
- [ ] Hand off to fresh execution session

## Activate and locate

First write `.super-exec/active` (`phase: plan`, `started: <current UTC ISO-8601>`), then `/se-local-ignore`. Argument selects spec but confirm match. Auto-chain trusts passed spec. No argument: scan `docs/specs/` and `.super-exec/specs/` (one app in monorepo), list specs without `plans/` in either root with `Depends on:` context, ask user. Local artifacts are per-machine: confirm.

Read selected spec fully; missing spec → `/se-discuss`. For `Depends on: <slug>` (missing/`none` means none), locate sibling in both roots; if unplanned/unbuilt, warn and ask whether to continue. Branch: auto-chain reuses discuss branch; re-plan reuses recorded frontmatter branch; otherwise run [@../se-discuss/branch-gate.md](../se-discuss/branch-gate.md) Phase B now and Phase C after approval. Never assume current branch fits. Before branching a committed split spec, verify selected spec exists on base; otherwise stop: wait for carrying PR merge or branch from predecessor.

## Design

Cheap finders inspect code patterns, models/boundaries, source/tests, and every repo skill. Bind a covering skill explicitly; never hand-roll its work. Map files/units/dependencies as **Design Evidence**, not acceptance or task order.

Ask one `AskUserQuestion` at a time only for an unresolved decision changing approved behavior, real invariant, dependency, or normal proof. Research first; recommendations stay defaults until approved. Record only spec-backed/approved structural invariants in **Approved Architecture Contract**. Optional HOW/file maps/defaults stay Design Evidence.

Classify UI. No UI → no impeccable. UI + installed impeccable → dispatch `shape`, record design intent/states/tasks, no code. Absent → report skip, suggest install, continue; never ask/block.

Detect baseline commands. Record exact focused checks; map every required outcome/transition to real distributable/deployed/user proof; label mock/script/bridge/lower-layer evidence supporting. Existing touched coverage → TDD; absent coverage → real browser/endpoint/custom proof, never test scaffolding. Browser/E2E requires bound dev-server skill or discovered fallback command, readiness signal, test command, teardown/reuse; no startup path → resolve before choosing E2E. UI requires browser screenshot or DOM evidence. `/se-verify` owns runner→judge: cheap runner facts, strong judge verdict, no inline verification.

## Write and activate plan

Use [plan-template.md](./plan-template.md) exactly: frontmatter `title`, `feature`, `branch`, `status: pending`; exact section order; task/checklist names brief and identical; body `## <Task name>` carries outcome, skills, dependencies, checks. Include `Final review / PR decision` only in checklist: bookkeeping, never executable work. No code, manifests/mockups, placeholders (`TBD`, `TODO`, `add error handling`, `handle edge cases`, `similar to Task N`). Work packages can span increments; check only complete named outcome.

Read `commitPlan` from `/se-get-config`, based on physical governing-spec root: `"inheritSpec"` → same root; `false` → `.super-exec/specs/`; `"ask"` → local spec stays local, committed spec asks local vs committed. Never commit a plan over local spec. Write `<root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md`; feature slug exactly matches spec, plan name follows `/se-slug-naming`, date is today. Repo basename/`package.json` name collision → halt and ask.

Atomically record `active_plan`, sibling `ledger_path`, `ledger_status: pending`, `phase: plan`. Create missing `deferred-findings-<plan-name>.md` (empty allowed), one-time seed only non-required Discuss/spec concerns with provenance. Existing ledger is durable history: validate/preserve, update only changed scope. Fields: fingerprint; normalized scenario/invariant; affected behavior/path; source/evidence; likelihood/impact/effort/confidence/fix complexity; disposition/status; promotion trigger. Never put rows in traceability. Valid ledger → `ledger_status: ready`; failure stays pending—do not approve/publish/execute.

## Review and handoff

Self-review traceability (provenance/priority, outcome, transition, normal proof, completion status), ready ledger/history, contracts/dependencies/proof consistency, scope boundaries, and outcome-authoritative status. Final checklist/status cannot complete while required outcome/work package incomplete. Fix inline.

Present plan + ledger as one unit. Changes re-run self-review. Approval may add `approved: <current UTC ISO-8601>`; frontmatter remains `pending`. If this skill owns branch, run branch-gate Phase C. Committed-root plan: ready plan + ledger commit together through `/se-commit`; local root: commit neither; obey user no-commit request. Stop: instruct fresh session `/se-exec`; never auto-start it.

Use strong non-fast controller/judge, cheap finders/runners, and `Task` dispatch; see `/se-subagent`.
