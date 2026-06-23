# Branch gate (reference)

Loaded by `se-discuss` in three phases. This is a reference, not a standalone skill — `se-discuss`
reads it on demand and follows the phase named by its checklist. It ensures:

1. The interview does not block on git or Atlassian MCP.
2. The user confirms ticket + branch name once, after the WHAT is clear.
3. Work lands on a correctly-named feature branch before any approved artifact is committed.

The local-only working dir (`.super-exec/`) is kept out of git automatically by the SessionStart hook, which lists it in the repo-local, uncommitted `.git/info/exclude` every session — so this gate makes **no** `.gitignore` edits.

Git inspection is handled by [@./branch-context](./branch-context), a lightweight read-only script that emits JSON. Mutating git commands (`fetch`, `checkout`) still run only in Phase C, after spec approval.

---

## Phase A: read-only warm-up (start of discuss)

Start this phase immediately, but do not wait for it before asking interview questions.

- **Run branch context in the background.** Start [@./branch-context](./branch-context), passing any user-provided ticket id / short description as arguments if available. Redirect output to `.super-exec/branch-context.json` when convenient, or keep the background job handle if the harness supports it. The script is read-only and returns JSON with current branch, inferred ticket, branch samples, convention hints, dirty state, and preferred base.
- **If a ticket is already known and Atlassian MCP is available, fetch ticket context in parallel.** Use the ticket title/description to seed the interview and later branch naming. If Atlassian MCP is unavailable, do not interrupt yet; defer the decision to Phase B.
- **Continue the interview.** Do not ask for a ticket or branch name at session start unless the ticket is required to understand the user's first request.

If background shell work is unavailable, skip the wait and run [@./branch-context](./branch-context) at the first natural pause before Phase B.

## Phase B: ticket + branch confirmation (after last WHAT question)

Run this after the feature slug is stable and before writing the spec file.

- **Read branch context.** If the background result is ready, read it. If not, wait briefly; if still unavailable, run [@./branch-context](./branch-context) synchronously now. Use the final feature slug as the source of truth for branch naming.
- **Resolve ticket once.** If a ticket was provided by the user, inferred from the current branch, or discovered from the prompt, use it. If no ticket is known, ask exactly once: "Do you have a Jira ticket for this task?" If the answer is no, record `NO_TICKET`.
- **Use Atlassian MCP when possible.** If a ticket is known and Atlassian MCP is available, query it for the title/description and use that data to derive the branch summary. If MCP is unavailable, ask the user to either enable it or confirm the branch summary manually. Never fabricate ticket data.
- **Resolve branch-name convention by precedence.** Follow the three-step precedence rule (see "Convention precedence" below). Surface the resolved convention before proposing the name.
- **Construct and confirm the branch name.** Present the proposed ticket value and branch name to the user. Accept or adjust before proceeding. This confirmation is durable for the approval/commit step; do not ask again later unless facts changed, branch creation fails, or checkout conflicts.

## Phase C: create/switch confirmed branch (after spec approval)

Run this only after the user approves the already-written spec and the next action is committing artifacts.

- **Re-check current branch.** If already on the confirmed branch, continue. If on any other branch — protected or not — switch/create before committing artifacts. Do not commit approved spec changes on a non-matching branch.
- **Inspect dirty state before switching.** The approved review artifacts (`docs/specs/`, `CONTEXT.md`, ADRs) are expected to be dirty. If unrelated files are dirty too, surface them briefly and state they will not be staged or committed by `se-commit`. Do not require a clean tree just to proceed.
- **Fetch and prune.** Run `git fetch --all --prune`. Do not skip this step even on a clean tree.
- **Detect the base branch.** Use the preferred base from Phase A/B if still valid. Otherwise check whether `origin/develop` exists (`git ls-remote --exit-code --heads origin develop`). If it exists use `origin/develop`; if not, fall back to `origin/main`.
- **Switch or create the branch.** If a local branch named `<confirmed-name>` already exists, execute `git checkout <confirmed-name>`. Otherwise execute `git checkout -b <confirmed-name> <base>^0` (for example, `git checkout -b intcomp-1234-new-banner origin/develop^0`). The `^0` suffix detaches from the remote-tracking ref so no upstream is set; the upstream is established on first push. Do not set `--track`.
- **If checkout would overwrite or conflict with any uncommitted change, stop and ask.** Never discard, stash, or rewrite the user's/spec changes silently. Present the conflicting paths and recommend the smallest safe recovery:
  - If the current HEAD is already the intended base (or the user accepts the base deviation), create the confirmed branch from the current HEAD so the approved uncommitted review artifacts remain in place.
  - Otherwise, ask the user to resolve the working-tree conflict manually or choose a different branch/base; do not proceed to commit until the confirmed branch contains the approved files.
