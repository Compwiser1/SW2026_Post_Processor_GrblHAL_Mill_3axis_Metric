# FrankenOKO GrblHal Post Processor — Current State (as of v2026.07.11-A)

This file is a **pickup point**, not a full history — it covers only what
changed this session. For the deeper history (coolant, N-numbers, operation
notes de-dup, coordinate formatting, etc.), see the original
`FrankenOKO_Post_Notes.md` included alongside this file.

## Current version: `2026.07.12-D`
Files: `SW26_GrblHAL_Mill_3axis_Metric_2026.07.12-D.SRC/.LIB/.lng`

## -12-D: Program-start Z move changed to machine-home retract
Old first line `G90 G54 G21 G00 Z<clearance>` moved Z to an ABSOLUTE
work-coordinate clearance value before any X/Y positioning - protective
in intent (guards the first X/Y rapid against a tool left low), but as
an absolute target it could also DESCEND (e.g. at the home corner when
parked above the clearance plane), which the user flagged. Replaced
with:
  N1 G00 G91 G28 Z0   (machine-home Z retract - always up-or-stay)
  N2 G90 G54 G21      (modes)
Same proven idiom as mid-program tool changes and program end. G00 on
the retract line establishes the motion mode the first bare X/Y rapid
relies on (identical to the SUB_TOOL_CHANGE_MILL pattern verified in
Test 3 output). DO NOT remove the Z retract entirely - the
Z-up-before-any-XY-travel protection matters when the spindle was left
low over the work; per-operation X/Y-then-Z-down approach order was
already correct and is unchanged.

## VERIFIED ON HARDWARE (machine-confirmed, post-12-C)
The complete radial-arc system is now empirically verified on the actual
machine, closing the error:33 saga:
- R-format partial arcs execute correctly (machine traces true curves)
- Full circles execute correctly as four 90-degree quadrant arcs
  (verified in the Test 3 multi-op job: 16 true circles across
  counterbore + bearing-bore ops, all closing correctly; 100 arcs total,
  zero validity issues on mathematical check)
- Sliver suppression verified: corner micro-arcs no longer appear in
  output and profile geometry is correct
- Tool table at top verified with 3 tools, correct type/diameter/
  description pairing; multi-operation layout, tool changes, and
  operation summaries all correct
- KNOWN COSMETIC LIMITATION (not a post bug): ncSender's 3D preview does
  not render R-format arcs - it draws straight chords between arc
  endpoints, so profiles look like polygons on screen. The sender
  streams motion words verbatim (confirmed from its own console log) and
  grblHAL parses R natively (confirmed by physical machine motion). If
  the preview matters, request R-arc rendering from the ncSender
  project; do NOT revert the post to I/J for the visualizer's sake -
  I/J is what produced the unfixable error:33 radius-mismatch failures.

## -12-C: CRITICAL gouge-bug fix in the quadrant split (caught in review)
-12-B turned every compensated corner into TWO full cut circles. Root
cause: CAMWorks' compensation engine emits MICRO-SLIVER arcs (a few
microns long) at corner transitions; their near-zero included angles
tripped the -12-A heuristic "angle near 0 = wrapped full circle", and
the quadrant splitter faithfully expanded each sliver into a real,
valid full circle. The assumption "0-degree arcs are never emitted" was
simply wrong. NOTE: the ORIGINAL I/J post had the same latent landmine -
slivers printed as bare `G02 I.. J..` (a full-circle command in grbl),
never triggered only because lead-in error:33 always halted execution
first.
FIX: sliver filter FIRST - any arc with (ARC_RADIUS * |ARC_INC_ANGLE|)
< 3 (arc length under ~0.05mm, below output display resolution) is
suppressed entirely (RETURN, no output; next absolute move re-syncs).
Full-circle split now requires angle =FULL_CIRCLE or >359.99 only.
Verified numerically: 0.05mm slivers suppressed at any radius, 0.1mm+
arcs print, 90-degree corners and true circles unaffected.

