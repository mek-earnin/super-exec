---
name: se-verify
description: Use when se-exec has just completed an implementer task and needs to confirm it is genuinely green — runs the runner→judge inner loop (baseline + task-specific verification) and loops fixer→re-verify until the evidence passes, then reports inner-loop-green.
---

# se-verify

se-verify is the **inner verification loop** invoked by se-exec after an implementer subagent completes a task. It operates a strict runner→judge cycle: a cheap runner subagent executes verification in its own throwaway context, a strong judge evaluates the returned evidence, and — if the judge finds anything short of green — a fixer subagent addresses the specific failure before the cycle repeats. The loop continues until the judge passes, with shown evidence, at which point the skill reports **inner-loop-green**. If the judge determines a failure is an implementation limitation (the spec is unachievable as written — not a fixable bug), the verifier reports **limitation-blocked** to se-exec instead of looping the fixer.

**Checkpoint definition:** *inner-loop-green = the baseline AND the task-specific verification both pass, with the runner's actual evidence shown and the judge's explicit pass rendered.*

No task is ever reported complete on the strength of what the implementer said, what the code looks like, or what "should" be true. Evidence or nothing.

---

## Mandatory Ordered Checklist

Complete every item in order. Do not skip or reorder steps. Do not advance past a step until it is confirmed done.

- [ ] **1. Receive the task context**
- [ ] **2. Dispatch the runner subagent**
- [ ] **3. Collect the runner's evidence**
- [ ] **4. Dispatch the judge subagent**
- [ ] **5. If FAIL — dispatch the fixer subagent**
- [ ] **6. If LIMITATION — report limitation-blocked**
- [ ] **7. Report inner-loop-green**

---

## 1. Receive the task context

Confirm you have in hand: (a) the task description from the plan, (b) the plan's **verification design** — specifically the recorded baseline commands (e.g. `lint:fix` + `type-check`, or `dotnet build`) and the task-specific verification method (test suite, browser check, endpoint call, or custom script). If either is missing, halt and ask se-exec to supply them before proceeding.

## 2. Dispatch the runner subagent

See the `se-subagent` skill for the concrete model and dispatch details. Dispatch the subagent with the `Task` tool. Give the runner:

