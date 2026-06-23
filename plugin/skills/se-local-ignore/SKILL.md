---
name: se-local-ignore
description: Internal reference for super-exec skills — the single owner of keeping the local-only working dir `.super-exec/` out of git via the repo-local, uncommitted `.git/info/exclude` (never the team-shared `.gitignore`). Apply this at session activation, immediately after writing `.super-exec/active`, and any time a super-exec step first creates `.super-exec/`. Not user-invokable.
user-invocable: false
---

# se-local-ignore — keep `.super-exec/` out of git (super-exec internal)

Keep super-exec's local-only working dir `.super-exec/` out of git via the repo-local, uncommitted `.git/info/exclude` — never the team-shared `.gitignore`.

At session activation, right after `.super-exec/active` is written, execute the `@./ensure-local-ignore` script (see [@./ensure-local-ignore](./ensure-local-ignore)) as a **background** shell, non-blocking. It is idempotent, a no-op outside a git repo, and exits 0, so it is safe to run unconditionally.

Run it directly as a background shell — **not** via a subagent, and **not** through the commit guard.

**Hard rule:** never commit `.super-exec/`; never add it to the team-shared `.gitignore`.