STILL UNVERIFIED - CHECK ON NEXT MULTI-OP JOB: a REAL full circle
(facing/pocket ops, e.g. the End Plate job) has never been posted in
radial mode. Native design implies genuine circles report angle=360
(=FULL_CIRCLE) and will split into quadrants correctly - but if they
instead report a wrapped angle near 0, the sliver filter would SUPPRESS
them (missing motion, undercut). Before cutting any pocket/facing job:
post it, confirm every circular feature appears as four R-format
quadrant lines, and air-cut first.

## -12-B: Estimated Machine Time accuracy fix
The printed estimate came from the post compiler's crude internal
accumulator (CALC_TIME: feed distance/feedrate only - no rapids, tool
changes, etc.), which badly undercounts multi-tool jobs. CAMWorks passes
its own full simulation estimate into the post as CW_TIME (same value it
writes to the "SOLIDWORKS CAM Estimated Machining Time" property). The
native CALC_SETUP_SHEET explicitly prefers CW_TIME when nonzero; our
custom end-of-tape flow never did that swap. Fixed: TIME_* variables are
now overwritten from CW_TIME_* (when CW_TIME<>0) right before
CALL(PROGRAM_END_BANNER). Expect the printed time to now match the
"SOLIDWORKS CAM Estimated Machining Time" file property.

## -12-A: Quadrant-split full circles + Estimated Time position fix
First -F test output (compiled clean, layout perfect, table correct, R
arcs present) exposed two bugs, both fixed here:

1. FULL CIRCLES WERE INVALID: emitted as bare `G02 R..` with no endpoint
   (unsolvable; grblHAL would reject). Root cause confirmed in MILL.LIB
   source: native CALC_RADIAL_ARCS full-circle test is EXACT equality
   `ABS(ARC_INC_ANGLE)=FULL_CIRCLE`, which our circles' computed angle
   does not satisfy - falls through to a single R move whose endpoint
   the modal X/Y registers suppress. FIX: overrode CALC_RADIAL_ARCS in
   our .SRC - detection by tolerance bands (|angle|>359.99 OR <0.01;
   near-0 can only mean a wrapped full circle since 0-degree arcs are
   never emitted), and the split is into FOUR 90-DEGREE QUADRANT arcs,
   not the native two halves: a 180-degree R arc has chord=exactly 2R
   and 1-decimal X/Y rounding can push the printed chord past 2R
   (unsolvable, error:33); 90-degree chords are ~1.414R with huge
   margin (verified numerically against the real job's circles with
   worst-case rounding). Direction from final ARC_DIR (+90 CCW/-90 CW).
   New LIB attrs: QSPLIT FLAG/STEP/COUNT/ANG.
2. ESTIMATED TIME ZEROED: printed "0 Seconds" when the banner was
   called at the end of CALC_END_OF_TAPE. Empirically, TIME_* values
   are only valid inside the ADD_MACRO block right after
   SETUP_SHEET_MILL (the original OUTPUT_ESTIMATED_TIME position) -
   something after ADD_MACRO_END zeroes them. FIX: moved the
   CALL(PROGRAM_END_BANNER) into that exact position. DO NOT move it
   back to section end.

VERIFY on next test: full circles now emit as FOUR R-format arc lines
each (three intermediate quadrant points + return to start); estimated
time shows real value; direction of split circles cuts correctly
(air-cut before material - this is new motion-generating code).

## -F: Condensed final layout (user-approved via rendered preview)
No blank `;` separator lines anywhere except the single one after M30.
Major banners: `~`/`#`/title/`#`/`~` (POST PROCESSOR INFORMATION,
PROGRAM START, PROGRAM END). Minor banners: single `~` rails. Estimated
Machine Time is an indented line inside the PROGRAM END title block.
TOOL_LIST_FOOTER section REMOVED entirely (layout has PROGRAM START
banner butting the last table row; call site is SECTIONEXIST-guarded so
it skips cleanly - if a footer is ever wanted again, just re-declare the
section, the call is still in the loop).

