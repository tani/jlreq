--[[---------------------------------------------------------------------------
  make_pdftex_jfm.lua --- build-time generator of the pdfTeX backend's JFM
  data files (PLAN.md §3.3, §5 M3, §10.1).

  Production version of poc/make_pdftex_jfm.lua: the PoC proved the JFM
  loading pattern and the serialization format (see poc/README-m3.md); this
  version drops the PoC's 49-pair subset filter and emits the FULL pair
  table (all defined pairs, 402 for the current jfm-jlreq.lua) plus all
  four class-option variants as separate files.

  Usage (from the repository root; run with texlua):
    texlua make_pdftex_jfm.lua [options] [output-file]

  Options:
    --jfm=<path|name>     JFM source. Default: <script dir>/jfm-jlreq.lua,
                          then kpse.find_file("jfm-jlreq.lua").
    --open-bracket-pos=<v>
                          Replicates jlreq.cls's
                            \directlua{jlreq.open_bracket_pos = <v>}
                          before the JFM load (jlreq.cls:493). One of
                          zenkaku_tentsuki, zenkakunibu_nibu, nibu_tentsuki
                          (jfm-jlreq.lua:1141-1164 parses
                          "<danraku>_<orikaeshi>").
    --burasage=true|false Replicates \directlua{jlreq.burasage = ...}
                          (jlreq.cls:494). true appends -0.5 to end_adjust
                          of classes 6 and 7 (jfm-jlreq.lua:1167-1171).
                          NOTE: the separate pTeX "b" JFM variant
                          (make_variant_jfm.lua burasage(), which zeroes
                          .width and shifts glue) is NOT used by LuaTeX-ja
                          at run time and is therefore NOT emitted here.
    --variant=<suffix>    Output variant suffix, one of "", "b", "z", "bz"
                          (default: derived from the two options above, see
                          variant_suffix()). An explicit suffix is for tools
                          that need the file name fixed; it must be
                          CONSISTENT with the options (asserted).
    --all-variants        Ignore [output-file]; write all four variants to
                          jlreq-pdftex-jfm<suffix>.def in the directory of
                          --output / the default output path. Used by the
                          Makefile's `pdftex-jfm` target.
    --outdir=<dir>        Directory for --all-variants output (default:
                          repository root, i.e. the JFM source's directory).
    --version             print generator version and exit.

  Output (one .def per variant):
    jlreq-pdftex-jfm.def    zenkaku_tentsuki, burasage=false  (= default)
    jlreq-pdftex-jfm-b.def  zenkaku_tentsuki, burasage=true
    jlreq-pdftex-jfm-z.def  zenkakunibu_nibu, burasage=false
    jlreq-pdftex-jfm-bz.def zenkakunibu_nibu, burasage=true

  Determinism: fixed header, sorted keys everywhere, %.6f fixed-decimal
  serialization of zw-unit numbers, no timestamps, no pairs() order leaking
  into the output. Running twice produces byte-identical output; the
  Makefile's `check-pdftex-jfm` target relies on this (cmp against the
  committed files).

  Output format (same as the PoC, see poc/m3-loadtest.tex for the runtime
  loading contract):
    \def\jlreqpdf@jfm@dir{yoko}
    \def\jlreqpdf@jfm@zw{1.000000} ... \def\jlreqpdf@jfm@version{3}
    \def\jlreqpdf@jfm@kanjiskip{{0.000000}{0.250000}{0.000000}}
    \def\jlreqpdf@jfm@xkanjiskip{{0.250000}{0.250000}{0.125000}}
    \def\jlreqpdf@jfm@class@<n>{{<w>}{<h>}{<d>}{<align>}{<left>}}
    \def\jlreqpdf@jfm@endadj@<n>{{0.500000}{0.000000}}
    \def\jlreqpdf@jfm@chars@<n>{<U+xxxx> ...}
    \def\jlreqpdf@jfm@cls@<hex-n>{<class>}          (single-codepoint dispatch)
    \def\jlreqpdf@jfm@combo@<n>{...}                (multi-codepoint sequences)
    \def\jlreqpdf@jfm@ajone@<n>{{247}...}           (Adobe-Japan1 glyph ids)
    \def\jlreqpdf@jfm@pseudo@parbdd{90} etc.        (parbdd/boxbdd/alchar)
    \def\jlreqpdf@jfm@pair@<from>@<to>{{nat}{str}{shr}{ratio}{spri}{shpri}{knat}{kstr}{kshr}}
  Every macro has exactly ONE top-level body group (multi-field data uses
  inner groups): \def\cs{a}{b} would define body {a} and TYPESET {b}.
  The .def uses no expl3 features (plain \def) so it can be \input from
  plain TeX or expl3; the digit-bearing names REQUIRE the \csname form
  (plain \def\foo@0 would make the 0 a parameter-text delimiter).
-----------------------------------------------------------------------------]]

