--[[---------------------------------------------------------------------------
  pdftexja-jfmconv.lua --- convert a LuaTeX-ja JFM (jfm-<name>.lua) into the
  pdfTeX-ja JFM data file ptjfm-<name>.def.

  pdfTeX has no Lua, so pdfTeX-ja reads JFMs as pre-generated TeX data.  The
  converter runs the JFM Lua file exactly as LuaTeX-ja would (the file calls
  luatexja.jfont.define_jfm(t)) and serializes the table.

  Usage (texlua):
    texlua pdftexja-jfmconv.lua --jfm=<path|name> [--name=<name>]
        [--pre=<lua chunk>] [--out=<file>]
  Options:
    --jfm=<path|name>  the JFM Lua file, or a JFM name resolved through
                       kpathsea as jfm-<name>.lua
    --name=<name>      output JFM name (default: the JFM name); the output
                       file is ptjfm-<name>.def
    --pre=<lua chunk>  Lua code run before the JFM file (sets the globals a
                       parameterized JFM reads, e.g. jlreq's
                       'jlreq={open_bracket_pos="nibu_tentsuki",burasage=true}')
    --out=<file>       output path (default ptjfm-<name>.def)
    --version          print the converter version

  Library use:  local conv = dofile("pdftexja-jfmconv.lua") with the global
  PDFTEXJA_JFMCONV_LIBRARY = true returns { generate = <function>,
  version = <string> }; generate{ jfm=<path>, name=<name>, pre=<chunk>,
  out=<path>, header=<extra header comment lines> } -> stats.

  Class numbering contract (pdfTeX-ja runtime):
    27 = the alchar pseudo class (latin/math boundary),
    90 = the parbdd/boxbdd pseudo class (paragraph/box head),
    93 = reserved (explicit glue boundary; never looked up).
  JFM classes holding 'alchar' / 'parbdd' / 'boxbdd' are renumbered to
  27 / 90 (parbdd wins when parbdd and boxbdd are different classes; the
  boxbdd class data is then dropped -- pdfTeX-ja treats box heads like
  paragraph heads).  'glue', 'nox_alchar' and 'jcharbdd' carry no runtime
  meaning here and are recorded as pseudo names only.  Ordinary classes
  that collide with 27/90/93 are moved to free numbers.  For jfm-jlreq.lua
  (alchar=27, parbdd/boxbdd=90) the numbering is unchanged.

  Pair data:
    glue  -> \ptj@jfm@pair@<f>@<t>{\ptj@pairfields{nat}{str}{shr}{ratio}
                {spri}{shpri}{knat}{kstr}{kshr}}
    kern  -> \ptj@jfm@pair@<f>@<t>{\ptj@pairkern{nat}{ratio}}
  Ignored class fields (no pdfTeX-ja runtime meaning): italic, down,
  round_threshold, end_stretch, end_shrink.

  Determinism: sorted keys, %.6f fixed decimals, no timestamps.
-----------------------------------------------------------------------------]]

local VERSION = "3.0"

kpse.set_program_name("texlua", "lualatex")
require("lualibs") -- table.fastcopy etc. (used by JFM files)

local U = unicode.utf8

local function num(x)
  if x == 0 then x = 0 end -- normalize -0.0
  return string.format("%.6f", x)
end
local function hexn(cp) return string.format("%X", cp) end