## -E: Estimated Machine Time moved inside PROGRAM END banner
Per user spec: time line now sits between the two `#` rows of the closing
banner. The standalone OUTPUT_ESTIMATED_TIME section was REMOVED entirely -
its call site in CALC_END_OF_TAPE is guarded by SECTIONEXIST so it skips
cleanly (deliberate; do not re-add without also removing the time line
from PROGRAM_END_BANNER or it will print twice). TIME_* values are valid
there because CALC_TOTAL_TIME runs at the top of CALC_END_OF_TAPE.

## ALSO IN THIS VERSION (-D): Layout revised to final user-approved style (UNTESTED)
Single `~` rails (75 chars) for all banners, `#` rows only at file top and
bottom, lone `;` blank lines for breathing room around banners and content
blocks. Estimated Machine Time stays after M30 (cannot exist at header
time), styled to match, before the PROGRAM END banner. Rendered preview
approved by user before packaging.

## PRIOR VERSION (-C): First layout restyle (superseded by -D)
User-specified banner layout applied throughout: major sections (POST
PROCESSOR SUMMARY / PROGRAM OVERVIEW / TOOL TABLE / PROGRAM START /
PROGRAM END) use `_`/`#`/`~` banner blocks; tool changes and operation
summaries use lighter `_`/`~` banners with indented content. Details:
- The user's mockup used the Unicode overline char (U+203E); substituted
  ASCII `~` throughout - this compiler/controller chain is not trusted
  with non-ASCII bytes (verified output file is 100% ASCII).
- ALL remaining `( ... )` comments that wrapped variable text are gone -
  operation Description/Notes lines converted to `;` style in the same
  pass (they embed user-entered CAM-tree text, same latent risk class as
  the tool-name bug). Verified: zero `:T:(` lines containing <..._DISP>
  tokens remain.
- "Post Processer" typo fixed to "Post Processor" in header content.
- Estimated Machine Time cannot print in the header (value only exists
  after all operations are processed) - stays after M30, restyled,
  followed by the new PROGRAM END banner (new PROGRAM_END_BANNER section
  called at the very end of CALC_END_OF_TAPE).
- All 22 TOOL_CHANGE_HDR_TYPE_* sections restyled by script (regex over
  the uniform 3-line pattern), plus OUTPUT_OPER_COMMENT_NO_NOTES /
  WITH_NOTES, OUTPUT_TOOL_LIST_HEADER, TOOL_LIST_FOOTER,
  START_OF_TAPE_MOTION (PROGRAM START banner), OUTPUT_ESTIMATED_TIME.


## ALSO IN THIS VERSION (-B): Tool table moved under the header (UNTESTED)
Table now prints between the header block and the first motion line (N1),
instead of after M30. Structural details that matter for future edits:
- START_OF_TAPE's first motion line was split into its own section
  (START_OF_TAPE_MOTION) so the table can print between header text and N1.
- The table loop moved into a new CALC_PRINT_TOOL_TABLE section, called
  from CALC_START_OF_TAPE inside an IF SETUP_CONFIG<>0 gate.
- CRITICAL ORDERING: the native preload fixups (LAST_PRELOAD overwrite of
  TOOL_ARRAY(0) + ARRAY_COUNT=1 reset) were MOVED from right after
  GETTOOLS(2,CALC_PRELOAD_TOOL) to AFTER the table print - they overwrite
  TOOL_ARRAY(0) and would corrupt the table's first row if they ran first.
  They still run before the first tool change, which is what matters for
  the runtime capture index calibration (ARRAY_COUNT=1).
- The table now reads the NATIVE TOOL_TYPE_ARRAY/TOOL_COMM_ARRAY (not
  CORR_*): at start-of-tape these hold pure preload data written at
  consistent indices by the native CALC_PRELOAD_TOOL loop. The end-of-tape
  corruption that forced the CORR_* workaround came from runtime captures
  mixing in later - that hasn't happened yet at print time. The CORR_*
  capture code in CALC_BEF_SETON_CODES / CALC_INIT_TOOL_CHANGE_MILL is
  retained but currently unused by the table (kept for easy revert).
