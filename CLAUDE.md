# CLAUDE.md — SW2026 Post Processor (GrblHAL Mill, 3-axis Metric)

Standing instructions for Claude Code when operating in this repository
(via `@claude` mentions in issues/PRs, or automation). Read this before
touching any `.SRC`, `.LIB`, or `.lng` file.

## What this project is

A custom SolidWorks 2026 CAM post processor for a personal GrblHAL CNC mill
("FrankenOKO"), built in the CAMWorks/SolidWorks CAM UPG-2 (Universal Post
Generator) compiler environment. Source files (`.SRC`, `.LIB`, `.lng`)
compile to a `.ctl` binary that SolidWorks CAM uses to post G-code. G-code
runs through ncSender (siganberg/ncSender) to real hardware.

## The one fact that overrides everything else

**The UPG-2 Post Processor Editor is a local, GUI-only, Windows-side
compiler. It cannot run in CI, and neither can Claude Code in this
GitHub Actions environment.** You cannot compile a `.ctl`, you cannot verify
a compile succeeded, and you cannot post a test job. Do not attempt to
simulate, approximate, or claim to have done any of this. Your job here is
limited to source-level work: editing `.SRC`/`.LIB`/`.lng`, static
correctness checks, documentation, and release packaging. Compilation,
posting, and hardware testing are exclusively the maintainer's job, done
locally, and are the actual verification gate — nothing you do here
substitutes for it.

## Hard rules for editing source files

These were each learned from a real bug that reached (or nearly reached)
compiled output or hardware. Do not reintroduce them.

- **Every source edit requires a version stamp bump.** The `.SRC` file
  contains a plain, free-form comment line:
  `:T:; Post Version: X.Y.Z<EOL>`. It exists specifically so the maintainer
  can verify, on a real compile, that their edits actually took effect —
  posting from SolidWorks CAM alone does NOT rebuild the `.ctl`. Versioning
  is plain semver, kept in lockstep with `post.json` by
  `.scripts/bump-release.sh` — never hand-edit the stamp or bump only one
  of the two. If you're asked to make a source change, bump the version
  (coordinate with the maintainer on major/minor/patch) but flag that a
  formal bump should still go through `.scripts/bump-release.sh` locally
  before tagging.
- **Never reuse a native MILL.LIB array name for a new array.** Native
  arrays (e.g. `CALC_PRELOAD_TOOL`) get written to at tape start regardless
  of your hook's timing, and collisions are silent — no compile error, just
  corrupted data. Always give new arrays unique, clearly-scoped names.
- **Always set `ATTRINLEN` explicitly on `CHARACTER` scratch variables.**
  Without it, values silently truncate around 26 characters, which breaks
  string comparisons in ways that are hard to trace back to this cause.
- **Any user-supplied text embedded in a G-code comment must use `;` style,
  never `(...)`.** Tool names, material names, and part names can contain
  parentheses (e.g. `1/4" (6.35mm)`), and grblHAL closes `(...)` comments on
  the first `)` it sees — this has caused a real mid-program halt on
  hardware. This is non-negotiable for any new comment that embeds fetched
  text.
- **No `:T:` output inside any `CALC_`-prefixed section.** Put it in a
  separate plain-named section and `CALL()` it.
- **`:LIBRARY=` inside the `.SRC` must match the `.LIB` filename exactly.**
  Update it on every rename.
- **Arc output is `:ARCS=RADIAL`, not `:ARCS=CENTER`.** GrblHAL doesn't
  support G41/G42, and software-computed cutter compensation under
  `:ARCS=CENTER` produces radius mismatches that trip grblHAL's arc
  validation (error:33). Do not revert this for any reason, including to
  "fix" a G-code sender's 3D preview — a sender not rendering R-format arcs
  correctly is a cosmetic viewer limitation, not a correctness problem with
  the post.
