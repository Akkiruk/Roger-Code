-- arcade_saves.lua
-- Saved games: one file for each player and game, so a run too long for one sitting can wait for its player. The files
-- are written the way the score tables are, with a good copy on disk at every moment, and an update leaves them alone
-- because the updater only touches files it installed. Only action.lua uses this. See "Classics" in games/README.md.

local M = { AUTOSAVE_MS = 30000 }

local VERSION = 1
local SUFFIXES = { "", ".tmp", ".bak" } -- after a reboot in the middle of a swap, .tmp is newer than .bak
local MAX_NAME = 60
-- A state may share a table between two fields, such as a town from a list: the default refuses those outright.
local SERIALISE = { compact = true, allow_repetitions = true }

--- A name fit for a file, different for every different name: anything but a letter or digit becomes _ and its hex code.
local function safe(text)
  local out = tostring(text):gsub("[^%w]", function(c) return string.format("_%02X", c:byte()) end)
  if #out <= MAX_NAME then return out end
  local hash = 5381
  for i = 1, #out do hash = (hash * 33 + out:byte(i)) % 2147483647 end
  return out:sub(1, MAX_NAME - 9) .. "_" .. string.format("%08x", hash)
end

function M.path(game, player)
  return "arcade_save_" .. safe(game) .. "_" .. safe(player) .. ".dat"
end

--- Is this what a save looks like, for this game and this player? The header draws score and lives without asking.
local function sound(save, game, player)
  if type(save) ~= "table" or save.version ~= VERSION or save.game ~= game or save.player ~= player then return false end
  local s, position = save.state, save.rng
  if type(s) ~= "table" or s.over or type(s.score) ~= "number" then return false end
  for _, field in ipairs({ s.level or 0, s.lives or 0 }) do
    if type(field) ~= "number" then return false end
  end
  return type(position) == "number" and position >= 1 and position <= 2147483646 and position % 1 == 0
end

local function readCopy(path, game, player)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local text = h.readAll()
  h.close()
  local ok, value = pcall(textutils.unserialise, text or "")
  if ok and sound(value, game, player) then return value end
  return nil
end

--- The newest good copy of a player's save: { state, rng, player, game, at }, or nil if there is none worth offering.
function M.read(game, player)
  local path = M.path(game, player)
  for _, suffix in ipairs(SUFFIXES) do
    local ok, save = pcall(readCopy, path .. suffix, game, player)
    if ok and save then return save end
  end
  return nil
end

--- The play tracker keeps the floor's copy of every save (share.lua): a cabinet's own changes go to it.
local function share(game, player, save, deleted)
  pcall(function() require("lib.arcade.share").push("save", game, player, save, deleted) end)
end

--- Write beside the file and swap. Returns true, or false and why: nothing here can raise an error, and a failure leaves
-- the last good save in place.
local function writeSave(game, player, save)
  local path = M.path(game, player)
  local tmp, bak = path .. ".tmp", path .. ".bak"
  local made, text = pcall(textutils.serialise, save, SERIALISE)
  if not made then return false, text end
  local ok, err = pcall(function()
    local h, why = fs.open(tmp, "w")
    if not h then error(why or ("could not open " .. tmp), 0) end
    local wrote, problem = pcall(h.write, text)
    h.close()
    if not wrote then error(problem, 0) end
    if fs.exists(bak) then fs.delete(bak) end
    if fs.exists(path) then fs.move(path, bak) end
    fs.move(tmp, path)
  end)
  if ok then return true end
  pcall(fs.delete, tmp)
  return false, err
end

--- How far a save has got, as one number, for keeping the furthest copy when cabinets disagree (merge.save). A game says it
--- with view.saveRank(state); a game with view.progress gets story share first, then level, then minutes played; any other
--- game has no measure (nil), and its copies go by time.
function M.rank(plugin, state)
  local view = plugin and plugin.view
  if type(state) ~= "table" or not view then return nil end
  if view.saveRank then
    local ok, r = pcall(view.saveRank, state)
    return ok and type(r) == "number" and r or nil
  end
  if view.progress then
    local ok, p = pcall(view.progress, state)
    if not ok or type(p) ~= "table" then return nil end
    local percent = p.ended and 100 or (tonumber(p.percent) or 0)
    return percent * 1e10 + math.min(tonumber(p.level) or 0, 9999) * 1e6 + math.min(tonumber(p.minutes) or 0, 999999)
  end
  return nil