- VERIFY on first test: every table row's Type/Description matches its
  tool-change header (the native-array theory is well-grounded in the
  MILL.LIB source but not yet empirically confirmed at this hook point);
  table sits between header and N1; nothing table-related prints after
  M30 anymore (Estimated Machine Time still does, unchanged).


## MAJOR CHANGE IN THIS VERSION: R-format arc output (UNTESTED - verify carefully)

### The problem this solves: grblHAL error:33 on cutter-compensated arcs
SolidWorks CAM's software-computed cutter compensation ("With
compensation" toolpath center - the ONLY mode usable on grblHAL, since
grblHAL does not support G41/G42 at all, confirmed from the grblHAL
project itself) produces corner/lead arcs whose I/J values imply start
and end radii differing by ~0.025mm (almost exactly 1 thousandth of an
inch - strong signature of internal inch-based rounding in CAM's offset
math). grbl/grblHAL hardcodes an arc validity check (NOT adjustable via
$12, which only controls trace resolution AFTER validation): mismatch
must be <=0.005mm, or <=0.1% of the arc radius. CAM's ~0.025mm floor
fails that for any arc under ~25mm radius. Exhaustively confirmed
unfixable on the CAM side: Arc Fit tolerance (3 values incl. min 0.01mm),
Arc Fit on/off, lead-in radius (3 values, non-monotonic results),
"Internal sharp corners" (only available in "Without compensation" mode =
requires G41/G42 = unusable on grblHAL). Post cannot intervene either:
X/Y/Z/I/J values come from opaque compiled ATTRCFUNC functions
(CALC_ENDPOINT/CALC_CENTER) with no read access from post code.

### The fix: switch from I/J center output to R radius output
R-format arcs (G02/G03 X.. Y.. R..) structurally cannot produce this
error - only ONE radius value is given, so there is nothing for the
controller to cross-check against itself. The entire R infrastructure
turned out to already exist natively:
- `:ARCS=CENTER` directive at the top of the .SRC selects I/J mode;
  changed to `:ARCS=RADIAL` (one-word change, line 8)
- Native `R` register with its own compiled CALC_RADIUS function
- `RADIUS_MOVE_MILL` output section (already present in the .SRC;
  updated its template from bare `<G>` to `<G:ARC_DIR>` to match how
  ARC_MOVE_MILL emits the G02/G03 direction - ARC_DIR is confirmed set
  before the radial branch dispatches)
- Native `CALC_RADIAL_ARCS` in MILL.LIB automatically SPLITS FULL
  CIRCLES into two 180-degree R-moves (computes the diametrically
  opposite point via trig) - full circles cannot be expressed in
  R-format, and the master library already handles this.

### MUST VERIFY on first test (in order):
1. Compile clean (the <G:ARC_DIR> template change is the likeliest
   compile risk)
2. Arcs now emit as `G02/G03 X.. Y.. R..` with NO I/J words
3. Full circles (e.g. the facing-op circles previously emitted as bare
   `G02 I.. J..` with no X/Y) now appear as TWO consecutive R-format
   half-circle moves
4. grblHAL accepts 180-degree R arcs - KNOWN RISK: at exactly 180
   degrees the center is mathematically ambiguous from (start,end,R);
   some controllers reject or mis-resolve this. If grblHAL rejects
   them, the fallback is overriding CALC_RADIAL_ARCS with a
   quadrant-splitting version (user's original idea; the trig precedent
   to copy is right in the native CALC_RADIAL_ARCS at MILL.LIB
   ~line 6889)
5. Direction sanity: verify a known-CW arc emits G02 and cuts the
   correct way (the ARC_NORM_Z inversion logic runs before the radial
   dispatch, so it should be inherited correctly - but verify)
6. AIR CUT the first real job with R-format before cutting material -
   this changes every arc motion command in every future program.



---

## Fixed this session (2026.07.09-M)

