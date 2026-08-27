---
name: se-exec
description: Use when a reviewed plan, or an approved spec or task spec on skip-plan, is ready to build, prove as working increments, and prepare one final PR.
---

# se-exec — Build Session Orchestrator

Execute approved outcomes as smallest coherent end-to-end **working increments**. Plan task order/file maps are evidence, never execution authority.

## Operational checklist

Use harness todo-list tool to load and track this checklist. Sync status as work changes; before approval, delivery, or completion claim, verify every applicable item complete.

- [ ] Activate, verify readiness, and resolve config
- [ ] Synchronize harness todo and durable state
- [ ] Select or correct smallest value slice
- [ ] Deliver reviewed checkpoints
- [ ] Prove runtime boundary
- [ ] Review, fix, and commit delivery
- [ ] Reconcile final outcomes and metadata
- [ ] Complete PR gate, terminal state, or handoff

## Activate

Read existing `.super-exec/active` first; the marker field `mode: skip-plan` is the discriminator that selects one of two activation modes. Absent `mode: skip-plan` is plan-backed even when the marker carries `spec:`; never infer skip-plan from a missing `active_plan`. Resolvable `active_plan` plus leftover `mode: skip-plan` → plan-backed wins: drop `mode: skip-plan` and follow the plan-backed gate (a later `/se-plan` is the user's choice).

**Plan-backed:** resolve explicit plan; else `active_plan`; else latest fallback with user confirmation. Read plan, spec under `docs/specs/` or `.super-exec/specs/`, checklist, traceability, runtime proof, handoff, and sibling `deferred-findings-<plan-name>.md`. Before `phase: exec`, `.super-exec/active` must retain `active_plan`, optional `branch`, matching `ledger_path`, and `ledger_status: ready`; ledger must exist. No `mode: skip-plan` and any of those missing → return to `/se-plan`; do not repair or execute.

**Skip-plan:** marker carries `mode: skip-plan` and `spec:`. Governing artifact is the spec that `spec:` names, or the **task spec** (settled discuss answers) when the value is the sentinel `task-spec`; a session-boundary spec under `.super-exec/specs/` may carry it across a boundary. Plan, ledger, and `active_plan` are absent by design — never return to `/se-plan` for a missing plan or ledger, and skip only ledger work that has no ledger. Same-session discuss may auto-invoke this mode; a later session resumes from marker `spec:`, the skip-plan handoff `.super-exec/handoff-<feature>.md`, and skip-plan increment state, no plan folder. Detect baseline and name the normal runtime path from that artifact. Verify, review, and commit stay mandatory; proof is never weakened.

Then write `phase: exec`, `started: <current UTC ISO-8601>`, preserve increment/handoff state, invoke `/se-local-ignore`. Skip-plan also (re)writes `mode: skip-plan` and `spec:` whenever either is missing, so the next session and the session-start hook still read skip-plan instead of hunting a plan on disk.

Plan-backed: verify current branch matches plan `branch`; skip-plan uses marker `branch` or the discuss branch. Completed iff `status: completed`, or a nonempty checklist exists and every item is checked; missing checklist never completes. Stop if complete. Change `pending` → `in_progress`; skip-plan has no plan frontmatter to move. Seed native todo from durable outcome state. Update native todo before durable state at every increment transition.

Get `humanReviewBeforeCheckpointCommit` and `autoCreatePr` from `/se-get-config`. Use booleans directly; ask only for `"ask"`. OFF review-before-commit is standing checkpoint-commit authorization.

## Operate

1. Select smallest unfinished user-value slice. Record selected/pending requirement IDs, normal proof/transitions, dependencies, revision. Every approved requirement remains mapped and mandatory.
2. Correction/stop cancels stale implementer/fixer/verifier/reviewer output. Inventory every committed identity/behavior obsolete from changed scope; remove it through focused verify/review/`/se-commit`, or get explicit retention approval. Persist identity, behavior, resolution, approval/evidence. Resolve inventory before re-slicing; decline obsolete findings.
3. Supporting checkpoint only unblocks slice: mid implementer with bound repo skills → `/se-verify supporting-checkpoint` focused evidence → `/se-review focused-checkpoint` exact identity/paths/requirements/invariants → reviewed focused `/se-commit`. If review-before-commit ON: write `gate-open`, show exact diff/message/identity, wait approval; content change invalidates approval—reopen, re-present, and wait again; clear marker before commit. Persist evidence/identity; do not complete increment/later requirements.
4. Assembled slice: `/se-verify working-increment` = full detected baseline, named normal distributable/deployed/user proof, relevant transitions. Unit/mock/bridge/script/lower-layer PASS is supporting only. Runtime/E2E FAIL stops architecture/deep review.
5. Runtime PASS: `/se-review working-increment-boundary` receives exact identity, selected/pending requirements, supported regressions, approved contracts, ledger, runtime proof. Pending work is never finding; stale findings decline. Local fix re-verifies/re-reviews changed paths/invariants/blockers only; widen only with evidence of contract, shared-data-flow, trust-boundary, or out-of-slice behavior impact. Obey `/se-review` bound; `blocked-review` persists/surfaces blockers and stops. Every content fix restarts verify → review → `/se-commit` delivery equivalence. Complete/reconcile selected requirements only after all three.

## Finish

Before final: correction inventory resolved; revalidate canonical ledger—remove fixed, invalid, duplicate, obsolete entries. Controller owns ledger; reviewers propose entries. Deduplicate normalized invariant/scenario + affected behavior/path fingerprint; meaningful duplicate code/reuse defect fixes now. Then `/se-verify final` (full baseline, whole-spec normal proof, cross-increment transitions) and final `/se-review`. Any content/ledger fix restarts final verify/review on new identity, then `/se-commit`.

Reconcile outcome status, todos, traceability, handoff, and checklist. Set plan `status: completed` and final bookkeeping only after required outcomes and full work packages, current proof/review, delivery, and reconciliation; `Final review / PR decision` cannot complete earlier. Committed-root metadata is content: focused verify/review then `/se-commit`. Require clean tree and `HEAD` = final delivery identity.

Skip-plan carries no plan frontmatter or checklist: same required outcomes, current proof/review, delivery, and reconciliation gate completion against its governing artifact. One plan, or one governing spec or task spec, yields one final PR unless the user explicitly stops; supporting checkpoints never open or complete a PR.

Auto-PR ON → `/se-pr` with unresolved-ledger summary. OFF → write `gate-open`, show exact final identity/content + disposition, wait matching approval, clear marker before PR-safe action, ask draft PR. No → clear active; yes → `/se-pr` with summary. Never omit unresolved summary.

## Terminal and handoff

`LIMITATION` is never PASS: persist `blocked-limitation` with identity, outcome, evidence, workaround; skip review/commit/PR/checklist/completion. Require explicit governing-spec approval/amendment before another completion gate; re-plan architecture changes. Priority/order-only correction re-slices. Add/drop/change approved behavior needs approved spec amendment; commit it when root is committed.

Low context → `/se-handoff`: active outcome/checkpoints, requirement IDs, review/delivery identities, runtime evidence, pending IDs, ledger reference/status, corrections, revision, toggles, next slice. Resume state, never next task. Plan-backed handoff lives beside the plan; skip-plan handoff lives under `.super-exec/` with no plan folder.

Skip-plan governing artifact is the approved spec or task spec: amendments, LIMITATION resolution, and scope guard target it. Spec is authority. Never drop/demote approved requirements or promote optional HOW/file maps/defaults into acceptance/blocking architecture absent approved behavior/real invariant. `/se-review` owns identity/convergence; `/se-commit` owns staged-review and delivery-tree equivalence. Heavy work via `Task`: implementer/fixer mid, runner cheap, judge/reviewer strong non-fast; never inline build/test/git/long review.
