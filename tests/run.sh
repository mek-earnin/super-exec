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
# the single skill-precedence site (ADR 0004). 'superpowers' in ANY OTHER file
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

# The review-before-commit OFF toggle is documented as the user's standing
# authorization to auto-commit per task — this is what reconciles super-exec
# auto-commit with host agent policies that forbid committing without an
# explicit per-action user request. If a future edit silently drops this
# framing, the conflict returns (the agent babysits each commit). These greps
# guard the framing's presence at every canonical site. The behavior itself
# (whether the model commits) is not unit-testable here; presence is.
#
# Each entry: <relative path>|||<case-insensitive fixed phrase that must exist>
framing_sites=(
  "plugin/skills/se-exec/SKILL.md|||standing authorization"
  "plugin/skills/using-super-exec/references/cursor-tools.md|||standing authorization"
  "docs/specs/0001-core-workflow.md|||standing authorization"
)

for entry in "${framing_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "framing: file not found: ${rel}"
  elif grep -qiF "$phrase" "$file" 2>/dev/null; then
    pass "framing present in ${rel} (\"${phrase}\")"
  else
    fail "framing missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

# The Cursor-specific resolution lives in a dedicated reference section; its
# header is the durable anchor for the host-policy reconciliation.
cursor_ref="${REPO_ROOT}/plugin/skills/using-super-exec/references/cursor-tools.md"
if grep -qiF "Host commit policy vs auto-commit" "$cursor_ref" 2>/dev/null; then
  pass "cursor-tools.md has 'Host commit policy vs auto-commit' section"
else
  fail "cursor-tools.md missing 'Host commit policy vs auto-commit' section"
fi

# ---------------------------------------------------------------------------
# Check 7 — SessionStart local-ignore (.git/info/exclude)
# ---------------------------------------------------------------------------
# The SessionStart hook keeps super-exec's local-only working dir (.super-exec/)
# out of git via the repo-local, uncommitted .git/info/exclude (NOT the
# team-shared .gitignore — ADR 0002). It must do so idempotently on every
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

  rm -rf "$ttmp"
fi

# ---------------------------------------------------------------------------
# Check 8 — Spec filename convention
# ---------------------------------------------------------------------------
echo ""
echo "Check 8: Spec filename convention"

spec_name_result=$(node -e "
  const fs = require('fs');
  const path = require('path');
  const specsRoot = path.join('${REPO_ROOT}', 'docs/specs');
  const bad = [];
  const seenByDir = new Map();

  function walk(dir) {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
        continue;
      }
      if (!entry.isFile() || !entry.name.endsWith('.md')) continue;

      const rel = path.relative('${REPO_ROOT}', full);
      if (!/^\\d{4}-[a-z0-9]+(?:-[a-z0-9]+)*\\.md$/.test(entry.name)) {
        bad.push(rel);
        continue;
      }

      const dirKey = path.relative(specsRoot, dir) || '.';
      const num = entry.name.slice(0, 4);
      const key = dirKey + '/' + num;
      if (seenByDir.has(key)) {
        bad.push(rel + ' (duplicate number with ' + seenByDir.get(key) + ')');
      } else {
        seenByDir.set(key, rel);
      }
    }
  }

  walk(specsRoot);
  process.stdout.write(bad.length ? bad.join('\\n') : 'ok');
" 2>/dev/null || echo "ERROR")

if [ "$spec_name_result" = "ok" ]; then
  pass "all docs/specs markdown files use NNNN-<slug>.md"
else
  fail "docs/specs files must use NNNN-<slug>.md:"
  echo "$spec_name_result" | sed 's/^/    /'
fi

