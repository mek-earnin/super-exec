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

## Goal
<Plan goal in 1-3 sentences. Spec: `<root>/[<app>/]<feature>/spec-<feature>.md`>

## Approved Architecture Contract
<Only spec-backed or explicitly approved boundaries, invariants, and behavior-preserving decisions.>

<Architecture diagram: mermaid or ASCII.>

## Design Evidence
<File map, folder/file structure ASCII tree, optional HOW/defaults, and research evidence. These guide design; they do not dictate execution order or create acceptance criteria.>

Deferred ledger: `<plan-folder>/deferred-findings-<plan-name>.md` (reference only; no deferred rows in this plan).

## Data Flow
<Happy-path data flow: mermaid or ASCII.>

<Main error-path data flow: mermaid or ASCII.>

## Requirement Traceability
| Required outcome | Provenance / priority | Normal proof mapping | Final status |
|---|---|---|---|
| <requirement/outcome> | <core requested | approved derived> | <normal path + transitions> | pending |

## Tasks
- [ ] <Task 1 name>
- [ ] <Task 2 name>

## Runtime Verification
- Available normal proof paths: <requirement/outcome + real deployment/user path mappings>
- Available transitions: <requirement/outcome + clean launch, reconnect, retry, Forget → Connect, permission change, crash/restart as relevant>
- Supporting evidence only: <unit, bridge, scripted, mocked, or lower-layer checks>

## Verification
<Detected baseline commands run at working-increment and final boundaries.>

<Focused checkpoint checks.>

<Runner evidence format.>

<Judge criteria.>

### Browser/E2E Preflight
- applicability: <required | not applicable>
- dev-server-skill: <repo skill name/path, or `none`>
- start-command: <skill invocation or fallback command>
- readiness-signal: <URL/port/log line and timeout>
- test-command: <playwright/e2e/browser command>
- teardown-rule: <reuse existing server, or stop PID started by runner>

## <Task 1 name>
- Outcome: <What this work package enables and why>
- Skills: <Repo skills to invoke, or `none`>
- Dependencies: <Dependency notes, or `none`>
- Required outcomes: <traceability IDs; parent can span working increments>
- Focused verification: <Cheapest relevant checkpoint evidence>

## <Task 2 name>
- Outcome: <What this work package enables and why>
- Skills: <Repo skills to invoke, or `none`>
- Dependencies: <Dependency notes, or `none`>
- Required outcomes: <traceability IDs; parent can span working increments>
- Focused verification: <Cheapest relevant checkpoint evidence>
