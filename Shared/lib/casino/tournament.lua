-- tournament.lua
-- A table's side of a hub tournament. The hub runs the contest (Games/CasinoHub/casino_hub_contest.lua) and says so over
-- net.lua, and any table of that game offers it. A player sits in a pretend seat (pretend.lua) with the contest's starting
-- chips. No tokens move, and nothing here can reach a token: it only keeps this file and sends scores.
--
-- One entry for each player in each contest: one stack, played at one table, across as many visits as they like until it runs
-- out or the contest ends. So a reboot must not hand out a fresh stack, or wipe a bad hand. This file holds every stack here,
-- and what a round had at stake goes in it as the round opens. A reboot in the middle of a round costs what was staked.
--
-- A score goes out after each round, and all of this table's scores go out again every few seconds until the hub's grace is
-- over, so a hub that reboots or comes back catches up. Nothing waits for an answer, so a hub that disappears cannot hang a
-- table: a seat plays on to the end it last heard, nobody new can enter, and the file keeps every stack in case it returns.

local journal = require("lib.casino.journal")
local net = require("lib.casino.net")

local M = {}

M.FILE = "casino_tournament.dat"
M.REPORT_MS = 15000      -- how often scores are said again
M.GRACE_MS = 60000       -- how long after the end the hub takes scores (casino_hub_contest.lua has the same figure)

local MOVED_MS = 5000    -- an end that moves by less than this is only the network's delay, and not worth a write

local lastReport = 0
local endsAt = 0         -- when the contest in the file ends. A seat asks every frame, so it is kept here and not read from disk

local function load()
  local file = journal.load(M.FILE)
  if type(file) == "table" and type(file.players) == "table" then return file end
  return nil
end

local function save(file)
  return journal.save(M.FILE, file)
end

local function say(file, name, entry)
  net.send("tscore", { contest = file.id, game = file.game, player = name, chips = entry.chips, rounds = entry.rounds,
    final = entry.final == true })
end

--- A stack that cannot bet again is finished, and the hub takes nothing more for it.
local function count(entry, chips)
  entry.chips = chips
  entry.rounds = entry.rounds + 1
  entry.risk = nil
  entry.final = chips < 1 or nil
end

--- Charge what a round had open: the computer went down, or the clock ran out, with it unfinished.
local function forfeit(file, name, entry)
  count(entry, math.max(0, entry.chips - entry.risk))
  journal.log("tournament " .. tostring(file.id) .. " " .. name .. " forfeits an open round: " .. entry.chips .. " chips left")
end

--- The contest a table of this game can offer now, or nil.
function M.offer(gameId, time)
  local contest = net.contest()
  if contest and contest.open and contest.game == gameId and contest.ends > time then return contest end
  return nil
end

--- What the hub's board says about a player.
local function onBoard(contest, name)
  for _, row in ipairs(contest.board) do
    if row.name == name then return row end
  end
  return nil
end

--- Take a player's one entry. Returns their entry, or nil and what to tell them.
function M.enter(contest, name)
  local row = onBoard(contest, name)
  if row and row.table ~= os.getComputerID() then
    return nil, "ONE ENTRY EACH", "Your stack is at table #" .. tostring(row.table)
  end
  local file = load()
  if not file or file.id ~= contest.id then
    file = { id = contest.id, game = contest.game, chips = contest.chips, ends = contest.ends, players = {} }
  end
  local entry = file.players[name]
  if not entry then
    -- The hub's word stands in for a file that has gone
    entry = { chips = row and row.chips or contest.chips, rounds = row and row.rounds or 0, final = row and row.final or nil }
    file.players[name] = entry
  end
  if entry.final or entry.chips < 1 then
    return nil, "ONE ENTRY EACH", "You finished this contest with " .. tostring(entry.chips) .. " chips"
  end
  if not save(file) then return nil, "NO ROOM", "This table cannot keep your entry" end
  endsAt = file.ends
  return entry
end

--- The hooks a pretend seat calls as this player's rounds go by.
function M.hooks(name)
  local function change(fn)
    local file = load()
    local entry = file and file.players[name]
    if not entry then return end
    fn(file, entry)
    save(file)
    return file, entry
  end
  return {
    opened = function(risk)
      change(function(_, entry) entry.risk = risk end)
    end,
    settled = function(_, chips)
      local file, entry = change(function(_, entry) count(entry, chips) end)
      if file then say(file, name, entry) end
    end,
    forfeit = function()
      local file, entry = change(function(file, entry)
        if entry.risk then forfeit(file, name, entry) end
      end)
      if file then say(file, name, entry) end
    end,
    ends = function() return endsAt end,
  }
end

--- After a reboot. A seat that was sitting has gone, so any round it had open is settled here, against it.
function M.boot()
  local file = load()
  if not file then return end
  local changed = false
  for name, entry in pairs(file.players) do
    if entry.risk then
      forfeit(file, name, entry)
      changed = true
    end
  end
  if changed then save(file) end
end

--- Call now and then: follow the end the hub says, and say every score again while the hub still takes them.
function M.tick(time)
  if time - lastReport < M.REPORT_MS then return end
  lastReport = time
  local file = load()
  if not file then return end
  local heard = net.contest()
  if heard and heard.id == file.id and math.abs(heard.ends - file.ends) > MOVED_MS then
    file.ends = heard.ends
    save(file)
  end
  endsAt = file.ends
  if time > file.ends + M.GRACE_MS then return end
  for name, entry in pairs(file.players) do
    if entry.rounds > 0 then say(file, name, entry) end
  end
end

return M
