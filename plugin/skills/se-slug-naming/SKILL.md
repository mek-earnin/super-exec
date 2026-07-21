---
name: se-slug-naming
description: Shared naming-convention authority for every author-chosen super-exec name (feature slug, spec name, ADR slug, plan-name) — caveman-compressed, prose-only. Load when an authoring skill needs to name a slug or plan. Not user-invokable.
user-invocable: false
---

# se-slug-naming — caveman-compressed naming (super-exec internal)

Single naming-convention authority. Every author-chosen name — **feature slug**, **spec name**, **ADR slug**, **plan-name** — follows this rule. Authoring skills reference `/se-slug-naming` instead of restating it.

PROSE-ONLY: no bundled script. Compression is a semantic author choice, not a deterministic transform.

## Rule

Caveman-compressed: lowercase, hyphen-joined words; filler dropped so only technical substance remains. Same drop logic as caveman full, minus symbols.

1. Lowercase; join words with `-`.
2. **DROP:**
   - articles: `a` / `an` / `the`
   - be-verbs / copulas: `is` / `are` / `was` / `were` / `be` / `been` / `being`
   - filler: `just` / `really` / `basically` / `actually` / `simply`
   - pleasantries
   - hedging
3. Keep technical terms exact; prefer short synonyms.
4. Characters limited to `[a-z0-9-]` (no symbols).

## Example

`local-only-plans-specs-are-the-shared-contract` → `local-only-plans-specs-shared-contract`

(`are` and `the` dropped; technical substance kept.)

## Forward-only

Governs **newly-created** names only. Migration never recompresses existing names — it only strips leading numbers. An author may compress an old name by hand if desired.

## Self-contained

This skill **embeds** the drop list above. It borrows caveman-full's logic but does **NOT** depend on the optional external `caveman` skill (plugin users may not have it).
