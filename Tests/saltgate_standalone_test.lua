-- saltgate_standalone_test.lua
-- SALTGATE installed on its own (the Pastebin installer) and kept up to date by Shared/lib/standalone_update.lua,
-- against a pretend GitHub and a pretend disk: a fresh install, an update from an older commit (a file renamed, one
-- dropped, the settings and the save kept), a download that fails halfway (nothing changes), a staging folder left by
-- a computer turned off mid-download, no http, the rate limit (it waits longer), the off switch, and how often it asks.
-- And the repo itself: every path the standalone manifest lists exists, and so do the 8 paths the published installer
-- (pastebin Ri6djbYq, Games/Saltgate/saltgate_install.lua) fetches from main, which every future install starts from.

local t = require("testing")
local kit = require("saltgate_testkit")

local GAME = kit.root()
local REPO = GAME:gsub("/?Games/Saltgate$", "")
if REPO == "" then REPO = "." end
local up = dofile(REPO .. "/Shared/lib/standalone_update.lua")

local function readFile(path)
  local fs_ = rawget(_G, "fs")
  if fs_ and fs_.open then
    if not fs_.exists(path) then return nil end
    local h = fs_.open(path, "rb")
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

-- ---------------------------------------------------------------- a pretend disk and a pretend GitHub

