# Setup checklist — SW2026 Post Processor repo

One-time setup to wire up the same release automation as your
`ncSender-Plugin-SW2026_G-Code_Tools` repo, adapted for the compile-locally
constraint. All files referenced here are in the accompanying zip, laid out
ready to unzip directly into your repo root.

## 1. Upload everything

Unzip into `SW2026_Post_Processor_GrblHAL_Mill_3axis_Metric`, preserving
the folder structure:

```
SW26_GrblHAL_Mill_3axis_Metric.SRC       <- v1.0.0, migrated + ready to compile
SW26_GrblHAL_Mill_3axis_Metric.LIB       <- renamed, unchanged content
SW26_GrblHAL_Mill_3axis_Metric.lng       <- renamed, unchanged content
FrankenOKO_Post_Notes.md                 <- carried-forward dev history
post.json                                <- version source of truth (1.0.0)
latest_release.md                        <- seeded v1.0.0 changelog entry
CLAUDE.md                                <- standing instructions for Claude Code
.github/workflows/release-build.yml
.scripts/bump-release.sh
.scripts/attach-ctl.sh
```

If you already have older dated files (`..._2026_07_12-D.SRC` etc.) sitting
in the repo, delete them — the stable, undated filenames above replace them
going forward. `:LIBRARY=` inside the `.SRC` now points at
`SW26_GrblHAL_Mill_3axis_Metric.LIB` (no date), so the `.LIB` file must sit
in the same folder with that exact name.

From a local clone:

```bash
chmod +x .scripts/bump-release.sh .scripts/attach-ctl.sh
git add .
git commit -m "chore: migrate to stable filenames, semver v1.0.0, add draft-release CI"
git push
```

## 2. What already happened to the version stamp — nothing left to do here

The `.SRC` file's compile-tripwire stamp is a plain, free-form comment
line (not a fixed-width field — that was an earlier, now-outdated
assumption on my part, corrected once I saw your actual current file):

```
:T:; Post Version: 1.0.0<EOL>
```

This is already set correctly in the uploaded `.SRC` file, along with the
`:LIBRARY=` self-reference fix. `post.json` is already set to `1.0.0` to
match. You don't need to hand-edit anything — from here forward, every
version bump goes through `.scripts/bump-release.sh`.

## 3. Claude GitHub App — probably already done

Since it's already installed for `ncSender-Plugin-SW2026_G-Code_Tools`, you
likely just need to **grant it access to this repo too**:
- Go to https://github.com/settings/installations
- Find the Claude app, click Configure
- Add `SW2026_Post_Processor_GrblHAL_Mill_3axis_Metric` to its repository
  access list

If it's not installed at all yet: https://github.com/apps/claude → install
→ select this repo.

## 4. Add the API key secret to this repo

Secrets are per-repository, so this needs to be added even though the old
repo already has one:
- Repo → Settings → Secrets and variables → Actions → New repository secret
- Name: `ANTHROPIC_API_KEY` (or `CLAUDE_CODE_OAUTH_TOKEN` if you're using
  `claude setup-token` instead)

## 5. Add the `@claude` mention workflow (optional, separate from releases)

`release-build.yml` only handles releases. If you also want `@claude` to
respond to issue/PR comments in this repo the same way it might elsewhere,
run `/install-github-app` in Claude Code locally, or add the standard
`examples/claude.yml`-style workflow from `anthropics/claude-code-action`.
Not required for the release flow to work.

## 6. Install the GitHub CLI locally, if you haven't

`.scripts/attach-ctl.sh` needs `gh`:
- https://cli.github.com/
- Then: `gh auth login`

## 7. Cut the actual v1.0.0 release

Since the source files are already at `1.0.0`, your first release doesn't
need a bump — just tag and push what you just uploaded:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Check the Actions tab — `release-build.yml` should run and create a
**draft** release with a Source zip attached (`SW26_GrblHAL_Mill_3axis_Metric-Source-v1.0.0.zip`, containing only `.SRC`/`.LIB`/`.lng`/`LICENSE`).

Then, same as always: compile locally in the Post Processor Editor, verify
the stamp reads `1.0.0`, test-post, hardware-test. Once you're satisfied:

```bash
.scripts/attach-ctl.sh v1.0.0 /path/to/compiled.ctl
```

That publishes the release with both the Source zip and a new Compiled
zip (`SW26_GrblHAL_Mill_3axis_Metric-Compiled-v1.0.0.zip`, containing the
`.ctl`) attached — plus GitHub's own auto-generated "Source code
(zip)"/"(tar.gz)" links, which appear on every tag automatically and
can't be turned off. Every release after this one goes through
`.scripts/bump-release.sh` instead of a manual tag.

That closes the loop: chat produces source + notes → you push → CI stages a
draft → you compile and verify locally exactly as you always have → one
script turns verified work into a public release.
