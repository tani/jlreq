# pdfTeX-ja (pdftexja) — Japanese typesetting for pdfLaTeX (experimental)

pdfTeX-ja plays, for **pdfLaTeX**, the role [LuaTeX-ja](https://ctan.org/pkg/luatexja)
plays for LuaLaTeX: it is the engine-level foundation of Japanese typesetting
(character classes and JFM glue, kinsoku, `zw`/`zh` units, vertical writing)
on which document classes build. The [jlreq](../README.md) class uses it as its
pdfLaTeX backend, exactly like it uses LuaTeX-ja under LuaLaTeX.

pdfTeX-ja is **not** a LuaTeX-ja clone. pdfTeX has no Lua, no node callbacks,
no box direction attribute and no control sequence names made of multi-byte
characters, so several mechanisms and APIs are pdfTeX-specific (listed below).

```latex
\documentclass{article}
\usepackage{pdftexja}
\begin{document}
日本語の文章です。「括弧」と、句読点。Latin text混在。
\end{document}
```

## How it works

* **Glyphs**: the CJK bundle's UTF-8 decoder through
  [bxcjkjatype](https://ctan.org/pkg/bxcjkjatype) (IPAex Type1 by default).
  The CJK state is switched on once for the whole file, so Japanese literals
  work everywhere (also inside class files at load time).
* **JFM**: pdfTeX-ja reads LuaTeX-ja JFMs as pre-generated TeX data
  (`ptjfm-<name>.def`, made by `pdftexja-jfmconv.lua`; no Lua at run time).
  Between consecutive characters the JFM pair glue (or kerns) are inserted,
  with LuaTeX-ja's semantics: kanjiskip/xkanjiskip fallback, priority data,
  `end_adjust` line-end candidates (hanging punctuation), mixed-size blending.
* **Kinsoku / jaxspmode**: per character, LuaTeX-ja semantics; the defaults are
  LuaTeX-ja's (`pdftexja-kinsoku.tex`, generated from `ltj-kinsoku.tex`).
* **Vertical writing** (`tate`): the page is typeset in an inner horizontal
  frame with rotated (or true vertical, from auxiliary vertical fonts) glyphs,
  and the page box is rotated at shipout. Furniture, footnotes, inline math
  baseline shift, tate-chu-yoko and yoko pages are handled.

## Package options

| option | meaning |
|---|---|
| `fontset=ipaex-type1\|ipa\|haranoaji\|custom` | font set (default `ipaex-type1`) |
| `fontprofile=<file>` | vertical glyph profile (required for `custom` + `tate`) |
| `jfm=<name>` | horizontal JFM data `ptjfm-<name>.def` (default `ujis`) |
| `tjfm=<name>` | vertical JFM data (default `ujisv`); used with `tate` |
| `tate` | vertical document (the class must provide a vertical page geometry: `\textwidth` is the line length) |
| `scale=<real>` | CJK size = `\f@size`×scale (default 1) |
| `disablejfam` | do not define `\mathmc`/`\mathgt` |
| `kinsoku=false` | do not load the default kinsoku table |

Only the JFM of the document direction is loaded.

## User and class API

### Units and metrics
* `\zw`, `\zh` — macros expanding to a dimen register: write `2\zw` (pdfTeX
  has no `zw` unit). Recomputed at every font size change.
* `\ptjsetzw{<dimen>}` — provisional assignment (before the first `\selectfont`).
* `\ptjconvertunits<tl var>` — rewrite pTeX units in a token list:
  `<digit>zw`→`\zw`, `zh`, `Q`/`H` (0.25mm). For classes that accept
  pTeX-style lengths in options.
* `\ptjcharheight`, `\ptjchardepth` — the JFM class-0 cell (pTeX's
  `\cht`/`\cdp`); in tate use these instead of measuring a glyph box.
* `\Cht \Cdp \Cwd \Cvs \Chs` — declared (as in pLaTeX/LuaTeX-ja).

### Parameters
* `\ptjsetparameter{<key>=<value>,...}`
  * `kanjiskip=<glue>`, `xkanjiskip=<glue>` — glue *specifications*, evaluated
    at each use (so `\zw`-relative values follow the size); default: the JFM's.
  * `prebreakpenalty={<char>,<int>}`, `postbreakpenalty={<char>,<int>}`
  * `jaxspmode={<char>,<inhibit|preonly|postonly|allow|0..3>}`
  * `scale=<real>`
  * `<char>` is a UTF-8 character, `` `<char> `` or a code point (`"3001`).
* `\ptjgetparameter{<key>}{<char>}` — expandable; `prebreakpenalty`,
  `postbreakpenalty`, `jaxspmode` (also `kanjiskip`, `xkanjiskip` without a
  char argument).
* `\inhibitglue` — suppress the next inter-character glue once.

### Character state (pdfTeX-specific)
* `\ptjlastnodechar` — count: code point of the last typeset Japanese
  character (−1 at paragraph/box boundaries); `\ptjupdatelastnodechar`
  applies the box-boundary rule before reading it.
* `\ptjsetlastchar{<cp>}` — make the following boundary behave as if `<cp>`
  had just been typeset (for material standing for a character).
* `\ptjresetcharstate` — paragraph-head state.
* `\ptjsavecharstate` / `\ptjrestorecharstate` / `\ptjresumeboundary` —
  bracket inserted material (e.g. note marks) without disturbing the
  surrounding boundaries; `\ptjresumeboundary` re-runs the look-ahead so the
  boundary towards the following item is emitted.
* `\ptjgetcharclass{<cp>}` — expandable JFM class of a code point.
* `\ptjgetjfmglue{<A>}{<B>}<skip>`, `\ptjgetjfmgluecp{<cpA>}{<B>}<skip>` —
  natural width of the glue between two characters.
* `\ptjforeachchar{<text>}<cmd>` — `<cmd>{<char>}` per (multi-byte) character.

### Direction (pdfTeX-specific)
* `\ptjifydir{T}{F}`, `\ptjiftdir{T}{F}` — expandable current-direction tests.
* `\ptjyokobox{<body>}`, `\ptjtatebox{<body>}` — direction box factory;
  a cross-direction body is embedded with pTeX's normalization.
  pdfTeX boxes carry no direction attribute: use the factory, not raw boxes.
* `\ptjtatechuyoko{<body>}` — tate-chu-yoko (advance pinned to one cell).
* `\ptjyokopage`, `\ptjtatepage`, `\ptjiftatepage{T}{F}` — horizontal logical
  pages inside a vertical document (pTeX's page-level `\yoko`).

### Kanji control sequences (pdfTeX-specific)
* `\ptjdefkanjics{<name>}{<replacement>}` — defines `\<name>` for a name made
  of kanji/kana and ASCII letters (e.g. `西暦true`) or one symbol (`　`).
  The name is read pTeX-style (longest run); spaces after a multi-letter name
  are skipped. Not expandable.

### Misc
* `\ptjkansuji{<integer expression>}` — pTeX `\kansuji` digit substitution
  (expandable; `\ptjkansuji\year` also works).
* `\mathmc{..}`, `\mathgt{..}` — Japanese in math (text-font boxes);
  `\ptjregistermathtextwrapper\cs` exempts a wrapper from the tate raw-box check;
  `\ptjmathinternalon`/`\ptjmathinternaloff` bracket class-internal math
  that must not be captured (e.g. dot leaders).
* `\ptjjidoribox{<width>}{<text>}`, `\ptjakigumibox{<skip>}{<text>}` — 字取り /
  空き組み (pTeX units allowed).
* `\ptjsetpagesize{<w>}{<h>}` — PDF page size with pLaTeX's `\mag` semantics.
* Japanese `\label` keys work (with nameref, hyperref, refcount, cleveref).
* pLaTeX's trim mark interface (`\iftombow`, `\maketombowbox`,
  `\@outputtombow`, …) is provided (as in LuaTeX-ja's lltjcore).
* `ruby.sty` (CJK bundle) works through an adapter (`pdftexja-ruby.sty`, loaded
  automatically); pdfTeX-ja defines no `\ruby` of its own.

### Priority-adjusted paragraphs
`\usepackage{pdftexja-adjust}` provides the environment `ptjparagraph`: one
paragraph broken by TeX and then re-spaced with LuaTeX-ja's priority
semantics (luatexja-adjust `priority=true`). Normal paragraphs use TeX's
proportional glue setting.

## Generating data

* JFM: `texlua pdftexja-jfmconv.lua --jfm=<name|file> [--name=..] [--pre=<lua>]`
  writes `ptjfm-<name>.def`. `--pre` sets the globals a parameterized JFM
  reads (jlreq: `--pre='jlreq={open_bracket_pos="nibu_tentsuki",burasage=true}'`).
  Class numbering: alchar→27, parbdd/boxbdd→90 (others moved off 27/90/93).
* Font profiles: `python3 pdftexja-mkfontprofile.py --fontset ipaex|ipa|haranoaji`
  or `--fontset custom --mincho <TTF> --gothic <TTF> --profile <file>`
  (needs fontTools and ttf2tfm).
* Kinsoku table: `texlua pdftexja-mkkinsoku.lua`.

## Build, test, install

```sh
make            # JFM data, kinsoku table (committed) + fonts/ (built from TeX Live)
make check      # regeneration diff zero, deterministic fonts, tests/run-tests.sh
make install PTJ_TEXMF=<texmf tree>
```

Requirements: TeX Live with bxcjkjatype, CJK (CJKutf8, ruby), zhmetrics,
ipaex(-type1), haranoaji, luatexja (data sources); Python 3 + fontTools for the
font build. See `doc/` for the design notes.

## Limitations

* No box direction attribute: direction is known only while a box is built
  by the factory; raw `\hbox` content in captured tate math is an error.
* Kinsoku/jaxspmode apply to multi-byte (Japanese) characters; latin-side
  `alxspmode` is not implemented.
* `\？`-style symbol commands of pTeX classes need explicit
  `\ptjdefkanjics` definitions.

License: same as jlreq (BSD 2-Clause).
