# Plans are local-only; specs are the shared contract

The spec for a feature is committed to `docs/specs/<feature>.md` and is the durable, team-shared contract. Plans live gitignored under `.super-exec/<feature>/<YYYY-MM-DD>-<plan-name>/` and are per-effort scaffolding — one feature has many plans over time (≈ one plan per implementation effort per PR).

We keep plans local because they are ephemeral implementation detail whose commit would add repo and PR churn, and because teammates only ever need the spec. It follows that **the spec must never reference a plan** — such a reference would dangle for everyone except the author, who is the only one with the plan on disk.

## Consequences

- The trade-off accepted: we lose in-repo traceability of which plan produced which change, in exchange for a clean shared surface and noise-free history. The spec's own git history records what changed and when.
- super-exec keeps `.super-exec/` out of git via the repo-local, **uncommitted** `.git/info/exclude` rather than the team-shared `.gitignore` — a local-only artifact deserves a local-only ignore, so no tool-specific line lands in a file teammates share. The SessionStart hook writes this exclude entry idempotently on **every** session (every entrypoint), so the ignore does not depend on the `se-shape` branch gate having run; it also degrades safely to a no-op outside a git repo. The plan must be self-contained enough to survive the session boundary and a handoff/resume without the controller's prior context.
  - Trade-off: a per-clone `.git/info/exclude` entry is not shared with teammates. This is acceptable because only a super-exec user creates `.super-exec/`, and that user's own SessionStart hook ensures the exclude on their clone; a teammate without super-exec never creates the dir, so has nothing to ignore.
