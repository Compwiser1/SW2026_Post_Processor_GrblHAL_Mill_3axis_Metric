# SW2026 Post Processor — GrblHAL Mill, 3-Axis, Metric

A SOLIDWORKS CAM 2026 post processor targeting **grblHAL** firmware.
Developed and tested on a FrankenOKO CNC mill running a Sienci SLB-EXT
control board, with G-code streamed via
[ncSender](https://github.com/siganberg/ncSender).

Current version: **2026.07.12-D** (see the `Post Version` stamp in the
program header of every posted file, and Git tags/Releases here).

## Key features

- **R-format arc output with automatic full-circle quadrant splitting.**
  grblHAL enforces a hardcoded arc radius-consistency check on I/J arcs
  (`error:33`) that SOLIDWORKS CAM's software-computed cutter
  compensation cannot reliably satisfy (its internal precision floor is
  roughly one thousandth of an inch). This post outputs radius-format
  arcs instead, which are structurally immune to that check, and splits
  full circles into four 90-degree arcs (R-format cannot express a full
  circle, and 180-degree halves sit numerically on the solvability
  limit). Micro-sliver arcs emitted by CAM's compensation engine at
  corner transitions are filtered out (below output resolution; in I/J
  form they decode as full-circle commands and will gouge).
- **Machine-verified**: partial arcs, quadrant circles, sliver
  suppression, and physical arc motion all confirmed on real hardware.
- **grblHAL-safe comments**: every line that embeds user-controlled text
  (tool descriptions, material, part name, operation names/notes) uses
  `;` line comments. grblHAL closes `( )` comments at the first `)`, so
  tool names like `1/4" (6.35mm)` or materials like `6061-T6 (SS)` break
  parenthesis-style comments and halt execution mid-program.
- **Tool table under the program header** (tool number, type, diameter
  in `###.##` mm, description), de-duplicated for reused tools.
- **Material Type in the header**, pulled from a SOLIDWORKS custom
  property (see Setup below).
- **Estimated machining time** from CAMWorks' own simulation estimate
  (`CW_TIME`), not the post compiler's crude feed-distance accumulator.
- **Safe start/end motion**: program start retracts Z to machine home
  (`G91 G28 Z0` — always up, never down) before any X/Y travel; every
  operation positions X/Y before descending Z.
- Clean sectioned output layout (banner-separated program info,
  overview, tool table, tool changes, operation summaries, program end).

## Files

| File | Purpose |
|---|---|
| `SW26_GrblHAL_Mill_3axis_Metric.SRC` | Post source (sections, output templates, logic) |
| `SW26_GrblHAL_Mill_3axis_Metric.LIB` | Post attribute library (variables, formats) |
| `SW26_GrblHAL_Mill_3axis_Metric.lng` | Language file |
| `NOTES.md` | Development history, known constraints, compiler gotchas |

The compiled `.ctl` binary is attached to Releases — SOLIDWORKS CAM
posts from the `.ctl`, not from these source files.

## Installation

1. Download the source files (or the `.ctl` from a Release if you don't
   need to modify anything).
2. If building from source: open the `.SRC` in the SOLIDWORKS
   CAM/CAMWorks **UPG-2 Post Processor Editor** and **compile** to
   produce the `.ctl`. Note: editing `.SRC`/`.LIB` does nothing until
   explicitly recompiled — posting uses only the `.ctl`. The `.SRC`
   expects `MILL.LIB` at `C:\CAMWorksData\UPG-2\MasterLibraryFiles\`
   (adjust the `:LIBRARY=` line if yours lives elsewhere).
3. Select the post in your SOLIDWORKS CAM machine definition.

## Required SOLIDWORKS setup

- **Material Type**: add a custom property literally named `Material` on
  the **Custom** tab (`File > Properties > Custom`) — link it to the
  assigned SW material so it stays in sync automatically. Note: the post
  cannot read the Configuration Properties tab at all (confirmed
  compiler limitation), only the document-level Custom tab.

## Known limitations

- **ncSender's 3D preview does not render R-format arcs** — it draws
  straight chords between arc endpoints, so curves look like polygons on
  screen. Display-only: the sender streams motion verbatim and grblHAL
  executes the arcs correctly (machine-verified). Do not convert back to
  I/J for the preview's sake — I/J is what produces unfixable `error:33`
  radius-mismatch failures with SOLIDWORKS CAM's compensated toolpaths.
- Coordinate/feed decimal padding is governed by the compiler's built-in
  functions and cannot be customized (documented UPG-2 limitation).
- See `NOTES.md` for the full list of constraints and the reasoning
  behind design decisions.

## Machine context

Built for a 3-axis metric mill running grblHAL with software-computed
cutter compensation ("With compensation" toolpath center in SOLIDWORKS
CAM) — grblHAL does not support G41/G42, so machine-side compensation is
not an option on this firmware.

## License

GPL-3.0 — see [LICENSE](LICENSE).
