---
name: se-discuss
description: Use BEFORE any planning or code, when the user wants a new feature or a change to existing behavior — "let's build/add/create X", "I want a feature that…", "change how Y works", "can we make it do Z". Use even if the user never says "spec".
---

# se-discuss — Discuss Phase

Drives **Discuss (spec)** phase of super-exec workflow. Runs relentless, structured interview to reach shared understanding of **WHAT**, then writes a new spec under its `commitSpec`-resolved root or updates an existing spec at its discovered path — **one spec per cohesive feature**, splitting multi-feature sessions (see Feature-split gate, §6). **WHAT-only**: every HOW/architecture/design decision defers to /se-plan.

Dispatch **finder subagents** (cheap / investigator tier, `haiku` — see `/se-subagent` skill) for all codebase research via `Task` tool.

> **Concise communication (optional):** if `caveman` skill / `/caveman` command available, activate it (e.g. `caveman lite`) so interview stays terse while preserving all technical substance; auto-relaxes for security warnings + multi-step sequences. Graceful detect-and-skip — **no hard dependency** (same posture as impeccable). Never install anything.

---

## Session activation (do this FIRST, before the checklist)

As very first action, **write the session marker** `.super-exec/active` in repo root (create `.super-exec/` if needed); small payload enough, e.g. `phase: discuss` and `started: <current UTC ISO-8601>`. Use `Write` tool. Existence + mtime are what hooks read; stale-marker decision is a model-judged heuristic with no fixed TTL. **Immediately after writing the marker, invoke `/se-local-ignore`.** These are the only side-effects at entry; behavior identical for manual and auto invocation.

If invoked with an argument (ticket id and/or short description), use it to seed the interview — still confirm and grill; never assume.

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
- [ ] **12. Spec-approval gate, then branch + commit + chain to /se-plan**

---

## 1. Start branch context warm-up (non-blocking)

Read [@./branch-gate.md](./branch-gate.md) and start only its **Phase A: read-only warm-up**. Runs [@./branch-context](./branch-context) in background when harness supports it. Do NOT wait for Atlassian MCP or git branch sampling before asking the first interview question. Do NOT create or switch branches here.

## 2. Explore project context via subagents

Dispatch finder subagents (via `Task` tool) to research: existing domain terms in `CONTEXT.md` (or `CONTEXT-MAP.md` for multi-context repos), related specs under BOTH roots (`docs/specs/` and `.super-exec/specs/`, plus `<app>/` in monorepos), relevant source files, naming conventions, any code touching the area of work. Use `Read`, `Bash`, `Grep` inside these subagents. Do NOT ask user for anything discoverable by reading the codebase.

## 3. New-vs-update detection

Scan BOTH roots — `docs/specs/` AND `.super-exec/specs/` (and the `<app>/` sub-dir in monorepos). Match existing spec by ticket key in header AND by feature slug (slug-only identity; no numeric prefix). Confirm with user via `AskUserQuestion`: "I found `docs/specs/payment-retry/spec-payment-retry.md` — is this an update to that spec, or a new one?" An **update** interviews only the **delta**; do not re-interview the whole spec.

## 4. Relentless WHAT-only interview

Interview WHAT-only, one question at a time (via `AskUserQuestion`), walking every branch of decision tree. Never ask about HOW — defer all implementation, architecture, file-layout questions to /se-plan. Question mechanics (recommended answer, multiple-choice, research-before-asking, scenario stress-tests) in **Interview Discipline** below.

## 5. Term-sharpening

Propose precise canonical term whenever user uses vague or overloaded one; resolve any conflict with existing `CONTEXT.md` entry before continuing; stress-test domain relationships with concrete scenarios. Full procedure in **Term-Sharpening Rules** below.

## 6. Feature-split gate + derive feature slug(s)

After interview, decide whether it covered **one** cohesive feature or **several** distinct ones.

**Cohesion rule (what counts as one feature).** Spec is a blueprint of intention, not a PR. Group capabilities sharing single design intention and tightly coupled into **one** feature — `login` + `logout` + `session-refresh` are one `auth` spec because they cannot be designed with separate architectures. Split independent capabilities into **separate** features — `auth`, `profile`, `activity-feed` are three specs. One spec may later spawn many plans; spec boundary is cohesion, never PR size.

**Split gate (never split silently).** When interview revealed multiple cohesive, independent features, propose the breakdown via `AskUserQuestion` before writing anything. Present proposed feature slugs in foundational/dependency order — e.g. "This looks like several features. Break into `auth`, `profile`, `activity-feed`?" — with options: **A** = yes, split as proposed; **B** = no, keep everything in one spec; **C** = other (free text to re-group or rename). Dependency ORDER is conveyed later via each spec's `Depends on:` header, not by a number. If user picks **B**, or interview covered a single feature, proceed as a single spec exactly as before.

