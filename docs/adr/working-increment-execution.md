# Runtime-discovered working-increment execution

Status: accepted

## Context

Executing a plan task-by-task in declared order can turn a feature into a waterfall: supporting layers complete before any user can exercise the requested behavior. When every task boundary also receives whole-spec review and every blocking finding must be fixed before work continues, later requirements and increasingly remote concerns block the current task. Each fix expands the surface for a new whole review, so the loop need not converge.

Discussion and planning can reinforce this failure by expanding acceptance work and ordering it horizontally by component or layer. A lower-layer probe, scripted state, or test suite may pass while the normal user path remains unbuilt or broken. Such proof is useful, but it is not equivalent to proof that the product works.

Approved scope, architecture, safety, and final correctness remain mandatory. This decision changes execution sequencing and review scope; it does not lower the required final outcome.

## Decision

`se-plan` preserves approved outcomes, requirements, architectural contracts, dependencies, and planned operational work. It maps approved requirements and relevant user transitions to available normal-path proof capabilities. It does not predefine or approve a list of working increments, freeze their boundaries, or freeze execution order.

At runtime, `se-exec` composes the smallest coherent end-to-end **working increment**: a slice that delivers a demonstrable part of the approved outcome through its appropriate normal path. It may split or reorder operational tasks to form that slice, provided it does not change approved scope, architecture, or requirement meaning. Dependencies and hard safety prerequisites still constrain sequencing.

Supporting layer, component, and infrastructure checkpoints remain useful. They receive focused verification and review appropriate to their changed paths and affected invariants. They are not represented as completed working increments merely because a lower-layer probe, scripted state, or narrow suite passes.

Full baseline verification, real-runtime proof, architecture review, and deep review occur at working-increment boundaries. Final completion still requires whole-spec proof over all approved requirements.

Plan activation is two-phase durable state: se-plan records active plan and canonical ledger path as `ledger_status: pending`, creates or validates the ledger, then records `ready`. Execution rejects incomplete, mismatched, or missing ledger state and returns to planning repair. An existing ledger is durable history, not a template: preserve its entries, dispositions, and evidence; create/seed only when absent. A committed-root plan publishes with its ready canonical ledger through the same review and commit flow.

### Invariants

- **Priority 1 — correctness:** requested behavior works through its real user path; correctness and safety gates remain mandatory.
- **Priority 2 — token efficiency:** after correctness, minimize context and token cost. Each cross-skill contract has one authoritative owner; callers reference it rather than restate it. Skill prose may use caveman compression and removes tokens that do not affect a decision, action, or evidence.
- Token optimization must never weaken requested-scope proof, safety, gates, resume state, or review convergence.
- Every approved requirement remains mandatory at final completion unless explicitly changed through the governing decision process.
- Runtime re-slicing may change order and checkpoint boundaries only; it may not silently add, remove, weaken, or reinterpret approved scope or architecture.
- A working increment is complete only with evidence that its selected normal path works end-to-end. Supporting evidence cannot substitute for that proof.
- Already-working behavior remains subject to non-regression checks.
- Direct, reachable security, privacy, data-loss, and correctness regressions remain blocking regardless of increment ordering or review effort.
- Review independence and evidence-based verification remain required.
- A fix creates a new review identity. Required proof and review rerun for that identity; all reviewed changes and tracked completion metadata are committed only after review and configured human approval clear the exact content.
- A human approval clears before commit only for its exact reviewed content. Any content change invalidates that approval and reopens the gate.
- Delivery identity is the committed result of an accepted review identity. PR HEAD and a clean tree must match the final verified and reviewed delivery identity.
- Configured human checkpoint gates remain honored. With Auto-PR OFF, one combined final review and deferred-disposition gate remains blocking until resolved.

## Requirement semantics

Each approved requirement is classified for the current execution state:

- **Current increment requirement:** required to complete the active working increment; failure blocks that increment.
- **Pending approved requirement:** approved work assigned to a later increment; it remains mandatory, but its absence is not a defect in the active increment.
- **Deferred non-required finding:** a concern that is not required for the active increment or final approved scope at that time. It is recorded for revalidation rather than silently discarded.

This classification is temporal, not a severity downgrade. A pending approved requirement becomes blocking when its increment is active and always blocks final completion if still unmet.

Pending approved requirements and deferred non-required concerns are separate sets. The latter may be deferred only with a recorded justification and revalidation point; the former are never deferments and remain final mandatory scope.

## Review convergence

Every review finding binds to an exact review identity and active increment scope. Review identity is pre-commit HEAD plus an exact scoped content snapshot, deterministic tracked-diff hash, and deterministic untracked-content hash. Evidence against any other identity is stale and rejected.

Delivery identity is post-commit HEAD and its tree. A commit is accepted only when deterministic tree/content equivalence proves that its delivery identity matches the reviewed snapshot. The PR clean gate evaluates delivery identity, not the earlier review identity.

A finding must have a recorded disposition:

- **Fix:** address it in the current increment.
- **Defer:** retain it for an explicit later revalidation point.
- **Decline:** reject it because its premise is unsupported, stale, or outside approved scope.

Disposition uses evidence-backed assessment of likelihood, impact, fix effort, confidence, and complexity added by the fix. The assessment must distinguish observed or directly reachable behavior from speculative possibility. Added complexity includes new state, concurrency, lifecycle, and regression surface, not only implementation size.

