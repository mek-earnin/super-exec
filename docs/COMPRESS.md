> **Living document.** Update as compression principles are learned or refined.

# Compression Principles

Compress super-exec skill files **without changing behavior**. A skill has two halves with different invariants:

- **`description` frontmatter = WHAT / WHEN** — what the skill is for and when to invoke it. Loaded at **session init** every session, so compressing it directly cuts init cost.
- **body = HOW** — the mechanism an agent follows once invoked. Loaded **on invoke** only.

(Exception: super-exec's SessionStart hook always injects `using-super-exec/SKILL.md`, plus `references/cursor-tools.md` on Cursor — those bodies are init cost too.)

---

## 1. Universal principles (any compression)

- **Lossless.** Cut words, never substance — same behavior as the original.
- **Justify every token.** If removing a word, phrase, or example changes nothing, remove it.
- **Merge redundancy.** Never say the same thing twice; drop synonym pairs, keep one (e.g. "change/modify" → "change").
- **Prefer shorter words.** e.g. "Use" over "Invoke". Terse, imperative.
- **Verify against a baseline.** Diff against the pre-compression version; confirm nothing of substance was dropped or altered.

---

## 2. Skill description (WHAT / WHEN)

### Golden rule — WHAT/WHEN, not HOW
A description's only job is to help an agent decide: *does this situation match? → invoke this skill.* Keep what it is for and when to use it; move pure **mechanism** to the body (subagents, marker writes, internal loop/track names, ordered steps).

> **Decision-scope is NOT HOW.** The *areas a skill checks or decides* are WHAT/WHEN — each area is its own trigger — even when they look like mechanism. Don't strip them. (This bit us: se-plan's scope was narrowed to "architecture", dropping **verification**; se-review was cut to a bare "code review", dropping arch-gate, deep-review, impeccable UI lens, severity, and the re-review loop.)

### Lossless-for-selection (the crucial invariant)
Compression must **never** change which skill an agent selects, or when. Every triggering scenario in the original must survive. "Triggering scenario" is broader than quoted phrases:

- Quoted example phrases and backticked commands
- Described situations/intents even if unquoted (e.g. "checkpoint work", "change existing behavior")
- Alternate invocation modes (e.g. "re-plan an existing spec without re-discussing")
- Entry-condition cues that disambiguate a skill from its siblings

Audit against the pre-compression baseline to confirm no scenario was dropped or narrowed.

### Keep (earns its place)
- Every literal/quoted trigger phrase, **verbatim**; backticked commands
- Entry conditions — the actual WHEN
- Distinct scenario variants and alternate invocation modes
- The skill's **full decision-scope** — every area it decides (each is a trigger); never narrow to a subset
- Sibling-disambiguation cues and selection-affecting constraints
- The `Not user-invokable` marker on internal skills

### Remove
- HOW/mechanism (see golden rule)
- Filler that changes nothing: "immediately", "genuinely", "before proceeding", "whether"
- Position/framing labels already implied by the entry condition (e.g. "Workflow entry point", "Second step")
- Restatements that duplicate an entry condition

### YAML safety
- **Never** put `": "` (colon + space) in a description value — it can break frontmatter parsing. Use an em dash, comma, or rephrase.
- Keep each description a single-line scalar; don't start the value with a YAML-special char (`"`, `{`, `[`, `#`, `>`, `|`, `&`, `*`, `!`, `%`, `@`).
- Prefer the opener "Use when …".

### Checklist (after compressing descriptions)
- [ ] Only `description:` lines changed (no body/frontmatter drift)
- [ ] No `": "` in any value; each is a single-line scalar
- [ ] Every quoted/backticked trigger preserved verbatim
- [ ] Every original triggering scenario still covered (diff vs baseline)
- [ ] Internal skills still marked `Not user-invokable`

---

## 3. Skill body (HOW)

The body is the mechanism once invoked. Structure for fast branch selection and faithful execution — not for init-token savings.

### Decision spine + detail sections
When the body encodes branching or control-flow:
- Lead with a terse **decision spine** — numbered steps in order, `→` for branches, salient markers (`STOP`, `skip the rest`, `100%`).
- Cross-reference spine to detail below (e.g. `(§1)`, `(§2)`).
- The spine lets an agent pick the right branch fast and legitimately skip executing sections that don't apply.

### Structure vs prose (hybrid)
- **Structured blocks** (if/else, ordered steps, arrows) for deterministic, mechanical steps — remove inference.
- **Prose** for judgment-laden nuance — definitions, edge cases, "what counts as X", rationale — where fragments lose meaning.

### Overview steers; it doesn't save load tokens
Bodies load in full on invoke — a spine adds tokens, not fewer. Payoff is faster, steadier decision-making and authorizing skips. Worth the few extra tokens for control-heavy skills; not for short linear ones.

### Spine = map; detail = law
Never restate the same rule verbatim in spine and detail — duplication drifts and violates justify-every-token. Merge the repeated meaning into one place: keep the authoritative detail with its nuances, and trim the echo — the spine stays navigation-only.

### Enforcement prose — readable, not telegraphic
For hard rules and multi-step sequences where fragment order could be misread, keep readable sentences. Telegraphic compression suits overviews and mechanical lists; risky for normative/enforcement text.

### Opening lines — load-bearing vs redundant
Body openings often mix redundant restatement (scope already in `description`/H1, roadmaps duplicated by dedicated sections) with load-bearing rules stated nowhere else (e.g. a blunt prohibition). Cut the redundant framing; keep or relocate load-bearing clauses so they survive.

### Checklist (after compressing bodies)
- [ ] Control-flow skills have a decision spine before detail sections; spine cross-references detail
- [ ] Spine navigates only; detail sections hold authoritative rules (no verbatim echo)
- [ ] Structured blocks for mechanical steps; prose kept where judgment matters
- [ ] Enforcement/normative text is readable sentences, not fragment chains
- [ ] Opening framing trimmed; load-bearing rules preserved
- [ ] Verify against baseline — same behavior as pre-compression version