- **`GET_SW_CUSTOM_PROP_BY_NAME` only reads the document-level Custom tab.**
  It cannot read Configuration Properties under any circumstance — don't
  attempt workarounds that assume otherwise.
- **`SECTIONEXIST()` checks fail silently on a stale/renamed section name.**
  If you rename a section, grep the whole source tree for references to the
  old name before assuming the rename is complete.
- **Keep `:ATTREMARK=` single-line.** Multi-line versions cause an
  "Unrecognized Keyword" compile error.
- **Watch for full-circle vs. micro-sliver-arc ambiguity in any arc-related
  logic.** CAMWorks emits near-zero-angle sliver arcs at compensation
  corner transitions; a naive "angle near 0 = full circle" heuristic will
  misfire on these and can turn a tiny corner arc into a full, physically
  cuttable circle. Full-circle detection must require a genuine
  `=FULL_CIRCLE` flag or an angle strictly greater than ~359.99°, and a
  radius-scaled minimum-angle filter should suppress below-resolution
  slivers before that check ever runs.

## Release workflow (what you're allowed to do here)

- `post.json` is the version source of truth for tooling (plain semver);
  its `version` field must always match the `.SRC` file's
  `; Post Version:` stamp exactly. If you edit source, you may be asked to
  bump both together, but do NOT push a tag yourself — tagging, version-
  bumping, and stamp updates are all done locally via
  `.scripts/bump-release.sh`, by the maintainer.
- `.github/workflows/release-build.yml` triggers on tag push, validates
  everything (tag/version match, compile-tripwire stamp, per-file content
  sanity), and creates an **empty draft release** — no zip built here,
  since the final archive needs the compiled `.ctl`, which doesn't exist
  yet at this point. `.scripts/attach-ctl.sh` is the only place a zip
  ever gets built: **one single zip**
  (`<post_id>-v<version>.zip`, flat structure) containing exactly
  `.SRC`, `.LIB`, `.lng`, `LICENSE`, and the compiled `.ctl` — then
  publishes. GitHub also auto-generates its own "Source code
  (zip)"/"(tar.gz)" links covering the *entire repo tree* on every tag —
  that's an unrelated GitHub platform feature with no way to suppress or
  scope down, not something this workflow creates or controls. Never
  attempt to make a release non-draft, edit release publish status, or
  attach a `.ctl` file — that is exclusively done locally via
  `.scripts/attach-ctl.sh` after real hardware verification.
- **Release titles currently include a `[EXPERIMENTAL]` suffix**
  (`<post_id> v<version> [EXPERIMENTAL]`), intentionally, until the
  maintainer decides to drop it — don't remove it unprompted.
- **Release notes are the current version only**, extracted as the
  topmost `## vX.X.X` section of `latest_release.md` — never the full
  running changelog history. If asked to review release notes, keep this
  scoping in mind.
- **Release notes are Claude's responsibility to write, not the
  maintainer's.** `.scripts/bump-release.sh` no longer opens an editor —
  it validates that `latest_release.md`'s top section already exactly
  matches `## v<the target version>` with real, non-empty content, and
  refuses to proceed otherwise.
- **Standard delivery pattern for a source change**: pre-stamp
  `post.json`'s `version` and the `.SRC` file's `; Post Version:` stamp
  to the exact target version yourself (don't leave them at the old
  version for the script to bump), prepend the matching `## vX.Y.Z`
  section to `latest_release.md` with real notes, and include whichever
  of `.SRC`/`.LIB`/`.lng` actually changed. Tell the maintainer the
  explicit version to run (`.scripts/bump-release.sh X.Y.Z`) — using the
  explicit form, not `patch`/`minor`/`major`, avoids any ambiguity about
  what "current version" means once the delivered files already show the
  target version.