**Derive slug(s).** For each resulting feature, name the slug per `/se-slug-naming` (caveman-compressed): a ≤6-word, lowercase-kebab summary of the **work itself** (e.g., `payment-retry-soft-decline`). A slug is NEVER the repo basename, the `package.json` `name`, or the app/project name — derive it from the feature. Note any real cross-feature dependency now (recorded in step 9 as a `Depends on` line). In a multi-feature split, matching a proposed feature to an existing spec makes that one an **update** (step 3); only genuinely-new features get new specs.

## 7. Collision gate (CRITICAL)

Before writing any spec file, compare EACH candidate slug against repo basename AND `package.json` `name` field. On a match, **HALT** and confirm the real feature with user via `AskUserQuestion`. Do not silently name a spec after the project. (In a multi-feature split each feature is named after itself, which naturally avoids app-name collision — but still check every slug.)

## 8. Ticket + branch confirmation

Complete [@./branch-gate.md](./branch-gate.md) **Phase B: ticket + branch confirmation** after last WHAT question. If no ticket provided or inferred, ask once: "Do you have a Jira ticket for this task?" If Atlassian MCP available and ticket known, use it to fetch ticket title/description and derive branch name.

- **Single spec** → present ticket value (`NO_TICKET` if none) and proposed branch name once; accept edits now. Only normal branch-name question.
- **Multi-feature split** → resolve ticket now (so spec headers can be written in step 9), but **defer branch-name confirmation to step 12**. First branch is named after the feature user chooses to plan first (picked at approval gate), and that single branch carries all specs. One ticket seeds every split spec header by default; if batch genuinely spans multiple tickets, edit per-feature `Ticket:` values into individual spec headers before approval.

## 9. Write / update the spec file(s) to the template

**Resolve placement per spec.**
- **Existing spec update** → keep the exact path/root found in step 3. Do NOT invoke `/se-get-config` for that spec and do NOT prompt about local vs committed placement; its on-disk root already decides both. A config change never relocates an existing spec. Only an explicit user request to move that spec may change its root.
- **New spec** → invoke `/se-get-config` and read `commitSpec`. Resolution: `true` → write under committed root `docs/specs/`; `false` → write under uncommitted root `.super-exec/specs/`; `"ask"` → prompt the user via `AskUserQuestion` which root they want, then use the chosen value.
- **Mixed multi-feature split** → resolve each spec independently: updates retain their discovered roots; only genuinely-new specs consult `commitSpec`.

The resulting on-disk root drives whether step 12 commits the approved spec: commit only specs under `docs/specs/`; specs under `.super-exec/specs/` are intentionally uncommitted-by-design.

Write `<root>/[<app>/]<feature>/spec-<feature>.md` (where `<root>` is the resolved root above; monorepos insert the `<app>/` segment) using `Write` or `Edit` tool, following [spec-template.md](./spec-template.md). Feature slug is named per `/se-slug-naming` — slug-only identity, no running number. Template file is copy-pasteable markdown only: starts directly with final artifact shape, has no outer explanatory heading/prose, no instructional comments, no fenced code-block wrapper. Sections must appear in template order with no additional sections. Replace header placeholders; use `NO_TICKET` only when user confirms there is no Jira ticket, and set `Status:` to `active` for current approved spec (`draft` only for an intentionally unapproved spec, `superseded` only for a replaced one). For an update, keep the existing path/slug and edit only sections affected by delta. The **Behavior / Requirements** section holds acceptance criteria with NO HOW; if a requirement implies an implementation (for example, "use a queue"), extract underlying behavior ("retries must be durable across process restarts") and state that instead. Architecture and implementation details belong to /se-plan. The **Domain terms** section holds entries mirrored to `CONTEXT.md` (following [@./context-format.md](./context-format.md)) when new canonical terms resolved. The **Decisions** section holds only hard, surprising, trade-off decisions; broader architecture decisions meeting ADR gate go to `docs/adr/` (global) or the feature's `adr/` folder (feature-specific) — see step 10. This file is the review artifact; do NOT commit it before approval.

**Multi-feature split.** Write one spec file per feature, each under its own slug folder (`<root>/[<app>/]<feature>/spec-<feature>.md`). Do NOT number specs; dependency ORDER is conveyed via the `Depends on:` header, not by a number. Every spec uses same template independently (its own Problem / Goals / Behavior). When a feature genuinely depends on a sibling (e.g. `activity-feed` needs `auth`), record it in header's optional `Depends on:` line — set to `none` when no dependency. Shared domain terms resolved during interview written once to `CONTEXT.md` (step 10), not duplicated per spec. All spec files are uncommitted review artifacts until batch approval in step 12.

## 10. Write deferred glossary / ADR review artifacts

