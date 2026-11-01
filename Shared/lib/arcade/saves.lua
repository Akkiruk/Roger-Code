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

--- Write beside the file and swap. Returns true, or false and why: nothing here can raise an error, and a failure leaves
-- the last good save in place. rng is the generator's position, from journal.trackedRng.
function M.write(game, player, state, rng)
  local path = M.path(game, player)
  local tmp, bak = path .. ".tmp", path .. ".bak"
  local save = { version = VERSION, game = game, player = player, rng = rng, state = state, at = os.epoch("utc") }
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

--- Every copy goes: a .bak left behind would bring a finished run back.
function M.delete(game, player)
  local path = M.path(game, player)
  for _, suffix in ipairs(SUFFIXES) do pcall(fs.delete, path .. suffix) end
end

return M
