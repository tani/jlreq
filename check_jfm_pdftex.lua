--[[---------------------------------------------------------------------------
  check_jfm_pdftex.lua --- static validator for the generated pdfTeX JFM
  data files (PLAN.md §5 M3, §6.1 T1; productionized from poc/m3-verify.lua).
  Naming follows the existing check_jfm.lua convention (repo root).

  Run from the repository root (default paths) or pass a .def explicitly:

    texlua check_jfm_pdftex.lua [<path-to-.def> ...] [--jfm=<path>]

  With no arguments, all four committed variants are validated:
    jlreq-pdftex-jfm.def    (zenkaku_tentsuki, burasage=false)
    jlreq-pdftex-jfm-b.def  (zenkaku_tentsuki, burasage=true)
    jlreq-pdftex-jfm-z.def  (zenkakunibu_nibu, burasage=false)
    jlreq-pdftex-jfm-bz.def (zenkakunibu_nibu, burasage=true)

  Per variant, each check prints a line and any failure sets rc=1:
    1. HEADER    declares generator version, source sha256, options and
                 variant suffix consistently with the file name.
    2. COVERAGE  every char entry of every class's chars list in
                 jfm-jlreq.lua appears exactly once in the .def dispatch
                 (single-codepoint chars as \cls@<hex>, combos, AJ1 glyphs,
                 pseudo names), and no char appears in two classes.
    3. PAIRS     ALL defined pair glues are byte-checked against the
                 freshly loaded JFM table (incl. defaults ratio=0.5,
                 priority={0,0}, kanjiskip_natural normalization as in
                 ltj-jfont.lua:141,144,157); no extra pairs beyond the
                 source. Additionally the 9 PoC canary pairs are asserted
                 with hardcoded values (independent of the loader).
    4. METRICS   class width/height/depth/align/left and
                 kanjiskip/xkanjiskip/zw/zh/dir match; end_adjust sorted.
    5. STRUCTURE every emitted line is a comment (%% / %), blank, or a \def
                 of the documented families; family counts reported;
                 total \def count = the sum of emitted families.
    6. SEMANTICS variant-specific oracles, independent of the generator's
                 code path: for b/bz, end_adjust of classes 6,7 must be
                 {-0.500000}{0.000000}{-0.500000} ... i.e. -0.5 appended
                 then sorted; for z/bz, class 1 width must be 1.0 and
                 every k->1 glue natural must be exactly 0.5 zw smaller
                 than the default variant's, with 90->1 == {0,0,0} ratio
                 1.5; for the default variant, class 1 width 0.5 and
                 90->1 == {0,0,0} ratio 0.5.
-----------------------------------------------------------------------------]]

