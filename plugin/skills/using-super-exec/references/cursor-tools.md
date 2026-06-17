# Cursor translation (one-way, CC → Cursor)

super-exec skills are authored in **Claude Code language** — CC tool names (`Read`, `Edit`, `Write`, `Task`, `AskUserQuestion`, `TodoWrite`), CC model aliases (`opus` / `sonnet` / `haiku`), and CC hook event names — written inline, with no per-skill harness branching.

This file is the **single** place that translation lives. When running under Cursor, read the CC primitive in a skill and resolve it through the tables below. The mapping is **one-way** (CC → Cursor): skills never spell a Cursor name; Cursor readers translate on the fly. Where a Cursor mapping is unknown or undocumented, the entry says **Cursor-native equivalent** rather than inventing a name.

---

## Model tiers (aliases, not version strings)

super-exec names model **tiers** by family alias so they never go stale (see the `se-subagent` skill for the canonical role → tier table). Resolve each alias to its Cursor equivalent here:

| CC alias | Tier / role | Cursor |
|---|---|---|
| `opus` (non-fast) | strong — shape interview, plan, arch-gate & deep review, verifier judgment, handoff authoring | The strongest available reasoning model at high reasoning effort — latest GPT (e.g. GPT-5.5, Extra High) **or** latest Opus (e.g. Opus 4.8, Extra High); if none is selectable, fall back to Default / inherit (non-fast). |
| `sonnet` (pinned) | mid — implementer / fixer | latest composer non-fast |
| `haiku` | cheap — script-runner / runner / finder / investigator | latest composer non-fast |

> Model names above are illustrative (`e.g.`), not pinned — always pick the *latest* in each family. The strong tier wants the best reasoning available; the mid/cheap tiers want the fast composer model.

> **Pinned-to-Sonnet policy on Cursor.** CC pins the implementer/fixer to `sonnet` explicitly. Cursor's composer model selection is less granular, so the equivalent is "latest composer non-fast" and inheritance from the non-fast tier is acceptable.

---

## Subagent dispatch

| Concept | Claude Code | Cursor |
|---|---|---|
| Spawn a subagent (general-purpose) | `Task` tool (no `subagent_type`) | Composer non-fast subagent |
| Spawn a typed agent | `Task` tool with `subagent_type` param | Cursor-native equivalent |
| Skill prose alias | "dispatch a subagent" / "spawn a Task" | "invoke a composer subagent" |

---

## Human interaction

| Concept | Claude Code | Cursor |
|---|---|---|
| Ask the user a structured question (forced choice) | `AskUserQuestion` tool | Cursor-native equivalent — ask the question in chat and wait for the user's reply before proceeding |

> Skills force `AskUserQuestion` for human decision points (the se-shape interview, se-plan risk-grilling, the se-exec toggles). On Cursor with no structured-question tool, degrade to a plain chat question and **wait** for the answer — never assume a default and proceed.

---

## File, edit, search, and todo tools

| Concept | Claude Code tool | Cursor equivalent |
|---|---|---|
| Read a file | `Read` | Cursor-native equivalent |
| Edit a file (diff-based) | `Edit` | Cursor-native equivalent |
| Write / create a file | `Write` | Cursor-native equivalent |
| Search / grep across files | `Bash` (`grep` / `ripgrep`) | Cursor-native equivalent |
| Glob / list files | `Bash` (`find` / `glob`) | Cursor-native equivalent |
| Web fetch a URL | `WebFetch` | Cursor-native equivalent |
| Web search | `WebSearch` | Cursor-native equivalent |
| Todo / task tracking | `TodoWrite` / `TodoRead` | Cursor-native equivalent |

---

## Hook events

| Event | Claude Code (PascalCase) | Cursor (camelCase) |
|---|---|---|
| Session begins | `SessionStart` | `sessionStart` |
| Before any tool call | `PreToolUse` | `beforeShellExecution` (shell scope; no generic pre-tool event) |
| After any tool call | `PostToolUse` | Cursor-native equivalent |
| Session ends | `SessionStop` | Cursor-native equivalent |

> CC hook event names are PascalCase; Cursor hook event names are camelCase. A hook registered as `PreToolUse` on CC will not fire if the Cursor config spells it `preToolUse` — always use the harness-correct casing.

---

## Context injection

| Field | Claude Code | Cursor |
|---|---|---|
| Inject additional context into the agent | `hookSpecificOutput.additionalContext` | `additional_context` |

---

## Pre-exec block decision (deny shell execution)

| Action | Claude Code | Cursor |
|---|---|---|
| Block a shell command | `permissionDecision: "deny"` in hook output | `{ permission: "deny", failClosed: true }` |
| Allow a shell command | `permissionDecision: "allow"` | `{ permission: "allow" }` |

---

## Controller-vs-subagent signal

| Signal | Claude Code | Cursor |
|---|---|---|
| Detect whether running inside a subagent | `agent_id` present in `PreToolUse` payload | **No equivalent signal.** Controller-only nudges and guards that rely on this signal degrade to prose on Cursor (documented but not enforceable programmatically). |

---

## Plugin root environment variables

| Variable | Claude Code | Cursor |
|---|---|---|
| Plugin root directory | `CLAUDE_PLUGIN_ROOT` | `CURSOR_PLUGIN_ROOT` |
| Project directory | `CLAUDE_PROJECT_DIR` | `CURSOR_PROJECT_DIR` |

---

## Guard degradation on Cursor

The super-exec guard registers on CC `PreToolUse` for both `Bash` and `Write|Edit|MultiEdit`. Two consequences on Cursor:

1. **N1 / N2 nudges** (delegate build/test to a subagent; route git/PR mutations through the repo skill) rely on `additionalContext` on the allow path, which Cursor's allow path does not expose — they degrade to plain allow. Rely on skill-prose discipline instead.
2. **N3 nudge** (don't write fenced code into a `docs/specs/*.md` spec) is backed by the file-edit hook registration. Cursor exposes **no generic pre-file event**, so N3 is **CC-only** and degrades to skill-prose discipline on Cursor — same posture as N1/N2.

The **B1 hard block** (no commit while `.super-exec/gate-open` exists) fires through `beforeShellExecution` and is enforced on both harnesses.

---

## Host commit policy vs auto-commit

Cursor's default agent policy discourages committing without an explicit, per-action user request ("only create commits when requested by the user; if unclear, ask first; never commit unless the user explicitly asks"). super-exec's auto-commit (review-before-commit **OFF**) is **not** that proactive committing: the user sets the toggle at se-exec entry via a structured question, and **that choice is explicit, standing authorization** to commit each task on inner-loop-green. Treat every per-task commit under OFF as a *user-requested* commit and do not pause to re-ask — pausing here is a defect, not caution.

The host policy still applies in full wherever super-exec has *not* been authorized: when review-before-commit is **ON**, commits wait behind `.super-exec/gate-open` and explicit human approval (the B1 block enforces this). The actual `git commit` also runs in a runner subagent (per `se-commit`), where git work belongs — the controller only decides to dispatch it. This is a prose-level resolution: there is no host hook that *forces* a commit, so the authorization framing is what keeps the controller from babysitting each commit.
