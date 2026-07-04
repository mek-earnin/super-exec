---
name: se-discuss
description: Use this BEFORE any feature work — creating a feature, building a component, adding functionality, or changing/modifying behavior — to reach a shared spec (the WHAT) through a focused interview before any planning or code. Triggers on "let's build/add/create X", "I want a feature that…", "change how Y works", "can we make it do Z". The entry point of the super-exec spec→plan→build workflow; invoke it whenever the user describes something to build or change, even if they never say "spec".
---

# se-discuss — Discuss Phase

se-discuss drives the **Discuss (spec)** phase of the super-exec gate-driven workflow. It conducts a relentless, structured interview to reach shared understanding of the **WHAT**, then produces or updates one or more committed specs in `docs/specs/` — **one spec per cohesive feature**. When a single session covers several distinct features (a new app described by its feature set, or a broad request that bundles unrelated capabilities), it proposes a split so each feature gets its own spec (see the Feature-split gate). It is **WHAT-only**: every HOW/architecture/design decision is deferred to se-plan.

Use a **strong non-fast model** (`opus` — see the `se-subagent` skill for tier details, "Discuss interview" row) for the interview and judgment. Dispatch **finder subagents** (cheap / investigator tier, `haiku`) for all codebase research using the `Task` tool.

> **Concise communication (optional):** if a `caveman` skill / `/caveman` command is available, activate it (e.g. `caveman lite`) at the start so the interview stays terse and high-signal — it compresses phrasing while preserving all technical substance and auto-relaxes for security warnings and multi-step sequences. If absent, proceed normally: this is a graceful detect-and-skip optional with **no hard dependency** (the same posture as impeccable). Never install anything.

---

## Session activation (do this FIRST, before the checklist)

Invoking this skill — whether the user typed `/se-discuss` or the model auto-invoked it to start
discussing a feature — **means a super-exec design session is starting**. As the very first action,
**write the session marker** `.super-exec/active` in the repo root (create `.super-exec/` if
needed); a small payload is enough, e.g. `phase: discuss` and `started: <current UTC ISO-8601>`.
Use the `Write` tool for this. Existence + mtime are what the hooks read; the stale-marker
decision is a model-judged heuristic with no fixed TTL. **Immediately after writing the marker,
invoke `/se-local-ignore`.** These are the only side-effects at entry; behavior is identical for
manual and auto invocation.

If invoked with an argument (a ticket id and/or short description), use it to seed the interview —
still confirm and grill; never assume.

---

## Mandatory Ordered Checklist

Work through every item in order. Do NOT skip any item, even for simple work.

- [ ] **1. Start branch context warm-up (non-blocking)**
- [ ] **2. Explore project context via subagents**
- [ ] **3. New-vs-update detection**
- [ ] **4. Relentless WHAT-only interview**
- [ ] **5. Term-sharpening**
- [ ] **6. Feature-split gate + derive feature slug(s)**
- [ ] **7. Collision gate (CRITICAL)**
- [ ] **8. Ticket + branch confirmation**
- [ ] **9. Write / update the spec file(s) to the template**
- [ ] **10. Write deferred glossary / ADR review artifacts**
- [ ] **11. Spec self-review**
- [ ] **12. Spec-approval gate, then branch + commit + chain to se-plan**

---

## 1. Start branch context warm-up (non-blocking)

Read [@./branch-gate.md](./branch-gate.md) and start only its **Phase A: read-only warm-up**. This runs [@./branch-context](./branch-context) in the background when the harness supports background shell work. Do NOT wait for Atlassian MCP or git branch sampling before asking the first interview question. Do NOT create or switch branches here.

## 2. Explore project context via subagents

Dispatch finder subagents (via the `Task` tool) to research: existing domain terms in `CONTEXT.md` (or `CONTEXT-MAP.md` for multi-context repos), related specs in `docs/specs/`, relevant source files, naming conventions, and any code that touches the area of work. Use `Read`, `Bash`, and `Grep` inside these subagents. Do NOT ask the user for anything that can be discovered by reading the codebase.

## 3. New-vs-update detection

