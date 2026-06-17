# ci-triage — Track B Reference Procedure

This document describes the full Track B procedure referenced by [`SKILL.md`](./SKILL.md). The SKILL.md controller delegates Track B execution to a subagent with the instruction "follow the procedure in `ci-triage.md`". This document is that procedure.

Track B is fully autonomous. It operates with no approval gate, posts no replies to the PR, and surfaces escalations only in the end-of-round report — never in a thread comment. Its output is a green check (or a documented escalation), not a conversation.

---

## 1. Reading CI state

The Track B executor receives the CI snapshot gathered by the state reader subagent in SKILL.md step 2. That snapshot already contains the results of two GitHub MCP `pull_request_read` calls:

- `get_check_runs` — the Checks API: the primary source of job-level conclusions (`success`, `failure`, `cancelled`, `timed_out`, `action_required`, `neutral`, `skipped`). This is the authoritative list of which jobs ran and what they concluded.
- `get_status` — the legacy combined commit status (used by tools that post to the older Statuses API rather than the Checks API). Treated as a supplementary signal when `get_check_runs` does not cover all signals from a particular tool.

Work from `get_check_runs` first. Consult `get_status` only for signals that do not appear in the check runs list.

Passing checks, cancelled jobs, and purely informational signals — changeset present, preview URL, green checks of any kind — are skipped entirely. The working set for Track B is the subset of check runs (and status contexts) whose conclusion is `failure`, `timed_out`, or `action_required`.

---

## 2. Mapping each failure to its human-readable reason

Before attempting any fix, determine why the job failed. Use this read order:

1. **Status comment (primary).** Call `get_comments` (top-level PR comments) and scan for a bot comment that mirrors the failing job — for example, a Playwright report comment, a PR-title validation summary, or a Cycode findings comment. These comments are written specifically to surface the human-readable reason for the failure. Use the information in the status comment as the basis for diagnosis.

2. **Raw failure log (fallback).** If the status comment is absent, too terse, or refers to a line that no longer exists, call `gh run view --log-failed` for the relevant workflow run to retrieve the raw log for failed steps only. This is the only `gh` command used for diagnosis; use it only when the comment is insufficient. Do not read raw logs when a comment already explains the failure clearly.

Never read both in the same round for the same job — pick the first source that yields enough detail and stop.

---

## 3. Per-job resolution

After mapping the failure to its reason, apply the resolution that matches the job type. Each resolution path is described below.

### Test jobs (Playwright, unit, integration)

Run the failing test(s) locally to determine the nature of the failure. Then follow the branch that matches the result:

**Local run passes:**
The failure is treated as flaky. Rerun the CI job exactly once using `gh run rerun --failed`. Then wait for the rerun to complete and check its conclusion.

- If the rerun passes: the failure was transient. Record verdict `flaky-rerun` in the round report with a link to the rerun.
- If the rerun still fails while local continues to pass: the job is stuck or the flakiness is persistent but not locally reproducible. Escalate — record the job as needing human attention in the round report with a note that local passes but CI remains red after one rerun.

**Local run fails:**
The failure is real. Fix the code by dispatching an implementer subagent (mid tier) with the diagnosis as context, then clear the inner verification loop via `se-verify` and the outer review loop via `se-review`, exactly as a build task in `se-exec`. Once both loops are green, commit via `se-commit`, then push the commit to the PR branch via `git push` (the Track B executor subagent performs the push after `se-commit` completes). The push triggers CI to rerun.

- If CI goes green after the push: record verdict `fixed` with links to the pushed commit and the check run.
- If CI remains red after the fix-and-push attempt: record verdict `escalated` — the failure cannot be made green and needs human attention.

**Cannot run locally (environment unavailable — e.g., device farm, container-only, secrets required):**
Escalate immediately. Do not attempt a blind fix or a speculative rerun. Record the job as needing human attention and note why local execution was unavailable.

### Lint, type-check, and unit failures (non-test jobs)

These failures have a deterministic source in the checked-in code. Fix the flagged issues directly — dispatch an implementer subagent with the failure output as context, verify via `se-verify` and `se-review`, commit via `se-commit`, and push.

