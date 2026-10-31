-- games/battleship/rules.lua
-- Battleship. Pure: no screen, sound or files. Each seat first places five ships, the first seat before the other, then
-- they take shots in turn. fleets[seat] and grids[seat] are that seat's secret; rules.viewFor is all anyone else is given.
-- shots[seat][y][x] is what seat knows about that cell of the enemy's water: 0 unfired, MISS, HIT or SUNK.

local M = { SIZE = 10, MISS = 1, HIT = 2, SUNK = 3 }

local SIZE, MISS, HIT, SUNK = M.SIZE, M.MISS, M.HIT, M.SUNK

M.SHIPS = {
  { name = "Carrier", len = 5 }, { name = "Battleship", len = 4 }, { name = "Cruiser", len = 3 },
  { name = "Submarine", len = 3 }, { name = "Destroyer", len = 2 },
}

local function grid(value)
  local out = {}
  for y = 1, SIZE do
    out[y] = {}
    for x = 1, SIZE do out[y][x] = value end
  end
  return out
end

function M.new(opts)
  local first = opts.first or 1
  return {
    turn = first, first = first, winner = 0, moves = 0, phase = "setup",
    placed = { 0, 0 }, salts = {}, fleets = { {}, {} }, grids = { grid(0), grid(0) },
    shots = { grid(0), grid(0) }, sunk = { 0, 0 }, lastShot = {},
  }
end

local function fits(g, len, x, y, dir)
  if x < 1 or y < 1 then return false end
  if dir == "h" and x + len - 1 > SIZE then return false end
  if dir == "v" and y + len - 1 > SIZE then return false end
  for i = 0, len - 1 do
    local cx, cy = dir == "h" and x + i or x, dir == "v" and y + i or y
    if g[cy][cx] ~= 0 then return false end
  end
  return true
end
M.fits = fits

--- Put the next ship down, and pass to the other seat, or start the shooting, once the fleet is complete.
local function placeShip(s, x, y, dir)
  local p = s.turn
  local n = s.placed[p] + 1
  local ship = M.SHIPS[n]
  s.fleets[p][n] = { x = x, y = y, dir = dir, hits = 0 }
  for i = 0, ship.len - 1 do
    s.grids[p][dir == "v" and y + i or y][dir == "h" and x + i or x] = n
  end
  s.placed[p] = n
  if n == #M.SHIPS then
    if s.placed[3 - p] < #M.SHIPS then
      s.turn = 3 - p
    else
      s.phase = "fire"
      s.turn = s.first
    end
  end
end

function M.checkAction(s, a)
  if s.winner ~= 0 then return false, "game over" end
  if a.kind == "forfeit" then return true end
  if s.phase == "setup" then
    if a.kind == "auto" then return true end
    if a.kind ~= "place" then return false, "Place your ships first" end
    if a.dir ~= "h" and a.dir ~= "v" then return false, "no such direction" end
    local ship = M.SHIPS[s.placed[s.turn] + 1]
    if not fits(s.grids[s.turn], ship.len, a.x, a.y, a.dir) then return false, "That ship does not fit there" end
    return true
  end
  if a.kind ~= "fire" then return false, "no such move" end
  local row = s.shots[s.turn][a.y]
  if not row or row[a.x] == nil then return false, "no such square" end
  if row[a.x] ~= 0 then return false, "You already fired there" end
  return true
end

local function fire(s, a)
  local p, enemy = s.turn, 3 - s.turn
  s.moves = s.moves + 1
  s.lastShot[p] = { a.x, a.y }
  local n = s.grids[enemy][a.y][a.x]
  local ev = { type = "shot", seat = p, x = a.x, y = a.y, hit = n ~= 0 }
  if n == 0 then
    s.shots[p][a.y][a.x] = MISS
  else
    s.shots[p][a.y][a.x] = HIT
    local ship = s.fleets[enemy][n]
    ship.hits = ship.hits + 1
    if ship.hits == M.SHIPS[n].len then
      for i = 0, ship.hits - 1 do
        s.shots[p][ship.dir == "v" and ship.y + i or ship.y][ship.dir == "h" and ship.x + i or ship.x] = SUNK
      end
      s.sunk[p] = s.sunk[p] + 1
      ev.sunk = M.SHIPS[n].name
      if s.sunk[p] == #M.SHIPS then s.winner = p end
    end
  end
  if s.winner == 0 then s.turn = enemy end
  return { ev }
