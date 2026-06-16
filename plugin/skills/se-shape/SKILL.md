---
name: se-shape
description: Use this BEFORE any feature work — creating a feature, building a component, adding functionality, or changing/modifying behavior — to reach a shared spec (the WHAT) through a focused interview before any planning or code. Triggers on "let's build/add/create X", "I want a feature that…", "change how Y works", "can we make it do Z". The entry point of the super-exec spec→plan→build workflow; invoke it whenever the user describes something to build or change, even if they never say "spec".
---

# se-shape — Shape Phase

se-shape drives the **Shape (spec)** phase of the super-exec gate-driven workflow. It conducts a relentless, structured interview to reach shared understanding of the **WHAT**, then produces or updates a committed spec in `docs/specs/`. It is **WHAT-only**: every HOW/architecture/design decision is deferred to se-plan.

> **Reference paths:** every `references/*.md` cited below lives at the plugin root — read it as `${CLAUDE_PLUGIN_ROOT}/references/<file>` on Claude Code, or `${CURSOR_PLUGIN_ROOT}/references/<file>` on Cursor.

Use a **strong non-fast model** (see `references/model-tiers.md`, "Shape interview" row) for the interview and judgment. Dispatch **finder subagents** (cheap / investigator tier) for all codebase research. For harness-specific tool names, resolve against `references/tool-map.md`.

> **Concise communication (optional):** if a `caveman` skill / `/caveman` command is available, activate it (e.g. `caveman lite`) at the start so the interview stays terse and high-signal — it compresses phrasing while preserving all technical substance and auto-relaxes for security warnings and multi-step sequences. If absent, proceed normally: this is a graceful detect-and-skip optional with **no hard dependency** (the same posture as impeccable). Never install anything.

---

## Session activation (do this FIRST, before the checklist)

Invoking this skill — whether the user typed `/se-shape` or the model auto-invoked it to start
shaping a feature — **means a super-exec design session is starting**. As the very first action,
**write the session marker** `.super-exec/active` in the repo root (create `.super-exec/` if
needed); a small payload is enough, e.g. `phase: shape` and `started: <current UTC ISO-8601>`.
Existence + mtime are what the hooks read; the stale-marker decision is a model-judged heuristic
with no fixed TTL. **Do not commit it** — `.super-exec/` is gitignored (the branch gate ensures
this). This is the only side-effect at entry; behavior is identical for manual and auto invocation.

If invoked with an argument (a ticket id and/or short description), use it to seed the interview —
still confirm and grill; never assume.

---

## Mandatory Ordered Checklist

Work through every item in order. Do NOT skip any item, even for simple work.

