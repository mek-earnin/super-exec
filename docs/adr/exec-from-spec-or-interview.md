---
Status: accepted
---

# Exec may start from a spec or interview WHAT

Discuss no longer always chains to plan. When work is already small and clear, a plan (architecture, data flow) would not improve implementation — it would only waste tokens. `/se-exec` may then start from an approved spec, or from settled interview answers (the **task spec**) when skip-spec. Skip-plan discuss auto-invokes `/se-exec` in the same session. Plan → execute stays a fresh-session boundary. Plan-backed exec still requires a ready ledger; skip-plan exec must not be sent back to `/se-plan` for a missing ledger. Verify, review, and commit stay mandatory.

## Considered options

- **Always plan after discuss.** Rejected: wastes tokens when work is already small and clear.
- **Skip discuss for small work as a product rule.** Rejected: user-triggered discuss must interview; auto-invoke remains model judgment.
- **Same-session plan → exec.** Rejected: keep the existing fresh-session boundary for the plan path.

## Consequences

- `/se-exec` has two activation modes: plan-backed and skip-plan.
- Skip-spec never offers plan.
- A session-boundary spec under `.super-exec` is the resume artifact when no governing spec exists and work must survive a handoff or context-limit.