- The exact baseline commands from the plan's verification design. Run them first.
- The task-specific verification commands or steps from the plan's verification design. Run them second.
- For any playwright, e2e, or browser verification, the runner must first scan local repo skills (`.claude/skills/*/SKILL.md`, `.cursor/skills/*/SKILL.md`, `plugin/skills/*/SKILL.md`, or the harness's native skill-discovery output) for `local-dev-server`, `dev-server`, or equivalent instructions, then follow that skill before the browser/e2e command. If no dev-server skill exists, use the fallback dev-server command recorded in the plan. If neither exists, return structured evidence that no dev-server startup path exists and do not run browser/e2e against nothing. The runner must start or confirm the local dev server, wait for readiness (URL/port/log line), record server evidence (command or skill, URL, PID when started), run the browser/e2e check against that server, and tear down any server it started.
- An instruction to return **structured EVIDENCE only**: exit codes, pass/fail counts, relevant log excerpts, and — for UI tasks — screenshot file paths or DOM assertion results. No interpretation. No "it looks fine." Raw output is never echoed into the controller's context.

**The runner executes. The controller never runs verification inline. Ever.**

## 3. Collect the runner's evidence

Wait for the runner to return. Accept only structured EVIDENCE — exit codes, counts, relevant log lines, file paths. If the runner returns an interpretation ("it passed") without hard evidence, reject it and re-dispatch the runner with an explicit instruction to include exit codes and output excerpts.

## 4. Dispatch the judge subagent

See the `se-subagent` skill for the concrete model. Dispatch the subagent with the `Task` tool. Supply the judge with:

- The task description from the plan.
- The acceptance criteria from the spec.
- The plan's verification design (what "pass" looks like for baseline and task-specific).
- The runner's evidence in full.

Ask the judge one question: **does the evidence demonstrate that the baseline and the task-specific verification both pass, as required by the spec and plan?** The judge must render an explicit **PASS**, **FAIL**, or **LIMITATION** — not a hedge.

- **PASS**: evidence is green; proceed to step 7.
- **FAIL**: findings must be specific — which command failed, what the output showed, what must be fixed. Proceed to step 5.
- **LIMITATION**: the spec is unachievable as written (not a fixable bug — an architectural or environmental constraint makes it impossible). Missing dev-server startup instructions for required browser/e2e verification count as LIMITATION unless the evidence already identifies a concrete command the fixer can add safely. The judge must state clearly why the failure cannot be fixed by the fixer. Proceed to step 6 (limitation-blocked path).

**The runner runs; the judge decides. These are distinct roles and must never be collapsed into a single agent.**

## 5. If FAIL — dispatch the fixer subagent

See the `se-subagent` skill. Dispatch the subagent with the `Task` tool. Give the fixer:

- The judge's specific failure finding(s) — not the full context, just what is broken and what the evidence showed.
- The relevant task description and acceptance criteria.

The fixer must not gold-plate, scope-creep, or rewrite unrelated code. It addresses the specific failure only.

**Before re-dispatching the fixer**, confirm the judge's finding describes a fixable bug — not an implementation limitation. If the judge's FAIL finding indicates the spec is structurally unachievable, treat it as a LIMITATION and proceed to step 6 instead.

After the fixer completes — return to step 2. Re-dispatch the runner. Re-collect evidence. Re-dispatch the judge. Repeat the loop until the judge renders an explicit PASS or LIMITATION.

## 6. If LIMITATION — report limitation-blocked

Do not dispatch the fixer. Report **limitation-blocked** to se-exec. Include in the report: the task name, the judge's specific finding (why the spec is unachievable as written), and the evidence the runner returned. se-exec owns the limitation-escalation decision tree — workaround, amend spec to closest-achievable, or ask the human. The verifier's role ends here.

## 7. Report inner-loop-green

Only when the judge has rendered an explicit PASS with the runner's evidence in hand, report: **inner-loop-green**. Include in the report: the task name, the baseline evidence summary (exit codes or counts), the task-specific evidence summary, and the judge's pass statement. This report is the only acceptable signal to se-exec that the task is verified.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "I'll just run the tests here in the controller." | Execute lint, build, tests, or any verification command inline in the primary context. | Never. All execution must be dispatched to the RUNNER subagent in its own throwaway context. The controller dispatches, waits, and reads the returned evidence. |
| "The implementer said it works." | Accept the implementer's word and skip verification. | Require the runner's evidence. The implementer's claim is not evidence. Trust nothing; verify everything. |
| "It should render fine / compile cleanly — let's move on." | Skip or abbreviate verification for UI or build tasks based on static reasoning. | UI tasks require real-browser evidence — a screenshot or DOM assertion from playwright against the repo dev-server, not "it should render." Compile tasks require the build exit code and output. |
| "I'll run playwright/e2e directly." | Launch browser/e2e tests without checking local dev-server instructions or proving the app is running | First scan local repo skills for the dev-server skill, or use the plan's fallback command. Start or confirm the local server, wait for readiness, then run playwright/e2e. Return server evidence plus browser evidence. |
| "Close enough — mark it done." | Report inner-loop-green before the judge has rendered an explicit PASS. | No done-claim without the judge's explicit PASS and the runner's shown evidence. "Close enough" is not a pass. |
| "The runner and judge can be the same cheap agent — it's faster." | Use the script-runner tier model for judgment, or fold both roles into one subagent. | The judge is the strong non-fast tier. The roles are separate by design: the runner reports facts; the judge reasons about correctness against spec + plan. Never collapse them. |
| "I'll skip the baseline — it passed last time." | Run only task-specific verification and skip the baseline suite. | The baseline runs on every cycle, without exception. A previous pass does not exempt the current cycle — the fixer may have introduced a regression. |
| "The judge said PASS, but I'll skip showing the evidence." | Report inner-loop-green without including the evidence summary in the report. | The evidence must be shown in the report. A PASS without evidence is not an inner-loop-green report. |
| "I'll fold the fixer feedback into the runner prompt." | Tell the runner what to fix and then verify in the same pass. | Fixer and runner are separate subagents with separate dispatches. The fixer fixes; then the runner verifies from scratch; then the judge evaluates. Never mix the roles. |
| "Re-dispatching the fixer on a failure that is an unfixable implementation limitation." | Loop the fixer indefinitely on a spec that cannot be satisfied as written. | Stop the loop and report `limitation-blocked` to se-exec. Only se-exec's limitation tree resolves it (workaround, amend spec to closest-achievable, or ask the human). |

---

## Model and Tool Assignments

Resolve all concrete model IDs and dispatch details from the `se-subagent` skill.

| Role | Prose alias | Reference |
|---|---|---|
| Runner | cheap / script-runner tier | `se-subagent` skill → "Script-runner" row |
| Judge / Verifier | strong non-fast tier | `se-subagent` skill → "Discuss interview · Plan · Review · verifier judgment" row |
| Fixer | implementer / mid tier (PINNED to `sonnet` on CC) | `se-subagent` skill → "Implementer · Fixer" row and pinned-to-sonnet policy |
| Subagent dispatch | `Task` tool | `se-subagent` skill → "Subagent Dispatch" section |

**UI verification:** when the plan's verification design specifies browser-based evidence, the runner uses playwright/e2e via the repo dev-server skill, or the plan's fallback dev-server command when no skill exists. The runner must scan local repo skills before running the browser command, start or confirm the local dev server, wait for readiness, then return server evidence plus a screenshot path or DOM assertion result. If no dev-server skill or fallback command exists, the runner returns structured missing-dev-server evidence instead of pretending browser evidence exists. "It should render" from a static analysis is not browser evidence.