- [ ] **1. Branch / ticket gate** — Load `references/branch-gate.md` (at the plugin root — see the reference-path note above) and follow it to completion. Do not duplicate or paraphrase its logic — read and apply it. Do not proceed past this step until the branch gate is satisfied (correct feature branch + `.gitignore` tidy).
- [ ] **2. Explore project context via subagents** — Dispatch finder subagents to research: existing domain terms in `CONTEXT.md` (or `CONTEXT-MAP.md` for multi-context repos), related specs in `docs/specs/`, relevant source files, naming conventions, and any code that touches the area of work. Do NOT ask the user for anything that can be discovered by reading the codebase.
- [ ] **3. New-vs-update detection** — Glob `docs/specs/` (and `docs/specs/<app>/` in monorepos). Match an existing spec by ticket key AND feature name. Confirm with the user: "I found `docs/specs/INTCOMP-123-payment-retry.md` — is this an update to that spec, or a new one?" An **update** interviews only the **delta**; do not re-interview the whole spec.
- [ ] **4. Relentless WHAT-only interview** — Ask one question at a time. Wait for the answer before the next. Walk every branch of the decision tree. For each question, provide your recommended answer. Prefer multiple-choice options when the answer space is bounded. If a question can be answered by exploring the codebase, dispatch a finder subagent instead of asking. Never ask about HOW — defer all implementation, architecture, and file-layout questions to se-plan.
- [ ] **5. Term-sharpening** — When the user uses a vague or overloaded term, propose a precise canonical term immediately ("you said 'account' — do you mean Customer or User per our glossary?"). When a term conflicts with an existing `CONTEXT.md` entry, call it out and resolve it before continuing. Stress-test domain relationships with concrete scenarios ("so when a User has two active Memberships, which one gets the retry?").
- [ ] **6. Derive the feature slug** — Produce a ≤6-word, lowercase-kebab summary of the **work itself** (e.g., `payment-retry-on-soft-decline`). The slug is NEVER the repo basename, the `package.json` `name`, or the app/project name. It is derived from the feature being shaped.
- [ ] **7. Collision gate (CRITICAL)** — Before writing the spec file, compare the candidate slug against the repo basename AND the `package.json` `name` field. On a match, **HALT** and confirm the real feature with the user. Do not silently name a spec after the project.
- [ ] **8. Write / update the spec to the template** — Write `docs/specs/<feature>.md` (or `docs/specs/<app>/<feature>.md` in monorepos) using the exact spec template below. For an update, edit only the sections affected by the delta.
- [ ] **9. Update `CONTEXT.md` with new terms (lazy)** — If the interview resolved new domain terms, add them to `CONTEXT.md`. Create the file only when the first term worth recording is identified; the file is a glossary only — no implementation details. If `CONTEXT-MAP.md` exists, resolve into the correct bounded context.
- [ ] **10. Offer ADR (3-criteria gate)** — Offer to write an ADR only when ALL THREE hold: (a) the decision is hard to reverse, AND (b) it would be surprising without context, AND (c) it resulted from a real trade-off between alternatives. If any criterion fails, skip the ADR. ADRs live at `docs/adr/NNNN-<slug>.md`.
- [ ] **11. Spec self-review** — Before presenting the spec to the user, scan it for: placeholders (TBD / TODO / "to be determined"), internal contradictions, scope creep (any HOW that snuck in), and ambiguity (any requirement readable two ways). Fix inline. A requirement readable two ways must be made explicit — pick one reading and state it.
- [ ] **12. Docs gate — handoff** — Present the finalized spec for user review. Recommend a commit with type `docs`. Tell the user: "Review the spec, then commit with `docs:`. When ready, run `/se-plan` to enter the planning phase." **NEVER auto-commit. NEVER auto-invoke se-plan.** se-shape stops at this gate.

---

## Spec Template

Write the spec file using exactly this structure. Sections must appear in this order. No additional sections.

```markdown
# <Feature>
> Ticket: INTCOMP-####  ·  Status: active

## Problem / Why

## Goals

## Non-goals (out of scope)

## Behavior / Requirements
<!-- Acceptance criteria only. No HOW — no architecture, no file layout, no tech choices. -->

## Domain terms
<!-- Entries here are mirrored to CONTEXT.md -->

## Decisions
<!-- Hard, surprising, trade-off decisions only. Others go to ADRs in docs/adr/. -->
```

The **Behavior / Requirements** section contains acceptance criteria with NO HOW. If a requirement implies an implementation (e.g., "use a queue"), extract the underlying behavior ("retries must be durable across process restarts") and state that instead. Architecture and implementation details belong to se-plan.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "This is too simple to shape" | Skip the interview and go straight to planning | Everything gets shaped. The spec can be short — one acceptance criterion is a valid spec. Run the full checklist. |
| "I'll ask the user what I could look up" | Ask the user about directory structure, existing patterns, domain terms, existing specs | Dispatch a finder subagent. Research the codebase. Ask only what is not discoverable. |
| "I'll add an architecture section" | Add tech choices, file layout, data model, or system design to the spec | WHAT-only. Move all HOW to a note for se-plan. Remove it from the spec. |
| "I'll name the spec after the repo" | Set the slug to the repo name, `package.json` `name`, or app name | Derive the slug from the feature being built. Collision gate halts on a match. |
| "I'll commit the spec for them" | Auto-commit the spec file | Never auto-commit. Present the spec, recommend `docs:` commit type, stop at the gate. |
| "I'll jump straight into planning" | Invoke se-plan or start implementation discussion | Hand off at the docs gate. Tell the user to run `/se-plan` after reviewing and committing. |
| "I'll ask multiple questions at once" | Present a list of questions | One question at a time. Wait for the answer. Provide your recommended answer with each question. |
| "I'll add a visual or mockup" | Describe UI layout or generate wireframe-style requirements | UI design direction belongs to se-plan. State functional behavior only. |
| "I know the branch is fine, I'll skip the branch gate" | Proceed without running the branch gate | Load and follow `references/branch-gate.md` first. Always. No exceptions. |
| "I'll write the CONTEXT.md eagerly" | Create CONTEXT.md before any term is worth recording | Lazy creation only. Create the file when the first canonical term resolves. Glossary entries only. |