local function disk(free)
  local files, dirs = {}, { [""] = true }
  local d = {}
  local function norm(p) return (p:gsub("^/+", ""):gsub("/+$", "")) end
  function d.exists(p) p = norm(p) return files[p] ~= nil or dirs[p] ~= nil end
  function d.isDir(p) return dirs[norm(p)] ~= nil end
  function d.getDir(p) return (norm(p):match("^(.*)/[^/]*$") or "") end
  function d.makeDir(p)
    p = norm(p)
    local acc = ""
    for part in p:gmatch("[^/]+") do acc = acc == "" and part or acc .. "/" .. part dirs[acc] = true end
  end
  function d.open(p, mode)
    p = norm(p)
    if mode:sub(1, 1) == "r" then
      local s = files[p]
      if not s then return nil end
      return { readAll = function() return s end, close = function() end }
    end
    if not dirs[d.getDir(p)] then return nil, "/" .. p .. ": No such directory" end
    local parts = {}
    return { write = function(s) parts[#parts + 1] = s end, close = function() files[p] = table.concat(parts) end }
  end
  function d.delete(p)
    p = norm(p)
    files[p] = nil
    dirs[p] = nil
    for k in pairs(files) do if k:sub(1, #p + 1) == p .. "/" then files[k] = nil end end
    for k in pairs(dirs) do if k:sub(1, #p + 1) == p .. "/" then dirs[k] = nil end end
  end
  function d.move(a, b)
    a, b = norm(a), norm(b)
    if files[b] then error("/" .. b .. ": File exists", 0) end
    files[b], files[a] = files[a], nil
  end
  function d.getFreeSpace()
    local used = 0
    for _, s in pairs(files) do used = used + math.max(500, #s) end
    return (free or 1000000) - used
  end
  d.files = files
  return d
end

local SHA_A = string.rep("a", 40)
local SHA_B = string.rep("b", 40)

--- A pretend GitHub: commits[sha] = { [repo path] = contents }; main = sha. Calls are counted; fail(url) can refuse.
local function github(commits)
  local gh = { main = SHA_A, calls = 0, fail = nil, code = nil }
  local function answer(code, body)
    return { getResponseCode = function() return code end, readAll = function() return body end, close = function() end }
  end
  gh.http = {
    get = function(url)
      gh.calls = gh.calls + 1
      if gh.fail then
        local why, code = gh.fail(url)
        if why then
          if code then return nil, why, answer(code, "") end
          return nil, why
        end
      end
      if url:match("commits/main$") then return answer(200, gh.main) end
      local sha, path = url:match("/(%x+)/(.+)$")
      local c = sha and commits[sha]
      if c and c[path] then return answer(200, c[path]) end
      return nil, "Not Found", answer(404, "")
    end,
  }
  return gh
end

local function pak(body)
  local b = "SGPAK1 3\n" .. body
  return b .. "\nSGEND " .. #b .. "\n"
end
local PAK = pak("xyz")
local function manifestText(extra)
  return table.concat({
    "program saltgate",
    "file Games/Saltgate/saltgate.pak saltgate.pak",
    "file Games/Saltgate/saltgate.lua saltgate.lua",
    "keep Games/Saltgate/saltgate_settings.lua saltgate_settings.lua",
    extra or "",
  }, "\n")
end

local function commitsAB()
  return {
    [SHA_A] = {
      ["Games/Saltgate/standalone.txt"] = manifestText("file Games/Saltgate/CREDITS_old.txt CREDITS_old.txt\nfile Games/Saltgate/gone.lua gone.lua"),
      ["Games/Saltgate/saltgate.pak"] = PAK,
      ["Games/Saltgate/saltgate.lua"] = "return 'A'",
      ["Games/Saltgate/saltgate_settings.lua"] = "return { sound = true }",
      ["Games/Saltgate/CREDITS_old.txt"] = "credits",
      ["Games/Saltgate/gone.lua"] = "return 1",
    },
    [SHA_B] = {
      -- CREDITS_old.txt renamed to CREDITS.txt; gone.lua dropped
      ["Games/Saltgate/standalone.txt"] = manifestText("file Games/Saltgate/CREDITS.txt CREDITS.txt"),
      ["Games/Saltgate/saltgate.pak"] = pak("new"),
      ["Games/Saltgate/saltgate.lua"] = "return 'B'",
      ["Games/Saltgate/saltgate_settings.lua"] = "return { sound = true, new = 1 }",
      ["Games/Saltgate/CREDITS.txt"] = "credits",
    },
  }
end

local function setup(opts)
  opts = opts or {}
  local d = disk(opts.free)
  local gh = github(opts.commits or commitsAB())
  local clock = 1000000
  local settingsT = { values = opts.settings or {} }
  function settingsT.get(k) return settingsT.values[k] end
  local o = up.options("Games/Saltgate/standalone.txt", "saltgate", {
    fs = d, http = gh.http, settings = settingsT, now = function() return clock end, sleep = function() end,
  })
  return { d = d, gh = gh, o = o, tick = function(s) clock = clock + s end }
end

t.test("standalone: the manifest is read, and a bad one refused", function()
  local m = up.parse(manifestText("file Shared/lib/crashreport.lua lib/crashreport.lua"))
  t.eq(m.program, "saltgate")
  t.eq(#m.files, 4)
  t.eq(m.files[3].keep, true, "the settings are a keep file")
  t.eq(m.files[4].to, "lib/crashreport.lua")
  t.truthy(not up.parse("program x\n"), "no files")
  t.truthy(not up.parse("file a ../evil\n"), "no climbing out")
  t.truthy(not up.parse("file a x\nfile b x\n"), "two files to one place")
end)

t.test("standalone: a fresh install is every listed file, at main's commit", function()
  local s = setup()
  local commit = up.install(s.o)
  t.eq(commit, SHA_A)
  t.eq(s.d.files["saltgate.lua"], "return 'A'")
  t.eq(s.d.files["saltgate.pak"], PAK)
  t.eq(s.d.files["CREDITS_old.txt"], "credits")
  t.eq(s.d.files["saltgate_settings.lua"], "return { sound = true }")
  t.truthy(not s.d.exists(".update"), "no staging folder left")
  local st = up.readState(s.o)
  t.eq(st.commit, SHA_A)
  t.eq(#st.files, 5)
end)

t.test("standalone: an older install updates: downloaded in the background, put in at the next start", function()
  local s = setup()
  up.install(s.o)
  s.d.files["saltgate_save2.dat"] = "money = 900"
  s.d.files["saltgate_settings.lua"] = "return { sound = false }" -- the player's own
  s.gh.main = SHA_B
  s.tick(3600)
  t.eq(up.check(s.o), "staged")
  t.eq(s.d.files["saltgate.lua"], "return 'A'", "nothing changes while the game runs")
  t.truthy(s.d.exists(".update/ready.dat"))
  t.eq(up.check(s.o), "checked recently", "once, not again at once")
  local commit = up.applyStaged(s.o)
  t.eq(commit, SHA_B)
  t.eq(s.d.files["saltgate.lua"], "return 'B'")
  t.eq(s.d.files["saltgate.pak"], pak("new"))
  t.eq(s.d.files["CREDITS.txt"], "credits", "the renamed file under its new name")
  t.truthy(not s.d.exists("CREDITS_old.txt"), "and not under its old one")
  t.truthy(not s.d.exists("gone.lua"), "a file that left the list is gone")
  t.eq(s.d.files["saltgate_settings.lua"], "return { sound = false }", "the settings kept")
  t.eq(s.d.files["saltgate_save2.dat"], "money = 900", "the save kept")
  t.truthy(not s.d.exists(".update"))
  t.eq(up.readState(s.o).commit, SHA_B)
  t.eq(up.readState(s.o).previous, SHA_A)
  t.eq(up.applyStaged(s.o), nil, "nothing more to put in")
  s.tick(3600)
  t.eq(up.check(s.o), "current")
end)

t.test("standalone: an install from before the updater (no record at all) updates to main", function()
  local s = setup()
  -- what the first Pastebin installer left: the files, no record
  s.d.files["saltgate.lua"] = "return 'old'"
  s.d.files["saltgate_settings.lua"] = "return { mine = true }"
  s.gh.main = SHA_B
  t.eq(up.check(s.o), "staged")
  t.eq(up.applyStaged(s.o), SHA_B)
  t.eq(s.d.files["saltgate.lua"], "return 'B'")
  t.eq(s.d.files["saltgate_settings.lua"], "return { mine = true }")
end)

t.test("standalone: a download that fails halfway changes nothing, and a later check finishes it", function()
  local s = setup()
  up.install(s.o)
  s.gh.main = SHA_B
  s.tick(3600)
  s.gh.fail = function(url) if url:find("saltgate.pak", 1, true) then return "Connection reset" end end
  local r = up.check(s.o)
  t.truthy(r:find("failed", 1, true), r)
  t.truthy(not s.d.exists(".update"), "nothing staged")
  t.eq(s.d.files["saltgate.lua"], "return 'A'")
  t.eq(up.applyStaged(s.o), nil)
  s.gh.fail = nil
  s.tick(up.BACKOFF_MAX + 1)
  t.eq(up.check(s.o), "staged")
  t.eq(up.applyStaged(s.o), SHA_B)
end)

t.test("standalone: a staging folder the computer was turned off in the middle of is cleared, not used", function()
  local s = setup()
  up.install(s.o)
  s.d.makeDir(".update/files")
  s.d.files[".update/files/saltgate.lua"] = "return 'half'"
  t.eq(up.applyStaged(s.o), nil)
  t.truthy(not s.d.exists(".update"), "cleared")
  t.eq(s.d.files["saltgate.lua"], "return 'A'")
end)

t.test("standalone: a broken file from GitHub is never staged", function()
  local c = commitsAB()
  c[SHA_B]["Games/Saltgate/saltgate.lua"] = "this is not lua ((("
  local s = setup({ commits = c })
  up.install(s.o)
  s.gh.main = SHA_B
  s.tick(3600)
  local r = up.check(s.o)
  t.truthy(r:find("does not compile", 1, true), r)
  t.truthy(not s.d.exists(".update"))
end)

t.test("standalone: a pack or a file cut short is never staged", function()
  local c = commitsAB()
  local full = c[SHA_B]["Games/Saltgate/saltgate.pak"]
  c[SHA_B]["Games/Saltgate/saltgate.pak"] = full:sub(1, #full - 5)
  local s = setup({ commits = c })
  up.install(s.o)
  s.gh.main = SHA_B
  s.tick(3600)
  local r = up.check(s.o)
  t.truthy(r:find("cut short", 1, true), r)
  t.truthy(not s.d.exists(".update"))
  -- and any file whose answer is shorter than its Content-Length
  c[SHA_B]["Games/Saltgate/saltgate.pak"] = full
  local http0 = s.gh.http.get
  s.gh.http.get = function(url, ...)
    local h, e, f = http0(url, ...)
    if h and url:find("CREDITS", 1, true) then h.getResponseHeaders = function() return { ["Content-Length"] = "999" } end end
    return h, e, f
  end
  s.tick(up.BACKOFF_MAX + 1)
  r = up.check(s.o)
  t.truthy(r:find("cut short", 1, true), r)
  t.truthy(not s.d.exists(".update"))
end)

t.test("standalone: no http, the off switch, and the rate limit: it plays on and waits longer each time", function()
  local s = setup()
  up.install(s.o)
  s.gh.main = SHA_B
  s.tick(3600)
  local noHttp = up.options("Games/Saltgate/standalone.txt", "saltgate", { fs = s.d, http = false, settings = s.o.settings, now = s.o.now })
  noHttp.http = nil
  t.eq(up.check(noHttp), "no http")
  s.o.settings.values["saltgate.autoupdate"] = false
  t.eq(up.check(s.o), "off")
  s.o.settings.values["saltgate.autoupdate"] = nil
  s.gh.fail = function() return "Forbidden", 403 end
  local calls = s.gh.calls
  t.truthy(up.check(s.o):find("403", 1, true), "the rate limit")
  t.eq(s.gh.calls - calls, 1, "one call, not retried")
  local st = up.readState(s.o)
  t.truthy(st.backoffUntil and st.backoffUntil > s.o.now(), "it waits")
  local first = st.backoffUntil - s.o.now()
  t.eq(up.check(s.o), "waiting after a failure")
  s.tick(first + 1)
  up.check(s.o)
  local second = up.readState(s.o).backoffUntil - s.o.now()
  t.truthy(second > first, "longer the second time: " .. first .. " then " .. second)
  t.truthy(second <= up.BACKOFF_MAX)
  t.eq(s.d.files["saltgate.lua"], "return 'A'", "and the installed game is untouched")
  s.gh.fail = function() return "Could not connect" end -- GitHub down: no answer at all
  s.tick(up.BACKOFF_MAX + 1)
  t.truthy(up.check(s.o):find("failed", 1, true))
end)

t.test("standalone: not enough disk for the update: nothing staged", function()
  local s = setup({ free = 4200 })
  up.install(s.o)
  s.gh.main = SHA_B
  s.tick(3600)
  local r = up.check(s.o)
  t.truthy(r:find("disk space", 1, true), r)
  t.truthy(not s.d.exists(".update"))
end)

-- ---------------------------------------------------------------- the repo

t.test("standalone: every repo path the standalone manifest lists exists at HEAD", function()
  local text = readFile(GAME .. "/standalone.txt")
  t.truthy(text, "Games/Saltgate/standalone.txt")
  local m = assert(up.parse(text))
  t.eq(m.program, "saltgate")
  local missing = {}
  for _, f in ipairs(m.files) do
    if not readFile(REPO .. "/" .. f.from) then missing[#missing + 1] = f.from end
  end
  t.eq(#missing, 0, "missing: " .. table.concat(missing, ", "))
  -- and it carries everything the deploy index ships of the game (but the server's lockdown file)
  local ship = readFile(GAME .. "/startup.lua"):match("%-%-%s*manifest%-ship:%s*([^\n]+)")
  local froms = {}
  for _, f in ipairs(m.files) do froms[f.from] = true end
  local absent = {}
  for name in ship:gmatch("%S+") do
    if name ~= "vhcc_lockdown.txt" and not froms["Games/Saltgate/" .. name] then absent[#absent + 1] = name end
  end
  t.eq(#absent, 0, "shipped by the deploy index but not standalone: " .. table.concat(absent, ", "))
end)

t.test("standalone: the 8 files the published installer fetches from main exist and work", function()
  -- pastebin Ri6djbYq is never republished: these paths are how every future install starts
  local boot = {
    "Games/Saltgate/saltgate.pak", "Games/Saltgate/sgpak.lua", "Games/Saltgate/saltgate.lua",
    "Games/Saltgate/startup.lua", "Games/Saltgate/saltgate_settings.lua", "Games/Saltgate/CREDITS.txt",
    "Games/Saltgate/pine3d/LICENSE.txt", "Shared/lib/crashreport.lua",
  }
  local installer = readFile(GAME .. "/saltgate_install.lua")
  t.truthy(installer, "the installer is in the repo")
  local ls = rawget(_G, "loadstring") or load
  for _, path in ipairs(boot) do
    local data = readFile(REPO .. "/" .. path)
    t.truthy(data and #data > 0, path .. " exists")
    local short = path:gsub("^Games/Saltgate/", "")
    t.truthy(installer:find(short, 1, true), "the installer still lists " .. short)
    if path:match("%.lua$") then t.truthy(ls(data, "=" .. path), path .. " compiles") end
    if path:match("%.pak$") then
      t.truthy(data:match("^SGPAK1 %d+\n"), "the pak has the header the published installer checks")
      local n = data:match("\nSGEND (%d+)\n$")
      t.truthy(n and tonumber(n) == #data - #("\nSGEND " .. n .. "\n"), "and its length at the end")
    end
  end
  -- the bootstrap: the game fetches the updater from main when it has none
  t.truthy(readFile(REPO .. "/Shared/lib/standalone_update.lua"), "Shared/lib/standalone_update.lua")
  t.truthy(readFile(GAME .. "/saltgate.lua"):find("Shared/lib/standalone_update.lua", 1, true), "saltgate.lua fetches it")
end)
