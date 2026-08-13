## Workflow
- Utilize subagents whenever possible especially when tasks can be done in parallel
- Utilize subagents to preserve contexts, choose model correctly (same rule as `@./plugin/skills/se-subagent/SKILL.md`)
- Gradually commit meaningful supporting checkpoints. Scope each commit to one coherent change; never combine unrelated work.
- Only reviewed changes may be committed. Route **every** commit — inside super-exec or any ad-hoc / out-of-workflow commit — through `@./plugin/skills/se-commit/SKILL.md`; never `git commit` directly. se-commit is enforcement **gate**, not reviewer: staged paths need review evidence. An ad-hoc checkpoint lacking evidence gets one or two fresh reviewers over staged diff, resolving Critical/Important. Any fix invalidates prior evidence for affected paths and needs fresh review.
- Before asking to commit, make sure all changes you want to commit have been reviewed and fixed, so the workflow is smoother. Avoid asking to commit just to hit the commit review gate.
- When bumping a version, always use `@devtools/bump-version.sh` 

## Preventing out of sync data
When plugin is updated
- Always update related specs in `docs/specs` if it's outdated or some part is not true anymore. The spec should provide goal and intention, not minor implementation details, so it shouldn't need much update unless there's a change in direction.
- Always update `README.md` if the content is not true any more. Keep it overview like marketing landing page, don't explain too much too deep. It shouldn't be a burden we have to keep updating. It should give the even more brief version of the spec but focusing on the plugin user perspective.