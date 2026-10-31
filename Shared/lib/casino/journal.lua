-- journal.lua
-- What a table must not forget across a reboot, kept on disk:
--   the open round (so a reboot resumes it instead of cancelling it), and what is owed either way.
-- Nothing is charged while a round is open, so losing power mid-round costs nobody anything:
-- the round comes back when its player does.

local M = {}

local ROUND_FILE = "casino_round.dat"
local OWED_FILE = "casino_owed.dat"
local KEEP_FILE = "casino_keep.dat"

local function read(path)
  if not fs.exists(path) then return nil end
  local handle = fs.open(path, "r")
  if not handle then return nil end
  local text = handle.readAll()
  handle.close()
  local value = text and textutils.unserialize(text)
  if type(value) == "table" then return value end
  return nil
end

--- Write beside the target and swap, keeping the last good copy, so a reboot mid-write loses at most one step.
local function write(path, value)
  local handle = fs.open(path .. ".tmp", "w")
  if not handle then return false end
  handle.write(textutils.serialize(value, { compact = true }))
  handle.close()
  if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
  if fs.exists(path) then fs.move(path, path .. ".bak") end
  fs.move(path .. ".tmp", path)
  return true
end

local function load(path)
  return read(path) or read(path .. ".bak")
end

function M.saveRound(round)
  return write(ROUND_FILE, round)
end

function M.loadRound()
  return load(ROUND_FILE)
end

function M.clearRound()
  for _, suffix in ipairs({ "", ".bak", ".tmp" }) do
    if fs.exists(ROUND_FILE .. suffix) then fs.delete(ROUND_FILE .. suffix) end
  end
end

--- Everything owed at this table: player name -> tokens, positive to the player, negative from them.
function M.owed()
  return load(OWED_FILE) or {}
end

function M.owedTo(name)
  return M.owed()[name] or 0
end

function M.addOwed(name, amount)
  local all = M.owed()
  local total = (all[name] or 0) + amount
  all[name] = total ~= 0 and total or nil
  write(OWED_FILE, all)
  return total
end

--- Things a game keeps between rounds, such as a blackjack shoe.
function M.loadKeep()
  return load(KEEP_FILE) or {}
end

function M.saveKeep(keep)
  return write(KEEP_FILE, keep)
end

return M
