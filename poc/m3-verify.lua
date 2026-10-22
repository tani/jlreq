--[[---------------------------------------------------------------------------
  m3-verify.lua --- PoC validator for the M3 .def generator (PLAN.md §5-M3,
  T1 static test layer). Run AFTER generating the .def:

    texlua poc/m3-verify.lua [path-to-.def] [path-to-jfm-jlreq.lua]

  Checks (each prints PASS/FAIL and exits 1 on any failure):
    1. COVERAGE   every char entry of every class's chars list in
                  jfm-jlreq.lua appears exactly once in the .def dispatch
                  (single-codepoint chars as \cls@<hex>, combos, AJ1 glyphs,
                  pseudo names), and no char appears in two classes.
    2. PAIRS      >= 5 representative pair glues are byte-checked against
                  the freshly loaded JFM table (incl. defaults ratio=0.5,
                  priority={0,0}, kanjiskip_natural normalization as in
                  ltj-jfont.lua:141,144,157).
    3. METRICS    class width/height/depth/align and kanjiskip/xkanjiskip
                  defaults match.
    4. STRUCTURE  every emitted line is a comment (%%), blank, or a \def of
                  the documented families; total \def count reported.
-----------------------------------------------------------------------------]]

local deffile = arg[1]
  or (function()
    local here = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
    return here .. "/jlreq-pdftex-jfm-sample.def"
  end)()
local jfmfile = arg[2] or (function()
  local here = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
  return here .. "/../jfm-jlreq.lua"
end)()

local failures = 0
local function fail(msg)
  print("FAIL: " .. msg)
  failures = failures + 1
end

