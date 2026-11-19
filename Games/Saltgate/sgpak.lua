-- sgpak.lua
-- Reads saltgate.pak (made by tools/saltgate/pack.mjs): the game's code and content in one compressed file, inflated
-- into memory at boot. Nothing is unpacked to disk. mount() gives an environment whose fs answers for the packed files
-- from memory (and for everything else from the real disk) and whose require loads packed modules from memory.
--
--   local pak = require("sgpak")   (or dofile)
--   local files, err = pak.read("saltgate.pak", { fs = fs, yield = function(done, total) end })
--   local env = pak.mount(files, { fs = fs, env = _ENV, require = require })
--   env.require("sg.core.app").main(args)
--
-- Format: "SGPAK1 <payload bytes>\n", then the payload as raw deflate (RFC 1951). Payload: one "path<TAB>bytes\n"
-- line a file, an empty line, then the files one after another. Lua files are minified with every line break kept,
-- so the line numbers in a crash trace are the readable source's.

local M = {}

local byte, char, sub = string.byte, string.char, string.sub
local unpack_ = rawget(_G, "unpack") or table.unpack

local P2 = {}
for i = 0, 31 do P2[i] = 2 ^ i end

-- ---------------------------------------------------------------- inflate

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163,
  195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049,
  3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CL_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }
local FAST = 9 -- codes up to this long are found with one table lookup; longer ones bit by bit

--- A Huffman decoder from code lengths (lengths[0..n-1]): { fast = { [bits] = sym * 16 + len }, count, symbols }.
local function huffman(lengths, n)
  local count, offs, symbols = {}, {}, {}
  for l = 0, 15 do count[l] = 0 end
  for s = 0, n - 1 do count[lengths[s] or 0] = count[lengths[s] or 0] + 1 end
  count[0] = 0
  offs[1] = 0
  for l = 1, 14 do offs[l + 1] = offs[l] + count[l] end
  for s = 0, n - 1 do
    local l = lengths[s] or 0
    if l > 0 then symbols[offs[l]] = s; offs[l] = offs[l] + 1 end
  end
  -- the table for short codes, indexed by the code's bits as they come off the stream (reversed)
  local fast = {}
  local code, next_ = 0, {}
  for l = 1, 15 do code = (code + count[l - 1]) * 2; next_[l] = code end
  for s = 0, n - 1 do
    local l = lengths[s] or 0
    if l > 0 then
      local c = next_[l]
      next_[l] = c + 1
      if l <= FAST then
        local r = 0
        for _ = 1, l do r = r * 2 + c % 2; c = (c - c % 2) / 2 end
        local step, e = P2[l], s * 16 + l
        for k = r, P2[FAST] - 1, step do fast[k] = e end
      end
    end
  end
  return { fast = fast, count = count, symbols = symbols }
end

local FIXED_LIT, FIXED_DIST
local function fixedTables()
  if FIXED_LIT then return FIXED_LIT, FIXED_DIST end
  local l = {}
  for s = 0, 143 do l[s] = 8 end
  for s = 144, 255 do l[s] = 9 end
  for s = 256, 279 do l[s] = 7 end
  for s = 280, 287 do l[s] = 8 end
  local d = {}
  for s = 0, 29 do d[s] = 5 end
  FIXED_LIT, FIXED_DIST = huffman(l, 288), huffman(d, 30)
  return FIXED_LIT, FIXED_DIST
end

