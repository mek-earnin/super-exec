# Plan Template

Write the plan file using exactly this structure. Sections must appear in this order. No additional top-level sections.

```markdown
# <Plan name>

## Goal
<1-3 sentences. Link to the spec: `docs/specs/<feature>.md`>

## Architecture
<Components, responsibilities, data flow — prose + mermaid or ASCII diagrams.
Folder/file structure as ASCII tree. Signatures or pseudo-code only where they
clarify architecture — never as implementation scaffolding.>

## Data Flow
<Diagram (mermaid or ASCII) showing how data moves through the system for the
primary happy path and the main error path.>

## Tasks
<Overview-level tasks. Each task states: what to accomplish, which repo skills
to invoke (MUST invoke `<skill-name>` before ...), dependency notes, and its
own verification step. No copy-paste code. No file manifests.>

## Verification
<Baseline commands (exact). Task-specific checks. Runner/judge split.
Evidence format expected from the runner.>
```
