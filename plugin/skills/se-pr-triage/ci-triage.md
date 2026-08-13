# ci-triage — Track B Reference Procedure

Track B is autonomous: no gate, no PR reply. Green check or report escalation only.

## Executor checklist

Use harness todo-list tool to load and track this checklist. Sync status as work changes; before delivery or completion claim, verify every applicable item complete.

- [ ] Diagnose each failing signal
- [ ] Resolve or escalate by signal type
- [ ] Verify, review, commit, push, and recheck applicable fixes
- [ ] Report green or escalated result without PR replies

## Diagnose

Use state-reader snapshot: `get_check_runs` first; `get_status` only for missing signals. Work failures, `timed_out`, `action_required`; skip passing, cancelled, informational. For each job, read matching `get_comments` status/bot reason first; only if insufficient use `gh run view --log-failed`. Stop after first adequate source.

## Resolve

- Test job: run locally. Pass → `gh run rerun --failed` once; pass = `flaky-rerun`, still red = escalate. Local fail → mid implementer → `/se-verify standalone-triage` → `/se-review standalone-triage` → `/se-commit` → push; CI green = `fixed`, otherwise escalate. Cannot run locally (device farm/container/secrets) → escalate; never blind fix/rerun.
- Lint/type/deterministic source failure: same implementer → standalone-triage verify/review → commit → push flow.
- PR title: GitHub MCP `update_pull_request`; no commit.
- SonarCloud: fix each source finding through same flow; human-only false-positive suppression escalates, others continue.
- Cycode: clear safe patch/SAST/code-quality fix may use same flow. Secret/credential, unclear SAST, or transitive breaking dependency → escalate; never rotate a credential, direct human to `#help-security`.

Executor is subagent; code changes dispatch mid implementer. Never reply, rerun same job twice, or bypass `/se-verify`, `/se-review`, `/se-commit`.

Escalation includes check/context name, `escalated`, why, check link, and relevant status-comment link. Controller emits it verbatim under `Escalations and aborts`.
