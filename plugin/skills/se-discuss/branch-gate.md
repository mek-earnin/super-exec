# Branch gate (reference)

Loaded by `se-discuss` (all three phases). Reused by `/se-plan` (Phases B+C) when /se-plan owns branch creation for a spec with no feature branch yet (features 2..N of a multi-feature split, or manual re-entry from a base branch). Reference, not a standalone skill — owning skill reads it on demand, follows the phase its checklist names. Ensures:

1. Interview never blocks on git or Atlassian MCP.
2. User confirms ticket + branch name once, after WHAT is clear.
3. Work lands on a correctly-named feature branch before any approved artifact is committed.

Local-only working dir (`.super-exec/`) kept out of git by SessionStart hook — lists it in repo-local, uncommitted `.git/info/exclude` every session. So this gate makes **no** `.gitignore` edits.

Git inspection → [@./branch-context](./branch-context), read-only script emitting JSON. Mutating git (`fetch`, `checkout`) runs only in Phase C, after spec approval.

---

## Phase A: read-only warm-up (start of discuss)

Start now, but don't wait for it before asking interview questions.

- **Run branch context in background.** Start [@./branch-context](./branch-context), passing any user-provided ticket id / short description as args if available. Redirect output → `.super-exec/branch-context.json` when convenient, or keep the background job handle if the harness supports it. Read-only. Returns JSON: current branch, inferred ticket, branch samples, convention hints, dirty state, preferred base.
- **Ticket known + Atlassian MCP available? Fetch ticket context in parallel.** Use title/description to seed the interview and later branch naming. MCP unavailable → don't interrupt yet; defer to Phase B.
- **Continue the interview.** Don't ask for a ticket or branch name at session start unless the ticket is needed to understand the user's first request.

Background shell unavailable → skip the wait, run [@./branch-context](./branch-context) at first natural pause before Phase B.

## Phase B: ticket + branch confirmation (after last WHAT question)

Run after the feature slug is stable, before writing the spec file.

> **Halves may run separately.** Two halves — ticket resolution + branch-name confirmation. In a multi-feature split (se-discuss) or an /se-plan re-entry, resolve the ticket when WHAT/spec is clear but confirm the branch name later (once the first feature to plan is chosen). Don't force the branch-name question early in those flows.

- **Read branch context.** Background result ready → read it. Not ready → wait briefly; still unavailable → run [@./branch-context](./branch-context) synchronously now. Final feature slug = source of truth for branch naming.
- **Resolve ticket once.** Ticket provided by user, inferred from current branch, discovered from prompt, or read from the selected spec's `Ticket:` header (when /se-plan reuses this gate for an existing spec) → use it. No ticket known → ask exactly once: "Do you have a Jira ticket for this task?" Answer no → record `NO_TICKET`.
- **Use Atlassian MCP when possible.** Ticket known + MCP available → query it for title/description, derive branch summary from that. MCP unavailable → ask user to enable it or confirm the branch summary manually. Never fabricate ticket data.
- **Resolve branch-name convention by precedence.** Follow the three-step precedence rule (see "Convention precedence" below). Surface the resolved convention before proposing the name.
- **Construct + confirm the branch name.** Present the proposed ticket value + branch name; accept or adjust before proceeding. This confirmation is durable for the approval/commit step; don't ask again unless facts changed, branch creation fails, or checkout conflicts.

## Phase C: create/switch confirmed branch (after spec approval, or skip-spec proceed)

Run after the user approves the already-written spec and the next action is committing artifacts — or, on skip-spec, after `proceed` / `implement` / `stop asking` authorizes the branch before first exec commit. Skip-spec has no spec file to commit.

- **Re-check current branch.** On the confirmed branch → continue. On any other branch (protected or not) → switch/create before committing artifacts. Do not commit approved spec changes on a non-matching branch.
- **Inspect dirty state before switching.** Approved review artifacts (`docs/specs/` OR `.super-exec/specs/`, plus `GLOSSARY.md` / `GLOSSARY-MAP.md`, ADRs) are expected dirty. Other dirty files (incl. unasked `CONTEXT.md` / `CONTEXT-MAP.md`) → surface; don't stage. Don't require a clean tree to proceed.
- **Fetch + prune.** Run `git fetch --all --prune`. Don't skip this even on a clean tree.
- **Detect the base branch.** Preferred base from Phase A/B still valid → use it. Else check whether `origin/develop` exists (`git ls-remote --exit-code --heads origin develop`): exists → use `origin/develop`, else fall back to `origin/main`.
- **Switch or create the branch.** Local branch `<confirmed-name>` exists → run `git checkout <confirmed-name>`. Else → run `git checkout -b <confirmed-name> <base>^0` (for example, `git checkout -b intcomp-1234-new-banner origin/develop^0`). The `^0` suffix detaches from the remote-tracking ref so no upstream is set; the upstream is established on first push. Do not set `--track`.
- **If checkout would overwrite or conflict with any uncommitted change, stop and ask.** Never discard, stash, or rewrite the user's/spec changes silently. Present the conflicting paths and recommend the smallest safe recovery:
  - Current HEAD is already the intended base (or the user accepts the base deviation) → create the confirmed branch from the current HEAD so the approved uncommitted review artifacts stay in place.
  - Otherwise → ask the user to resolve the working-tree conflict manually or choose a different branch/base; do not proceed to commit until the confirmed branch contains the approved files.