### 5. Nested parentheses breaking real G-code execution — RESOLVED
A real part with tools named using a "fractional-inch (metric equivalent)"
convention (e.g. `1/4" (6.35mm) CRB_EM 2FL 26 LOC`) caused the posted file
to fail on actual hardware: it ran only the first line and reported
"complete." Root cause: grblHAL (like most G-code dialects) closes a
`(...)` comment at the **first** `)` it finds - it does not support
nested parentheses. Any comment whose content itself contains a `)`
(e.g. a tool description with a unit conversion in parens, or a Material
custom property value like `6061-T3 (SS)`) closes early, leaving a bare
unmatched `)` sitting in the G-code stream as invalid syntax.

This had been a **latent bug** the whole time Material Type existed in
the header - every prior test job's tool names happened to be pure metric
with no parens, so it never surfaced until a real part with parens-in-name
tooling was actually run on hardware (rather than just reviewed as text).

**Fix**: converted every line that embeds fetched/variable text (tool
descriptions and the Material property) from `(...)` comment style to
`;` line-comment style, which runs to end of line and is completely
immune to parenthesis content:
- All 21 `TOOL_CHANGE_HDR_TYPE_*` sections (+ 1 fallback) - the tool-change
  header line containing `<TOOL_COMMENT_DISP>`
- All 21 `TOOL_ROW_TYPE_*` sections (+ 1 fallback) - the tool-table row
  line containing `<TOOL_COMM_DISP>`
- The `Material Type:` header line containing `<MATERIAL_DISP>`

Static lines with no variable content (dashed separators, "Post Version",
etc.) were deliberately left as `(...)` - only lines that echo
CAMWorks/SolidWorks-sourced text were changed, since those are the only
ones whose content isn't under the post's control.

**Also converted**: `Part Name:` (`<PART_NAME_DISP>`, the SolidWorks
filename) - same latent risk if a part is ever named with parentheses,
now covered.

**Scoping decision**: deliberately did NOT convert every comment in the
file to `;` "just in case." Only lines that echo fetched/variable text
(tool descriptions, Material, Part Name) can ever contain an unbalanced
paren - static separator/label lines are 100% author-controlled text and
can never break this way regardless of comment style. A blanket sweep
would also risk changing behavior for tools (like ncSender) that may
parse `(...)`-style comments specially for UI display purposes, for no
correctness benefit on lines that were never actually at risk.

---

## Fixed previously (see prior notes below for full detail)


### 1. Tool table Type/Description offset — RESOLVED
Two separate, compounding bugs, both found via targeted diagnostic builds
(temporary `:T:` debug lines), not guesswork:

- **Cause A — array-name collision.** MILL.LIB's native `CALC_PRELOAD_TOOL`
  (fired once via `GETTOOLS(2,...)` at the very start of the tape) writes
  into the same `TOOL_TYPE_ARRAY`/`TOOL_COMM_ARRAY` our own tool-change
  capture also used. Its leftover data at low array indices was never
  cleared, unlike `TOOL_ARRAY(0)`/`TOOL_DIAM_ARRAY(0)` which explicitly are.
  **Fix:** capture into brand-new dedicated arrays instead —
  `CORR_TYPE_ARRAY`/`CORR_COMM_ARRAY` — never touched by native code.
- **Cause B — consistent 1-index offset.** Even after Cause A was fixed, a
  clean, constant 1-index gap remained between where our hooks captured
  data and where `TOOL_ARRAY` actually stored each tool (confirmed via
  diagnostic logging against a real 25-tool job: every capture at index
  `N` landed in `TOOL_ARRAY` at index `N-1`, with zero exceptions).
  Root mechanism inside the compiled engine unconfirmed — something
  between our hook and the native write advances `ARRAY_COUNT` once more
  than the visible source implies. **Fix:** capture at `ARRAY_COUNT-1`
  (was `ARRAY_COUNT`) in `CALC_BEF_SETON_CODES`, and `ARRAY_COUNT-2` (was
  `ARRAY_COUNT-1`) in `CALC_INIT_TOOL_CHANGE_MILL`.

