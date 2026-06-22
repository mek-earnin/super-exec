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
<Plan goal in 1-3 sentences. Spec: `docs/specs/NNNN-<feature>.md`>

## Architecture
<Components and responsibilities.>

<Architecture diagram: mermaid or ASCII.>

<Folder/file structure: ASCII tree.>

<Boundary signatures or pseudo-code.>

## Data Flow
<Happy-path data flow: mermaid or ASCII.>

<Main error-path data flow: mermaid or ASCII.>

## Tasks
### <Task 1 name>
- Outcome: <What this task accomplishes and why>
- Skills: <Repo skills to invoke, or `none`>
- Dependencies: <Dependency notes, or `none`>
- Verification: <Task-specific check and expected evidence>

### <Task 2 name>
- Outcome: <What this task accomplishes and why>
- Skills: <Repo skills to invoke, or `none`>
- Dependencies: <Dependency notes, or `none`>
- Verification: <Task-specific check and expected evidence>

## Verification
<Baseline commands.>

<Task-specific checks.>

<Runner evidence format.>

<Judge criteria.>

### Browser/E2E Preflight
- applicability: <required | not applicable>
- dev-server-skill: <repo skill name/path, or `none`>
- start-command: <skill invocation or fallback command>
- readiness-signal: <URL/port/log line and timeout>
- test-command: <playwright/e2e/browser command>
- teardown-rule: <reuse existing server, or stop PID started by runner>
