-- saltgate_pak_test.lua
-- saltgate.pak, what the deploy index ships of SALTGATE (tools/saltgate/pack.mjs makes it; sgpak.lua reads it at
-- boot): it inflates, it holds every file under sg/, content/, music/ and pine3d/ and nothing else, each one up to
-- date (a Lua file compiles to the same code as its readable source, on the same lines), and the environment it mounts
-- loads modules and content from memory with traces that name the readable file and line.
-- This fails while the pak is stale: run "node tools/saltgate/pack.mjs" and commit saltgate.pak.

local t = require("testing")
local kit = require("saltgate_testkit")
local pak = dofile(kit.root() .. "/sgpak.lua")

local ROOT = kit.root()
local ROOTS = { "sg", "content", "music", "pine3d" }

local function readFile(path)
  local fs_ = rawget(_G, "fs")
  if fs_ and fs_.open then
    local h = fs_.open(path, "rb")
    if not h then return nil end
    local s = h.readAll()
    h.close()
    return s or ""
  end
  local h = io.open(path, "rb")
  if not h then return nil end
  local s = h:read("*a")
  h:close()
  return s
end

--- Every file under dir, as paths relative to the game's folder.
local function listFiles(dir)
  local out = {}
  local fs_ = rawget(_G, "fs")
  if fs_ and fs_.list then
    local function walk(rel)
      for _, name in ipairs(fs_.list(ROOT .. "/" .. rel)) do
        local r = rel .. "/" .. name
        if fs_.isDir(ROOT .. "/" .. r) then walk(r) else out[#out + 1] = r end
      end
    end
    walk(dir)
    return out
  end
  local windows = package.config:sub(1, 1) == "\\"
  local cmd = windows and ('dir /s /b /a-d "' .. (ROOT .. "/" .. dir):gsub("/", "\\") .. '"')
    or ('find "' .. ROOT .. "/" .. dir .. '" -type f')
  local p = io.popen(cmd)
  for line in p:lines() do
    line = line:gsub("\\", "/")
    local at = line:find("/" .. dir .. "/", 1, true)
    if at then out[#out + 1] = line:sub(at + 1) end
  end
  p:close()
  return out
end

local function shipsInPak(rel)
  return not (rel:match("%.md$") or rel:match("%.bak$") or (rel:match("^pine3d/") and rel:match("%.txt$")))
end

local clock = rawget(_G, "os") and os.clock or function() return 0 end
local started = clock()
local yields = 0
local pakBytes = readFile(ROOT .. "/saltgate.pak") or ""
local files, order = pak.unpack(pakBytes, function() yields = yields + 1; t.breathe() end)
local inflateSeconds = clock() - started

t.test("pak: saltgate.pak inflates, and lets the computer breathe while it does", function()
  t.truthy(files, "inflated: " .. tostring(order))
  t.truthy(#order > 150, #order .. " files")
  t.truthy(yields > 10, "yielded " .. yields .. " times")
  print(string.format("     %d files inflated in %.2f s (plain Lua)", #order, inflateSeconds))
end)

local function sameCode(a, b, name)
  local ls = rawget(_G, "loadstring") or load
  local fa, ea = ls(a, "=" .. name)
  local fb, eb = ls(b, "=" .. name)
  if not fa then return false, "the source does not compile: " .. tostring(ea) end
  if not fb then return false, "the packed file does not compile: " .. tostring(eb) end
  local ok, da = pcall(string.dump, fa)
  if not ok then return true end -- no string.dump here: compiling is all that can be checked
  return da == string.dump(fb), "compiles differently from its source (run node tools/saltgate/pack.mjs)"
end

t.test("pak: every file is in it, up to date, and nothing else is", function()
  t.truthy(files, "inflated")
  local want = {}
  for _, dir in ipairs(ROOTS) do
    for _, rel in ipairs(listFiles(dir)) do
      if shipsInPak(rel) then want[rel] = true end
    end
  end
  local missing, extra, stale = {}, {}, {}
  for rel in pairs(want) do
    if not files[rel] then missing[#missing + 1] = rel end
  end
  for rel, packed in pairs(files) do
    if not want[rel] then
      extra[#extra + 1] = rel
    else
      local src = readFile(ROOT .. "/" .. rel)
      if rel:match("%.lua$") then
        local same, why = sameCode(src, packed, rel)
        if not same then stale[#stale + 1] = rel .. ": " .. why end
        -- the line numbers of a crash trace are the readable file's
        local _, a = src:gsub("\n", "")
        local _, b = packed:gsub("\n", "")
        if b > a then stale[#stale + 1] = rel .. ": more lines than its source" end
      elseif src ~= packed then
        stale[#stale + 1] = rel .. ": differs from its source"
      end
    end
    t.breathe()
  end
  table.sort(missing); table.sort(extra); table.sort(stale)
  t.eq(#missing, 0, "missing from the pak (run node tools/saltgate/pack.mjs): " .. table.concat(missing, ", "))
  t.eq(#extra, 0, "in the pak with no source: " .. table.concat(extra, ", "))
  t.eq(#stale, 0, "stale: " .. table.concat(stale, "; "))
end)

local function fakeFs()
  local disk = { ["saltgate_settings.lua"] = "return {}" }
  local real = {}
  function real.exists(p) return p == "" or disk[p] ~= nil end
  function real.isDir(p) return p == "" end
  function real.isReadOnly() return false end
  function real.getSize(p) return #(disk[p] or "") end
  function real.list(p) if p == "" or p == "/" then return { "saltgate_settings.lua" } end error("/" .. p .. ": Not a directory", 0) end
  function real.open(p, mode)
    if mode:sub(1, 1) == "w" then
      local parts = {}
      return { write = function(s) parts[#parts + 1] = s end, close = function() disk[p] = table.concat(parts) end }
    end
    if not disk[p] then return nil end
    local s = disk[p]
    return { readAll = function() return s end, close = function() end }
  end
  return real, disk
end

t.test("pak: the mounted game reads its files from memory and writes saves to the disk", function()
  t.truthy(files, "inflated")
  local real, disk = fakeFs()
  local env = pak.mount(files, { fs = real, env = {}, require = function(name) error("not packed: " .. name, 0) end })
  local vfs = env.fs
  t.truthy(vfs.exists("content/world"), "a packed folder")
  t.truthy(vfs.isDir("content/world"))
  t.truthy(vfs.exists("/content/world/map.txt"), "a packed file, with a leading slash")
  t.truthy(not vfs.isDir("content/world/map.txt"))
  t.truthy(vfs.isReadOnly("sg/core/app.lua"))
  t.truthy(vfs.exists("saltgate_settings.lua"), "the disk's own files too")
  local plugins = vfs.list("sg/plugins")
  t.truthy(#plugins >= 10, "the plugins: " .. table.concat(plugins, " "))
  t.eq(plugins[1], "a_world.lua")
  local root = vfs.list("")
  local names = " " .. table.concat(root, " ") .. " "
  t.truthy(names:find(" sg ") and names:find(" saltgate_settings.lua "), "the root holds both: " .. names)
  local h = vfs.open("content/world/map.txt", "r")
  t.eq(h.readAll(), files["content/world/map.txt"])
  h.close()
  local first = vfs.open("content/world/map.txt", "r").readLine()
  t.eq(first, files["content/world/map.txt"]:match("^[^\n]*"))
  local w = vfs.open("saltgate_save2.dat", "w")
  w.write("money = 5")
  w.close()
  t.eq(disk["saltgate_save2.dat"], "money = 5", "a save goes to the disk")
  t.eq(vfs.getSize("sg/core/app.lua"), #files["sg/core/app.lua"])
end)

t.test("pak: require loads packed modules in the game's environment, and a crash names the readable line", function()
  t.truthy(files, "inflated")
  local mine = {}
  for k, v in pairs(files) do mine[k] = v end
  mine["sg/boom.lua"] = "local x = 1\n\n\nerror('boom ' .. x)\n"
  mine["sg/seesfs.lua"] = "return { fs = fs, g = rawget(_G, 'fs'), name = ... }"
  local real = fakeFs()
  local outer = {}
  local env = pak.mount(mine, { fs = real, env = {}, require = function(name) outer[#outer + 1] = name; return { outer = name } end })
  local m = env.require("sg.seesfs")
  t.truthy(m.fs == env.fs and m.g == env.fs, "a module's fs (and _G.fs) is the pack's")
  t.eq(m.name, "sg.seesfs", "a module gets its name")
  t.truthy(env.require("sg.seesfs") == m, "loaded once")
  t.eq(env.require("lib.crashreport").outer, "lib.crashreport", "what is not packed goes to the program's require")
  local ok, err = pcall(env.require, "sg.boom")
  t.truthy(not ok)
  t.truthy(tostring(err):find("sg/boom.lua:4: boom 1", 1, true), tostring(err))
  -- the real thing: content through core/content.lua, and the music through its init.lua
  local contentLib = env.require("sg.core.content")
  local c = contentLib.new({})
  t.truthy(c:exists("world/map.txt"), "content/ through the pack")
  t.truthy(#c:list("story") > 20, "the jobs")
  local music = env.require("music")
  t.truthy(type(music) == "table", "music/init.lua")
  t.truthy(env.package.loaded["music.player"] ~= nil, "music.player came along")
end)