**Verified**: all 16 tool rows in a real test job matched their headers
exactly (Tool#, Type, Diameter, Description all correctly paired).

### 2. Tool table diameter format — RESOLVED
Changed `TOOL DIAM DISP` from `LEFT_PLACES=2`/`RIGHT_PLACES=3` (`##.###`)
to `LEFT_PLACES=3`/`RIGHT_PLACES=2` (`###.##`). Same total width (6 chars),
so no header/column spacing changes needed.

### 3. Material Type blank in header — RESOLVED
Root cause was **not a code bug** — the SolidWorks custom property named
`Material` simply didn't exist on that test part's Custom tab yet. Once
added (and, per the user's workflow, linked to the assigned SW material so
it doesn't need re-typing per part), `GET_SW_CUSTOM_PROP_BY_NAME({Material},
CALC_GET_MATERIAL_CUSTOM_PROP)` picks it up correctly. No further action
needed unless it goes blank again — if so, check the Custom tab for that
specific part first, before assuming a code regression.

### 4. Stock Size in header — TRIED, REVERTED (not currently possible)
User wanted `Material Thickness` replaced with Stock X/Y/Z. Investigated
thoroughly and confirmed dead-end for now:
- No native CAMWorks Stock Manager variable exists anywhere in `MILL.LIB`
  (confirmed by full-text search, including the `QUERY_SYSTEM()`
  mechanism used elsewhere for CAM-specific data).
- SolidWorks' Bounding Box feature *does* auto-generate properties
  (`Total Bounding Box Length/Width/Thickness`, no `SW-` prefix) — but
  they live only on the **Configuration Properties** tab.
- **Confirmed by direct test** (both a linked Bounding Box value and a
  plain typed dummy value): `GET_SW_CUSTOM_PROP_BY_NAME` cannot read
  anything from the Configuration Properties tab at all. It only works
  against the document-level **Custom** tab (same tab Material lives on).
- User's CAMWorks Stock size = bounding box + a margin that varies per
  job, so even if the tab issue weren't there, a bounding-box link
  wouldn't reflect the true stock size anyway.
- **Decision**: not worth the manual-entry burden this would require:
  removed the header line and all related code (fetch calls, callback
  sections, scratch/display attributes) rather than keep a manual-only
  field. `Material Thickness` was *not* restored in its place (user only
  asked to remove Stock Size, not bring Thickness back) — easy to restore
  if wanted later, just ask.

**If revisiting**: don't re-attempt the Configuration Properties /
Bounding Box route — that's a proven dead end with this compiler. Only
a Custom-tab property (manually typed or copy-pasted per part) would work.

---

## Working conventions established this session (apply going forward)

- **Version stamp**: hardcoded literal text in the header
  (`Post Version: YYYY.MM.DD-<letter>`), bumped by hand on every edit.
  This is the only way to confirm a posted file actually reflects the
  latest compiled `.ctl` — SolidWorks CAM gives no visible compile
  timestamp, and edited `.SRC`/`.LIB` text does nothing until recompiled
  through the Post Processor Editor. Dates use **Central time (CST/CDT)**
  per user preference, not UTC.
- **GitHub repo workflow (adopted at v2026.07.12-D)**: source lives at
  https://github.com/Compwiser1/SW2026_Post_Processor_GrblHAL_Mill_3axis_Metric
  with STABLE filenames (`SW26_GrblHAL_Mill_3axis_Metric.SRC/.LIB/.lng`) so
  Git diffs/history work across versions. The version lives in: the header
  stamp (unchanged discipline), Git tags (`v2026.07.12-D`), and versioned
  zips attached to GitHub Releases (with the compiled `.ctl`). The
  `:LIBRARY=` self-reference now points at the stable `.LIB` name and no
  longer changes per version.
- **Notes file in every zip**: starting after `2026.07.09-L`, every
  version handoff includes an updated copy of this notes file inside the
  zip alongside `.SRC`/`.LIB`/`.lng`, not just the code. Update the
  "Current version" line, the "Fixed this session" section, and anything
  in "Still open" before zipping - don't ship code without it.
- **Zip naming**: `SW26_GrblHAL_Mill_3axis_Metric_<version>.zip`, and the
  three files *inside* the zip are also individually renamed to that same
  base name (`.SRC`/`.LIB`/`.lng`).
- **`:LIBRARY=` self-reference gotcha**: the `.SRC` file has a hardcoded
  path to its own `.LIB` file (`:LIBRARY=.\<filename>.LIB`, near the top).
  This must be updated to match every time the `.LIB` filename changes —
  otherwise the compiler can't find its own library. This exact class of
  bug caused a real N-number regression earlier in the project (see the
  original notes file).
- **`:T:` output is not allowed inside any section whose name starts with
  `CALC_`** — confirmed by direct compiler error. Text output for
  diagnostics or anything else must live in its own plain-named section
  and get `CALL()`ed from the `CALC_` section instead.
- **`ARRAY_COUNT` and `LOOP` cannot be bound directly to a display
  attribute's `:VAR=`** — compiler rejects it ("Primary var not found"),
  even though they're declared normally in `MILL.LIB`. Copy to an
  ordinary scratch variable first (same pattern already used for
  `CUR_TYPE`), then bind the display attribute to the copy.
- **`GET_SW_CUSTOM_PROP_BY_NAME` only reads the document-level Custom
  tab** — confirmed it cannot see Configuration Properties tab entries at
  all, static or linked. Keep this in mind for any future SolidWorks
  data-pull requests.
- **grblHAL `(...)` comments do not support nesting** — they close at the
  first `)` encountered, full stop. Any line that embeds fetched/variable
  text (tool descriptions, material names, part names) must use `;`
  line-comments instead if that text could ever contain a `)` — e.g. a
  tool named `1/4" (6.35mm) ...` or a material value like `6061-T3 (SS)`.
  This was a real, latent bug that only surfaced the first time a part
  with parens-containing tool names was actually run on hardware, not
  just reviewed as text output - don't assume "it worked in past test
  files" rules this out for a new job with different tooling.
