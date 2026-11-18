-- core/save.lua
-- The save file, version 2: one table of sections, each owned by one part of the game, each with its own version and
-- its own migration. Reads version 1 saves (today's game) and turns them into version 2. Writes go to a temporary
-- file first, then replace the save, keeping the last good one as a backup. Pure apart from the fs it is given.
--
-- v2:
--   { version = 2, sections = { player = 1, story = 1, ... },     -- each section's own version
--     player = { money, x, z, h, health, district },
--     story = { done = { id = true }, flags = {}, mission = nil or a script's saveState, finished, ending },
--     world = { time, weather, unlocked = {} },
--     garage = { cars = {} },
--     activities = {},  progress = { stats = {}, achievements = {} },
--     settings = { tutorialDone, sound, music },
--     (a plugin's own section, registered with save.section) }
--
--   save.blank() -> a new v2 save
--   save.migrate(data) -> v2 save, or nil and why (a newer version than this game knows is refused, not damaged)
--   save.section(name, { version = n, blank = function() return {} end, migrate = function(old, from) return new end })
--   save.read(fs, path) -> v2 save (from the backup if the main file is bad), or a blank one and a note
--   save.write(fs, path, data)
--   save.toLegacy(v2) -> the v1 table today's game loads (until the game itself moves to v2)
--   save.fromLegacy(v1data, v2) -> v2 with today's game's fields put in

local M = {}

M.VERSION = 2

local sections = {
  player = { version = 1, blank = function() return { money = 0, health = 100 } end },
  story = { version = 1, blank = function() return { done = {}, flags = {}, finished = false } end },
  world = { version = 1, blank = function() return { time = 18, weather = "clear", unlocked = {} } end },
  garage = { version = 1, blank = function() return { cars = {} } end },
  activities = { version = 1, blank = function() return {} end },
  progress = { version = 1, blank = function() return { stats = {}, achievements = {} } end },
  settings = { version = 1, blank = function() return {} end },
}
local CORE = {}
for k in pairs(sections) do CORE[k] = true end

--- A plugin's own section (or a newer version of one). migrate(old, fromVersion) returns the section at version.
function M.section(name, def)
  if type(name) ~= "string" or type(def) ~= "table" or type(def.version) ~= "number" then
    error("save.section needs a name and { version, blank, migrate }", 2)
  end
  local old = sections[name]
  if old and not CORE[name] and old.owner ~= def.owner then error("save section '" .. name .. "' is registered twice", 2) end
  def.blank = def.blank or function() return {} end
  sections[name] = def
end

function M.sectionNames()
  local out = {}
  for k in pairs(sections) do out[#out + 1] = k end
  table.sort(out)
  return out
end

function M.blank()
  local data = { version = M.VERSION, sections = {} }
  for name, def in pairs(sections) do
    data[name] = def.blank()
    data.sections[name] = def.version
  end
  return data
end

--- Bring every section up to date: missing ones get their blank, older ones their migration.
local function settle(data)
  data.sections = data.sections or {}
  for name, def in pairs(sections) do
    local have = data.sections[name]
    if type(data[name]) ~= "table" then
      data[name] = def.blank()
      data.sections[name] = def.version
    elseif have == nil or have < def.version then
      if def.migrate then data[name] = def.migrate(data[name], have or 0) end
      data.sections[name] = def.version
    end
  end
  return data
end

--- Any save to v2.
function M.migrate(data)
  if type(data) ~= "table" then return nil, "not a save" end
  local v = data.version
  if v == nil or v == 1 then
    local out = M.blank()
    out.player.money = tonumber(data.money) or 0
    for _, id in ipairs(type(data.done) == "table" and data.done or {}) do
      if type(id) == "string" then out.story.done[id] = true end
    end
    out.story.finished = data.finished and true or false
    if out.story.finished then out.story.flags.act1Done = true end
    if type(data.stats) == "table" then
      for k, n in pairs(data.stats) do
        if type(n) == "number" then out.progress.stats[k] = n end
      end
    end
    out.settings.tutorialDone = data.tutorialDone and true or nil
    return settle(out)
  end
  if v == M.VERSION then return settle(data) end
  if type(v) == "number" and v > M.VERSION then return nil, "this save is from a newer SALTGATE (version " .. v .. ")" end
  return nil, "unknown save version " .. tostring(v)
end

-- ---------------------------------------------------------------- files

local function serialise(data)
  local tu = rawget(_G, "textutils")
  if tu and tu.serialise then return tu.serialise(data) end
  -- outside CC (tests): a plain Lua table constructor
  local function ser(v)
    local t = type(v)
    if t == "table" then
      local parts = {}
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for _, k in ipairs(keys) do
        local key = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
        parts[#parts + 1] = key .. "=" .. ser(v[k])
      end
      return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "string" then
      return string.format("%q", v)
    end
    return tostring(v)
  end
  return ser(data)
end

local function unserialise(text)
  local tu = rawget(_G, "textutils")
  if tu and tu.unserialise then return tu.unserialise(text) end
  local fn = (rawget(_G, "loadstring") or load)("return " .. text)
  if not fn then return nil end
  local ok, v = pcall(fn)
  return ok and v or nil
end

local function readFile(fs, path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local text = h.readAll()
  h.close()
  return unserialise(text or "")
end

--- The save at path, as v2. A broken main file falls back to the backup; nothing at all gives a blank save.
-- Returns data, note (nil, or why it is not the main file).
function M.read(fs, path)
  local raw = readFile(fs, path)
  local data, err = nil, nil
  if raw then data, err = M.migrate(raw) end
  if data then return data end
  local backup = readFile(fs, path .. ".bak")
  if backup then
    local b = M.migrate(backup)
    if b then return b, "the save was unreadable (" .. tostring(err or "damaged") .. "): using the backup" end
  end
  if raw and err then return nil, err end
  return M.blank(), raw and "the save was unreadable: starting fresh" or nil
end

function M.write(fs, path, data)
  data.version = M.VERSION
  local tmp = path .. ".tmp"
  local h = fs.open(tmp, "w")
  if not h then return false, "cannot write " .. tmp end
  h.write(serialise(data))
  h.close()
  if fs.exists(path) then
    if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
    fs.move(path, path .. ".bak")
  end
  fs.move(tmp, path)
  return true
end

-- ---------------------------------------------------------------- today's game

function M.toLegacy(v2)
  local done = {}
  for id in pairs(v2.story.done or {}) do done[#done + 1] = id end
  table.sort(done)
  return {
    version = 1, money = v2.player.money or 0, done = done, finished = v2.story.finished,
    stats = v2.progress.stats, tutorialDone = v2.settings.tutorialDone,
  }
end

function M.fromLegacy(v1, v2)
  local fresh = M.migrate(v1)
  v2 = v2 or M.blank()
  v2.player.money = fresh.player.money
  v2.story.done = fresh.story.done
  v2.story.finished = fresh.story.finished
  v2.progress.stats = fresh.progress.stats
  v2.settings.tutorialDone = fresh.settings.tutorialDone
  return v2
end

return M
