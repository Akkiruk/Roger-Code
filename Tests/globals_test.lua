-- globals_test.lua
-- Every global a shipped file reads must be one something really defines, on every code path, not just the ones other tests run.
-- A gear shop build called shiftCounts on a line above its `local function shiftCounts`, so the call read a nil global and the
-- upkeep job crashed every 10 s in the real game. luac -p -l lists each GETGLOBAL and SETGLOBAL with its name, so this reads
-- that listing for every .lua file the installer ships (Apps, Games, Shared, System, Utilities) and fails on any name not below.
-- Needs desktop Lua with io.popen and luac beside lua (or LUAC set to its path). Under ComputerCraft it skips.
-- A file luac 5.1 cannot parse (goto, other 5.2 syntax) is reported as skipped, not failed: check-lua-no-goto.ps1 covers goto.

local t = require("testing")

-- Lua 5.1 standard globals CC:Tweaked keeps. Not here because the real server has none of them: collectgarbage
-- (docs/conformance/server-vs-emulator-2026-10-30.md in craftos-agent), module, newproxy, gcinfo.
local LUA = {
  "_G", "_VERSION", "assert", "coroutine", "debug", "dofile", "error", "getfenv", "getmetatable", "ipairs", "load",
  "loadfile", "loadstring", "math", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "select", "setfenv",
  "setmetatable", "string", "table", "tonumber", "tostring", "type", "unpack", "xpcall",
  -- Cobalt, CC:Tweaked's Lua, also has these from 5.2/5.3
  "bit32", "utf8", "rawlen",
}

-- CC:Tweaked 1.101.3, taken from craftos-agent's rom/cc-1.101.3
local CC = {
  -- Java side: the native APIs and the two strings the computer starts with
  "fs", "os", "term", "http", "peripheral", "redstone", "rs", "turtle", "pocket", "commands", "_HOST", "_CC_DEFAULT_SETTINGS",
  -- bios.lua sets these (exec only on command computers; bit is its stub for the old bit API)
  "write", "print", "printError", "read", "sleep", "exec", "bit",
  -- rom/apis/*.lua, loaded by the bios as globals
  "colors", "colours", "disk", "gps", "help", "io", "keys", "paintutils", "parallel", "rednet", "settings", "textutils",
  "vector", "window",
  -- rom/programs/shell.lua gives each program these in its own env, and arg holds its arguments
  "shell", "multishell", "require", "package", "arg",
}

-- Mods in the pack that add a global API (vhcctweaks: ILuaAPI getNames in CCVaultAPI.java and VHCCTweaksAPI.java)
local MODS = {
  "ccvault", -- vhcctweaks: tokens and the bank, docs/CCVAULT_API.md
  "vhcc",    -- vhcctweaks: the computer's local files and the pack's own calls
}

-- Globals the codebase sets on purpose. A file that writes a global not listed here fails, since a stray write is the other
-- half of this bug: Task Master set screenWidth as a global and then drew with a local of the same name that stayed nil.
-- name = why
local OWN = {
}

-- Files left out of the check: vendored code nobody here writes. The Surface API copies (Games/*/surface) have no .lua so
-- are never read.
local VENDORED = {
}

local ROOTS = { "Apps", "Games", "Shared", "System", "Utilities" }

local known = {}
for _, list in ipairs({ LUA, CC, MODS }) do
  for _, name in ipairs(list) do known[name] = true end
end
for name in pairs(OWN) do known[name] = true end
local vendored = {}
for _, path in ipairs(VENDORED) do vendored[path] = true end

local windows = package.config:sub(1, 1) == "\\"
local root = (arg and arg[0] or ""):match("^(.*)[/\\]Tests[/\\]run%.lua$") or "."

local function quote(path)
  return '"' .. path .. '"'
end

