# Worktree — Isolated Build Reference

This file documents the `--worktree` opt-in path for se-exec. By default
se-exec operates directly in the main checkout. Pass `--worktree` when you
need the build to run in a fully isolated working tree — for example, when
parallel sessions are touching the same files, or when a risky refactor
should not disturb the main checkout until the plan is verified green.

---

## 1. Why and when

A git worktree is a second checkout of the same repository sharing the same
object store. It has its own working tree and its own HEAD, so uncommitted
changes in one worktree do not appear in the other.

Use `--worktree` when:

- Another session (or a long-running dev-server) is actively modifying files
  in the main checkout and you want the build to be isolated from that churn.
- The plan involves changes that are risky to leave half-applied in the main
  tree — the worktree acts as a staging area until all tasks are green.
- You want to run the build and the existing session side by side without
  context leakage between the two working directories.

Do not use `--worktree` by default. It adds setup/teardown overhead and an
extra branch to manage. The opt-in flag keeps the common path simple.

---

## 2. Create the worktree

Place the worktree **outside** the main repository directory (a sibling, not
a subdirectory) so it is never picked up by the main tree's file globs,
watch processes, or package-manager installs.

**Add a worktree on an existing branch:**

```
git worktree add ../super-exec-worktree <branch>
```

**Add a worktree on a new branch, based on the current branch:**

```
git worktree add -b <new-branch> ../super-exec-worktree <base-ref>
```

Replace `<base-ref>` with the branch or commit the new branch should start
from — typically `HEAD` or `origin/develop`. The worktree directory and
branch name are both required; git will not create one without the other.

All `git worktree add` calls run inside a **runner subagent** (see section 7).
The controller never runs git commands inline.

---

## 3. Work in the worktree

Implementer and runner subagents receive the worktree path as their working
directory. All reads, edits, and shell commands they issue target that path.

`.super-exec/` markers and the plan directory live in the **main repo**, not
the worktree. The guard and the controller both resolve `.super-exec/` from
the project root reported by `CLAUDE_PROJECT_DIR`, which points at the main
checkout. The worktree has no `.super-exec/`
directory; guards and gate checks continue to work correctly because they
read from the main repo root.

Pass the worktree path to each subagent explicitly. Do not rely on the
subagent inferring it — the working directory must be stated in the prompt.

---

## 4. Verify and commit

Verification runs in the worktree. The runner subagent executes all baseline
and task-specific commands with the worktree as the working directory,
exactly as it would in the main checkout. The runner → judge split applies
without change: the runner returns structured evidence; the judge evaluates
it against the spec and plan.

Commits also happen in the worktree. The commit appears on the worktree's
branch, not on the main checkout's branch. Worktree mode does **not** change
how commits work — commit through **`se-commit`** exactly as in the main
checkout. The only worktree-specific delta is that the runner subagent is
given the **worktree path** as its working directory.

---

## 5. Integrate and clean up

When all tasks are verified green:

1. **Merge or open a PR from the worktree branch.** The worktree branch is an
   ordinary git branch. Treat it exactly as you would any feature branch:
   merge it into the target branch, or push it and open a pull request.

2. **Remove the worktree.** Use `git worktree remove` — do NOT delete the
   directory by hand. Deleting the directory without this command leaves a
   stale entry in git's worktree list that must be cleaned up manually.

   ```
   git worktree remove ../super-exec-worktree
   ```

   If the worktree has uncommitted changes, git will refuse the remove unless
   `--force` is passed. Confirm the worktree is clean (or intentionally
   discard the changes) before removing.

3. **Prune stale entries.** After removal, run:

   ```
   git worktree prune
   ```

   This removes any leftover administrative files for worktrees whose
   directories no longer exist.

Both steps run inside a runner subagent. The controller issues no git
commands inline.

---

## 6. Caveats

**One branch per worktree.** Each worktree checks out exactly one branch.
You cannot check out the same branch in two worktrees simultaneously — git
will refuse with an error. If the main checkout already has the branch
checked out, create a new branch for the worktree (use `git worktree add -b`).

**Shared object store.** All worktrees share the same `.git/objects`
directory. A `git gc` in any worktree compacts objects for all of them.
This is normally transparent, but be aware that large fetches or gc runs
in one worktree affect the other.

**Submodules.** If the repo uses submodules, a freshly added worktree does
not automatically initialize them. The runner subagent that sets up the
worktree must run `git submodule update --init` inside the worktree if the
plan requires submodule contents.

**Dependencies.** A new worktree shares the source files but not installed
dependencies. If the project requires `npm install`, `bundle install`, or a
similar step, include it in the worktree setup sequence before the first
implementer task runs.

---

## 7. All git runs in a runner subagent

No git command — `git worktree add`, `git commit`, `git worktree remove`,
`git worktree prune`, or any other — runs inline in the controller. Every
git operation is dispatched to a runner subagent (cheap / script-runner
tier, see the `se-subagent` skill) with the `Task` tool. The runner returns the exit code
and relevant output as structured evidence. The controller reads the
evidence and decides the next step.

This rule applies to the worktree lifecycle as much as to any other
git operation in the workflow.
