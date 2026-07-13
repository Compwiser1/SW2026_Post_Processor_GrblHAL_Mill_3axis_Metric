#!/usr/bin/env bash
#
# .scripts/bump-release.sh
#
# Local helper for cutting a new SOURCE release of this post processor. It
# does NOT talk to GitHub Actions directly — it just prepares and pushes the
# commit + tag that release-build.yml is waiting for. Run this from the
# Codespace/Claude Code CLI terminal where you have push access to the repo.
#
# NORMAL FLOW: Claude delivers updated files (any of .SRC/.LIB/.lng, plus a
# latest_release.md with a new top section for the target version) as part
# of a chat session. You place them in the repo (replacing existing files),
# then run this script. It does NOT require a clean working tree — the
# whole point is that you just dropped in changed files.
#
# Versioning is plain semver (X.Y.Z), matching the ncSender plugin repo.
# post.json's "version" field and the ".SRC" file's "Post Version: ..."
# compile-tripwire stamp are always kept in lockstep.
#
# Usage:
#   .scripts/bump-release.sh patch   # bump from post.json's committed version
#   .scripts/bump-release.sh minor
#   .scripts/bump-release.sh major
#   .scripts/bump-release.sh 1.4.2   # explicit target version
#
# If the files you dropped in already have post.json/the .SRC stamp set to
# the target version (Claude's normal delivery), this script detects that
# and leaves them alone rather than double-bumping. If they still show the
# OLD version (e.g. you're bumping locally without new files), it updates
# both to match the computed target version, same as before.
#
# What it does:
#   1. Determines the target version (bump type against post.json's
#      CURRENTLY-ON-DISK version, or an explicit X.Y.Z)
#   2. Verifies latest_release.md's top section already reads "## vX.Y.Z"
#      for that exact target version, with real (non-empty) content —
#      errors out instead of proceeding if not
#   3. Updates post.json and the .SRC stamp to the target version, UNLESS
#      they already match it
#   4. Stages EVERY changed/new file in the working tree (git add -A) —
#      not just post.json/.SRC/latest_release.md, so any real .LIB/.lng
#      or other file changes are included, not silently dropped
#   5. Shows you exactly what's about to be committed and asks to confirm
#   6. Commits as: chore: create new release vX.X.X
#   7. Tags the commit: vX.X.X
#   8. Pushes the commit and the tag, which triggers release-build.yml
#
# REMINDER: pushing the tag only builds an empty DRAFT release. You still
# have to compile locally in the Post Processor Editor, verify the stamp,
# test-post, and hardware-test before running attach-ctl.sh to publish.
#
# Requires: git, jq

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required (https://stedolan.github.io/jq/)." >&2
  exit 1
fi

SRC_FILE=$(find . -maxdepth 1 -name '*.SRC' | head -n1)
if [ -z "$SRC_FILE" ]; then
  echo "Error: no .SRC file found at repo root." >&2
  exit 1
fi

CURRENT_VERSION=$(jq -r '.version' post.json)
POST_ID=$(jq -r '.id' post.json)

BUMP_ARG="${1:-patch}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$BUMP_ARG" in
  major)
    NEW_VERSION="$((MAJOR + 1)).0.0"
    ;;
  minor)
    NEW_VERSION="${MAJOR}.$((MINOR + 1)).0"
    ;;
  patch)
    NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
    ;;
  *[0-9]*.*[0-9]*.*[0-9]*)
    NEW_VERSION="$BUMP_ARG"
    ;;
  *)
    echo "Error: unrecognized argument '$BUMP_ARG'. Use patch, minor, major, or X.Y.Z." >&2
    exit 1
    ;;
esac

# Validate that latest_release.md already has real notes for the exact
# target version. Notes come from Claude, written alongside the source
# edit, not typed in here interactively.
if [ ! -f latest_release.md ]; then
  echo "Error: latest_release.md not found." >&2
  exit 1
fi

TOP_HEADING=$(grep -m1 '^## ' latest_release.md || true)
EXPECTED_HEADING="## v${NEW_VERSION}"
if [ "$TOP_HEADING" != "$EXPECTED_HEADING" ]; then
  echo "Error: latest_release.md's top section is '${TOP_HEADING:-<none found>}', expected '${EXPECTED_HEADING}'." >&2
  echo "Get updated files (including a real v${NEW_VERSION} notes entry) from Claude before bumping to this version." >&2
  exit 1
fi

SECTION_BODY=$(awk '/^## /{if (seen) exit; seen=1; next} seen' latest_release.md | sed '/^[[:space:]]*$/d' | sed 's/^-[[:space:]]*$//' | sed '/^$/d')
if [ -z "$SECTION_BODY" ]; then
  echo "Error: latest_release.md's v${NEW_VERSION} section has no real content (empty or placeholder only)." >&2
  echo "Get updated files with real release notes from Claude before bumping." >&2
  exit 1
fi

echo "Post:    $POST_ID"
echo "Current: $CURRENT_VERSION"
echo "Target:  $NEW_VERSION"
echo ""

# Update post.json only if it doesn't already match the target (Claude's
# normal delivery pre-sets this; a purely local bump needs it set here).
JSON_VERSION=$(jq -r '.version' post.json)
if [ "$JSON_VERSION" != "$NEW_VERSION" ]; then
  TMP_MANIFEST=$(mktemp)
  jq --arg v "$NEW_VERSION" '.version = $v' post.json > "$TMP_MANIFEST"
  mv "$TMP_MANIFEST" post.json
  echo "post.json: updated to ${NEW_VERSION}"
else
  echo "post.json: already at ${NEW_VERSION}, left alone"
fi

# Same for the .SRC stamp.
if ! grep -q '; Post Version: ' "$SRC_FILE"; then
  echo "Error: no '; Post Version: ...' stamp found in ${SRC_FILE}. Fix the stamp manually before bumping." >&2
  exit 1
fi
if grep -q "; Post Version: ${NEW_VERSION}" "$SRC_FILE"; then
  echo "${SRC_FILE}: stamp already at ${NEW_VERSION}, left alone"
else
  sed -i.bak -E "s/; Post Version: .*/; Post Version: ${NEW_VERSION}<EOL>/" "$SRC_FILE"
  rm -f "${SRC_FILE}.bak"
  echo "${SRC_FILE}: stamp updated to ${NEW_VERSION}"
fi

echo ""
echo "Files that will be committed:"
git add -A
git status --short
echo ""
read -r -p "Commit these, tag v${NEW_VERSION}, and proceed? [y/N] " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Aborted. Changes are staged but not committed — run 'git reset' to unstage if needed."
  exit 0
fi

git commit -m "chore: create new release v${NEW_VERSION}"
git tag "v${NEW_VERSION}"

echo ""
echo "Ready to push. This will trigger release-build.yml and create an empty DRAFT release."
read -r -p "Push commit and tag now? [y/N] " PUSH_CONFIRM
if [ "$PUSH_CONFIRM" = "y" ] || [ "$PUSH_CONFIRM" = "Y" ]; then
  git push
  git push origin "v${NEW_VERSION}"
  echo "Pushed. Check the Actions tab on GitHub for the empty draft release."
  echo ""
  echo "NEXT: open the Post Processor Editor, recompile, verify the stamp posts"
  echo "as v${NEW_VERSION}, test-post a job, and hardware-test before running:"
  echo "  .scripts/attach-ctl.sh v${NEW_VERSION} /path/to/compiled.ctl"
else
  echo "Not pushed. Run 'git push && git push origin v${NEW_VERSION}' when ready."
fi