Findings have stable fingerprints so reviews do not relitigate the same concern after a local change. If absent, `se-plan` creates canonical sibling `deferred-findings-<plan-name>.md` beside active `plan-<plan-name>.md`, consistent with `handoff-<plan-name>.md`, and one-time seeds it with pre-plan deferred concerns. Once created, this controller-owned ledger is canonical durable history: re-planning preserves entries, dispositions, and evidence, updating only items required by changed scope. The plan document only references this ledger and holds approved requirements, outcomes, and tasks. Review, handoff, and active execution state reference it. Each entry carries fingerprint, evidence, disposition, promotion condition, and revalidation point. Auto-PR and final revalidation consume separate ledger; unresolved entries propagate to PR summary.

Re-review is scoped to changed paths, affected invariants, and unresolved blockers. Widening to an architecture-wide or deep review requires explicit evidence that the change broadened an architectural, trust-boundary, data-flow, or comparable system-wide risk. Repeated non-convergence escalates through a bounded decision path instead of restarting indefinitely.

A priority or order correction re-slices immediately and cancels obsolete in-flight review and fix work. Before re-slicing removed or changed scope, inventory every committed delivery identity and attributable behavior made obsolete by correction, including completed working increments and supporting checkpoints; remove it through normal reviewed commit flow or record explicit human approval to retain it. Final completion rechecks this inventory across committed delivery identities, so amended scope cannot silently ship obsolete behavior. Adding, dropping, or changing approved behavior requires governing-spec amendment and approval before completion. Deferred findings are revalidated before final completion; a deferment never makes an approved requirement optional.

## Runtime proof

Proof from the actual distributable or deployed normal path outranks probes, mocks, scripted states, and narrow test harnesses. Relevant user transitions for the active increment are part of that proof, not optional polish. Lower-level evidence remains valuable supporting evidence, but cannot close an increment when the normal path has not been demonstrated.

If the increment's end-to-end normal-path check fails, execution fixes or diagnoses that failure before deeper architecture or deep review. This short-circuit prevents review effort from outrunning proof that the increment provides user value.

If autonomous convergence or required normal-path proof cannot be reached, execution enters one finite terminal state: `blocked-review` for every unresolved fix-now finding, including correctness, naming, maintenance, or duplicate-code findings, and for configured human-gate blocking; justified review widening also counts toward this state. `blocked-limitation` is required for every validated `LIMITATION` and requires explicit human governing-spec resolution even when Auto-PR is ON. Neither state may defer a direct requested blocker, claim completion, continue into final review, or create a PR.

## Safety and correctness

This decision prioritizes review and proof; it does not relax correctness. Direct and reachable security, privacy, data-loss, or correctness regressions are blocking immediately. Reviewers must still identify such risks and require proportionate remediation. The deferment path applies only when the evidence and current requirement scope support it, with final revalidation preserving complete accountability.

## Consequences

Expected benefits:

- Earlier proof of user value and faster feedback on the real path.
- Resumable progress expressed as working increments rather than completed layers.
- Fewer repeated full suites and whole-feature reviews for local supporting changes.
- Less stale, duplicated, and speculative review churn.
- Lower repeated context and subagent prompt size; references remain resolvable and standalone modes retain their needed local contract.

Accepted costs:

- Execution must maintain increment state, requirement classification, finding fingerprints, dispositions, and revalidation records.
- Controllers and reviewers must exercise explicit triage judgment and receive exact revision and scope.
- Scoped review can miss a broader issue if widening evidence is ignored. Final whole-spec review and final normal-runtime proof mitigate, but do not eliminate, that risk.
- Delivery identity, deferred-ledger persistence, task reconciliation, and PR propagation add execution-state discipline.

## Alternatives considered

- **Keep task waterfall and improve prompts.** Rejected: prompts do not change plan-order execution, whole-spec task review, or the feedback loop's convergence properties.
- **Downgrade severity only.** Rejected: changing labels without scope, evidence, disposition, and re-review rules leaves the same loop intact.
- **Fix working increments during planning.** Rejected: a plan cannot reliably know the smallest viable slice before runtime discovery; fixed boundaries recreate a hidden waterfall.
- **Review the whole spec after every task.** Rejected: it makes unstarted, approved future work appear defective in the current increment.
- **Remove task checkpoints.** Rejected: focused checkpoints catch local regressions and preserve resumability.
- **Apply only a review budget.** Rejected: a budget without scope correction, finding dispositions, and escalation can suppress legitimate blocking work rather than make review converge.

## Migration and compatibility

Existing plans remain executable. The runtime controller derives working increments from their tasks, requirements, dependencies, and approved architecture; it need not rewrite the plan to do so. Requirement and outcome completion is authoritative: an original task or work-package checkbox completes only when its full outcome is complete, even if runtime work split across increments. Final completion requires every approved outcome.

Legacy plans with mixed `Architecture` sections are normalized during migration: only spec-backed or explicitly approved invariants gate execution; optional implementation HOW is design evidence. Ambiguity requires confirmation or re-planning before it can gate work.

Standalone `se-commit` and PR-triage retain explicit compatibility modes separate from active-increment review unless explicitly aligned by later decisions. The default delivery shape remains one plan and one final PR; intermediate working increments are execution progress, not a requirement to create separate plans or pull requests.
