# G1 PoC: class-load-time Japanese metric measurement under pdfLaTeX

Gate **G1** (PLAN.md §7): can `jlreq`'s class-load-time measurement idioms
(`\setbox…\hbox{阿}` etc., jlreq.cls:1331–1338, 543–555) work under pdfTeX
before `\begin{document}`?

## How to run

```sh
cd poc
pdflatex g1-font-init.tex   # run twice if you want the savepos probes settled
```

- Build products (`g1-font-init.pdf`, `.log`, `.aux`) land in the CWD;
  compile in a scratch dir if you want `poc/` clean.
- The machine-readable measurement log is written by the run itself to
  **`g1-measurements.txt`** (via `\immediate\write`, so it exists even if
  the run later fails).
- Do NOT set `TEXINPUTS` — the default already includes the CWD; overriding
  it breaks kpathsea default-tree lookup (`ipaex-type1.sty not found`).

## What it does

Plain `article` + `\usepackage[ipaex-type1]{bxcjkjatype}` (**no** `whole`
option — the CJK environment is entered explicitly in the preamble, which
is what the future backend does during class init). Sections `[1]`–`[7]`
of the measurements:

1. Basic metrics: `\hbox{阿}` at `\normalsize`/`\large`/`\footnotesize`,
   mincho (`ipxm`) and gothic (`ipxg`), plus explicit
   `\fontsize{12}{12}`/`\fontsize{9}{9}` inside the preamble CJK env.
2. Six jlreq idioms replicated in the preamble: (a) `\hbox{阿}` width;
   (b) `\setbox` ht/dp of `漢字`; (c) `\dimexpr` arithmetic on measured
   dims (the `\jlreq@box@putcenter` expression); (d) the
   `\begingroup…\expandafter\endgroup\jlreq@do` group-export idiom
   (jlreq.cls:543–555, jlreq-helpers.sty:482–497); (e) the full
   jlreq.cls:1333–1338 `Cht/Cdp/Cwd/Cvs/Chs` block; (f) `\hbox to N*wd`.
