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
   class lists), JA↔LA spacing (xkanjiskip), punctuation JFM widths (glyph
   boxed at class width w<1zw with tentsuki overhang — identical ink
   geometry vs platex reference), hanging punctuation (`hanging_punctuation`
   via `\pdfprotrudechars=2` + `\rpcode`, `-b`/`-bz` variants), and an
   end_adjust approximation (squeeze folded into glue shrink — line-end-only
   semantics and priority order are documented as pdfTeX-inexpressible;
   priority loss measured harmless: poc/README-m5-numeric.md). Measured:
   pair fixtures PASS at exact pt values; kinsoku verified by bbox (no
   line-head closing brackets); hanging verified (right margin kern −10pt,
   ink ends 0.5zw past the nominal edge); squeeze verified (0 Overfull).
5. **M6 — class integration**: `jlreq-complements.sty` gained a `pdflatex`
   option (thebibliography/theindex/theorems work; the class loads it under
   d); `jlreq-trimmarks.sty` gained pdfTeX tombow + TrimBox/BleedBox +
   rotated banner (`\rotatebox{-90}`); `\sidenote` (both `sidenote_type`
   variants) works; `reference_mark=interlinear` works; Q/H units work in
   all length options and `\jlreqsetup` values (1Q=1H=0.25mm), incl. literal
   `2zw`; Japanese in math (`\mathmc`/`\mathgt`, direct JA chars, matrix
   cells) works behind enablejfam; `\kansuji` is implemented as an
   expandable digitwise macro (13 values verified against upLaTeX);
   `\mag`-based runs are geometry-exact vs the pTeX DVI route.
   Coexistence verified with hyperref (Japanese bookmarks via UTF-16BE
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
  to pt) + 23 coexistence fixtures (hyperref JP bookmarks, amsmath,
  graphicx/xcolor, lists, tables, options sweep incl. Q/H units,
  jlreqsetup literal-zw, microtype+twocolumn, trimmarks with
  TrimBox/BleedBox, trimmarks rotated banner, warichu, headings-toc-aux,
  footnotes-rules, sidenote & sidenote-symbol, math-jfm &
  math-jfm-disablejfam & math-matrix, eqref-hyperref, kanji-numbers,
  reference-mark-interlinear) — all rc=0; `pdftotext` extraction correct;
  IPAex Type 1 embedded.
- Kinsoku: line-head punctuation machine-scanned from PDF bbox across all
  fixtures — **0 violations** (closing brackets, stops, commas never start a
  line). The formerly documented rare edge (latin→closing-bracket `（x）`
  in narrow columns) is fixed: the zero-glue CJK-decoder residue before
  prebreak classes is now `\unskip`ped (fixture preclose-latin.tex).
- Test base: `tests/run-pdftex-tests.sh` (65 checks: T1 JFM data, T2 error
  gate, T3/T4 rule measurements + bbox scan, T5 documents, T7
  3-engine regression + backend isolation).
- Performance: (B) backend 1.5× the raw bxcjkjatype baseline; 0.375s vs
  upLaTeX 0.191s / LuaLaTeX 0.961s on the 2-page stress fixture.

### 明示的な制限 / Explicit limitations (per the basic principle: no
unsupported claims)

- 縦組み（`tate`）: **experimental core implemented** (T1, 2026-10-23 —
  see docs/pdftex-tate-eval.md). bxcjkvert/CJKvert as a *dependency path*
  is insufficient (glyph-level rotation only; punctuation lands wrong
  corner, no tate-chu-yoko/JFM/paper model), so instead of that package
  we use a shipout-rotation architecture (horizontal inner galley,
  +90° CJK glyphs with per-class metric offsets, whole output box
  rotated −90°): reading top→bottom, columns right→left, kinsoku
  verified from galley dumps, 2-page verified, pair glue matches the
  tests/fixtures/pdflatex-tate-*.tex). Follow-up slices additionally
  verified page furniture (running heads placement, `\@outputpage`
  furniture-width override), vertical headings/TOC, footnote/endnote/
  sidenote/`\marginpar` and basic floats (**T1 core unchanged — bbox/cm
  parity with uplatex ground truth**), and math adjacency (ground truth
  is the uplatex "寝かせ" style: whole formula rotated CW-90°, matched
  with a δ=0.343zw inboard correction; edges bitwise). Remaining:
  jlreq-trimmarks banner in tate, `\tatechuyoko` (explicit ClassError
  as on other engines in non-tate spots), ruby, tate-keyed jlreqsetup.
- Priority-ordered stretch/shrink (`stretch_priority`/`shrink_priority`) and
  line-end-only `end_adjust`: approximated (single-priority shrink); the
  exact semantics are inexpressible on the stock breaker — documented and
  measured harmless on the reference corpus (poc/README-m5-numeric.md).
- Japanese `\label` names: active-byte expansion inside
  `\csname r@…\endcsname` — agreed unfixable without breaking hyperref
  bookmarks; ASCII labels are the documented workaround (see comments in
  tests/fixtures/pdflatex-coexist/eqref-hyperref.tex). (`\eqref` +
  hyperref with Japanese section context itself works; fixture proves
  refs resolve.)
- Paragraph-start LA→JA boundary gets no xkanjiskip: detecting a latin
  predecessor in unshifted horizontal mode is structurally unsound under
  pdfTeX (latin chars are unhookable; indent/kern signatures ambiguous) —
  limitation agreed after probe (paragraph-boundary reset itself works).
- `\　` (single-U+3000 control-sequence spelling): U+3000 is not a letter
  under the CJKutf8 route, so the spelling cannot tokenize — blocked by
  design. Use the literal U+3000 character (outputs as a CJK space) or
  `\jaspace{zenkaku/nibu/shibu}` (tested rc=0).
- Font set is IPAex only (`ipaex-type1`, with `\CJKbold` synthetic bold);
  other Japanese font presets are future work.
- fontsize/jafontsize in `zw`/`zh` units is self-referential under pdfTeX
  and raises an explicit ClassError (jlreq.cls:611–626) — previously it
  silently became 0pt. Q/H units and `jafontscale` ratios are the supported
  alternatives (tested).
- ~~Tombow *drawing coordinates* with `\mag≠1000`~~ → resolved: tombow
  marks now match uplatex at `\mag=1200` too (HiRes ink-bbox identical:
  `42.048 42.174 845.082 1140.894`), via the `\put` origin correction in
  jlreq-trimmarks-pdftex.def:58–77 (cancels the `\hoffset`/`\voffset`
  leakage into stored drawing coords; content-stream verified; mag=1000
  stream byte-unchanged). Regression gate: `tests/fixtures/pdflatex-coexist/
  mag-tombow.tex` + `tests/check-tombow-mag.py` asserting the mag-invariant
  stored rule coordinates (35.05, 922.444) and the ×1.2 page CTM. Text-block
  parity stays bitwise (y ≤0.065bp vs uplatex, jlreq-trimmarks-pdftex.def:79–89).
- Hanging punctuation is implemented (`-b`/`-bz` variants) but degrades
  silently if a whatsit (e.g. hyperref `\label`) lands between the 、。 and
  the following pair glue (node-level constraint, poc/README-g3b.md).

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
3. `jlreq-trimmarks` pdfTeX support is implemented (tombow, TrimBox/BleedBox,
   rotated banner via `\rotatebox{-90}`). Should it ship in the same PR
   series as the class integration, or as its own PR for separate review of
   the reimplemented tombow machinery?
