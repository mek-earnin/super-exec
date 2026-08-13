# Core workflow
> Ticket: NO_TICKET  ·  Status: active  ·  Depends on: none

## Problem / Why

super-exec must deliver approved behavior quickly without losing verification, review independence, repo conventions, human gates, or requirement traceability. Previous task-ordered execution could complete infrastructure and repeat whole-build reviews while normal user behavior remained unbuilt or unproven.

## Goals

- Turn intent into approved, provenance-aware requirements and architecture contracts.
- Let execution deliver smallest coherent, demonstrable user-value increments.
- Keep evidence, review, commits, handoffs, and final PR decisions auditable.
- Preserve runner/judge separation, review independence, spec authority, and direct security/privacy/data-loss/correctness safeguards.
- Keep four entrypoints: `/se-discuss`, `/se-plan`, `/se-exec`, and `/se-pr-triage`.

## Non-goals (out of scope)

- Changing standalone commit or post-PR triage workflow except shared review-evidence semantics.
- Treating model recommendations or research concerns as user requirements without explicit approval.
- Replacing real runtime proof with mocks, scripts, or lower-layer checks.
- Requiring every implementation default or file-map detail as architecture contract.

## Behavior / Requirements

### Discuss

1. `/se-discuss` maps material user decisions as a dependency graph: nodes are choices that can change requested WHAT, acceptance, priority, or first useful outcome; edges are prerequisites. Its frontier contains every unresolved node with settled prerequisites.
2. Nodes require user request/correction, verified current-behavior contradiction, or explicit user approval of a derived requirement. An explicitly user-raised edge case stays in the frontier until the user accepts, rejects, or explicitly defers it; if accepted, it remains a Core requested requirement with user priority regardless of likelihood. Only agent-originated concerns or suggestions default to Deferred until user promotion.
3. Each interview round asks the complete provenance-filtered frontier together, with stable session-unique numbered WHAT-only questions and each question’s own recommended answer.
4. Facts are agent work through research, codebase inspection, subagents, or MCP. A pending fact blocks only its dependent nodes; unrelated fact-settled frontier questions continue. If all candidate nodes require pending facts, the interview waits for those facts rather than asking incomplete questions.
5. Interview converges when its frontier is empty and shared understanding is reached, or when user signals such as “proceed,” “implement,” or “stop asking.” Those signals end questioning under user authority. Only settled decisions become requested or approved requirements; unanswered nodes remain deferred or unapproved and are never inferred/defaulted into scope. It must not write a spec or adopt inferred decisions before that point. Stress testing exposes material ambiguity but cannot expand scope indefinitely.
6. Specs distinguish concise **Core requested requirements**, **Approved derived requirements**, and **Deferred concerns**. Derived requirements retain provenance/priority; recommendation/research/model discovery never silently becomes core.
7. Specs remain WHAT-only. Existing-spec updates preserve their discovered root without consulting config or re-prompting about placement; commit every spec whose resolved on-disk root is `docs/specs/`. Local-root specs remain local.

### Plan

1. `/se-plan` records approved outcomes, dependencies, requirement traceability/provenance, architecture contracts, normal runtime verification path, and focused checkpoint checks.
2. File map and design evidence support architecture; they never dictate task order, working increments, or acceptance.
3. Plan work packages are not immutable execution increments. `/se-exec` may split, combine, and reorder them operationally while preserving approved outcomes, final traceability, and approved architecture contracts.
4. Only approved behavior and real invariants can make architecture blocking. Optional HOW/defaults belong in design evidence and cannot silently become acceptance.
5. Every approved requirement maps to an outcome and remains mandatory for final completion. Later requirements are pending, not current defects.
6. After plan file is written, immediately record `active_plan`, canonical ledger path, and `ledger_status: pending`; approval is not the first time `active_plan` is recorded. Only after ledger creation/validation does se-plan transition status to `ready`.
7. Plan maps required outcomes/transitions to available normal proof paths, not to pre-defined increments. Folder/file trees and optional HOW live in Design Evidence; only spec-backed or explicitly approved structural invariants are gateable.
8. A plan creates sibling `deferred-findings-<plan-name>.md` only when absent, including an empty ledger. It one-time seeds non-required Discuss/spec deferred concerns and is canonical thereafter; existing ledger entries, dispositions, and evidence are preserved and never reseeded or overwritten. Requirement traceability never contains ledger rows. When plan lives under committed root, plan and ready canonical ledger receive same approval/review and one `/se-commit` publication; plan never commits alone.

### Execute

