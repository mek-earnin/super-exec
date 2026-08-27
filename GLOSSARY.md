# super-exec

Plugin workflow from intent to PR: discuss, optional plan, execute, verify, review.

## Language

**Skip-plan**:
After discuss, do not write a plan; enter `/se-exec` in the same session because a plan would not improve implementation.
_Avoid_: planless execution, optional plan

**Skip-spec**:
Existing feature with no spec, too small to record one. Interview answers are the task spec. Always skip-plan.
_Avoid_: no-spec, spec-less

**Task spec**:
Settled discuss interview answers that govern that `/se-exec` instance when no durable approved spec exists.
_Avoid_: unwritten spec, verbal spec, interview notes

**Session-boundary spec**:
Uncommitted `.super-exec` spec written without approval so skip-spec work can survive a handoff or context-limit.
_Avoid_: shadow spec, local spec