If interview resolved new domain terms, add intended `CONTEXT.md` edits now (following [@./context-format.md](./context-format.md)) so user can review them with the spec; create file (via `Write`) only when first term worth recording is identified. Offer an ADR only when **ADR 3-Criteria Gate** (below) passes; if offered and accepted, route by scope and write it (slug-only, named per `/se-slug-naming`, following [@./adr-format.md](./adr-format.md)) before approval so it is reviewable:
- **Feature-specific ADR** (concerns only this feature) → `<root>/[<app>/]<feature>/adr/<slug>.md` (inherits the spec's root).
- **Global / cross-cutting ADR** → `docs/adr/<slug>.md` (slug-only, no running number).
Do NOT commit any of these files before approval.

## 11. Spec self-review

Before presenting to user, scan EVERY written spec for: placeholders (TBD / TODO / "to be determined"), internal contradictions, scope creep (any HOW that snuck in), **any code (fenced code blocks, file layout, scaffolding — the spec is WHAT-only)**, and ambiguity (any requirement readable two ways). Fix inline using `Edit`. Move any code/HOW to a note for /se-plan and remove it from the spec. A requirement readable two ways must be made explicit — pick one reading and state it.

For a multi-feature split, additionally check: each spec is cohesive (no unrelated capabilities crammed together, no tightly-coupled capability split across two specs), dependency order is expressed via `Depends on:` (not by number), and every `Depends on` reference points to a real sibling spec.

## 12. Spec-approval gate, then branch + commit + chain to /se-plan

### Single spec

Present the finalized spec and ask via `AskUserQuestion`: **"Everything look good? Proceed to planning?"**

- **Change requested** → fix the written files using `Edit`, re-present, ask again via `AskUserQuestion`. Loop until user explicitly approves (e.g. "looks good" / "yes" / "approve").
- **On approval** → complete [@./branch-gate.md](./branch-gate.md) **Phase C: create/switch confirmed branch**, then — when the spec's resolved on-disk root is `docs/specs/` — **commit the already-written approved artifacts** via **`/se-commit`**, passing the paths this approval touched (the spec + any ADR / `CONTEXT.md` file). When the spec lives under `.super-exec/specs/` (local), do **not** commit it and say so — it is intentionally uncommitted-by-design. Also skip the commit and say so when the user asked not to commit. The user's approval IS the authorization to create/switch to the already-confirmed branch and (when applicable) commit. Before approval, keep review artifacts uncommitted; after approval, commit only the approved paths that belong under `docs/specs/` (plus any shared `CONTEXT.md` / global ADR under `docs/`). If branch switching conflicts with the approved uncommitted files, stop and ask rather than stashing, discarding, or rewriting them.
- **Then auto-invoke `/se-plan`** to continue the design session — the user does NOT type `/se-plan`. The discuss→plan transition is automatic; only the later plan→execute transition is a hard fresh-session boundary.

### Multi-feature split

1. **Batch approval.** Present ALL spec files together and ask ONE approval via `AskUserQuestion`: **"Everything look good across all specs? Proceed to planning?"** A change request loops back to editing any spec with `Edit` and re-presenting the set; repeat until the user approves the whole batch.
2. **Which to plan first.** On approval, ask via `AskUserQuestion` which spec to plan first (default the most foundational — the one others `Depends on`, or the first listed if none).
3. **Branch.** Confirm the first branch name for that chosen feature ([@./branch-gate.md](./branch-gate.md) **Phase B** naming, deferred from step 8), then run **Phase C: create/switch** it. This single branch carries all the specs.
4. **Commit (root-driven).** Via **`/se-commit`**, commit only the specs whose resolved on-disk root is `docs/specs/` plus any shared `CONTEXT.md` / global ADR (e.g. `docs: add initial specs for <app>`), passing those paths. Specs under `.super-exec/specs/` stay local — do not commit them and say so. Also skip and say so when the user asked not to commit. The first PR will therefore carry the first feature's implementation plus any committed specs.
5. **Chain the first feature only.** Auto-invoke `/se-plan <first-chosen spec slug or path>` — **pass the chosen spec explicitly** so /se-plan plans the right one, not an arbitrary spec from the batch. Do NOT chain the others. Tell the user the remaining specs (list them by slug) are planned one at a time later: in a fresh session `/se-plan` auto-discovers unplanned specs and asks which to plan (see /se-plan). Only the first feature is planned in this session.

---

## Red-Flag Table

When you catch yourself about to do any of the following, STOP and apply the correction.

| Red flag | What you were about to do | Correction |
|---|---|---|
| "This is too simple to discuss" | Skip interview and go straight to planning | Everything gets discussed. Spec can be short — one acceptance criterion is a valid spec. Run the full checklist. |
| "I'll ask the user what I could look up" | Ask user about directory structure, existing patterns, domain terms, existing specs | Dispatch a finder subagent via `Task`. Research the codebase. Ask only what is not discoverable. |
| "I'll add an architecture section" | Add tech choices, file layout, data model, or system design to the spec | WHAT-only. Move all HOW to a note for /se-plan. Remove it from the spec. |
| "I'll name the spec after the repo" | Set slug to repo name, `package.json` `name`, or app name | Derive slug from the feature being built. Collision gate halts on a match. |
| "This app has many features, I'll write one big spec" | Cram several independent features into one spec because they came from one conversation | If interview covered multiple cohesive, independent features, fire the Feature-split gate and propose one spec per feature. Cohesion (shared design intention), not conversation count, sets the boundary. |
| "It's clearly multiple features, I'll just split it" | Silently write N spec files without asking | Never split silently. Propose the slug-based breakdown via `AskUserQuestion` (A = split / B = one spec / C = edit). The user can always choose one spec. |
| "I'll auto-chain /se-plan for every spec I wrote" | Chain into planning for all N specs at once | Chain only the first-chosen feature. The rest are picked up later by `/se-plan` auto-discovery (lists unplanned specs and asks which to plan), one at a time. |
| "I'll put each split spec on its own branch / on base" | Commit split specs across N branches, or on the base branch | Specs whose root is `docs/specs/` commit together in ONE commit on the first-chosen feature's branch. That branch carries every spec; the first PR includes the committed ones. Features 2..N get their own branch later, created by /se-plan. |
| "I'll commit the spec before they've approved it" | Commit the spec while changes still under review or before the user says "looks good" | Commit only AFTER explicit approval, and only when the spec's resolved on-disk root is `docs/specs/`. Run the review/fix loop (via `AskUserQuestion`) first; on approval, commit via `/se-commit` — unless the user declined or the spec is local under `.super-exec/specs/`. Never commit before approval or mid-change. |
| "I'll stop and make them type `/se-plan`" | Hand off at the gate and wait for a manual `/se-plan` invocation | After the spec is approved (and committed when applicable), **auto-invoke `/se-plan`** in the same session. The user never types `/se-plan`. Only the plan→execute boundary stays a manual fresh-session step. |
| "I'll ask multiple questions at once" | Present a list of questions | One question at a time via `AskUserQuestion`. Wait for the answer. Provide your recommended answer with each question. |
| "I'll add a visual or mockup" | Describe UI layout or generate wireframe-style requirements | UI design direction belongs to /se-plan. State functional behavior only. |
| "I need the branch before I can interview" | Block the first user question on git/MCP/branch naming | Start the read-only branch-context warm-up in the background, then keep interviewing. Branch confirmation happens after the last WHAT question; branch creation happens only after spec approval. |
| "I already confirmed the branch, I'll ask again before committing" | Re-prompt for the same branch at approval time | Do not ask again unless branch creation fails, checkout conflicts, or facts changed. The earlier confirmation plus spec approval authorizes creating/switching to that branch and committing (when applicable). |
| "I need approval before writing the spec file" | Ask the user to approve an in-memory summary with no file to review | Write the uncommitted `<root>/.../spec-<feature>.md` file first: new specs use the `commitSpec`-resolved root; updates use their existing root. Human approval reviews the actual file diff; only the commit (when applicable) waits. |
| "Uncommitted spec on the old branch is dangerous, I'll hide it elsewhere" | Relocate or stash the review artifact to dodge review | The spec file itself is the review surface. Write it to its resolved root (`docs/specs/` or `.super-exec/specs/`), but do not commit until approval (and never commit a local `.super-exec/specs/` spec). |
| "This is an update, but `commitSpec` says `ask`" | Re-prompt whether the existing spec should be local or committed | Existing path wins. Keep its discovered root and skip `/se-get-config`; only an explicit user request may move it. |
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
4. Add resolved terms to `CONTEXT.md` (lazy) using `Edit` (or `Write` if the file doesn't exist yet), following the format in [@./context-format.md](./context-format.md).
5. If `CONTEXT-MAP.md` exists, the repo has multiple bounded contexts. Identify which context the feature lives in before discussing, and use that context's `CONTEXT.md`.

---

## ADR 3-Criteria Gate

Offer an ADR only when ALL THREE apply:

1. **Hard to reverse** — undoing this decision requires significant rework.
2. **Surprising without context** — a future developer reading the spec or code would wonder why this choice was made.
3. **Real trade-off** — there were at least two viable alternatives and a reason to prefer this one.

If any criterion fails, skip the ADR. Document the decision in the spec's **Decisions** section instead.

ADR file path by scope (slug-only, named per `/se-slug-naming`; no running number):
- **Feature-specific** → `<root>/[<app>/]<feature>/adr/<slug>.md` (inherits the spec's root).
- **Global / cross-cutting** → `docs/adr/<slug>.md`.

Write the ADR content following [@./adr-format.md](./adr-format.md).