--- Inflate raw deflate data from data[start..]; returns the output as a string, or nil and an error. yield(bytesOut)
-- is called now and then (every few thousand symbols) so a long inflate can let the computer breathe.
function M.inflate(data, start, yield)
  local pos = start or 1
  local buf, cnt = 0, 0 -- the bit buffer and how many bits are in it
  local out, n = {}, 0  -- output bytes
  local pieces = {}     -- the output as strings, made at the end

  local function need(k)
    while cnt < k do
      local b = byte(data, pos) or 0
      pos = pos + 1
      buf = buf + b * P2[cnt]
      cnt = cnt + 8
    end
  end
  local function bits(k)
    if cnt < k then need(k) end
    local p = P2[k]
    local v = buf % p
    buf = (buf - v) / p
    cnt = cnt - k
    return v
  end
  local function decode(h)
    if cnt < 15 then need(15) end
    local e = h.fast[buf % 512]
    if e then
      local l = e % 16
      local p = P2[l]
      buf = (buf - buf % p) / p
      cnt = cnt - l
      return (e - l) / 16
    end
    -- a long code: canonical decoding one bit at a time (as zlib's puff.c)
    local count, symbols = h.count, h.symbols
    local code, first, index = 0, 0, 0
    for l = 1, 15 do
      local b = buf % 2
      buf = (buf - b) / 2
      cnt = cnt - 1
      code = code + b
      local c = count[l]
      if code - c < first then return symbols[index + code - first] end
      index = index + c
      first = (first + c) * 2
      code = code * 2
    end
    error("bad code in saltgate.pak")
  end

  local symbolsSinceYield = 0
  local final = 0
  while final == 0 do
    final = bits(1)
    local kind = bits(2)
    if kind == 0 then
      -- stored: to a byte boundary, then LEN, NLEN and the bytes
      local drop = cnt % 8
      bits(drop)
      local l = bits(16)
      bits(16)
      -- what is left in the bit buffer is whole bytes of the block
      while l > 0 and cnt >= 8 do n = n + 1; out[n] = bits(8); l = l - 1 end
      for k = 0, l - 1 do n = n + 1; out[n] = byte(data, pos + k) end
      pos = pos + l
    elseif kind == 3 then
      return nil, "bad block in saltgate.pak"
    else
      local lit, dist
      if kind == 1 then
        lit, dist = fixedTables()
      else
        local hlit, hdist, hclen = bits(5) + 257, bits(5) + 1, bits(4) + 4
        local cl = {}
        for k = 1, 19 do cl[CL_ORDER[k]] = 0 end
        for k = 1, hclen do cl[CL_ORDER[k]] = bits(3) end
        local clh = huffman(cl, 19)
        local lengths, k = {}, 0
        while k < hlit + hdist do
          local s = decode(clh)
          if s < 16 then lengths[k] = s; k = k + 1
          else
            local rep, v = 0, 0
            if s == 16 then
              if k == 0 then return nil, "bad lengths in saltgate.pak" end
              v, rep = lengths[k - 1], 3 + bits(2)
            elseif s == 17 then rep = 3 + bits(3)
            else rep = 11 + bits(7) end
            for _ = 1, rep do lengths[k] = v; k = k + 1 end
          end
        end
        local ll, dl = {}, {}
        for s = 0, hlit - 1 do ll[s] = lengths[s] end
        for s = 0, hdist - 1 do dl[s] = lengths[hlit + s] end
        lit, dist = huffman(ll, hlit), huffman(dl, hdist)
      end
      while true do
        local s = decode(lit)
        if s < 256 then
          n = n + 1
          out[n] = s
        elseif s == 256 then
          break
        else
          s = s - 256
          local l = LEN_BASE[s]
          local x = LEN_EXTRA[s]
          if x > 0 then l = l + bits(x) end
          local ds = decode(dist) + 1
          local d = DIST_BASE[ds]
          x = DIST_EXTRA[ds]
          if x > 0 then d = d + bits(x) end
          local from = n - d
          for k = 1, l do out[n + k] = out[from + k] end
          n = n + l
        end
        symbolsSinceYield = symbolsSinceYield + 1
        if symbolsSinceYield >= 8192 then
          symbolsSinceYield = 0
          if yield then yield(n) end
        end
      end
    end
  end
  -- the bytes into a string, 4 KiB at a time
  for i = 1, n, 4096 do
    local j = i + 4095
    if j > n then j = n end
    pieces[#pieces + 1] = char(unpack_(out, i, j))
  end
  if yield then yield(n) end
  return table.concat(pieces)
end

-- ---------------------------------------------------------------- the pack

--- The pack's files { [path] = bytes } from a pak's bytes, or nil, err.
function M.unpack(pak, yield)
  local size, at = pak:match("^SGPAK1 (%d+)\n()")
  if not size then return nil, "not a SALTGATE pack" end
  local payload, err = M.inflate(pak, at, yield)
  if not payload then return nil, err end
  if #payload ~= tonumber(size) then
    return nil, "saltgate.pak is damaged (" .. #payload .. " bytes inflated, " .. size .. " expected)"
  end
  local files, order = {}, {}
  local headerEnd = payload:find("\n\n", 1, true)
  if not headerEnd then return nil, "saltgate.pak has no file list" end
  local p = headerEnd + 2
  for path, bytes in payload:sub(1, headerEnd):gmatch("([^\t\n]+)\t(%d+)\n") do
    local b = tonumber(bytes)
    files[path] = sub(payload, p, p + b - 1)
    order[#order + 1] = path
    p = p + b
  end
  if p ~= #payload + 1 then return nil, "saltgate.pak's file list does not match its contents" end
  return files, order
end

--- Read and unpack a pak file. opts: fs, yield(bytesOut, totalBytes).
function M.read(path, opts)
  opts = opts or {}
  local fs_ = opts.fs or rawget(_G, "fs")
  local h = fs_.open(path, "rb")
  if not h then return nil, "cannot open " .. path end
  local pak = h.readAll()
  h.close()
  if not pak then return nil, path .. " is empty" end
  local total = tonumber(pak:match("^SGPAK1 (%d+)\n")) or 1
  local yield = opts.yield and function(done) opts.yield(done, total) end
  return M.unpack(pak, yield)
end

-- ---------------------------------------------------------------- the file system and require

local function clean(path)
  path = tostring(path):gsub("\\", "/")
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then parts[#parts] = nil
    elseif part ~= "." and part ~= "" then parts[#parts + 1] = part end
  end
  return table.concat(parts, "/")
end
M.clean = clean

--- A read handle on a string, like fs.open's.
local function handle(data, binary)
  local p = 1
  local h = {}
  function h.readAll()
    if p > #data then return binary and nil or "" end
    local s = sub(data, p)
    p = #data + 1
    return s
  end
  function h.readLine(keep)
    if p > #data then return nil end
    local e = data:find("\n", p, true)
    local s
    if e then s = sub(data, p, keep and e or e - 1); p = e + 1
    else s = sub(data, p); p = #data + 1 end
    return s
  end
  function h.read(count)
    if p > #data then return nil end
    if count == nil then
      local b = byte(data, p)
      p = p + 1
      if binary then return b end
      return char(b)
    end
    local s = sub(data, p, p + count - 1)
    p = p + count
    return s
  end
  function h.seek() return nil, "not supported" end
  function h.close() p = #data + 1 end
  return h
end

--- An fs that answers for the packed files from memory, and passes everything else to the real one. Packed files are
-- read-only.
function M.fs(files, realFs)
  local dirs = { [""] = {} }
  for path in pairs(files) do
    local parent, name = "", nil
    for part in path:gmatch("[^/]+") do
      if name then
        local d = parent == "" and name or parent .. "/" .. name
        if not dirs[d] then dirs[d] = {}; dirs[parent][name] = true end
        parent = d
      end
      name = part
    end
    dirs[parent][name] = true
  end
  local vfs = {}
  for k, v in pairs(realFs) do vfs[k] = v end
  local function packed(p) return files[p] ~= nil or (p ~= "" and dirs[p] ~= nil) end
  function vfs.exists(path)
    local p = clean(path)
    return packed(p) or realFs.exists(path)
  end
  function vfs.isDir(path)
    local p = clean(path)
    if files[p] then return false end
    if dirs[p] and p ~= "" then return true end
    return realFs.isDir(path)
  end
  function vfs.isReadOnly(path)
    if packed(clean(path)) then return true end
    return realFs.isReadOnly(path)
  end
  function vfs.getSize(path)
    local p = clean(path)
    if files[p] then return #files[p] end
    return realFs.getSize(path)
  end
  function vfs.list(path)
    local p = clean(path)
    local seen, out = {}, {}
    if dirs[p] then
      for name in pairs(dirs[p]) do seen[name] = true; out[#out + 1] = name end
    end
    if realFs.exists(path) and realFs.isDir(path) then
      for _, name in ipairs(realFs.list(path)) do
        if not seen[name] then out[#out + 1] = name end
      end
    elseif not dirs[p] then
      return realFs.list(path) -- the real error
    end
    table.sort(out)
    return out
  end
  function vfs.open(path, mode)
    local p = clean(path)
    if files[p] and (mode == "r" or mode == "rb") then return handle(files[p], mode == "rb") end
    return realFs.open(path, mode)
  end
  return vfs
end

--- An environment for the game: the program's own globals, with an fs over the pack and a require that loads packed
-- modules ("a.b" -> a/b.lua or a/b/init.lua) from memory, each run in this environment with the chunk name of its
-- file ("@sg/core/app.lua"), so errors and traces name the readable source's file and line. Anything not in the pack
-- (lib.crashreport, the Roger runtime) goes to the program's own require. opts: fs, env (the program's _ENV),
-- require, load.
function M.mount(files, opts)
  local realFs = opts.fs
  local base = opts.env
  local env = {}
  for k, v in pairs(_G) do env[k] = v end
  for k, v in pairs(base) do env[k] = v end -- shell, multishell, require ... from the program's own environment
  local outerRequire = opts.require or base.require
  -- CC's load takes source and an environment; plain Lua 5.1's does not (loadstring and setfenv there)
  local load_ = opts.load or function(src, name, mode, e)
    local ok, fn, err = pcall(load, src, name, mode, e)
    if ok and type(fn) == "function" then return fn end
    local ls, sf = rawget(_G, "loadstring"), rawget(_G, "setfenv")
    if ls and sf then
      fn, err = ls(src, name)
      if fn then sf(fn, e) end
      return fn, err
    end
    return nil, ok and err or fn
  end
  local loaded = {}
  local sentinel = {}
  local function find(name)
    local p = name:gsub("%.", "/")
    if files[p .. ".lua"] then return p .. ".lua" end
    if files[p .. "/init.lua"] then return p .. "/init.lua" end
  end
  local function require_(name)
    if type(name) ~= "string" then error("bad argument #1 to 'require' (string expected)", 2) end
    local have = loaded[name]
    if have == sentinel then error("loop or previous error loading module '" .. name .. "'", 2) end
    if have ~= nil then return have end
    local path = find(name)
    if not path then return outerRequire(name) end
    local fn, err = load_(files[path], "@" .. path, "t", env)
    if not fn then error(err, 0) end
    loaded[name] = sentinel
    local ok, res = pcall(fn, name, path)
    if not ok then loaded[name] = nil; error(res, 0) end
    if res == nil then res = true end
    loaded[name] = res
    return res
  end
  env.fs = M.fs(files, realFs)
  env.require = require_
  env.package = { loaded = loaded, path = base.package and base.package.path or "", preload = {},
    searchers = base.package and base.package.loaders or {}, config = "/\n;\n?\n!\n-" }
  env._G = env
  env._ENV = env
  setmetatable(env, { __index = _G })
  return env
end

return M
