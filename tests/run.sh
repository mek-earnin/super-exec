#!/usr/bin/env bash
# tests/run.sh — Tier-1 regression harness for super-exec plugin.
# Run from anywhere: bash tests/run.sh
# Exits 0 if all checks pass; non-zero if any fail.

set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0
FAILURES=()

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); FAILURES+=("$1"); }

# ---------------------------------------------------------------------------
# Check 1 — Manifest lint
# ---------------------------------------------------------------------------
echo ""
echo "Check 1: Manifest lint"

# Files that must parse as valid JSON
json_files=(
  "${REPO_ROOT}/.claude-plugin/marketplace.json"
  "${REPO_ROOT}/plugin/.claude-plugin/plugin.json"
  "${REPO_ROOT}/plugin/hooks/hooks.json"
  "${REPO_ROOT}/plugin/hooks/hooks-cursor.json"
  "${REPO_ROOT}/plugin/.cursor-plugin/plugin.json"
)

for f in "${json_files[@]}"; do
  rel="${f#${REPO_ROOT}/}"
  if node -e "JSON.parse(require('fs').readFileSync('${f}','utf8'))" 2>/dev/null; then
    pass "valid JSON: ${rel}"
  else
    fail "invalid JSON: ${rel}"
  fi
done

# marketplace.json plugins[0].source === "./plugin"
marketplace_source=$(node -e "
  const m = JSON.parse(require('fs').readFileSync('${REPO_ROOT}/.claude-plugin/marketplace.json','utf8'));
  process.stdout.write(m.plugins[0].source);
" 2>/dev/null || echo "ERROR")
if [ "$marketplace_source" = "./plugin" ]; then
  pass "marketplace.json plugins[0].source === \"./plugin\""
else
  fail "marketplace.json plugins[0].source expected \"./plugin\" got \"${marketplace_source}\""
fi

# plugin.json has non-empty name, version, description
plugin_check=$(node -e "
  const p = JSON.parse(require('fs').readFileSync('${REPO_ROOT}/plugin/.claude-plugin/plugin.json','utf8'));
  const issues = [];
  if (!p.name || !p.name.trim()) issues.push('name empty');
  if (!p.version || !p.version.trim()) issues.push('version empty');
  if (!p.description || !p.description.trim()) issues.push('description empty');
  if (issues.length) { process.stdout.write(issues.join(', ')); process.exit(1); }
  process.stdout.write('ok');
" 2>/dev/null || echo "ERROR")
if [ "$plugin_check" = "ok" ]; then
  pass "plugin.json has non-empty name, version, description"
else
  fail "plugin.json missing required fields: ${plugin_check}"
fi

# ---------------------------------------------------------------------------
# Check 2 — Frontmatter
# ---------------------------------------------------------------------------
echo ""
echo "Check 2: Frontmatter"

skill_count=0
skill_fail=0
while IFS= read -r -d '' skill_md; do
  skill_count=$((skill_count + 1))
  rel="${skill_md#${REPO_ROOT}/}"
  result=$(node -e "
    const fs = require('fs');
    const content = fs.readFileSync('${skill_md}','utf8');
    // Must start with ---
    if (!content.startsWith('---')) {
      process.stdout.write('no frontmatter');
      process.exit(1);
    }
    // Find closing ---
    const rest = content.slice(3);
    const end = rest.indexOf('\n---');
    if (end === -1) {
      process.stdout.write('unclosed frontmatter');
      process.exit(1);
    }
    const fm = rest.slice(0, end);
    // Extract name: and description:
    const nameMatch = fm.match(/^name:\s*(.+)/m);
    const descMatch = fm.match(/^description:\s*(.+)/m);
    if (!nameMatch || !nameMatch[1].trim()) {
      process.stdout.write('missing or empty name:');
      process.exit(1);
    }
    if (!descMatch || !descMatch[1].trim()) {
      process.stdout.write('missing or empty description:');
      process.exit(1);
    }
    process.stdout.write('ok');
  " 2>/dev/null || echo "ERROR")
  if [ "$result" = "ok" ]; then
    pass "frontmatter OK: ${rel}"
  else
    fail "frontmatter problem in ${rel}: ${result}"
    skill_fail=$((skill_fail + 1))
  fi
done < <(find "${REPO_ROOT}/plugin/skills" -name "SKILL.md" -print0 2>/dev/null)

if [ "$skill_count" -eq 0 ]; then
  fail "no SKILL.md files found under plugin/skills/"
fi

# ---------------------------------------------------------------------------
# Check 3 — Guard unit tests
# ---------------------------------------------------------------------------
echo ""
echo "Check 3: Guard unit tests"

GUARD="${REPO_ROOT}/plugin/hooks/guard"
FIXTURES_DIR="${REPO_ROOT}/tests/fixtures/guard"
EXPECTATIONS="${FIXTURES_DIR}/expectations.json"

guard_pass=0
guard_fail=0
guard_total=0

# Read the fixture names from expectations.json
fixture_names=$(node -e "
  const e = JSON.parse(require('fs').readFileSync('${EXPECTATIONS}','utf8'));
  Object.keys(e.fixtures).forEach(k => console.log(k));
" 2>/dev/null)

while IFS= read -r fixture_name; do
  [ -z "$fixture_name" ] && continue
  guard_total=$((guard_total + 1))

  fixture_file="${FIXTURES_DIR}/${fixture_name}"
  if [ ! -f "$fixture_file" ]; then
    fail "guard[$fixture_name]: fixture file not found"
    guard_fail=$((guard_fail + 1))
    continue
  fi

  # Read expectations for this fixture
  exp=$(node -e "
    const e = JSON.parse(require('fs').readFileSync('${EXPECTATIONS}','utf8'));
    const f = e.fixtures['${fixture_name}'];
    if (!f) { process.stdout.write('NOT_FOUND'); process.exit(1); }
    // Output: harness|activeMarker|gateOpenMarker|expectDecision|nudge|failClosed
    const active = f.markers.active ? '1' : '0';
    const gateOpen = f.markers['gate-open'] ? '1' : '0';
    process.stdout.write([f.harness, active, gateOpen, f.expect, f.nudge, f.failClosed ? '1' : '0'].join('|'));
  " 2>/dev/null || echo "ERROR")

  if [ "$exp" = "ERROR" ] || [ "$exp" = "NOT_FOUND" ]; then
    fail "guard[$fixture_name]: failed to read expectations"
    guard_fail=$((guard_fail + 1))
    continue
  fi

  harness=$(echo "$exp" | cut -d'|' -f1)
  active_marker=$(echo "$exp" | cut -d'|' -f2)
  gate_open_marker=$(echo "$exp" | cut -d'|' -f3)
  expect_decision=$(echo "$exp" | cut -d'|' -f4)
  nudge=$(echo "$exp" | cut -d'|' -f5)
  fail_closed=$(echo "$exp" | cut -d'|' -f6)

  # Create temp project dir with marker state
  tmp_dir=$(mktemp -d)
  mkdir -p "${tmp_dir}/.super-exec"

  if [ "$active_marker" = "1" ]; then
    touch "${tmp_dir}/.super-exec/active"
  fi
  if [ "$gate_open_marker" = "1" ]; then
    touch "${tmp_dir}/.super-exec/gate-open"
  fi

  # Run the guard with appropriate env
  if [ "$harness" = "cursor" ]; then
    guard_output=$(
      env -i \
        PATH="$PATH" \
        HOME="${HOME:-/tmp}" \
        CURSOR_PROJECT_DIR="$tmp_dir" \
        CURSOR_PLUGIN_ROOT="${REPO_ROOT}/plugin" \
        "$GUARD" < "$fixture_file" 2>/dev/null
    ) || true
  else
    # CC: ensure CURSOR_* are unset; set CLAUDE_PROJECT_DIR
    guard_output=$(
      env -i \
        PATH="$PATH" \
        HOME="${HOME:-/tmp}" \
        CLAUDE_PROJECT_DIR="$tmp_dir" \
        "$GUARD" < "$fixture_file" 2>/dev/null
    ) || true
  fi

  rm -rf "$tmp_dir"

  # Assert the decision
  check_name="guard[${fixture_name}]"
  case "$expect_decision" in
    deny)
      # Output must parse as JSON with the right deny shape
      decision_val=$(node -e "
        const out = $(printf '%s' "$guard_output" | node -e "
          let d=''; process.stdin.on('data',c=>d+=c); process.stdin.on('end',()=>{
            try { JSON.parse(d); process.stdout.write(JSON.stringify(d)); }
            catch(e) { process.stdout.write('\"\"'); }
          });
        " 2>/dev/null || echo '""');
        if (!out) { process.stdout.write('no_output'); process.exit(0); }
        try {
          const o = JSON.parse(out);
          if (o.hookSpecificOutput && o.hookSpecificOutput.permissionDecision === 'deny') {
            process.stdout.write('deny');
          } else if (o.permission === 'deny') {
            process.stdout.write('deny_cursor:' + (o.failClosed ? '1' : '0'));
          } else {
            process.stdout.write('not_deny:' + JSON.stringify(o));
          }
        } catch(e) { process.stdout.write('parse_error'); }
      " 2>/dev/null || echo "error")

      if echo "$decision_val" | grep -q '^deny'; then
        # For cursor, also check failClosed
        if [ "$harness" = "cursor" ] && [ "$fail_closed" = "1" ]; then
          if echo "$decision_val" | grep -q 'deny_cursor:1'; then
            pass "$check_name → deny (failClosed:true)"
            guard_pass=$((guard_pass + 1))
          else
            fail "$check_name → expected deny+failClosed:true, got: ${decision_val}"
            guard_fail=$((guard_fail + 1))
          fi
        else
          pass "$check_name → deny"
          guard_pass=$((guard_pass + 1))
        fi
      else
        fail "$check_name → expected deny, got: ${decision_val} (output: ${guard_output:0:120})"
        guard_fail=$((guard_fail + 1))
      fi
      ;;

    allow)
      # Parse the output (may be empty = silent allow)
      allow_result=$(node -e "
        const raw = $(printf '%s' "$guard_output" | node -e "
          let d=''; process.stdin.on('data',c=>d+=c); process.stdin.on('end',()=>{
            process.stdout.write(JSON.stringify(d));
          });
        " 2>/dev/null || echo '""');
        const nudge = '${nudge}';
        if (!raw || !raw.trim()) {
          // Silent allow
          if (nudge === 'none') {
            process.stdout.write('ok:silent_allow');
          } else {
            process.stdout.write('fail:expected_nudge_' + nudge + '_but_silent');
          }
          process.exit(0);
        }
        try {
          const o = JSON.parse(raw);
          const pd = o.hookSpecificOutput && o.hookSpecificOutput.permissionDecision;
          if (pd && pd !== 'allow') {
            process.stdout.write('fail:decision_is_' + pd);
            process.exit(0);
          }
          const ctx = o.hookSpecificOutput && o.hookSpecificOutput.additionalContext;
          if (nudge === 'none') {
            if (ctx && ctx.trim()) {
              process.stdout.write('fail:expected_no_nudge_but_got_context');
            } else {
              process.stdout.write('ok:allow_no_nudge');
            }
          } else if (nudge === 'n1') {
            if (!ctx || !ctx.trim()) {
              process.stdout.write('fail:n1_expected_additionalContext_but_empty');
            } else if (!/delegat|throwaway|subagent|build|test/i.test(ctx)) {
              process.stdout.write('fail:n1_context_does_not_mention_delegate_build_test');
            } else {
              process.stdout.write('ok:n1_nudge');
            }
          } else if (nudge === 'n2') {
            if (!ctx || !ctx.trim()) {
              process.stdout.write('fail:n2_expected_additionalContext_but_empty');
            } else if (!/git|pr|skill|repo/i.test(ctx)) {
              process.stdout.write('fail:n2_context_does_not_mention_git_pr_skill');
            } else {
              process.stdout.write('ok:n2_nudge');
            }
          } else if (nudge === 'n3') {
            if (!ctx || !ctx.trim()) {
              process.stdout.write('fail:n3_expected_additionalContext_but_empty');
            } else if (!/spec|what-only|code|plan|docs\/specs/i.test(ctx)) {
              process.stdout.write('fail:n3_context_does_not_mention_spec_code_plan');
            } else {
              process.stdout.write('ok:n3_nudge');
            }
          } else {
            process.stdout.write('ok:allow');
          }
        } catch(e) {
          process.stdout.write('fail:json_parse_error:' + e.message);
        }
      " 2>/dev/null || echo "fail:node_error")

      if echo "$allow_result" | grep -q '^ok:'; then
        pass "$check_name → allow (${allow_result#ok:})"
        guard_pass=$((guard_pass + 1))
      else
        fail "$check_name → ${allow_result} (output: ${guard_output:0:200})"
        guard_fail=$((guard_fail + 1))
      fi
      ;;

    *)
      fail "$check_name: unknown expected decision '${expect_decision}'"
      guard_fail=$((guard_fail + 1))
      ;;
  esac

done <<< "$fixture_names"

echo "  Guard: ${guard_pass}/${guard_total}"

# ---------------------------------------------------------------------------
# Check 4 — Hook-config parity
# ---------------------------------------------------------------------------
echo ""
echo "Check 4: Hook-config parity"

hooks_cc="${REPO_ROOT}/plugin/hooks/hooks.json"
hooks_cursor="${REPO_ROOT}/plugin/hooks/hooks-cursor.json"

# CC: has SessionStart and PreToolUse
cc_has_session=$(node -e "
  const h = JSON.parse(require('fs').readFileSync('${hooks_cc}','utf8'));
  process.stdout.write(h.hooks && h.hooks.SessionStart ? '1' : '0');
" 2>/dev/null || echo "0")

cc_has_guard=$(node -e "
  const h = JSON.parse(require('fs').readFileSync('${hooks_cc}','utf8'));
  const ptu = h.hooks && h.hooks.PreToolUse;
  const found = ptu && ptu.some(entry =>
    entry.hooks && entry.hooks.some(hk => hk.command && hk.command.includes('guard'))
  );
  process.stdout.write(found ? '1' : '0');
" 2>/dev/null || echo "0")

# Cursor: has sessionStart and beforeShellExecution
cursor_has_session=$(node -e "
  const h = JSON.parse(require('fs').readFileSync('${hooks_cursor}','utf8'));
  process.stdout.write(h.hooks && h.hooks.sessionStart ? '1' : '0');
" 2>/dev/null || echo "0")

cursor_has_guard=$(node -e "
  const h = JSON.parse(require('fs').readFileSync('${hooks_cursor}','utf8'));
  const bse = h.hooks && h.hooks.beforeShellExecution;
  const found = bse && bse.some(entry => entry.command && entry.command.includes('guard'));
  process.stdout.write(found ? '1' : '0');
" 2>/dev/null || echo "0")

if [ "$cc_has_session" = "1" ]; then
  pass "hooks.json registers SessionStart"
else
  fail "hooks.json missing SessionStart"
fi

if [ "$cc_has_guard" = "1" ]; then
  pass "hooks.json registers PreToolUse guard"
else
  fail "hooks.json missing PreToolUse guard"
fi

if [ "$cursor_has_session" = "1" ]; then
  pass "hooks-cursor.json registers sessionStart"
else
  fail "hooks-cursor.json missing sessionStart"
fi

if [ "$cursor_has_guard" = "1" ]; then
  pass "hooks-cursor.json registers beforeShellExecution guard"
else
  fail "hooks-cursor.json missing beforeShellExecution guard"
fi

# Parity: both have guard or neither does
if [ "$cc_has_guard" = "$cursor_has_guard" ]; then
  pass "guard parity: both hook configs register the guard"
else
  fail "guard parity mismatch: CC=${cc_has_guard} Cursor=${cursor_has_guard}"
fi

# ---------------------------------------------------------------------------
# Check 5 — Self-containment grep
# ---------------------------------------------------------------------------
echo ""
echo "Check 5: Self-containment grep"

# super-exec stays self-contained, with ONE allowlisted exception: the
# using-super-exec precedence clause names 'superpowers' on purpose — that is
# the single skill-precedence site (ADR superpowers-coinstall-skill-precedence). 'superpowers' in ANY OTHER file
# under plugin/ is a self-containment leak to remove ('impeccable' remains the
# only other allowed external). The allowlist is exactly one file:
ALLOWED_SUPERPOWERS_FILE="plugin/skills/using-super-exec/SKILL.md"

# Hits in plugin/ EXCLUDING the one allowlisted file. Any remaining hit fails.
# (Negative self-test: a planted 'superpowers' reference in any other plugin/
# file lands here and fails the check.)
superpowers_hits=$(grep -rin 'superpowers' "${REPO_ROOT}/plugin/" 2>/dev/null \
  | grep -v "/${ALLOWED_SUPERPOWERS_FILE}:" \
  | head -20 || true)

if [ -z "$superpowers_hits" ]; then
  pass "no 'superpowers' references in plugin/ outside ${ALLOWED_SUPERPOWERS_FILE}"
else
  fail "found 'superpowers' references in plugin/ outside the allowlist (${ALLOWED_SUPERPOWERS_FILE}):"
  echo "$superpowers_hits" | sed 's/^/    /'
fi

# Allowlist anchor: the precedence clause SHOULD reference superpowers. If it no
# longer does, the allowlist is stale (clause moved/removed) — flag it.
if grep -qin 'superpowers' "${REPO_ROOT}/${ALLOWED_SUPERPOWERS_FILE}" 2>/dev/null; then
  pass "allowlist anchor present: ${ALLOWED_SUPERPOWERS_FILE} references superpowers"
else
  fail "allowlist anchor missing: ${ALLOWED_SUPERPOWERS_FILE} no longer references superpowers (stale allowlist?)"
fi

# ---------------------------------------------------------------------------
# Check 6 — Auto-commit authorization framing
# ---------------------------------------------------------------------------
echo ""
echo "Check 6: Auto-commit authorization framing"

# OFF directly authorizes checkpoint commits; Cursor maps that decision to its
# host policy. Check concepts owned by each surface, not prose or headings.
authorization_result="$(REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const read = rel => fs.readFileSync(path.join(process.env.REPO_ROOT, rel), 'utf8').toLowerCase();
const has = (text, terms) => terms.every(term => text.includes(term));
const exec = read('plugin/skills/se-exec/SKILL.md');
const cursor = read('plugin/skills/using-super-exec/references/cursor-tools.md');
const valid = has(exec, ['review-before-commit', 'off', 'checkpoint', 'commit', 'authorization'])
  && has(cursor, ['commit policy', 'se-exec', 'review-before-commit', 'authorization']);
process.stdout.write(valid ? 'ok' : 'missing owner authorization behavior');
NODE
)"
if [ "$authorization_result" = "ok" ]; then
  pass "checkpoint authorization and Cursor host-policy resolution are documented"
else
  fail "checkpoint authorization or Cursor host-policy resolution is missing"
fi

# ---------------------------------------------------------------------------
# Check 7 — SessionStart local-ignore (.git/info/exclude)
# ---------------------------------------------------------------------------
# The SessionStart hook keeps super-exec's local-only working dir (.super-exec/)
# out of git via the repo-local, uncommitted .git/info/exclude (NOT the
# team-shared .gitignore — ADR local-only-plans-specs-are-the-shared-contract). It must do so idempotently on every
# session and degrade to a no-op outside a git repo. If a future edit drops
# this, the dir risks being committed (or the team .gitignore gets polluted
# again).
echo ""
echo "Check 7: SessionStart local-ignore"

HOOK="${REPO_ROOT}/plugin/hooks/session-start"

if ! command -v git >/dev/null 2>&1; then
  fail "git not available — cannot test SessionStart local-ignore"
else
  ttmp=$(mktemp -d)
  trepo="${ttmp}/repo"
  mkdir -p "$trepo"
  ( cd "$trepo" && git init -q ) 2>/dev/null || true

  # Run twice to prove idempotency. ensure_local_ignore runs before any JSON
  # output, so the hook's exit code is irrelevant here. </dev/null because the
  # hook now reads its payload from stdin (do not block on a missing pipe).
  for _ in 1 2; do
    env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
      CLAUDE_PROJECT_DIR="$trepo" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugin" \
      "$HOOK" >/dev/null 2>&1 </dev/null || true
  done

  exclude_file="${trepo}/.git/info/exclude"
  se_count=$(grep -cxF '.super-exec/' "$exclude_file" 2>/dev/null || true); [ -n "$se_count" ] || se_count=0

  if [ "$se_count" = "1" ]; then
    pass "hook adds .super-exec/ to .git/info/exclude (idempotent across 2 runs)"
  else
    fail "exclude entry wrong: .super-exec/=${se_count} (expected 1)"
  fi

  # research/ is local to THIS repo only — the hook must NOT ignore it in
  # target repos.
  if grep -qxF 'research/' "$exclude_file" 2>/dev/null; then
    fail "hook wrongly added research/ to a target repo's .git/info/exclude"
  else
    pass "hook does not touch research/ in target repos (this-repo-only)"
  fi

  # The pattern must actually make git ignore the dir.
  ( cd "$trepo" && mkdir -p .super-exec && touch .super-exec/x ) 2>/dev/null || true
  if ( cd "$trepo" && git check-ignore -q .super-exec/x ) 2>/dev/null; then
    pass "git treats .super-exec/ as ignored after hook run"
  else
    fail "git does not ignore .super-exec/ after hook run"
  fi

  # Outside a git repo: no error, no .git created (degrade to no-op).
  tnogit="${ttmp}/notgit"
  mkdir -p "$tnogit"
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
    CLAUDE_PROJECT_DIR="$tnogit" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugin" \
    "$HOOK" >/dev/null 2>&1 </dev/null || true
  if [ ! -e "${tnogit}/.git" ]; then
    pass "hook is a no-op outside a git repo (no .git created)"
  else
    fail "hook created .git artifacts outside a git repo"
  fi

  # Cursor regression: Cursor's sessionStart payload carries the workspace path
  # in workspace_roots[] (NOT cwd) and does not reliably export a project-dir
  # env var. The hook must resolve PROJECT_DIR from the payload, NOT fall back
  # to PWD (the plugin dir). Simulate that: cwd = a separate git repo, NO
  # project-dir env vars, payload = {workspace_roots:[<userrepo>]}. The exclude
  # MUST land in <userrepo>, never in the cwd repo.
  userrepo="${ttmp}/cursor-user-repo"
  cwdrepo="${ttmp}/cursor-cwd-repo"   # stands in for the plugin dir
  mkdir -p "$userrepo" "$cwdrepo"
  ( cd "$userrepo" && git init -q ) 2>/dev/null || true
  ( cd "$cwdrepo" && git init -q ) 2>/dev/null || true
  cursor_payload="{\"hook_event_name\":\"sessionStart\",\"workspace_roots\":[\"${userrepo}\"]}"
  ( cd "$cwdrepo" && printf '%s' "$cursor_payload" | env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
      CURSOR_PLUGIN_ROOT="${REPO_ROOT}/plugin" "$HOOK" >/dev/null 2>&1 ) || true
  if grep -qxF '.super-exec/' "${userrepo}/.git/info/exclude" 2>/dev/null \
     && ! grep -qxF '.super-exec/' "${cwdrepo}/.git/info/exclude" 2>/dev/null; then
    pass "Cursor payload: exclude lands in workspace_roots[0], not PWD"
  else
    in_user=$(grep -cxF '.super-exec/' "${userrepo}/.git/info/exclude" 2>/dev/null || true)
    in_cwd=$(grep -cxF '.super-exec/' "${cwdrepo}/.git/info/exclude" 2>/dev/null || true)
    fail "Cursor payload misrouted exclude (workspace=${in_user:-0} pwd=${in_cwd:-0}; expected 1/0)"
  fi

  # Resume detection should prefer the active_plan recorded in .super-exec/active
  # over the newest plan on disk. This is what lets the recorded plan remain the
  # build target even when other local plans exist.
  markerrepo="${ttmp}/marker-repo"
  mkdir -p "$markerrepo/.super-exec/marker-feature/2026-06-22-marker-plan" \
           "$markerrepo/.super-exec/latest-feature/2026-06-22-latest-plan"
  ( cd "$markerrepo" && git init -q ) 2>/dev/null || true
  marker_plan="${markerrepo}/.super-exec/marker-feature/2026-06-22-marker-plan/plan.md"
  latest_plan="${markerrepo}/.super-exec/latest-feature/2026-06-22-latest-plan/plan.md"
  printf '# Marker Plan\n' > "$marker_plan"
  printf '# Latest Plan\n' > "$latest_plan"
  touch -t 202606220900 "$marker_plan" 2>/dev/null || true
  touch -t 202606221000 "$latest_plan" 2>/dev/null || true
  printf 'phase: exec\nactive_plan: %s\n' "$marker_plan" > "${markerrepo}/.super-exec/active"
  marker_output=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
    CLAUDE_PROJECT_DIR="$markerrepo" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugin" \
    "$HOOK" 2>/dev/null </dev/null || true)
  if printf '%s' "$marker_output" | grep -q 'marker-feature' \
     && printf '%s' "$marker_output" | grep -q '2026-06-22-marker-plan' \
     && ! printf '%s' "$marker_output" | grep -q 'latest-feature'; then
    pass "SessionStart resume uses active_plan marker before latest-plan discovery"
  else
    fail "SessionStart ignored active_plan marker when newer plan existed"
  fi

  # Skip-plan resume: marker has mode: skip-plan + spec, no active_plan, and a
  # stale plan exists on disk. Orientation must name the governing spec and
  # must NOT pick that unrelated plan.
  skipplanrepo="${ttmp}/skip-plan-marker-repo"
  mkdir -p "$skipplanrepo/.super-exec" \
           "$skipplanrepo/docs/specs/stale-feature/plans/2026-06-22-stale-plan"
  ( cd "$skipplanrepo" && git init -q ) 2>/dev/null || true
  stale_plan="${skipplanrepo}/docs/specs/stale-feature/plans/2026-06-22-stale-plan/plan-stale-plan.md"
  printf '%s\n' '---' 'title: Stale' 'status: in_progress' '---' '# Stale' > "$stale_plan"
  printf 'phase: exec\nmode: skip-plan\nspec: docs/specs/core-workflow/spec-core-workflow.md\n' \
    > "${skipplanrepo}/.super-exec/active"
  skipplan_output=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
    CLAUDE_PROJECT_DIR="$skipplanrepo" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugin" \
    "$HOOK" 2>/dev/null </dev/null || true)
  if printf '%s' "$skipplan_output" | grep -q 'skip-plan' \
     && printf '%s' "$skipplan_output" | grep -q 'docs/specs/core-workflow/spec-core-workflow.md' \
     && ! printf '%s' "$skipplan_output" | grep -q 'stale-feature'; then
    pass "SessionStart skip-plan resume uses governing spec, not latest-plan discovery"
  else
    fail "SessionStart skip-plan resume picked a disk plan or dropped the spec"
  fi

  # Skip-plan must NOT be inferred. A marker with `spec:` but no `mode:` (a
  # plan-phase marker written before the plan file exists) must still fall
  # through to latest-plan discovery — the old "spec: && no active_plan"
  # inference wrongly captured it as skip-plan.
  nomoderepo="${ttmp}/no-mode-marker-repo"
  nomodeplandir="${nomoderepo}/docs/specs/shipping/plans/2026-07-20-label-v1"
  mkdir -p "$nomodeplandir" "${nomoderepo}/.super-exec"
  ( cd "$nomoderepo" && git init -q ) 2>/dev/null || true
  printf '%s\n' '---' 'title: Label v1' 'status: in_progress' '---' '# Label' \
    > "${nomodeplandir}/plan-label-v1.md"
  printf 'phase: exec\nspec: docs/specs/shipping/spec-shipping.md\n' \
    > "${nomoderepo}/.super-exec/active"
  nomode_output=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
    CLAUDE_PROJECT_DIR="$nomoderepo" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugin" \
    "$HOOK" 2>/dev/null </dev/null || true)
  if printf '%s' "$nomode_output" | grep -q 'Feature: shipping' \
     && printf '%s' "$nomode_output" | grep -q '2026-07-20-label-v1' \
     && ! printf '%s' "$nomode_output" | grep -qF 'SESSION IN PROGRESS (skip-plan)'; then
    pass "SessionStart does not infer skip-plan from spec: without mode: skip-plan"
  else
    fail "SessionStart inferred skip-plan from a spec-only marker (output: ${nomode_output:0:200})"
  fi

  # Leftover mode: skip-plan plus a resolvable active_plan: plan-backed wins.
  # se-plan should have dropped the mode; if it didn't, the hook still must
  # not hide the real plan behind a skip-plan note.
  bothrepo="${ttmp}/both-mode-and-plan-repo"
  bothplandir="${bothrepo}/.super-exec/both-feature/2026-06-22-both-plan"
  mkdir -p "$bothplandir"
  ( cd "$bothrepo" && git init -q ) 2>/dev/null || true
  both_plan="${bothplandir}/plan.md"
  printf '%s\n' '---' 'title: Both' 'status: in_progress' '---' '# Both' > "$both_plan"
  printf 'phase: exec\nmode: skip-plan\nspec: task-spec\nactive_plan: %s\n' "$both_plan" \
    > "${bothrepo}/.super-exec/active"
  both_output=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
    CLAUDE_PROJECT_DIR="$bothrepo" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugin" \
    "$HOOK" 2>/dev/null </dev/null || true)
  if printf '%s' "$both_output" | grep -q 'both-feature' \
     && printf '%s' "$both_output" | grep -q '2026-06-22-both-plan' \
     && ! printf '%s' "$both_output" | grep -qF 'SESSION IN PROGRESS (skip-plan)'; then
    pass "SessionStart plan-backed wins when mode: skip-plan leftover sits next to active_plan"
  else
    fail "SessionStart hid a real plan behind leftover skip-plan mode (output: ${both_output:0:200})"
  fi

  # If the active plan frontmatter says status: completed, the orientation note
  # must not call it in-progress. se-exec remains the authority on whether to
  # resume or stop, but the hook should not mislabel cheap metadata it can parse.
  completedrepo="${ttmp}/completed-marker-repo"
  mkdir -p "$completedrepo/.super-exec/completed-feature/2026-06-22-completed-plan"
  ( cd "$completedrepo" && git init -q ) 2>/dev/null || true
  completed_plan="${completedrepo}/.super-exec/completed-feature/2026-06-22-completed-plan/plan.md"
  printf '%s\n' '---' 'title: Completed Plan' 'status: completed' '---' '# Completed Plan' > "$completed_plan"
  printf 'phase: exec\nactive_plan: %s\n' "$completed_plan" > "${completedrepo}/.super-exec/active"
  completed_output=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
    CLAUDE_PROJECT_DIR="$completedrepo" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugin" \
    "$HOOK" 2>/dev/null </dev/null || true)
  if printf '%s' "$completed_output" | grep -q 'Completed plan:' \
     && ! printf '%s' "$completed_output" | grep -q 'In-progress plan:'; then
    pass "SessionStart labels completed active_plan without saying in-progress"
  else
    fail "SessionStart mislabels completed active_plan as in-progress"
  fi

  # Lifecycle comments must not claim the hook clears stale markers. The hook
  # only surfaces context; driver skills own marker writes/deletes.
  if grep -qF 'stale-TTL sweep' "$HOOK" 2>/dev/null; then
    fail "SessionStart lifecycle comments still mention a stale-TTL sweep"
  else
    pass "SessionStart lifecycle comments do not mention stale-TTL sweep"
  fi

  if grep -qF 'NEVER auto-deletes' "$HOOK" 2>/dev/null \
     && grep -qF 'Never writes, moves, or deletes any .super-exec/ marker' "$HOOK" 2>/dev/null; then
    pass "SessionStart documents read-only marker behavior"
  else
    fail "SessionStart must document that it never auto-deletes markers"
  fi

  # v1 layout: active_plan points at a v1 plan file
  #   <root>/<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md
  # Orientation must surface the real <feature> (skipping the plans/ level), the
  # plan-dir, and detect the v1 handoff-<plan-name>.md — never label the feature
  # as "plans".
  v1repo="${ttmp}/v1-marker-repo"
  v1plandir="${v1repo}/.super-exec/specs/payments/plans/2026-07-20-retry-v1"
  mkdir -p "$v1plandir"
  ( cd "$v1repo" && git init -q ) 2>/dev/null || true
  v1_plan="${v1plandir}/plan-retry-v1.md"
  printf '%s\n' '---' 'title: Retry v1' 'status: in_progress' '---' '# Retry' > "$v1_plan"
  printf '# handoff\n' > "${v1plandir}/handoff-retry-v1.md"
  printf 'phase: exec\nactive_plan: %s\n' "$v1_plan" > "${v1repo}/.super-exec/active"
  v1_output=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
    CLAUDE_PROJECT_DIR="$v1repo" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugin" \
    "$HOOK" 2>/dev/null </dev/null || true)
  if printf '%s' "$v1_output" | grep -q 'Feature: payments' \
     && printf '%s' "$v1_output" | grep -q '2026-07-20-retry-v1' \
     && printf '%s' "$v1_output" | grep -qi 'handoff' \
     && ! printf '%s' "$v1_output" | grep -q 'Feature: plans'; then
    pass "SessionStart resolves a v1 plan dir (feature, plan-name, handoff) without mislabeling 'plans'"
  else
    fail "SessionStart failed to resolve v1 plan dir correctly (output: ${v1_output:0:200})"
  fi

  # v1 fallback discovery: NO active_plan value in the marker; a v1 plan file
  # under the committed docs/specs/ root must still be discovered (both-root).
  v1fbrepo="${ttmp}/v1-fallback-repo"
  v1fbplandir="${v1fbrepo}/docs/specs/billing/plans/2026-07-20-invoice-v1"
  mkdir -p "$v1fbplandir" "${v1fbrepo}/.super-exec"
  ( cd "$v1fbrepo" && git init -q ) 2>/dev/null || true
  printf '%s\n' '---' 'title: Invoice v1' 'status: in_progress' '---' '# Invoice' \
    > "${v1fbplandir}/plan-invoice-v1.md"
  printf 'phase: exec\n' > "${v1fbrepo}/.super-exec/active"
  v1fb_output=$(env -i PATH="$PATH" HOME="${HOME:-/tmp}" \
    CLAUDE_PROJECT_DIR="$v1fbrepo" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/plugin" \
    "$HOOK" 2>/dev/null </dev/null || true)
  if printf '%s' "$v1fb_output" | grep -q 'Feature: billing' \
     && printf '%s' "$v1fb_output" | grep -q '2026-07-20-invoice-v1'; then
    pass "SessionStart fallback discovers a v1 plan under docs/specs/ (both-root discovery)"
  else
    fail "SessionStart fallback failed to discover v1 plan under docs/specs/ (output: ${v1fb_output:0:200})"
  fi

  rm -rf "$ttmp"
fi

# ---------------------------------------------------------------------------
# Check 8 — Spec filename convention
# ---------------------------------------------------------------------------
echo ""
echo "Check 8: Spec filename convention"

# v1 spec-file layout: <root>/[<app>/]<feature>/spec-<feature>.md — slug-only folders (NO running number),
# scanned across BOTH roots (docs/specs + .super-exec/specs). Only spec files (spec-*.md) are validated here;
# plan-*.md / handoff-*.md / feature-ADR slug files under a root are ignored. A flat NNNN-<slug>.md spec
# (a running number at any depth under a root) ALWAYS fails — v1 identity is slug-only, no numbers.
spec_name_result=$(node -e "
  const fs = require('fs');
  const path = require('path');
  const roots = ['docs/specs', '.super-exec/specs'].map(r => path.join('${REPO_ROOT}', r));
  const V0_FLAT = /^\\d{4}-[a-z0-9]+(?:-[a-z0-9]+)*\\.md$/;  // NNNN-slug.md (v0, forbidden under v1)
  const SEG_OK  = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;              // slug charset for a path segment
  const NUMBERED = /^\\d{4}-/;                               // leading running number on a folder
  const bad = [];

  function rec(root, dir) {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) { rec(root, full); continue; }
      if (!entry.isFile() || !entry.name.endsWith('.md')) continue;
      const rel = path.relative('${REPO_ROOT}', full);

      if (entry.name.indexOf('spec-') === 0) {
        // v1 spec file: folder chain root->parent must be slug-only (no number); parent === <feature>.
        const feature = entry.name.slice(5, -3);
        const relDir = path.relative(root, path.dirname(full));
        const segs = relDir === '' ? [] : relDir.split(path.sep);
        if (segs.length === 0) { bad.push(rel + ' (v1 spec must live in a <feature>/ folder, not the root)'); continue; }
        for (const s of segs) {
          if (NUMBERED.test(s)) bad.push(rel + ' (running number in folder \"' + s + '\")');
          else if (!SEG_OK.test(s)) bad.push(rel + ' (non-slug folder \"' + s + '\")');
        }
        if (!SEG_OK.test(feature)) bad.push(rel + ' (feature slug \"' + feature + '\" not slug-only)');
        else if (segs[segs.length - 1] !== feature) bad.push(rel + ' (spec-<feature> must match its folder \"' + segs[segs.length - 1] + '\")');
      } else if (V0_FLAT.test(entry.name)) {
        // numbered spec filename (running number, any depth under a root) — forbidden under slug-only v1 identity.
        bad.push(rel + ' (numbered spec filename; v1 requires <feature>/spec-<feature>.md, no running number)');
      }
      // else: plan-*.md / handoff-*.md / feature-ADR slug files — not a spec, ignored.
    }
  }

  for (const root of roots) rec(root, root);
  process.stdout.write(bad.length ? bad.join('\\n') : 'ok');
" 2>/dev/null || echo "ERROR")

if [ "$spec_name_result" = "ok" ]; then
  pass "spec files conform to v1 layout (<root>/[<app>/]<feature>/spec-<feature>.md, slug-only, both roots; no running numbers)"
else
  fail "spec file layout violations (v1 = <root>/[<app>/]<feature>/spec-<feature>.md, slug-only per-feature folder, both roots):"
  echo "$spec_name_result" | sed 's/^/    /'
fi

spec_convention_sites=(
  "plugin/skills/se-discuss/SKILL.md|||spec-<feature>.md"
  "plugin/skills/se-plan/SKILL.md|||plan-<plan-name>.md"
  "plugin/skills/se-plan/SKILL.md|||/se-get-config"
  "plugin/skills/se-plan/plan-template.md|||spec-<feature>.md"
  "docs/specs/core-workflow/spec-core-workflow.md|||<root>/[<app>/]<feature>/spec-<feature>.md"
  "docs/adr/local-only-plans-specs-are-the-shared-contract.md|||docs/specs/NNNN-<feature>.md"
)

for entry in "${spec_convention_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "spec convention: file not found: ${rel}"
  elif grep -qF -- "$phrase" "$file" 2>/dev/null; then
    pass "spec convention present in ${rel} (\"${phrase}\")"
  else
    fail "spec convention missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

# --- se-discuss v1 placement (Task 6): config-driven root + slug-only path ---
discuss_skill="${REPO_ROOT}/plugin/skills/se-discuss/SKILL.md"
if [ -f "$discuss_skill" ]; then
  if grep -qF '<root>/[<app>/]<feature>/spec-<feature>.md' "$discuss_skill" 2>/dev/null; then
    pass "se-discuss SKILL has v1 spec path template <root>/[<app>/]<feature>/spec-<feature>.md"
  else
    fail "se-discuss SKILL missing v1 spec path template <root>/[<app>/]<feature>/spec-<feature>.md"
  fi
  if grep -qiE 'commitSpec.*true.*false.*ask|true.*false.*ask.*commitSpec' "$discuss_skill" 2>/dev/null; then
    pass "se-discuss SKILL resolves commitSpec placement choices"
  else
    fail "se-discuss SKILL missing commitSpec placement choices"
  fi
  discuss_root_result="$(REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const text = fs.readFileSync(path.join(process.env.REPO_ROOT, 'plugin/skills/se-discuss/SKILL.md'), 'utf8').toLowerCase();
const has = terms => terms.every(term => text.includes(term));
const preserves = has(['existing', 'discovered root', 'config', 'move', 'explicit request']);
const commits = has(['committed-root artifacts', '/se-commit', 'local specs never commit']);
process.stdout.write(preserves && commits ? 'ok' : 'missing existing-root or publication behavior');
NODE
)"
  if [ "$discuss_root_result" = "ok" ]; then
    pass "se-discuss preserves existing roots and commits only committed-root artifacts"
  else
    fail "se-discuss existing-root or publication behavior is missing"
  fi
  if grep -qF 'docs/specs/' "$discuss_skill" 2>/dev/null \
     && grep -qF '.super-exec/specs/' "$discuss_skill" 2>/dev/null; then
    pass "se-discuss SKILL mentions both roots docs/specs/ and .super-exec/specs/"
  else
    fail "se-discuss SKILL must mention both docs/specs/ and .super-exec/specs/"
  fi
  if grep -qF 'docs/specs/NNNN-<feature>.md' "$discuss_skill" 2>/dev/null; then
    fail "se-discuss SKILL still contains flat v0 write template docs/specs/NNNN-<feature>.md"
  else
    pass "se-discuss SKILL no longer uses flat docs/specs/NNNN-<feature>.md write template"
  fi
else
  fail "se-discuss SKILL.md missing"
fi

core_workflow_spec="${REPO_ROOT}/docs/specs/core-workflow/spec-core-workflow.md"
if grep -qF 'without consulting config or re-prompting about placement' "$core_workflow_spec" 2>/dev/null \
   && grep -qF 'commit every spec whose resolved on-disk root is `docs/specs/`' "$core_workflow_spec" 2>/dev/null; then
  pass "core workflow preserves existing spec roots and commits by resolved root"
else
  fail "core workflow must preserve existing spec roots and commit by resolved root"
fi

# --- se-plan v1 placement (Task 7): config-driven root + slug-only plan path ---
plan_skill="${REPO_ROOT}/plugin/skills/se-plan/SKILL.md"
if [ -f "$plan_skill" ]; then
  if grep -qF '<root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md' "$plan_skill" 2>/dev/null; then
    pass "se-plan SKILL has v1 plan path template <root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md"
  else
    fail "se-plan SKILL missing v1 plan path template <root>/[<app>/]<feature>/plans/<YYYY-MM-DD>-<plan-name>/plan-<plan-name>.md"
  fi
  if grep -qF '/se-get-config' "$plan_skill" 2>/dev/null \
     && grep -qF 'commitPlan' "$plan_skill" 2>/dev/null; then
    pass "se-plan SKILL consults /se-get-config for commitPlan"
  else
    fail "se-plan SKILL missing /se-get-config consult for commitPlan"
  fi
  if grep -qF 'docs/specs/' "$plan_skill" 2>/dev/null \
     && grep -qF '.super-exec/specs/' "$plan_skill" 2>/dev/null; then
    pass "se-plan SKILL mentions both roots docs/specs/ and .super-exec/specs/"
  else
    fail "se-plan SKILL must mention both docs/specs/ and .super-exec/specs/"
  fi
  plan_discovery_result="$(REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const text = fs.readFileSync(path.join(process.env.REPO_ROOT, 'plugin/skills/se-plan/SKILL.md'), 'utf8').toLowerCase();
const has = terms => terms.every(term => text.includes(term));
const valid = has(['no argument', 'scan', 'specs', 'plans/', 'list', 'ask user']);
process.stdout.write(valid ? 'ok' : 'missing no-argument discovery behavior');
NODE
)"
  if [ "$plan_discovery_result" = "ok" ]; then
    pass "se-plan discovers unplanned specs and asks user to choose"
  else
    fail "se-plan no-argument discovery behavior is missing"
  fi
  if grep -qiF 'lowest-numbered' "$plan_skill" 2>/dev/null; then
    fail "se-plan SKILL still says lowest-numbered (v0 auto-discovery)"
  else
    pass "se-plan SKILL no longer uses lowest-numbered auto-discovery"
  fi
  if grep -qF 'docs/specs/NNNN-<feature>.md' "$plan_skill" 2>/dev/null; then
    fail "se-plan SKILL still contains flat v0 path docs/specs/NNNN-<feature>.md"
  else
    pass "se-plan SKILL no longer uses flat docs/specs/NNNN-<feature>.md path"
  fi
  # Committed root publishes ready plan + ledger; local root publishes neither.
  plan_publication_result="$(REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const plan = fs.readFileSync(path.join(process.env.REPO_ROOT, 'plugin/skills/se-plan/SKILL.md'), 'utf8');
const has = terms => terms.every(term => plan.toLowerCase().includes(term.toLowerCase()));
const committedPair = has(['ready', 'plan', 'ledger', 'together', '/se-commit']);
const localPair = has(['local root', 'commit neither']);
process.stdout.write(committedPair && localPair ? 'ok' : 'invalid paired plan publication');
NODE
)"
  if [ "$plan_publication_result" = "ok" ]; then
    pass "se-plan publishes plan and ledger together when committed; neither when local"
  else
    fail "se-plan config-aware paired plan publication contract missing: ${plan_publication_result}"
  fi
  if grep -qF 'there is no commit tied to this branch' "$plan_skill" 2>/dev/null; then
    fail "se-plan SKILL still claims always-local plan (there is no commit tied to this branch)"
  else
    pass "se-plan SKILL no longer claims always-local plan (no commit tied to this branch)"
  fi
else
  fail "se-plan SKILL.md missing"
fi

# --- se-exec v1 config + placement (Task 8): toggles from /se-get-config + both-root paths ---
exec_skill="${REPO_ROOT}/plugin/skills/se-exec/SKILL.md"
if [ -f "$exec_skill" ]; then
  if grep -qF '/se-get-config' "$exec_skill" 2>/dev/null \
     && grep -qF 'humanReviewBeforeCheckpointCommit' "$exec_skill" 2>/dev/null \
     && grep -qF 'autoCreatePr' "$exec_skill" 2>/dev/null; then
    pass "se-exec SKILL consults /se-get-config for humanReviewBeforeCheckpointCommit and autoCreatePr"
  else
    fail "se-exec SKILL missing /se-get-config consult for humanReviewBeforeCheckpointCommit and autoCreatePr"
  fi
  exec_toggle_result="$(REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const text = fs.readFileSync(path.join(process.env.REPO_ROOT, 'plugin/skills/se-exec/SKILL.md'), 'utf8').toLowerCase();
const has = terms => terms.every(term => text.includes(term));
const valid = has(['humanreviewbeforecheckpointcommit', 'autocreatepr', 'booleans', 'directly', 'ask', 'only']);
process.stdout.write(valid ? 'ok' : 'missing direct-boolean/ask-only toggle behavior');
NODE
)"
  if [ "$exec_toggle_result" = "ok" ]; then
    pass "se-exec uses resolved booleans directly and prompts only for ask"
  else
    fail "se-exec direct-boolean/ask-only toggle behavior is missing"
  fi
  if grep -qF 'docs/specs/' "$exec_skill" 2>/dev/null \
     && grep -qF '.super-exec/specs/' "$exec_skill" 2>/dev/null; then
    pass "se-exec SKILL mentions both roots docs/specs/ and .super-exec/specs/"
  else
    fail "se-exec SKILL must mention both docs/specs/ and .super-exec/specs/"
  fi
  handoff_owner_result="$(REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const read = rel => fs.readFileSync(path.join(process.env.REPO_ROOT, rel), 'utf8').toLowerCase();
const exec = read('plugin/skills/se-exec/SKILL.md');
const handoff = read('plugin/skills/se-handoff/SKILL.md');
const valid = exec.includes('/se-handoff') && handoff.includes('handoff-<plan-name>.md');
process.stdout.write(valid ? 'ok' : 'handoff ownership is missing');
NODE
)"
  if [ "$handoff_owner_result" = "ok" ]; then
    pass "se-exec delegates handoff and se-handoff owns filename"
  else
    fail "handoff delegation or filename ownership is missing"
  fi
else
  fail "se-exec SKILL.md missing"
fi

# ---------------------------------------------------------------------------
# Check 9 — Plan and execution lifecycle contracts
# ---------------------------------------------------------------------------
echo ""
echo "Check 9: Plan and execution lifecycle contracts"

lifecycle_contract_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$lifecycle_contract_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.env.REPO_ROOT;
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8').toLowerCase();
const plan = read('plugin/skills/se-plan/SKILL.md');
const exec = read('plugin/skills/se-exec/SKILL.md');
const template = read('plugin/skills/se-plan/plan-template.md');
const core = read('docs/specs/core-workflow/spec-core-workflow.md');
const problems = [];
const has = (text, terms, label) => {
  if (!terms.every(term => text.includes(term))) problems.push(label);
};
has(template, ['status: pending', 'final review / pr decision'], 'plan template lifecycle entries');
has(plan, ['status: pending', 'active_plan', 'ledger_status: pending', 'ledger_status: ready', 'fresh session'], 'plan lifecycle ordering');
has(exec, ['status: completed', 'nonempty checklist', 'missing checklist never completes'], 'completion guard');
const completionAction = exec.split(/\r?\n/).find(line => {
  const clause = line.toLowerCase();
  return /\b(?:set|transition|mark)\w*\b.*\bstatus\b[^a-z0-9]{0,8}completed\b/.test(clause)
    && clause.includes('only after');
}) || '';
has(completionAction, ['required outcomes', 'full work packages', 'proof/review', 'delivery', 'reconciliation'], 'completion prerequisites bound to status action');
has(exec, ['active_plan', 'ledger_status: ready', 'return to `/se-plan`'], 'execution readiness');
has(exec, ['/se-handoff', 'clean tree', 'final delivery identity'], 'terminal handoff and delivery boundary');
has(core, ['missing checklist', 'completed'], 'core completion guard');
process.stdout.write(problems.length ? problems.join('; ') : 'ok');
NODE
then
  lifecycle_contract_result="$(<"$lifecycle_contract_output")"
else
  lifecycle_contract_result="ERROR"
fi
rm -f "$lifecycle_contract_output"
if [ "$lifecycle_contract_result" = "ok" ]; then
  pass "plan and execution lifecycle contracts remain behaviorally bound"
else
  fail "plan/execution lifecycle contract problem: ${lifecycle_contract_result}"
fi

# ---------------------------------------------------------------------------
# Check 10 — Template artifacts are copy-pasteable
# ---------------------------------------------------------------------------
echo ""
echo "Check 10: Template artifacts are copy-pasteable"

template_purity_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$template_purity_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');

const repoRoot = process.env.REPO_ROOT;
const templates = [
  'plugin/skills/se-plan/plan-template.md',
  'plugin/skills/se-discuss/spec-template.md',
  'plugin/skills/se-pr/pr-template.md',
  'plugin/skills/se-handoff/handoff-template.md',
];

const forbidden = [
  { re: /```markdown/i, label: 'fenced markdown wrapper' },
  { re: /\bWrite the\b/i, label: 'write instructions' },
  { re: /\bUsed by\b/i, label: 'usage prose' },
  { re: /\bThe file must contain\b/i, label: 'outline instructions' },
  { re: /\bfollowing sections\b/i, label: 'section-order prose' },
  { re: /\bDefault Title Format\b/i, label: 'title-rule prose' },
  { re: /\bBody Rules\b/i, label: 'body-rule prose' },
  { re: /\bExamples:\b/i, label: 'example prose' },
];

const problems = [];
for (const rel of templates) {
  const full = path.join(repoRoot, rel);
  if (!fs.existsSync(full)) {
    problems.push(`${rel}: missing`);
    continue;
  }

  const content = fs.readFileSync(full, 'utf8');
  const first = content.split(/\r?\n/).find((line) => line.trim()) || '';
  if (/^#\s+.*\b(Template|Reference|Outline)\b/i.test(first)) {
    problems.push(`${rel}: meta heading`);
  }
  if (/^\s*```/.test(first)) {
    problems.push(`${rel}: starts with fence`);
  }

  for (const { re, label } of forbidden) {
    if (re.test(content)) {
      problems.push(`${rel}: ${label}`);
    }
  }
}

process.stdout.write(problems.length ? problems.join('\n') : 'ok');
NODE
then
  template_purity_result="$(<"$template_purity_output")"
else
  template_purity_result="ERROR"
fi
rm -f "$template_purity_output"

if [ "$template_purity_result" = "ok" ]; then
  pass "plugin template files are pure copy-pasteable artifacts"
else
  fail "plugin template files must be artifact-only:"
  echo "$template_purity_result" | sed 's/^/    /'
fi

pr_template_exact_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$pr_template_exact_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const repoRoot = process.env.REPO_ROOT;
const actual = fs.readFileSync(path.join(repoRoot, 'plugin/skills/se-pr/pr-template.md'), 'utf8');
const expected = `## Jira tickets:
- <TICKET_ID | NO_TICKET>

## Describe your changes
-
`;

process.stdout.write(actual === expected ? 'ok' : `expected:\n${expected}\nactual:\n${actual}`);
NODE
then
  pr_template_exact_result="$(<"$pr_template_exact_output")"
else
  pr_template_exact_result="ERROR"
fi
rm -f "$pr_template_exact_output"

if [ "$pr_template_exact_result" = "ok" ]; then
  pass "se-pr built-in fallback template matches expected body"
else
  fail "se-pr built-in fallback template drifted:"
  echo "$pr_template_exact_result" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Check 11 — Core spec stays synced with shipped entrypoints and templates
# ---------------------------------------------------------------------------
echo ""
echo "Check 11: Core spec sync"

core_spec_sites=(
  "docs/specs/core-workflow/spec-core-workflow.md|||> Ticket: NO_TICKET  ·  Status: active"
  "docs/specs/core-workflow/spec-core-workflow.md|||four entrypoints"
  "docs/specs/core-workflow/spec-core-workflow.md|||/se-pr-triage"
  "docs/specs/core-workflow/spec-core-workflow.md|||## Behavior / Requirements"
  "docs/specs/core-workflow/spec-core-workflow.md|||Working-increment boundary"
  "docs/specs/core-workflow/spec-core-workflow.md|||Deferred finding ledger"
)

for entry in "${core_spec_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "core spec sync: file not found: ${rel}"
  elif grep -qF -- "$phrase" "$file" 2>/dev/null; then
    pass "core spec sync present in ${rel} (\"${phrase}\")"
  else
    fail "core spec sync missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

impeccable_owner_result="$(REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const read = rel => fs.readFileSync(path.join(process.env.REPO_ROOT, rel), 'utf8').toLowerCase();
const subagent = read('plugin/skills/se-subagent/SKILL.md');
const plan = read('plugin/skills/se-plan/SKILL.md');
const valid = subagent.includes('impeccable-critique') && subagent.includes('strong')
  && plan.includes('impeccable') && plan.includes('dispatch');
process.stdout.write(valid ? 'ok' : 'impeccable owner/caller mapping missing');
NODE
)"
if [ "$impeccable_owner_result" = "ok" ]; then
  pass "se-subagent owns impeccable tier and se-plan invokes it"
else
  fail "impeccable owner/caller mapping is missing"
fi

core_spec_forbidden_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$core_spec_forbidden_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const repoRoot = process.env.REPO_ROOT;
const checks = [
  {
    rel: 'docs/specs/core-workflow/spec-core-workflow.md',
    forbidden: [/three entrypoints/i, /build pending/i, /## Data flow\b/, /Status:\s*draft/i, /README.*recommends?.*superpowers/i, /README.*disabl(?:e|ing).*superpowers/i],
  },
  {
    rel: 'docs/adr/skills-only-no-thin-commands.md',
    forbidden: [/three entrypoints/i, /stale-TTL sweep/i],
  },
  {
    rel: 'docs/adr/superpowers-coinstall-skill-precedence.md',
    forbidden: [/README.*recommends?.*superpowers/i, /README.*disabl(?:e|ing).*superpowers/i, /static README recommendation/i],
  },
];
const hits = [];
for (const { rel, forbidden } of checks) {
  const content = fs.readFileSync(path.join(repoRoot, rel), 'utf8');
  for (const re of forbidden) {
    if (re.test(content)) hits.push(`${rel}: ${re}`);
  }
}
process.stdout.write(hits.length ? hits.join('\n') : 'ok');
NODE
then
  core_spec_forbidden_result="$(<"$core_spec_forbidden_output")"
else
  core_spec_forbidden_result="ERROR"
fi
rm -f "$core_spec_forbidden_output"

if [ "$core_spec_forbidden_result" = "ok" ]; then
  pass "stale core-spec/ADR wording is absent"
else
  fail "stale core-spec/ADR wording remains:"
  echo "$core_spec_forbidden_result" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Check 12 — README landing-page scope
# ---------------------------------------------------------------------------
echo ""
echo "Check 12: README landing-page scope"

readme_scope_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$readme_scope_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const repoRoot = process.env.REPO_ROOT;
const rel = 'README.md';
const content = fs.readFileSync(path.join(repoRoot, rel), 'utf8');

const required = [
  'discuss -> plan -> exec -> PR / triage',
  '/se-discuss',
  '/se-plan',
  '/se-exec',
  '/se-pr-triage',
  'docs/specs/',
  'docs/specs/core-workflow/spec-core-workflow.md',
  'plugin/skills/*/SKILL.md',
];

const forbidden = [
  /active_plan/i,
  /standing go-ahead/i,
  /standing authorization/i,
  /plan frontmatter/i,
  /native task\/todo/i,
  /Missing checklists/i,
  /after outer review is clean/i,
  /SessionStart/i,
  /model slug/i,
  /review before each commit/i,
  /pull_request_template/i,
  /docs\/specs\/NNNN-<feature>\.md/,
  /\.git\/info\/exclude/i,
];

const problems = [];
for (const phrase of required) {
  if (!content.includes(phrase)) problems.push(`missing required high-level anchor: ${phrase}`);
}
for (const re of forbidden) {
  if (re.test(content)) problems.push(`README contains low-level contract detail: ${re}`);
}

process.stdout.write(problems.length ? problems.join('\n') : 'ok');
NODE
then
  readme_scope_result="$(<"$readme_scope_output")"
else
  readme_scope_result="ERROR"
fi
rm -f "$readme_scope_output"

if [ "$readme_scope_result" = "ok" ]; then
  pass "README stays high-level and points to source-of-truth files"
else
  fail "README scope problem:"
  echo "$readme_scope_result" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Check 13 — se-local-ignore skill ownership + behavior
# ---------------------------------------------------------------------------
# The se-local-ignore skill is the single owner and guaranteed layer for keeping
# .super-exec/ out of git (the SessionStart hook in Check 7 is only a best-effort
# backup — see ADR local-only-plans-specs-are-the-shared-contract). This check enforces: the skill exists and is internal,
# documents the canonical command, every driver skill applies it at activation,
# and the canonical command is idempotent, ignores .super-exec/, and no-ops
# outside a git repo.
echo ""
echo "Check 13: se-local-ignore skill ownership"

li_skill="${REPO_ROOT}/plugin/skills/se-local-ignore/SKILL.md"
li_script="${REPO_ROOT}/plugin/skills/se-local-ignore/ensure-local-ignore"

if [ -f "$li_skill" ]; then
  pass "se-local-ignore/SKILL.md exists"
else
  fail "se-local-ignore/SKILL.md missing"
fi

if grep -qxF 'user-invocable: false' "$li_skill" 2>/dev/null; then
  pass "se-local-ignore is internal (user-invocable: false)"
else
  fail "se-local-ignore must declare user-invocable: false"
fi

# The skill bundles its own script and invokes it via a relative path
# (the branch-context pattern), rather than inlining the raw command.
if [ -x "$li_script" ]; then
  pass "se-local-ignore bundles an executable ensure-local-ignore script"
else
  fail "se-local-ignore/ensure-local-ignore missing or not executable"
fi

if grep -qF '@./ensure-local-ignore' "$li_skill" 2>/dev/null \
   && ! grep -qF 'CLAUDE_SKILL_DIR' "$li_skill" 2>/dev/null; then
  pass "se-local-ignore invokes its bundled script via an @./ mention"
else
  fail "se-local-ignore must invoke @./ensure-local-ignore without \${CLAUDE_SKILL_DIR}"
fi

if grep -qF 'git check-ignore -q .super-exec/' "$li_script" 2>/dev/null; then
  pass "ensure-local-ignore uses the canonical check-ignore guard"
else
  fail "ensure-local-ignore missing canonical 'git check-ignore -q .super-exec/' guard"
fi

# Every driver skill (those that write .super-exec/active) must invoke /se-local-ignore.
for driver in se-discuss se-plan se-exec se-pr-triage; do
  ds="${REPO_ROOT}/plugin/skills/${driver}/SKILL.md"
  if grep -qF '/se-local-ignore' "$ds" 2>/dev/null; then
    pass "${driver} invokes /se-local-ignore at activation"
  else
    fail "${driver} does not invoke /se-local-ignore"
  fi
done

# Functional: run the ACTUAL bundled script. It must be idempotent, ignore the
# dir, never write .gitignore, and no-op outside a git repo.
if ! command -v git >/dev/null 2>&1; then
  fail "git not available — cannot test ensure-local-ignore behavior"
elif [ ! -x "$li_script" ]; then
  fail "ensure-local-ignore not executable — cannot run behavior tests"
else
  litmp=$(mktemp -d)
  lirepo="${litmp}/repo"
  mkdir -p "$lirepo"
  ( cd "$lirepo" && git init -q ) 2>/dev/null || true

  # Run three times via CLAUDE_PROJECT_DIR (the resolution the script uses).
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" CLAUDE_PROJECT_DIR="$lirepo" "$li_script" || fail "ensure-local-ignore exited nonzero (run 1)"
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" CLAUDE_PROJECT_DIR="$lirepo" "$li_script" || fail "ensure-local-ignore exited nonzero (run 2)"
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" CLAUDE_PROJECT_DIR="$lirepo" "$li_script" || fail "ensure-local-ignore exited nonzero (run 3)"

  li_count=$(grep -cxF '.super-exec/' "${lirepo}/.git/info/exclude" 2>/dev/null || true)
  [ -n "$li_count" ] || li_count=0
  if [ "$li_count" = "1" ]; then
    pass "ensure-local-ignore is idempotent across 3 runs (one exclude line)"
  else
    fail "ensure-local-ignore not idempotent: .super-exec/=${li_count} (expected 1)"
  fi

  ( cd "$lirepo" && mkdir -p .super-exec && touch .super-exec/active ) 2>/dev/null || true
  if ( cd "$lirepo" && git check-ignore -q .super-exec/active ) 2>/dev/null; then
    pass "git ignores .super-exec/ after ensure-local-ignore runs"
  else
    fail "git does not ignore .super-exec/ after ensure-local-ignore runs"
  fi

  # Does not touch the team-shared .gitignore.
  if [ ! -e "${lirepo}/.gitignore" ]; then
    pass "ensure-local-ignore never writes the team-shared .gitignore"
  else
    fail "ensure-local-ignore wrongly created/edited .gitignore"
  fi

  # No-op outside a git repo: no .git created, no exclude written.
  linogit="${litmp}/notgit"
  mkdir -p "$linogit"
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" CLAUDE_PROJECT_DIR="$linogit" "$li_script" || fail "ensure-local-ignore exited nonzero (no-git)"
  if [ ! -e "${linogit}/.git" ]; then
    pass "ensure-local-ignore is a no-op outside a git repo"
  else
    fail "ensure-local-ignore created .git artifacts outside a git repo"
  fi

  rm -rf "$litmp"
fi

# ---------------------------------------------------------------------------
# Check 14 — cursor-tools skill-bundled file path convention
# ---------------------------------------------------------------------------
# Skills reference bundled files by paths relative to the skill file.
# cursor-tools.md documents how both harnesses resolve those paths.
echo ""
echo "Check 14: cursor-tools skill-bundled file path convention"

cursor_tools_ref="${REPO_ROOT}/plugin/skills/using-super-exec/references/cursor-tools.md"
bundled_path_result="$(REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const text = fs.readFileSync(path.join(process.env.REPO_ROOT, 'plugin/skills/using-super-exec/references/cursor-tools.md'), 'utf8').toLowerCase();
const valid = text.includes('@./<file>') && text.includes('@../<skill>/<file>')
  && text.includes('resolve from loaded skill path');
process.stdout.write(valid ? 'ok' : 'relative bundled-path resolution missing');
NODE
)"
if [ "$bundled_path_result" = "ok" ]; then
  pass "cursor-tools.md defines relative bundled and sibling path resolution"
else
  fail "cursor-tools.md missing relative bundled/sibling path resolution"
fi

# ---------------------------------------------------------------------------
# Check 15 — no skill body still uses ${CLAUDE_SKILL_DIR}
# ---------------------------------------------------------------------------
echo ""
echo "Check 15: no skill body references \${CLAUDE_SKILL_DIR}"

skill_claude_skill_dir_hits=$(grep -rlF 'CLAUDE_SKILL_DIR' "${REPO_ROOT}/plugin/skills/" 2>/dev/null \
  | grep -vF 'using-super-exec/references/cursor-tools.md' || true)
if [ -z "$skill_claude_skill_dir_hits" ]; then
  pass "no skill body references \${CLAUDE_SKILL_DIR}"
else
  fail "skill bodies still contain \${CLAUDE_SKILL_DIR}: ${skill_claude_skill_dir_hits}"
fi

# ---------------------------------------------------------------------------
# Check 16 — se-pr-triage two-gate reply contract
# ---------------------------------------------------------------------------
echo ""
echo "Check 16: se-pr-triage two-gate reply contract"

triage_contract_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$triage_contract_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.env.REPO_ROOT;

const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const skill = read('plugin/skills/se-pr-triage/SKILL.md');
const spec = read('docs/specs/pr-triage-watch-bot/spec-pr-triage-watch-bot.md');
const core = read('docs/specs/core-workflow/spec-core-workflow.md');
const orientation = read('plugin/skills/using-super-exec/SKILL.md');
const readme = read('README.md');
const problems = [];

const orderedHeadings = [
  '## 5. Mandatory decision approval gate (Gate 1)',
  '## 6. Execute approved Track A fixes',
  '## 7. Compose exact final replies',
  '## 8. Mandatory final reply approval gate (Gate 2)',
  '## 9. Post exact approved replies',
];
let previous = -1;
for (const heading of orderedHeadings) {
  const index = skill.indexOf(heading);
  if (index === -1) problems.push(`skill missing ordered heading: ${heading}`);
  if (index !== -1 && index <= previous) problems.push(`skill heading out of order: ${heading}`);
  if (index !== -1) previous = index;
}

const required = [
  [skill, 'Do not draft, generate, suggest, outline, or present any reply body — provisional, sample, or final — for any decision before step 7.', 'skill no pre-step-7 reply drafting'],
  [skill, 'The rationale is internal analysis for the human, not a draft addressed to the reviewer.', 'skill Gate-1 rationale is not reply copy'],
  [skill, 'First step where any reply text may be drafted.', 'skill reply composition starts at step 7'],
  [skill, 'Placeholders such as `<SHA>` and provisional implementation wording are forbidden.', 'skill no provisional Fix replies'],
  [skill, 'Any reply target or body change after Gate-2 approval invalidates that approval', 'skill Gate-2 invalidation'],
  [skill, 'A round with only Decline / Answer / Defer items still performs this step after Gate 1.', 'skill no-Fix batch'],
  [skill, 'do not create a reply candidate', 'skill aborted Fix exclusion'],
  [skill, 'There is no auto-approve mode, even under `/loop`.', 'skill Gate-2 loop rule'],
  [spec, 'Gate-1 approval authorizes only the approved Fix work; it never authorizes a PR reply.', 'spec Gate-1 authority'],
  [spec, 'During triage and Gate 1, the controller must not draft, generate, suggest, outline, or present any reply body', 'spec no initial reply drafting'],
  [spec, 'reply composition begins only here, after the step-12 Fix phase has completed', 'spec post-fix reply composition'],
  [spec, 'Final reply approval gate (mandatory)', 'spec Gate-2'],
  [spec, 'placeholders and provisional wording are forbidden', 'spec exact post-fix bodies'],
  [core, 'Post-PR triage retains two human gates', 'core two-gate discipline'],
  [core, 'Gate 1 approves decisions and Fix scope only', 'core Gate-1 scope'],
  [core, 'Gate 2 approves exact final reply target/body', 'core Gate-2 scope'],
  [orientation, 'separately gates the exact final replies before posting', 'orientation two-gate summary'],
  [readme, 'exact final replies are previewed and approved separately after fixes are pushed', 'README user-facing contract'],
];
for (const [content, phrase, label] of required) {
  if (!content.includes(phrase)) problems.push(`missing ${label}: ${phrase}`);
}
if (!/Gate-1 approval[\s\S]{0,120}only approved Fix work[\s\S]{0,120}never authorizes a PR reply/i.test(skill)) {
  problems.push('skill Gate-1 authorizes Fix scope, not replies');
}

const forbidden = [
  [spec, /single approval/i, 'spec stale single-approval wording'],
  [skill, /Process each Track A item using the approved decisions and reply text/i, 'skill stale one-gate execution'],
  [skill, /Only after the commit is pushed, post the approved reply/i, 'skill stale auto-post after push'],
];
for (const [content, pattern, label] of forbidden) {
  if (pattern.test(content)) problems.push(label);
}

process.stdout.write(problems.length ? problems.join('\n') : 'ok');
NODE
then
  triage_contract_result="$(<"$triage_contract_output")"
else
  triage_contract_result="ERROR"
fi
rm -f "$triage_contract_output"

if [ "$triage_contract_result" = "ok" ]; then
  pass "se-pr-triage enforces ordered decision and exact-final-reply gates"
else
  fail "se-pr-triage two-gate contract problem:"
  echo "$triage_contract_result" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Check 17 — se-config schema + default JSON contract
# ---------------------------------------------------------------------------
# Task 1 foundation: schema enumerates exactly the four config keys with
# true|false|"ask", ships defaults, stable $id, additionalProperties:false;
# default file carries $schema raw-URL + shipped values.
echo ""
echo "Check 17: se-config schema + default JSON"

SCHEMA_URL='https://raw.githubusercontent.com/mek-earnin/super-exec/main/plugin/skills/se-config/se-config.schema.json'
schema_file="${REPO_ROOT}/plugin/skills/se-config/se-config.schema.json"
default_file="${REPO_ROOT}/plugin/skills/se-get-config/se-config.default.json"

se_config_contract_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" SCHEMA_URL="$SCHEMA_URL" node >"$se_config_contract_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const repoRoot = process.env.REPO_ROOT;
const schemaUrl = process.env.SCHEMA_URL;
const problems = [];

const CONFIG_KEYS = [
  'commitSpec',
  'commitPlan',
  'humanReviewBeforeCheckpointCommit',
  'autoCreatePr',
];
const ALLOWED = [true, false, 'ask'];
const ALLOWED_COMMIT_PLAN = ['inheritSpec', false, 'ask'];
const DEFAULTS = {
  commitSpec: 'ask',
  commitPlan: 'ask',
  humanReviewBeforeCheckpointCommit: 'ask',
  autoCreatePr: 'ask',
};

function allowedFor(key) {
  return key === 'commitPlan' ? ALLOWED_COMMIT_PLAN : ALLOWED;
}

function sameSet(a, b) {
  return a.length === b.length && a.every((x) => b.includes(x));
}

function sameEnum(actual, allowed) {
  if (!Array.isArray(actual) || actual.length !== allowed.length) return false;
  return allowed.every((v) => actual.some((x) => Object.is(x, v)));
}

let schema;
let defaults;
try {
  schema = JSON.parse(fs.readFileSync(path.join(repoRoot, 'plugin/skills/se-config/se-config.schema.json'), 'utf8'));
} catch (e) {
  problems.push('schema not valid JSON: ' + e.message);
}
try {
  defaults = JSON.parse(fs.readFileSync(path.join(repoRoot, 'plugin/skills/se-get-config/se-config.default.json'), 'utf8'));
} catch (e) {
  problems.push('default not valid JSON: ' + e.message);
}

if (schema) {
  if (schema.$id !== schemaUrl) {
    problems.push(`schema $id expected ${schemaUrl}, got ${JSON.stringify(schema.$id)}`);
  }
  if (schema.additionalProperties !== false) {
    problems.push(`schema additionalProperties expected false, got ${JSON.stringify(schema.additionalProperties)}`);
  }
  if (!schema.properties || typeof schema.properties !== 'object') {
    problems.push('schema missing properties object');
  } else {
    const propKeys = Object.keys(schema.properties).filter((k) => k !== '$schema');
    if (!sameSet(propKeys, CONFIG_KEYS)) {
      problems.push(`schema config keys expected [${CONFIG_KEYS.join(', ')}], got [${propKeys.join(', ')}]`);
    }
    for (const key of CONFIG_KEYS) {
      const prop = schema.properties[key];
      if (!prop) {
        problems.push(`schema missing property: ${key}`);
        continue;
      }
      const allowed = allowedFor(key);
      if (!sameEnum(prop.enum, allowed)) {
        problems.push(`schema ${key}.enum expected ${JSON.stringify(allowed)}, got ${JSON.stringify(prop.enum)}`);
      }
      if (!Object.is(prop.default, DEFAULTS[key])) {
        problems.push(`schema ${key}.default expected ${JSON.stringify(DEFAULTS[key])}, got ${JSON.stringify(prop.default)}`);
      }
    }
  }
}

if (defaults) {
  if (defaults.$schema !== schemaUrl) {
    problems.push(`default $schema expected ${schemaUrl}, got ${JSON.stringify(defaults.$schema)}`);
  }
  const defaultKeys = Object.keys(defaults).filter((k) => k !== '$schema');
  if (!sameSet(defaultKeys, CONFIG_KEYS)) {
    problems.push(`default config keys expected [${CONFIG_KEYS.join(', ')}], got [${defaultKeys.join(', ')}]`);
  }
  for (const key of CONFIG_KEYS) {
    if (!Object.is(defaults[key], DEFAULTS[key])) {
      problems.push(`default ${key} expected ${JSON.stringify(DEFAULTS[key])}, got ${JSON.stringify(defaults[key])}`);
    }
  }
}

process.stdout.write(problems.length ? problems.join('\n') : 'ok');
NODE
then
  se_config_contract_result="$(<"$se_config_contract_output")"
else
  se_config_contract_result="ERROR"
fi
rm -f "$se_config_contract_output"

if [ ! -f "$schema_file" ]; then
  fail "se-config schema file missing: plugin/skills/se-config/se-config.schema.json"
elif [ ! -f "$default_file" ]; then
  fail "se-config default file missing: plugin/skills/se-get-config/se-config.default.json"
elif [ "$se_config_contract_result" = "ok" ]; then
  pass "se-config schema + default JSON match the four-key contract"
else
  fail "se-config schema/default contract problem:"
  echo "$se_config_contract_result" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Check 18 — get-merged-config lenient merge + se-get-config skill
# ---------------------------------------------------------------------------
# Task 2: internal se-get-config skill + zero-dep get-merged-config script.
# Assert exact effective JSON for precedence, malformed-tier skip, invalid-value
# drop, missing files → defaults; plus repo-env precedence and executable bit.
echo ""
echo "Check 18: get-merged-config merge + se-get-config skill"

gmc_script="${REPO_ROOT}/plugin/skills/se-get-config/get-merged-config"
gmc_skill="${REPO_ROOT}/plugin/skills/se-get-config/SKILL.md"

if [ -f "$gmc_skill" ]; then
  gmc_fm=$(node -e "
    const fs = require('fs');
    const c = fs.readFileSync('${gmc_skill}', 'utf8');
    if (!c.startsWith('---')) { process.stdout.write('no frontmatter'); process.exit(1); }
    const end = c.slice(3).indexOf('\n---');
    if (end === -1) { process.stdout.write('unclosed frontmatter'); process.exit(1); }
    const fm = c.slice(3, 3 + end);
    const name = (fm.match(/^name:\\s*(.+)/m) || [])[1];
    const inv = (fm.match(/^user-invocable:\\s*(.+)/m) || [])[1];
    const issues = [];
    if (name !== 'se-get-config') issues.push('name=' + JSON.stringify(name));
    if (String(inv).trim() !== 'false') issues.push('user-invocable=' + JSON.stringify(inv));
    process.stdout.write(issues.length ? issues.join('; ') : 'ok');
  " 2>/dev/null || echo "ERROR")
  if [ "$gmc_fm" = "ok" ]; then
    pass "se-get-config SKILL.md frontmatter (name + user-invocable: false)"
  else
    fail "se-get-config SKILL.md frontmatter problem: ${gmc_fm}"
  fi
  if grep -qF '@./get-merged-config' "$gmc_skill" 2>/dev/null; then
    pass "se-get-config SKILL.md invokes @./get-merged-config"
  else
    fail "se-get-config SKILL.md missing @./get-merged-config reference"
  fi
  if grep -qiE 'no diagnostics|never.*diagnostics|does not surface diagnostics' "$gmc_skill" 2>/dev/null \
     && grep -qiE 'lenient|malformed|invalid value' "$gmc_skill" 2>/dev/null; then
    pass "se-get-config SKILL.md documents lenient merge + no diagnostics"
  else
    fail "se-get-config SKILL.md missing lenient/no-diagnostics docs"
  fi
else
  fail "se-get-config SKILL.md missing"
fi

if [ -x "$gmc_script" ]; then
  pass "get-merged-config is executable"
else
  fail "get-merged-config missing or not executable"
fi

if ! command -v git >/dev/null 2>&1; then
  fail "git not available — cannot test get-merged-config behavior"
elif [ ! -x "$gmc_script" ]; then
  fail "get-merged-config not executable — cannot run merge behavior tests"
else
  gmctmp=$(mktemp -d)
  gmcrepo="${gmctmp}/repo"
  gmchome="${gmctmp}/home"
  mkdir -p "$gmcrepo" "$gmchome"
  ( cd "$gmcrepo" && git init -q ) 2>/dev/null || true

  EXPECT_DEFAULTS='{"commitSpec":"ask","commitPlan":"ask","humanReviewBeforeCheckpointCommit":"ask","autoCreatePr":"ask"}'
  EXPECT_PRECEDENCE='{"commitSpec":true,"commitPlan":"inheritSpec","humanReviewBeforeCheckpointCommit":false,"autoCreatePr":"ask"}'
  EXPECT_MALFORMED='{"commitSpec":false,"commitPlan":"ask","humanReviewBeforeCheckpointCommit":"ask","autoCreatePr":"ask"}'
  EXPECT_INVALID='{"commitSpec":true,"commitPlan":"ask","humanReviewBeforeCheckpointCommit":"ask","autoCreatePr":false}'

  run_gmc() {
    # $1 = HOME, $2 = CLAUDE_PROJECT_DIR (empty to unset), optional $3 = CURSOR_PROJECT_DIR, $4 = cwd
    local _home="$1" _claude="$2" _cursor="${3:-}" _cwd="${4:-$gmcrepo}"
    (
      cd "$_cwd" || exit 1
      if [ -n "$_claude" ] && [ -n "$_cursor" ]; then
        env -i PATH="$PATH" HOME="$_home" CLAUDE_PROJECT_DIR="$_claude" CURSOR_PROJECT_DIR="$_cursor" \
          "$gmc_script"
      elif [ -n "$_claude" ]; then
        env -i PATH="$PATH" HOME="$_home" CLAUDE_PROJECT_DIR="$_claude" \
          "$gmc_script"
      elif [ -n "$_cursor" ]; then
        env -i PATH="$PATH" HOME="$_home" CURSOR_PROJECT_DIR="$_cursor" \
          "$gmc_script"
      else
        env -i PATH="$PATH" HOME="$_home" \
          "$gmc_script"
      fi
    )
  }

  # --- missing local + user → all defaults ---
  out=$(run_gmc "$gmchome" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_DEFAULTS" ]; then
    pass "get-merged-config missing tiers → all defaults"
  else
    fail "get-merged-config missing tiers expected ${EXPECT_DEFAULTS} got ${out}"
  fi

  # --- local > user > default precedence ---
  # local: commitSpec/commitPlan (commitPlan:"inheritSpec" — valid under new contract);
  # user: humanReview (and lower commit* overridden);
  # autoCreatePr absent in both → default "ask"
  mkdir -p "${gmcrepo}/.super-exec" "${gmchome}/.super-exec"
  cat >"${gmcrepo}/.super-exec/se-config.local.json" <<'EOF'
{"commitSpec":true,"commitPlan":"inheritSpec"}
EOF
  cat >"${gmchome}/.super-exec/se-config.json" <<'EOF'
{"commitSpec":false,"commitPlan":false,"humanReviewBeforeCheckpointCommit":false}
EOF

  out=$(run_gmc "$gmchome" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_PRECEDENCE" ]; then
    pass "get-merged-config local > user > default precedence"
  else
    fail "get-merged-config precedence expected ${EXPECT_PRECEDENCE} got ${out}"
  fi

  # --- malformed local tier skipped whole; user still applies ---
  printf '{not json' >"${gmcrepo}/.super-exec/se-config.local.json"
  cat >"${gmchome}/.super-exec/se-config.json" <<'EOF'
{"commitSpec":false}
EOF
  out=$(run_gmc "$gmchome" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_MALFORMED" ]; then
    pass "get-merged-config malformed local tier skipped whole"
  else
    fail "get-merged-config malformed-tier expected ${EXPECT_MALFORMED} got ${out}"
  fi

  # --- invalid value drops only that key; valid sibling applies ---
  cat >"${gmcrepo}/.super-exec/se-config.local.json" <<'EOF'
{"commitSpec":true,"commitPlan":"yes","autoCreatePr":false}
EOF
  rm -f "${gmchome}/.super-exec/se-config.json"
  out=$(run_gmc "$gmchome" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_INVALID" ]; then
    pass "get-merged-config invalid value drops only that key"
  else
    fail "get-merged-config invalid-value expected ${EXPECT_INVALID} got ${out}"
  fi

  # --- repo env precedence: CLAUDE_PROJECT_DIR wins over CURSOR + cwd ---
  otherrepo="${gmctmp}/other"
  mkdir -p "${otherrepo}/.super-exec"
  ( cd "$otherrepo" && git init -q ) 2>/dev/null || true
  # otherrepo's commitPlan:true is legacy — now invalid → treated as absent →
  # no lower tier provides it (home tier removed above) → "ask" default
  cat >"${otherrepo}/.super-exec/se-config.local.json" <<'EOF'
{"commitSpec":false,"commitPlan":true,"humanReviewBeforeCheckpointCommit":true,"autoCreatePr":false}
EOF
  # Reset primary repo local to a distinct value
  cat >"${gmcrepo}/.super-exec/se-config.local.json" <<'EOF'
{"commitSpec":true}
EOF
  EXPECT_CLAUDE='{"commitSpec":true,"commitPlan":"ask","humanReviewBeforeCheckpointCommit":"ask","autoCreatePr":"ask"}'
  EXPECT_OTHER='{"commitSpec":false,"commitPlan":"ask","humanReviewBeforeCheckpointCommit":true,"autoCreatePr":false}'

  out=$(run_gmc "$gmchome" "$gmcrepo" "$otherrepo" "$otherrepo" || true)
  if [ "$out" = "$EXPECT_CLAUDE" ]; then
    pass "get-merged-config CLAUDE_PROJECT_DIR wins over CURSOR_PROJECT_DIR"
  else
    fail "get-merged-config CLAUDE precedence expected ${EXPECT_CLAUDE} got ${out}"
  fi

  out=$(run_gmc "$gmchome" "" "$otherrepo" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_OTHER" ]; then
    pass "get-merged-config CURSOR_PROJECT_DIR used when CLAUDE unset"
  else
    fail "get-merged-config CURSOR fallback expected ${EXPECT_OTHER} got ${out}"
  fi

  out=$(run_gmc "$gmchome" "" "" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_CLAUDE" ]; then
    pass "get-merged-config falls back to cwd when project env unset"
  else
    fail "get-merged-config cwd fallback expected ${EXPECT_CLAUDE} got ${out}"
  fi

  # --- commitPlan new contract: "inheritSpec" | false | "ask" (default "ask") ---
  # Home tier stays absent (removed above) for the rest of these cases so
  # commitPlan resolution is driven solely by the local tier / embedded default.

  # (a) commitPlan:"inheritSpec" is a valid value and merges through unchanged
  cat >"${gmcrepo}/.super-exec/se-config.local.json" <<'EOF'
{"commitPlan":"inheritSpec"}
EOF
  EXPECT_INHERITSPEC='{"commitSpec":"ask","commitPlan":"inheritSpec","humanReviewBeforeCheckpointCommit":"ask","autoCreatePr":"ask"}'
  out=$(run_gmc "$gmchome" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_INHERITSPEC" ]; then
    pass "get-merged-config commitPlan inheritSpec merges through unchanged"
  else
    fail "get-merged-config commitPlan inheritSpec expected ${EXPECT_INHERITSPEC} got ${out}"
  fi

  # (b) legacy commitPlan:true is now invalid → treated as absent → "ask" default
  cat >"${gmcrepo}/.super-exec/se-config.local.json" <<'EOF'
{"commitPlan":true}
EOF
  EXPECT_LEGACY_TRUE='{"commitSpec":"ask","commitPlan":"ask","humanReviewBeforeCheckpointCommit":"ask","autoCreatePr":"ask"}'
  out=$(run_gmc "$gmchome" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_LEGACY_TRUE" ]; then
    pass "get-merged-config legacy commitPlan:true is invalid → falls to ask default"
  else
    fail "get-merged-config legacy commitPlan:true expected ${EXPECT_LEGACY_TRUE} got ${out}"
  fi

  # (c) commitPlan:"ask" is still valid and merges through
  cat >"${gmcrepo}/.super-exec/se-config.local.json" <<'EOF'
{"commitPlan":"ask"}
EOF
  EXPECT_COMMITPLAN_ASK='{"commitSpec":"ask","commitPlan":"ask","humanReviewBeforeCheckpointCommit":"ask","autoCreatePr":"ask"}'
  out=$(run_gmc "$gmchome" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_COMMITPLAN_ASK" ]; then
    pass "get-merged-config commitPlan ask still valid, merges through"
  else
    fail "get-merged-config commitPlan ask expected ${EXPECT_COMMITPLAN_ASK} got ${out}"
  fi

  # (d) embedded default for commitPlan is "ask" when unset in all tiers
  cat >"${gmcrepo}/.super-exec/se-config.local.json" <<'EOF'
{"commitSpec":true,"autoCreatePr":false}
EOF
  EXPECT_COMMITPLAN_UNSET='{"commitSpec":true,"commitPlan":"ask","humanReviewBeforeCheckpointCommit":"ask","autoCreatePr":false}'
  out=$(run_gmc "$gmchome" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_COMMITPLAN_UNSET" ]; then
    pass "get-merged-config commitPlan defaults to ask when unset in all tiers"
  else
    fail "get-merged-config commitPlan unset expected ${EXPECT_COMMITPLAN_UNSET} got ${out}"
  fi

  # (e) sanity: the other three keys still accept true/false/"ask" unchanged
  # (commitSpec:true merges through; humanReview:false and autoCreatePr:"ask" too)
  cat >"${gmcrepo}/.super-exec/se-config.local.json" <<'EOF'
{"commitSpec":true,"humanReviewBeforeCheckpointCommit":false,"autoCreatePr":"ask"}
EOF
  EXPECT_OTHER_KEYS_SANITY='{"commitSpec":true,"commitPlan":"ask","humanReviewBeforeCheckpointCommit":false,"autoCreatePr":"ask"}'
  out=$(run_gmc "$gmchome" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_OTHER_KEYS_SANITY" ]; then
    pass "get-merged-config other three keys still accept true/false/ask (commitSpec:true merges through)"
  else
    fail "get-merged-config other-keys sanity expected ${EXPECT_OTHER_KEYS_SANITY} got ${out}"
  fi

  # (f) commitPlan:false is a valid first-class value and merges through as false
  cat >"${gmcrepo}/.super-exec/se-config.local.json" <<'EOF'
{"commitPlan":false}
EOF
  EXPECT_COMMITPLAN_FALSE='{"commitSpec":"ask","commitPlan":false,"humanReviewBeforeCheckpointCommit":"ask","autoCreatePr":"ask"}'
  out=$(run_gmc "$gmchome" "$gmcrepo" || true)
  if [ "$out" = "$EXPECT_COMMITPLAN_FALSE" ]; then
    pass "get-merged-config commitPlan false is valid, merges through as false"
  else
    fail "get-merged-config commitPlan false expected ${EXPECT_COMMITPLAN_FALSE} got ${out}"
  fi

  rm -rf "$gmctmp"
fi

# ---------------------------------------------------------------------------
# Check 19 — se-slug-naming skill (prose-only naming convention)
# ---------------------------------------------------------------------------
# Task 3: internal se-slug-naming skill — shared naming-convention authority.
# Assert user-invocable: false, prose-only (dir contains only SKILL.md; no
# sibling scripts), and that the drop-rule list + worked example are embedded.
echo ""
echo "Check 19: se-slug-naming skill (prose-only naming convention)"

slug_skill_dir="${REPO_ROOT}/plugin/skills/se-slug-naming"
slug_skill="${slug_skill_dir}/SKILL.md"

if [ -f "$slug_skill" ]; then
  pass "se-slug-naming/SKILL.md exists"
else
  fail "se-slug-naming/SKILL.md missing"
fi

if [ -f "$slug_skill" ]; then
  slug_fm=$(node -e "
    const fs = require('fs');
    const c = fs.readFileSync('${slug_skill}', 'utf8');
    if (!c.startsWith('---')) { process.stdout.write('no frontmatter'); process.exit(1); }
    const end = c.slice(3).indexOf('\n---');
    if (end === -1) { process.stdout.write('unclosed frontmatter'); process.exit(1); }
    const fm = c.slice(3, 3 + end);
    const name = (fm.match(/^name:\\s*(.+)/m) || [])[1];
    const inv = (fm.match(/^user-invocable:\\s*(.+)/m) || [])[1];
    const issues = [];
    if (String(name).trim() !== 'se-slug-naming') issues.push('name=' + JSON.stringify(name));
    if (String(inv).trim() !== 'false') issues.push('user-invocable=' + JSON.stringify(inv));
    process.stdout.write(issues.length ? issues.join('; ') : 'ok');
  " 2>/dev/null || echo "ERROR")
  if [ "$slug_fm" = "ok" ]; then
    pass "se-slug-naming SKILL.md frontmatter (name + user-invocable: false)"
  else
    fail "se-slug-naming SKILL.md frontmatter problem: ${slug_fm}"
  fi

  # Prose-only: skill dir must contain only SKILL.md (no sibling scripts/executables).
  slug_extras=$(find "$slug_skill_dir" -mindepth 1 -maxdepth 1 ! -name 'SKILL.md' 2>/dev/null || true)
  if [ -z "$slug_extras" ]; then
    pass "se-slug-naming is prose-only (dir contains only SKILL.md)"
  else
    fail "se-slug-naming must be prose-only (no sibling scripts); found: $(echo "$slug_extras" | tr '\n' ' ')"
  fi

  # Drop-rule list + worked example must be present in the skill body.
  # Assert ALL FIVE drop categories via substantive content (token lists / labels),
  # not rubber-stamp header words that also appear in intro prose (e.g. "filler").
  if grep -qE '`a`[[:space:]]*/[[:space:]]*`an`[[:space:]]*/[[:space:]]*`the`|\ba\b[[:space:]]*/[[:space:]]*.*[[:space:]]*/[[:space:]]*.*\bthe\b' "$slug_skill" 2>/dev/null \
     && grep -qE '`is`[[:space:]]*/.*/.*`being`|\bis\b[[:space:]]*/.*/.*\bbeing\b' "$slug_skill" 2>/dev/null \
     && grep -qE '`just`[[:space:]]*/.*/.*`simply`|\bjust\b[[:space:]]*/.*/.*\bsimply\b' "$slug_skill" 2>/dev/null \
     && grep -qiE 'pleasantries' "$slug_skill" 2>/dev/null \
     && grep -qiE 'hedging' "$slug_skill" 2>/dev/null; then
    pass "se-slug-naming embeds drop-rule list (articles, be-verbs, filler, pleasantries, hedging)"
  else
    fail "se-slug-naming missing embedded drop-rule list (articles / be-verbs / filler / pleasantries / hedging)"
  fi

  if grep -qF 'local-only-plans-specs-are-the-shared-contract' "$slug_skill" 2>/dev/null \
     && grep -qF 'local-only-plans-specs-shared-contract' "$slug_skill" 2>/dev/null; then
    pass "se-slug-naming includes worked example string"
  else
    fail "se-slug-naming missing worked example (local-only-plans-specs-are-the-shared-contract → local-only-plans-specs-shared-contract)"
  fi

  if grep -qiE 'forward-only|FORWARD-ONLY' "$slug_skill" 2>/dev/null \
     && grep -qiE 'never recompress|migration never recompress' "$slug_skill" 2>/dev/null; then
    pass "se-slug-naming states FORWARD-ONLY (migrate never recompresses)"
  else
    fail "se-slug-naming missing FORWARD-ONLY / never-recompress statement"
  fi

  if grep -qiE 'self-contained|embeds the drop' "$slug_skill" 2>/dev/null \
     && grep -qiE 'does([[:space:]]|\*)+NOT([[:space:]]|\*)+depend|does not depend' "$slug_skill" 2>/dev/null \
     && grep -qiF 'caveman' "$slug_skill" 2>/dev/null; then
    pass "se-slug-naming states self-contained (no external caveman dependency)"
  else
    fail "se-slug-naming missing self-contained / no-external-caveman statement"
  fi
fi

# ---------------------------------------------------------------------------
# Check 20 — se-config skill: print + set (Task 4)
# ---------------------------------------------------------------------------
# Human read/write surface. CLI owns raw-tier print + validated set; Effective
# (merged) is SKILL-level via /se-get-config — CLI must NOT merge or shell out
# to get-merged-config. migrate coverage lives in Check 21.
echo ""
echo "Check 20: se-config skill print + set"

secfg_cli="${REPO_ROOT}/plugin/skills/se-config/se-config-cli"
secfg_skill="${REPO_ROOT}/plugin/skills/se-config/SKILL.md"
SCHEMA_URL_SET='https://raw.githubusercontent.com/mek-earnin/super-exec/main/plugin/skills/se-config/se-config.schema.json'

if [ -f "$secfg_skill" ]; then
  secfg_fm=$(node -e "
    const fs = require('fs');
    const c = fs.readFileSync('${secfg_skill}', 'utf8');
    if (!c.startsWith('---')) { process.stdout.write('no frontmatter'); process.exit(1); }
    const end = c.slice(3).indexOf('\n---');
    if (end === -1) { process.stdout.write('unclosed frontmatter'); process.exit(1); }
    const fm = c.slice(3, 3 + end);
    const name = (fm.match(/^name:\\s*(.+)/m) || [])[1];
    const dmi = (fm.match(/^disable-model-invocation:\\s*(.+)/m) || [])[1];
    const inv = (fm.match(/^user-invocable:\\s*(.+)/m) || [])[1];
    const issues = [];
    if (String(name).trim() !== 'se-config') issues.push('name=' + JSON.stringify(name));
    if (String(dmi).trim() !== 'true') issues.push('disable-model-invocation=' + JSON.stringify(dmi));
    if (inv !== undefined && String(inv).trim() === 'false') {
      issues.push('user-invocable must not be false');
    }
    process.stdout.write(issues.length ? issues.join('; ') : 'ok');
  " 2>/dev/null || echo "ERROR")
  if [ "$secfg_fm" = "ok" ]; then
    pass "se-config SKILL.md frontmatter (name + disable-model-invocation: true)"
  else
    fail "se-config SKILL.md frontmatter problem: ${secfg_fm}"
  fi

  # Unsupported hosts preserve manual-only intent through read-first behavior.
  cursor_tools_ref="${REPO_ROOT}/plugin/skills/using-super-exec/references/cursor-tools.md"
  disable_mapping_result="$(REPO_ROOT="$REPO_ROOT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const text = fs.readFileSync(path.join(process.env.REPO_ROOT, 'plugin/skills/using-super-exec/references/cursor-tools.md'), 'utf8').toLowerCase();
const has = terms => terms.every(term => text.includes(term));
const valid = has(['disable-model-invocation', 'manual-only', 'safe read-first', 'mutations require explicit arguments']);
process.stdout.write(valid ? 'ok' : 'manual-only fallback mapping missing');
NODE
)"
  if [ "$disable_mapping_result" = "ok" ]; then
    pass "cursor-tools.md maps manual-only behavior with safe read-first fallback"
  else
    fail "cursor-tools.md missing manual-only safe read-first fallback mapping"
  fi

  if grep -qF '@./se-config-cli' "$secfg_skill" 2>/dev/null; then
    pass "se-config SKILL.md invokes @./se-config-cli"
  else
    fail "se-config SKILL.md missing @./se-config-cli reference"
  fi

  if grep -qF '/se-get-config' "$secfg_skill" 2>/dev/null \
     && grep -qiE 'Effective \(merged\)|effective \(merged\)' "$secfg_skill" 2>/dev/null \
     && grep -qiE 'no other skill' "$secfg_skill" 2>/dev/null; then
    pass "se-config SKILL.md documents Effective via /se-get-config + exclusivity"
  else
    fail "se-config SKILL.md missing Effective/se-get-config or exclusivity docs"
  fi
else
  fail "se-config SKILL.md missing"
fi

if [ -x "$secfg_cli" ]; then
  pass "se-config-cli is executable"
else
  fail "se-config-cli missing or not executable"
fi

# Hard architectural constraint: CLI must not couple to se-get-config files.
if [ -f "$secfg_cli" ]; then
  if grep -qiE 'get-merged-config|se-get-config' "$secfg_cli" 2>/dev/null; then
    # Comments mentioning the constraint are OK; requiring/shelling-out is not.
    if grep -qE "require\\(.*get-merged-config|spawn.*get-merged-config|exec.*get-merged-config|se-get-config/" "$secfg_cli" 2>/dev/null; then
      fail "se-config-cli must not require/shell-out to get-merged-config / se-get-config"
    else
      pass "se-config-cli has no runtime coupling to se-get-config"
    fi
  else
    pass "se-config-cli has no runtime coupling to se-get-config"
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  fail "git not available — cannot test se-config-cli behavior"
elif [ ! -x "$secfg_cli" ]; then
  fail "se-config-cli not executable — cannot run print/set behavior tests"
else
  secfgtmp=$(mktemp -d)
  secfgrepo="${secfgtmp}/repo"
  secfghome="${secfgtmp}/home"
  mkdir -p "$secfgrepo" "$secfghome"
  ( cd "$secfgrepo" && git init -q ) 2>/dev/null || true

  run_secfg() {
    # Args after env: forwarded to se-config-cli
    local _home="$1" _claude="$2"
    shift 2
    (
      cd "$secfgrepo" || exit 1
      env -i PATH="$PATH" HOME="$_home" CLAUDE_PROJECT_DIR="$_claude" \
        "$secfg_cli" "$@"
    )
  }

  # --- set: accept each valid value for a valid key ---
  set_ok=1
  for val in true false ask; do
    if ! run_secfg "$secfghome" "$secfgrepo" set local commitSpec "$val" >/dev/null 2>&1; then
      set_ok=0
      fail "se-config-cli set rejected valid value ${val}"
    fi
  done
  if [ "$set_ok" -eq 1 ]; then
    pass "se-config-cli set accepts true|false|ask"
  fi

  # --- set: reject invalid key ---
  if run_secfg "$secfghome" "$secfgrepo" set local notAKey true >/dev/null 2>&1; then
    fail "se-config-cli set should reject invalid key"
  else
    pass "se-config-cli set rejects invalid key"
  fi

  # --- set: reject invalid value ---
  if run_secfg "$secfghome" "$secfgrepo" set local commitSpec yes >/dev/null 2>&1; then
    fail "se-config-cli set should reject invalid value"
  else
    pass "se-config-cli set rejects invalid value"
  fi

  # --- set: reject target default ---
  if run_secfg "$secfghome" "$secfgrepo" set default commitSpec true >/dev/null 2>&1; then
    fail "se-config-cli set should reject target default"
  else
    pass "se-config-cli set rejects target default"
  fi

  # --- set: creates tier file WITH $schema; update preserves sibling key ---
  rm -rf "${secfgrepo}/.super-exec" "${secfghome}/.super-exec"
  run_secfg "$secfghome" "$secfgrepo" set local commitSpec true >/dev/null 2>&1 || true
  run_secfg "$secfghome" "$secfgrepo" set local commitPlan false >/dev/null 2>&1 || true
  set_file_check=$(node -e "
    const fs = require('fs');
    const p = '${secfgrepo}/.super-exec/se-config.local.json';
    let obj;
    try { obj = JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) {
      process.stdout.write('parse-fail:' + e.message); process.exit(0);
    }
    const issues = [];
    if (obj['\$schema'] !== '${SCHEMA_URL_SET}') issues.push('\$schema=' + JSON.stringify(obj['\$schema']));
    if (obj.commitSpec !== true) issues.push('commitSpec=' + JSON.stringify(obj.commitSpec));
    if (obj.commitPlan !== false) issues.push('commitPlan=' + JSON.stringify(obj.commitPlan));
    process.stdout.write(issues.length ? issues.join('; ') : 'ok');
  " 2>/dev/null || echo "ERROR")
  if [ "$set_file_check" = "ok" ]; then
    pass "se-config-cli set creates file with \$schema and preserves sibling key"
  else
    fail "se-config-cli set file content problem: ${set_file_check}"
  fi

  # --- set user tier also creates under HOME ---
  run_secfg "$secfghome" "$secfgrepo" set user autoCreatePr ask >/dev/null 2>&1 || true
  if [ -f "${secfghome}/.super-exec/se-config.json" ]; then
    pass "se-config-cli set user writes ~/.super-exec/se-config.json"
  else
    fail "se-config-cli set user did not create user tier file"
  fi

  # --- unknown subcommand → non-zero (migrate is a real subcommand now) ---
  if run_secfg "$secfghome" "$secfgrepo" not-a-real-cmd >/dev/null 2>&1; then
    fail "se-config-cli unknown subcommand should exit non-zero"
  else
    pass "se-config-cli unknown subcommand exits non-zero"
  fi

  # --- print: local block then user block; never a default block ---
  mkdir -p "${secfgrepo}/.super-exec" "${secfghome}/.super-exec"
  cat >"${secfgrepo}/.super-exec/se-config.local.json" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/mek-earnin/super-exec/main/plugin/skills/se-config/se-config.schema.json",
  "commitSpec": true
}
EOF
  cat >"${secfghome}/.super-exec/se-config.json" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/mek-earnin/super-exec/main/plugin/skills/se-config/se-config.schema.json",
  "commitPlan": false
}
EOF
  print_out=$(run_secfg "$secfghome" "$secfgrepo" print 2>/dev/null || true)
  print_order_ok=$(node -e "
    const out = process.argv[1];
    const localIdx = out.search(/===\\s*local\\s*===/i);
    const userIdx = out.search(/===\\s*user\\s*===/i);
    const defaultIdx = out.search(/===\\s*default\\s*===/i);
    const issues = [];
    if (localIdx < 0) issues.push('missing local block');
    if (userIdx < 0) issues.push('missing user block');
    if (localIdx >= 0 && userIdx >= 0 && !(localIdx < userIdx)) issues.push('local must precede user');
    if (defaultIdx >= 0) issues.push('must not render default block');
    if (!/\"commitSpec\":\\s*true/.test(out)) issues.push('local commitSpec missing in output');
    if (!/\"commitPlan\":\\s*false/.test(out)) issues.push('user commitPlan missing in output');
    process.stdout.write(issues.length ? issues.join('; ') : 'ok');
  " "$print_out" 2>/dev/null || echo "ERROR")
  if [ "$print_order_ok" = "ok" ]; then
    pass "se-config-cli print shows local then user; never default"
  else
    fail "se-config-cli print ordering problem: ${print_order_ok}"
  fi

  # --- print: malformed local flagged as diagnostic ---
  printf '{not json' >"${secfgrepo}/.super-exec/se-config.local.json"
  print_malformed=$(run_secfg "$secfghome" "$secfgrepo" print 2>/dev/null || true)
  if echo "$print_malformed" | grep -qiE 'MALFORMED|invalid JSON|diagnostic' \
     && echo "$print_malformed" | grep -qiE 'local'; then
    pass "se-config-cli print flags malformed local as diagnostic"
  else
    fail "se-config-cli print missing malformed-local diagnostic"
  fi

  # --- print: invalid value for known key flagged as diagnostic ---
  cat >"${secfgrepo}/.super-exec/se-config.local.json" <<'EOF'
{
  "commitSpec": true,
  "commitPlan": "yes"
}
EOF
  print_invalid=$(run_secfg "$secfghome" "$secfgrepo" print 2>/dev/null || true)
  if echo "$print_invalid" | grep -qiE 'diagnostic:.*invalid value.*commitPlan|invalid value for "commitPlan"'; then
    pass "se-config-cli print flags invalid value as diagnostic"
  else
    fail "se-config-cli print missing invalid-value diagnostic"
  fi

  rm -rf "$secfgtmp"
fi

# ---------------------------------------------------------------------------
# Check 21 — se-config migrate (Task 5)
# ---------------------------------------------------------------------------
# Manual v0→v1 structural migration. ALL fixtures live in mktemp -d — never
# touch the real super-exec repo or real $HOME.
echo ""
echo "Check 21: se-config migrate (v0→v1)"

mig_cli="${REPO_ROOT}/plugin/skills/se-config/se-config-cli"
mig_skill="${REPO_ROOT}/plugin/skills/se-config/SKILL.md"

if [ -f "$mig_skill" ]; then
  if grep -qE 'migrate' "$mig_skill" 2>/dev/null \
     && grep -qE -- '--apply' "$mig_skill" 2>/dev/null \
     && grep -qiE 'dry-run|DRY-RUN|dry run' "$mig_skill" 2>/dev/null \
     && grep -qiE 'idempotent' "$mig_skill" 2>/dev/null; then
    pass "se-config SKILL.md documents migrate (dry-run, --apply, idempotent)"
  else
    fail "se-config SKILL.md missing migrate docs (dry-run / --apply / idempotent)"
  fi
else
  fail "se-config SKILL.md missing"
fi

if ! command -v git >/dev/null 2>&1; then
  fail "git not available — cannot test se-config migrate"
elif [ ! -x "$mig_cli" ]; then
  fail "se-config-cli not executable — cannot test migrate"
else
  migtmp=$(mktemp -d)
  migrepo="${migtmp}/repo"
  mighome="${migtmp}/home"
  mkdir -p "$migrepo" "$mighome"
  (
    cd "$migrepo" || exit 1
    git init -q
    git config user.email "migrate-test@example.com"
    git config user.name "Migrate Test"
  ) 2>/dev/null || true

  run_mig() {
    local _home="$1" _claude="$2"
    shift 2
    (
      cd "$migrepo" || exit 1
      env -i PATH="$PATH" HOME="$_home" CLAUDE_PROJECT_DIR="$_claude" \
        "$mig_cli" "$@"
    )
  }

  # --- Build v0 fixture matrix (all inside migrepo) ---
  mkdir -p \
    "${migrepo}/docs/specs" \
    "${migrepo}/docs/specs/payments" \
    "${migrepo}/docs/specs/already-feature" \
    "${migrepo}/docs/adr" \
    "${migrepo}/.super-exec/0003-widget-feature/2026-07-20-widget-plan" \
    "${migrepo}/.super-exec/payments/0001-cashout/2026-06-01-cashout-v1"

  # TRACKED spec
  cat >"${migrepo}/docs/specs/0002-tracked-feature.md" <<'EOF'
# tracked-feature
> Ticket: NO_TICKET
EOF
  # UNTRACKED spec
  cat >"${migrepo}/docs/specs/0004-untracked-feature.md" <<'EOF'
# untracked-feature
EOF
  # Monorepo <app> tracked spec
  cat >"${migrepo}/docs/specs/payments/0007-payout-flow.md" <<'EOF'
# payout-flow (monorepo)
EOF
  # Numbered GLOBAL ADR (tracked)
  cat >"${migrepo}/docs/adr/0005-global-decision.md" <<'EOF'
# ADR: global-decision
EOF
  # Already-v1 dir (must be skipped)
  cat >"${migrepo}/docs/specs/already-feature/spec-already-feature.md" <<'EOF'
# already-feature (v1)
EOF
  # Already-unnumbered ADR (must be skipped)
  cat >"${migrepo}/docs/adr/plain-slug.md" <<'EOF'
# already unnumbered ADR
EOF

  # Plan + handoff with Spec:/Plan: pointers
  cat >"${migrepo}/.super-exec/0003-widget-feature/2026-07-20-widget-plan/plan.md" <<'EOF'
# widget plan
## Goal
Build widgets. Spec: `docs/specs/0002-tracked-feature.md`
EOF
  cat >"${migrepo}/.super-exec/0003-widget-feature/2026-07-20-widget-plan/handoff.md" <<'EOF'
# Handoff
## Session State
- Plan: .super-exec/0003-widget-feature/2026-07-20-widget-plan/plan.md
EOF

  # Monorepo plan
  cat >"${migrepo}/.super-exec/payments/0001-cashout/2026-06-01-cashout-v1/plan.md" <<'EOF'
# cashout plan
Spec: `docs/specs/payments/0007-payout-flow.md`
EOF

  # active marker with spec: + active_plan: (both rewritten on migrate)
  cat >"${migrepo}/.super-exec/active" <<'EOF'
phase: exec
spec: docs/specs/0002-tracked-feature.md
active_plan: .super-exec/0003-widget-feature/2026-07-20-widget-plan/plan.md
branch: test-branch
EOF

  # Commit tracked files only (spec + ADR + monorepo spec); leave untracked spec + .super-exec alone
  (
    cd "$migrepo" || exit 1
    git add \
      docs/specs/0002-tracked-feature.md \
      docs/specs/payments/0007-payout-flow.md \
      docs/adr/0005-global-decision.md \
      docs/specs/already-feature/spec-already-feature.md \
      docs/adr/plain-slug.md
    git commit -q -m "v0 fixtures for migrate test"
  ) 2>/dev/null || true

  # Snapshot tree before dry-run
  before_tree=$(cd "$migrepo" && find . -type f | sort)

  # --- dry-run: lists moves, changes NOTHING ---
  dry_out=$(run_mig "$mighome" "$migrepo" migrate 2>/dev/null || true)
  after_dry_tree=$(cd "$migrepo" && find . -type f | sort)
  dry_ok=1
  if [ "$before_tree" != "$after_dry_tree" ]; then
    dry_ok=0
    fail "migrate dry-run mutated the filesystem"
  else
    pass "migrate dry-run changes nothing on disk"
  fi

  dry_list_ok=$(node -e "
    const out = process.argv[1];
    const issues = [];
    const required = [
      'docs/specs/0002-tracked-feature.md',
      'docs/specs/tracked-feature/spec-tracked-feature.md',
      'docs/specs/0004-untracked-feature.md',
      'docs/specs/untracked-feature/spec-untracked-feature.md',
      'docs/specs/payments/0007-payout-flow.md',
      'docs/specs/payments/payout-flow/spec-payout-flow.md',
      'docs/adr/0005-global-decision.md',
      'docs/adr/global-decision.md',
      '.super-exec/0003-widget-feature/2026-07-20-widget-plan/plan.md',
      '.super-exec/specs/widget-feature/plans/2026-07-20-widget-plan/plan-widget-plan.md',
      'handoff-widget-plan.md',
      '.super-exec/specs/payments/cashout/plans/2026-06-01-cashout-v1/plan-cashout-v1.md',
      'active_plan:',
      'spec:',
    ];
    for (const s of required) {
      if (!out.includes(s)) issues.push('missing in dry-run: ' + s);
    }
    if (!/DRY-RUN/i.test(out)) issues.push('missing DRY-RUN marker');
    process.stdout.write(issues.length ? issues.join('; ') : 'ok');
  " "$dry_out" 2>/dev/null || echo "ERROR")
  if [ "$dry_list_ok" = "ok" ]; then
    pass "migrate dry-run lists correct v0→v1 moves + spec:/active_plan: rewrite"
  else
    fail "migrate dry-run listing problem: ${dry_list_ok}"
  fi

  # --- --apply: exact v1 paths ---
  apply_out=$(run_mig "$mighome" "$migrepo" migrate --apply 2>/dev/null || true)

  apply_paths_ok=$(node -e "
    const fs = require('fs');
    const path = require('path');
    const root = process.argv[1];
    const issues = [];
    function exists(rel) {
      try { fs.accessSync(path.join(root, rel)); return true; } catch (_) { return false; }
    }
    const mustExist = [
      'docs/specs/tracked-feature/spec-tracked-feature.md',
      'docs/specs/untracked-feature/spec-untracked-feature.md',
      'docs/specs/payments/payout-flow/spec-payout-flow.md',
      'docs/adr/global-decision.md',
      'docs/specs/already-feature/spec-already-feature.md',
      'docs/adr/plain-slug.md',
      '.super-exec/specs/widget-feature/plans/2026-07-20-widget-plan/plan-widget-plan.md',
      '.super-exec/specs/widget-feature/plans/2026-07-20-widget-plan/handoff-widget-plan.md',
      '.super-exec/specs/payments/cashout/plans/2026-06-01-cashout-v1/plan-cashout-v1.md',
    ];
    const mustGone = [
      'docs/specs/0002-tracked-feature.md',
      'docs/specs/0004-untracked-feature.md',
      'docs/specs/payments/0007-payout-flow.md',
      'docs/adr/0005-global-decision.md',
      '.super-exec/0003-widget-feature/2026-07-20-widget-plan/plan.md',
      '.super-exec/0003-widget-feature/2026-07-20-widget-plan/handoff.md',
      '.super-exec/payments/0001-cashout/2026-06-01-cashout-v1/plan.md',
    ];
    for (const p of mustExist) if (!exists(p)) issues.push('missing: ' + p);
    for (const p of mustGone) if (exists(p)) issues.push('still present: ' + p);
    process.stdout.write(issues.length ? issues.join('; ') : 'ok');
  " "$migrepo" 2>/dev/null || echo "ERROR")
  if [ "$apply_paths_ok" = "ok" ]; then
    pass "migrate --apply produces exact v1 paths (NNNN- stripped)"
  else
    fail "migrate --apply path problem: ${apply_paths_ok}"
  fi

  # --- git tracking preserved for tracked files (git mv) ---
  tracked_ok=$(
    cd "$migrepo" || exit 1
    issues=""
    # Tracked dest must be in the index / known to git
    for rel in \
      docs/specs/tracked-feature/spec-tracked-feature.md \
      docs/specs/payments/payout-flow/spec-payout-flow.md \
      docs/adr/global-decision.md
    do
      if ! git ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
        issues="${issues}not tracked: ${rel}; "
      fi
    done
    # Untracked dest must NOT be in the index
    if git ls-files --error-unmatch docs/specs/untracked-feature/spec-untracked-feature.md >/dev/null 2>&1; then
      issues="${issues}untracked spec wrongly in index; "
    fi
    # Rename detectable via status or log --follow
    if ! git status --short | grep -qE 'R[ ]+.*tracked-feature|docs/specs/tracked-feature'; then
      # After commit-less rename, status should show renames or staged R
      if ! git status --short | grep -q 'tracked-feature'; then
        issues="${issues}no rename/status evidence for tracked-feature; "
      fi
    fi
    if [ -z "$issues" ]; then echo ok; else echo "$issues"; fi
  )
  if [ "$tracked_ok" = "ok" ]; then
    pass "migrate --apply preserves git tracking (git mv for tracked files)"
  else
    fail "migrate git-tracking problem: ${tracked_ok}"
  fi

  # --- pointer rewrites ---
  ptr_ok=$(node -e "
    const fs = require('fs');
    const path = require('path');
    const root = process.argv[1];
    const issues = [];
    const plan = fs.readFileSync(path.join(root, '.super-exec/specs/widget-feature/plans/2026-07-20-widget-plan/plan-widget-plan.md'), 'utf8');
    const handoff = fs.readFileSync(path.join(root, '.super-exec/specs/widget-feature/plans/2026-07-20-widget-plan/handoff-widget-plan.md'), 'utf8');
    const active = fs.readFileSync(path.join(root, '.super-exec/active'), 'utf8');
    if (!plan.includes('docs/specs/tracked-feature/spec-tracked-feature.md')) issues.push('plan Spec: not rewritten');
    if (plan.includes('docs/specs/0002-tracked-feature.md')) issues.push('plan still has old Spec path');
    if (!handoff.includes('.super-exec/specs/widget-feature/plans/2026-07-20-widget-plan/plan-widget-plan.md')) issues.push('handoff Plan: not rewritten');
    if (handoff.includes('.super-exec/0003-widget-feature/')) issues.push('handoff still has old Plan path');
    if (!/active_plan:\\s*\\.super-exec\\/specs\\/widget-feature\\/plans\\/2026-07-20-widget-plan\\/plan-widget-plan\\.md/.test(active)) {
      issues.push('active active_plan: not rewritten');
    }
    if (!/spec:\\s*docs\\/specs\\/tracked-feature\\/spec-tracked-feature\\.md/.test(active)) {
      issues.push('active spec: not rewritten');
    }
    if (/spec:\\s*docs\\/specs\\/0002-tracked-feature\\.md/.test(active)) {
      issues.push('active still has old spec: path');
    }
    process.stdout.write(issues.length ? issues.join('; ') : 'ok');
  " "$migrepo" 2>/dev/null || echo "ERROR")
  if [ "$ptr_ok" = "ok" ]; then
    pass "migrate rewrites Spec: / Plan: / spec: / active_plan: pointers"
  else
    fail "migrate pointer rewrite problem: ${ptr_ok}"
  fi

  # --- global ADR stays in docs/adr/, number stripped, NOT feature-specific ---
  if [ -f "${migrepo}/docs/adr/global-decision.md" ] \
     && [ ! -f "${migrepo}/docs/adr/0005-global-decision.md" ] \
     && ! find "${migrepo}/docs/specs" -path '*/adr/global-decision.md' 2>/dev/null | grep -q .; then
    pass "numbered global ADR → docs/adr/<slug>.md (stays global)"
  else
    fail "global ADR migration incorrect (must stay in docs/adr/, not feature-specific)"
  fi

  # --- boundary: nothing crossed docs ↔ .super-exec ---
  boundary_ok=$(node -e "
    const fs = require('fs');
    const path = require('path');
    const root = process.argv[1];
    const issues = [];
    // Specs must remain under docs/
    for (const p of [
      'docs/specs/tracked-feature/spec-tracked-feature.md',
      'docs/specs/untracked-feature/spec-untracked-feature.md',
      'docs/specs/payments/payout-flow/spec-payout-flow.md',
    ]) {
      if (!fs.existsSync(path.join(root, p))) issues.push('missing docs spec: ' + p);
    }
    // Plans must remain under .super-exec/
    for (const p of [
      '.super-exec/specs/widget-feature/plans/2026-07-20-widget-plan/plan-widget-plan.md',
      '.super-exec/specs/payments/cashout/plans/2026-06-01-cashout-v1/plan-cashout-v1.md',
    ]) {
      if (!fs.existsSync(path.join(root, p))) issues.push('missing se plan: ' + p);
    }
    // No plan under docs/, no spec under .super-exec/specs from these fixtures with wrong root
    function walk(dir, acc) {
      let ents; try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch (_) { return; }
      for (const e of ents) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) walk(full, acc);
        else acc.push(path.relative(root, full).split(path.sep).join('/'));
      }
    }
    const all = [];
    walk(root, all);
    for (const rel of all) {
      if (rel.startsWith('docs/') && /\\/plans\\//.test(rel) && /plan-/.test(rel)) {
        issues.push('plan crossed into docs: ' + rel);
      }
      if (rel.startsWith('.super-exec/specs/') && /spec-tracked-feature\\.md$/.test(rel)) {
        issues.push('tracked spec crossed into .super-exec: ' + rel);
      }
    }
    process.stdout.write(issues.length ? issues.join('; ') : 'ok');
  " "$migrepo" 2>/dev/null || echo "ERROR")
  if [ "$boundary_ok" = "ok" ]; then
    pass "migrate preserves docs ↔ .super-exec boundary"
  else
    fail "migrate boundary problem: ${boundary_ok}"
  fi

  # --- idempotent re-run ---
  tree_after_apply=$(cd "$migrepo" && find . -type f | sort)
  rerun_out=$(run_mig "$mighome" "$migrepo" migrate --apply 2>/dev/null || true)
  tree_after_rerun=$(cd "$migrepo" && find . -type f | sort)
  if [ "$tree_after_apply" = "$tree_after_rerun" ] \
     && echo "$rerun_out" | grep -qiE 'Nothing to migrate|no-op|No v0 artifacts'; then
    pass "migrate --apply re-run is idempotent no-op"
  elif [ "$tree_after_apply" = "$tree_after_rerun" ]; then
    pass "migrate --apply re-run is idempotent no-op"
  else
    fail "migrate --apply re-run mutated filesystem (not idempotent)"
  fi

  rm -rf "$migtmp"
fi

# ---------------------------------------------------------------------------
# Check 22 — Task 9 anti-straggler + using-super-exec config skills
# ---------------------------------------------------------------------------
# v0 path tokens must not remain in plugin/skills outside se-config/
# (se-config keeps migration-context v0 wording on purpose).
echo ""
echo "Check 22: Task 9 anti-straggler (v0 tokens outside se-config)"

straggler_hits="$(mktemp)"
: >"$straggler_hits"
(
  cd "$REPO_ROOT"
  for token in \
    'docs/specs/NNNN-<feature>.md' \
    '.super-exec/NNNN' \
    'MMMM' \
    'plan.md' \
    'handoff.md'
  do
    # Fixed-string so plan-<plan-name>.md / handoff-<plan-name>.md do not match.
    grep -rFn --exclude-dir=se-config -- "$token" plugin/skills 2>/dev/null || true
  done
) >>"$straggler_hits"

if [ -s "$straggler_hits" ]; then
  fail "v0 path tokens remain in plugin/skills (excl. se-config):"
  sed 's/^/    /' "$straggler_hits"
else
  pass "no v0 path tokens in plugin/skills outside se-config"
fi
rm -f "$straggler_hits"

using_skill="${REPO_ROOT}/plugin/skills/using-super-exec/SKILL.md"
if [ ! -f "$using_skill" ]; then
  fail "using-super-exec SKILL.md missing"
else
  missing_cfg=()
  for phrase in '/se-config' '/se-get-config' '/se-slug-naming'; do
    if ! grep -qF -- "$phrase" "$using_skill" 2>/dev/null; then
      missing_cfg+=("$phrase")
    fi
  done
  if [ "${#missing_cfg[@]}" -eq 0 ]; then
    pass "using-super-exec SKILL mentions /se-config, /se-get-config, /se-slug-naming"
  else
    fail "using-super-exec SKILL missing: ${missing_cfg[*]}"
  fi
fi

# ---------------------------------------------------------------------------
# Check 23/24 — Compressed workflow and increment-integrity contracts
# ---------------------------------------------------------------------------
echo ""
echo "Check 23/24: Compressed workflow and increment-integrity contracts"

compressed_contract_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$compressed_contract_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.env.REPO_ROOT;
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const files = {
  discuss: read('plugin/skills/se-discuss/SKILL.md'),
  plan: read('plugin/skills/se-plan/SKILL.md'),
  exec: read('plugin/skills/se-exec/SKILL.md'),
  verify: read('plugin/skills/se-verify/SKILL.md'),
  review: read('plugin/skills/se-review/SKILL.md'),
  commit: read('plugin/skills/se-commit/SKILL.md'),
  pr: read('plugin/skills/se-pr/SKILL.md'),
  triage: read('plugin/skills/se-pr-triage/SKILL.md'),
  ci: read('plugin/skills/se-pr-triage/ci-triage.md'),
  cursor: read('plugin/skills/using-super-exec/references/cursor-tools.md'),
  template: read('plugin/skills/se-plan/plan-template.md'),
  handoff: read('plugin/skills/se-handoff/handoff-template.md'),
  subagent: read('plugin/skills/se-subagent/SKILL.md'),
  core: read('docs/specs/core-workflow/spec-core-workflow.md'),
  placement: read('docs/specs/se-config-and-artifact-placement/spec-se-config-and-artifact-placement.md'),
  adr: read('docs/adr/working-increment-execution.md'),
};
const problems = [];
const words = (text, required, label) => {
  const missing = required.filter(word => !text.toLowerCase().includes(word.toLowerCase()));
  if (missing.length) problems.push(`${label}: ${missing.join(', ')}`);
};
const ordered = (text, actions, label) => {
  let at = -1;
  for (const action of actions) {
    const next = text.toLowerCase().indexOf(action.toLowerCase(), at + 1);
    if (next < 0 || next <= at) return problems.push(`${label}: ${action}`);
    at = next;
  }
};
const lineWith = (text, needle) => text.split(/\r?\n/).find(line => line.includes(needle)) || '';
const reject = (condition, label) => { if (condition) problems.push(label); };
const checkboxBlocks = text => {
  const blocks = [];
  let block = null;
  for (const [index, line] of text.split(/\r?\n/).entries()) {
    if (/^\s*-\s+\[\s\]/.test(line)) {
      if (!block) block = { start: index, end: index, text: '' };
      block.end = index;
      block.text += `${line}\n`;
    } else if (block) {
      blocks.push(block);
      block = null;
    }
  }
  if (block) blocks.push(block);
  return blocks;
};
const checklist = (name, text, firstAction, coverage) => {
  const blocks = checkboxBlocks(text);
  if (blocks.length !== 1) return problems.push(`${name}: expected one checkbox block, got ${blocks.length}`);
  const block = blocks[0];
  const lineAt = text.split(/\r?\n/).slice(0, block.start).join('\n').length;
  const nearby = text.slice(Math.max(0, lineAt - 400), lineAt + 900);
  if (!/harness\s+todo-list[\s\S]{0,120}(?:track|sync)[\s\S]{0,160}(?:complete|completion|applicable)/i.test(nearby)) {
    problems.push(`${name}: harness todo tracking/completion instruction`);
  }
  if (lineAt > text.indexOf(firstAction)) problems.push(`${name}: checklist is after first operation`);
  words(block.text, coverage, `${name} checklist coverage`);
};

checklist('discuss', files.discuss, '## Start', [
  'activate', 'local ignore', 'existing/new', 'root', 'WHAT', 'provenance',
  'split', 'name', 'branch', 'template', 'self-review', 'approval', 'commit', 'plan',
]);
checklist('plan', files.plan, '## Activate', [
  'activate', 'discover', 'dependencies', 'branch', 'research', 'architecture',
  'proof', 'plan', 'ledger', 'pending', 'ready', 'review', 'approve', 'publish', 'fresh',
]);
checklist('exec', files.exec, '## Activate', [
  'activate', 'readiness', 'config', 'todo', 'durable', 'slice', 'correct',
  'checkpoint', 'runtime', 'review', 'fix', 'commit', 'reconcile', 'PR', 'handoff',
]);
checklist('ci triage', files.ci, '## Diagnose', [
  'diagnose', 'signal', 'resolve', 'escalate', 'verify', 'review', 'commit', 'push', 'recheck', 'report', 'PR replies',
]);
checklist('PR', files.pr, '## 1.', [
  'choose', 'identity', 'delegate', 'draft', 'evidence', 'create', 'confirm', 'clear',
]);
checklist('PR triage', files.triage, '## Session activation', [
  'detect', 'state', 'actionable', 'track', 'approval', 'fixes', 'replies', 'report', 'clear',
]);

// Artifact roots, discovery, config, paired publication, and lifecycle.
words(files.discuss, ['both spec roots', 'Existing spec keeps discovered root', 'commitSpec', 'spec-<feature>.md'], 'spec roots');
words(files.plan, ['No argument', 'docs/specs/', '.super-exec/specs/', 'Depends on:', 'commitPlan', 'plan-<plan-name>.md'], 'plan discovery/config');
words(files.plan, ['ledger_status: pending', 'ledger_status: ready', 'validate/preserve', 'commit together'], 'plan ledger/publication');
words(files.exec, ['humanReviewBeforeCheckpointCommit', 'autoCreatePr', 'status: completed', 'nonempty checklist', 'missing checklist never completes'], 'exec readiness/completion');
words(files.exec, ['content change invalidates approval', 'reopen', 're-present', 'wait again'], 'approval invalidation');
words(files.exec, ['required outcomes', 'full work packages', 'current proof/review', 'delivery', 'reconciliation'], 'completion bookkeeping');
const completionAction = files.exec.split(/\r?\n/).find(line => {
  const clause = line.toLowerCase();
  return /\b(?:set|transition|mark)\w*\b.*\bstatus\b[^a-z0-9]{0,8}completed\b/.test(clause)
    && clause.includes('only after');
}) || '';
words(completionAction, ['required outcomes', 'full work packages', 'proof/review', 'delivery', 'reconciliation'], 'status completion prerequisites');
words(files.exec + files.cursor, ['standing checkpoint-commit authorization', 'standing user authorization'], 'standing authorization');

// WHAT-only artifact writing and shared harness capability mapping.
words(files.discuss, ['WHAT-only', 'no wrappers/comments', 'Domain terms mirror', 'real alternative trade-off'], 'spec template semantics');
words(files.discuss, ['GLOSSARY.md', 'GLOSSARY-MAP.md', 'do not automatically write', 'CONTEXT.md'], 'glossary dual-read');
words(files.cursor, ['Glob', 'file search', 'todo-list read/update'], 'Cursor reference capabilities');
words(files.plan, ['Final review / PR decision', 'bookkeeping, never executable work'], 'final PR bookkeeping');

// Discussion owner section: use normalized, structural predicates so new
// frontier detail cannot make an arbitrary regex window hide convergence.
const discussInterview = files.discuss.split(/\r?\n##\s+/).find(section =>
  ['design tree', 'frontier', 'shared understanding'].every(marker =>
    section.toLowerCase().includes(marker)
  )
) || '';
const normalizeDiscuss = text => text
  .toLowerCase()
  .replace(/[*_`]/g, '')
  .replace(/[‐‑‒–—-]/g, ' ')
  .replace(/\s+/g, ' ')
  .trim();
const discussNormalized = normalizeDiscuss(discussInterview);
const hasDiscussTerms = (text, terms) => terms.every(term => text.includes(term));
const inDiscussOrder = (text, terms) => {
  let index = -1;
  for (const term of terms) {
    index = text.indexOf(term, index + 1);
    if (index < 0) return false;
  }
  return true;
};
const discussChecks = [
  ['decision tree and branches', hasDiscussTerms(discussNormalized, ['design tree', 'decision', 'branches'])],
  ['frontier settles prerequisites', hasDiscussTerms(discussNormalized, ['frontier', 'prerequisites', 'settled'])],
  ['round batches current frontier', hasDiscussTerms(discussNormalized, ['whole frontier', 'one round'])],
  ['facts stay agent research', hasDiscussTerms(discussNormalized, ['finding facts', 'environment', 'sub agent', "don't ask"])],
  ['unrelated frontier proceeds', hasDiscussTerms(discussNormalized, ['running exploration', 'downstream', 'ask the rest'])],
  ['empty frontier waits required facts', hasDiscussTerms(discussNormalized, ['every candidate', 'required pending facts', 'await'])],
  ['responses recompute graph state', hasDiscussTerms(discussNormalized, ['user answers', 'settled decisions', 'reshapes the tree', 'recompute'])],
  ['dependent questions wait', hasDiscussTerms(discussNormalized, ['depends', 'still open in this round', 'later round'])],
  ['stable question identifiers', hasDiscussTerms(discussNormalized, ['stable', 'session unique', 'q<number>', 'never reassign', 'retire'])],
  ['bounded provenance graph', hasDiscussTerms(discussNormalized, ['bound the graph', 'material', 'provenance', 'user request', 'verified current behavior contradiction', 'user approved derived', 'do not add'])],
  ['user-raised edges stay active', hasDiscussTerms(discussNormalized, ['explicitly user raised edge case', 'active frontier decision', 'accepts', 'explicitly defers', 'rejects', 'stop signal leaves', 'deferred/unapproved'])],
  ['accepted user edges stay requested', hasDiscussTerms(discussNormalized, ['if accepted', 'core requested requirements', 'user priority', 'regardless of likelihood'])],
  ['agent-originated concerns defer by default', hasDiscussTerms(discussNormalized, ['agent originated', 'concerns or suggestions', 'default to deferred concerns', 'user promotes'])],
  ['batching follows scope filter', hasDiscussTerms(discussNormalized, ['scope/provenance filter', 'structured harness question interaction'])],
];
for (const [label, passed] of discussChecks) {
  if (!passed) problems.push(`discuss dependency interview: ${label}`);
}
const sourceQuestionFormat = /❓\s+\*\*Q1\*\*[\s\S]*<question title>[\s\S]*➡️\s+<your recommended answer>/.test(discussInterview);
if (!sourceQuestionFormat) problems.push('discuss dependency interview: usable source question format');
const frontierViolation = text => {
  const normalized = normalizeDiscuss(text);
  const serial = hasDiscussTerms(normalized, ['ask each question', 'separately']);
  const downstream = hasDiscussTerms(normalized, ['include', 'downstream', 'current batch']);
  const prematureSpec = hasDiscussTerms(normalized, ['write spec', 'first round'])
    && (normalized.includes('choices remain') || normalized.includes('decisions remain'));
  const expandsScope = hasDiscussTerms(normalized, ['every imaginable edge case', 'frontier']);
  const autoPromotesAgentConcern = hasDiscussTerms(normalized, ['agent concerns', 'requirements automatically']);
  const blanketDefersUnlikelyEdge = hasDiscussTerms(normalized, ['defer every unlikely edge case']);
  const defersUserRaisedConcern = hasDiscussTerms(normalized, ['user raised concerns', 'deferred concerns', 'without asking']);
  return serial || downstream || prematureSpec || expandsScope || autoPromotesAgentConcern
    || blanketDefersUnlikelyEdge || defersUserRaisedConcern;
};
const unnumberedBatch = text => {
  const normalized = normalizeDiscuss(text);
  return hasDiscussTerms(normalized, ['whole frontier', 'question'])
    && !/(?:q<number>|q\d+)/i.test(text);
};
for (const [label, opposite] of [
  ['serial questions', 'Ask each question separately.'],
  ['downstream batch', 'Include downstream questions in current batch.'],
  ['premature spec', 'Write spec after first round while choices remain.'],
  ['unbounded edge cases', 'Add every imaginable edge case to the frontier.'],
  ['automatic agent requirements', 'Agent concerns become requirements automatically.'],
  ['blanket unlikely-edge deferral', 'Defer every unlikely edge case.'],
  ['user-raised default deferral', 'Put user-raised concerns in Deferred concerns without asking.'],
  ['unnumbered batch', 'Ask the whole frontier with each question and recommendation.'],
]) {
  const escaped = label === 'unnumbered batch'
    ? !unnumberedBatch(opposite)
    : !frontierViolation(opposite);
  if (escaped) problems.push(`discuss synthetic opposite escaped: ${label}`);
}
reject(frontierViolation(files.discuss), 'discuss permits a serial, downstream, or premature-spec contract');
reject(unnumberedBatch(files.discuss), 'discuss permits unnumbered frontier questions');
const convergenceScope = discussNormalized;
for (const [signal, rule] of [
  ['proceed signal', /\bproceed\b/i],
  ['implement signal', /\bimplement\b/i],
  ['stop-asking signal', /\bstop[\s,/-]+asking\b/i],
]) {
  if (!rule.test(convergenceScope)) problems.push(`discussion convergence: ${signal}`);
}
if (!inDiscussOrder(discussNormalized, ['material', 'what', 'acceptance', 'priority', 'first value'])) {
  problems.push('discussion convergence: material choice dimensions');
}
if (!inDiscussOrder(convergenceScope, ['frontier', 'empty', 'shared understanding'])) {
  problems.push('discussion convergence: frontier-empty shared-understanding guard');
}
const actsBeforeSharedUnderstanding = discussInterview.split(/\r?\n/).some(line => {
  const normalized = normalizeDiscuss(line);
  return /\b(?:write|create|act|run|enter)\b/.test(normalized)
    && /\b(?:before|until)\b/.test(normalized)
    && normalized.includes('shared understanding')
    && !/\b(?:do not|never|only after)\b/.test(normalized);
});
reject(actsBeforeSharedUnderstanding, 'discussion convergence permits acting before shared understanding');
if (!hasDiscussTerms(convergenceScope, [
  'settled', 'answered', 'requested', 'approved requirements',
  'unanswered', 'unsettled', 'deferred', 'unapproved', 'never infer',
])) {
  problems.push('discussion convergence: stop leaves unresolved decisions deferred');
}
const coreDiscuss = normalizeDiscuss(files.core.split(/\r?\n###\s+/).find(section =>
  /\bdependency graph\b/.test(section) && /\bshared understanding\b/.test(section)
) || '');
if (!hasDiscussTerms(coreDiscuss, ['each question', 'own', 'recommended answer'])) {
  problems.push('core discussion graph: per-question recommendation');
}
if (!hasDiscussTerms(coreDiscuss, ['user request', 'verified current behavior contradiction', 'explicit user approval', 'explicitly user raised', 'stays in the frontier', 'if accepted', 'core requested requirement', 'regardless of likelihood', 'agent originated', 'default to deferred'])) {
  problems.push('core discussion graph: provenance and branch boundaries');
}
words(files.plan + files.exec, ['re-slices', 'working increments', 'Plan task order/file maps are evidence'], 'adaptable increment boundary');
words(files.exec, ['full detected baseline', 'normal distributable/deployed/user proof', 'proof/review', 'delivery', 'reconciliation'], 'proof to reconciliation');
ordered(files.exec, ['gate-open', 'wait approval', 'clear marker', '/se-commit'], 'checkpoint approval order');
ordered(files.exec, ['/se-verify', '/se-review', '/se-commit'], 'reviewed delivery order');
words(files.exec, ['clean tree', 'HEAD', 'final delivery identity', 'blocked-limitation', 'blocked-review'], 'delivery and terminal gates');
words(files.exec, ['priority/order-only correction', 'approved spec amendment', 'correction inventory'], 'correction gates');
words(files.verify + files.review + files.triage + files.ci, ['standalone-triage'], 'triage verification boundary');
words(files.pr, ['final delivery identity', 'tree-equivalence proof', 'clean-working-tree evidence', 'deferred-findings-<plan-name>.md'], 'PR delivery inputs');
words(files.handoff + files.template, ['deferred-findings-<plan-name>.md', 'Reconciliation'], 'handoff and template ledger');
words(files.verify + files.subagent, ['PASS', 'FAIL', 'LIMITATION'], 'verdict propagation');
words(files.review, [
  'meaningful duplicate code/reuse defect', 'duplicate finding fingerprint',
  'At most two scoped re-review rounds', 'At bound', 'blocked-review',
], 'review convergence');
words(files.core + files.placement + files.adr, ['ledger_status: pending', 'ledger_status: ready', 'plan and ready canonical ledger', 'committed-root'], 'documented ledger invariants');

// Final PR gate: arm → identify/dispose → approve → clear → choose safe PR action.
const autoPrOff = lineWith(files.exec, 'Auto-PR ON');
ordered(autoPrOff, ['gate-open', 'final identity', 'disposition', 'matching approval', 'clear marker', 'PR-safe action'], 'Auto-PR OFF final gate ordering');
reject(/(?:skip|bypass|omit)[^.\n]{0,80}(?:approval|gate-open)/i.test(autoPrOff), 'Auto-PR OFF bypasses approval or gate');

// A summary follows unresolved work, never mere ledger history.
const prSummary = lineWith(files.pr, 'unresolved entries exist');
words(prSummary, ['summary', 'unresolved entries', 'neither', 'PR path', 'omit'], 'PR unresolved-summary requirement');
reject(/(?:non-?empty|closed-only)[^.\n]{0,80}ledger/i.test(prSummary), 'PR summary triggers from non-actionable ledger history');

// Plan activation moves one canonical ledger forward without erasing history.
ordered(files.plan, ['ledger_status: pending', 'Create missing', 'Valid ledger', 'ledger_status: ready'], 'ledger pending-create-validate-ready ordering');
words(files.plan, ['Existing ledger is durable history', 'validate/preserve'], 'ledger preserves existing history');
words(files.placement, ['never overwrite or reseed'], 'ledger never reseeds existing history');
reject(/ledger_status:\s*ready[\s\S]{0,120}(?:before|then).*create/i.test(files.plan), 'ledger becomes ready before canonical creation');

// LIMITATION stops autonomous fixing until the governing spec is resolved.
const limitation = lineWith(files.exec, '`LIMITATION` is never PASS');
words(limitation, ['blocked-limitation', 'skip review/commit/PR/checklist/completion', 'governing-spec approval/amendment'], 'LIMITATION terminal handling');
reject(/(?:dispatch|invoke|route|loop)[^.\n]{0,80}fixer/i.test(limitation), 'LIMITATION enters a fixer loop');

// Correction removes or explicitly retains obsolete delivered behavior before reslicing/finalization.
const correction = lineWith(files.exec, 'Inventory every committed identity/behavior');
words(correction, ['obsolete', 'focused verify/review', '/se-commit', 'retention approval', 'before re-slicing'], 'correction cleanup before reslice');
words(files.core + files.adr, ['every committed delivery identity', 'completed working increment', 'supporting checkpoint'], 'correction inventory covers all delivery forms');
reject(/re-slic(?:e|ing)[\s\S]{0,120}inventory/i.test(correction), 'correction reslices before inventory cleanup');

// Runtime slicing and scoped reviews prevent frozen-plan or whole-spec-per-task regressions.
words(files.plan + files.exec, ['re-slices', 'working increments', 'evidence, never execution authority'], 'runtime-discovered increments');
reject(/for each working increment/i.test(files.plan), 'plan predefines working increments');
words(files.review, ['changed paths', 'focused verification evidence'], 'scoped checkpoint review');
reject(/whole-spec.*task|per-task.*whole-spec/i.test(files.exec + files.review), 'whole-spec review required per task');

// Sibling ledger names must stay plan-derived; reject the legacy bare filename.
words(files.plan + files.exec + files.pr + files.handoff, ['deferred-findings-<plan-name>.md'], 'plan-derived deferred ledger name');
reject(/(?:^|[^\w-])deferred-findings\.md\b/i.test(files.plan + files.exec + files.review + files.pr + files.handoff + files.template + files.triage + files.ci), 'bare deferred ledger filename remains');

process.stdout.write(problems.length ? problems.join('\n') : 'ok');
NODE
then
  compressed_contract_result="$(<"$compressed_contract_output")"
else
  compressed_contract_result="ERROR"
fi
rm -f "$compressed_contract_output"
if [ "$compressed_contract_result" = "ok" ]; then
  pass "compressed workflows retain checklist and lifecycle behavior contracts"
else
  fail "compressed workflow behavior contract problem:"
  echo "$compressed_contract_result" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Check 25 — Skip-plan / skip-spec routing after discuss
# ---------------------------------------------------------------------------
# Discuss no longer always chains into /se-plan: small, clear work skips the
# plan (and, with no spec worth recording, skips the spec too) and enters
# /se-exec in the same session. These checks fail if that routing is dropped
# or if skip-plan exec is sent back to /se-plan for a missing plan/ledger.
echo ""
echo "Check 25: Skip-plan / skip-spec routing"

skip_plan_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$skip_plan_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.env.REPO_ROOT;
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const files = {
  discuss: read('plugin/skills/se-discuss/SKILL.md'),
  plan: read('plugin/skills/se-plan/SKILL.md'),
  exec: read('plugin/skills/se-exec/SKILL.md'),
  handoff: read('plugin/skills/se-handoff/SKILL.md'),
  review: read('plugin/skills/se-review/SKILL.md'),
  using: read('plugin/skills/using-super-exec/SKILL.md'),
  readme: read('README.md'),
};
const problems = [];
const words = (text, required, label) => {
  const missing = required.filter(word => !text.toLowerCase().includes(word.toLowerCase()));
  if (missing.length) problems.push(`${label}: ${missing.join(', ')}`);
};
const reject = (condition, label) => { if (condition) problems.push(label); };
const lineWith = (text, pattern) => text.split(/\r?\n/).find(line => pattern.test(line)) || '';

// Discuss routes to skip-plan/skip-spec instead of always planning.
words(files.discuss, [
  'skip-plan', 'skip-spec', 'task spec', 'session-boundary spec',
  'same-session `/se-exec`', 'skip-spec vs write-spec',
], 'discuss skip routing');
reject(/single:\s*auto-invoke\s*`?\/se-plan/i.test(files.discuss), 'discuss still auto-invokes /se-plan unconditionally');
words(files.discuss, ['never ask skip-plan vs plan'], 'discuss forbids plan on the skip-spec path');

// Producers must WRITE the marker contract the hook and se-exec consume:
// `mode: skip-plan` + `spec:` in .super-exec/active. Asserting only the hook
// consumer let a release ship where nothing ever wrote mode: skip-plan.
words(files.discuss, [
  '.super-exec/active', 'mode: skip-plan', 'task-spec',
], 'discuss writes the skip-plan marker fields');
const discussMarkerLine = lineWith(files.discuss, /mode: skip-plan/i);
words(discussMarkerLine, ['`spec:`', 'before'], 'discuss writes spec: before invoking exec');
words(files.exec, ['mode: skip-plan', '`spec:`'], 'exec reads/writes the skip-plan marker fields');
words(files.handoff, ['mode: skip-plan', 'session-boundary spec'], 'handoff preserves the skip-plan marker');

// Skip-plan exec is a first-class activation mode, never bounced to se-plan.
words(files.exec, ['skip-plan', 'task spec', 'activation mode'], 'exec skip-plan mode');
const skipPlanLine = lineWith(files.exec, /never return to `\/se-plan`/i);
words(skipPlanLine, ['skip-plan', 'missing plan or ledger'], 'exec skip-plan missing-ledger tolerance');
// Skip-plan is a marker field, never inferred from an absent active_plan.
words(files.exec, ['never infer skip-plan from a missing `active_plan`'], 'exec forbids inferring skip-plan');
words(files.exec, ['plan-backed wins'], 'exec leftover skip-plan yields to a resolvable active_plan');
words(files.plan, ['Drop any leftover `mode: skip-plan`'], 'plan clears leftover skip-plan mode');
words(files.review, ['Skip-plan with no ledger'], 'review skips ledger when skip-plan has none');

// Skip-spec keeps slug naming and the branch gate, and drops only the spec.
words(files.discuss, [
  '/se-slug-naming', 'branch-gate Phase B', 'skip presenting a spec',
], 'skip-spec keeps slug and branch gate');

// Plan stays optional and keeps its fresh-session boundary.
words(files.plan, ['skip-plan', 'not mandatory', 'fresh session'], 'plan optionality');

// Skip-plan handoff has no plan folder.
words(files.handoff, ['skip-plan', 'handoff-<plan-name>.md', '.super-exec/handoff-<feature>.md'], 'handoff skip-plan path');

// Orientation and landing page describe both routes.
words(files.using, ['skip-plan', 'same session', 'task spec'], 'orientation skip-plan');
reject(/auto-chain into `\/se-plan`/i.test(files.using), 'orientation still claims discuss always auto-chains to /se-plan');
words(files.readme, ['skip'], 'README mentions skipping the plan');

process.stdout.write(problems.length ? problems.join('\n') : 'ok');
NODE
then
  skip_plan_result="$(<"$skip_plan_output")"
else
  skip_plan_result="ERROR"
fi
rm -f "$skip_plan_output"
if [ "$skip_plan_result" = "ok" ]; then
  pass "skip-plan / skip-spec routing is encoded in the skills"
else
  fail "skip-plan / skip-spec routing problem:"
  echo "$skip_plan_result" | sed 's/^/    /'
fi

# The hook's skip-plan branch must key off the explicit `mode: skip-plan` field
# only. The old inference ("marker has spec: and no active_plan") swallowed
# ordinary plan-phase markers, so it must stay deleted.
SESSION_START_HOOK="${REPO_ROOT}/plugin/hooks/session-start"
if grep -qF '[ "$marker_mode" = "skip-plan" ]' "$SESSION_START_HOOK" 2>/dev/null \
   && ! grep -qE '\[ -n "\$marker_spec" \][[:space:]]*&&[[:space:]]*\[ -z "\$active_plan" \]' "$SESSION_START_HOOK" 2>/dev/null; then
  pass "session-start gates skip-plan on mode: skip-plan, with no spec-only inference"
else
  fail "session-start skip-plan branch is missing the mode gate or still infers from spec:"
fi

echo ""
echo "========================================"
total=$((PASS + FAIL))
echo "Results: ${PASS}/${total} checks passed"
if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo ""
  echo "Failed checks:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
fi
echo "========================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
