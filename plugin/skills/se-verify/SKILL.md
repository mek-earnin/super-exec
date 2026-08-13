---
name: se-verify
description: Use when se-exec needs evidence for a supporting checkpoint, working increment, or final whole-plan proof.
---

# se-verify

se-verify is runner → judge evidence contract. Runner reports facts; independent strong judge renders PASS, FAIL, or LIMITATION. Evidence scope is explicit: `supporting-checkpoint`, `working-increment`, `final`, or `standalone-triage`.

## Required context

Receive review identity, scope, requirements, verification design, normal path/transitions, and changed paths. Capture before runner; changed content makes evidence stale and reruns scope. `/se-commit` owns staging/reviewed-snapshot and delivery-tree equivalence. `standalone-triage` receives PR/CI acceptance inputs and changed paths, not increment artifacts. Missing increment/final scope or normal path is FAIL.

## Runner contract

Dispatch cheap runner. Return identity, commands, exit codes/counts, relevant excerpts, artifacts, normal-path provenance, and transitions.

- **supporting-checkpoint** — run cheapest relevant focused checks. Do not run full baseline or represent bridge/unit/mock/scripted PASS as product success.
- **working-increment** — run full detected baseline, then prove selected behavior through named normal distributable/deployed/user path and each relevant selected transition. A scripted state, mocked response, unit suite, or lower-layer bridge is supporting evidence only.
- **final** — rerun full detected baseline plus whole-spec normal-path proof after all review fixes; cover required cross-increment transitions.
- **standalone-triage** — run PR/CI-failure-relevant baseline and focused checks supplied by triage; preserve Critical/Important blocking behavior without requiring plan increment state.

For browser/E2E, runner starts/confirms normal local server via repo skill or recorded fallback, waits for readiness, and records server + browser evidence. For deployed/distributable paths, record artifact/version, launch path, and observed user-visible outcome.

## Judge contract

Dispatch independent strong judge with evidence, scope, requirements, normal path, and acceptance criteria:

1. Did required checks for this scope pass?
2. For working-increment/final scope, does evidence prove normal user flow rather than a substitute?
3. Did relevant selected transitions pass?
4. Does evidence bind review identity?

Render exact `PASS`, `FAIL`, or `LIMITATION`.

- `PASS` supporting checkpoint → focused evidence only; cannot close working increment.
- `PASS` working increment → permits boundary review.
- `PASS` final → permits final review/completion.
- `FAIL` → specific fix targets; re-run same scope after fix.
- `LIMITATION` → persist/report `blocked-limitation` to caller; do not loop fixer or treat it as PASS. Active se-exec skips review/commit/PR/completion until explicit human governing-spec approval/amendment; re-plan when architecture changes. Auto-PR never overrides this. Standalone triage escalates.

Runtime/E2E failure at working-increment/final scope is prioritized over architecture/deep review. Report `runtime-proof-failed` so se-exec short-circuits review until core flow works.

## Non-negotiables

- Runner and judge never collapse into one agent.
- No completion claim without shown evidence and explicit judge PASS.
- Baseline is required at working-increment and final boundaries; it is not required at supporting checkpoints.
- Lower-layer, scripted, mocked, and static PASS cannot count as normal user-flow PASS.

## Model and tool assignments

Runner = cheap/script-runner tier. Judge = strong non-fast tier. Fixer = mid tier. Dispatch via `Task`; controller never runs verification inline.