--- Run a shell command and give back its output lines. cmd.exe drops the first and last quote of a command line, hence the
--- extra pair round the whole thing on Windows.
local function lines(command)
  if windows then command = '"' .. command .. '"' end
  local pipe = io.popen(command .. " 2>&1")
  if not pipe then return nil end
  local out = {}
  for line in pipe:lines() do out[#out + 1] = line end
  pipe:close()
  return out
end

local function findLuac()
  local env = os.getenv and os.getenv("LUAC")
  if env and env ~= "" then return env end
  local interpreter = arg and arg[-1]
  if interpreter then
    local dir, name = interpreter:match("^(.-)([^/\\]+)$")
    local luacName = name and name:gsub("^lua", "luac", 1)
    if luacName and luacName ~= name then
      local candidate = dir .. luacName
      local probe = lines(quote(candidate) .. " -v")
      if probe and probe[1] and probe[1]:match("^Lua 5%.1") then return candidate end
    end
  end
  for _, candidate in ipairs({ "luac5.1", "luac" }) do
    local probe = lines(candidate .. " -v")
    if probe and probe[1] and probe[1]:match("^Lua 5%.1") then return candidate end
  end
  return nil
end

--- Every shipped .lua file, as a path from the repo root with forward slashes, sorted.
local function shippedFiles()
  local files = {}
  for _, top in ipairs(ROOTS) do
    local dir = root .. "/" .. top
    local found
    if windows then
      found = lines("dir /s /b /a-d " .. quote((dir .. "/*.lua"):gsub("/", "\\")))
    else
      found = lines("find " .. quote(dir) .. " -type f -name '*.lua'")
    end
    for _, path in ipairs(found or {}) do
      path = path:gsub("\\", "/")
      local at = path:find("/" .. top .. "/", 1, true)
      if at and path:match("%.lua$") then
        local relative = path:sub(at + 1)
        if not vendored[relative] then files[#files + 1] = relative end
      end
    end
  end
  table.sort(files)
  return files
end

--- The globals some files read and write: path -> { reads = name -> first line, writes = ... }. One luac lists a batch of
--- files, each function headed by the file it is in. nil and luac's message when luac cannot parse one of them.
local function globalsOf(luac, batch)
  local args = {}
  for i, relative in ipairs(batch) do args[i] = quote(root .. "/" .. relative) end
  local out = lines(quote(luac) .. " -p -l " .. table.concat(args, " "))
  local byPath, prefix = {}, root .. "/"
  for _, relative in ipairs(batch) do byPath[relative] = { reads = {}, writes = {} } end
  local current, parsed = nil, false
  for _, line in ipairs(out or {}) do
    local path = line:match("^main <(.-):%d+,%d+>") or line:match("^function <(.-):%d+,%d+>")
    if path then
      parsed = true
      if path:sub(1, #prefix) == prefix then path = path:sub(#prefix + 1) end
      current = byPath[path]
      if current then current.seen = true end
    end
    local at, op, name = line:match("^%s*%d+%s+%[(%d+)%]%s+([GS]ETGLOBAL)%s.-; (.+)$")
    if op and current then
      local into = op == "GETGLOBAL" and current.reads or current.writes
      at = tonumber(at)
      if not into[name] or at < into[name] then into[name] = at end
    end
  end
  if not parsed then return nil, table.concat(out or {}, " ") end
  for _, globals in pairs(byPath) do
    if not globals.seen then globals.skip = "luac listed nothing for it" end
  end
  return byPath
end

if not (io and io.popen) then
  print("skip globals: no io.popen here (runs under desktop Lua only)")
  return
end

local luac = findLuac()
if not luac then
  t.test("globals: luac 5.1 found", function()
    error("no luac 5.1 beside " .. tostring(arg and arg[-1]) .. " or on PATH; set LUAC to its path")
  end)
  return
end

local files = shippedFiles()
t.test("globals: the shipped files are found", function()
  t.truthy(#files > 100, "found " .. #files .. " .lua files under " .. root)
end)

-- Forty files to a luac keeps the command line short of cmd.exe's limit. A batch that does not parse goes again a file at a
-- time, so only the file luac cannot read is skipped.
local listed = {}
for first = 1, #files, 40 do
  local batch = {}
  for i = first, math.min(first + 39, #files) do batch[#batch + 1] = files[i] end
  local found = globalsOf(luac, batch)
  if found then
    for path, globals in pairs(found) do listed[path] = globals end
  else
    for _, relative in ipairs(batch) do
      local one, err = globalsOf(luac, { relative })
      listed[relative] = one and one[relative] or { skip = err or "luac gave nothing" }
    end
  end
end

local skipped, checked, findings = {}, 0, {}
for _, relative in ipairs(files) do
  local globals = listed[relative]
  if globals.skip then
    skipped[#skipped + 1] = relative .. ": " .. globals.skip
  else
    checked = checked + 1
    local reads, writes = globals.reads, globals.writes
    for name, at in pairs(writes) do
      if not OWN[name] then
        findings[#findings + 1] = ("%s:%d sets global %s (make it local, or list it in OWN with why)"):format(relative, at, name)
      end
    end
    for name, at in pairs(reads) do
      -- A file may read a global it sets itself, even above the line that sets it
      if not known[name] and not writes[name] then
        findings[#findings + 1] = ("%s:%d reads global %s, which nothing defines"):format(relative, at, name)
      end
    end
  end
end
table.sort(findings)

for _, line in ipairs(skipped) do print("skip globals " .. line) end

t.test("globals: every global a shipped file reads or sets is a real one (" .. checked .. " files)", function()
  if #findings > 0 then error(#findings .. " unknown globals:\n     " .. table.concat(findings, "\n     "), 0) end
end)