local GEN_VERSION = "1.0"

-- ------------------------- option parsing ----------------------------------
local opts = {
  jfm = nil,
  open_bracket_pos = "zenkaku_tentsuki",
  burasage = "false",
  variant = nil,
  all_variants = false,
  outdir = nil,
  output = nil,
}
local i = 1
while i <= #arg do
  local a = arg[i]
  if a == "--version" then
    print("make_pdftex_jfm.lua " .. GEN_VERSION)
    os.exit(0)
  elseif a == "--all-variants" then
    opts.all_variants = true
  elseif a:sub(1, 6) == "--jfm=" then
    opts.jfm = a:sub(7)
  elseif a:sub(1, 19) == "--open-bracket-pos=" then
    opts.open_bracket_pos = a:sub(20)
  elseif a:sub(1, 11) == "--burasage=" then
    opts.burasage = a:sub(12)
  elseif a:sub(1, 10) == "--variant=" then
    opts.variant = a:sub(11)
  elseif a:sub(1, 9) == "--outdir=" then
    opts.outdir = a:sub(10)
  elseif a:sub(1, 2) == "--" then
    io.stderr:write("make_pdftex_jfm.lua: unknown option " .. a .. "\n")
    os.exit(1)
  else
    if opts.output then
      io.stderr:write("make_pdftex_jfm.lua: too many arguments\n")
      os.exit(1)
    end
    opts.output = a
  end
  i = i + 1
end

if not (opts.burasage == "true" or opts.burasage == "false") then
  io.stderr:write("make_pdftex_jfm.lua: --burasage must be true or false\n")
  os.exit(1)
end

local VALID_OBP = { zenkaku_tentsuki = true, zenkakunibu_nibu = true, nibu_tentsuki = true }
if not VALID_OBP[opts.open_bracket_pos] then
  io.stderr:write("make_pdftex_jfm.lua: --open-bracket-pos must be one of "
    .. "zenkaku_tentsuki, zenkakunibu_nibu, nibu_tentsuki\n")
  os.exit(1)
end

-- ------------------------- JFM loading (mirrors luajfm2pl.lua /
-- make_variant_jfm.lua) -----------------------------------------------------
kpse.set_program_name("texlua", "lualatex")
require("lualibs") -- table.fastcopy etc. (same as make_variant_jfm.lua:2;
                   -- jfm-jlreq.lua:1175 needs table.fastcopy)

local scriptdir = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
local jfmfile
if opts.jfm then
  jfmfile = opts.jfm
else
  local f = io.open(scriptdir .. "/jfm-jlreq.lua", "r")
  if f then f:close(); jfmfile = scriptdir .. "/jfm-jlreq.lua" end
end
if not jfmfile then jfmfile = kpse.find_file("jfm-jlreq.lua") end
if not jfmfile or (function()
  local f = io.open(jfmfile, "r")
  if not f then return true end
  f:close(); return false
end)() then
  io.stderr:write("make_pdftex_jfm.lua: cannot find jfm-jlreq.lua\n")
  os.exit(1)
end

-- load_jfm(obp, bura): load jfm-jlreq.lua with the same jlreq globals
-- jlreq.cls sets via \directlua before the JFM load (jlreq.cls:491-494).
-- Returns the table passed to luatexja.jfont.define_jfm (jfm-jlreq.lua:1192).
local function load_jfm(obp, bura, src)
  jlreq = { open_bracket_pos = obp, burasage = bura }
  local jfm
  luatexja = { jfont = {} }
  function luatexja.jfont.define_jfm(j) jfm = j end
  dofile(src or jfmfile)
  return jfm
end

