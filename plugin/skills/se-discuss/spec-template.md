# Spec Template

Write the spec file using exactly this structure. Sections must appear in this order. No additional sections.

```markdown
# <Feature>
> Ticket: INTCOMP-####  ·  Status: active

## Problem / Why

## Goals

## Non-goals (out of scope)

## Behavior / Requirements
<!-- Acceptance criteria only. No HOW — no architecture, no file layout, no tech choices. -->

## Domain terms
<!-- Entries here are mirrored to CONTEXT.md -->

## Decisions
<!-- Hard, surprising, trade-off decisions only. Others go to ADRs in docs/adr/. -->
```

The **Behavior / Requirements** section contains acceptance criteria with NO HOW. If a requirement implies an implementation (e.g., "use a queue"), extract the underlying behavior ("retries must be durable across process restarts") and state that instead. Architecture and implementation details belong to se-plan.