3. `\zw`/`\zh` emulation (pdfTeX has no zw/zh units — only measured dims).
4. Bold: `\CJKbold` (bxcjkjatype's `CJKboldbyembolden` → PDF `Tr 2`) and
   `\bfseries` (NFSS `bx` request against c70ipxm.fd, which ssub-falls-back).
5. Latin/CJK interplay (`\mcdefault` = ipxm but Latin stays OT1/cmr).
6. State across `\begin{document}`: measured values survive; direct body JP
   text needs a fresh env — provided via `\AtBeginDocument{\begin{CJK}…}`.
7. Edge: `\makeatletter` inside the env, nested CJK envs.

## Results (measured, from g1-measurements.txt)

| Probe | Expected | Measured | Verdict |
|---|---|---|---|
| mincho @10pt | W=10.0 H=8.8 D=1.2 | **10.0 / 8.79999 / 1.2 pt** | PASS (Δ<0.0001pt) |
| mincho @14.4pt (`\large`) | linear ×1.44 → 14.4/12.672/1.728 | 12.0 / 10.56 / 1.43999 pt | PASS, linear in **font size** (CJK* scale: 10pt JFM → 12pt at `\large`) |
| mincho @8pt (`\footnotesize`) | ×0.8 → 8/7.04/0.96 | 8.0 / 7.04 / 0.95999 pt | PASS, exactly linear |
| gothic @10pt | same as mincho | 10.0 / 8.79999 / 1.2 pt | PASS |
| `\fontsize{12}{12}` / `{9}{9}` | 12pt / 9pt widths | 12.0pt / 9.0pt widths | PASS |
| `Cht/Cdp/Cwd/Cvs/Chs` | jlreq.cls:1334–1338 | 8.79999/1.2/10.0/12.0/10.0 pt | PASS |
| group-export idiom | value survives `\endgroup` | wd(漢)=10.0pt exported | PASS |
| `\hbox to 10*wd` | exactly 100pt | 100.0pt | PASS |
| zw emulation | 1zw = 10.0pt @10pt | 10.0pt | PASS |
| zh emulation | ht+dp = 10pt | 9.99998pt | PASS (rounding) |

Full JFM class-0 proportions (width=1, height=0.88, depth=0.12 from
`jfm-jlreq.lua`) are reproduced exactly by the ipaex Type1 `CJK*` metric
mechanism — **class-load-time measurement is fully feasible**.

## Key findings for the backend design

- **`\begin{CJK}` in the preamble works for measurement** (`\setbox…\hbox`
  is legal in vertical mode). Typesetting literal JP text in the preamble
  still errors (`Missing \begin{document}`) — that is a LaTeX-kernel rule,
  not a CJK problem, and it does not affect measurement idioms.
- **`\makeatother` hazard**: each CJK env may lazily load `UTF8.enc/.chr`
  and the `.fd(x)` files through `\CJK@input`, which wraps the load in
  `\makeatletter…\makeatother`. If the class body runs inside a CJK env
  under `\makeatletter`, the catcode of `@` **flips to 12 mid-env**. The
  backend must either (a) re-issue `\makeatletter` after `\begin{CJK}`
  (what this PoC does), or (b) pre-warm all CJK loads once before the
  class body runs, so no lazy load happens later. **This is a real trap
  for the M2 backend.**
- **Env bindings are local**: with bxcjkjatype's default `encapsulated` CJK
  load, the active-char bindings (`CJK@<byte>`) live only inside the env;
  after `\end{CJK}` direct JP text fails (`Unicode character … not set
  up`). Catcodes of bytes `80–FF` stay active globally. A document-wide env
  must be hooked at `\AtBeginDocument` (exactly what `whole` does).
- **`\zw`/`\zh` are NOT available as units in pdfTeX**; the backend must
  define `\jlreq@zw`/`\jlreq@zh` as real dimens measured at init
  (`\wd` of `\hbox{阿}` and `\ht+\dp` respectively) — measurement shows
  these reproduce the JFM values exactly.
- **`\bfseries` does not select a bold JP font** (c70ipxm.fd ssub-falls-back
  to m/n; there is no bold IPAex Type1). Faux-bold must go through
  `\CJKbold` (bxcjkjatype's `CJKboldbyembolden` = PDF text-rendering mode
  `Tr 2`), which does **not** change metrics (W stays 10.0pt) — good for
  jlreq's heading-metrics assumptions, but headings requesting
  `\bfseries` need an explicit `\CJKbold` in the backend's font hooks.
- **Latin is untouched**: `\mcdefault`→ipxm only affects CJK family
  selection; Latin remains OT1/cmr (JLReq normally uses the same ipxm for
  Latin in pTeX, so the M2 backend must decide explicitly what `\mcfamily`
  means for Latin — the split is clean because NFSS Latin selection is
  independent of CJK selection here).
- Scaling is linear in the **font size** (`\fontdimen6`), i.e.
  `CJK*` scaling keeps width=size, height=0.88·size, depth=0.12·size at
  every size — so a single measurement at one size can derive all sizes if
  needed, but measuring per-size is cheap and more robust.

## Limitations

- This PoC uses `bxcjkjatype`+`ipaex-type1` metrics (width=1/height=0.88/
  depth=0.12 match `jfm-jlreq.lua` class-0), **not** a generated jlreq JFM
  (that is the separate JFM PoC). Character-class-specific widths
  (e.g. 始め括弧 0.5zw) are not yet modeled — the backend will need the
  generated metric table for those.
- `\raise` (in `\jlreq@box@putcenter`) is horizontal-mode-only; in real
  jlreq it only ever expands inside typeset material, which the PoC
  reproduces with an outer `\hbox`.
- No 縦組み (vertical writing) — G4 scope.
