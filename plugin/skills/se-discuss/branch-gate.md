# Branch gate (reference)

Loaded by `se-discuss` at its branch/ticket gate step (the first checklist item of a design
session). This is a reference, not a standalone skill — `se-discuss` reads it on demand and follows
it to completion before anything else in the discuss session. It ensures:

1. Work lands on a correctly-named feature branch (never on `main`, `develop`, or any integration branch).
2. The branch name follows the repo's own convention (or the bundled default when the repo is silent).

The local-only working dir (`.super-exec/`) is kept out of git automatically by the SessionStart hook, which lists it in the repo-local, uncommitted `.git/info/exclude` every session — so this gate makes **no** `.gitignore` edits.

All git execution is delegated to a runner subagent — never run git commands inline in the controller.

---

## Procedure (do these in order)

- **Inspect current branch.** Read `git branch --show-current`. If the branch already matches the work (feature name, ticket, intent), confirm with the user and skip branch creation. Otherwise proceed.
- **Resolve the ticket.** Ask the user for the ticket ID. Query the Atlassian MCP to pull the ticket title and description. If the Atlassian MCP is unavailable, ask the user to enable it; if they decline or it remains unavailable, ask them to supply a raw branch name directly and use that verbatim. Never block hard — degrade gracefully.
- **Resolve branch-name convention by precedence.** Follow the three-step precedence rule (see "Convention precedence" below). Surface the resolved convention to the user before constructing the name.
- **Construct and confirm the branch name.** Present the proposed name to the user. Accept or adjust before proceeding.
- **Fetch and prune.** Dispatch a runner subagent (script-runner tier — see the `se-subagent` skill) with the `Task` tool to run `git fetch --all --prune`. Do not skip this step even on a clean tree.
- **Detect the base branch.** In the same runner subagent, check whether `origin/develop` exists (`git ls-remote --exit-code origin develop`). If it exists use `origin/develop`. If it does not exist fall back to `origin/main`.
- **Create the branch (runner subagent).** Still in the runner subagent, execute `git checkout -b <name> origin/<base>^0`. The `^0` suffix detaches from the remote-tracking ref so no upstream is set; the upstream is established on first push. Do not set `--track`.

> Ignoring `.super-exec/` is **not** this gate's job — the SessionStart hook already ensures it is in `.git/info/exclude` (local, uncommitted) every session. Do not edit `.gitignore` here.

---

## Convention precedence

The branch name is derived by applying these three checks in order. Stop at the first source that yields a rule.

```
(a) Repo skill: .claude/skills/git-new-branch (SKILL.md)
       ↓  present? → follow it 100%, every word. Skip (b) and (c).
(b) Detected repo pattern: sample the last 20 branch names from git history
       ↓  clear pattern? → mirror that pattern exactly. Skip (c).
(c) Bundled default (only when (a) and (b) are both silent)
       ↓  apply the default convention below.
```

**The repo always wins. The bundled default only fills silence.**

To detect a repo pattern: dispatch a runner subagent to run `git branch -a --sort=-committerdate | head -20`. Scan for a consistent prefix/separator scheme (e.g. `ENG-1234/short-description`, `type/ENG-1234-summary`). If two-thirds or more of recent branches share a structure, that structure is the detected pattern.

### Bundled default convention

Use only when neither (a) nor (b) applies.

- All-lowercase, hyphen-separated words. No underscores, no slashes, no uppercase.
- **With a ticket:** `<ticket-id>-<summary>` where `<ticket-id>` is the lowercased ticket key (e.g. `intcomp-1234`) and `<summary>` is at most 6 words drawn from the ticket title.
  - Example: `intcomp-1234-new-headline-note-banner`
- **Without a ticket:** `<type>-<summary>` where `<type>` is one of `feat | fix | chore | ci | docs | test | style | refactor | perf` and `<summary>` is at most 6 words.
  - Example: `feat-add-push-notification-opt-in`

---

## Red-flag table

| Thought | Reality — what to do instead |
|---|---|
| "I'll just run the git commands inline in the controller." | Never. All `git fetch`, `git checkout -b`, and any other git execution must be dispatched to a runner subagent (script-runner tier — see the `se-subagent` skill). The controller waits for the subagent's result. |
| "I'll branch off `main` — it's the safe default." | Auto-detect first. Check whether `origin/develop` exists. Branch off `develop` if it does; fall back to `main` only when `develop` is absent. |
| "The repo has no skill and I don't see a pattern, so I'll invent something sensible." | No invention. When (a) and (b) are both silent, apply the bundled default convention verbatim — `<ticket-id>-<≤6-word-summary>` or `<type>-<≤6-word-summary>`. |
| "I'll skip `git fetch --all --prune` — the tree is clean." | Always fetch first. Stale remote-tracking refs can cause the base detection to pick the wrong branch or miss that `develop` has been deleted. |
| "The current branch name looks roughly right, I'll keep going." | Confirm it actually matches this work before declaring it usable. Read the branch name, show it to the user, and get explicit acknowledgement. |
| "I'll set `--track` so the user's pushes go to the right place automatically." | Do not set `--track`. Use `git checkout -b <name> origin/<base>^0` exactly. The upstream is set on first push, not at branch creation. |
| "I'll append `.super-exec/` to `.gitignore` to be safe." | Don't touch `.gitignore`. The SessionStart hook keeps `.super-exec/` out of git via the local, uncommitted `.git/info/exclude` — editing the team-shared `.gitignore` is the old mechanism and would create a pointless tracked diff. |
| "Atlassian MCP is unavailable — I'll make up a ticket summary." | Never fabricate ticket data. Degrade gracefully: first ask the user to enable the MCP; if they decline, ask for a raw branch name and use it verbatim. |

---

## Subagent dispatch

- **Runner subagent** (git execution, branch detection) → script-runner / finder tier (see the `se-subagent` skill for the tier mapping). Dispatch it with the `Task` tool.
- **Atlassian MCP** → invoke the Atlassian MCP directly. The MCP is optional; absence must degrade gracefully, not hard-fail.

The branch-creation commands (`git fetch`, `git checkout -b`) are operational setup, not user-visible commits or pushes, so they do not trigger the commit/push nudge guard. Later commits and pushes made during the session do go through repo skills dispatched to subagents as normal.
