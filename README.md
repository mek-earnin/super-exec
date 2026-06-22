# super-exec

super-exec is a guided agent workflow for taking software work from a vague idea to a reviewable pull request. It ships as a Claude Code and Cursor plugin, and gives the agent a disciplined path instead of leaving each session to improvise.

Core flow:

```text
discuss -> plan -> exec -> PR / triage
```

You keep the approval points. super-exec does the research, planning, verification, review, and PR prep in between.

## Why Use It

super-exec is built for teams that want agent speed without constant babysitting:

- Turns loose intent into a reviewed spec before implementation starts.
- Separates WHAT from HOW, then builds from that agreed plan.
- Keeps heavy searches, builds, tests, and reviews out of the main session when possible.
- Verifies with real evidence before claiming work is done.
- Prefers the target repo's own skills and conventions for branches, commits, PRs, tests, and local dev.
- Keeps local execution artifacts local, while specs remain shareable review artifacts.

## Install

Install it per repo:

```text
/plugin marketplace add mek-earnin/super-exec
/plugin install super-exec
```

Open a session in the target repo after install; super-exec orients itself from the repo and plugin context.

### Optional Plugins

super-exec is self-contained. These plugins improve specific workflows when present, and are skipped when absent:

| Plugin | Adds |
|---|---|
| `impeccable` | UI design, build, and critique help for frontend work. |
| `caveman` | Terse, high-signal agent communication. |

If `superpowers` is also installed, super-exec is intended to drive the feature workflow where the two overlap. superpowers remains useful for areas outside that workflow, such as standalone debugging.

## Workflow

### 1. Discuss

Run `/se-discuss` when starting a new feature or behavior change. The agent interviews you until the problem, goals, non-goals, requirements, domain terms, and key decisions are clear. The output is a spec you review before the workflow moves on.

### 2. Plan

Planning turns the approved spec into an implementation and verification plan. It covers architecture, task shape, reuse opportunities, repo skills to invoke, and the evidence needed to prove the work. You review the plan before build work begins.

### 3. Exec

Run `/se-exec` in a fresh session when ready to build. The agent works task by task through implementation, verification, review, fixes, and PR preparation. It keeps the spec and plan as the source of truth for scope.

### 4. PR / Triage

The workflow can open a draft PR when the build is ready. After a PR exists, `/se-pr-triage` helps process review comments and CI failures without mixing post-PR work back into the build session.

## Entrypoints

| Entrypoint | Use it for |
|---|---|
| `/se-discuss` | Start from an idea, ticket, or desired change and produce a reviewed spec. |
| `/se-plan` | Re-enter or revise planning for an existing spec. |
| `/se-exec` | Build from a reviewed plan, verify the work, review it, and prepare the PR. |
| `/se-pr-triage` | Handle review comments and CI failures after a PR is open. |

Most users start with `/se-discuss`, then follow the prompts. You can also describe the work naturally and let the agent choose the matching entrypoint.

## Artifacts

The durable team-facing artifact is the spec in `docs/specs/`. Local plans, handoffs, and session state live under `.super-exec/` and are not meant to be committed.

Detailed workflow contracts and implementation-specific behavior live in the source-of-truth files:

- `docs/specs/0001-core-workflow.md`
- `plugin/skills/*/SKILL.md`
- skill-owned templates and reference files under `plugin/skills/`

Keep this README as a landing page. If workflow details change, update the spec and skills first.