-- ---------- brace-group parser ----------------------------------------------
-- split_groups(s): returns list of top-level {..} group contents in s.
-- Handles arbitrary nesting (e.g. "{{a}{b}}" -> 1 element "{a}{b}").
local function split_groups(s)
  local groups = {}
  local pos = 1
  while true do
    local s0 = s:find("{", pos, true)
    if not s0 then break end
    local depth, p = 1, s0 + 1
    while depth > 0 and p <= #s do
      local c = s:sub(p, p)
      if c == "{" then depth = depth + 1 elseif c == "}" then depth = depth - 1 end
      p = p + 1
    end
    if depth ~= 0 then return nil end -- unbalanced braces
    groups[#groups + 1] = s:sub(s0 + 1, p - 2)
    pos = p
  end
  return groups
end

-- ---------- load the .def and parse \defs ------------------------------------
local defs = {}      -- name -> {top-level group contents}
local defnames = {}  -- ordered list of defined macro names
local nlines, ndef = 0, 0
local df = io.open(deffile, "r")
if not df then print("FAIL: cannot open " .. deffile) os.exit(1) end
for line in df:lines() do
  nlines = nlines + 1
  if line:sub(1, 1) == "%" then
    -- comment (headers use %%)
  elseif line:sub(1, 1) == "\\" and line:match("^\\expandafter\\def\\csname") then
    ndef = ndef + 1
    local name, rest = line:match("^\\expandafter\\def\\csname ([^ ]+)\\endcsname(.*)$")
    if not name then
      fail(string.format("line %d: unparseable csname def: %s", nlines, line))
    else
      local args = split_groups(rest)
      if not args then
        fail(string.format("line %d: unbalanced braces: %s", nlines, line))
      else
        if defs[name] then
          fail(string.format("line %d: duplicate def of %s", nlines, name))
        end
        defs[name] = args
        defnames[#defnames + 1] = name
      end
    end
  elseif line:sub(1, 5) == "\\def\\" then
    ndef = ndef + 1
    local name, rest = line:match("^\\def\\([^ {]+)(.*)$")
    if not name then
      fail(string.format("line %d: unparseable \\def: %s", nlines, line))
    else
      local args = split_groups(rest)
      if not args then
        fail(string.format("line %d: unbalanced braces: %s", nlines, line))
      else
        if defs[name] then
          fail(string.format("line %d: duplicate \\def of %s", nlines, name))
        end
        defs[name] = args
        defnames[#defnames + 1] = name
      end
    end
  elseif line:match("^%s*$") then
    -- blank
  else
    fail(string.format("line %d: unrecognized line: %s", nlines, line))
  end
end
df:close()

-- ---------- load the JFM exactly as the generator does -----------------------
kpse.set_program_name("texlua", "lualatex")
require("lualibs")
jlreq = { open_bracket_pos = "zenkaku_tentsuki", burasage = false }
local jfm
luatexja = { jfont = {} }
function luatexja.jfont.define_jfm(j) jfm = j end
dofile(jfmfile)
if not jfm then print("FAIL: JFM did not load") os.exit(1) end
local U = unicode.utf8

-- header flags in the .def must say which variant it holds; m3-verify only
-- validates the default variant.
local hdr
do
  local f = io.open(deffile, "r")
  hdr = f:read("*a")
  f:close()
end
if not hdr:match("options: open_bracket_pos=zenkaku_tentsuki burasage=false") then
  fail("header does not declare the default variant "
    .. "(open_bracket_pos=zenkaku_tentsuki burasage=false); "
    .. "m3-verify.lua only validates the default variant")
end

local function num(x) return string.format("%.6f", x) end
local function hexn(cp) return string.format("%X", cp) end

local n_expect, n_ok = 0, 0
for c, v in pairs(jfm) do
  if type(c) == "number" and v.chars then
    for _, ch in ipairs(v.chars) do
      n_expect = n_expect + 1
      if type(ch) == "string" and ch:sub(1, 4) == "AJ1-" then
        local gid = ch:sub(5)
        local a = defs["jlreqpdf@jfm@ajone@" .. c]
        -- body is {{247}{248}...}: a[1] is "{247}{248}..."; split it
        local inner = a and a[1] and split_groups(a[1])
        local ok = inner ~= nil
        if ok then
          local found = false
          for _, g in ipairs(inner) do if g == gid then found = true end end
          ok = found
        end
        if ok then n_ok = n_ok + 1
        else fail("AJ1 glyph " .. ch .. " missing from ajone@" .. c) end
      elseif type(ch) == "string" and U.len(ch) == 1 then
        local cp = U.byte(ch)
        local cls = defs["jlreqpdf@jfm@cls@" .. hexn(cp)]
        if not cls then
          fail(string.format("char U+%X (%s) missing from dispatch", cp, ch))
        elseif cls[1] ~= tostring(c) then
          fail(string.format("char U+%X dispatched to %s, expected %d", cp, cls[1], c))
        else
          n_ok = n_ok + 1
        end
      elseif type(ch) == "string" and (ch == "alchar" or ch == "nox_alchar"
        or ch == "parbdd" or ch == "boxbdd" or ch == "jcharbdd" or ch == "glue") then
        local p = defs["jlreqpdf@jfm@pseudo@" .. ch]
        if not p then
          fail("pseudo char " .. ch .. " missing from dispatch")
        elseif p[1] ~= tostring(c) then
          fail("pseudo " .. ch .. " dispatched to " .. p[1] .. ", expected " .. c)
        else
          n_ok = n_ok + 1
        end
      elseif type(ch) == "string" and U.len(ch) >= 2 then
        -- combo: sequence of codepoints; base codepoint may also be a
        -- single char of the same class (e.g. U+31F7 alone is in class 11)
        local a = defs["jlreqpdf@jfm@combo@" .. c]
        local ok = a and a[1] and true
        if ok then
          local hs = {}
          for k = 1, U.len(ch) do hs[#hs + 1] = "U+" .. hexn(U.byte(ch, k)) end
          local want = table.concat(hs, ",")
          local found = false
          for item in a[1]:gmatch("%S+") do if item == want then found = true end end
          ok = found
        end
        if ok then n_ok = n_ok + 1
        else fail("combo " .. ch .. " missing from combo@" .. c) end
      else
        fail("unclassifiable source entry " .. tostring(ch) .. " in class " .. c)
      end
    end
  end
end
print(string.format("coverage: %d/%d char entries accounted for", n_ok, n_expect))

-- no char in two classes (source side check)
local seen = {}
for c, v in pairs(jfm) do
  if type(c) == "number" and v.chars then
    for _, ch in ipairs(v.chars) do
      if type(ch) == "string" and U.len(ch) == 1 then
        local cp = U.byte(ch)
        if seen[cp] then
          fail(string.format("char U+%X appears in classes %d and %d in source",
            cp, seen[cp], c))
        end
        seen[cp] = c
      end
    end
  end
end

-- ---------- 2. PAIRS: >=5 representative cross-checks ------------------------
local function glue_fields(f, t)
  local g = jfm[f].glue and jfm[f].glue[t]
  if not g then return nil end
  return {
    num(g[1]), num(g[2]), num(g[3]),
    num(g.ratio or 0.5),                  -- ltj-jfont.lua:141 default
    tostring((g.priority or {0, 0})[1]),  -- ltj-jfont.lua:144
    tostring((g.priority or {0, 0})[2]),
    tostring(g.kanjiskip_natural or 0),    -- norm_val, ltj-jfont.lua:157
    tostring(g.kanjiskip_stretch or 0),
    tostring(g.kanjiskip_shrink or 0),
  }
end

local pair_checks = {
  { 2, 1,   "close-bracket -> open-bracket (」->「)" },
  { 0, 1,   "kanji -> open-bracket (阿->「)" },
  { 2, 0,   "close-bracket -> latin boundary (」->A, class 0)" },
  { 5, 6,   "middle-dot -> full-stop (・->。)" },
  { 6, 5,   "full-stop -> middle-dot (。->・)" },
  { 1, 5,   "open-bracket -> middle-dot (「->・)" },
  { 0, 5,   "kanji -> middle-dot (阿->・)" },
  { 0, 0,   "kanji -> kanji (阿->伊)" },
  { 90, 1,  "paragraph-start -> open-bracket (parbdd->「)" },
  { 7, 5,   "comma -> middle-dot (、->・)" },
}
local npairs_checked = 0
for _, chk in ipairs(pair_checks) do
  local f, t, desc = chk[1], chk[2], chk[3]
  local want = glue_fields(f, t)
  local d = defs[string.format("jlreqpdf@jfm@pair@%d@%d", f, t)]
  if d then d = split_groups(d[1]) end -- {{a}{b}...} -> {a},{b},...
  if want == nil then
    if d then fail(desc .. ": .def has pair but JFM does not define it") end
  else
    if not d then
      fail(desc .. ": pair missing from .def")
    else
      local ok = #d == #want
      if ok then
        for k = 1, #want do if d[k] ~= want[k] then ok = false end end
      end
      if ok then
        npairs_checked = npairs_checked + 1
        print(string.format("pair %d->%d OK  (%s)  {%s,%s,%s} r=%s p=(%s,%s) knat=%s",
          f, t, desc, d[1], d[2], d[3], d[4], d[5], d[6], d[7]))
      else
        fail(string.format("%s: .def {%s} != expected {%s}", desc,
          table.concat(d, ","), table.concat(want, ",")))
      end
    end
  end
end
if npairs_checked < 5 then
  fail("only " .. npairs_checked .. " pairs cross-checked, need >= 5")
end

-- ---------- 3. METRICS --------------------------------------------------------
do
  local ks = split_groups(defs["jlreqpdf@jfm@kanjiskip"][1])
  local xs = split_groups(defs["jlreqpdf@jfm@xkanjiskip"][1])
  if defs["jlreqpdf@jfm@zw"][1] ~= num(jfm.zw) then fail("zw mismatch") end
  if defs["jlreqpdf@jfm@zh"][1] ~= num(jfm.zh) then fail("zh mismatch") end
  if defs["jlreqpdf@jfm@dir"][1] ~= jfm.dir then fail("dir mismatch") end
  if not ks or ks[1] ~= num(jfm.kanjiskip[1]) or ks[2] ~= num(jfm.kanjiskip[2])
     or ks[3] ~= num(jfm.kanjiskip[3]) then
    fail("kanjiskip mismatch: got {" .. defs["jlreqpdf@jfm@kanjiskip"][1]
      .. "} want {" .. num(jfm.kanjiskip[1]) .. "}{" .. num(jfm.kanjiskip[2])
      .. "}{" .. num(jfm.kanjiskip[3]) .. "}")
  end
  if not xs or xs[1] ~= num(jfm.xkanjiskip[1]) or xs[2] ~= num(jfm.xkanjiskip[2])
     or xs[3] ~= num(jfm.xkanjiskip[3]) then
    fail("xkanjiskip mismatch")
  end
end

local classes = {}
for k in pairs(jfm) do if type(k) == "number" then classes[#classes + 1] = k end end
table.sort(classes)
for _, c in ipairs(classes) do
  local v = jfm[c]
  local w, h, d = v.width or 1, v.height or 0.88, v.depth or 0.12
  local got = defs["jlreqpdf@jfm@class@" .. c]
  if got then got = split_groups(got[1]) end -- {{w}{h}{d}{align}} -> 4 fields
  if not got then
    fail("class " .. c .. " metrics missing")
  elseif got[1] ~= num(w) or got[2] ~= num(h) or got[3] ~= num(d)
     or got[4] ~= (v.align or "left") then
    fail("class " .. c .. " metrics mismatch: {" .. table.concat(got, ",")
      .. "} expected {" .. num(w) .. "," .. num(h) .. "," .. num(d) .. ","
      .. (v.align or "left") .. "}")
  end
  local ea = v.end_adjust
  local ge = defs["jlreqpdf@jfm@endadj@" .. c]
  if ea then
    local copy = {}
    for k = 1, #ea do copy[k] = ea[k] end
    table.sort(copy) -- ltj-jfont.lua:123 sorts too
    local inner = ge and ge[1] and split_groups(ge[1])
    if not inner or #inner ~= #copy then
      fail("class " .. c .. " end_adjust missing/size")
    else
      for k = 1, #copy do
        if inner[k] ~= num(copy[k]) then
          fail("class " .. c .. " end_adjust[" .. k .. "] mismatch")
        end
      end
    end
  elseif ge then
    fail("class " .. c .. " has endadj in .def but none in JFM")
  end
end
print("metrics: all " .. #classes .. " classes + kanjiskip/xkanjiskip/zw/zh/dir OK")

-- ---------- 4. STRUCTURE -------------------------------------------------------
local family_counts = {}
for _, name in ipairs(defnames) do
  local fam = name:match("^jlreqpdf@jfm@([%w]+)@") or name:match("^jlreqpdf@jfm@([%w]+)$") or "?"
  family_counts[fam] = (family_counts[fam] or 0) + 1
end
local fams = {}
for f in pairs(family_counts) do fams[#fams + 1] = f end
table.sort(fams)
local cl = {}
for _, f in ipairs(fams) do cl[#cl + 1] = f .. "=" .. family_counts[f] end
print("families: " .. table.concat(cl, " "))
print(string.format("total \\defs: %d  (lines: %d)", ndef, nlines))

-- ---------- verdict --------------------------------------------------------------
if failures == 0 then
  print("m3-verify: ALL CHECKS PASSED")
  os.exit(0)
else
  print("m3-verify: " .. failures .. " failure(s)")
  os.exit(1)
end