- **Then commit artifacts.** Approved review artifacts under `docs/specs/` / `.super-exec/specs/`, plus `GLOSSARY.md` / `GLOSSARY-MAP.md` and ADRs written this session, should already exist uncommitted. `CONTEXT.md` / `CONTEXT-MAP.md` only if the user asked. Then `se-discuss` calls `/se-commit` (committed-root paths only).

---

## Convention precedence

Derive the branch name by applying these three checks in order. Stop at the first source that yields a rule.

```
(a) Repo skill: .claude/skills/git-new-branch (SKILL.md)
       ↓  present? → follow it 100%, every word. Skip (b) and (c).
(b) Detected repo pattern: sample the last 20 branch names from git history
       ↓  clear pattern? → mirror that pattern exactly. Skip (c).
(c) Bundled default (only when (a) and (b) are both silent)
       ↓  apply the default convention below.
```

**Repo always wins. Bundled default only fills silence.**

Detect a repo pattern: prefer the `recentBranches` + `conventionHint` fields from [@./branch-context](./branch-context). Need more evidence → sample recent branch names, scan for a consistent prefix/separator scheme (e.g. `ENG-1234/short-description`, `type/ENG-1234-summary`). Two-thirds+ of recent branches share a structure → that's the detected pattern.

### Bundled default convention

Use only when neither (a) nor (b) applies.

- All-lowercase, hyphen-separated words. No underscores, no slashes, no uppercase.
- **With a ticket:** `<ticket-id>-<summary>` — `<ticket-id>` = lowercased ticket key (e.g. `intcomp-1234`), `<summary>` ≤ 6 words drawn from the ticket title.
  - Example: `intcomp-1234-new-headline-note-banner`
- **Without a ticket:** `<type>-<summary>` — `<type>` one of `feat | fix | chore | ci | docs | test | style | refactor | perf`, `<summary>` ≤ 6 words.
  - Example: `feat-add-push-notification-opt-in`

---

## Red-flag table

| Thought | Reality — what to do instead |
|---|---|
| "I'll block the first interview question until branch context finishes." | Don't wait. Start Phase A in the background, keep interviewing. |
| "I'll ask for the ticket before I know what the task is." | Defer ticket prompting to Phase B unless the ticket is needed to understand the first request. |
| "The user confirmed the branch in Phase B, but I'll ask again after approval." | Don't ask again unless facts changed, branch creation failed, or checkout conflicts. Phase B confirmation + spec approval authorizes Phase C. Skip-spec: Phase B confirmation + `proceed`/`implement`/`stop asking` authorizes Phase C. |
| "I'll hide the spec draft in `.super-exec/` until approval." | Wrong. A new spec is written to its `commitSpec`-resolved root; an existing-spec update stays at its discovered path. THAT file is the review surface — do not relocate or stash it elsewhere to dodge review. Only the commit (when the resolved root is `docs/specs/`) waits for Phase C. |
| "There are unrelated dirty files, so I need to clean/stash them before switching." | Don't mutate unrelated work. Surface it, carry it if git allows, rely on `/se-commit` staging isolation so only approved artifact paths are committed. |
| "Checkout conflicts with dirty files, so I'll stash or overwrite to get unstuck." | Stop and ask. Uncommitted work may be the user's or the approved review artifact; never stash, discard, or rewrite it without explicit user direction. |
| "I'll branch off `main` — it's the safe default." | Auto-detect first. Branch off `origin/develop` if it exists; fall back to `main` only when `develop` is absent. |
| "The repo has no skill and I don't see a pattern, so I'll invent something sensible." | No invention. (a) + (b) both silent → apply the bundled default verbatim — `<ticket-id>-<≤6-word-summary>` or `<type>-<≤6-word-summary>`. |
| "I'll skip `git fetch --all --prune` — the tree is clean." | Always fetch first. Stale remote-tracking refs → base detection picks the wrong branch or misses that `develop` was deleted. |
| "The current branch name looks roughly right, I'll keep going." | Confirm it actually matches this work in Phase B. Read the name, show the user, get explicit acknowledgement. |
| "I'll set `--track` so the user's pushes go to the right place automatically." | Don't set `--track`. Use `git checkout -b <name> origin/<base>^0` exactly. Upstream is set on first push, not at branch creation. |
| "I'll append `.super-exec/` to `.gitignore` to be safe." | Don't touch `.gitignore`. SessionStart hook keeps `.super-exec/` out of git via the local, uncommitted `.git/info/exclude`; editing the team-shared `.gitignore` is the old mechanism, creates a pointless tracked diff. |
| "Atlassian MCP is unavailable — I'll make up a ticket summary." | Never fabricate ticket data. Degrade gracefully: ask the user to enable MCP or confirm the branch name manually. |

---

## Helper + subagent dispatch

- **[@./branch-context](./branch-context)** → read-only branch inspection + convention sampling. Run it directly; replaces spawning a subagent just to inspect the current branch.
- **Runner subagent** (mutating git execution, if the harness requires delegation) → script-runner / finder tier (see the `/se-subagent` skill for the tier mapping). Dispatch it with the `Task` tool.
- **Atlassian MCP** → invoke it directly. Optional; absence must degrade gracefully, not hard-fail.

branch-context helper = read-only operational setup. Branch-creation commands (`git fetch`, `git checkout -b`) = operational setup, not user-visible commits or pushes, so they don't trigger the commit/push nudge guard. Later commits + pushes during the session go through repo skills dispatched to subagents as normal.