- **Diagnostic-first debugging works well in this project.** Every real
  bug this session (tool table array collision, the 1-index offset,
  Material's true cause) was found via temporary `:T:` debug lines dumping
  actual runtime values, not by reasoning about the source alone — the
  compiled behavior repeatedly diverged from what the visible `.SRC`/`.LIB`
  code implied. Default to adding a diagnostic build before a second
  guess, not after.

---

## Diagnosed as NOT a post-processor issue (informational, no code change)

### grblHAL error:33 ("Motion command target is invalid") on a specific job
A test job ("Operation Compensation Test 2 - Simple External Profile")
stopped mid-run on real hardware with no post-side symptom (clean file,
no comment/parsing issue - confirmed byte-for-byte). ncSender's console
log showed the real cause: `error:33` on a G03 move, meaning the arc's
start-point-to-center radius and end-point-to-center radius didn't match
within grblHAL's tolerance (verified mathematically: 0.635mm vs 0.651mm,
~0.016mm mismatch). This is a CAM-side arc-fitting precision issue, not a
post output-formatting issue - matches the previously-documented
"coordinate/feed decimal formatting" limitation (post can't control the
underlying precision of CAMWorks' arc-fit math, only how it's displayed).
**Fix lives in SolidWorks CAM** (tighten the operation's cutting/arc-fit
tolerance) **or in grblHAL's own settings** (loosen arc tolerance), not in
`.SRC`/`.LIB`. If this pattern recurs, check the specific operation's
tolerance setting before assuming a post regression.

## Still open (from the original notes file, untouched this session)

- Coordinate/feed decimal formatting — accepted as a final, documented
  compiler limitation (X/Y/Z/I/J/K/F won't consistently show 2 decimals).
- N-number leading zeros — cosmetic only; a prior attempt to fix broke
  sequence numbering entirely and was reverted. Needs a careful, isolated
  attempt separate from anything touching the counter mechanism.
- Corner Radius column removal from the tool table — not achievable
  without a fully custom table (six rounds of real compile failures
  earlier in the project). User has explicitly rejected an external
  plugin/script-layer approach for this and future work — everything
  needs to happen in the post itself.
