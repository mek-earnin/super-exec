# Tool Map — CC ↔ Cursor

Skills are authored in harness-neutral prose. This file maps every primitive referenced
in skill prose to its concrete CC or Cursor equivalent. When a Cursor mapping is unknown
or undocumented, the entry says **Cursor-native equivalent** rather than inventing a name.

---

## Subagent Dispatch

| Concept | Claude Code | Cursor |
|---|---|---|
| Spawn a subagent (general-purpose) | `Task` tool (no `subagent_type`) | Composer non-fast subagent |
| Spawn a typed agent | `Task` tool with `subagent_type` param | Cursor-native equivalent |
| Skill prose alias | "dispatch a subagent" / "spawn a Task" | "invoke a composer subagent" |

---

## Hook Events

| Event | Claude Code (PascalCase) | Cursor (camelCase) |
|---|---|---|
| Session begins | `SessionStart` | `sessionStart` |
| Before any tool call | `PreToolUse` | `beforeShellExecution` (shell scope; no generic pre-tool event) |
| After any tool call | `PostToolUse` | Cursor-native equivalent |
| Session ends | `SessionStop` | Cursor-native equivalent |

> CC hook event names are PascalCase; Cursor hook event names are camelCase.
> Skills that reference hook events must branch on harness.

---

## Context Injection

| Field | Claude Code | Cursor |
|---|---|---|
| Inject additional context into agent | `hookSpecificOutput.additionalContext` | `additional_context` |

---

## Pre-Exec Block Decision (deny shell execution)

| Action | Claude Code | Cursor |
|---|---|---|
| Block a shell command | `permissionDecision: "deny"` in hook output | `{ permission: "deny", failClosed: true }` |
| Allow a shell command | `permissionDecision: "allow"` | `{ permission: "allow" }` |

---

## Controller-vs-Subagent Signal

| Signal | Claude Code | Cursor |
|---|---|---|
| Detect whether running inside a subagent | `agent_id` present in `PreToolUse` payload | **No equivalent signal.** Controller-only nudges and guards that rely on this signal degrade to prose on Cursor (the restriction is documented but cannot be enforced programmatically). |

---

## Plugin Root Environment Variables

| Variable | Claude Code | Cursor |
|---|---|---|
| Plugin root directory | `CLAUDE_PLUGIN_ROOT` | `CURSOR_PLUGIN_ROOT` |
| Project directory | `CLAUDE_PROJECT_DIR` | `CURSOR_PROJECT_DIR` |

---

## File, Edit, Search, and Todo Tools

| Concept | Claude Code tool | Cursor equivalent |
|---|---|---|
| Read a file | `Read` | Cursor-native equivalent |
| Edit a file (diff-based) | `Edit` | Cursor-native equivalent |
| Write / create a file | `Write` | Cursor-native equivalent |
| Search / grep across files | `Bash` (`grep` / `ripgrep`) | Cursor-native equivalent |
| Glob / list files | `Bash` (`find` / `glob`) | Cursor-native equivalent |
| Web fetch a URL | `WebFetch` (deferred tool) | Cursor-native equivalent |
| Web search | `WebSearch` (deferred tool) | Cursor-native equivalent |
| Todo / task tracking | `TodoWrite` / `TodoRead` | Cursor-native equivalent |

---

## Notes for Skill Authors

1. **Branch on harness** using the `CLAUDE_PLUGIN_ROOT` / `CURSOR_PLUGIN_ROOT` env var
   presence, or an explicit `HARNESS` variable set by the plugin bootstrap.
2. **Do not hardcode tool names** from one harness in skill prose intended for both —
   use the concept column above and resolve at runtime.
3. **controller-only guards** that depend on `agent_id` must document their Cursor
   degradation explicitly: "this check is not enforced on Cursor; rely on skill prose
   discipline instead."
4. **Hook event casing matters**: a hook registered as `PreToolUse` on CC will not fire
   if the Cursor config spells it `preToolUse` — always use the harness-correct casing
   from the table above.