1. `/se-exec` activation reads existing `.super-exec/active` first. Before entering execution, it requires matching canonical ledger path, `ledger_status: ready`, and existing canonical file; absent, pending/non-ready, mismatched, or missing ledger returns to se-plan repair without execution. It preserves any existing `active_plan` and convenience `branch` until plan resolution replaces them. Plan frontmatter is durable execution metadata. A missing checklist is never treated as completed; completion requires frontmatter `status: completed`, or a checklist exists, has at least one item, and all items are checked.
2. It maintains durable active increment state: working-increment outcome, selected requirements, review identity, delivery identity when committed, supporting checkpoints, runtime proof/evidence, pending requirements, deferred-ledger reference/status only, corrections, and toggles.
3. **Working increment** is smallest coherent end-to-end unfinished requested slice that produces actual user value fastest. **Supporting checkpoint** is enabling work with focused verification, focused review, and focused reviewed commit; it does not complete an iteration. **Pending requirement** remains final mandatory scope outside active increment.
4. A user correction immediately cancels obsolete implementer/fixer/verifier/reviewer work and declines stale output. Before re-slicing, inventory every committed delivery identity and attributable behavior made obsolete by removed/changed scope, including completed working increments and supporting checkpoints; each must be removed through normal reviewed commit flow or explicitly retained by human approval, with durable resolution evidence. Unresolved inventory blocks re-slicing and final completion. Then update requirement provenance/outcome and re-slice active increment. Stale review work is never completed.
5. Review-before-commit and Auto-PR resolve from `/se-get-config`; resolved values do not prompt. With review-before-commit off, standing authorization permits focused checkpoint commits.
6. One approved plan yields one final PR unless user explicitly stops. Supporting checkpoints may commit safely but do not open or complete a PR.
7. `Final review / PR decision` is not an executable implementation task.
8. The native task/todo tool is operational session state; plan, active marker, handoff, and ledger provide durable resume state.
9. Post-PR triage retains two human gates: Gate 1 approves decisions and Fix scope only, while Gate 2 approves exact final reply target/body after any fix is pushed.
10. Review identity is pre-commit `HEAD` plus deterministic exact scoped tracked-diff/untracked-content hash and reviewed content tree. Before commit staging equals reviewed content identity; commit creates delivery identity (new `HEAD`/tree), whose tree/content must equal reviewed snapshot. Only changed content reruns verify/review; a changed SHA with equivalent tree does not. PR requires clean tree and `HEAD` equal delivery identity.
11. Boundary/final sequence is fix → capture review identity → scoped verify → scoped review → prove staged equality → commit → prove delivery-tree equality.
12. Checkpoint human review writes `gate-open`, presents reviewed diff/message and identity, then waits explicit approval. It clears `gate-open` before `/se-commit`; content change invalidates approval and reopens the gate. Auto-PR OFF uses one combined final-work/deferred-disposition gate with the same clear-before-PR-safe-action ordering; OFF checkpoint mode remains standing authorization.
13. LIMITATION persists `blocked-limitation` and skips review/commit/PR/completion until explicit human governing-spec approval/amendment (and re-plan if architecture changes), regardless of Auto-PR. Finite review rounds persist `blocked-review` and stop on every unresolved fix-now blocker.

### Verification

1. Verification remains runner → judge: runner supplies structured evidence; independent strong judge renders explicit PASS/FAIL/LIMITATION.
2. Supporting checkpoint runs cheapest relevant focused checks only. It does not run full baseline or deep review.
3. Working-increment boundary runs full detected baseline plus selected-requirement proof through named normal distributable/deployed/user path. It covers relevant selected transitions such as clean launch, reconnect, retry, Forget → Connect, permission changes, and crash/restart.
4. Unit, static, mocked, bridge, scripted-state, or lower-layer evidence is supporting only; it cannot count as normal user-flow PASS.
5. Runtime/E2E failure short-circuits architecture/deep review until core normal flow works.
6. Final completion reruns full detected baseline and whole-spec normal-path proof after all review fixes. Any final-review code fix invalidates prior final proof and reruns final verification/review against current revision.

### Review

1. Every review binds to exact current revision/diff, declared scope, active selected requirements, pending register, approved architecture contracts, runtime evidence, and deferred ledger.
2. Review scopes: focused checkpoint; working-increment boundary; final. Full architecture/deep review occurs only at working-increment boundary or final, after runtime proof. A pending/later requirement cannot fail active increment.
3. A stale-revision finding is declined. Fresh reviewers consult durable deferred ledger and cannot reopen unchanged finding under different wording.
4. Each finding records stable identity/fingerprint, evidence, qualitative likelihood, impact, fix effort, confidence, fix-added complexity/regression surface, severity, disposition, and promotion trigger/status where deferred. Static possibility alone is not likely.
5. Severity measures impact; disposition controls flow:
   - `fix now/block`: active requested behavior, known supported regression, direct reachable correctness/security/privacy/data-loss issue, real naming problem, meaningful duplicate code/reuse defect, or meaningful maintenance hazard.
   - `defer/non-blocking`: remote/uncertain concern whose expected risk does not justify current complexity; persist fingerprint, evidence, promotion trigger, and status.
   - `decline`: stale, duplicate finding fingerprint, invalid, impossible, unsupported speculation, or pending/out-of-scope finding.
