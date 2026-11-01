-- games/battleship/rules.lua
-- Battleship for a stake. Pure: no screen, sound or files. The rules are the Arcade's, copied so Duel needs nothing from that package,
-- with three changes for money: both players place at once, a seat that runs out of time forfeits, and a player can give up.
-- players[n].fleet and .grid are that player's secret. players[n].shots is what they know of the enemy's water: 0 unfired, MISS, HIT
-- or SUNK. viewFor is all anyone else is given, and it hands over the fleets only once the match is over.
--
-- A square travels as one number, (y - 1) * SIZE + x, so a region's value stays a plain number. A ship tapped too near the edge is
-- slid back onto the water. Running out of time while placing waits to see the other player: if they finish they win, and if they
-- run out too nobody came and nothing moves.

local hash = require("lib.casino.rng")

local M = { SIZE = 10, MISS = 1, HIT = 2, SUNK = 3 }

local SIZE, MISS, HIT, SUNK = M.SIZE, M.MISS, M.HIT, M.SUNK

M.SHIPS = {
  { name = "Carrier", len = 5 }, { name = "Battleship", len = 4 }, { name = "Cruiser", len = 3 },
  { name = "Submarine", len = 3 }, { name = "Destroyer", len = 2 },
}

local FLEET = #M.SHIPS
local SALT = 2147483646

local function grid(value)
  local out = {}
  for y = 1, SIZE do
    out[y] = {}
    for x = 1, SIZE do out[y][x] = value end
  end
  return out
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

--- The x, y of a square's number, or nil for anything that is not a square.
function M.square(value)
  if type(value) ~= "number" or value ~= math.floor(value) or value < 1 or value > SIZE * SIZE then return nil end
  return (value - 1) % SIZE + 1, math.floor((value - 1) / SIZE) + 1
end

function M.cell(x, y)
  return (y - 1) * SIZE + x
end

local function find(s, seat)
  for position, player in ipairs(s.players) do
    if player.seat == seat then return player, s.players[3 - position], position end
  end
  return nil
end

function M.new(entries, button, rng, keep)
  local players = {}
  local stake = math.floor(entries[1].stake or 25)
  for position, entry in ipairs(entries) do
    players[position] = { seat = entry.seat, name = entry.name, stack = entry.stack, placed = 0, dir = "h", fleet = {}, grid = grid(0),
      shots = grid(0), sunk = 0, ready = false, late = false, confirm = false }
    stake = math.min(stake, math.floor(entry.stack))
  end
  local first = entries[button] and button or 1
  return { phase = "setup", stake = stake, first = first, turn = first, moves = 0, winner = 0, players = players }, { { type = "deal" } }
end

local function fits(g, len, x, y, dir)
  for i = 0, len - 1 do
    local cx, cy = dir == "h" and x + i or x, dir == "v" and y + i or y
    if not g[cy] or g[cy][cx] ~= 0 then return false end
  end
  return true
end

local function placeShip(p, x, y, dir)
  local n = p.placed + 1
  p.fleet[n] = { x = x, y = y, dir = dir, hits = 0 }
  for i = 0, M.SHIPS[n].len - 1 do
    p.grid[dir == "v" and y + i or y][dir == "h" and x + i or x] = n
  end
  p.placed = n
end

--- A fleet as text, with a random salt so a seal can't be guessed by trying fleets. A secret until the match ends.
local function fleetText(p)
  local parts = {}
  for n, ship in ipairs(p.fleet) do parts[n] = ship.x .. "," .. ship.y .. ship.dir end
  return table.concat(parts, ";") .. "|" .. tostring(p.salt)
end

local function endMatch(s, winner, how)
  s.phase, s.how = "over", how
  s.winner = winner
end

local function positionOf(s, p)
  return s.players[1] == p and 1 or 2
end

