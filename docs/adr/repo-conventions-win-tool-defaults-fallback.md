# Repo conventions win; super-exec defaults are fallbacks

super-exec ships a complete set of opinionated default conventions — branch naming, commit format, PR-template handling, verification baseline detection — so it works in any repo out of the box. But every convention-bearing action resolves in precedence order: **the target repo's own skill (followed exactly, every word) → a detected repo pattern → super-exec's default.** The repo's conventions always win; the tool's defaults only fill silence.

We chose this so the tool is adaptable and drop-in across the 7 EarnIn repos, which differ from each other and already own excellent skills (`git-new-branch`, `git-commit-message`, `create-pr`, …). Baking a single fixed convention into the tool would fight each repo and guarantee drift; having no defaults at all would make it useless in a bare repo. Layering complete defaults *under* the repo's conventions gives both: it fits everywhere, and it never overrides a repo that has an opinion.

## Consequences

- super-exec must discover repo skills/conventions at runtime (glob `.claude/skills/*`, read `AGENTS.md`/`CLAUDE.md`, sample git history) before acting on branch/commit/PR/verify/version.
- A repo can change super-exec's behavior simply by adding or editing its own skill — no change to super-exec required.
- The precedence applies not only to convention actions (branch/commit/PR) but to **any task a repo skill covers** (e.g. `create-api-service`, `add-icon`, `component-props-type`). The plan phase enumerates the full repo skill catalog and binds matching skills to tasks, so they are invoked rather than hand-rolled; the implementer is required to honor the binding at execute time.
