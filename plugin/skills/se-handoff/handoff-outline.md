# handoff.md Content Outline

The file must contain the following sections in order:

```
# Handoff — <plan-dir name>

## Session State
- Branch: <branch-name>
- Base: <base-branch>
- Plan: .super-exec/<feature>/<plan-dir>/plan.md
- Review-before-commit: on | off
- Auto-PR: on | off
- Impeccable opt-in: opted-in | opted-out | not asked

## Completed Tasks
For each done task:
### <Task name>
- Status: DONE
- Evidence: <brief summary — exit code, test count, key output line>

## Next Unstarted Task
### <Task name>
(copy or summarize the full task description from plan.md so the next session
 does not need to re-read the plan to understand the scope)

## In-Flight Decisions
<Free prose. Record any design choices, scope clarifications, or discoveries
 made during this session that are not visible in committed code or plan.md.
 If nothing, write "None.">

## Open Follow-Ups
<Bulleted list of deferred items, known gaps, or things to revisit.
 If none, write "None.">
```
