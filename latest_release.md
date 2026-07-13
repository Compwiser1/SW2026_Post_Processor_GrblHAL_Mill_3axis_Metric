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
#   1. Uploads the given .ctl file as an asset on the existing draft release
#   2. Publishes the release (removes draft status), making it public
#
# Usage:
#   .scripts/attach-ctl.sh v2026.07.13-A /path/to/SW26_GrblHAL_Mill_3axis_Metric.ctl
#
# Requires: GitHub CLI (gh), authenticated (gh auth login) with write access
# to this repo.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <tag> <path-to-ctl-file>" >&2
  echo "Example: $0 v2026.07.13-A /path/to/SW26_GrblHAL_Mill_3axis_Metric.ctl" >&2
  exit 1
fi

TAG="$1"
CTL_PATH="$2"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI (gh) is required (https://cli.github.com/)." >&2
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

echo "Release: $TAG"
echo "Attaching: $CTL_PATH"
echo ""
echo "By running this you are confirming the .ctl has been recompiled,"
echo "stamp-verified, test-posted, and hardware-tested on FrankenOKO."
read -r -p "Confirm and publish? [y/N] " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Aborted. Nothing was uploaded or published."
  exit 0
fi

gh release upload "$TAG" "$CTL_PATH" --clobber
gh release edit "$TAG" --draft=false

echo ""
echo "Published: $TAG is now live on GitHub Releases with the compiled .ctl attached."
