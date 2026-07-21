# Cursor translation (one-way, CC → Cursor)

super-exec skills authored in **Claude Code language** — CC tool names (`Read`, `Edit`, `Write`, `Task`, `AskUserQuestion`, `TodoWrite`), CC model aliases (`opus` / `sonnet` / `haiku`), CC hook event names. Harness-neutral translation layer; skills don't branch per harness.

**Single** place translation lives. Under Cursor, read the CC primitive in a skill and resolve via the tables below. Mapping is **one-way** (CC → Cursor): skills never spell a Cursor name; Cursor readers translate on the fly. Where a Cursor mapping is unknown/undocumented, the entry says **Cursor-native equivalent** rather than inventing a name.

---

## Model tiers (aliases, not version strings)

super-exec names model **tiers** by family alias so they never go stale (see the `/se-subagent` skill for the canonical role → tier table). Resolve each alias to its Cursor equivalent:

| CC alias | Tier / role | Cursor |
|---|---|---|
| `opus` (non-fast) | strong — discuss interview, plan, arch-gate & deep review, impeccable-critique, verifier judgment, handoff authoring | Strongest available reasoning model at high reasoning effort — latest GPT (e.g. GPT-5.5, Extra High) **or** latest Opus (e.g. Opus 4.8, Extra High); if none selectable, fall back to Default / inherit (non-fast). |
| `sonnet` (pinned) | mid — implementer / fixer | latest composer non-fast |
| `haiku` | cheap — script-runner / runner / finder / investigator | latest composer non-fast |

> Model names above are illustrative (`e.g.`), not pinned — always pick the *latest* in each family. Strong tier wants best reasoning available; mid/cheap tiers want the non-fast Composer model.

> **Pinned-to-Sonnet policy on Cursor.** CC pins the implementer/fixer to `sonnet` explicitly. Cursor's composer model selection is less granular, so the equivalent is "latest composer non-fast" and inheritance from the non-fast tier is acceptable.

---

## Subagent dispatch

| Concept | Claude Code | Cursor |
|---|---|---|
| Spawn a subagent (general-purpose) | `Task` tool (no `subagent_type`) | Composer non-fast subagent |
| Spawn a typed agent | `Task` tool with `subagent_type` param | Cursor-native equivalent |
| Skill prose alias | "dispatch a subagent" / "spawn a Task" | "invoke a composer subagent" |

---

## Skill frontmatter keys

| Key | Claude Code | Cursor |
|---|---|---|
| `user-invocable: false` | Internal skill — humans can't invoke it directly; only other skills / the model load it (e.g. `/se-get-config`, `/se-slug-naming`) | Cursor-native equivalent — treat as internal; don't surface it as a user command |
| `disable-model-invocation: true` | Skill is **human-invoked only** — the model never auto-invokes it (e.g. `/se-config`) | Cursor-native equivalent — mark the skill manual-only. If the host does **not** honor the key it **degrades gracefully**: the model may auto-load the skill, which is safe because these are read-first commands whose mutating paths (`se-config set`, `se-config migrate`) require explicit human arguments and `migrate` defaults to dry-run. |

> `disable-model-invocation` is a hint about *who triggers* the skill, not a security boundary. On a harness that ignores it the skill still works; the worst case is a model-initiated invocation of a command that does nothing destructive without explicit args.

---

## Human interaction

| Concept | Claude Code | Cursor |
|---|---|---|
| Ask the user a structured question (forced choice) | `AskUserQuestion` tool | Cursor-native equivalent — ask the question in chat and wait for the user's reply before proceeding |

> Skills force `AskUserQuestion` for human decision points (/se-discuss interview, /se-plan risk-grilling, /se-exec toggles). On Cursor with no structured-question tool, degrade to a plain chat question and **wait** for the answer — never assume a default and proceed.

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

> CC hook event names are PascalCase; Cursor's are camelCase. A hook registered as `PreToolUse` on CC won't fire if the Cursor config spells it `preToolUse` — always use the harness-correct casing.

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

## Plugin & skill paths

| Variable | Claude Code | Cursor |
|---|---|---|
| Plugin root directory | `CLAUDE_PLUGIN_ROOT` | `CURSOR_PLUGIN_ROOT` |
| Project directory | `CLAUDE_PROJECT_DIR` | `CURSOR_PROJECT_DIR` |

**Skill-bundled files:** Reference scripts/files beside a skill with the `@./<file>` file-mention form (e.g. `@./branch-context`, [@./worktree.md](./worktree.md) — link text `@./<file>`, link target `./<file>`). Both harnesses resolve that path from the loaded SKILL.md's own location — Claude Code exposes `${CLAUDE_SKILL_DIR}` for that directory internally; Cursor derives it from the loaded skill path. No path env var is exported to the agent shell, so never rely on `${CLAUDE_SKILL_DIR}` or `${CURSOR_PLUGIN_ROOT}` inside an agent bash command.

**Cross-skill references:** a skill may reference a sibling's bundled file with the relative `@../<other-skill>/<file>` form (e.g. /se-plan references [@../se-discuss/branch-gate.md](../se-discuss/branch-gate.md)). Resolves the same way — relative to the referencing SKILL.md's own directory — so the agent reads the target with the `Read` tool on demand.

---

## Guard degradation on Cursor

The super-exec guard registers on CC `PreToolUse` for both `Bash` and `Write|Edit|MultiEdit`. Two consequences on Cursor:

1. **N1 / N2 nudges** (delegate build/test to a subagent; route git/PR mutations through the repo skill) rely on `additionalContext` on the allow path, which Cursor's allow path doesn't expose — they degrade to plain allow. Rely on skill-prose discipline instead.
2. **N3 nudge** (don't write fenced code into a `spec-<feature>.md` under either root — `docs/specs/` or `.super-exec/specs/`) is backed by the file-edit hook registration. Cursor exposes **no generic pre-file event**, so N3 is **CC-only** and degrades to skill-prose discipline on Cursor — same posture as N1/N2.

The **B1 hard block** (no commit while `.super-exec/gate-open` exists) fires through `beforeShellExecution` and is enforced on both harnesses.

---

## Host commit policy vs auto-commit

Cursor's default agent policy discourages committing without an explicit, per-action user request ("only create commits when requested by the user; if unclear, ask first; never commit unless the user explicitly asks"). super-exec's auto-commit (review-before-commit **OFF**) is **not** that proactive committing: the user sets the toggle at /se-exec entry via a structured question, and **that choice is explicit, standing authorization** to commit each task on inner-loop-green. Treat every per-task commit under OFF as a *user-requested* commit and don't pause to re-ask — pausing here is a defect, not caution.

The host policy still applies in full wherever super-exec has *not* been authorized: when review-before-commit is **ON**, commits wait behind `.super-exec/gate-open` and explicit human approval (the B1 block enforces this). The actual `git commit` also runs in a runner subagent (per `/se-commit`), where git work belongs — the controller only decides to dispatch it. This is a prose-level resolution: there is no host hook that *forces* a commit, so the authorization framing is what keeps the controller from babysitting each commit.
