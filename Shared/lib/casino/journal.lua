-- journal.lua
-- What a table must not forget across a reboot, kept on disk:
--   the open round (so a reboot resumes it instead of cancelling it), and what is owed either way.
-- Nothing is charged while a round is open, so losing power mid-round costs nobody anything:
-- the round comes back when its player does.
--
-- Nothing here can throw, so a full disk cannot stop a table just after money moved. A write that fails returns false.
-- The owed book is one file and every change to it is one write, so a step against it lands whole or not at all. Beside
-- the players it holds two things under keys no player name can have: the transfers under way, and the tags of recent
-- steps, which is how a step repeated after a reboot knows it already happened. See books.lua.

local M = {}

local ROUND_FILE = "casino_round.dat"
local OWED_FILE = "casino_owed.dat"
local KEEP_FILE = "casino_keep.dat"
local LOG_FILE = "casino.log"
local LOG_MAX_BYTES = 48000
local MIN_FREE_BYTES = 32000  -- below this a log gives way, so the files that hold money always have room
local MOVES = "#moves"
local DONE = "#done"
local DONE_KEPT = 40

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

--- Write beside the target and swap, keeping the last good copy, so a reboot mid-write loses nothing that was finished.
local function write(path, value)
  local tmp = path .. ".tmp"
  local ok, written = pcall(function()
    local text = textutils.serialize(value, { compact = true })
    local handle = fs.open(tmp, "w")
    if not handle then return false end
    local fine = pcall(handle.write, text)
    handle.close()
    return fine and fs.getSize(tmp) >= #text
  end)
  if not ok or not written then
    pcall(fs.delete, tmp)
    return false
  end
  return (pcall(function()
    if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
    if fs.exists(path) then fs.move(path, path .. ".bak") end
    fs.move(tmp, path)
  end))
end

--- With the main file gone the swap above was cut short, and .tmp is whole: it is only ever swapped in once finished.
local function load(path)
  return read(path) or read(path .. ".tmp") or read(path .. ".bak")
end

M.save, M.load = write, load

--- Add a line to a log, turning it over when it gets big. Failing to log must never matter.
function M.appendLine(path, maxBytes, line)
  pcall(function()
    if fs.exists(path) and fs.getSize(path) > maxBytes then
      if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
      fs.move(path, path .. ".bak")
    end
    if fs.getFreeSpace("/") < MIN_FREE_BYTES then
      if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
      if fs.getFreeSpace("/") < MIN_FREE_BYTES then return end
    end
    local handle = fs.open(path, "a")
    if handle then
      pcall(handle.writeLine, line)
      handle.close()
    end
  end)
end

--- The table's own log.
function M.log(message)
  M.appendLine(LOG_FILE, LOG_MAX_BYTES, os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(message))
end

function M.saveRound(round)
  return write(ROUND_FILE, round)
end

function M.loadRound()
  return load(ROUND_FILE)
end

--- The main file goes last: while anything is left it must be the newest copy, never an older phase that would replay.
function M.clearRound()
  for _, suffix in ipairs({ ".tmp", ".bak", "" }) do
    if fs.exists(ROUND_FILE .. suffix) then pcall(fs.delete, ROUND_FILE .. suffix) end
  end
end

local function book()
  return load(OWED_FILE) or {}
end

local function change(all, name, amount)
  local total = (all[name] or 0) + amount
  all[name] = total ~= 0 and total or nil
end

local function isDone(all, tag)
  for _, seen in ipairs(all[DONE] or {}) do
    if seen == tag then return true end
  end
  return false
end

local function markDone(all, tag)
  all[DONE] = all[DONE] or {}
  table.insert(all[DONE], tag)
  while #all[DONE] > DONE_KEPT do table.remove(all[DONE], 1) end
end

--- Everything owed at this table: player name -> tokens, positive to the player, negative from them.
function M.owed()
  local all = book()
  all[MOVES], all[DONE] = nil, nil
  return all
end

function M.owedTo(name)
  return book()[name] or 0
end

function M.addOwed(name, amount)
  local all = book()
  change(all, name, amount)
  write(OWED_FILE, all)
  return all[name] or 0
end

--- Put a result in the book, once: the same tag again changes nothing. Returns false if the book could not be written.
function M.book(name, amount, tag)
  local all = book()
  if isDone(all, tag) then return true end
  change(all, name, amount)
  markDone(all, tag)
  return write(OWED_FILE, all)
end

--- Say a transfer is about to happen. Returns false if that could not be written, and then it must not happen.
function M.beginMove(name, amount, tag)
  local all = book()
  all[MOVES] = all[MOVES] or {}
  all[MOVES][tag] = { name = name, amount = amount, at = os.epoch("utc") }
  return write(OWED_FILE, all)
end

--- A transfer's answer: moved is what really went, 0 if nothing did. It comes off the book in the write that ends the move.
function M.endMove(tag, moved)
  local all = book()
  local move = all[MOVES] and all[MOVES][tag]
  if move then
    all[MOVES][tag] = nil
    if not next(all[MOVES]) then all[MOVES] = nil end
    change(all, move.name, -moved)
    markDone(all, tag)
    write(OWED_FILE, all)
  end
end

--- The transfers still under way: tag -> { name, amount, at }. After a reboot these are the ones in doubt.
function M.moves()
  return book()[MOVES] or {}
end

--- Things a game keeps between rounds, such as a blackjack shoe.
function M.loadKeep()
  return load(KEEP_FILE) or {}
end

function M.saveKeep(keep)
  return write(KEEP_FILE, keep)
end

return M
