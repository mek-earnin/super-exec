---
name: se-local-ignore
description: Load when a super-exec step needs to keep the local-only `.super-exec/` directory out of git — at session activation right after writing `.super-exec/active`, or whenever a step first creates `.super-exec/`. Not user-invokable.
user-invocable: false
---

# se-local-ignore — keep `.super-exec/` out of git (super-exec internal)

Keep local-only working dir `.super-exec/` out of git via repo-local, uncommitted `.git/info/exclude` — never team-shared `.gitignore`.

At session activation, right after `.super-exec/active` written, run `@./ensure-local-ignore` (see [@./ensure-local-ignore](./ensure-local-ignore)) as a **background** shell, non-blocking. Safe to run unconditionally — idempotent, no-op outside git repo, exits 0.

Run it directly as a background shell — **not** via a subagent, and **not** through the commit guard.

**Hard rule:** never commit `.super-exec/`; never add it to the team-shared `.gitignore`.