### PR-title validation failure

The PR title does not match the required format (typically a conventional-commit prefix check). Correct the PR title via the GitHub MCP — `update_pull_request` with the corrected title. No commit is needed; correcting the title is sufficient to clear the check on the next push or re-evaluation.

### SonarCloud quality gate failure

The SonarCloud gate has flagged new issues (code smells, bugs, vulnerabilities, or coverage drops) introduced by this PR. Read the findings from the SonarCloud status comment (`get_comments`). Fix each flagged issue at the source via the same implementer → `se-verify` → `se-review` → `se-commit` → push flow.

If a finding is a false positive that cannot be suppressed without human input (for example, a suppression that requires a SonarCloud project admin action), escalate that specific finding and continue fixing the others.

### Cycode findings (secrets / SAST / vulnerable dependencies)

Cycode is a security scanner. Treat its findings with extra caution.

**Fix when the remedy is clear:** a vulnerable dependency with a known patched version, a code quality finding with an obvious safe fix, or a SAST finding that can be resolved by a code change that does not require special access. Apply the fix via implementer → `se-verify` → `se-review` → `se-commit` → push.

**Escalate when ambiguous or when resolution requires a human action.** Specifically: any finding that involves a detected secret or credential (the credential must be rotated, which is a human action — an agent must never attempt to rotate credentials autonomously); any SAST finding where the safe remediation is unclear; any dependency finding where the only path forward is to accept a breaking change in a transitive dependency. Record each such finding in the round report with enough detail for a human to act, and direct the human to `#help-security` on Slack as the appropriate channel.

---

## 4. Things Track B never does

- **Never posts a reply to the PR.** No in-thread comment, no top-level PR comment, no status comment. The resolution of a Track B failure is a green check, not a thread reply. If escalation is necessary, it appears in the end-of-round report produced by the SKILL.md controller — not as a PR comment.
- **Never skips the subagent dispatch model.** The Track B executor itself is a subagent. When it needs to fix code, it dispatches a further implementer subagent (mid tier), not inline edits. `se-verify`, `se-review`, and `se-commit` are invoked as documented in their own skills.
- **Never reruns a job more than once for the same failure.** One rerun per flaky job per round. A second rerun that is still red is an escalation, not another rerun.
- **Never fixes a Cycode credential finding.** Escalate with detail and direct the human to `#help-security`.

---

## 5. Escalation format

An escalation is a record in the end-of-round report. Each escalation entry contains:

- The name of the failing check run or status context.
- The verdict: `escalated`.
- A one-to-two sentence summary of why autonomous resolution was not possible (e.g., "local run passes but CI remains red after one rerun", "Cycode found a secret — credential rotation required", "environment unavailable for local test execution").
- A link to the check run.
- Where relevant, a link to the status comment that described the failure.

Escalations are surfaced by the SKILL.md controller in the end-of-round report under "Escalations and aborts — items needing human attention." Track B supplies the above information; the controller includes it verbatim.

---

## 6. Access split summary

| Operation | Tool |
|---|---|
| Read CI check runs (which jobs failed) | GitHub MCP `pull_request_read` → `get_check_runs` |
| Read legacy combined commit status | GitHub MCP `pull_request_read` → `get_status` |
| Read status/bot comments (failure reason) | GitHub MCP `pull_request_read` → `get_comments` |
| Read raw failure log (when comment is insufficient) | `gh run view --log-failed` |
| Rerun a failed job once | `gh run rerun --failed` |
| Correct the PR title | GitHub MCP `update_pull_request` |
| All code fixes | Implementer subagent (mid tier) via `Task` tool |
| Verification (inner loop) | `se-verify` (runner → judge split) |
| Review (outer loop) | `se-review` |
| Commit | `se-commit` (runner subagent) |
| Push fix commit to PR branch | `git push` — performed by the Track B executor subagent (cheap tier) via `Task` tool after `se-commit` completes |

GitHub MCP is the primary tool for all read operations and PR mutations. The two `gh` commands (`gh run rerun --failed`, `gh run view --log-failed`) are used only for the CI run-level operations that MCP does not expose. No other `gh` or raw API calls are introduced.
