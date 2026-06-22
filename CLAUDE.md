## Workflow
- Utilize subagents whenever possible especially when tasks can be done in parallel
- Utilize subagents to preserve contexts, choose model correctly (same rule as `@./plugin/skills/se-subagent/SKILL.md`)
- Gradually commit finished task as a checkpoint. It should be meaningful work and it would be scoped to specific chunk of work. Never commit everything including unrelated things in one commit.
- When bumping a version, always use `@devtools/bump-version.sh` 

## Preventing out of sync data
When plugin is updated
- Always update related specs in `docs/specs` if it's outdated or some part is not true anymore. The spec should provide goal and intention, not minor implementation details, so it shouldn't need much update unless there's a change in direction.
- Always update `README.md` if the content is not true any more. Keep it overview like marketing landing page, don't explain too much too deep. It shouldn't be a burden we have to keep updating. It should give the even more brief version of the spec but focusing on the plugin user perspective.