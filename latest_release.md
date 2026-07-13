## v1.0.4

Fourth pipeline verification test — confirming the zip naming convention
change (SW26_GrblHAL_Mill_3axis_Metric vX.Y.Z per delivery) alongside the
now-default combined bump-release.sh + attach-ctl.sh instruction flow.

## v1.0.3

Third pipeline verification test — confirming the streamlined
single-instruction Claude Code CLI flow (bump-release.sh followed by
attach-ctl.sh in one pass) works correctly end-to-end.

## v1.0.2

Second pipeline verification test — confirming Claude Code CLI can execute
the full bump/build/publish sequence itself (empty draft, [EXPERIMENTAL]
title, single combined zip, current-version-only notes) without manual
step-by-step commands.

## v1.0.1

Testing the release pipeline end-to-end.

## v1.0.0

First release under the new repo structure and versioning scheme:

- **Versioning switched from date-letter (`YYYY.MM.DD-<letter>`) to plain
  semver.** The old scheme was never intended to survive a move to
  automated releases; `1.0.0` is a clean starting point, not a translation
  of prior version history. `post.json` and the `.SRC` file's
  `; Post Version:` stamp are now kept in lockstep by
  `.scripts/bump-release.sh` on every future release.
- **Filenames stabilized.** `.SRC`/`.LIB`/`.lng` no longer embed a date in
  the filename, matching the GitHub repo convention.
- **Release process is now automated via GitHub Actions.**

No functional G-code output changes carried forward from `2026.07.12-D`.
