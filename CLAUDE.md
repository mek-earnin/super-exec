## Workflow
- Utilize subagents whenever possible especially when tasks can be done in parallel
- Utilize subagents to preserve contexts, choose model correctly (same rule as `@./plugin/skills/se-subagent/SKILL.md`)
- Gradually commit finished task as a checkpoint. It should be meaningful work and it would be scoped to specific chunk of work. Never commit everything including unrelated things in one commit.
- When bumping a version, always use `@devtools/bump-version.sh` 

## Preventing out of sync data
When plugin is updated
- Always update related specs in `docs/specs`
- Always update `README.md`