---

## Interview Discipline

**One question at a time.** After every answer, decide the next most important unresolved question. Never batch questions.

**Provide your recommended answer.** For every question, state what you believe the answer is and why, then ask the user to confirm or correct. This anchors the conversation and surfaces hidden assumptions.

**Multiple-choice when bounded.** When the answer space is known, enumerate options. Example: "Should this gate apply to (a) all Membership types, (b) only paid tiers, or (c) configurable per tier? I'd recommend (b) based on the existing retry logic in `payments/retry.ts`."

**Research before asking.** Before asking any question about the codebase — existing behavior, naming conventions, related specs — dispatch a finder subagent to look it up. Do not ask the user what you can discover yourself.

**Stress-test with scenarios.** After the requirements stabilize, probe edge cases with concrete examples: "So when a Customer has no active Membership at retry time, the requirement says the retry fails silently — is that correct, or should it surface to the user?" Ambiguous requirements surface here, not in implementation.

**Cross-reference the code.** If the user states how something currently works, verify it with a finder subagent. Surface contradictions immediately: "You said the retry runs synchronously — I found `payments/retry.ts:47` which shows it enqueues to SQS. Which is the intended behavior going forward?"

---

## Term-Sharpening Rules

1. When the user uses a term that appears in `CONTEXT.md`, echo back the canonical definition and confirm alignment.
2. When the user uses a term NOT in `CONTEXT.md` but that has a natural canonical form in the domain, propose it: "You said 'user' — should we canonicalize this as `Customer` (the authenticated entity) or `User` (the internal admin persona)?"
3. When a term is used in two different senses across the interview, flag it immediately: "You used 'account' to mean both the EWA balance and the bank account. I'll call these `WageAdvanceBalance` and `LinkedBankAccount` to disambiguate — confirm?"
4. Add resolved terms to `CONTEXT.md` (lazy). Format: `**Term** — definition.`
5. If `CONTEXT-MAP.md` exists, the repo has multiple bounded contexts. Identify which context the feature lives in before shaping, and use that context's `CONTEXT.md`.

---

## ADR 3-Criteria Gate

Offer an ADR only when ALL THREE apply:

1. **Hard to reverse** — undoing this decision requires significant rework.
2. **Surprising without context** — a future developer reading the spec or code would wonder why this choice was made.
3. **Real trade-off** — there were at least two viable alternatives and a reason to prefer this one.

If any criterion fails, skip the ADR. Document the decision in the spec's **Decisions** section instead.

ADR file path: `docs/adr/NNNN-<slug>.md` where `NNNN` is the next available number (find the highest existing number and increment).

---

## Model and Tool Assignments

| Role | Claude Code | Cursor |
|---|---|---|
| Interview + judgment (this skill) | Strong non-fast (Opus) — see `references/model-tiers.md` | Default / inherit (non-fast) |
| Codebase finder subagents | Cheap investigator (Haiku) — see `references/model-tiers.md` | Composer non-fast |

Resolve concrete model names from `references/model-tiers.md`. Resolve tool names (Read, Edit, Write, subagent dispatch) from `references/tool-map.md`.
