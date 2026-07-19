# Worktree — Isolated Build Reference

The `--worktree` opt-in path for se-exec. Default: se-exec runs directly in the
main checkout. Pass `--worktree` when the build needs a fully isolated working
tree — e.g. parallel sessions touching the same files, or a risky refactor that
shouldn't disturb the main checkout until the plan is verified green.

---

## 1. Why and when

A git worktree is a second checkout of the same repo sharing the same object
store. Own working tree, own HEAD → uncommitted changes in one worktree don't
appear in the other.

Use `--worktree` when:

- Another session (or long-running dev-server) is modifying files in the main
  checkout and you want the build isolated from that churn.
- The plan's changes are risky to leave half-applied in the main tree — the
  worktree is a staging area until all tasks are green.
- You want to run the build and the existing session side by side with no
  context leakage between the two working directories.

Do not use `--worktree` by default. It adds setup/teardown overhead and an extra
branch to manage; the opt-in flag keeps the common path simple.

---

## 2. Create the worktree

Place the worktree **outside** the main repo directory (a sibling, not a
subdirectory) so it is never picked up by the main tree's file globs, watch
processes, or package-manager installs.

**Add a worktree on an existing branch:**

```
git worktree add ../super-exec-worktree <branch>
```

**Add a worktree on a new branch, based on the current branch:**

```
git worktree add -b <new-branch> ../super-exec-worktree <base-ref>
```

Replace `<base-ref>` with the branch or commit the new branch starts from —
typically `HEAD` or `origin/develop`. Worktree directory and branch name are
both required; git won't create one without the other.

All `git worktree add` calls run inside a **runner subagent** (see section 7).
The controller never runs git commands inline.

---

## 3. Work in the worktree

Implementer and runner subagents get the worktree path as their working
directory. All their reads, edits, and shell commands target that path.

`.super-exec/` markers and the plan directory live in the **main repo**, not the
worktree. Guard and controller both resolve `.super-exec/` from the project root
reported by `CLAUDE_PROJECT_DIR`, which points at the main checkout. The worktree
has no `.super-exec/` directory; guards and gate checks still work because they
read from the main repo root.

Pass the worktree path to each subagent explicitly. Do not rely on the subagent
inferring it — state the working directory in the prompt.

---

## 4. Verify and commit

Verification runs in the worktree. The runner subagent executes all baseline and
task-specific commands with the worktree as the working directory, exactly as in
the main checkout. The runner → judge split is unchanged: the runner returns
structured evidence; the judge evaluates it against the spec and plan.

Commits also happen in the worktree, on the worktree's branch, not the main
checkout's branch. Worktree mode does **not** change how commits work — commit
through **`/se-commit`** exactly as in the main checkout. The only
worktree-specific delta: the runner subagent gets the **worktree path** as its
working directory.

---

## 5. Integrate and clean up

When all tasks are committed and outer-review-clean:

1. **Merge or open a PR from the worktree branch.** It's an ordinary git branch —
   treat it as any feature branch: merge into the target branch, or push it and
   open a pull request.

2. **Remove the worktree.** Use `git worktree remove` — do NOT delete the
   directory by hand. Deleting it by hand leaves a stale entry in git's worktree
   list that must be cleaned up manually.

   ```
   git worktree remove ../super-exec-worktree
   ```

   If the worktree has uncommitted changes, git refuses the remove unless
   `--force` is passed. Confirm the worktree is clean (or intentionally discard
   the changes) before removing.

3. **Prune stale entries.** After removal, run:

   ```
   git worktree prune
   ```

   Removes leftover administrative files for worktrees whose directories no
   longer exist.

Both steps run inside a runner subagent. The controller issues no git commands
inline.

---

## 6. Caveats

**One branch per worktree.** Each worktree checks out exactly one branch. You
cannot check out the same branch in two worktrees at once — git refuses with an
error. If the main checkout already has the branch checked out, create a new
branch for the worktree (`git worktree add -b`).

**Shared object store.** All worktrees share the same `.git/objects` directory. A
`git gc` in any worktree compacts objects for all of them — normally
transparent, but large fetches or gc runs in one worktree affect the other.

**Submodules.** If the repo uses submodules, a freshly added worktree does not
auto-initialize them. The runner subagent that sets up the worktree must run
`git submodule update --init` inside the worktree if the plan requires submodule
contents.

**Dependencies.** A new worktree shares source files but not installed
dependencies. If the project needs `npm install`, `bundle install`, or similar,
include it in the worktree setup before the first implementer task runs.

---

## 7. All git runs in a runner subagent

No git command — `git worktree add`, `git commit`, `git worktree remove`,
`git worktree prune`, or any other — runs inline in the controller. Every git
operation is dispatched to a runner subagent (cheap / script-runner tier, see the
`/se-subagent` skill) with the `Task` tool. The runner returns the exit code and
relevant output as structured evidence; the controller reads it and decides the
next step.

This applies to the worktree lifecycle as much as any other git operation in the
workflow.