- **`bump-release.sh` stages the entire working tree (`git add -A`)**,
  not just specific filenames — this was a real bug fixed after testing:
  the original version only staged `post.json`/`latest_release.md`/the
  `.SRC` file by name, silently dropping any `.LIB` or `.lng` change from
  the release commit. Any file you deliver that the maintainer places in
  the repo will be picked up, so there's no need to separately instruct
  them to `git add` specific files before running the script — just
  "place these files, then run `.scripts/bump-release.sh X.Y.Z`."
- **Don't split delivery into two separate round-trips unless there's an
  actual reason to.** Because the maintainer can compile locally the
  moment they receive the pre-stamped `.SRC`, they're often able to have
  a hardware-verified `.ctl` ready *before* even touching the Codespace.
  If the maintainer says the `.ctl` is already ready, give ONE combined
  instruction that runs `bump-release.sh` followed immediately by
  `attach-ctl.sh` in the same pass — don't make them come back for a
  second message just because that used to be necessary. The safety gate
  that matters is `attach-ctl.sh`'s own interactive confirmation prompt
  (which still requires an explicit yes attesting to compile + stamp
  verification + test-post + hardware test), not an artificial pause
  between two separate chat turns.
- If asked to review or update `FrankenOKO_Post_Notes.md` or
  `latest_release.md`, preserve the existing convention: `latest_release.md`
  is a per-release changelog (newest section on top, becomes the GitHub
  Release body); `FrankenOKO_Post_Notes.md` is the carried-forward full
  development history for session continuity.

## Getting file changes into this repo — proven method

Real experience from this repo's setup: bulk uploads (zip extraction,
dragging whole folders, GitHub's web "Add file" button) have repeatedly
either dropped hidden dot-folders (`.github`, `.scripts`) entirely, or
silently cross-mixed content between files (e.g. `post.json` ending up
containing `CLAUDE.md`'s text). Both failure modes left every file
*present* with a *plausible size* — nothing looked obviously wrong until
manually inspected file-by-file.

**What's actually reliable:**
- **Single-file drag-and-drop** into the GitHub Codespace's VS Code
  Explorer, one file at a time, confirming the "Replace" prompt. This
  worked cleanly every time it was used.
- **Terminal heredocs** (`cat > file << 'EOF' ... EOF`) typed or pasted
  directly into the Codespace terminal, for smaller text files. Also
  fully reliable.
- **`release-build.yml`'s content sanity-check step** (added after this
  incident) now catches cross-file content mixups automatically at build
  time — if a future release build fails on that step, the error names
  exactly which file doesn't match its expected content signature. Fix
  that file specifically rather than re-uploading everything.

**What's proven unreliable, avoid:**
- Extracting a zip locally then dragging the whole folder into a
  browser-based uploader — hidden dot-folders (`.github`, `.scripts`)
  are easy to lose this way, especially since they're hidden by default
  in macOS Finder and some Windows Explorer configurations.
- Any bulk/batch file transfer where the mapping from source to
  destination isn't independently verified per file afterward.

**After any batch of file changes, before tagging a release**: run the
labeled verification loop to confirm every file's content matches its
filename, rather than trusting that files transferred correctly:

```bash
for f in SW26_GrblHAL_Mill_3axis_Metric.LIB SW26_GrblHAL_Mill_3axis_Metric.lng \
         CLAUDE.md SETUP_INSTRUCTIONS.md latest_release.md FrankenOKO_Post_Notes.md \
         .scripts/attach-ctl.sh .scripts/bump-release.sh \
         .github/workflows/release-build.yml SW26_GrblHAL_Mill_3axis_Metric.SRC post.json; do
  echo "=== $f ==="
  head -2 "$f"
  echo ""
done
```

## What to do when asked to make a source change

1. Make the edit.
2. Bump the version stamp in the same commit/PR (coordinate with
   `post.json` if that file is also being touched).
3. State plainly in your summary that this is untested, uncompiled source —
   never imply verification you weren't able to perform.
4. If the change touches anything in the "Hard rules" list above, call that
   out explicitly rather than assuming it's fine.
