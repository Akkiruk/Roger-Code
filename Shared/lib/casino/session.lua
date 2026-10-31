-- session.lua
-- What a player did on this visit, and what they must be told as they go. Kept on disk, so a reboot loses neither.
--   a session  rounds, net and best win since they sat down. It ends when they leave: "12 rounds, +340, best win 900".
--   a note     what the owed book holds for a player who has walked away, whispered once per amount, and what became of it.
-- The stats keep a player's whole record at this table; this is one visit, and it is gone once it has been said.
-- Nothing here moves a token or changes the book. It only reads journal.owedTo, which is the truth about what is owed.

local chat = require("lib.casino.chat")
local journal = require("lib.casino.journal")
local ui = require("lib.casino.ui")

local M = {}

local FILE = "casino_session.dat"
local SEEN_KEPT = 24   -- rounds remembered, so one replayed after a reboot is not counted twice

local function load()
  local data = journal.load(FILE)
  if type(data) ~= "table" then data = {} end
  data.players, data.told, data.seen = data.players or {}, data.told or {}, data.seen or {}
  return data
end

local function save(data)
  return journal.save(FILE, data)
end

--- Add a finished round to a player's visit. The same tag again changes nothing.
function M.record(name, net, tag)
  local data = load()
  for _, seen in ipairs(data.seen) do
    if seen == tag then return end
  end
  table.insert(data.seen, tag)
  while #data.seen > SEEN_KEPT do table.remove(data.seen, 1) end
  local entry = data.players[name] or { rounds = 0, net = 0, best = 0 }
  entry.rounds = entry.rounds + 1
  entry.net = entry.net + net
  entry.best = math.max(entry.best, net)
  entry.at = os.epoch("utc")
  data.players[name] = entry
  save(data)
end

--- End a visit. Returns what it came to, or nil if they played nothing.
function M.close(name)
  local data = load()
  local entry = data.players[name]
  if not entry then return nil end
  data.players[name] = nil
  save(data)
  return entry
end

--- Who has a visit open, and when they last finished a round: name -> time.
function M.open()
  local list = {}
  for name, entry in pairs(load().players) do list[name] = entry.at or 0 end
  return list
end

--- "12 rounds, +340, best win 900".
function M.text(entry)
  local line = ui.group(entry.rounds) .. (entry.rounds == 1 and " round, " or " rounds, ") .. ui.signed(entry.net)
  if entry.best > 0 then line = line .. ", best win " .. ui.group(entry.best) end
  return line
end

--- A transfer still in doubt may already have moved, so the book cannot yet be read out as what they are owed.
local function inDoubt(name)
  for _, move in pairs(journal.moves()) do
    if move.name == name then return true end
  end
  return false
end

--- Tell a player who has left what the book holds for them, once for each amount.
-- @param name string    the player
-- @param title string   the table
function M.noteOwed(name, title)
  local owed = journal.owedTo(name)
  if owed == 0 or inDoubt(name) then return false end
  local data = load()
  if data.told[name] == owed then return false end
  local text = owed > 0 and ("You are owed %s at %s. A tap there collects it."):format(ui.group(owed), title)
    or ("You owe %s at %s. A tap there settles it."):format(ui.group(-owed), title)
  -- With no chat box it stays untold, so one added later still gets to say it
  if not chat.tell(name, text) then return false end
  data.told[name] = owed
  save(data)
  return true
end

--- Tell a player that what they were owed, or owed, has moved.
-- @param moved number   tokens moved: to the player when positive, from them when negative
-- @param left number    what the book still holds for them
function M.noteMoved(name, moved, left, title)
  local text = moved > 0 and ("Collected %s owed to you at %s."):format(ui.group(moved), title)
    or ("Paid %s you owed at %s."):format(ui.group(-moved), title)
  if left > 0 then
    text = text .. " Still owed to you: " .. ui.group(left) .. "."
  elseif left < 0 then
    text = text .. " Still to pay: " .. ui.group(-left) .. "."
  end
  chat.tell(name, text)
  local data = load()
  if data.told[name] then
    data.told[name] = left ~= 0 and left or nil
    save(data)
  end
end

return M
