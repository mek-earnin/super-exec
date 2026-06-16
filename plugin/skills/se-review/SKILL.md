---
name: se-review
description: Use when se-exec has just committed a task and needs an outer review loop — arch-gate, deep-review (data-flow → reuse → pattern), optional impeccable UI lens, severity-tagged findings, and fresh re-review after fixes, looping until clean.
---

# se-review — Outer Review Loop

se-review is the **outer review loop** invoked by se-exec after a task is committed and inner-loop-green has been declared by se-verify. It operates a distinct gate-and-review cycle: a fresh reviewer subagent checks architecture conformance first, then performs a structured deep-review pass. Findings are severity-tagged and blocked on Critical/Important. Fixes re-enter the inner loop (se-verify's fix path), and a fresh reviewer re-reviews from scratch after every fix cycle. The loop runs until a fresh reviewer declares the work clean.

> **Reference paths:** every `references/*.md` cited lives at the plugin root — read it as `${CLAUDE_PLUGIN_ROOT}/references/<file>` on Claude Code, or `${CURSOR_PLUGIN_ROOT}/references/<file>` on Cursor.

**Reviewers always run as subagents.** The controller dispatches, waits, and reads the returned summary. Heavy or long review never runs inline in the controller task.

**Realism filter (always active):** a finding is only valid if the failure state it describes can actually be reached given the code as written and the inputs the system can receive. Never flag impossible or unreachable cases — a negative index into an internally-controlled array the caller cannot influence, an error path that requires an input the API contract forbids, a race condition that cannot occur in a single-threaded runtime. A finding that requires an impossible state is not a finding. State this conclusion explicitly in any report that dismisses such a case.

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder steps. Do not advance past a step until it is confirmed done.

- [ ] **1. Arch-gate: dispatch a fresh reviewer subagent (strong non-fast tier).** See `references/model-tiers.md` for the concrete model and `references/tool-map.md` for the subagent dispatch primitive. Provide the reviewer with:
  - The AGREED architecture from the plan (the Architecture + Data Flow sections of `plan.md` and any risk-grilling decisions recorded there).
  - The committed implementation diff or the relevant modified files.
  - A single question: **does the implementation's shape match the agreed architecture?** The reviewer must render an explicit CONFORMS or DEVIATES verdict.

  The reviewer checks structural shape — component responsibilities, data-flow direction, module boundaries, interface signatures — against what the plan recorded as the agreed design. It does not yet assess correctness, bugs, or style.

- [ ] **2. Arch-gate verdict: DEVIATES → re-enter the inner loop.** If the arch-gate reviewer renders DEVIATES, the work does not proceed to deep review. Instead:
  - Dispatch the inner loop fix path (se-verify's fixer step) targeting the specific structural deviation only.
  - After the fixer completes and se-verify reports inner-loop-green again, return to step 1 and dispatch a FRESH arch-gate reviewer. The reviewer that detected the deviation does not re-review its own finding.
  - Repeat until the arch-gate reviewer renders CONFORMS.

- [ ] **3. Deep-review pass: dispatch a fresh reviewer subagent (strong non-fast tier).** Once the arch-gate is clean, dispatch a new reviewer subagent — not the arch-gate reviewer — with the full implementation diff and the spec acceptance criteria. Instruct the reviewer to assess in this exact order:

  **(a) Data-flow bugs.** Trace every data path from input to output. Look for: incorrect transformations, dropped or duplicated values, wrong ordering of operations, mishandled async boundaries, incorrect error propagation. Apply the realism filter: flag only paths that can actually be reached.

  **(b) Reuse-existing-utility check.** Did the implementation hand-roll something that a repo utility, helper, or installed skill already provides? Dispatch a finder subagent (cheap / investigator tier) to enumerate relevant repo utilities, helpers, and `.claude/skills/` entries before rendering this sub-finding. A hand-rolled duplicate of an existing repo utility is always at least an Important finding.

  **(c) Pattern and consistency check.** Does the implementation follow the conventions established in the codebase — naming, error handling style, logging, module structure, test patterns? Inconsistency that would confuse a future maintainer is a Minor finding unless it creates a correctness risk.

  The reviewer must tag every finding with exactly one severity: **Critical**, **Important**, or **Minor**. It must not hedge or omit a tag.

- [ ] **4. Apply the severity filter.**
  - **Critical** — correctness failure, data loss, security issue, or spec violation. BLOCKS. Must be fixed before reporting clean.
  - **Important** — meaningful defect (hand-rolled duplicate of existing utility, incorrect but recoverable behavior, pattern violation that creates a maintenance hazard). BLOCKS. Must be fixed before reporting clean.
  - **Minor** — style, readability, naming, low-impact inconsistency. NON-BLOCKING. Reported in the final summary; does not trigger a fix loop.

  If there are no Critical or Important findings, skip to step 7.

- [ ] **5. impeccable UI-critique lens (when enabled).** Evaluate this step if and only if the plan recorded an impeccable opt-in AND the feature involves UI work:
  - Detect whether impeccable is installed: glob `.claude/skills/impeccable*/SKILL.md` or the Cursor equivalent.
  - **If absent:** skip this lens. Note in the report: "impeccable not installed — UI lens skipped." Never block on an absent optional external.
  - **If present:** dispatch a reviewer subagent that runs impeccable `critique` (or `audit`, per the installed skill's interface) against the UI changes. The reviewer returns impeccable findings tagged with Critical / Important / Minor using the same severity rules. These findings enter the fix loop on the same terms as deep-review findings — Critical/Important block; Minor is reported only.

  impeccable is the only allowed optional external tool at this step. No other external tools are invoked here.

- [ ] **6. Critical/Important findings → re-enter the inner loop.** For each Critical or Important finding (including any from the impeccable lens):
  - Dispatch the inner loop fix path (se-verify's fixer step), providing the fixer with: the specific finding (what is wrong, where, and what the evidence showed), the relevant acceptance criteria, and the plan's architectural context. Do NOT provide the full review; give only what is needed to fix the specific issue.
  - After the fixer completes and se-verify reports inner-loop-green again, collect all fixes and return to step 3. Dispatch a FRESH deep-review reviewer — not the one that raised the finding and not the one that proposed the fix.
  - Minor findings are collected and held; they do not trigger a fix loop.

- [ ] **7. Fresh re-review after every fix cycle.** After any fix cycle (step 2 or step 6), the re-review is always performed by a NEW subagent that has not seen the prior review conversation. Provide the fresh reviewer with the full current diff and the spec. The reviewer runs the same deep-review sequence (steps 3a → 3b → 3c) plus the impeccable lens if enabled. Loop until a fresh reviewer finds zero Critical or Important findings.

- [ ] **8. Report clean.** Only when a fresh reviewer has returned zero Critical or Important findings, report the work as reviewed-clean. The report must include:
  - The arch-gate verdict (CONFORMS, how many cycles it took).
  - Each Critical and Important finding that was fixed (one line each: what it was, what fixed it).
  - All Minor findings with a recommendation for each (non-blocking; caller decides whether to act).
  - Whether the impeccable lens ran, was skipped, or was absent.
  - The fresh reviewer's clean verdict.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What to do instead |
|---|---|
| "I'll review it myself inline rather than dispatching a subagent." | Every review pass — arch-gate, deep-review, post-fix re-review — is a fresh reviewer subagent (strong non-fast tier). The controller dispatches, waits, reads the summary. Heavy review never runs inline. |
| "The architecture is close enough — it's basically what the plan said." | There is no "close enough" at the arch-gate. CONFORMS or DEVIATES. A deviation, however small in your judgment, re-enters the inner loop and re-gates. |
| "I'll skip the reuse check — this looks original." | The reuse check is always step (b) of the deep-review pass. Dispatch a finder subagent to enumerate repo utilities and skills before rendering a reuse verdict. Never assume originality without checking. |
| "This negative-index / impossible-input case is a bug." | Apply the realism filter. An index into an internally-controlled array that the caller cannot influence, or an error path gated by an API contract, is an unreachable case. Unreachable cases are not findings. Document the dismissal explicitly. |
| "The same agent that fixed it can re-review — it knows the context." | Fresh reviewer, always. The agent that proposed or applied the fix cannot re-review its own work. A new subagent with no prior conversation context re-reviews after every fix cycle. |
| "Minor issues should block until they're resolved." | Minor is non-blocking by definition. Collect Minor findings, include them in the final report, and let the caller decide. Only Critical and Important block the loop. |
| "impeccable isn't installed — I can't proceed with the UI review." | Skip the impeccable lens, note it in the report, and continue. impeccable is the only optional external; its absence never blocks the workflow. |
| "I'll give the fixer the full review context so it has everything it needs." | Give the fixer only the specific finding, the relevant acceptance criteria, and the plan's architectural context. The full review is noise; targeted context produces targeted fixes. |
| "Deep review can run before the arch-gate is clean." | Arch-gate FIRST, always. Deep review does not begin until a fresh reviewer has rendered CONFORMS on the architecture. Skipping the gate means reviewing code that may be structurally wrong. |
| "I'll run the impeccable lens even though the plan didn't opt in." | The impeccable lens runs if and only if the plan recorded an opt-in AND the feature involves UI work. No opt-in → no lens, regardless of whether impeccable is installed. |

---

## Severity Reference

| Severity | Meaning | Effect |
|---|---|---|
| **Critical** | Correctness failure, data loss, security issue, or spec violation. | BLOCKS. Re-enters inner loop immediately. |
| **Important** | Meaningful defect — hand-rolled duplicate of existing utility, incorrect but recoverable behavior, pattern violation creating a maintenance hazard. | BLOCKS. Re-enters inner loop. |
| **Minor** | Style, readability, naming, low-impact inconsistency. | NON-BLOCKING. Reported in final summary only. |

A reviewer that omits a severity tag or hedges ("this might be important") is sent back with an explicit instruction to tag every finding before the controller accepts the summary.

---

## Model and Tool Assignments

Resolve all concrete model IDs and dispatch primitives from the reference files — do not hardcode them here.

| Role | Prose alias | Reference |
|---|---|---|
| Arch-gate reviewer | strong non-fast tier | `references/model-tiers.md` → "Shape interview · Plan · Review" row |
| Deep-review reviewer | strong non-fast tier | `references/model-tiers.md` → "Shape interview · Plan · Review" row |
| impeccable critique reviewer | strong non-fast tier (subagent running impeccable) | `references/model-tiers.md` → "Shape interview · Plan · Review" row |
| Finder (reuse check) | cheap / investigator tier | `references/model-tiers.md` → "Script-runner · Finder" row |
| Fixer (inner loop) | implementer / mid tier (PINNED to Sonnet on CC) | `references/model-tiers.md` → "Implementer · Fixer" row and pinned-to-Sonnet policy |
| Subagent dispatch | `Task` tool (CC) / composer subagent (Cursor) | `references/tool-map.md` → "Subagent Dispatch" section |
