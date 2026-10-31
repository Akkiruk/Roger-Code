-- pretend.lua
-- A seat with pretend chips and no tokens: practice, and hub tournaments. See door.lua for how a table comes to use it.
-- This file holds the stand-ins for everything a table reaches through a door. It requires no wallet, no books, no journal,
-- no stats, no session and no network, so nothing here can reach them: chips are one number in this object, and a seat's keep
-- and shoe are made for it and die with it. Nothing goes on disk, so a reboot simply ends a practice seat. A tournament seat
-- is the same seat with hooks, which tournament.lua uses to keep its entry across a reboot.
--
-- Seat options: kind "practice" or "tournament", title, name, guest, chips, rules (the game's), at (the time now), hooks.
-- Hooks (optional): opened(risk) as a round's stake changes, settled(net, chips) when it ends, forfeit(), ends() -> time.

local M = {}

M.CHIPS = 1000           -- what a seat starts with
M.GUEST = "Guest"        -- the seat's name when nothing can say who touched
M.IDLE_MS = 45000        -- no touch from the player for this long ends a seat
M.WAITED_MS = 10000      -- the same with someone else waiting, or with the detector saying they have gone
M.OVERTIME_MS = 45000    -- a tournament round still open this long after the end is forfeited

local NO_HOUSE = 1e9     -- nothing covers a pretend bet, so a table's limit never comes from here

local Seat = {}
Seat.__index = Seat

local function nothing() end
local function yes() return true end
local function zero() return 0 end

--- Everything a seat needs in place of the real thing. A door raises an error for anything missing from here.
local function stands(seat)
  return {
    badges = {
      award = function() return {} end,
      hear = nothing,
      sayAll = nothing,
      streak = zero,
      player = function() return {} end,
    },
    books = {
      resolve = yes,
      move = function(_, net)
        seat:settled(net)
        return net, 0, nil
      end,
    },
    journal = {
      log = nothing,
      saveRound = function(round)
        seat:saved(round)
        return true
      end,
      loadRound = nothing,
      clearRound = nothing,
      book = yes,
      owedTo = zero,
      saveKeep = yes,
    },
    lamps = { pulse = nothing },
    net = {
      tick = nothing,
      hub = nothing,
      otherExposure = zero,
      setExposure = nothing,
      send = nothing,
      claim = nothing,
      granted = nothing,
    },
    session = {
      record = nothing,
      close = nothing,
      open = function() return {} end,
      text = function() return "" end,
      noteOwed = nothing,
      noteMoved = nothing,
    },
    stats = {
      record = function(_, wagered, net) seat:recorded(wagered, net) end,
      player = function() return seat.record end,
      leaders = function() return {} end,
    },
    wallet = {
      available = yes,
      livePlayer = nothing,
      lockIfOwner = function() return false end,
      wantsLock = function() return false end,
      balance = function() return seat.chips end,
      hostName = nothing,
      hostBalance = function() return NO_HOUSE end,
      terminalLocked = nothing,
      isApproved = yes,
      requestApproval = nothing,
    },
  }
end

--- A new seat. It keeps its own keep, so a shoe game gets a shoe nobody else can see.
function M.new(options)
  local seat = setmetatable({
    kind = options.kind or "practice",
    title = options.title or "PRACTICE",
    name = options.name or M.GUEST,
    guest = options.guest == true,
    chips = options.chips or M.CHIPS,
    rules = options.rules,
    hooks = options.hooks,
    keep = {},
    record = { rounds = 0, wagered = 0, net = 0, best = 0 },
    touched = options.at or 0,
    risk = nil,              -- what an open round has staked, or nil between rounds
    waited = false,          -- someone else has touched the table
  }, Seat)
  seat.stands = stands(seat)
  return seat
end

--- A round was saved: note what it has at stake, which is what a reboot in the middle of it costs a tournament entry.
function Seat:saved(round)
  if round.phase ~= "open" then return end
  local risk = self.rules and self.rules.risk and self.rules.risk(round.state) or round.stake
  if risk ~= self.risk then
    self.risk = risk
    if self.hooks then self.hooks.opened(risk) end
  end
end

function Seat:settled(net)
  self.chips = math.max(0, self.chips + math.floor(net + 0.5))
  self.risk = nil
  if self.hooks then self.hooks.settled(net, self.chips) end
end

function Seat:recorded(wagered, net)
  local record = self.record
  record.rounds = record.rounds + 1
  record.wagered = record.wagered + wagered
  record.net = record.net + net
  record.best = math.max(record.best, net)
end

--- The player touched their table.
function Seat:touch(time)
  self.touched = time
end

--- Someone else touched it: the seat gives way sooner, once its player stops.
function Seat:wanted()
  self.waited = true
end

--- Whether a touch from this name is the player's. A guest has no name, so nothing can tell one touch from another.
function Seat:owns(who)
  return self.guest or who == self.name
end

--- Why this seat is over, or nil. scene is what is on the wall and away is the detector's word, if it has one.
-- A bet screen gives way at once. A round plays out, and only a tournament's clock can end one at the player's cost.
function Seat:over(time, scene, away)
  local open = self.risk ~= nil
  local ends = self.hooks and self.hooks.ends()
  if ends and time >= ends + (scene.name == "bet" and 0 or M.OVERTIME_MS) then return "time" end
  if scene.name == "bet" and not open and self.chips < 1 then return "bust" end
  if scene.playing or (scene.queue and #scene.queue > 0) then return nil end
  if open and self.kind == "tournament" then return nil end -- the table's own idle play finishes it, so the entry is fair
  local limit = (self.waited or (away and away > 0)) and M.WAITED_MS or M.IDLE_MS
  if time - self.touched >= limit then return "idle" end
  return nil
end

--- The seat has left. A tournament round left open costs what it had staked.
function Seat:ended()
  if self.risk and self.hooks then self.hooks.forfeit() end
  self.risk = nil
end

--- What the wall says, the whole time this seat sits.
function Seat:label(time)
  if self.kind ~= "tournament" then return "PRACTICE: PRETEND CHIPS, NO TOKENS" end
  local ends = self.hooks and self.hooks.ends()
  local left = ends and math.max(0, math.ceil((ends - time) / 60000)) or 0
  return "TOURNAMENT: NO TOKENS, " .. left .. " MIN LEFT"
end

--- What someone else hears when they touch this seat's table.
function Seat:busy()
  return self.title .. " seat: it frees up when idle"
end

--- The line the idle screen shows after the seat leaves.
function Seat:summary(why)
  local line = self.kind == "tournament" and "Tournament chips: " or "Practice over, chips were pretend: "
  if why == "bust" then return line .. "out of chips" end
  return line .. tostring(self.chips)
end

return M