end

function M.step(s, a, rng)
  local ok, why = M.checkAction(s, a)
  if not ok then return nil, why end
  if a.kind == "forfeit" then
    s.winner, s.forfeit = 3 - a.seat, a.seat
    return s, {}
  end
  if a.kind == "fire" then return s, fire(s, a) end
  local p = s.turn
  if a.kind == "place" then
    placeShip(s, a.x, a.y, a.dir)
    if s.placed[p] == #M.SHIPS then s.salts[p] = rng and rng(2147483646) or 0 end
    return s, { { type = "placed", seat = p } }
  end
  -- auto: the rest of this seat's fleet, wherever the dice say
  while s.turn == p and s.phase == "setup" do
    local ship = M.SHIPS[s.placed[p] + 1]
    local x, y, dir = rng(SIZE), rng(SIZE), rng(2) == 1 and "h" or "v"
    if fits(s.grids[p], ship.len, x, y, dir) then placeShip(s, x, y, dir) end
  end
  s.salts[p] = rng(2147483646)
  return s, { { type = "placed", seat = p } }
end

--- The moves a missed timer can pick from. Placing by hand is for people, so setup offers the dice.
function M.legalActions(s)
  local out = {}
  if s.winner ~= 0 then return out end
  if s.phase == "setup" then return { { kind = "auto" } } end
  local row = s.shots[s.turn]
  for y = 1, SIZE do
    for x = 1, SIZE do
      if row[y][x] == 0 then out[#out + 1] = { kind = "fire", x = x, y = y } end
    end
  end
  return out
end

--- Every place the next ship could go.
function M.placements(s)
  local out = {}
  local ship = M.SHIPS[s.placed[s.turn] + 1]
  for _, dir in ipairs({ "h", "v" }) do
    for y = 1, SIZE do
      for x = 1, SIZE do
        if fits(s.grids[s.turn], ship.len, x, y, dir) then out[#out + 1] = { kind = "place", x = x, y = y, dir = dir } end
      end
    end
  end
  return out
end

function M.key(a)
  if a.kind == "fire" then return "fire " .. a.x .. "," .. a.y end
  if a.kind == "place" then return "place " .. a.x .. "," .. a.y .. "," .. a.dir end
  return a.kind
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

--- A fleet as text, with a random salt so a seal can't be guessed by trying fleets. Seat's secret until the game ends.
function M.fleetText(s, seat)
  local parts = {}
  for n, ship in ipairs(s.fleets[seat]) do parts[n] = ship.x .. "," .. ship.y .. ship.dir end
  return table.concat(parts, ";") .. "|" .. tostring(s.salts[seat])
end

--- What seat may know: their own fleet, every shot, and which enemy ships are still afloat, which sinking announces.
function M.viewFor(s, seat)
  local enemy = 3 - seat
  local afloat = {}
  for n, ship in ipairs(s.fleets[enemy]) do
    if ship.hits < M.SHIPS[n].len then afloat[#afloat + 1] = n end
  end
  return {
    turn = s.turn, first = s.first, winner = s.winner, moves = s.moves, phase = s.phase, lastShot = copy(s.lastShot),
    seat = seat, placed = { [seat] = s.placed[seat] },
    fleets = { [seat] = copy(s.fleets[seat]) }, grids = { [seat] = copy(s.grids[seat]) },
    shots = copy(s.shots), sunk = copy(s.sunk), afloat = afloat,
  }
end

function M.snapshot(s)
  local letters = { [0] = ".", [MISS] = "o", [HIT] = "x", [SUNK] = "#" }
  local function rows(g)
    local out = {}
    for y = 1, SIZE do
      local row = {}
      for x = 1, SIZE do row[x] = letters[g[y][x]] end
      out[y] = table.concat(row)
    end
    return out
  end
  return { phase = s.phase, shots = { rows(s.shots[1]), rows(s.shots[2]) }, sunk = { s.sunk[1], s.sunk[2] } }
end

return M
