---
name: se-discuss
description: Use BEFORE any planning or code, when the user wants a new feature or a change to existing behavior — "let's build/add/create X", "I want a feature that…", "change how Y works", "can we make it do Z". Use even if the user never says "spec".
---

# se-discuss — Discuss Phase

Own requested scope, provenance, and convergence. Interview **WHAT** only; `/se-plan` owns HOW/architecture. Cheap finder subagents research; `/se-subagent` owns tiers. Optional caveman available: detect/use, never install/block.

## Operational checklist

Use harness todo-list tool to load and track this checklist. Sync status as work changes; before approval, delivery, or completion claim, verify every applicable item complete.

- [ ] Activate and apply local ignore
- [ ] Discover existing/new artifacts and root
- [ ] Converge WHAT and provenance
- [ ] Split, name, and complete branch phases
- [ ] Write template artifact in resolved root
- [ ] Self-review and obtain approval
- [ ] Commit or hand off to plan as allowed

## Start and discover

First write `.super-exec/active` (`phase: discuss`, `started: <current UTC ISO-8601>`), then `/se-local-ignore`. Argument seeds interview, never assumes outcome. Read [@./branch-gate.md](./branch-gate.md), start Phase A read-only warm-up and fact discovery promptly; never create/switch here.

Finders inspect `CONTEXT.md`/`CONTEXT-MAP.md`, both spec roots, relevant code, conventions, and existing behavior. Scan both roots (plus monorepo app) for matching ticket/slug; confirm update vs new. Update interviews delta only.

## Interview as a decision/dependency graph

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Only ask material WHAT, acceptance, priority, or first-value decisions; never HOW, architecture, files, or UI design.

Bound the graph to requested scope. Add a node only with provenance: user request/correction, verified current-behavior contradiction, or explicitly user-approved derived requirement; otherwise do not add it to the frontier. An explicitly user-raised edge case stays an active frontier decision until user accepts it, explicitly defers/later/maybe, rejects it, or a stop signal leaves it deferred/unapproved. If accepted, capture it in Core requested requirements with user priority regardless of likelihood. Only agent-originated concerns or suggestions default to Deferred concerns until user promotes them.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled — the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Each question should be formatted like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Give every frontier question a stable session-unique `Q<number>` ID; never reassign an ID to another decision, and retire invalidated IDs. After the scope/provenance filter, use one structured harness question interaction for the whole frontier; each field/option keeps its visible Q ID and per-question recommendation. If host batching limits apply, use minimum interactions for that same frontier and never mix later dependent nodes.

Each round the user answers reshapes the tree — settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it — don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report — ask the rest of the frontier now.

Start fact discovery promptly. Ask immediately when the fact-settled frontier is nonempty; if every candidate is blocked on required pending facts, await them rather than invent incomplete questions.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.

`proceed`, `implement`, or `stop asking` is that confirmation and ends questioning under user authority. Only settled decisions become requested or approved requirements; unanswered decisions remain deferred or unapproved (optionally Deferred concerns), never inferred/defaulted into scope. Then continue existing split/name/branch, spec-writing, review, and approval flow.

## Split, name, branch

One cohesive design intention = one spec; PR size does not matter. Split independent features only after user chooses: proposed split / keep one / regroup. Use `Depends on:` for order, never numbers. Name each work slug via `/se-slug-naming`; it cannot equal repo basename, `package.json` name, or app name—collision halts and asks. Existing matching split member is update.

After WHAT, run branch-gate Phase B. Resolve ticket once (`NO_TICKET` only after user says none); fetch known ticket with available Atlassian MCP. Single spec: confirm ticket + branch now. Split: resolve ticket now, defer branch name until user picks first plan; one first-feature branch carries committed split specs.

## Write review artifacts

Existing spec keeps discovered root; never consult config/move absent explicit request. New spec uses `/se-get-config commitSpec`: `true` → `docs/specs/`; `false` → `.super-exec/specs/`; `"ask"` → ask. Write `<root>/[<app>/]<feature>/spec-<feature>.md` using [spec-template.md](./spec-template.md), no wrappers/comments/extra sections. Keep update path/slug; edit delta only.

Spec is WHAT-only: acceptance in Core requested requirements; explicitly approved research/agent suggestions in Approved derived requirements with provenance/priority; unaccepted concerns Deferred concerns. Convert implied implementation into behavior. Domain terms mirror `CONTEXT.md` through [@./context-format.md](./context-format.md); create lazily. Decisions holds hard/surprising trade-offs. Offer ADR only if hard to reverse, surprising without context, and real alternative trade-off; use [@./adr-format.md](./adr-format.md), feature path `<root>/[<app>/]<feature>/adr/<slug>.md` or global `docs/adr/<slug>.md`. Never commit pre-approval.

Split: one independent template spec each, optional real sibling dependency or `none`; shared terms once in `CONTEXT.md`.

## Review and publish

Self-review every spec: no placeholders, contradictions, HOW/code/file layout/scaffolding, or ambiguous requirement; split cohesion and real dependency references. Fix inline.

Present one spec or full split batch; loop edits until explicit approval. Approval authorizes branch-gate Phase C and, for committed-root artifacts only, `/se-commit` with exact approved spec/ADR/`CONTEXT.md` paths. Local specs never commit; user no-commit overrides. Checkout conflict → stop and ask; never stash/discard/rewrite.

Single: auto-invoke `/se-plan`. Split: after batch approval ask first plan (default foundational), run deferred Phase B then C, commit committed artifacts together, auto-invoke `/se-plan <chosen slug/path>` only; list remaining specs for later manual no-arg discovery. Plan → execute remains fresh-session boundary.