-- ------------------------- variant model ------------------------------------
-- jlreq.cls builds the pTeX/upTeX JFM name as (b?)(z?)jlreq via
-- \jlreq@jfmname@prefix (jlreq.cls:507-514): "b" if burasage, "z" if
-- open_bracket_pos is zenkakunibu_nibu, "u" first if upTeX.  The pdfTeX
-- backend has no upTeX variant, so the suffixes are "", "b", "z", "bz".
-- nibu_tentsuki is a valid class option but is NOT covered by this
-- prefix system; it differs from zenkaku_tentsuki in the loaded table
-- (90->1 glue -0.5, jfm-jlreq.lua:1161-1162), so it has no variant file
-- here and --variant must not claim it.
local VARIANTS = {
  { suffix = "",    open_bracket_pos = "zenkaku_tentsuki", burasage = false },
  { suffix = "b",   open_bracket_pos = "zenkaku_tentsuki", burasage = true },
  { suffix = "z",   open_bracket_pos = "zenkakunibu_nibu", burasage = false },
  { suffix = "bz",  open_bracket_pos = "zenkakunibu_nibu", burasage = true },
}

-- T1b (tate JFM data): the vertical variant. Source = jfm-jlreqv-pl.lua
-- (the committed tate PL table produced by make_variant_jfm.lua's tate()
-- transform: dir='tate', height=depth=0.5 per class).  The tate file is a
-- SEPARATE data domain (vertical axis), not a class-option variant, so it
-- is emitted alongside the yoko files by --all-variants and validated by
-- the same check target.  The off@<n>{raise}{shift} table (see the
-- emission site for the derivation formula) is tate-only.  The tate file
-- carries no class-option suffixes: jlreq's vertical JFM prefix system
-- (jlreq.cls:507-514) covers only the plain jlreqv for the backend's
-- current single-direction model.
local TATE_JFM = {
  file = "jfm-jlreqv-pl.lua",
  outfile = "jlreq-pdftex-jfm-tate.def",
}

local function variant_suffix(obp, bura)
  local s = ""
  if bura then s = s .. "b" end
  if obp == "zenkakunibu_nibu" then s = s .. "z" end
  return s
end