Glob `docs/specs/` (and `docs/specs/<app>/` in monorepos). Match an existing spec by ticket key in the header AND by the feature slug after the numeric prefix. Confirm with the user via `AskUserQuestion`: "I found `docs/specs/0007-payment-retry.md` — is this an update to that spec, or a new one?" An **update** interviews only the **delta**; do not re-interview the whole spec.

## 4. Relentless WHAT-only interview

Ask one question at a time using `AskUserQuestion`. Wait for the answer before the next. Walk every branch of the decision tree. For each question, provide your recommended answer. Prefer multiple-choice options when the answer space is bounded. If a question can be answered by exploring the codebase, dispatch a finder subagent (via `Task`) instead of asking. Never ask about HOW — defer all implementation, architecture, and file-layout questions to se-plan.

## 5. Term-sharpening

When the user uses a vague or overloaded term, propose a precise canonical term immediately ("you said 'account' — do you mean Customer or User per our glossary?"). When a term conflicts with an existing `CONTEXT.md` entry, call it out and resolve it before continuing. Stress-test domain relationships with concrete scenarios ("so when a User has two active Memberships, which one gets the retry?").

## 6. Feature-split gate + derive feature slug(s)

After the interview, decide whether it covered **one** cohesive feature or **several** distinct ones.

**Cohesion rule (what counts as one feature).** A spec is a blueprint of intention, not a PR. Group capabilities that share a single design intention and are tightly coupled into **one** feature — `login` + `logout` + `session-refresh` are one `auth` spec because they cannot be designed with separate architectures. Split capabilities that are independent into **separate** features — `auth`, `profile`, `activity-feed` are three specs. One spec may later spawn many plans; the spec boundary is cohesion, never PR size.

**Split gate (never split silently).** When the interview revealed multiple cohesive, independent features, propose the breakdown via `AskUserQuestion` before writing anything. Present the proposed specs numbered in foundational/dependency order — e.g. "This looks like several features. Break into `0001 auth`, `0002 profile`, `0003 activity-feed`?" — with options: **A** = yes, split as proposed; **B** = no, keep everything in one spec; **C** = other (free text to re-group or rename). If the user picks **B**, or the interview covered a single feature, proceed as a single spec exactly as before.

**Derive slug(s).** For each resulting feature, produce a ≤6-word, lowercase-kebab summary of the **work itself** (e.g., `payment-retry-on-soft-decline`). A slug is NEVER the repo basename, the `package.json` `name`, or the app/project name — it is derived from the feature. Note any real cross-feature dependency now (recorded in step 9 as a `Depends on` line). In a multi-feature split, matching a proposed feature to an existing spec makes that one an **update** (step 3); only the genuinely-new features get new specs.

## 7. Collision gate (CRITICAL)

Before writing any spec file, compare EACH candidate slug against the repo basename AND the `package.json` `name` field. On a match, **HALT** and confirm the real feature with the user via `AskUserQuestion`. Do not silently name a spec after the project. (In a multi-feature split each feature is named after itself, which naturally avoids the app-name collision — but still check every slug.)

## 8. Ticket + branch confirmation

Complete [@./branch-gate.md](./branch-gate.md) **Phase B: ticket + branch confirmation** after the last WHAT question. If no ticket was provided or inferred, ask once: "Do you have a Jira ticket for this task?" If Atlassian MCP is available and a ticket is known, use it to fetch the ticket title/description and derive the branch name.

- **Single spec** → present the ticket value (`NO_TICKET` if none) and proposed branch name once; accept edits now. This is the only normal branch-name question.
- **Multi-feature split** → resolve the ticket now (so the spec headers can be written in step 9), but **defer the branch-name confirmation to step 12**. The first branch is named after the feature the user chooses to plan first (picked at the approval gate), and that single branch carries all the specs. One ticket seeds every split spec header by default; if the batch genuinely spans multiple tickets, edit the per-feature `Ticket:` values into the individual spec headers before approval.

## 9. Write / update the spec file(s) to the template

