-- HISTORICAL PoC ARTIFACT (superseded -- do not use or update).
-- Superseded by the production generator make_pdftex_jfm.lua at the
-- repository root (GEN_VERSION 2.0: 12 variants, yoko+tate, manifest era).
-- Kept only as the experiment record referenced from docs/ and README.
--[[---------------------------------------------------------------------------
  make_pdftex_jfm.lua --- PoC generator for M3 (PLAN.md §3.3, §12-4)

  Reads the single JFM source jfm-jlreq.lua (the same file that serves
  pTeX/upTeX via luajfm2pl.lua and LuaTeX-ja at run time) and emits a
  deterministic, machine-loadable TeX data file (.def) for the future
  pdfTeX expl3 backend (jlreq-pdftex.sty).

  Usage:
    texlua poc/make_pdftex_jfm.lua [options] [output-file]

  Options:
    --jfm=<path|name>     JFM source. Default: ../jfm-jlreq.lua relative to
                          this script, then kpse.find_file("jfm-jlreq.lua").
    --open-bracket-pos=<v>
                          Replicates jlreq.cls's
                            \directlua{jlreq.open_bracket_pos = <v>}
                          before JFM load (jlreq.cls:493). One of:
                            zenkaku_tentsuki (default in jlreq.cls)
                            zenkakunibu_nibu, nibu_tentsuki
                          (jfm-jlreq.lua:1141-1164 parses
                          "<danraku>_<orikaeshi>" and only
                          orikaeshi=="nibu" and danraku=="zenkakunibu"/
                          "nibu" have an effect.)
    --burasage=true|false Replicates \directlua{jlreq.burasage = ...}
                          (jlreq.cls:494). true appends -0.5 to end_adjust
                          of classes 6 and 7 (jfm-jlreq.lua:1167-1171).
                          NOTE: the separate pTeX "b" variant
                          (make_variant_jfm.lua burasage(), which zeroes
                          .width and shifts glue) is NOT used by LuaTeX-ja
                          at run time and is therefore NOT emitted here.
    --version             print generator version and exit.

  Determinism: fixed header, sorted keys everywhere, %.6f fixed-decimal
  serialization of zw-unit numbers, no timestamps, no pairs() order leaking
  into the output. Running twice produces byte-identical output.

  Output format (documented in poc/README-m3.md):
    \def\jlreqpdf@jfm@dir{yoko}
    \def\jlreqpdf@jfm@zw{1.000000} ... \def\jlreqpdf@jfm@version{3}
    \def\jlreqpdf@jfm@kanjiskip{{0.000000}{0.250000}{0.000000}}
    \def\jlreqpdf@jfm@xkanjiskip{{0.250000}{0.250000}{0.125000}}
    \def\jlreqpdf@jfm@class@<n>{{<w>}{<h>}{<d>}{<align>}}
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
  plain TeX or expl3; @ must be catcode 11 (loader's job, one \makeatletter).
-----------------------------------------------------------------------------]]

local GEN_VERSION = "0.1-poc"

-- ------------------------- option parsing ----------------------------------
local opts = {
  jfm = nil,
  open_bracket_pos = "zenkaku_tentsuki",
  burasage = "false",
  output = nil,
}
local i = 1
while i <= #arg do
  local a = arg[i]
  if a == "--version" then
    print("make_pdftex_jfm.lua " .. GEN_VERSION)
    os.exit(0)
  elseif a:sub(1, 6) == "--jfm=" then
    opts.jfm = a:sub(7)
  elseif a:sub(1, 19) == "--open-bracket-pos=" then
    opts.open_bracket_pos = a:sub(20)
  elseif a:sub(1, 11) == "--burasage=" then
    opts.burasage = a:sub(12)
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

-- ------------------------- JFM loading (mirrors luajfm2pl.lua /
-- make_variant_jfm.lua) -----------------------------------------------------
kpse.set_program_name("texlua", "lualatex")
require("lualibs") -- table.fastcopy etc. (same as make_variant_jfm.lua:2;
                   -- jfm-jlreq.lua:1175 needs table.fastcopy)

-- Resolve JFM source: explicit, then ../<name>.lua next to this script,
-- then kpse.find_file.
local jfmfile
if opts.jfm then
  jfmfile = opts.jfm
else
  local here = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
  local try = here .. "/../jfm-jlreq.lua"
  local f = io.open(try, "r")
  if f then f:close(); jfmfile = try
  else
    jfmfile = kpse.find_file("jfm-jlreq.lua")
  end
end
if not jfmfile or (function()
  local f = io.open(jfmfile, "r")
  if not f then return true end
  f:close(); return false
end)() then
  io.stderr:write("make_pdftex_jfm.lua: cannot find jfm-jlreq.lua\n")
  os.exit(1)
end

-- jlreq global, read by jfm-jlreq.lua:1141-1172. jlreq.cls sets it via
-- \directlua BEFORE the JFM is loaded (jlreq.cls:493-494); we replicate.
jlreq = {
  open_bracket_pos = opts.open_bracket_pos,
  burasage = (opts.burasage == "true"),
}

local jfm
luatexja = { jfont = {} }
function luatexja.jfont.define_jfm(j) jfm = j end
dofile(jfmfile)

if not jfm then
  io.stderr:write("make_pdftex_jfm.lua: JFM did not load\n")
  os.exit(1)
end

-- ------------------------- deterministic serialization helpers -------------
local U = unicode.utf8
local out = {}
local function emit(s) out[#out + 1] = s end

local function num(x)
  -- Fixed 6-decimal format: no locale issues, no float drift in output.
  -- All JFM quantities are fractions of zw with exact binary/fifth values
  -- (0.25, 0.5, 0.75, 0.88, 0.12, 1/3->0.33333333, 0.33333333 ratios).
  return string.format("%.6f", x)
end

local function hexn(cp) return string.format("%X", cp) end

-- Class numbers sorted numerically (0,1,2,4,...,300,301,302).
local classes = {}
for k in pairs(jfm) do
  if type(k) == "number" then classes[#classes + 1] = k end
end
table.sort(classes)

-- ------------------------- validation of the loaded JFM -------------------
-- (ltj-jfont.lua define_jfm does the same normalization; we keep the raw
-- table but normalize the few fields the backend consumes.)
for _, c in ipairs(classes) do
  local v = jfm[c]
  if v.width == nil then v.width = 1 end       -- luajfm2pl.lua:127
  if v.height == nil then v.height = 0.88 end  -- luajfm2pl.lua:129
  if v.depth == nil then v.depth = 0.12 end    -- luajfm2pl.lua:133
end

-- ------------------------- char dispatch data ------------------------------
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

-- ------------------------- pair subset (PoC size reduction) ---------------
-- PoC: full char->class dispatch for ALL classes (the core data), but pair
-- glue only for the closure {0,1,2,4,5,6,7} x {0,1,2,4,5,6,7} (plus the
-- 90->1 pair that open_bracket_pos variants modify). The set is computed
-- from the loaded table (defined pairs only), not hardcoded numbers.
local PAIR_CLASSES = { 0, 1, 2, 4, 5, 6, 7 }
local pair_from, pair_to = {}, {}
for _, c in ipairs(PAIR_CLASSES) do pair_from[c] = true; pair_to[c] = true end

-- ------------------------- emit --------------------------------------------
emit("%% jlreq-pdftex-jfm sample data (PoC, M3)")
emit("%% generated by make_pdftex_jfm.lua " .. GEN_VERSION)
emit("%% source: " .. jfmfile)
emit("%% options: open_bracket_pos=" .. opts.open_bracket_pos
     .. " burasage=" .. opts.burasage)
emit("%% deterministic: sorted keys, %.6f fixed decimals, no timestamps")
emit("%% loader contract: \\makeatletter (catcode @ = 11) before \\input")
emit("%% all lengths are in zw units (jfm.zw = " .. num(jfm.zw) .. ")")

emit("\\def\\jlreqpdf@jfm@dir{" .. tostring(jfm.dir) .. "}")
emit("\\def\\jlreqpdf@jfm@zw{" .. num(jfm.zw) .. "}")
emit("\\def\\jlreqpdf@jfm@zh{" .. num(jfm.zh) .. "}")
emit("\\def\\jlreqpdf@jfm@version{" .. tostring(jfm.version or 1) .. "}")
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
emit("% ---- class metrics: \\jlreqpdf@jfm@class@<n>{{w}{h}{d}{align}}")
emit("% (all defs go through \\csname: names contain digits; plain")
emit("% \\def\\foo@0{..} would treat 0 as parameter-text delimiter)")
for _, c in ipairs(classes) do
  local v = jfm[c]
  local align = v.align or "left" -- ltj-jfont.lua:96 default
  defop(string.format("jlreqpdf@jfm@class@%d", c),
    string.format("{%s}{%s}{%s}{%s}",
      num(v.width), num(v.height), num(v.depth), align))
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
emit("% ---- full char lists per class (space separated U+XXXX hex, for")
emit("% ---- debugging/verification; the runtime dispatch is cls@<hex> below)")
for _, c in ipairs(classes) do
  local chars = jfm[c].chars
  if chars and #chars > 0 then
    local hexes = {}
    for _, ch in ipairs(chars) do
      hexes[#hexes + 1] = "U+" .. hexn(U.byte(ch, 1) or 0)
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

-- pair glue
emit("% ---- pair glue: \\pair@<from>@<to>{nat}{stretch}{shrink}{ratio}")
emit("% ----   {stretch-priority}{shrink-priority}{kanjiskip-natural-flag}")
emit("% ---- PoC subset: from,to in {0,1,2,4,5,6,7}; 90->1 kept (open-bracket")
emit("% ---- variant touches it). Full table would be 402 pairs (25x25 grid")
emit("% ---- minus undefined cells); see README-m3.md.")
local pair_count = 0
local function emit_pair(f, t)
  local g = jfm[f].glue and jfm[f].glue[t]
  if not g then return end
  local ratio = g.ratio
  if ratio == nil then ratio = 0.5 end -- ltj-jfont.lua:141 default
  local pri = g.priority or { 0, 0 }   -- ltj-jfont.lua:144
  local knat = g.kanjiskip_natural or 0 -- ltj-jfont.lua:157 norm_val
  local kstr = g.kanjiskip_stretch or 0
  local kshr = g.kanjiskip_shrink or 0
  defop(string.format("jlreqpdf@jfm@pair@%d@%d", f, t),
    string.format("{%s}{%s}{%s}{%s}{%d}{%d}{%d}{%d}{%d}",
      num(g[1]), num(g[2]), num(g[3]), num(ratio),
      pri[1], pri[2], knat, kstr, kshr))
  pair_count = pair_count + 1
end
for _, f in ipairs(classes) do
  if pair_from[f] then
    local tos = {}
    for t in pairs(jfm[f].glue or {}) do
      if pair_to[t] then tos[#tos + 1] = t end
    end
    table.sort(tos)
    for _, t in ipairs(tos) do emit_pair(f, t) end
  end
end
emit_pair(90, 1) -- always emitted (variant-dependent; jfm-jlreq.lua:1124-1129)

emit("")
emit("%% end of jlreq-pdftex-jfm sample")

-- ------------------------- write ------------------------------------------
local text = table.concat(out, "\n") .. "\n"
local outfile = opts.output or "jlreq-pdftex-jfm-sample.def"
local fp, err = io.open(outfile, "wb")
if not fp then
  io.stderr:write("cannot open output: " .. tostring(err) .. "\n")
  os.exit(1)
end
fp:write(text)
fp:close()

-- ------------------------- summary (stderr) -------------------------------
local nclasses = #classes
local nchars = 0
for _ in pairs(single) do nchars = nchars + 1 end
local ncombo = 0
for _, l in pairs(combos) do ncombo = ncombo + #l end
local najone = 0
for _, l in pairs(ajones) do najone = najone + #l end
local npseudo = #pseudonames
local total_possible_pairs = 0
for _, f in ipairs(classes) do
  for _, t in ipairs(classes) do
    if jfm[f].glue and jfm[f].glue[t] then total_possible_pairs = total_possible_pairs + 1 end
  end
end
local size = #text
io.stderr:write(string.format(
  [[make_pdftex_jfm.lua %s: wrote %s
  classes=%d  single-char dispatch=%d  combos=%d  AJ1 glyphs=%d  pseudo=%d
  pairs emitted=%d (subset) of %d defined in JFM  bytes=%d
  options: open_bracket_pos=%s burasage=%s]],
  GEN_VERSION, outfile, nclasses, nchars, ncombo, najone, npseudo,
  pair_count, total_possible_pairs, size,
  opts.open_bracket_pos, opts.burasage))
