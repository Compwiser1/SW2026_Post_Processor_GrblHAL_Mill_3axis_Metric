#!/usr/bin/env bash
#
# .scripts/bump-release.sh
#
# Local helper for cutting a new SOURCE release of this post processor. It
# does NOT talk to GitHub Actions directly — it just prepares and pushes the
# commit + tag that release-build.yml is waiting for. Run this locally where
# you have push access to the repo.
#
# Versioning is plain semver (X.Y.Z), matching the ncSender plugin repo.
# post.json's "version" field and the ".SRC" file's "Post Version: ..."
# compile-tripwire stamp are always kept in lockstep by this script — you
# never hand-edit either one separately.
#
# The .SRC stamp is a plain, free-form comment line — no fixed-width
# padding, e.g.:
#   :T:; Post Version: 1.0.0<EOL>
# (Earlier versions of this project used a padded, parenthesized-comment
# stamp format; that was replaced with a plain semicolon-comment line, and
# this script matches the current format. Do not hand-edit the stamp -
# always go through this script.)
#
# Usage:
#   .scripts/bump-release.sh patch   # 1.0.0 -> 1.0.1 (default)
#   .scripts/bump-release.sh minor   # 1.0.0 -> 1.1.0
#   .scripts/bump-release.sh major   # 1.0.0 -> 2.0.0
#   .scripts/bump-release.sh 1.4.2   # set an explicit version
#
# What it does:
#   1. Reads the current version from post.json
#   2. Computes the new version (bump type or explicit version)
#   3. Updates post.json in place
#   4. Updates the "Post Version: ..." stamp in the .SRC file to match
#   5. Opens $EDITOR on latest_release.md so you can write release notes
#      (this file's contents become the GitHub Release body)
#   6. Commits as: chore: create new release vX.X.X
#   7. Tags the commit: vX.X.X
#   8. Pushes the commit and the tag, which triggers release-build.yml
#
# REMINDER: pushing the tag only builds a DRAFT source release. You still
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

if [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree is not clean. Commit or stash changes first." >&2
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

echo "Post:    $POST_ID"
echo "Current: $CURRENT_VERSION"
echo "New:     $NEW_VERSION"
read -r -p "Proceed? [y/N] " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Aborted."
  exit 0
fi

# Update post.json version field in place
TMP_MANIFEST=$(mktemp)
jq --arg v "$NEW_VERSION" '.version = $v' post.json > "$TMP_MANIFEST"
mv "$TMP_MANIFEST" post.json

# Update the compile-tripwire stamp in the .SRC file to match. Plain
# free-form line, no padding: ":T:; Post Version: X.Y.Z<EOL>"
if ! grep -q '; Post Version: ' "$SRC_FILE"; then
  echo "Error: no '; Post Version: ...' stamp found in ${SRC_FILE}. Fix the stamp manually before bumping." >&2
  exit 1
fi
sed -i.bak -E "s/; Post Version: .*/; Post Version: ${NEW_VERSION}<EOL>/" "$SRC_FILE"
rm -f "${SRC_FILE}.bak"

# Seed / open release notes for editing
if [ ! -f latest_release.md ]; then
  echo "## v${NEW_VERSION}" > latest_release.md
  echo "" >> latest_release.md
  echo "- " >> latest_release.md
else
  {
    echo "## v${NEW_VERSION}"
    echo ""
    echo "- "
    echo ""
    cat latest_release.md
  } > latest_release.md.tmp
  mv latest_release.md.tmp latest_release.md
fi

"${EDITOR:-nano}" latest_release.md

git add post.json latest_release.md "$SRC_FILE"
git commit -m "chore: create new release v${NEW_VERSION}"
git tag "v${NEW_VERSION}"

echo ""
echo "Ready to push. This will trigger release-build.yml and create a DRAFT release (source only)."
read -r -p "Push commit and tag now? [y/N] " PUSH_CONFIRM
if [ "$PUSH_CONFIRM" = "y" ] || [ "$PUSH_CONFIRM" = "Y" ]; then
  git push
  git push origin "v${NEW_VERSION}"
  echo "Pushed. Check the Actions tab on GitHub for the draft release build."
  echo ""
  echo "NEXT: open the Post Processor Editor, recompile, verify the stamp posts"
  echo "as v${NEW_VERSION}, test-post a job, and hardware-test before running:"
  echo "  .scripts/attach-ctl.sh v${NEW_VERSION} /path/to/compiled.ctl"
else
  echo "Not pushed. Run 'git push && git push origin v${NEW_VERSION}' when ready."
fi
