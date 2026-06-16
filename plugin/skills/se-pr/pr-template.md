# PR Template Reference (Path B)

Used by se-pr step 3 when no repo `create-pr` skill is present.

---

## Default Title Format

```
<type>(<optional-scope>): <brief summary> - <TICKET-a>, <TICKET-b>
```

**Types:** `feat`, `fix`, `ci`, `test`, `chore`

**Scope rules:**
- Monorepo, exactly one app/package changed → include the app/package name as scope
- Monorepo, multiple apps/packages changed → omit scope entirely
- Standalone repo → omit scope entirely (regardless of what changed)

**Tickets:** comma-separated ticket IDs (e.g. `ENG-123, ENG-456`). Use `NO_TICKET` if none.

**Examples:**
```
feat(payments): add retry logic for failed ACH transfers - ENG-1234
fix: correct null pointer in user session cleanup - ENG-5678, ENG-5679
chore: upgrade Node to 20.x - NO_TICKET
```

---

## Body Rules

1. Locate `pull_request_template.md` — typically at `.github/pull_request_template.md`.
2. Count its top-level `##` headings. Your draft must mirror those sections **1:1**: exactly that many primary sections, same headings, same order.
3. No extra primary `##` sections. Sub-sections (`###`) and detail within a section are allowed.
4. If no template exists, write a concise structured description with these minimum sections:
   - **What changed** — summary of the change
   - **Why** — motivation or linked ticket
   - **How to test** — steps or pointers for reviewers
5. If UI changes were made and screenshots exist from the verify phase, embed them in the template's testing or screenshots section (or a `###` sub-section if no dedicated slot exists).
6. Always create the PR in `--draft` mode.
