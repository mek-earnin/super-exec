---
name: se-local-ignore
description: Load when a super-exec step needs to keep the local-only `.super-exec/` directory out of git — at session activation right after writing `.super-exec/active`, or whenever a step first creates `.super-exec/`. Not user-invokable.
user-invocable: false
---

# se-local-ignore — keep `.super-exec/` out of git (super-exec internal)

Keep local-only working dir `.super-exec/` out of git via repo-local, uncommitted `.git/info/exclude` — never team-shared `.gitignore`.

At session activation, right after `.super-exec/active` is written, **fire `@./ensure-local-ignore` (see [@./ensure-local-ignore](./ensure-local-ignore)) as a background job and continue immediately** — run it via the Bash tool with `run_in_background: true`. It is fire-and-forget: never block the session (or any subagent) on it, never wait for its output, and never gate the driver's first real step on it. Safe to run unconditionally — idempotent, a no-op outside a git repo, always exits 0.

Run it as a backgrounded Bash job **only** — not in the foreground, not with a trailing `&` (use the `run_in_background` parameter, which actually detaches), not via a subagent, and not through the commit guard.

**Hard rule:** never commit `.super-exec/`; never add it to the team-shared `.gitignore` — it belongs only in the repo-local, uncommitted `.git/info/exclude`.