local function sha256_hex(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local raw = sha2.digest256(data)
  return (raw:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function find_jfm(spec)
  local f = io.open(spec, "r")
  if f then f:close(); return spec end
  local p = kpse.find_file("jfm-" .. spec .. ".lua")
  if p then return p end
  p = kpse.find_file(spec)
  return p
end

local function load_jfm(path, pre)
  local jfm
  luatexja = luatexja or {}
  luatexja.jfont = luatexja.jfont or {}
  luatexja.jfont.jfm_feature = luatexja.jfont.jfm_feature or {}
  function luatexja.jfont.define_jfm(j) jfm = j end
  if pre and pre ~= "" then
    local chunk, err = load(pre, "=--pre")
    if not chunk then error("--pre: " .. err) end
    chunk()
  end
  dofile(path)
  return jfm
end

local KNOWN_CLASS_FIELDS = {
  chars = true, align = true, width = true, height = true, depth = true,
  left = true, glue = true, kern = true, end_adjust = true,
}
local IGNORED_CLASS_FIELDS = {
  italic = true, down = true, round_threshold = true,
  end_stretch = true, end_shrink = true,
}
local PSEUDO = {
  alchar = true, nox_alchar = true, parbdd = true, boxbdd = true,
  jcharbdd = true, glue = true,
}
local RESERVED = { [27] = true, [90] = true, [93] = true }

local function generate(o)
  local jfmpath = assert(o.jfm, "jfm path")
  local jfm = load_jfm(jfmpath, o.pre)
  if not jfm then error("the JFM file did not call define_jfm: " .. jfmpath) end
  local name = o.name

  -- ---------------- class renumbering ---------------------------------------
  local orig = {}
  for k, v in pairs(jfm) do
    if type(k) == "number" and type(v) == "table" then orig[#orig + 1] = k end
  end
  table.sort(orig)
  local function has(c, pseudo)
    for _, ch in ipairs(jfm[c].chars or {}) do
      if ch == pseudo then return true end
    end
    return false
  end
  local map = {}
  local alchar_c, parbdd_c, boxbdd_c
  for _, c in ipairs(orig) do
    if has(c, "alchar") then alchar_c = c end
    if has(c, "parbdd") then parbdd_c = c end
    if has(c, "boxbdd") then boxbdd_c = c end
  end
  local dropped = {}
  if alchar_c then map[alchar_c] = 27 end
  if parbdd_c then map[parbdd_c] = 90 end
  if boxbdd_c and boxbdd_c ~= parbdd_c then
    if parbdd_c then dropped[boxbdd_c] = true else map[boxbdd_c] = 90 end
  end
  local used = {}
  for _, v in pairs(map) do used[v] = true end
  for _, c in ipairs(orig) do
    if map[c] == nil and not dropped[c] then
      if RESERVED[c] or used[c] then
        local n = 1000
        while used[n] or RESERVED[n] or jfm[n] do n = n + 1 end
        map[c] = n
      else
        map[c] = c
      end
      used[map[c]] = true
    end
  end
  local classes = {}
  local inv = {}
  for c, n in pairs(map) do classes[#classes + 1] = n; inv[n] = c end
  table.sort(classes)

  -- ---------------- validation / defaults -----------------------------------
  for _, n in ipairs(classes) do
    local v = jfm[inv[n]]
    for k in pairs(v) do
      if not KNOWN_CLASS_FIELDS[k] and not IGNORED_CLASS_FIELDS[k] then
        error(string.format("unknown class field %q in class %d", tostring(k), inv[n]))
      end
    end
    if v.width == nil then v.width = 1 end
    if v.height == nil then v.height = (jfm.dir == "tate") and 0.5 or 0.88 end
    if v.depth == nil then v.depth = (jfm.dir == "tate") and 0.5 or 0.12 end
  end

  -- ---------------- char dispatch -------------------------------------------
  local single, combos, ajones, pseudos = {}, {}, {}, {}
  for _, n in ipairs(classes) do
    for _, ch in ipairs(jfm[inv[n]].chars or {}) do
      local t = type(ch)
      if t == "string" and ch:sub(1, 4) == "AJ1-" then
        local gid = tonumber(ch:sub(5))
        if not gid then error("bad AJ1 entry: " .. ch) end
        ajones[n] = ajones[n] or {}
        ajones[n][#ajones[n] + 1] = gid
      elseif t == "string" and PSEUDO[ch] then
        if pseudos[ch] then error("duplicate pseudo char " .. ch) end
        pseudos[ch] = n
      elseif t == "string" and U.len(ch) == 2 and ch:sub(-1) == "*" then
        -- "X*": the char and its vertical variant (LuaTeX-ja syntax);
        -- pdfTeX-ja has one glyph per code point
        local cp = U.byte(ch, 1)
        if single[cp] then error(string.format("duplicate char U+%X", cp)) end
        single[cp] = n
      elseif t == "string" and U.len(ch) == 1 then
        local cp = U.byte(ch)
        if single[cp] then
          error(string.format("duplicate char U+%X in classes %d and %d", cp, single[cp], n))
        end
        single[cp] = n
      elseif t == "string" and U.len(ch) >= 2 then
        local cps = {}
        for k = 1, U.len(ch) do cps[#cps + 1] = U.byte(ch, k) end
        combos[n] = combos[n] or {}
        combos[n][#combos[n] + 1] = cps
      elseif t == "number" then
        if single[ch] then error(string.format("duplicate char U+%X", ch)) end
        single[ch] = n
      else
        error("unclassifiable chars entry in class " .. inv[n])
      end
    end
  end

  -- ---------------- emit ----------------------------------------------------
  local out = {}
  local function emit(s) out[#out + 1] = s end
  local function defop(nm, body)
    emit("\\expandafter\\def\\csname " .. nm .. "\\endcsname{" .. body .. "}")
  end
  emit("%% ptjfm-" .. name .. ".def -- pdfTeX-ja JFM data")
  emit("%% generated by pdftexja-jfmconv.lua " .. VERSION
    .. " -- DO NOT EDIT")
  emit("%% source: " .. jfmpath:match("[^/]*$") .. " (sha256 below)")
  emit("%% source sha256: " .. sha256_hex(jfmpath))
  if o.pre and o.pre ~= "" then emit("%% pre: " .. o.pre) end
  for _, l in ipairs(o.header or {}) do emit("%% " .. l) end
  emit("%% deterministic: sorted keys, %.6f fixed decimals, no timestamps")
  emit("%% loader contract: \\makeatletter (catcode @ = 11) before \\input")
  emit("%% all lengths are in zw units (jfm.zw = " .. num(jfm.zw or 1) .. ")")
  local renum = {}
  for _, n in ipairs(classes) do
    if inv[n] ~= n then renum[#renum + 1] = inv[n] .. "->" .. n end
  end
  if #renum > 0 then emit("%% class renumbering: " .. table.concat(renum, " ")) end
  for c in pairs(dropped) do emit("%% dropped class " .. c .. " (boxbdd; treated as parbdd)") end

  emit("\\def\\ptj@jfm@name{" .. name .. "}")
  emit("\\def\\ptj@jfm@dir{" .. tostring(jfm.dir) .. "}")
  emit("\\def\\ptj@jfm@zw{" .. num(jfm.zw or 1) .. "}")
  emit("\\def\\ptj@jfm@zh{" .. num(jfm.zh or 1) .. "}")
  emit("\\def\\ptj@jfm@version{" .. tostring(jfm.version or 1) .. "}")
  local ks = jfm.kanjiskip or { 0, 0, 0 }
  local xks = jfm.xkanjiskip or { 0, 0, 0 }
  emit("\\def\\ptj@jfm@kanjiskip{{" .. num(ks[1] or 0) .. "}{"
    .. num(ks[2] or 0) .. "}{" .. num(ks[3] or 0) .. "}}")
  emit("\\def\\ptj@jfm@xkanjiskip{{" .. num(xks[1] or 0) .. "}{"
    .. num(xks[2] or 0) .. "}{" .. num(xks[3] or 0) .. "}}")
  emit("\\def\\ptj@jfm@classlist{" .. table.concat(classes, ",") .. "}")
  emit("")
  emit("% ---- class metrics: \\ptj@jfm@class@<n>{{w}{h}{d}{align}{left}}")
  for _, n in ipairs(classes) do
    local v = jfm[inv[n]]
    defop(string.format("ptj@jfm@class@%d", n),
      string.format("{%s}{%s}{%s}{%s}{%s}",
        num(v.width), num(v.height), num(v.depth), v.align or "left", num(v.left or 0)))
  end
  emit("")
  emit("% ---- end_adjust (line-end adjustment candidates, ascending)")
  for _, n in ipairs(classes) do
    local ea = jfm[inv[n]].end_adjust
    if ea then
      local copy = {}
      for k = 1, #ea do copy[k] = ea[k] end
      table.sort(copy)
      local body = {}
      for _, v in ipairs(copy) do body[#body + 1] = "{" .. num(v) .. "}" end
      defop(string.format("ptj@jfm@endadj@%d", n), table.concat(body))
    end
  end
  emit("")
  emit("% ---- char lists per class (U+XXXX; verification aid)")
  for _, n in ipairs(classes) do
    local chars = jfm[inv[n]].chars
    if chars and #chars > 0 then
      local hexes = {}
      for _, ch in ipairs(chars) do
        if type(ch) == "string" and ch:sub(1, 4) == "AJ1-" then
          hexes[#hexes + 1] = ch
        elseif type(ch) == "string" and PSEUDO[ch] then
          hexes[#hexes + 1] = ch
        elseif type(ch) == "number" then
          hexes[#hexes + 1] = "U+" .. hexn(ch)
        else
          hexes[#hexes + 1] = "U+" .. hexn(U.byte(ch, 1) or 0)
        end
      end
      defop(string.format("ptj@jfm@chars@%d", n), table.concat(hexes, " "))
    end
  end
  emit("")
  emit("% ---- char -> class dispatch (single code points), sorted")
  local cps = {}
  for cp in pairs(single) do cps[#cps + 1] = cp end
  table.sort(cps)
  for _, cp in ipairs(cps) do
    defop(string.format("ptj@jfm@cls@%s", hexn(cp)), tostring(single[cp]))
  end
  emit("")
  emit("% ---- multi-codepoint sequences (combos) per class")
  for _, n in ipairs(classes) do
    local list = combos[n]
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
      defop(string.format("ptj@jfm@combo@%d", n), table.concat(items, " "))
    end
  end
  emit("% ---- Adobe-Japan1 glyph ids (not addressable under pdfTeX)")
  for _, n in ipairs(classes) do
    local list = ajones[n]
    if list then
      table.sort(list)
      local items = {}
      for _, gid in ipairs(list) do items[#items + 1] = "{" .. tostring(gid) .. "}" end
      defop(string.format("ptj@jfm@ajone@%d", n), table.concat(items))
    end
  end
  emit("% ---- pseudo chars")
  local pnames = {}
  for nm in pairs(pseudos) do pnames[#pnames + 1] = nm end
  table.sort(pnames)
  for _, nm in ipairs(pnames) do
    defop(string.format("ptj@jfm@pseudo@%s", nm), tostring(pseudos[nm]))
  end
  emit("")
  emit("% ---- pairs: glue \\ptj@pairfields{nat}{stretch}{shrink}{ratio}")
  emit("% ----   {stretch-priority}{shrink-priority}{kanjiskip-natural-flag}")
  emit("% ----   {kanjiskip-stretch}{kanjiskip-shrink}; kern \\ptj@pairkern{nat}{ratio}")
  local pair_count = 0
  for _, f in ipairs(classes) do
    local v = jfm[inv[f]]
    local rows = {}
    for t, g in pairs(v.glue or {}) do
      if map[t] then rows[#rows + 1] = { map[t], "glue", g } end
    end
    for t, k in pairs(v.kern or {}) do
      if map[t] and not (v.glue and v.glue[t]) then rows[#rows + 1] = { map[t], "kern", k } end
    end
    table.sort(rows, function(a, b) return a[1] < b[1] end)
    for _, r in ipairs(rows) do
      local t, kind, g = r[1], r[2], r[3]
      if kind == "glue" then
        local ratio = g.ratio
        if ratio == nil then ratio = 0.5 end
        local pri = g.priority or { 0, 0 }
        if type(pri) == "number" then pri = { pri, pri } end
        emit(string.format(
          "\\expandafter\\def\\csname ptj@jfm@pair@%d@%d\\endcsname{\\ptj@pairfields{%s}{%s}{%s}{%s}{%d}{%d}{%d}{%d}{%d}}",
          f, t, num(g[1] or 0), num(g[2] or 0), num(g[3] or 0), num(ratio),
          pri[1] or 0, pri[2] or 0, g.kanjiskip_natural or 0,
          g.kanjiskip_stretch or 0, g.kanjiskip_shrink or 0))
      else
        local nat, ratio = g, 0.5
        if type(g) == "table" then nat = g[1] or 0; ratio = g[2] or 0.5 end
        emit(string.format(
          "\\expandafter\\def\\csname ptj@jfm@pair@%d@%d\\endcsname{\\ptj@pairkern{%s}{%s}}",
          f, t, num(nat), num(ratio)))
      end
      pair_count = pair_count + 1
    end
  end
  emit("")
  emit("%% end of ptjfm-" .. name .. ".def")
  local text = table.concat(out, "\n") .. "\n"
  local fp = assert(io.open(o.out, "wb"))
  fp:write(text)
  fp:close()
  local nchars = 0
  for _ in pairs(single) do nchars = nchars + 1 end
  return { classes = #classes, chars = nchars, pairs = pair_count, bytes = #text }
end

if PDFTEXJA_JFMCONV_LIBRARY then
  return { generate = generate, version = VERSION, find_jfm = find_jfm }
end

-- ------------------------------ CLI -----------------------------------------
local opts = {}
for _, a in ipairs(arg) do
  if a == "--version" then print("pdftexja-jfmconv.lua " .. VERSION); os.exit(0)
  elseif a:sub(1, 6) == "--jfm=" then opts.jfm = a:sub(7)
  elseif a:sub(1, 7) == "--name=" then opts.name = a:sub(8)
  elseif a:sub(1, 6) == "--pre=" then opts.pre = a:sub(7)
  elseif a:sub(1, 6) == "--out=" then opts.out = a:sub(7)
  else io.stderr:write("pdftexja-jfmconv.lua: unknown argument " .. a .. "\n"); os.exit(1)
  end
end
if not opts.jfm then
  io.stderr:write("usage: texlua pdftexja-jfmconv.lua --jfm=<file|name> [--name=<name>] [--pre=<lua>] [--out=<file>]\n")
  os.exit(1)
end
local path = find_jfm(opts.jfm)
if not path then io.stderr:write("cannot find JFM " .. opts.jfm .. "\n"); os.exit(1) end
opts.name = opts.name or (path:match("jfm%-([^/]*)%.lua$") or opts.jfm)
opts.out = opts.out or ("ptjfm-" .. opts.name .. ".def")
opts.jfm = path
local ok, r = pcall(generate, opts)
if not ok then io.stderr:write("pdftexja-jfmconv.lua: " .. tostring(r) .. "\n"); os.exit(1) end
io.stderr:write(string.format("pdftexja-jfmconv.lua %s: wrote %s (classes %d, chars %d, pairs %d, %d bytes)\n",
  VERSION, opts.out, r.classes, r.chars, r.pairs, r.bytes))
