# Skills-only entrypoints; no thin command wrappers

super-exec exposes its three entrypoints (`se-discuss`, `se-plan`, `se-exec`) as **skills only**, each writing the `.super-exec/active` session marker on its own entry. We dropped the originally-planned thin slash-commands that wrapped each skill to write the marker. The reason: a separate command layer that does nothing but write a marker and call a same-named skill is confusing, and skills are already invocable as `/se-discuss` — so one concept (the skill) is easier to reason about, and the behavior is identical whether the user invokes it manually or the model auto-invokes it.

## Considered options

- **Command + skill split (original plan).** A `/se-discuss` command writes the marker, then invokes the `se-discuss` skill (pure behavior). Gives intent-gating: the marker side-effect fires only on an explicit slash invocation, never on model auto-invocation. Rejected as an extra, same-named layer that duplicates the entrypoint concept for one line of side-effect.
- **Skills only (chosen).** The skill writes the marker as its first action. One concept, uniform behavior across manual and automatic invocation.

## Consequences

- Invoking a driver skill — manually *or* via model auto-invocation on description match — is treated as an explicit start: it writes `.super-exec/active` and the guards go live. This is intended, not a side-effect to suppress.
- Marker provenance shifts from "a `/se-*` command" to "a `/se-*` driver skill's session-activation step." The marker lifecycle is otherwise unchanged (`se-pr` clears `active` on PR completion; `session-start` runs the stale-TTL sweep; `se-handoff` never clears it).
- Slash-argument substitution (`$ARGUMENTS`) is lost; the skills instead read any ticket id / `--worktree` flag from the invocation or conversation and confirm.
- The plugin manifests declare no `commands/` directory; the surface is skills + hooks + references only.
