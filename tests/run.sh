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
  "plugin/skills/using-super-exec/SKILL.md|||standing authorization"
  "plugin/skills/using-super-exec/references/cursor-tools.md|||standing authorization"
  "docs/specs/0001-core-workflow.md|||standing authorization"
  "README.md|||standing go-ahead"
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
  "README.md|||docs/specs/NNNN-<feature>.md"
  "docs/adr/0002-local-only-plans-specs-are-the-shared-contract.md|||docs/specs/NNNN-<feature>.md"
)

for entry in "${spec_convention_sites[@]}"; do
  rel="${entry%%|||*}"
  phrase="${entry##*|||}"
  file="${REPO_ROOT}/${rel}"
  if [ ! -f "$file" ]; then
    fail "spec convention: file not found: ${rel}"
  elif grep -qF "$phrase" "$file" 2>/dev/null; then
    pass "spec convention present in ${rel} (\"${phrase}\")"
  else
    fail "spec convention missing in ${rel}: expected phrase \"${phrase}\""
  fi
done

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
