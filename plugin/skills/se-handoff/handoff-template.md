# Handoff — <plan-dir name>

## Session State
- Branch: <branch-name>
- Base: <base-branch>
- Plan: <root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md
- Review-before-commit: on | off
- Auto-PR: on | off
- UI plan: yes | no

## Active Working Increment
- Outcome: <smallest coherent end-to-end user value, or `None.`>
- Selected requirements: <traceability IDs/requirements>
- State: <slicing | implementing | runtime-proof | reviewing | checkpointed>
- Runtime demonstration: <normal path and selected transitions, or `pending`>
- Review identity: <pre-commit HEAD + deterministic scoped tracked/untracked hash + reviewed content snapshot>
- Delivery identity: <committed HEAD/tree equivalent to reviewed snapshot, or `pending`>

## Supporting Checkpoints
### <Checkpoint name>
- Status: <completed | in progress | pending>
- Focused evidence: <brief summary — exit code, count, key output>
- Focused review / commit: <revision or pending>

## Pending Requirements
<Approved requirements outside active increment, with traceability IDs, or `None.`>

## Deferred Ledger Reference
- Path: <plan-folder>/deferred-findings-<plan-name>.md
- Status: <absent | open | revalidated | empty>

## Reconciliation
- Required outcome status: <complete/pending IDs>
- Work-package checkbox status: <only fully complete named outcomes checked>
- Terminal state: <none | blocked-review | blocked-limitation>

## Corrections And Decisions
<Current user corrections, scope clarifications, cancellation state, or `None.`>