--- This player's fleet is all down. Seal it, and start the shooting, or take the win from a player who has already run out of time.
local function fleetDone(s, p, other, events, rng)
  p.ready = true
  p.salt = rng:below(SALT)
  p.seal = hash.sha256(fleetText(p)):sub(1, 10)
  events[#events + 1] = { type = "ready", seat = p.seat }
  if other.late then
    endMatch(s, positionOf(s, p), "timeout")
    events[#events + 1] = { type = "forfeit", seat = other.seat, how = "timeout" }
  elseif other.ready then
    s.phase, s.turn = "fire", s.first
    events[#events + 1] = { type = "battle", seat = s.players[s.first].seat }
  end
end

local function place(s, p, other, value, rng)
  local x, y = M.square(value)
  if not x then return {} end
  local n = p.placed + 1
  local reach = SIZE - M.SHIPS[n].len + 1
  if p.dir == "h" then x = math.min(x, reach) else y = math.min(y, reach) end
  if not fits(p.grid, M.SHIPS[n].len, x, y, p.dir) then return {} end
  placeShip(p, x, y, p.dir)
  local events = { { type = "placed", seat = p.seat } }
  if p.placed == FLEET then fleetDone(s, p, other, events, rng) end
  return events
end

--- The rest of this fleet, wherever the dice say.
local function randomFleet(s, p, other, rng)
  while p.placed < FLEET do
    local ship = M.SHIPS[p.placed + 1]
    local x, y, dir = rng:below(SIZE) + 1, rng:below(SIZE) + 1, rng:below(2) == 0 and "h" or "v"
    if fits(p.grid, ship.len, x, y, dir) then placeShip(p, x, y, dir) end
  end
  local events = { { type = "placed", seat = p.seat } }
  fleetDone(s, p, other, events, rng)
  return events
end

local function undo(p)
  local n = p.placed
  if n == 0 then return {} end
  for y = 1, SIZE do
    for x = 1, SIZE do
      if p.grid[y][x] == n then p.grid[y][x] = 0 end
    end
  end
  p.fleet[n] = nil
  p.placed = n - 1
  return { { type = "undo", seat = p.seat } }
end

local function fire(s, p, other, x, y)
  if p.shots[y][x] ~= 0 then return {} end
  s.moves = s.moves + 1
  local n = other.grid[y][x]
  local ev = { type = "shot", seat = p.seat, x = x, y = y, hit = n ~= 0 }
  if n == 0 then
    p.shots[y][x] = MISS
  else
    p.shots[y][x] = HIT
    local ship = other.fleet[n]
    ship.hits = ship.hits + 1
    if ship.hits == M.SHIPS[n].len then
      for i = 0, ship.hits - 1 do
        p.shots[ship.dir == "v" and ship.y + i or ship.y][ship.dir == "h" and ship.x + i or ship.x] = SUNK
      end
      p.sunk = p.sunk + 1
      ev.sunk = M.SHIPS[n].name
    end
  end
  p.last = { x = x, y = y, hit = ev.hit, sunk = ev.sunk }
  if p.sunk == FLEET then
    endMatch(s, positionOf(s, p), "fleet")
  else
    s.turn = positionOf(s, other)
  end
  return { ev }
end

local function luckyShot(s, p, other, rng)
  local open = {}
  for y = 1, SIZE do
    for x = 1, SIZE do
      if p.shots[y][x] == 0 then open[#open + 1] = { x, y } end
    end
  end
  local pick = open[rng:below(#open) + 1]
  return fire(s, p, other, pick[1], pick[2])
end

--- A clock ran out. While shooting that is the match. While placing it waits on the other player, unless they are done or gone too.
local function timeout(s, p, other)
  local gone = { type = "forfeit", seat = p.seat, how = "timeout" }
  if s.phase == "fire" or other.ready then
    endMatch(s, positionOf(s, other), "timeout")
    return { gone }
  end
  if other.late then
    endMatch(s, 0, "void")
    return { { type = "void" } }
  end
  p.late, p.confirm = true, false
  return { { type = "late", seat = p.seat } }
end

--- Whether it is this player's moment to do anything.
local function canAct(s, p)
  if p.late then return false end
  if s.phase == "setup" then return not p.ready end
  return s.players[s.turn] == p
end

function M.waitingOn(s)
  local list = {}
  if s.phase == "setup" then
    for _, p in ipairs(s.players) do
      if not p.ready and not p.late then list[#list + 1] = p.seat end
    end
  elseif s.phase == "fire" then
    list[1] = s.players[s.turn].seat
  end
  return list
end

function M.actions(s, seat)
  local p = find(s, seat)
  if not p or s.phase == "over" or not canAct(s, p) then return {} end
  if p.confirm then
    return {
      { id = "keep", label = "KEEP PLAYING", color = "win", textColor = "ink" },
      { id = "concede_yes", label = "GIVE UP", color = "red", sub = "You lose " .. s.stake },
    }
  end
  local list = {}
  if s.phase == "setup" then
    list[1] = { id = "rotate", label = p.dir == "h" and "ACROSS" or "DOWN", sub = "Tap to turn", color = "blue" }
    list[2] = { id = "random", label = "RANDOM", sub = "Place the rest", color = "accent", textColor = "ink" }
    if p.placed > 0 then list[3] = { id = "undo", label = "UNDO", color = "panel2" } end
  else
    list[1] = { id = "lucky", label = "RANDOM SHOT", color = "accent", textColor = "ink" }
  end
  list[#list + 1] = { id = "concede", label = "GIVE UP", color = "red" }
  return list
end

function M.act(s, seat, id, value, rng)
  if s.phase == "over" or seat == nil or rng == nil then return {} end
  local p, other = find(s, seat)
  if not p then return {} end
  if not canAct(s, p) then return {} end
  if id == "timeout" then return timeout(s, p, other) end
  if p.confirm then
    if id == "keep" then
      p.confirm = false
      return { { type = "resume", seat = seat } }
    elseif id == "concede_yes" then
      endMatch(s, positionOf(s, other), "concede")
      return { { type = "forfeit", seat = seat, how = "concede" } }
    end
    return {}
  end
  if id == "concede" then
    p.confirm = true
    return { { type = "asked", seat = seat } }
  end
  if s.phase == "setup" then
    if id == "place" then return place(s, p, other, value, rng) end
    if id == "random" then return randomFleet(s, p, other, rng) end
    if id == "undo" then return undo(p) end
    if id == "rotate" then
      p.dir = p.dir == "h" and "v" or "h"
      return { { type = "rotate", seat = seat } }
    end
    return {}
  end
  if id == "fire" then
    local x, y = M.square(value)
    if not x then return {} end
    return fire(s, p, other, x, y)
  end
  if id == "lucky" then return luckyShot(s, p, other, rng) end
  return {}
end

--- A missing player loses. Nothing else is safe at a stake: a shot or a fleet from the computer could win them the match.
function M.auto()
  return "timeout"
end

--- What anyone may know of a player: what they have fired at, and what the sinkings have announced.
local function publicPlayer(s, p, over)
  local lost = {}
  for n, ship in ipairs(M.SHIPS) do
    local placed = p.fleet[n]
    lost[n] = placed ~= nil and placed.hits == ship.len
  end
  local out = { seat = p.seat, name = p.name, placed = p.placed, ready = p.ready, late = p.late, sunk = p.sunk, lost = lost,
    shots = copy(p.shots), last = copy(p.last), seal = p.seal }
  if over then
    out.grid = copy(p.grid)
    if p.seal then out.proof = fleetText(p) end
  end
  return out
end

--- What a seat may know: their own fleet, every shot, and which ships have gone down. seat nil, or a seat not in the match, sees no fleet
-- until it is over.
function M.viewFor(s, seat)
  local over = s.phase == "over"
  local view = { phase = s.phase, over = over, moves = s.moves, stake = s.stake, how = s.how, players = {},
    turn = s.phase == "fire" and s.players[s.turn].seat or false,
    winner = s.winner ~= 0 and s.players[s.winner].seat or false }
  for position, p in ipairs(s.players) do view.players[position] = publicPlayer(s, p, over) end
  local own = seat and find(s, seat)
  if own then
    view.seat = seat
    local hits = {}
    for n, ship in ipairs(own.fleet) do hits[n] = ship.hits end
    view.you = { grid = copy(own.grid), hits = hits, dir = own.dir, confirm = own.confirm }
  end
  return view
end

function M.done(s)
  return s.phase == "over"
end

function M.nets(s)
  local nets = {}
  for _, p in ipairs(s.players) do nets[p.seat] = 0 end
  if s.winner ~= 0 then
    nets[s.players[s.winner].seat] = s.stake
    nets[s.players[3 - s.winner].seat] = -s.stake
  end
  return nets
end

--- How the match was decided, in a line anyone may read.
local function reason(s)
  local winner = s.winner ~= 0 and s.players[s.winner] or nil
  local loser = s.winner ~= 0 and s.players[3 - s.winner] or nil
  if s.how == "void" then return "Nobody placed a fleet in time, so no tokens move" end
  if s.how == "timeout" then return loser.name .. " ran out of time" end
  if s.how == "concede" then return loser.name .. " gave up" end
  return winner.name .. " sank the whole fleet in " .. s.moves .. " shots"
end

function M.result(s, seat)
  if s.phase ~= "over" then return { kind = "push", title = "MATCH ON", detail = "" } end
  local line = reason(s)
  if s.winner == 0 then return { kind = "push", title = "NO MATCH", detail = line } end
  local p = seat and find(s, seat)
  if not p then return { kind = "win", title = s.players[s.winner].name .. " WINS", detail = line } end
  if s.players[s.winner] == p then return { kind = "win", title = "YOU WIN " .. s.stake, detail = line } end
  return { kind = "lose", title = "YOU LOSE " .. s.stake, detail = line }
end

--- All either player had at stake.
function M.risk(s, seat)
  return find(s, seat) and s.stake or 0
end

return M