-- ------------------------- arguments ----------------------------------------
local deffiles = {}
local jfmfile_opt = nil
do
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a:sub(1, 6) == "--jfm=" then
      jfmfile_opt = a:sub(7)
    elseif a:sub(1, 2) == "--" then
      io.stderr:write("check_jfm_pdftex.lua: unknown option " .. a .. "\n")
      os.exit(2)
    else
      deffiles[#deffiles + 1] = a
    end
    i = i + 1
  end
end
local scriptdir = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."

local DEFAULT_DEFS = {
  { suffix = "",    file = "jlreq-pdftex-jfm.def",    obp = "zenkaku_tentsuki",  bura = false },
  { suffix = "b",   file = "jlreq-pdftex-jfm-b.def",  obp = "zenkaku_tentsuki",  bura = true },
  { suffix = "z",   file = "jlreq-pdftex-jfm-z.def",  obp = "zenkakunibu_nibu", bura = false },
  { suffix = "bz",  file = "jlreq-pdftex-jfm-bz.def", obp = "zenkakunibu_nibu", bura = true },
  { suffix = "tate", file = "jlreq-pdftex-jfm-tate.def", obp = "zenkaku_tentsuki", bura = false, tate = true, jfmfile = "jfm-jlreqv-pl.lua" },
}
if #deffiles == 0 then
  for _, d in ipairs(DEFAULT_DEFS) do
    local f = io.open(d.file, "r")
    if not f then
      io.stderr:write("check_jfm_pdftex.lua: cannot open " .. d.file
        .. " (run `make pdftex-jfm` first)\n")
      os.exit(2)
    end
    f:close()
  end
  deffiles = DEFAULT_DEFS
end

-- ------------------------- helpers ------------------------------------------
local failures = 0
local function fail(msg)
  print("  FAIL: " .. msg)
  failures = failures + 1
end
local function num(x)
  if x == 0 then x = 0 end
  return string.format("%.6f", x)
end
local function hexn(cp) return string.format("%X", cp) end

-- split_groups(s): list of top-level {..} group contents in s.
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
    if depth ~= 0 then return nil end
    groups[#groups + 1] = s:sub(s0 + 1, p - 2)
    pos = p
  end
  return groups
end

-- ------------------------- JFM loading --------------------------------------
kpse.set_program_name("texlua", "lualatex")
require("lualibs")

local jfmfile = jfmfile_opt
  or (function()
    local f = io.open(scriptdir .. "/jfm-jlreq.lua", "r")
    if f then f:close(); return scriptdir .. "/jfm-jlreq.lua" end
    return kpse.find_file("jfm-jlreq.lua")
  end)()
if not jfmfile then
  io.stderr:write("check_jfm_pdftex.lua: cannot find jfm-jlreq.lua\n")
  os.exit(2)
end

local function load_jfm(obp, bura, src)
  jlreq = { open_bracket_pos = obp, burasage = bura }
  local jfm
  luatexja = { jfont = {} }
  function luatexja.jfont.define_jfm(j) jfm = j end
  dofile(src or jfmfile)
  return jfm
end

local function sha256_hex(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local raw = sha2.digest256(data)
  return (raw:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end
local JFM_SHA256 = sha256_hex(jfmfile)

-- expected suffix of a .def given its declared options
local function variant_suffix(obp, bura)
  local s = ""
  if bura then s = s .. "b" end
  if obp == "zenkakunibu_nibu" then s = s .. "z" end
  return s
end

-- serialize one glue entry exactly as the generator does (ltj-jfont defaults)
local function glue_fields(g)
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

local U = unicode.utf8

-- ---------- independent canary pairs (default variant, hardcoded) ----------
-- Byte-level oracles for representative values, transcribed from
-- jfm-jlreq.lua directly (NOT via the loader), so a loader regression cannot
-- mask an emission error.  Each entry cites its source location.
-- NOTE: class 0 has NO self pair 0->0 (commented out at jfm-jlreq.lua:22).
local CANARY_DEFAULT = {
  -- [0].glue[1] = {0.5, stretch_width=0.25, 0.5, ratio=1, priority={-1,-2}, knat=1}
  { "pair@0@1",   "{0.500000}{0.250000}{0.500000}{1.000000}{-1}{-2}{1}{0}{0}" },   -- :9
  -- [2].glue[0] (close bracket -> kanji): {0.5, 0.25, 0.5, ratio=0, priority={-1,-2}}
  { "pair@2@0",   "{0.500000}{0.250000}{0.500000}{0.000000}{-1}{-2}{1}{0}{0}" },   -- :66
  -- [5].glue[6] (middle dot -> full stop): {0.25, 0, 0.25, ratio=0, priority={0,-1}}
  { "pair@5@6",   "{0.250000}{0.000000}{0.250000}{0.000000}{0}{-1}{1}{0}{0}" },   -- :250
  -- [6].glue[5] (full stop -> middle dot): {0.75, 0, 0.25, ratio=0.33333333, priority={0,-1}}
  { "pair@6@5",   "{0.750000}{0.000000}{0.250000}{0.333333}{0}{-1}{1}{0}{0}" },   -- :285
  -- [1].glue[5] (open bracket -> middle dot): {0.25, 0, 0.25, ratio=1, priority={0,-1}}
  { "pair@1@5",   "{0.250000}{0.000000}{0.250000}{1.000000}{0}{-1}{1}{0}{0}" },   -- :37
  -- [0].glue[5]: {0.25, 0, 0.25, ratio=1, priority={0,-1}}
  { "pair@0@5",   "{0.250000}{0.000000}{0.250000}{1.000000}{0}{-1}{1}{0}{0}" },   -- :10
  -- [90].glue[1] = {0,0,0} (default; line-start bracket is betagumi)
  { "pair@90@1",  "{0.000000}{0.000000}{0.000000}{0.500000}{0}{0}{0}{0}{0}" },   -- :1127
  -- [7].glue[5] (comma -> middle dot): {0.75, 0, 0.75, ratio=0.33333333, priority={0,-1}}
  { "pair@7@5",   "{0.750000}{0.000000}{0.750000}{0.333333}{0}{-1}{1}{0}{0}" },   -- :311
  -- [2].glue[1] (close -> open bracket): {0.5, 0.25, 0.5, ratio=0, priority={-1,-2}}
  { "pair@2@1",   "{0.500000}{0.250000}{0.500000}{0.000000}{-1}{-2}{1}{0}{0}" },  -- :65
  -- class metrics: [1] width 0.5 (default), [6] w/h/d, align
  { "class@1",    "{0.500000}{0.880000}{0.120000}{right}{0.000000}" },
  { "class@6",    "{0.500000}{0.880000}{0.120000}{left}{0.000000}" },
  { "class@0",    "{1.000000}{0.880000}{0.120000}{middle}{0.000000}" },
  -- kanjiskip / xkanjiskip (jfm-jlreq.lua:23-24)
  { "kanjiskip",  "{0.000000}{0.250000}{0.000000}" },
  { "xkanjiskip", "{0.250000}{0.250000}{0.125000}" },
  -- end_adjust of 6 in the DEFAULT variant: source {0.5, 0} (:276), emitted
  -- sorted ascending -> {0, 0.5} (ltj-jfont.lua:123 sorts too)
  { "endadj@6",   "{0.000000}{0.500000}" },
  -- end_adjust of 2 (close brackets): {0.5, 0} sorted -> {0, 0.5} (:104)
  { "endadj@2",   "{0.000000}{0.500000}" },
}
-- Same pairs for the z variants: every k->1 glue shifts by -0.5 with the
-- ratio re-blended per add_space (jfm-jlreq.lua:1137), 90->1 gains +0.5.
-- Expected values were computed independently and hardcoded here.
local CANARY_Z = {
  ["pair@0@1"]   = "{0.000000}{0.250000}{0.500000}{0.000000}{-1}{-2}{1}{0}{0}",
  ["pair@2@1"]   = "{0.000000}{0.250000}{0.500000}{-0.333333}{-1}{-2}{1}{0}{0}",
  ["pair@90@1"]  = "{0.000000}{0.000000}{0.000000}{1.500000}{0}{0}{0}{0}{0}",
  ["class@1"]    = "{1.000000}{0.880000}{0.120000}{right}{0.000000}",
}
-- For b/bz: end_adjust of 6,7 gains -0.5 (jfm-jlreq.lua:1167-1171), then is
-- sorted ascending: {-0.5, 0, 0.5}.
local CANARY_B_EA = {
  ["endadj@6"]   = "{-0.500000}{0.000000}{0.500000}",
  ["endadj@7"]   = "{-0.500000}{0.000000}{0.500000}",
}
-- nibu_tentsuki would give 90->1 = {-0.5,0,0} ratio -0.5; no variant file
-- exists for it (documented in make_pdftex_jfm.lua).

-- ---------- per-variant check driver ----------------------------------------
local function check_variant(spec)
  local deffile, obp, bura, suffix =
    spec.file, spec.obp, spec.bura, spec.suffix
  print("== " .. deffile
    .. " (open_bracket_pos=" .. obp .. " burasage=" .. tostring(bura) .. ")")
  local vfail0 = failures

  -- ---- parse the .def ------------------------------------------------------
  local defs = {}      -- name -> {top-level group contents}
  local defnames = {}  -- ordered list of defined macro names
  local nlines, ndef = 0, 0
  local header = {}
  local df = io.open(deffile, "r")
  if not df then print("  FAIL: cannot open " .. deffile) os.exit(2) end
  for line in df:lines() do
    nlines = nlines + 1
    if line:sub(1, 2) == "%%" then
      header[#header + 1] = line:sub(3)
    elseif line:sub(1, 1) == "%" then
      -- section comment
    elseif line:sub(1, 1) == "\\" and line:match("^\\expandafter\\def\\csname") then
      ndef = ndef + 1
      local name, rest = line:match("^\\expandafter\\def\\csname ([^ ]+)\\endcsname(.*)$")
      if not name then
        fail("line " .. nlines .. ": unparseable csname def")
      else
        local args = split_groups(rest)
        if not args then
          fail("line " .. nlines .. ": unbalanced braces")
        else
          if defs[name] then fail("line " .. nlines .. ": duplicate def of " .. name) end
          defs[name] = args
          defnames[#defnames + 1] = name
        end
      end
    elseif line:match("^\\def\\") then
      ndef = ndef + 1
      local name, rest = line:match("^\\def\\([^ {]+)(.*)$")
      if not name then
        fail("line " .. nlines .. ": unparseable \\def")
      else
        local args = split_groups(rest)
        if not args then
          fail("line " .. nlines .. ": unbalanced braces")
        else
          if defs[name] then fail("line " .. nlines .. ": duplicate \\def of " .. name) end
          defs[name] = args
          defnames[#defnames + 1] = name
        end
      end
    elseif line:match("^%s*$") then
      -- blank
    else
      fail("line " .. nlines .. ": unrecognized line: " .. line)
    end
  end
  df:close()

  -- ---- 1. HEADER -----------------------------------------------------------
  do
    local h = table.concat(header, "\n")
    local want_sha
    if spec.tate then
      -- tate variant's declared source is jfm-jlreqv-pl.lua (T1b)
      local ssrc = scriptdir .. "/" .. spec.jfmfile
      local f = io.open(ssrc, "r")
      if not f then ssrc = kpse.find_file(spec.jfmfile) else f:close() end
      local tsha = sha256_hex(ssrc)
      want_sha = "source sha256: " .. tostring(tsha)
      if not h:find("source: " .. spec.jfmfile, 1, true) then
        fail("header does not name tate source " .. spec.jfmfile)
      end
      if not h:find("options: dir=tate", 1, true) then
        fail("header options line mismatched (want 'options: dir=tate')")
      end
    else
      want_sha = "source sha256: " .. JFM_SHA256
      local hop = "options: open_bracket_pos=" .. obp .. " burasage=" .. tostring(bura)
      if not h:find(hop, 1, true) then
        fail("header options line mismatched (want '" .. hop .. "')")
      end
    end
    if not h:find(want_sha, 1, true) then
      fail("header sha256 line missing/mismatched (want " .. want_sha .. ")")
    end
    if not h:find("generated by make_pdftex_jfm%.lua ") then
      fail("header does not name the generator")
    end
    if (defs["jlreqpdf@jfm@variant"] or {{""}})[1] ~= suffix then
      fail("jlreqpdf@jfm@variant is "
        .. tostring((defs["jlreqpdf@jfm@variant"] or {{}})[1])
        .. ", want " .. suffix)
    end
    if not spec.tate then
      -- variant implied by options must match the file name suffix
      local implied = variant_suffix(obp, bura)
      if implied ~= suffix then
        fail("options imply variant '" .. implied .. "' but file suffix is '" .. suffix .. "'")
      end
    end
  end

  -- ---- load the JFM for this variant ---------------------------------------
  local jfm = load_jfm(obp, bura, spec.jfmfile and (scriptdir .. "/" .. spec.jfmfile) or nil)
  if not jfm then fail("JFM did not load") return end

  local classes = {}
  for k in pairs(jfm) do if type(k) == "number" then classes[#classes + 1] = k end end
  table.sort(classes)

  -- ---- 2. COVERAGE -----------------------------------------------------------
  local n_expect, n_ok = 0, 0
  for _, c in ipairs(classes) do
    local chars = jfm[c].chars
    if chars then
      for _, ch in ipairs(chars) do
        n_expect = n_expect + 1
        if type(ch) == "string" and ch:sub(1, 4) == "AJ1-" then
          local gid = ch:sub(5)
          local a = defs["jlreqpdf@jfm@ajone@" .. c]
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
  if n_expect > 0 and n_ok == n_expect then
    print(string.format("  coverage: %d/%d char entries accounted for", n_ok, n_expect))
  else
    fail(string.format("coverage incomplete: %d/%d", n_ok, n_expect))
  end

  -- no char in two classes (source side check)
  local seen = {}
  for _, c in ipairs(classes) do
    local chars = jfm[c].chars
    if chars then
      for _, ch in ipairs(chars) do
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

  -- ---- 3. PAIRS: ALL defined pairs byte-checked ----------------------------
  local npairs_src = 0
  for _, f in ipairs(classes) do
    local g = jfm[f].glue or {}
    local tos = {}
    for t in pairs(g) do tos[#tos + 1] = t end
    table.sort(tos)
    for _, t in ipairs(tos) do
      npairs_src = npairs_src + 1
      local want = glue_fields(g[t])
      local d = defs[string.format("jlreqpdf@jfm@pair@%d@%d", f, t)]
      if not d then
        fail(string.format("pair %d->%d missing from .def", f, t))
      else
        -- 新形式: 本体は \jlreqpdf@pairfields{f1}...{f9} マクロ呼び出し
        -- （.def側で引数再括弧化問題を回避するため）。
        local body = d[1]:gsub("^\\jlreqpdf@pairfields", "")
        local got = split_groups(body)
        local ok = got ~= nil and #got == #want
        if ok then
          for k = 1, #want do if got[k] ~= want[k] then ok = false end end
        end
        if not ok then
          fail(string.format("pair %d->%d: .def {%s} != expected {%s}",
            f, t, d[1], table.concat(want, "}{")))
        end
      end
    end
  end
  -- no EXTRA pairs in the .def beyond the source
  local npairs_def = 0
  for _, name in ipairs(defnames) do
    if name:match("^jlreqpdf@jfm@pair@") then npairs_def = npairs_def + 1 end
  end
  if npairs_def ~= npairs_src then
    fail(string.format("pair count mismatch: .def has %d, source defines %d",
      npairs_def, npairs_src))
  end
  print(string.format("  pairs: %d/%d defined pairs byte-checked (no extras)",
    npairs_src, npairs_def))

  -- ---- independent canaries -------------------------------------------------
  -- Byte-level oracles on top of the loader-based checks. Default-variant
  -- values are hardcoded; z/b variants get their specific overrides.
  local ncanary = 0
  -- tate-specific canary overrides (T1b): the tate metric table has
  -- height=depth=0.5 per class and the punctuation glue model differs.
  local CANARY_TATE = {
    ["class@1"]    = "{0.500000}{0.500000}{0.500000}{right}{0.000000}",
    ["class@6"]    = "{0.500000}{0.500000}{0.500000}{left}{0.000000}",
    ["class@0"]    = "{1.000000}{0.500000}{0.500000}{middle}{0.000000}",
    ["pair@0@1"]   = "{0.500000}{0.000000}{0.500000}{1.000000}{-1}{-2}{1}{0}{0}",
    ["pair@2@0"]   = "{0.500000}{0.000000}{0.500000}{0.000000}{-1}{-2}{1}{0}{0}",
    ["pair@90@1"]  = "{0.000000}{0.000000}{0.000000}{0.500000}{0}{0}{0}{0}{0}",
    ["pair@2@1"]   = "{0.500000}{0.000000}{0.500000}{0.000000}{-1}{-2}{1}{0}{0}",
    ["endadj@6"]   = "{0.000000}{0.500000}",
    ["endadj@2"]   = "{0.000000}{0.500000}",
  }
  for _, chk in ipairs(CANARY_DEFAULT) do
    local name, want = chk[1], chk[2]
    if spec.tate and CANARY_TATE[name] then
      want = CANARY_TATE[name]
    end
    if name:match("^pair@0@1$") and (suffix == "z" or suffix == "bz") then
      want = CANARY_Z["pair@0@1"]
    elseif name:match("^pair@2@1$") and (suffix == "z" or suffix == "bz") then
      want = CANARY_Z["pair@2@1"]
    elseif name:match("^pair@90@1$") and (suffix == "z" or suffix == "bz") then
      want = CANARY_Z["pair@90@1"]
    elseif name:match("^class@1$") and (suffix == "z" or suffix == "bz") then
      want = CANARY_Z["class@1"]
    elseif (name == "endadj@6" or name == "endadj@7")
      and (suffix == "b" or suffix == "bz") then
      want = CANARY_B_EA[name]
    end
    local d = defs["jlreqpdf@jfm@" .. name]
    local body = d and d[1]
    if body and name:match("^pair@") then
      body = body:gsub("^\\jlreqpdf@pairfields", "")
    end
    if not d then
      fail("canary " .. name .. " missing")
    elseif body ~= want then
      fail("canary " .. name .. " = " .. body .. ", want " .. want)
    else
      ncanary = ncanary + 1
    end
  end
  print(string.format("  canaries: %d hardcoded byte-oracles OK", ncanary))

  -- ---- 4. METRICS -------------------------------------------------------------
  do
    local ks = split_groups(defs["jlreqpdf@jfm@kanjiskip"][1])
    local xs = split_groups(defs["jlreqpdf@jfm@xkanjiskip"][1])
    if defs["jlreqpdf@jfm@zw"][1] ~= num(jfm.zw) then fail("zw mismatch") end
    if defs["jlreqpdf@jfm@zh"][1] ~= num(jfm.zh) then fail("zh mismatch") end
    if defs["jlreqpdf@jfm@dir"][1] ~= jfm.dir then fail("dir mismatch") end
    if defs["jlreqpdf@jfm@version"][1] ~= tostring(jfm.version or 1) then fail("version mismatch") end
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
  for _, c in ipairs(classes) do
    local v = jfm[c]
    local w, h, d = v.width or 1, v.height or 0.88, v.depth or 0.12
    local left = v.left or 0
    local got = defs["jlreqpdf@jfm@class@" .. c]
    if got then got = split_groups(got[1]) end -- {{w}{h}{d}{align}{left}}
    if not got then
      fail("class " .. c .. " metrics missing")
    elseif got[1] ~= num(w) or got[2] ~= num(h) or got[3] ~= num(d)
      or got[4] ~= (v.align or "left") or got[5] ~= num(left) then
      fail("class " .. c .. " metrics mismatch: {" .. table.concat(got, ",")
        .. "} expected {" .. num(w) .. "," .. num(h) .. "," .. num(d) .. ","
        .. (v.align or "left") .. "," .. num(left) .. "}")
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
  print("  metrics: all " .. #classes .. " classes + kanjiskip/xkanjiskip/zw/zh/dir OK")

  -- ---- 5. STRUCTURE ------------------------------------------------------------
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
  print("  families: " .. table.concat(cl, " "))
  print(string.format("  total \\defs: %d  (lines: %d)", ndef, nlines))

  -- ---- 6. SEMANTICS: variant-specific oracles -----------------------------------
  if suffix == "z" or suffix == "bz" then
    -- jfm-jlreq.lua:1148-1155: class 1 width +0.5; every k->1 glue -0.5
    -- (ratio re-blended by add_space); :1159-1160: 90->1 +0.5.
    local c1 = split_groups(defs["jlreqpdf@jfm@class@1"][1])
    if not c1 or c1[1] ~= num(1.0) then
      fail("z variant: class 1 width must be 1.000000, got "
        .. defs["jlreqpdf@jfm@class@1"][1])
    end
    -- every k->1 natural is exactly 0.5 less than in the default table,
    -- except 90->1 whose net is 0 (=-0.5 then +0.5), ratio 1.5.
    local jd = load_jfm("zenkaku_tentsuki", false)
    for _, f in ipairs(classes) do
      local gd = jd[f].glue and jd[f].glue[1]
      local gz = jfm[f].glue and jfm[f].glue[1]
      if gd and gz then
        local dz = split_groups(defs[string.format("jlreqpdf@jfm@pair@%d@1", f)][1])
        local want_nat = num(gd[1] - 0.5 + (f == 90 and 0.5 or 0))
        if dz[1] ~= want_nat then
          fail(string.format("z variant: pair %d->1 natural %s, want %s (default-0.5)",
            f, dz[1], want_nat))
        end
      elseif gd and not gz then
        fail("z variant: pair " .. f .. "->1 lost")
      elseif gz and not gd then
        fail("z variant: pair " .. f .. "->1 appeared from nowhere")
      end
    end
    local p901 = split_groups(defs["jlreqpdf@jfm@pair@90@1"][1])
    if p901[1] ~= num(0) or p901[4] ~= num(1.5) then
      fail("z variant: pair 90->1 must be {0.000000}...{1.500000}, got "
        .. defs["jlreqpdf@jfm@pair@90@1"][1])
    end
    print("  semantics: z oracle OK (class1 width 1.0, all ->1 pairs -0.5, 90->1 {0}r1.5)")
  else
    local c1 = split_groups(defs["jlreqpdf@jfm@class@1"][1])
    if not c1 or c1[1] ~= num(0.5) then
      fail("default/b variant: class 1 width must be 0.500000, got "
        .. defs["jlreqpdf@jfm@class@1"][1])
    end
  end
  if suffix == "b" or suffix == "bz" then
    -- jfm-jlreq.lua:1167-1171: end_adjust of 6,7 = source {0.5,0} + {-0.5},
    -- then sorted ascending -> {-0.5, 0, 0.5} (ltj-jfont.lua:123 sorts too)
    local b_ok = true
    for _, c in ipairs({ 6, 7 }) do
      local got = split_groups(defs["jlreqpdf@jfm@endadj@" .. c][1])
      if not got or #got ~= 3 or got[1] ~= num(-0.5) or got[2] ~= num(0)
        or got[3] ~= num(0.5) then
        fail("b variant: end_adjust of class " .. c
          .. " must be {-0.500000}{0.000000}{0.500000} (sorted), got "
          .. defs["jlreqpdf@jfm@endadj@" .. c][1])
        b_ok = false
      end
    end
    if b_ok then
      print("  semantics: b oracle OK (end_adjust of 6,7 = {-0.5}{0}{0.5})")
    end
  else
    -- default/z: end_adjust of 6,7 stays the source {0.5,0}, sorted -> {0,0.5}
    local nb_ok = true
    for _, c in ipairs({ 6, 7 }) do
      local got = split_groups(defs["jlreqpdf@jfm@endadj@" .. c][1])
      if not got or #got ~= 2 or got[1] ~= num(0) or got[2] ~= num(0.5) then
        fail("non-b variant: end_adjust of class " .. c
          .. " must be {0.000000}{0.500000}, got "
          .. defs["jlreqpdf@jfm@endadj@" .. c][1])
        nb_ok = false
      end
    end
    if nb_ok then
      print("  semantics: non-b oracle OK (end_adjust of 6,7 = {0}{0.5})")
    end
  end

  -- cross-variant diff summary (informational, via committed sibling files)
  print((failures == vfail0) and ("  PASS " .. deffile) or ("  FAILED " .. deffile))
  return failures == vfail0
end

-- ------------------------- run ----------------------------------------------
local all_ok = true
for _, f in ipairs(deffiles) do
  local spec
  if type(f) == "table" then
    spec = f
  else
    -- explicit file argument: infer the variant from the file name
    local sfx = f:match("jlreq%-pdftex%-jfm%-?(%w*)%.def$") or "?"
    local known = { [""] = true, b = true, z = true, bz = true }
    if not known[sfx] then
      io.stderr:write("check_jfm_pdftex.lua: cannot infer variant of " .. f .. "\n")
      os.exit(2)
    end
    spec = {
      file = f, suffix = sfx,
      obp = (sfx == "z" or sfx == "bz") and "zenkakunibu_nibu" or "zenkaku_tentsuki",
      bura = (sfx == "b" or sfx == "bz"),
    }
  end
  if not check_variant(spec) then all_ok = false end
  print("")
end
if all_ok then
  print("check_jfm_pdftex: ALL CHECKS PASSED (" .. #deffiles .. " file(s))")
  os.exit(0)
else
  print("check_jfm_pdftex: " .. failures .. " failure(s)")
  os.exit(1)
end
