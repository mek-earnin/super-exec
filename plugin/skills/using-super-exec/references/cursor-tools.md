# Cursor translation (CC → Cursor)

Skills use Claude Code names; Cursor readers translate. This is sole translation owner: skills never branch by host or spell Cursor model names.

## Models and dispatch

| CC alias | Tier | Cursor |
|---|---|---|
| `opus` non-fast | strong: interview, planning, architecture/deep review, judge, handoff | strongest current high-reasoning GPT or Opus; otherwise non-fast inherit |
| `sonnet` pinned | mid: implementer/fixer | latest `cursor-grok-*` high |
| `haiku` | cheap: runner/finder/git/`gh` | latest available non-fast `gpt-*-luna*` (for example, `gpt-5.6-luna-medium`); fallback to latest non-fast `composer-*` or equivalent non-fast cheap-tier model |

Names are examples, never pinned. Resolve role from `/se-subagent`; set explicit non-fast model for subagents. CC `Task` maps to a cursor non-fast model subagent; typed Task → Cursor-native equivalent.

## Tools and interaction

`Read`/`Edit`/`Write`/`Bash`/`WebFetch`/`WebSearch` map to Cursor-native equivalents; `Glob` means file search. Harness todo-list read/update maps to its native list tool. `AskUserQuestion` maps to chat question and wait; never infer a default. `user-invocable: false` remains internal. `disable-model-invocation: true` remains manual-only where supported; otherwise safe read-first behavior: mutations require explicit arguments and migrate defaults dry-run.

## Hooks and paths

CC `SessionStart` → Cursor `sessionStart`; `PreToolUse` → `beforeShellExecution` (shell only); `PostToolUse`/`SessionStop` → native equivalent. Extra context: `hookSpecificOutput.additionalContext` → `additional_context`. Shell block: `permissionDecision: "deny"` → `{ permission: "deny", failClosed: true }`; allow → `{ permission: "allow" }`.

Plugin/project variables: `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PROJECT_DIR` → `CURSOR_PLUGIN_ROOT`/`CURSOR_PROJECT_DIR`. Bundle reference: `@./<file>`; cross-skill reference: `@../<skill>/<file>`. Resolve from loaded skill path; never rely on a skill-directory shell variable.

Cursor has no controller/subagent signal or generic pre-file hook. CC-only nudges N1/N2 and fenced-spec N3 therefore degrade to skill prose. B1 (no commit while `.super-exec/gate-open`) stays enforced through `beforeShellExecution`.

Cursor's explicit-commit policy accepts `/se-exec` review-before-commit OFF as standing user authorization for focused reviewed checkpoints. ON follows se-exec exact approval/identity/reopen/clear-before-commit gate. Auto-PR OFF follows its final gate ordering.
