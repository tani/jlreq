# Upstream Issue draft (PLAN.md §12-5): pdfLaTeX backend for jlreq

This is a **draft** for the upstream issue to abenori/jlreq. It reflects the
current implementation state (M1–M8 horizontal scope complete; vertical
explicitly gated out).

---

## Title (proposal)

Add a pdfLaTeX (pdfTeX) backend to jlreq — engine detection, horizontal
typesetting rules, and audited compatibility

## Body (proposal)

### 目的 / Goal

Make `\documentclass{jlreq}` usable with `pdflatex` for **horizontal**
documents while keeping the existing public API and Japanese typesetting
rules, and keeping pLaTeX/upLaTeX/LuaLaTeX behavior untouched. Vertical
writing (`tate`) stays unsupported under pdfTeX with an explicit error (an
engine-API gate; see below).

### 実績 / What exists

1. **M1 — engine detection** (smallest possible diff, mergeable alone)
   - `jlreq-helpers.sty`: pdfTeX detected via `\pdftexversion` (engine letter
     `d`); `\directlua` → l, `\pdftexversion` → d, `\ucs` → u. No misdetection.
   - `jlreq.cls`: `pdflatex` class option; explicit-option vs actual-engine
     mismatch error; pdfTeX path separated before any pTeX primitive.
2. **M2 — glyph & unit foundation**: `jlreq-pdftex.sty` (internal) loads
   `bxcjkjatype[ipaex-type1,noCJKpunct]`, establishes an always-on CJK state
   at class load (so `\hbox{阿}` measurement works), emulates `\zw`/`\zh` as
   size-tracking dimen macros, declares `\Cht`..`\Chs`. Measured at load:
   Cwd=10.0/Cht=8.8/Cdp=1.2/Cvs=17/Chs=10pt @10pt.
3. **M3 — JFM data from the single source**: `make_pdftex_jfm.lua` generates
   `jlreq-pdftex-jfm{,-b,-z,-bz}.def` (402 pair rules, 25 classes, 403 chars
   each) from `jfm-jlreq.lua`. `make check-pdftex-jfm` proves regeneration
   diff = 0; `check_jfm_pdftex.lua` byte-checks every pair against the source.
   Runtime needs **no Lua** (static `.def` files are committed).
4. **M4/M5 — horizontal rules**: pair glue (exact JFM values incl. 二分アキ
   before opening brackets), kinsoku (行頭/行末 penalties per jlreq's own
   class lists), JA↔LA spacing (xkanjiskip), and an end_adjust approximation
   (squeeze folded into glue shrink — line-end-only semantics and priority
   order are documented as pdfTeX-inexpressible). Measured: 7/7 pair
   fixtures PASS at exact pt values; kinsoku verified by bbox (no line-head
   closing brackets); squeeze verified (85pt natural content fits 78.5pt
   line, 0 Overfull).
5. **M6 — class integration**: `jlreq-complements.sty` gained a `pdflatex`
   option (thebibliography/theindex/theorems work; the class loads it under
   d); coexistence verified with hyperref (Japanese bookmarks via UTF-16BE
   outlines), amsmath, graphicx/xcolor, lists, tables, and a class-options
   sweep (paper/fontsize/line_length/… + `\jlreqsetup` keys; 割注 works).
6. **M8 — packaging/docs**: README ja/en describe the experimental support
   and limitations; `docs/pdftex-{audit,compatibility,internals,tests,
   jfm-generation}.md`; Makefile `install`/`tds` ship the backend files and
   the `.def` data; CI gate = `make check-pdftex-jfm`.

### 検証 / Verification summary

- p/u/l regression: 3 fixtures × 3 engines — **DVI byte-identical**
  (timestamp-normalized) for p/u; **PDF date-normalized byte-identical** for
  lualatex, before vs after the whole backend work.