Write `docs/specs/NNNN-<feature>.md` (or `docs/specs/<app>/NNNN-<feature>.md` in monorepos) using the `Write` or `Edit` tool, following [spec-template.md](./spec-template.md). The template file is copy-pasteable markdown only: it starts directly with the final artifact shape, has no outer explanatory heading/prose, has no instructional comments, and has no fenced code-block wrapper. Sections must appear in the template order with no additional sections. Replace header placeholders; use `NO_TICKET` only when the user confirms there is no Jira ticket, and set `Status:` to `active` for the current approved spec (`draft` only for an intentionally unapproved spec, `superseded` only for a replaced one). `NNNN` is the next available number in that directory (find the highest existing four-digit prefix and increment). For an update, keep the existing number and edit only the sections affected by the delta. The **Behavior / Requirements** section contains acceptance criteria with NO HOW; if a requirement implies an implementation (for example, "use a queue"), extract the underlying behavior ("retries must be durable across process restarts") and state that instead. Architecture and implementation details belong to se-plan. The **Domain terms** section contains entries mirrored to `CONTEXT.md` when new canonical terms were resolved. The **Decisions** section contains only hard, surprising, trade-off decisions; broader architecture decisions that meet the ADR gate go to `docs/adr/`. This uncommitted file is the review artifact; do NOT commit it before approval.

**Multi-feature split.** Write one spec file per feature, numbering them sequentially from the next available prefix in **dependency order** (0001 = most foundational; a dependency always gets a lower number than the feature that needs it). Every spec uses the same template independently (its own Problem / Goals / Behavior). When a feature genuinely depends on a sibling (e.g. `activity-feed` needs `auth`), record it in the header's optional `Depends on:` line — set it to `none` when there is no dependency. Shared domain terms resolved during the interview are written once to `CONTEXT.md` (step 10), not duplicated per spec. All spec files are uncommitted review artifacts until the batch approval in step 12.

## 10. Write deferred glossary / ADR review artifacts

If the interview resolved new domain terms, add the intended `CONTEXT.md` edits now so the user can review them with the spec; create the file (via `Write`) only when the first term worth recording is identified. Offer an ADR only when ALL THREE hold: (a) the decision is hard to reverse, AND (b) it would be surprising without context, AND (c) it resulted from a real trade-off between alternatives. ADRs live at `docs/adr/NNNN-<slug>.md`; write them before approval only when offered and accepted so they are reviewable. Do NOT commit any of these files before approval.

## 11. Spec self-review

Before presenting to the user, scan EVERY written spec for: placeholders (TBD / TODO / "to be determined"), internal contradictions, scope creep (any HOW that snuck in), **any code (fenced code blocks, file layout, scaffolding — the spec is WHAT-only)**, and ambiguity (any requirement readable two ways). Fix inline using `Edit`. Move any code/HOW to a note for se-plan and remove it from the spec. A requirement readable two ways must be made explicit — pick one reading and state it.

For a multi-feature split, additionally check: each spec is cohesive (no unrelated capabilities crammed together, no tightly-coupled capability split across two specs), the numbering reflects dependency order, and every `Depends on` reference points to a real sibling spec.

## 12. Spec-approval gate, then branch + commit + chain to se-plan

### Single spec

Present the finalized spec and ask via `AskUserQuestion`: **"Everything look good? Proceed to planning?"**

- **Change requested** → fix the written files using `Edit`, re-present, ask again via `AskUserQuestion`. Loop until the user explicitly approves (e.g. "looks good" / "yes" / "approve").
- **On approval** → complete [@./branch-gate.md](./branch-gate.md) **Phase C: create/switch confirmed branch**, then **commit the already-written approved artifacts** via **`/se-commit`**, passing the paths this approval touched (the spec + any ADR / `CONTEXT.md` file). **UNLESS** the user asked not to commit, or `docs/specs/` is gitignored (in either case, skip the commit and say so). The user's approval IS the authorization to create/switch to the already-confirmed branch and commit. Before approval, keep review artifacts uncommitted; after approval, commit only the approved paths. If branch switching conflicts with the approved uncommitted files, stop and ask rather than stashing, discarding, or rewriting them.
- **Then auto-invoke `/se-plan`** to continue the design session — the user does NOT type `/se-plan`. The discuss→plan transition is automatic; only the later plan→execute transition is a hard fresh-session boundary.