-- ------------------------- SHA256 of the JFM source ------------------------
-- sha2.digest256 returns RAW binary in TeX Live's texlua (luatexja's
-- ltluatex loadout); hex-encode it ourselves.
local function sha256_hex(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local raw = sha2.digest256(data)
  return (raw:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end

local JFM_SHA256 = sha256_hex(jfmfile)
if not JFM_SHA256 then
  io.stderr:write("make_pdftex_jfm.lua: cannot read " .. jfmfile .. "\n")
  os.exit(1)
end

-- ------------------------- per-variant generation ---------------------------

-- Fields of a JFM class table that this generator understands.  Anything
-- else in jfm-jlreq.lua must be examined and either emitted or explicitly
-- allowed here -- silently dropping data would break the "single source"
-- requirement of PLAN.md §1.3/§3.3.
local KNOWN_CLASS_FIELDS = {
  chars = true, align = true, width = true, height = true, depth = true,
  left = true, glue = true, end_adjust = true,
}
-- jfm-jlreq.lua currently sets only these; round_threshold/italic/down are
-- ltj-jfont.lua normalization defaults (values nil in this JFM) and carry no
-- data for the backend, so they are not emitted.  Assert their absence so a
-- future jfm-jlreq.lua change is caught by the check target, not the runtime.
local ABSENT_EXPECTED_CLASS_FIELDS = {
  italic = true, down = true, round_threshold = true, kern = true,
  end_stretch = true, end_shrink = true,
}

local U = unicode.utf8

local function num(x)
  -- Fixed 6-decimal format: no locale issues, no float drift in output.
  -- All JFM quantities are fractions of zw (0.25, 0.5, 1/3, 0.33333333...).
  if x == 0 then x = 0 end -- normalize -0.0 (nibu_tentsuki's add_space result)
  return string.format("%.6f", x)
end

local function hexn(cp) return string.format("%X", cp) end

local function generate_variant(variant, outfile)
  local obp, bura = variant.open_bracket_pos, variant.burasage
  local jfm = load_jfm(obp, bura, variant.jfmfile or jfmfile)
  if not jfm then
    io.stderr:write("make_pdftex_jfm.lua: JFM did not load\n")
    os.exit(1)
  end

  local out = {}
  local function emit(s) out[#out + 1] = s end

  -- Class numbers sorted numerically (0,1,2,4,...,300,301,302).
  local classes = {}
  for k in pairs(jfm) do
    if type(k) == "number" then classes[#classes + 1] = k end
  end
  table.sort(classes)

  -- --------------------- validation of the loaded JFM ---------------------
  for _, c in ipairs(classes) do
    local v = jfm[c]
    for k in pairs(v) do
      if not KNOWN_CLASS_FIELDS[k] and not ABSENT_EXPECTED_CLASS_FIELDS[k] then
        io.stderr:write(string.format(
          "make_pdftex_jfm.lua: unknown class field %q in class %d -- "
          .. "extend the generator (see KNOWN_CLASS_FIELDS)\n", tostring(k), c))
        os.exit(1)
      end
      if ABSENT_EXPECTED_CLASS_FIELDS[k] then
        io.stderr:write(string.format(
          "make_pdftex_jfm.lua: jfm-jlreq.lua now sets field %q in class %d; "
          .. "the generator does not emit it -- update generator and .def\n",
          tostring(k), c))
        os.exit(1)
      end
    end
    -- luajfm2pl.lua:127,129,133 defaults (same as the PoC; ltj-jfont.lua
    -- leaves these nil for non-tate, but the backend needs concrete values).
    if v.width == nil then v.width = 1 end
    if v.height == nil then v.height = 0.88 end
    if v.depth == nil then v.depth = 0.12 end
  end

  -- --------------------- char dispatch data -------------------------------
  -- Every entry of every class's chars list is classified:
  --   single : one Unicode codepoint  -> \jlreqpdf@jfm@cls@<hex>
  --   combo  : >= 2 codepoints (e.g. か゚ = U+304B U+309A) -> combo@<class>
  --   ajone  : "AJ1-<n>" Adobe-Japan1 glyph id (classes 191/192/193)
  --            -> ajone@<class>
  --   pseudo : 'alchar' (class 27), 'parbdd','boxbdd' (class 90)
  --            -> pseudo@<name>
  -- jfm-jlreq.lua's lists contain no ranges and no "X*" forms, so those
  -- luajfm2pl cases need no handling (verified by the coverage check).
  local single = {}   -- [cp] = class
  local combos = {}   -- [class] = { {cp,cp,...}, ... } sorted
  local ajones = {}   -- [class] = { glyphid, ... } sorted
  local pseudos = {}  -- [name] = class
  for _, c in ipairs(classes) do
    local chars = jfm[c].chars
    if chars then
      for _, ch in ipairs(chars) do
        local t = type(ch)
        if t == "string" and ch:sub(1, 4) == "AJ1-" then
          local gid = tonumber(ch:sub(5))
          if not gid then
            io.stderr:write("bad AJ1 entry: " .. ch .. "\n"); os.exit(1)
          end
          ajones[c] = ajones[c] or {}
          ajones[c][#ajones[c] + 1] = gid
        elseif t == "string" and U.len(ch) == 1 then
          local cp = U.byte(ch)
          if single[cp] then
            io.stderr:write(string.format("duplicate char U+%X in classes %d and %d\n",
              cp, single[cp], c))
            os.exit(1)
          end
          single[cp] = c
        elseif t == "string" and (ch == "alchar" or ch == "nox_alchar"
          or ch == "parbdd" or ch == "boxbdd" or ch == "jcharbdd" or ch == "glue") then
          -- pseudo char names, matched BEFORE the combo branch: these are
          -- ASCII names and U.len() >= 2 holds for them too!
          -- (jfm-jlreq.lua:985 'alchar', :1125 'parbdd'/'boxbdd';
          --  ltj-jfont.lua:74-79 also knows jcharbdd/glue/nox_alchar.)
          if pseudos[ch] then
            io.stderr:write("duplicate pseudo char " .. ch .. "\n"); os.exit(1)
          end
          pseudos[ch] = c
        elseif t == "string" and U.len(ch) >= 2 then
          local cps = {}
          for k = 1, U.len(ch) do cps[#cps + 1] = U.byte(ch, k) end
          combos[c] = combos[c] or {}
          combos[c][#combos[c] + 1] = cps
        elseif t == "number" then
          -- numeric codepoint (used by other luaTeX-ja JFMs, not jfm-jlreq)
          if single[ch] then
            io.stderr:write(string.format("duplicate char U+%X\n", ch)); os.exit(1)
          end
          single[ch] = c
        else
          io.stderr:write("unclassifiable chars entry in class " .. c .. "\n")
          os.exit(1)
        end
      end
    end
  end

  -- --------------------- emit ----------------------------------------------
  emit("%% jlreq-pdftex-jfm data (variant: "
    .. (variant.tate and "tate" or (variant.suffix == "" and "default" or variant.suffix)) .. ")")
  emit("%% generated by make_pdftex_jfm.lua " .. GEN_VERSION
    .. " -- DO NOT EDIT; regenerate with `make pdftex-jfm`")
  local srcfile = variant.jfmfile or jfmfile
  local src_sha = variant.jfmfile and sha256_hex(srcfile) or JFM_SHA256
  emit("%% source: " .. srcfile:match("[^/]*$") .. " (sha256 below)")
  emit("%% source sha256: " .. src_sha)
  emit("%% options: " .. (variant.tate and "dir=tate" or
    ("open_bracket_pos=" .. obp .. " burasage=" .. tostring(bura))))
  emit("%% deterministic: sorted keys, %.6f fixed decimals, no timestamps")
  emit("%% loader contract: \\makeatletter (catcode @ = 11) before \\input;")
  emit("%%   standard catcodes otherwise; the file does not restore them.")
  emit("%%   Retrieval of digit-bearing names needs \\csname + \\edef (see")
  emit("%%   poc/m3-loadtest.tex; LaTeX2e \\typeout does not expand \\csname).")
  emit("%% all lengths are in zw units (jfm.zw = " .. num(jfm.zw) .. ")")

  emit("\\def\\jlreqpdf@jfm@dir{" .. tostring(jfm.dir) .. "}")
  emit("\\def\\jlreqpdf@jfm@zw{" .. num(jfm.zw) .. "}")
  emit("\\def\\jlreqpdf@jfm@zh{" .. num(jfm.zh) .. "}")
  emit("\\def\\jlreqpdf@jfm@version{" .. tostring(jfm.version or 1) .. "}")
  emit("\\def\\jlreqpdf@jfm@variant{" .. (variant.tate and "tate" or variant.suffix) .. "}")
  emit("\\def\\jlreqpdf@jfm@kanjiskip{{" .. num(jfm.kanjiskip[1]) .. "}{"
    .. num(jfm.kanjiskip[2]) .. "}{" .. num(jfm.kanjiskip[3]) .. "}}")
  emit("\\def\\jlreqpdf@jfm@xkanjiskip{{" .. num(jfm.xkanjiskip[1]) .. "}{"
    .. num(jfm.xkanjiskip[2]) .. "}{" .. num(jfm.xkanjiskip[3]) .. "}}")
  emit("")
  -- defop(name, body): emit a \def whose macro NAME may contain digits
  -- (class ids, codepoints). Plain \def\foo@0{...} would make the "0" a
  -- parameter-text delimiter (TeX csname letters only), so ALL definitions
  -- go through \csname (the standard expl3 \cs_new:cpn equivalent).
  local function defop(name, body)
    emit("\\expandafter\\def\\csname " .. name .. "\\endcsname{" .. body .. "}")
  end

  -- per-class metrics + end_adjust + char lists (metrics for ALL classes)
  emit("% ---- class metrics: \\jlreqpdf@jfm@class@<n>{{w}{h}{d}{align}{left}}")
  emit("% (all defs go through \\csname: names contain digits; plain")
  emit("% \\def\\foo@0{..} would treat 0 as parameter-text delimiter)")
  for _, c in ipairs(classes) do
    local v = jfm[c]
    local align = v.align or "left" -- ltj-jfont.lua:96 default
    local left = v.left or 0       -- ltj-jfont.lua:104 default
    defop(string.format("jlreqpdf@jfm@class@%d", c),
      string.format("{%s}{%s}{%s}{%s}{%s}",
        num(v.width), num(v.height), num(v.depth), align, num(left)))
  end
  emit("")
  emit("% ---- end_adjust (ltj-adjust.lua insert_lineend_kern; the LuaTeX-ja")
  emit("% ---- line-end adjustment steps); sorted ascending as in ltj-jfont.")
  for _, c in ipairs(classes) do
    local ea = jfm[c].end_adjust
    if ea then
      local copy = {}
      for k = 1, #ea do copy[k] = ea[k] end
      table.sort(copy) -- ltj-jfont.lua:123 sorts too
      local body = {}
      for _, v in ipairs(copy) do body[#body + 1] = "{" .. num(v) .. "}" end
      defop(string.format("jlreqpdf@jfm@endadj@%d", c), table.concat(body))
    end
  end
  emit("")
  -- T1b: tate-only punctuation offset table.  off@<n>{raise}{shift} carries
  -- the RAW metric values (pt) for placing rotated punctuation ink at the
  -- JLREQ target corner; the consumer maps them through its measured
  -- slopes (dx/draise ~ +1.23, dy/dkern ~ +1.43 against +90 glyph rotation).
  --
  -- DERIVATION (automated; computed by poc/tate_off.lua from the IPAex
  -- Type1 charstring ink bboxes extracted by poc/extbbox3.py — no
  -- hand-tuned raster values):
  --   V4 shipout-rotation axes: reading_x (right) = sheet_y (raise moves
  --   it), reading_y (down) = sheet_x (kern moves it).  For a yoko ink
  --   bbox (x0,x1,y0,y1) in 1/1000-em units, the CW-rotated ink occupies
  --   sheet_x in [-y1,-y0], sheet_y in [x0,x1].  With the box normalized
  --   to wd=1zw, ht=ght(0.88zw), dp=0:
  --     raise(pt) = (0.88 - ink_x1/1000) * 10   [ink right edge -> cell right]
  --     shift(pt) = -(ink_y1/1000) * 10         [ink top edge -> cell top]
  --   using the class's representative glyph (the yoko glyph actually
  --   shipped in the Type1 subset): 1:「=uni300C, 2:」=uni300D,
  --   6:。=uni3002, 7:、=uni3001, 11:っ=uni3063, 161:｣=uniFF63 (FF plane).
  --   Classes outside {1,2,6,7,11,161} are 0/0 (full-width glyphs need no
  --   corner offset; rotation-correct by construction).
  if variant.tate and variant.offtable then
    emit("% ---- tate punctuation offsets: \\off@<n>{raise}{shift}")
    emit("% ---- (pt; raise = reading-frame vertical, shift = horizontal;")
    emit("% ---- derivation: see the comment above and poc/tate_off.lua)")
    for _, c in ipairs(classes) do
      local o = variant.offtable[c] or { raise = "0.000000", shift = "0.000000" }
      defop(string.format("jlreqpdf@jfm@off@%d", c),
        string.format("{%s}{%s}", o.raise, o.shift))
    end
    emit("")
  end
  emit("% ---- full char lists per class (space separated U+XXXX hex, for")
  emit("% ---- debugging/verification; the runtime dispatch is cls@<hex> below)")
  for _, c in ipairs(classes) do
    local chars = jfm[c].chars
    if chars and #chars > 0 then
      local hexes = {}
      for _, ch in ipairs(chars) do
        if type(ch) == "string" and ch:sub(1, 4) == "AJ1-" then
          hexes[#hexes + 1] = ch
        else
          hexes[#hexes + 1] = "U+" .. hexn(U.byte(ch, 1) or 0)
        end
      end
      defop(string.format("jlreqpdf@jfm@chars@%d", c), table.concat(hexes, " "))
    end
  end
  emit("")

  -- char->class dispatch, sorted by codepoint (deterministic)
  emit("% ---- char -> class dispatch (single-codepoint chars), sorted by cp")
  local cps = {}
  for cp in pairs(single) do cps[#cps + 1] = cp end
  table.sort(cps)
  for _, cp in ipairs(cps) do
    defop(string.format("jlreqpdf@jfm@cls@%s", hexn(cp)), tostring(single[cp]))
  end
  emit("")

  -- combos / ajone / pseudo
  emit("% ---- multi-codepoint sequences (combos) per class, e.g. U+304B U+309A")
  for _, c in ipairs(classes) do
    local list = combos[c]
    if list then
      table.sort(list, function(a, b)
        for k = 1, math.max(#a, #b) do
          local x, y = a[k] or -1, b[k] or -1
          if x ~= y then return x < y end
        end
        return false
      end)
      local items = {}
      for _, seq in ipairs(list) do
        local hs = {}
        for _, cp in ipairs(seq) do hs[#hs + 1] = "U+" .. hexn(cp) end
        items[#items + 1] = table.concat(hs, ",")
      end
      defop(string.format("jlreqpdf@jfm@combo@%d", c), table.concat(items, " "))
    end
  end
  emit("% ---- Adobe-Japan1 glyph ids (classes 191/192/193; pTeX/VF-only feature)")
  for _, c in ipairs(classes) do
    local list = ajones[c]
    if list then
      table.sort(list)
      local items = {}
      for _, gid in ipairs(list) do items[#items + 1] = "{" .. tostring(gid) .. "}" end
      defop(string.format("jlreqpdf@jfm@ajone@%d", c), table.concat(items))
    end
  end
  emit("% ---- pseudo chars (not codepoints): alchar=latin run, parbdd/boxbdd=bounds")
  local pseudonames = {}
  for name in pairs(pseudos) do pseudonames[#pseudonames + 1] = name end
  table.sort(pseudonames)
  for _, name in ipairs(pseudonames) do
    defop(string.format("jlreqpdf@jfm@pseudo@%s", name), tostring(pseudos[name]))
  end
  emit("")

  -- pair glue: FULL table (every defined pair of the loaded JFM)
  emit("% ---- pair glue: \\pair@<from>@<to>{nat}{stretch}{shrink}{ratio}")
  emit("% ----   {stretch-priority}{shrink-priority}{kanjiskip-natural-flag}")
  emit("% ----   {kanjiskip-stretch}{kanjiskip-shrink}")
  emit("% ---- full table: every defined pair of jfm-jlreq.lua (402 currently)")
  local pair_count = 0
  local pair_keys = {} -- [f] = sorted list of t
  for _, f in ipairs(classes) do
    local tos = {}
    for t in pairs(jfm[f].glue or {}) do tos[#tos + 1] = t end
    table.sort(tos)
    pair_keys[f] = tos
  end
  for _, f in ipairs(classes) do
    for _, t in ipairs(pair_keys[f]) do
      local g = jfm[f].glue[t]
      local ratio = g.ratio
      if ratio == nil then ratio = 0.5 end -- ltj-jfont.lua:141 default
      local pri = g.priority or { 0, 0 }   -- ltj-jfont.lua:144
      local knat = g.kanjiskip_natural or 0 -- ltj-jfont.lua:157 norm_val
      local kstr = g.kanjiskip_stretch or 0
      local kshr = g.kanjiskip_shrink or 0
      -- ペアデータはマクロ呼び出し形式で出力する（実行時に9引数へ直接分解される。
      -- 生グループ {{f1}...{f9}} 形式だと \def 本体の二重括弧が
      -- 引数取得の再括弧化で分割不能になるため）。
      emit(string.format(
        "\\expandafter\\def\\csname jlreqpdf@jfm@pair@%d@%d\\endcsname{\\jlreqpdf@pairfields{%s}{%s}{%s}{%s}{%d}{%d}{%d}{%d}{%d}}",
        f, t, num(g[1]), num(g[2]), num(g[3]), num(ratio),
        pri[1], pri[2], knat, kstr, kshr))
      pair_count = pair_count + 1
    end
  end

  emit("")
  emit("%% end of jlreq-pdftex-jfm"
    .. (variant.tate and "-tate"
        or (variant.suffix == "" and "" or ("-" .. variant.suffix))))

  local text = table.concat(out, "\n") .. "\n"
  local fp, err = io.open(outfile, "wb")
  if not fp then
    io.stderr:write("cannot open output " .. outfile .. ": " .. tostring(err) .. "\n")
    os.exit(1)
  end
  fp:write(text)
  fp:close()

  local nchars = 0
  for _ in pairs(single) do nchars = nchars + 1 end
  local ncombo = 0
  for _, l in pairs(combos) do ncombo = ncombo + #l end
  local najone = 0
  for _, l in pairs(ajones) do najone = najone + #l end
  local npseudo = #pseudonames
  return {
    text = text, classes = #classes, chars = nchars, combos = ncombo,
    ajones = najone, pseudos = npseudo, pairs = pair_count, bytes = #text,
  }
end

-- ------------------------- T1b tate off table -------------------------------
-- The off@ table is computed by poc/tate_off.lua (IPAex Type1 charstring
-- bboxes via poc/extbbox3.py).  This loader consumes poc/tate-off.lua;
-- it is generated by `make pdftex-jfm` before the main generator runs
-- (see the Makefile's pdftex-jfm rule).
local function load_off_table(dir)
  local f = io.open(dir .. "/tate-off.lua", "r")
  if not f then
    io.stderr:write("make_pdftex_jfm.lua: tate off-table missing: run "
      .. "texlua poc/tate_off.lua in the repository root first (or the "
      .. "Makefile target does it)\n")
    os.exit(1)
  end
  local data = f:read("*a"); f:close()
  local t = {}
  for c, ra, sh in data:gmatch("%[(%d+)%]%s*=%s*%{[^}]*raise%s*=%s*(-?[%d.]+)[^}]*shift%s*=%s*(-?[%d.]+)") do
    t[tonumber(c)] = { raise = ra, shift = sh }
  end
  return t
end

-- ------------------------- main dispatch ------------------------------------
local default_outname = "jlreq-pdftex-jfm%s.def"

if opts.all_variants then
  local outdir = opts.outdir
  if not outdir then
    -- default: next to the JFM source (repository root when run via make)
    outdir = jfmfile:match("^(.*)/[^/]*$") or "."
  end
  local ok = true
  -- T1b: the tate off-table must be computed first (poc/tate_off.lua runs
  -- in the output directory, where extbbox3.py's json snapshots live).
  local tate_off = load_off_table(outdir == "." and "." or outdir)
  local tate_variant = {
    tate = true, jfmfile = scriptdir .. "/" .. TATE_JFM.file,
    offtable = tate_off,
  }
  do
    local outfile = string.format("%s/%s",
      (outdir == "." and "" or outdir), TATE_JFM.outfile)
    if outdir == "." then outfile = TATE_JFM.outfile end
    local r = generate_variant(tate_variant, outfile)
    io.stderr:write(string.format(
      [[make_pdftex_jfm.lua %s: wrote %s
  classes: %d  chars: %d (%d single + %d combos + %d AJ1 + %d pseudo)
  pairs: %d  bytes: %d
  options: dir=tate source=%s]],
      GEN_VERSION, outfile, r.classes,
      r.chars + r.combos + r.ajones + r.pseudos,
      r.chars, r.combos, r.ajones, r.pseudos, r.pairs, r.bytes,
      TATE_JFM.file))
    io.stderr:write("\n")
    if r.pairs == 0 then ok = false end
  end
  for _, v in ipairs(VARIANTS) do
    local outfile = string.format("%s/jlreq-pdftex-jfm%s.def",
      (outdir == "." and "" or outdir), v.suffix == "" and "" or ("-" .. v.suffix))
    if outdir == "." then
      outfile = string.format("jlreq-pdftex-jfm%s.def",
        v.suffix == "" and "" or ("-" .. v.suffix))
    end
    local r = generate_variant(v, outfile)
    io.stderr:write(string.format(
      [[make_pdftex_jfm.lua %s: wrote %s
  classes: %d  chars: %d (%d single + %d combos + %d AJ1 + %d pseudo)
  pairs: %d  bytes: %d
  options: open_bracket_pos=%s burasage=%s]],
      GEN_VERSION, outfile, r.classes, r.chars + r.combos + r.ajones + r.pseudos,
      r.chars, r.combos, r.ajones, r.pseudos, r.pairs, r.bytes,
      v.open_bracket_pos, tostring(v.burasage)))
    io.stderr:write("\n")
    if r.pairs == 0 then ok = false end
  end
  if not ok then os.exit(1) end
  os.exit(0)
end

-- single-variant mode (default: the two options decide the variant)
local bura = (opts.burasage == "true")
local suffix = variant_suffix(opts.open_bracket_pos, bura)
if opts.variant then
  if opts.variant ~= suffix then
    io.stderr:write(string.format(
      "make_pdftex_jfm.lua: --variant=%s contradicts the options "
      .. "(--open-bracket-pos=%s --burasage=%s imply variant %q)\n",
      opts.variant, opts.open_bracket_pos, opts.burasage, suffix))
    os.exit(1)
  end
end
if opts.open_bracket_pos == "nibu_tentsuki" then
  io.stderr:write(
    "make_pdftex_jfm.lua: nibu_tentsuki is a valid jlreq class option but has "
    .. "no variant file (jlreq.cls's JFM prefix system, jlreq.cls:507-514, "
    .. "covers only zenkakunibu_nibu for the z prefix; nibu_tentsuki changes "
    .. "the 90->1 pair and the backend does not load it yet). "
    .. "Use --open-bracket-pos=zenkaku_tentsuki or zenkakunibu_nibu.\n")
  os.exit(1)
end
local variant = nil
for _, v in ipairs(VARIANTS) do
  if v.suffix == suffix then variant = v end
end
if not variant then
  io.stderr:write("make_pdftex_jfm.lua: internal: no variant for suffix " .. suffix .. "\n")
  os.exit(1)
end
local outfile = opts.output or string.format(default_outname,
  suffix == "" and "" or ("-" .. suffix))
local r = generate_variant(variant, outfile)
io.stderr:write(string.format(
  [[make_pdftex_jfm.lua %s: wrote %s
  classes: %d  chars: %d (%d single + %d combos + %d AJ1 + %d pseudo)
  pairs: %d  bytes: %d
  options: open_bracket_pos=%s burasage=%s]],
  GEN_VERSION, outfile, r.classes, r.chars + r.combos + r.ajones + r.pseudos,
  r.chars, r.combos, r.ajones, r.pseudos, r.pairs, r.bytes,
  opts.open_bracket_pos, opts.burasage))
io.stderr:write("\n")
if r.pairs == 0 then os.exit(1) end
