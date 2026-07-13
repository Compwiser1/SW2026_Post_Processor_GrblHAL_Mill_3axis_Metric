#!/usr/bin/env bash
#
# .scripts/attach-ctl.sh
#
# Run this AFTER, and only after:
#   1. Recompiling in the Post Processor Editor
#   2. Confirming the version stamp posts correctly (the compile tripwire)
#   3. Posting a test job and reviewing the NC output
#   4. Running it on FrankenOKO and confirming correct, safe behavior
#
# This is the one manual gate in the whole release flow, and it's the only
# point that actually catches a hardware-breaking bug — do not skip steps
# or attach a .ctl that hasn't been through all four.
#
# What it does:
#   1. Builds ONE zip (<post_id>-v<version>.zip) containing exactly:
#      .SRC, .LIB, .lng, LICENSE, and the given .ctl
#   2. Uploads that zip as the release's only custom asset
#   3. Replaces the draft placeholder notes with the real current-version
#      release notes (top section of latest_release.md only — not a
#      running changelog)
#   4. Publishes the release (removes draft status), making it public
#
# GitHub also auto-generates its own "Source code (zip)"/"(tar.gz)" links
# on every tag — that's a GitHub platform feature covering the ENTIRE repo
# tree, with no API option to suppress or scope down. It's separate from,
# and unrelated to, the one curated zip this script builds.
#
# Usage:
#   .scripts/attach-ctl.sh v1.0.0 SW26_GrblHAL_Mill_3axis_Metric.ctl
#
# Requires: GitHub CLI (gh), authenticated (gh auth login) with write access
# to this repo, and jq.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <tag> <path-to-ctl-file>" >&2
  echo "Example: $0 v1.0.0 SW26_GrblHAL_Mill_3axis_Metric.ctl" >&2
  exit 1
fi

TAG="$1"
CTL_PATH="$2"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI (gh) is required (https://cli.github.com/)." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required (https://stedolan.github.io/jq/)." >&2
  exit 1
fi

if [ ! -f "$CTL_PATH" ]; then
  echo "Error: file not found: $CTL_PATH" >&2
  exit 1
fi

if [[ "$CTL_PATH" != *.ctl ]]; then
  echo "Warning: '$CTL_PATH' doesn't end in .ctl — double-check this is the right file." >&2
  read -r -p "Continue anyway? [y/N] " CONFIRM
  [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ] || { echo "Aborted."; exit 0; }
fi

if [ ! -f post.json ]; then
  echo "Error: post.json not found. Run this from the repo root." >&2
  exit 1
fi
POST_ID=$(jq -r '.id' post.json)
VERSION="${TAG#v}"

SRC_FILE=$(find . -maxdepth 1 -name '*.SRC' | head -n1)
LIB_FILE=$(find . -maxdepth 1 -name '*.LIB' | head -n1)
LNG_FILE=$(find . -maxdepth 1 -name '*.lng' | head -n1)

for f in "$SRC_FILE" "$LIB_FILE" "$LNG_FILE" LICENSE; do
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    echo "Error: required file missing at repo root: ${f:-<.SRC/.LIB/.lng not found>}" >&2
    exit 1
  fi
done

echo "Release: $TAG"
echo "Compiled .ctl: $CTL_PATH"
echo "Will bundle: $(basename "$SRC_FILE"), $(basename "$LIB_FILE"), $(basename "$LNG_FILE"), LICENSE, $(basename "$CTL_PATH")"
echo ""
echo "By running this you are confirming the .ctl has been recompiled,"
echo "stamp-verified, test-posted, and hardware-tested on FrankenOKO."
read -r -p "Confirm and publish? [y/N] " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Aborted. Nothing was uploaded or published."
  exit 0
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$SRC_FILE" "$LIB_FILE" "$LNG_FILE" LICENSE "$CTL_PATH" "$TMP_DIR/"

ZIP_NAME="${POST_ID}-v${VERSION}.zip"
ZIP_PATH="$TMP_DIR/$ZIP_NAME"
(cd "$TMP_DIR" && zip -j "$(basename "$ZIP_PATH")" \
  "$(basename "$SRC_FILE")" "$(basename "$LIB_FILE")" "$(basename "$LNG_FILE")" \
  LICENSE "$(basename "$CTL_PATH")")

echo "Built: $ZIP_NAME"

# Regenerate release notes from latest_release.md — only the current
# (topmost) version section, never the running changelog history.
if [ -f latest_release.md ]; then
  NOTES=$(awk '/^## /{if (seen) exit; seen=1} seen' latest_release.md)
else
  NOTES="Release ${VERSION}"
fi

gh release upload "$TAG" "$ZIP_PATH" --clobber
gh release edit "$TAG" --notes "$NOTES" --draft=false

echo ""
echo "Published: $TAG is now live on GitHub Releases with $ZIP_NAME attached."