### Multi-feature split

1. **Batch approval.** Present ALL spec files together and ask ONE approval via `AskUserQuestion`: **"Everything look good across all specs? Proceed to planning?"** A change request loops back to editing any spec with `Edit` and re-presenting the set; repeat until the user approves the whole batch.
2. **Which to plan first.** On approval, ask via `AskUserQuestion` which spec to plan first (default the lowest-numbered, `0001`).
3. **Branch.** Confirm the first branch name for that chosen feature ([@./branch-gate.md](./branch-gate.md) **Phase B** naming, deferred from step 8), then run **Phase C: create/switch** it. This single branch carries all the specs.
4. **Single commit.** Commit ALL spec files plus any shared `CONTEXT.md` / ADR in ONE commit via **`/se-commit`** (e.g. `docs: add initial specs for <app>`), passing every spec path. **UNLESS** the user asked not to commit, or `docs/specs/` is gitignored (skip and say so). The first PR will therefore carry the first feature's implementation plus all specs.
5. **Chain the first feature only.** Auto-invoke `/se-plan <first-chosen spec slug or path>` — **pass the chosen spec explicitly** so se-plan plans the right one, not an arbitrary spec from the batch. Do NOT chain the others. Tell the user the remaining specs (list them by number/slug) are planned one at a time later: in a fresh session `/se-plan` auto-discovers the next unplanned spec by number (see se-plan). Only the first feature is planned in this session.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "This is too simple to discuss" | Skip the interview and go straight to planning | Everything gets discussed. The spec can be short — one acceptance criterion is a valid spec. Run the full checklist. |
| "I'll ask the user what I could look up" | Ask the user about directory structure, existing patterns, domain terms, existing specs | Dispatch a finder subagent via `Task`. Research the codebase. Ask only what is not discoverable. |
| "I'll add an architecture section" | Add tech choices, file layout, data model, or system design to the spec | WHAT-only. Move all HOW to a note for se-plan. Remove it from the spec. |
| "I'll name the spec after the repo" | Set the slug to the repo name, `package.json` `name`, or app name | Derive the slug from the feature being built. Collision gate halts on a match. |
| "This app has many features, I'll write one big spec" | Cram several independent features into a single spec because they came from one conversation | If the interview covered multiple cohesive, independent features, fire the Feature-split gate and propose one spec per feature. Cohesion (shared design intention), not conversation count, sets the boundary. |
| "It's clearly multiple features, I'll just split it" | Silently write N spec files without asking | Never split silently. Propose the numbered breakdown via `AskUserQuestion` (A = split / B = one spec / C = edit). The user can always choose one spec. |
| "I'll auto-chain se-plan for every spec I wrote" | Chain into planning for all N specs at once | Chain only the first-chosen feature. The rest are picked up later by `/se-plan` auto-discovery (next unplanned spec by number), one at a time. |
| "I'll put each split spec on its own branch / on base" | Commit the split specs across N branches, or on the base branch | All specs commit together in ONE commit on the first-chosen feature's branch. That branch carries every spec; the first PR includes them all. Features 2..N get their own branch later, created by se-plan. |
| "I'll commit the spec before they've approved it" | Commit the spec while changes are still under review or before the user says "looks good" | Commit only AFTER explicit approval. Run the review/fix loop (via `AskUserQuestion`) first; on approval, commit via `/se-commit` — unless the user declined or `docs/specs/` is gitignored. Never commit before approval or mid-change. |
| "I'll stop and make them type `/se-plan`" | Hand off at the gate and wait for a manual `/se-plan` invocation | After the spec is approved (and committed), **auto-invoke `/se-plan`** in the same session. The user never types `/se-plan`. Only the plan→execute boundary stays a manual fresh-session step. |
| "I'll ask multiple questions at once" | Present a list of questions | One question at a time via `AskUserQuestion`. Wait for the answer. Provide your recommended answer with each question. |
| "I'll add a visual or mockup" | Describe UI layout or generate wireframe-style requirements | UI design direction belongs to se-plan. State functional behavior only. |
| "I need the branch before I can interview" | Block the first user question on git/MCP/branch naming | Start the read-only branch-context warm-up in the background, then keep interviewing. Branch confirmation happens after the last WHAT question; branch creation happens only after spec approval. |
| "I already confirmed the branch, I'll ask again before committing" | Re-prompt for the same branch at approval time | Do not ask again unless branch creation fails, checkout conflicts, or facts changed. The earlier confirmation plus spec approval authorizes creating/switching to that branch and committing. |
| "I need approval before writing the spec file" | Ask the user to approve an in-memory summary with no file to review | Write the uncommitted `docs/specs/...` file first. Human approval reviews the actual file diff; only the commit waits. |
| "Uncommitted spec on the old branch is dangerous, I'll hide it in `.super-exec/`" | Keep the review artifact outside `docs/specs/` | The spec file itself is the review surface. Write it in `docs/specs/`, but do not commit until approval. |
| "I know the branch is fine, I'll skip the branch gate" | Proceed without running branch warm-up / confirmation / creation phases | Read and follow [@./branch-gate.md](./branch-gate.md). Warm up early, confirm late, create after approval. |
| "I'll write the CONTEXT.md eagerly" | Create CONTEXT.md before any term is worth recording | Lazy creation only. Create the file when the first canonical term resolves. Glossary entries only. |