spec_convention_sites=(
  "plugin/skills/se-discuss/SKILL.md|||docs/specs/NNNN-<feature>.md"
  "plugin/skills/se-discuss/SKILL.md|||next available number"
  "plugin/skills/se-plan/SKILL.md|||docs/specs/NNNN-<feature>.md"
  "plugin/skills/se-plan/plan-template.md|||docs/specs/NNNN-<feature>.md"
  "docs/specs/0001-core-workflow.md|||docs/specs/NNNN-<feature>.md"
  "docs/adr/0002-local-only-plans-specs-are-the-shared-contract.md|||docs/specs/NNNN-<feature>.md"
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

# ---------------------------------------------------------------------------
# Check 9 — Plan frontmatter status contract
# ---------------------------------------------------------------------------
echo ""
echo "Check 9: Plan frontmatter status contract"

# Plans carry local execution metadata in YAML frontmatter. The branch recorded
# there is the build-session source of truth, and status uses the lowercase
# enum pending | in_progress | completed.
plan_frontmatter_sites=(
  "plugin/skills/se-plan/plan-template.md|||title: <Plan title>"
  "plugin/skills/se-plan/plan-template.md|||feature: <feature slug>"
  "plugin/skills/se-plan/plan-template.md|||branch: <confirmed branch name>"
  "plugin/skills/se-plan/plan-template.md|||status: pending"
  "plugin/skills/se-plan/SKILL.md|||status: \`pending\`"
  "plugin/skills/se-exec/SKILL.md|||verify the current git branch matches \`branch\`"
  "plugin/skills/se-exec/SKILL.md|||update \`status\` from \`pending\` to \`in_progress\`"
  "plugin/skills/se-exec/SKILL.md|||update \`status\` to \`completed\`"
  "docs/specs/0001-core-workflow.md|||plan frontmatter"
)

for entry in "${plan_frontmatter_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "plan frontmatter: file not found: ${rel}"
  elif grep -qF -- "$phrase" "$file" 2>/dev/null; then
    pass "plan frontmatter contract present in ${rel} (\"${phrase}\")"
  else
    fail "plan frontmatter contract missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

# Guard against the old plan status enum returning at the canonical contract
# sites. "Completed Tasks" in handoff templates is a section label, not status.
old_status_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$old_status_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const repoRoot = process.env.REPO_ROOT;
const files = [
  'plugin/skills/se-plan/plan-template.md',
  'plugin/skills/se-plan/SKILL.md',
  'plugin/skills/se-exec/SKILL.md',
  'docs/specs/0001-core-workflow.md',
];
const old = /\b(ToDo|InProgress)\b|status:\s*ToDo|status`\s+to\s+`Completed`|`Completed`/;
const hits = [];
for (const rel of files) {
  const content = fs.readFileSync(path.join(repoRoot, rel), 'utf8');
  if (old.test(content)) hits.push(rel);
}
process.stdout.write(hits.length ? hits.join('\n') : 'ok');
NODE
then
  old_status_result="$(<"$old_status_output")"
else
  old_status_result="ERROR"
fi
rm -f "$old_status_output"
if [ "$old_status_result" = "ok" ]; then
  pass "old plan status enum is absent from contract sites"
else
  fail "old plan status enum found in contract sites:"
  echo "$old_status_result" | sed 's/^/    /'
fi

# se-exec must not clobber an approved/resume plan pointer during activation.
activation_contract_sites=(
  "plugin/skills/se-exec/SKILL.md|||preserve any existing \`active_plan\`"
  "plugin/skills/se-exec/SKILL.md|||preserve \`branch\` if present"
  "docs/specs/0001-core-workflow.md|||preserving any existing \`active_plan\`"
)

for entry in "${activation_contract_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "se-exec activation contract: file not found: ${rel}"
  elif grep -qF -- "$phrase" "$file" 2>/dev/null; then
    pass "se-exec activation preserves marker state in ${rel}"
  else
    fail "se-exec activation contract missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

# active_plan must be written as soon as plan.md exists, not only after human
# plan approval. Approval may add approved: metadata and gates the fresh-session
# handoff, but resume/orientation needs a concrete plan path before approval.
active_plan_timing_sites=(
  "plugin/skills/se-plan/SKILL.md|||Immediately after \`plan.md\` is written"
  "plugin/skills/se-plan/SKILL.md|||approval is not the first time \`active_plan\` is recorded"
  "docs/specs/0001-core-workflow.md|||then immediately record \`active_plan"
  "docs/specs/0001-core-workflow.md|||approval is not the first time \`active_plan\` is recorded"
  "plugin/hooks/session-start|||immediately after plan.md write"
)

for entry in "${active_plan_timing_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "active_plan timing: file not found: ${rel}"
  elif grep -qF -- "$phrase" "$file" 2>/dev/null; then
    pass "active_plan timing contract present in ${rel}"
  else
    fail "active_plan timing contract missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

active_plan_old_timing_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$active_plan_old_timing_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const repoRoot = process.env.REPO_ROOT;
const files = [
  'plugin/skills/se-plan/SKILL.md',
  'docs/specs/0001-core-workflow.md',
  'plugin/hooks/session-start',
];
const forbidden = [
  /active_plan after plan approval/i,
  /adds active_plan after\s+plan approval/i,
  /after the plan is approved[^.\n]*active_plan/i,
  /when the plan is approved[^.\n]*active_plan/i,
  /when approved[^.\n]*active_plan/i,
];
const hits = [];
for (const rel of files) {
  const content = fs.readFileSync(path.join(repoRoot, rel), 'utf8');
  if (forbidden.some((re) => re.test(content))) hits.push(rel);
}
process.stdout.write(hits.length ? hits.join('\n') : 'ok');
NODE
then
  active_plan_old_timing_result="$(<"$active_plan_old_timing_output")"
else
  active_plan_old_timing_result="ERROR"
fi
rm -f "$active_plan_old_timing_output"
if [ "$active_plan_old_timing_result" = "ok" ]; then
  pass "active_plan is not documented as approval-only"
else
  fail "active_plan still appears approval-gated in contract sites:"
  echo "$active_plan_old_timing_result" | sed 's/^/    /'
fi

# Completion detection must not treat legacy plans with no checklist as done.
completion_guard_sites=(
  "plugin/skills/se-exec/SKILL.md|||Completion guard"
  "plugin/skills/se-exec/SKILL.md|||checklist exists, has at least one item"
  "plugin/skills/se-exec/SKILL.md|||frontmatter \`status: completed\`"
  "plugin/skills/se-exec/SKILL.md|||tell the user the plan is already completed and stop before steps 3-10"
  "docs/specs/0001-core-workflow.md|||A missing checklist is never treated as completed"
)

for entry in "${completion_guard_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "completion guard: file not found: ${rel}"
  elif grep -qF -- "$phrase" "$file" 2>/dev/null; then
    pass "completion guard contract present in ${rel}"
  else
    fail "completion guard missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

# The final PR decision item is fixed session bookkeeping, not implementer work.
final_pr_sites=(
  "plugin/skills/se-plan/plan-template.md|||- [ ] Final review / PR decision"
  "plugin/skills/se-plan/SKILL.md|||not an executable task"
  "plugin/skills/se-exec/SKILL.md|||step 10 only"
  "docs/specs/0001-core-workflow.md|||not an executable implementation task"
)

for entry in "${final_pr_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "final PR checklist: file not found: ${rel}"
  elif grep -qF -- "$phrase" "$file" 2>/dev/null; then
    pass "final PR checklist contract present in ${rel}"
  else
    fail "final PR checklist contract missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

# Checklist marking happens after the outer review is clean, not merely after
# task implementation verifies green.
post_review_marking_sites=(
  "plugin/skills/se-exec/SKILL.md|||task is committed and outer-loop-clean"
  "docs/specs/0001-core-workflow.md|||after the task is committed and outer-loop-clean"
)

for entry in "${post_review_marking_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "post-review checklist marking: file not found: ${rel}"
  elif grep -qF "$phrase" "$file" 2>/dev/null; then
    pass "post-review checklist marking present in ${rel}"
  else
    fail "post-review checklist marking missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

# Harness-native task/todo tools are operational session state; plan.md is
# durable resume state. Keep both contract surfaces present.
task_sync_sites=(
  "plugin/skills/se-exec/SKILL.md|||TodoWrite"
  "plugin/skills/se-exec/SKILL.md|||translated equivalent"
  "plugin/skills/se-exec/SKILL.md|||operational session state"
  "plugin/skills/se-exec/SKILL.md|||durable local resume state"
  "plugin/skills/se-exec/SKILL.md|||update the native task/todo tool first"
  "plugin/skills/using-super-exec/SKILL.md|||Individual skills do not branch by harness"
  "docs/specs/0001-core-workflow.md|||native task/todo tool is operational session state"
)

for entry in "${task_sync_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "task sync: file not found: ${rel}"
  elif grep -qF "$phrase" "$file" 2>/dev/null; then
    pass "task sync contract present in ${rel} (\"${phrase}\")"
  else
    fail "task sync contract missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

# Guidance removed from spec-template.md comments must live in se-discuss.
spec_guidance_sites=(
  "plugin/skills/se-discuss/SKILL.md|||acceptance criteria with NO HOW"
  "plugin/skills/se-discuss/SKILL.md|||no instructional comments"
  "plugin/skills/se-discuss/SKILL.md|||mirrored to \`CONTEXT.md\`"
  "plugin/skills/se-discuss/SKILL.md|||hard, surprising, trade-off decisions"
  "plugin/skills/se-discuss/SKILL.md|||docs/adr/"
)

for entry in "${spec_guidance_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "spec template guidance: file not found: ${rel}"
  elif grep -qF "$phrase" "$file" 2>/dev/null; then
    pass "spec template guidance present in ${rel} (\"${phrase}\")"
  else
    fail "spec template guidance missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

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
  'plugin/skills/se-handoff/handoff-outline.md',
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
  "docs/specs/0001-core-workflow.md|||> Ticket: NO_TICKET  ·  Status: active"
  "docs/specs/0001-core-workflow.md|||four entrypoints"
  "docs/specs/0001-core-workflow.md|||/se-pr-triage"
  "docs/specs/0001-core-workflow.md|||se-pr-triage/              # + ci-triage.md; post-PR review/CI triage"
  "docs/specs/0001-core-workflow.md|||## Data Flow"
  "docs/specs/0001-core-workflow.md|||### Browser/E2E Preflight"
  "plugin/skills/using-super-exec/references/cursor-tools.md|||impeccable-critique"
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

core_spec_forbidden_output="$(mktemp)"
if REPO_ROOT="$REPO_ROOT" node >"$core_spec_forbidden_output" 2>/dev/null <<'NODE'
const fs = require('fs');
const path = require('path');
const repoRoot = process.env.REPO_ROOT;
const checks = [
  {
    rel: 'docs/specs/0001-core-workflow.md',
    forbidden: [/three entrypoints/i, /build pending/i, /## Data flow\b/, /Status:\s*draft/i, /README.*recommends?.*superpowers/i, /README.*disabl(?:e|ing).*superpowers/i],
  },
  {
    rel: 'docs/adr/0003-skills-only-no-thin-commands.md',
    forbidden: [/three entrypoints/i, /stale-TTL sweep/i],
  },
  {
    rel: 'docs/adr/0004-superpowers-coinstall-skill-precedence.md',
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
  'docs/specs/0001-core-workflow.md',
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
# Summary
# ---------------------------------------------------------------------------
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