end

-- Playthroughs that ended on this computer (finished, or given up for NEW GAME), by game and player: a later save carries
-- them, so a copy of an ended run elsewhere never comes back (merge.save).
local ENDED_FILE = "arcade_ended.dat"

local function readEnded()
  local h = fs.exists(ENDED_FILE) and fs.open(ENDED_FILE, "r")
  if not h then return {} end
  local ok, value = pcall(textutils.unserialise, h.readAll() or "")
  h.close()
  return ok and type(value) == "table" and value or {}
end

--- The playthroughs this computer knows have ended for a player at a game.
function M.ended(game, player)
  local list = readEnded()[tostring(game) .. "|" .. tostring(player)]
  return type(list) == "table" and list or {}
end

local function noteEnded(game, player, run)
  if type(run) ~= "string" then return end
  local all = readEnded()
  local key = tostring(game) .. "|" .. tostring(player)
  local list = type(all[key]) == "table" and all[key] or {}
  for _, r in ipairs(list) do
    if r == run then return end
  end
  list[#list + 1] = run
  while #list > 30 do table.remove(list, 1) end
  all[key] = list
  pcall(function()
    local h = fs.open(ENDED_FILE, "w")
    if h then h.write(textutils.serialise(all, { compact = true })); h.close() end
  end)
end

--- A new playthrough's name, different on every computer and every time.
function M.newRun()
  return tostring(os.getComputerID()) .. ":" .. tostring(os.epoch("utc")) .. ":" .. tostring(math.random(1, 999999))
end

--- A player's save. Returns true, or false and why. rng is the generator's position, from journal.trackedRng. meta, from
--- action.lua: { run, rank } for the furthest copy to win between cabinets.
function M.write(game, player, state, rng, meta)
  meta = meta or {}
  local ended = M.ended(game, player)
  local save = { version = VERSION, game = game, player = player, rng = rng, state = state, at = os.epoch("utc"),
    run = meta.run, rank = meta.rank, ended = #ended > 0 and ended or nil }
  local ok, err = writeSave(game, player, save)
  if ok then share(game, player, save) end
  return ok, err
end

--- A save as it came from the floor's copy, written as it is: its own time, nothing sent back.
function M.put(game, player, save)
  if not sound(save, game, player) then return false, "not a save for " .. tostring(game) .. " and " .. tostring(player) end
  return writeSave(game, player, save)
end

--- Every player's save for a game on this computer, newest first: { save, ... } as read gives them.
function M.list(game)
  local prefix = "arcade_save_" .. safe(game) .. "_"
  local out = {}
  for _, name in ipairs(fs.list("")) do
    if name:sub(1, #prefix) == prefix and name:sub(-4) == ".dat" then
      local ok, value = pcall(function()
        local h = fs.open(name, "r")
        if not h then return nil end
        local text = h.readAll()
        h.close()
        return textutils.unserialise(text or "")
      end)
      if ok and type(value) == "table" and sound(value, game, value.player) then out[#out + 1] = value end
    end
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

--- Every copy goes: a .bak left behind would bring a finished run back.
--- The floor's copy hears of it too, so no other cabinet offers the run that ended.
function M.delete(game, player)
  local was = M.read(game, player)
  if was and was.run then noteEnded(game, player, was.run) end
  local path = M.path(game, player)
  for _, suffix in ipairs(SUFFIXES) do pcall(fs.delete, path .. suffix) end
  -- Only a save that was here can end: telling the floor a run ended when this computer never had it would wipe that player's
  -- save everywhere (START on a new computer used to do exactly that, before its copy from the tracker had arrived).
  if not was then return end
  local ended = M.ended(game, player)
  share(game, player, { run = was.run, ended = #ended > 0 and ended or nil }, true)
end

--- A copy from the floor said this run is over: remember it here too, and drop the save if it is that run.
function M.endedElsewhere(game, player, marker)
  for _, run in ipairs(type(marker) == "table" and type(marker.ended) == "table" and marker.ended or {}) do
    noteEnded(game, player, run)
  end
  if type(marker) == "table" and marker.deleted and marker.run then noteEnded(game, player, marker.run) end
end

return M
