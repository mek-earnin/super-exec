---
name: se-get-config
description: Load when a super-exec skill needs the merged effective se-config (commit/placement/review/PR keys) as JSON — invoke at any decision point that branches on config. Not user-invokable.
user-invocable: false
---

# se-get-config — merged effective se-config (super-exec internal)

Single merge authority for tiered `se-config`. Skills that decide commit, placement, review, or PR behavior consult this skill at the decision point and branch on the returned values.

**Invoke `@./get-merged-config` (see [@./get-merged-config](./get-merged-config))** via the Bash tool. Capture stdout — that is the effective config JSON. No args.

## Output

One compact JSON object on stdout with exactly these keys (deterministic order):

```json
{"commitSpec":…,"commitPlan":…,"humanReviewBeforeCheckpointCommit":…,"autoCreatePr":…}
```

Each value is exactly `true`, `false`, or `"ask"`. Every key always resolves — never omit a key, never print diagnostics.

## Lenient merge

Tiers, highest first:

1. **local** — `<repo>/.super-exec/se-config.local.json`
2. **user** — `~/.super-exec/se-config.json`
3. **default** — bundled `se-config.default.json` beside the script

Per key: use the highest-priority tier that supplies a **valid** value; otherwise fall through. Embedded defaults backstop every key.

- Malformed JSON → skip the **entire** tier.
- Well-formed file with an invalid value for one key → treat that key as absent; valid sibling keys still apply.
- Allowed values exactly `true` | `false` | `"ask"` — no coercion (`"true"`, `1`, etc. are invalid).
- Missing tier files are fine (treated as absent).

Repo root resolution mirrors `branch-context`: `CLAUDE_PROJECT_DIR` → `CURSOR_PROJECT_DIR` → cwd, then git toplevel when available.