- **Then commit artifacts.** The approved `docs/specs/`, `CONTEXT.md`, or ADR files should already exist as uncommitted review artifacts. Only after this phase succeeds should `se-discuss` call `/se-commit`.

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

To detect a repo pattern: prefer the `recentBranches` and `conventionHint` fields from [@./branch-context](./branch-context). If more evidence is needed, sample recent branch names and scan for a consistent prefix/separator scheme (e.g. `ENG-1234/short-description`, `type/ENG-1234-summary`). If two-thirds or more of recent branches share a structure, that structure is the detected pattern.

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
| "I'll block the first interview question until branch context finishes." | Do not wait. Start Phase A in the background and keep interviewing. |
| "I'll ask for the ticket before I know what the task is." | Defer ticket prompting to Phase B unless the ticket is needed to understand the first request. |
| "The user confirmed the branch in Phase B, but I'll ask again after approval." | Do not ask again unless facts changed, branch creation failed, or checkout conflicts. The Phase B confirmation plus spec approval authorizes Phase C. |
| "I'll hide the spec draft in `.super-exec/` until approval." | Wrong review surface. Write the uncommitted spec in `docs/specs/` so the user can review the actual file; only the commit waits for Phase C. |
| "There are unrelated dirty files, so I need to clean/stash them before switching." | Do not mutate unrelated work. Surface it, carry it if git allows, and rely on `se-commit` staging isolation so only approved artifact paths are committed. |
| "Checkout conflicts with dirty files, so I'll stash or overwrite to get unstuck." | Stop and ask. Uncommitted work may belong to the user or be the approved review artifact; never stash, discard, or rewrite it without explicit user direction. |
| "I'll branch off `main` — it's the safe default." | Auto-detect first. Check whether `origin/develop` exists. Branch off `develop` if it does; fall back to `main` only when `develop` is absent. |
| "The repo has no skill and I don't see a pattern, so I'll invent something sensible." | No invention. When (a) and (b) are both silent, apply the bundled default convention verbatim — `<ticket-id>-<≤6-word-summary>` or `<type>-<≤6-word-summary>`. |
| "I'll skip `git fetch --all --prune` — the tree is clean." | Always fetch first. Stale remote-tracking refs can cause the base detection to pick the wrong branch or miss that `develop` has been deleted. |
| "The current branch name looks roughly right, I'll keep going." | Confirm it actually matches this work in Phase B before declaring it usable. Read the branch name, show it to the user, and get explicit acknowledgement. |
| "I'll set `--track` so the user's pushes go to the right place automatically." | Do not set `--track`. Use `git checkout -b <name> origin/<base>^0` exactly. The upstream is set on first push, not at branch creation. |
| "I'll append `.super-exec/` to `.gitignore` to be safe." | Don't touch `.gitignore`. The SessionStart hook keeps `.super-exec/` out of git via the local, uncommitted `.git/info/exclude` — editing the team-shared `.gitignore` is the old mechanism and would create a pointless tracked diff. |
| "Atlassian MCP is unavailable — I'll make up a ticket summary." | Never fabricate ticket data. Degrade gracefully: ask the user to enable MCP or confirm the branch name manually. |

---

## Helper + subagent dispatch

- **[@./branch-context](./branch-context)** → read-only branch inspection and convention sampling. Run it directly; it replaces spawning a subagent just to inspect the current branch.
- **Runner subagent** (mutating git execution, if the harness requires delegation) → script-runner / finder tier (see the `se-subagent` skill for the tier mapping). Dispatch it with the `Task` tool.
- **Atlassian MCP** → invoke the Atlassian MCP directly. The MCP is optional; absence must degrade gracefully, not hard-fail.

The branch-context helper is operational setup and read-only. The branch-creation commands (`git fetch`, `git checkout -b`) are operational setup, not user-visible commits or pushes, so they do not trigger the commit/push nudge guard. Later commits and pushes made during the session do go through repo skills dispatched to subagents as normal.
