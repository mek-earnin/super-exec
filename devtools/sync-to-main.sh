#!/usr/bin/env bash
#
# sync-to-main.sh — force the remote main branch to match develop, without
# checking out (your current branch and working tree stay untouched).
#
# It force-pushes so the remote target (default: origin/main) points at the
# exact same commit as the source branch (default: develop), as if main had
# just branched off develop and its previous history never existed.
#
# Usage:
#   devtools/sync-to-main.sh [options]      Force origin/main to match develop
#
# Options:
#   --source <branch>   Branch to sync from            (default: develop)
#   --target <branch>   Remote branch to overwrite     (default: main)
#   --remote <remote>   Remote name                    (default: origin)
#   --no-fetch          Skip fetching the remote before comparing
#   --dry-run           Show the plan, then exit without pushing
#   -y, --yes           Skip the confirmation prompt
#   -h, --help          Show this help
#
set -euo pipefail

SOURCE="develop"
TARGET="main"
REMOTE="origin"
DO_FETCH=1
DRY_RUN=0
ASSUME_YES=0

# --- helpers ---

usage() {
  echo "Usage: devtools/sync-to-main.sh [options]"
  echo ""
  echo "Force the remote main branch to match develop, without checking out."
  echo ""
  echo "  --source <branch>   Branch to sync from         (default: develop)"
  echo "  --target <branch>   Remote branch to overwrite  (default: main)"
  echo "  --remote <remote>   Remote name                 (default: origin)"
  echo "  --no-fetch          Skip fetching the remote before comparing"
  echo "  --dry-run           Show the plan, then exit without pushing"
  echo "  -y, --yes           Skip the confirmation prompt"
  echo "  -h, --help          Show this help"
}

short() {
  git rev-parse --short "$1"
}

# --- parse args ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="${2:?--source needs a value}"; shift 2 ;;
    --target) TARGET="${2:?--target needs a value}"; shift 2 ;;
    --remote) REMOTE="${2:?--remote needs a value}"; shift 2 ;;
    --no-fetch) DO_FETCH=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument '$1' (see --help)" >&2; exit 1 ;;
  esac
done

# --- preconditions ---

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

if ! git rev-parse --verify --quiet "refs/heads/$SOURCE" >/dev/null; then
  echo "error: source branch '$SOURCE' not found locally" >&2
  exit 1
fi

# --- gather state ---

if [[ "$DO_FETCH" -eq 1 ]]; then
  echo "Fetching $REMOTE..."
  git fetch --quiet --prune "$REMOTE"
fi

SOURCE_SHA="$(git rev-parse "refs/heads/$SOURCE")"

REMOTE_REF="refs/remotes/$REMOTE/$TARGET"
if git rev-parse --verify --quiet "$REMOTE_REF" >/dev/null; then
  TARGET_SHA="$(git rev-parse "$REMOTE_REF")"
else
  TARGET_SHA=""
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# --- show plan ---

echo ""
echo "Sync plan (no checkout — you stay on '$CURRENT_BRANCH'):"
echo "  source : $SOURCE ($(short "$SOURCE_SHA"))"
if [[ -n "$TARGET_SHA" ]]; then
  echo "  target : $REMOTE/$TARGET ($(short "$TARGET_SHA")) -> $(short "$SOURCE_SHA")"
else
  echo "  target : $REMOTE/$TARGET (does not exist yet) -> $(short "$SOURCE_SHA")"
fi

if [[ "$SOURCE_SHA" == "$TARGET_SHA" ]]; then
  echo ""
  echo "Already in sync. Nothing to do."
  exit 0
fi

echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] Would run: git push --force $REMOTE $SOURCE:refs/heads/$TARGET"
  exit 0
fi

# --- confirm ---

if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo "This will FORCE-overwrite $REMOTE/$TARGET to match '$SOURCE' exactly."
  echo "The previous history of $REMOTE/$TARGET will be discarded."
  read -r -p "Proceed? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

# --- push ---

echo ""
echo "Pushing..."
git push --force "$REMOTE" "$SOURCE:refs/heads/$TARGET"

echo ""
echo "Done. $REMOTE/$TARGET now matches '$SOURCE' at $(short "$SOURCE_SHA")."