6. Direct reachable supported security/privacy/data-loss/correctness safeguards remain non-negotiable. Hypothetical severe scenarios need runtime/reachability evidence before blocking.
7. After local fix, re-review changed paths, affected invariants, and unresolved blockers. Widen only with explicit evidence of approved architecture, shared data-flow, trust-boundary, or broader behavior impact.
8. At most two scoped re-review rounds, including justified widening, may run. At terminal bound every unresolved fix-now finding persists in `blocked-review`, is surfaced, and stops autonomous work; remote/uncertain concerns may be evidence-based defer/decline before that bound.
9. Before final plan completion, revalidate deferred ledger. Remove fixed/invalid/duplicate findings and apply only tightly bounded safe local fixes. With Auto-PR OFF, one human gate combines deferred disposition and final-work review; Auto-PR ON adds brief PR notice and proceeds to PR review.
10. Deferred concerns are separate from required traceability and never become mandatory scope merely by register presence. On plan write, se-plan creates/same-root-commits canonical separate plan-folder `deferred-findings-<plan-name>.md`, derived from `plan-<plan-name>.md`, even if empty; it one-time seeds Discuss/spec deferred concerns as non-required entries. Once plan exists this ledger is canonical. Plan, handoff, and active marker reference its path/status only, never rows. Each entry has fingerprint, normalized scenario/invariant, affected behavior/path, source/evidence, likelihood/impact/effort/confidence/fix-added complexity, disposition/status, and promotion trigger.

### Handoff and commits

1. Handoff lives beside plan and persists active increment, checkpoints, selected requirements, review/delivery identities, runtime demonstration/evidence, pending requirements, deferred ledger path/status only, corrections, branch/toggles, and current revision. Resume restores this state, not merely next plan task.
2. `se-commit` accepts focused checkpoint review evidence or increment-boundary review evidence for exact staged paths/review identity; it verifies staging/reviewed snapshot and delivery-tree equivalence without duplicating review inside active se-exec. Standalone commit and PR-triage behavior remain unchanged.
3. PR preparation receives final delivery identity/clean-tree evidence and unresolved deferred summary. It rejects mismatch or a missing summary when unresolved ledger entries exist, for both repo-skill and fallback paths.

## Verification design

- Plan detects baseline and names normal runtime path before execution.
- UI, browser, E2E, deployed, and distributable checks record startup/launch evidence, readiness, artifact identity, and user-visible outcome as applicable.
- No controller runs heavy verification/review inline.
- Model tiers remain role-based: strong non-fast for discuss/plan/review/judgment, mid for implementation/fix, latest available non-fast GPT Luna for runners/finders under Cursor mapping, with non-fast Composer or an equivalent cheap-tier model as fallback.

## Artifacts & locations

Artifact placement remains config-driven. Existing spec updates preserve discovered root. Both roots remain symmetric:

| Artifact | Location | Commit |
|---|---|---|
| Spec | `<root>/[<app>/]<feature>/spec-<feature>.md` | resolved root |
| Plan | `<root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md` | resolved root |
| Handoff | plan folder `handoff-<plan-name>.md` | follows plan |
| Deferred finding ledger | plan folder `deferred-findings-<plan-name>.md` | follows plan |
| Active marker | `.super-exec/active` | local |

`<root>` is `docs/specs/` or `.super-exec/specs/`. `commitPlan` remains derived from governing spec root. Plan frontmatter contains `title`, `feature`, `branch`, and `status: pending`; execution updates `status` from `pending` to `in_progress`, then to `completed`.

## Domain terms

- **Core requested requirement** — user-stated acceptance.
- **Approved derived requirement** — explicitly approved recommendation/research discovery, with provenance/priority.
- **Working increment** — smallest coherent end-to-end value slice with normal-path proof.
- **Supporting checkpoint** — focused enabling progress, not increment completion.
- **Pending requirement** — final mandatory scope outside active increment.
- **Deferred finding** — durable non-blocking review concern with evidence/fingerprint/promotion trigger.
- **Normal-path proof** — evidence through path user/distributable/deployment actually uses, not substitute test state.

## Decisions

- Spec authority remains: ordinary divergence is code bug by default. Genuine limitation always requires explicit human governing-spec approval/amendment; Auto-PR has no amendment authority.
- Plan architecture contracts stay authoritative; file maps/defaults are evidence, not gates.
- Review disposition model applies to active se-exec only. Standalone commit and post-PR triage preserve their own workflow.

## Related specs

- [`se-config and configurable artifact placement`](../se-config-and-artifact-placement/spec-se-config-and-artifact-placement.md)
- [`PR triage watch bot`](../pr-triage-watch-bot/spec-pr-triage-watch-bot.md)