---

## Interview Discipline

**One question at a time.** After every answer, decide the next most important unresolved question. Never batch questions. Use `AskUserQuestion` for every question posed to the user.

**Provide your recommended answer.** For every question, state what you believe the answer is and why, then ask the user to confirm or correct. This anchors the conversation and surfaces hidden assumptions.

**Multiple-choice when bounded.** When the answer space is known, enumerate options. Example: "Should this gate apply to (a) all Membership types, (b) only paid tiers, or (c) configurable per tier? I'd recommend (b) based on the existing retry logic in `payments/retry.ts`."

**Research before asking.** Before asking any question about the codebase — existing behavior, naming conventions, related specs — dispatch a finder subagent via `Task` to look it up. Do not ask the user what you can discover yourself.

**Stress-test with scenarios.** After the requirements stabilize, probe edge cases with concrete examples: "So when a Customer has no active Membership at retry time, the requirement says the retry fails silently — is that correct, or should it surface to the user?" Ambiguous requirements surface here, not in implementation.

**Cross-reference the code.** If the user states how something currently works, verify it with a finder subagent. Surface contradictions immediately: "You said the retry runs synchronously — I found `payments/retry.ts:47` which shows it enqueues to SQS. Which is the intended behavior going forward?"

---

## Term-Sharpening Rules

1. When the user uses a term that appears in `CONTEXT.md`, echo back the canonical definition and confirm alignment.
2. When the user uses a term NOT in `CONTEXT.md` but that has a natural canonical form in the domain, propose it: "You said 'user' — should we canonicalize this as `Customer` (the authenticated entity) or `User` (the internal admin persona)?"
3. When a term is used in two different senses across the interview, flag it immediately: "You used 'account' to mean both the EWA balance and the bank account. I'll call these `WageAdvanceBalance` and `LinkedBankAccount` to disambiguate — confirm?"
4. Add resolved terms to `CONTEXT.md` (lazy) using `Edit` (or `Write` if the file doesn't exist yet). Format: `**Term** — definition.`
5. If `CONTEXT-MAP.md` exists, the repo has multiple bounded contexts. Identify which context the feature lives in before discussing, and use that context's `CONTEXT.md`.

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

| Role | Model | Dispatch |
|---|---|---|
| Interview + judgment (this skill) | Strong non-fast (`opus`) — see the `se-subagent` skill | N/A (this skill runs as the primary agent) |
| Codebase finder subagents | Cheap investigator (`haiku`) — see the `se-subagent` skill | `Task` tool |
