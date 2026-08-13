---
name: se-review
description: Use inside se-exec for focused checkpoint review or convergent working-increment/final review.
---

# se-review — Scoped, Convergent Review

se-review evaluates exact review identity in `focused-checkpoint`, `working-increment-boundary`, `final`, or `standalone-triage`. Pending requirements never fail active increment.

## Required review packet

Controller supplies:

- review identity and changed paths;
- scope and active selected requirement IDs;
- pending requirement register;
- approved contracts, not optional HOW/design evidence;
- normal-path runtime proof and transition evidence for boundary/final scopes;
- known supported regressions, affected invariants, prior review disposition;
- separate plan-folder deferred ledger `deferred-findings-<plan-name>.md`, where `<plan-name>` derives from active plan filename.

Recompute identity before accepting evidence. Different-revision evidence is stale; rerun scope. `/se-commit` owns staging and delivery equivalence. Record pending work as pending, never finding. Consult ledger; do not reopen unchanged fingerprint.

## Review order

### Focused checkpoint

Review changed paths, selected enabling behavior, and affected invariants only. Require focused verification evidence. No full baseline, architecture gate, deep whole-increment review, or final spec-match assertion.

### Working-increment boundary

First require normal-path runtime PASS. If runtime/E2E failed, return `runtime-proof-failed`; do not run architecture/deep review.

After runtime PASS, independent reviewers assess:
1. Approved architecture contract conformance.
2. Direct data-flow correctness for selected requirements and known supported regressions.
3. Reuse/meaningful duplication and maintenance hazards.
4. Pattern/naming consistency and UI critique when applicable.

### Final

Require final full baseline and whole-spec normal-path proof after review fixes. Review whole traceability and approved contracts, then revalidate ledger. Any final-review code fix invalidates prior final proof; se-exec reruns final verification and this scoped final review on current revision.

### Standalone triage

Review PR/CI fix identity, changed paths, failure evidence, repository contracts, and explicit triage acceptance inputs. Preserve Critical/Important blocking behavior. Do not require active increment, pending register, or deferred ledger artifacts.

## Finding format and disposition

Every finding contains:

`id/fingerprint`, current revision, paths, requirement/invariant, concrete evidence, qualitative likelihood (`observed`, `reproducible`, `directly reachable`, `uncertain`, `unsupported`, `impossible`), impact, fix effort, confidence, fix-added complexity/regression surface, severity, disposition, and promotion trigger/status when deferred.

Severity describes impact. Disposition controls workflow:

- **fix now / block** — active requested behavior, known supported regression, direct reachable correctness/security/privacy/data-loss issue, real naming defect, meaningful duplicate code/reuse defect, or meaningful maintenance hazard. Direct reachable supported safeguards stay non-negotiable.
- **defer / non-blocking** — remote or uncertain concern whose expected risk does not justify current complexity. Persist stable fingerprint, evidence, promotion trigger (new runtime evidence, relevant code change, supported contract change), and `open` status.
- **decline** — stale, duplicate finding fingerprint, invalid, impossible, unsupported speculation, or out-of-scope pending requirement. Persist reason if it may recur.

Static possibility alone is never `likely`. Potential severity alone does not force a remote hypothetical to block without runtime/reachability evidence.

## Re-review and convergence

After local fix, capture new review identity, rerun appropriate `/se-verify` scope, then fresh reviewer receives identity, changed paths, affected invariants, unresolved blockers, pending register, and ledger. Re-review this scope only. Widen only with concrete changed-invariant evidence showing approved architecture, shared data flow, trust boundary, or behavior impact; every widening counts toward the bound.

At most two scoped re-review rounds, including widening. At bound, persist every unresolved fix-now finding in `blocked-review` with identity/evidence; surface and stop. Never defer it or claim completion. Remote/uncertain concerns may defer/decline before bound.

## Reports

Report identity/scope, runtime gate, findings/dispositions, ledger updates, rounds/widening, and clean/escalated result. Clean means no fix-now blocker in scope, not pending-work completion.

## Model and tool assignments

Architecture/deep reviewers = strong non-fast tier; reuse finder = cheap tier; fixer = mid tier. All dispatch through `Task`; no long review inline.
