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
#   1. Zips the given .ctl file into its own archive
#      (<post_id>-Compiled-v<version>.zip)
#   2. Uploads that zip as an asset on the existing draft release
#   3. Publishes the release (removes draft status), making it public
#
# The release ends up with exactly two custom assets: the Compiled zip
# (this script) and the Source zip (built by release-build.yml from
# .SRC/.LIB/.lng/LICENSE only). GitHub also auto-generates its own
# "Source code (zip)"/"(tar.gz)" links on every tag — that's a GitHub
# platform feature with no API option to suppress, unrelated to and
# separate from the two zips this project actually publishes.
#
# Usage:
#   .scripts/attach-ctl.sh v1.0.0 /path/to/SW26_GrblHAL_Mill_3axis_Metric.ctl
#
# Requires: GitHub CLI (gh), authenticated (gh auth login) with write access
# to this repo, and jq.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <tag> <path-to-ctl-file>" >&2
  echo "Example: $0 v1.0.0 /path/to/SW26_GrblHAL_Mill_3axis_Metric.ctl" >&2
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

echo "Release: $TAG"
echo "Compiled .ctl: $CTL_PATH"
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

CTL_FILENAME=$(basename "$CTL_PATH")
cp "$CTL_PATH" "$TMP_DIR/$CTL_FILENAME"

ZIP_NAME="${POST_ID}-Compiled-v${VERSION}.zip"
ZIP_PATH="$TMP_DIR/$ZIP_NAME"
(cd "$TMP_DIR" && zip -j "$ZIP_NAME" "$CTL_FILENAME")

echo "Built: $ZIP_NAME"

gh release upload "$TAG" "$ZIP_PATH" --clobber
gh release edit "$TAG" --draft=false

echo ""
echo "Published: $TAG is now live on GitHub Releases with $ZIP_NAME attached."
