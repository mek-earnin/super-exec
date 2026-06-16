---
name: se-review
description: Use when se-exec has just committed a task and needs an outer review loop — arch-gate, deep-review (data-flow → reuse → pattern), optional impeccable UI lens, severity-tagged findings, and fresh re-review after fixes, looping until clean.
---

# se-review — Outer Review Loop

se-review is the **outer review loop** invoked by se-exec after a task is committed and inner-loop-green has been declared by se-verify. It operates a distinct gate-and-review cycle: a fresh reviewer subagent checks architecture conformance first, then performs a structured deep-review pass. Findings are severity-tagged and blocked on Critical/Important. Fixes re-enter the inner loop (se-verify's fix path), and a fresh reviewer re-reviews from scratch after every fix cycle. The loop runs until a fresh reviewer declares the work clean.

**Reviewers always run as subagents.** The controller dispatches a fresh reviewer subagent with the `Task` tool, waits, and reads the returned summary. Heavy or long review never runs inline in the controller task.

**Realism filter (always active):** a finding is only valid if the failure state it describes can actually be reached given the code as written and the inputs the system can receive. Never flag impossible or unreachable cases — a negative index into an internally-controlled array the caller cannot influence, an error path that requires an input the API contract forbids, a race condition that cannot occur in a single-threaded runtime. A finding that requires an impossible state is not a finding. State this conclusion explicitly in any report that dismisses such a case.

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder steps. Do not advance past a step until it is confirmed done.

- [ ] **1. Arch-gate: dispatch a fresh reviewer subagent (strong / reviewer tier) using the `Task` tool.** See the `se-subagent` skill for prose tier aliases and dispatch guidance. Provide the reviewer with:
  - The AGREED architecture from the plan (the Architecture + Data Flow sections of `plan.md` and any risk-grilling decisions recorded there).
  - The committed implementation diff or the relevant modified files.
  - A single question: **does the implementation's shape match the agreed architecture?** The reviewer must render an explicit CONFORMS or DEVIATES verdict.

  The reviewer checks structural shape — component responsibilities, data-flow direction, module boundaries, interface signatures — against what the plan recorded as the agreed design. It does not yet assess correctness, bugs, or style.

- [ ] **2. Arch-gate verdict: DEVIATES → re-enter the inner loop.** If the arch-gate reviewer renders DEVIATES, the work does not proceed to deep review. Instead:
  - Dispatch the inner loop fix path (se-verify's fixer step) targeting the specific structural deviation only.
  - After the fixer completes and se-verify reports inner-loop-green again, return to step 1 and dispatch a FRESH arch-gate reviewer. The reviewer that detected the deviation does not re-review its own finding.
  - Repeat until the arch-gate reviewer renders CONFORMS.

- [ ] **3. Deep-review pass: dispatch a fresh reviewer subagent (strong / reviewer tier) using the `Task` tool.** Once the arch-gate is clean, dispatch a new reviewer subagent — not the arch-gate reviewer — with the full implementation diff and the spec acceptance criteria. Instruct the reviewer to assess in this exact order:

  **(a) Data-flow bugs.** Trace every data path from input to output. Look for: incorrect transformations, dropped or duplicated values, wrong ordering of operations, mishandled async boundaries, incorrect error propagation. Apply the realism filter: flag only paths that can actually be reached.

  **(b) Reuse-existing-utility check.** Did the implementation hand-roll something that a repo utility, helper, or installed skill already provides? Dispatch a finder subagent (cheap / finder tier) using the `Task` tool to enumerate relevant repo utilities, helpers, and `.claude/skills/` entries before rendering this sub-finding. A hand-rolled duplicate of an existing repo utility is always at least an Important finding.

  **(c) Pattern and consistency check.** Does the implementation follow the conventions established in the codebase — naming, error handling style, logging, module structure, test patterns? Inconsistency that would confuse a future maintainer is a Minor finding unless it creates a correctness risk.

  The reviewer must tag every finding with exactly one severity: **Critical**, **Important**, or **Minor**. It must not hedge or omit a tag.

- [ ] **4. Apply the severity filter.**
  - **Critical** — correctness failure, data loss, security issue, or spec violation. BLOCKS. Must be fixed before reporting clean.
  - **Important** — meaningful defect (hand-rolled duplicate of existing utility, incorrect but recoverable behavior, pattern violation that creates a maintenance hazard). BLOCKS. Must be fixed before reporting clean.
  - **Minor** — style, readability, naming, low-impact inconsistency. NON-BLOCKING. Reported in the final summary; does not trigger a fix loop.

  If there are no Critical or Important findings, skip to step 7.

- [ ] **5. impeccable UI-critique lens (when enabled).** Evaluate this step if and only if the plan recorded an impeccable opt-in AND the feature involves UI work:
  - Detect whether impeccable is installed: glob `.claude/skills/impeccable*/SKILL.md`.
  - **If absent:** skip this lens. Note in the report: "impeccable not installed — UI lens skipped." Never block on an absent optional external.
  - **If present:** dispatch a reviewer subagent using the `Task` tool that runs impeccable `critique` (or `audit`, per the installed skill's interface) against the UI changes. The reviewer returns impeccable findings tagged with Critical / Important / Minor using the same severity rules. These findings enter the fix loop on the same terms as deep-review findings — Critical/Important block; Minor is reported only.

  impeccable is the only allowed optional external tool at this step. No other external tools are invoked here.

- [ ] **6. Critical/Important findings → re-enter the inner loop.** For each Critical or Important finding (including any from the impeccable lens):
  - **Spec-violation findings default to a code fix.** The spec is authoritative; divergence from the spec is a bug in the code by default. The fix is always to the CODE, not the spec. Only se-exec's limitation-escalation tree ever changes the spec — and only when an implementation limitation makes the spec genuinely unachievable. Never propose a spec change as the resolution to a Critical spec-violation finding unless se-exec's escalation path has been explicitly triggered.
  - Dispatch the inner loop fix path (se-verify's fixer step) using the `Task` tool, providing the fixer with: the specific finding (what is wrong, where, and what the evidence showed), the relevant acceptance criteria, and the plan's architectural context. Do NOT provide the full review; give only what is needed to fix the specific issue.
  - After the fixer completes and se-verify reports inner-loop-green again, collect all fixes and return to step 3. Dispatch a FRESH deep-review reviewer — not the one that raised the finding and not the one that proposed the fix.
  - Minor findings are collected and held; they do not trigger a fix loop.

- [ ] **7. Fresh re-review after every fix cycle.** After any fix cycle (step 2 or step 6), the re-review is always performed by a NEW subagent dispatched with the `Task` tool that has not seen the prior review conversation. Provide the fresh reviewer with the full current diff and the spec. The reviewer runs the same deep-review sequence (steps 3a → 3b → 3c) plus the impeccable lens if enabled. Loop until a fresh reviewer finds zero Critical or Important findings.

- [ ] **8. Report clean.** Only when a fresh reviewer has returned zero Critical or Important findings, perform a final spec-match assertion before closing the loop:

  **Final spec-match assertion (lightweight backstop):** confirm that the assembled implementation, taken as a whole, still matches the spec's documented decisions and acceptance criteria. This is not a full re-review — it is a single pass checking for cross-task drift that per-task verification could miss (e.g., two individually-correct tasks whose interaction violates a spec invariant, or a late fix that silently reverted an earlier accepted decision). If the assertion fails, treat the drift as a Critical finding and re-enter step 6.

  Once the assertion passes, report the work as reviewed-clean. The report must include:
  - The arch-gate verdict (CONFORMS, how many cycles it took).
  - Each Critical and Important finding that was fixed (one line each: what it was, what fixed it).
  - All Minor findings with a recommendation for each (non-blocking; caller decides whether to act).
  - Whether the impeccable lens ran, was skipped, or was absent.
  - The fresh reviewer's clean verdict and the spec-match assertion result.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What to do instead |
|---|---|
| "I'll review it myself inline rather than dispatching a subagent." | Every review pass — arch-gate, deep-review, post-fix re-review — is a fresh reviewer subagent (strong / reviewer tier) dispatched with the `Task` tool. The controller dispatches, waits, reads the summary. Heavy review never runs inline. |
| "The architecture is close enough — it's basically what the plan said." | There is no "close enough" at the arch-gate. CONFORMS or DEVIATES. A deviation, however small in your judgment, re-enters the inner loop and re-gates. |
| "I'll skip the reuse check — this looks original." | The reuse check is always step (b) of the deep-review pass. Dispatch a finder subagent with the `Task` tool to enumerate repo utilities and skills before rendering a reuse verdict. Never assume originality without checking. |
| "This negative-index / impossible-input case is a bug." | Apply the realism filter. An index into an internally-controlled array that the caller cannot influence, or an error path gated by an API contract, is an unreachable case. Unreachable cases are not findings. Document the dismissal explicitly. |
| "The same agent that fixed it can re-review — it knows the context." | Fresh reviewer, always. The agent that proposed or applied the fix cannot re-review its own work. A new subagent with no prior conversation context re-reviews after every fix cycle. |
| "Minor issues should block until they're resolved." | Minor is non-blocking by definition. Collect Minor findings, include them in the final report, and let the caller decide. Only Critical and Important block the loop. |
| "impeccable isn't installed — I can't proceed with the UI review." | Skip the impeccable lens, note it in the report, and continue. impeccable is the only optional external; its absence never blocks the workflow. |
| "I'll give the fixer the full review context so it has everything it needs." | Give the fixer only the specific finding, the relevant acceptance criteria, and the plan's architectural context. The full review is noise; targeted context produces targeted fixes. |
| "Deep review can run before the arch-gate is clean." | Arch-gate FIRST, always. Deep review does not begin until a fresh reviewer has rendered CONFORMS on the architecture. Skipping the gate means reviewing code that may be structurally wrong. |
| "I'll run the impeccable lens even though the plan didn't opt in." | The impeccable lens runs if and only if the plan recorded an opt-in AND the feature involves UI work. No opt-in → no lens, regardless of whether impeccable is installed. |
| "This spec violation should be fixed by updating the spec." | The spec is authoritative. A spec violation is a code bug by default. Fix the code. Only se-exec's limitation-escalation tree changes the spec, and only when the spec is genuinely unachievable. |

---

## Severity Reference

| Severity | Meaning | Effect |
|---|---|---|
| **Critical** | Correctness failure, data loss, security issue, or spec violation. | BLOCKS. Re-enters inner loop immediately. Spec violations default to a code fix — see step 6. |
| **Important** | Meaningful defect — hand-rolled duplicate of existing utility, incorrect but recoverable behavior, pattern violation creating a maintenance hazard. | BLOCKS. Re-enters inner loop. |
| **Minor** | Style, readability, naming, low-impact inconsistency. | NON-BLOCKING. Reported in final summary only. |

A reviewer that omits a severity tag or hedges ("this might be important") is sent back with an explicit instruction to tag every finding before the controller accepts the summary.

---

## Model and Tool Assignments

See the `se-subagent` skill for prose tier aliases and dispatch guidance. Never hardcode a version-pinned model ID here.

| Role | Prose alias | Dispatch |
|---|---|---|
| Arch-gate reviewer | strong / reviewer tier | `Task` tool |
| Deep-review reviewer | strong / reviewer tier | `Task` tool |
| impeccable critique reviewer | strong / reviewer tier (subagent running impeccable) | `Task` tool |
| Finder (reuse check) | cheap / finder tier | `Task` tool |
| Fixer (inner loop) | mid / fixer tier — PINNED to `sonnet` on CC | `Task` tool |