- pdflatex: mixed doc + rule-measurement fixtures (7 pair measurements exact
  to pt) + 10 coexistence fixtures (hyperref JP bookmarks, amsmath,
  graphicx/xcolor, lists, tables, options sweep, microtype+twocolumn,
  trimmarks with TrimBox/BleedBox, warichu, headings-toc-aux, footnotes-rules)
  — all rc=0; `pdftotext` extraction correct; IPAex Type 1 embedded.
- Kinsoku: line-head punctuation machine-scanned from PDF bbox across all
  fixtures — **0 violations** (closing brackets, stops, commas never start a
  line). One rare edge (latin→closing-bracket in narrow columns via the
  CJK decoder's internal node) is documented in the compatibility matrix.
- Test base: `tests/run-pdftex-tests.sh` (46 checks: T1 JFM data, T2 error
  conditions, T3/T4 rule measurements + bbox scan, T5 documents, T7
  3-engine regression + backend isolation).
- Performance: (B) backend 1.5× the raw bxcjkjatype baseline; 0.375s vs
  upLaTeX 0.191s / LuaLaTeX 0.961s on the 2-page stress fixture.

### 明示的な制限 / Explicit limitations (per the basic principle: no
unsupported claims)

- 縦組み（`tate`）: pdfTeX lacks `\tate`/`\iftdir`/縦用JFM etc. — explicit
  error under d (G4 gate decision: horizontal-first).
- ぶら下げ組み: pdfTeX has no line-end protrusion mechanism — unsupported
  (the `-b` variant data exists for the future).
- Priority-ordered stretch/shrink (`stretch_priority`/`shrink_priority`) and
  line-end-only `end_adjust`: approximated (single-priority shrink); the
  exact semantics are inexpressible on the stock breaker — documented.
- `\eqref` (hyperref+math) and Japanese in math matrix cells: CJK active
  character interaction — known limitation, fixtures document workarounds.
- `jlreq-trimmarks` under pdfTeX: still an explicit error (deep pTeX tombow
  machinery dependency; a prototype worked but was withdrawn after a p/u
  regression — needs its own careful PR).
- `jlreqsetup` length keys under pdfLaTeX: use `2\zw` (macro) instead of the
  literal `2zw` in key values like `footnote_indent`.
- `\sidenote` / `\sidenotemark` / `\sidenotetext` (both `sidenote_type`
  variants): `number` fails with `Dimension too large` inside the marginpar
  box-adjust path; `symbol` hits a `\CJK@punctchar` internal error — blocked
  pending a dedicated integration pass. `\marginpar` plain, `\footnote` and
  `\endnote` work as alternatives (tested).
- `\　` (single-U+3000 control-sequence spelling): U+3000 is not a letter
  under the CJKutf8 route, so the spelling cannot tokenize — blocked by
  design. Use the literal U+3000 character (outputs as a CJK space) or
  `\jaspace{zenkaku/nibu/shibu}` (tested rc=0).
- `reference_mark=interlinear` (行間合印): position computation depends on
  `\lastnodechar`, fixed at -1 under pdfTeX — `reference_mark=inline` is the
  supported mode (tested rc=0).
- `hanging_punctuation`: as above, terminal limitation agreed (G3) — option
  selects the `-b` JFM variant without runtime error, but the protrusion
  mechanism itself does not exist in pdfTeX.

### 提案 / Proposed PR series (per PLAN.md §8)

1. PR 1: engine detection + fixtures (already structured this way).
2. PR 2: `jlreq-pdftex.sty` + cls gates (fonts/units/metrics).
3. PR 3: generator + `.def` data + Makefile check targets.
4. PR 4: rules backend (`jlreq-pdftex-rules.sty`).
5. PR 5: complements option + docs + README.

### 質問 / Questions for the maintainer

1. Is the horizontal-only scope with an explicit vertical error acceptable
   for a first merge (vertical gated behind G4)?
2. Default font configuration `ipaex-type1` — or should another preset be
   the pdfTeX default?
3. Should `jlreq-trimmarks` pdfTeX support land separately later, given the
   pTeX tombow machinery dependency?
