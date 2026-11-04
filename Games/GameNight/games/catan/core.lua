-- games/catan/core.lua
-- What the rules and the computer players both need to know about a game in progress: what is legal where, what things cost, who
-- has the longest road, how many points a player has. Pure: it reads the state and changes only what a function says it changes.
--
-- The state's board is in dense lists so it saves and serialises plainly:
--   terrain[h] 0-5, number[h] (0 on the desert), owner[v] 0 or a player, city[v] bool, road[e] 0 or a player, robber = h,
--   harbors = { { edge, res } }, res 0 for three for one.
-- Players are numbered 1-4 in turn order. A player has res = { brick, lumber, wool, grain, ore }, dev = { { k, t } } (t is the turn
-- it was bought), knights, and pieces left.

local board = require("games.catan.board")

local M = {}

local RES_COUNT = 5

function M.total(list)
  local sum = 0
  for i = 1, RES_COUNT do sum = sum + (list[i] or 0) end
  return sum
end

function M.zero()
  return { 0, 0, 0, 0, 0 }
end

function M.copy(list)
  return { list[1] or 0, list[2] or 0, list[3] or 0, list[4] or 0, list[5] or 0 }
end

function M.canAfford(res, cost)
  for i = 1, RES_COUNT do
    if (res[i] or 0) < (cost[i] or 0) then return false end
  end
  return true
end

--- What a player is short of for a cost: a list and the total.
function M.missing(res, cost)
  local out, sum = M.zero(), 0
  for i = 1, RES_COUNT do
    out[i] = math.max(0, (cost[i] or 0) - (res[i] or 0))
    sum = sum + out[i]
  end
  return out, sum
end

function M.pay(state, p, cost)
  local player = state.players[p]
  for i = 1, RES_COUNT do
    player.res[i] = player.res[i] - cost[i]
    state.bank[i] = state.bank[i] + cost[i]
  end
end

-- ------------------------------------------------------------------ the board

--- Whether a corner and all its neighbours are empty: the distance rule.
function M.spacious(state, v)
  if state.owner[v] ~= 0 then return false end
  for _, n in ipairs(board.vertices[v].near) do
    if state.owner[n] ~= 0 then return false end
  end
  return true
end

--- Whether a player's road reaches this corner.
function M.roadTo(state, p, v)
  for _, e in ipairs(board.vertices[v].edges) do
    if state.road[e] == p then return true end
  end
  return false
end

--- Where a player may put a settlement. In setup, anywhere the distance rule allows.
function M.townSpots(state, p, setup)
  local list = {}
  for v = 1, #board.vertices do
    if M.spacious(state, v) and (setup or M.roadTo(state, p, v)) then list[#list + 1] = v end
  end
  return list
end

function M.citySpots(state, p)
  local list = {}
  for v = 1, #board.vertices do
    if state.owner[v] == p and not state.city[v] then list[#list + 1] = v end
  end
  return list
end

--- Whether a road of this player's may grow out of corner v: their building is there, or no one else's is and their road is.
local function reaches(state, p, v)
  local owner = state.owner[v]
  if owner == p then return true end
  if owner ~= 0 then return false end
  return M.roadTo(state, p, v)
end

--- Where a player may put a road. from limits it to the sides of one corner, as for a setup road.
function M.roadSpots(state, p, from)
  local list = {}
  if from then
    for _, e in ipairs(board.vertices[from].edges) do
      if state.road[e] == 0 then list[#list + 1] = e end
    end
    table.sort(list)
    return list
  end
  for e, edge in ipairs(board.edges) do
    if state.road[e] == 0 and (reaches(state, p, edge.a) or reaches(state, p, edge.b)) then list[#list + 1] = e end
  end
  return list
end

--- Where the robber may go: anywhere but where it is.
function M.robberSpots(state)
  local list = {}
  for h = 1, #board.hexes do
    if h ~= state.robber then list[#list + 1] = h end
  end
  return list
end

--- Who could be robbed on a hex by p: a building there and a card in hand.
function M.victims(state, p, h)
  local seen, list = {}, {}
  for _, v in ipairs(board.hexes[h].corners) do
    local owner = state.owner[v]
    if owner ~= 0 and owner ~= p and not seen[owner] and M.total(state.players[owner].res) > 0 then
      seen[owner] = true
      list[#list + 1] = owner
    end
  end
  table.sort(list)
  return list
end

--- Trade ratios for a player: 4, or 3 with a three for one harbour, or 2 for that resource.
function M.ratios(state, p)
  local out = { 4, 4, 4, 4, 4 }
  for _, harbor in ipairs(state.harbors) do
    local edge = board.edges[harbor.edge]
    if state.owner[edge.a] == p or state.owner[edge.b] == p then
      for i = 1, RES_COUNT do
        if harbor.res == 0 then
          out[i] = math.min(out[i], 3)
        elseif harbor.res == i then
          out[i] = 2
        end
      end
    end
  end
  return out
end

--- Whether giving give to the bank for get is a fair trade at these ratios: each resource given in whole lots of its ratio, as many
-- lots as cards taken, and nothing both given and taken.
function M.bankTradeOk(state, p, give, get)
  local ratios = M.ratios(state, p)
  local lots, wanted = 0, 0
  for i = 1, RES_COUNT do
    if give[i] > 0 and get[i] > 0 then return false end
    if give[i] % ratios[i] ~= 0 then return false end
    lots = lots + give[i] / ratios[i]
    wanted = wanted + get[i]
    if get[i] > state.bank[i] then return false end
  end
  return lots > 0 and lots == wanted and M.canAfford(state.players[p].res, give)
end

-- ------------------------------------------------------------------ points

--- The longest road a player has: the most sides in one trail, no side twice, broken at any corner someone else has built on.
function M.longestRoad(state, p)
  local best = 0
  local used = {}
  local function walk(v, length)
    if length > best then best = length end
    -- A trail cannot go on through someone else's building
    if length > 0 and state.owner[v] ~= 0 and state.owner[v] ~= p then return end
    for _, e in ipairs(board.vertices[v].edges) do
      if state.road[e] == p and not used[e] then
        used[e] = true
        local edge = board.edges[e]
        walk(edge.a == v and edge.b or edge.a, length + 1)
        used[e] = nil
      end
    end
  end
  for v = 1, #board.vertices do
    if M.roadTo(state, p, v) then walk(v, 0) end
  end
  return best
end

--- Who holds the longest road now. The holder keeps it on a tie, a broken road can lose it, and a tie for the most with the holder
-- out of it means nobody holds it.
function M.updateLongest(state)
  local lengths, top = {}, 0
  for p = 1, #state.players do
    lengths[p] = M.longestRoad(state, p)
    state.players[p].roadLength = lengths[p]
    if lengths[p] > top then top = lengths[p] end
  end
  local holder = state.longest
  if holder ~= 0 and lengths[holder] >= 5 and lengths[holder] >= top then return holder end
  local leaders = {}
  for p = 1, #state.players do
    if lengths[p] == top then leaders[#leaders + 1] = p end
  end
  if top >= 5 and #leaders == 1 then
    state.longest = leaders[1]
  else
    state.longest = 0
  end
  return state.longest
end

--- Points anyone can see: buildings, longest road, largest army.
function M.publicPoints(state, p)
  local points = 0
  for v = 1, #board.vertices do
    if state.owner[v] == p then points = points + (state.city[v] and 2 or 1) end
  end
  if state.longest == p then points = points + 2 end
  if state.army == p then points = points + 2 end
  return points
end

function M.hiddenPoints(state, p)
  local points = 0
  for _, card in ipairs(state.players[p].dev) do
    if card.k == "vp" then points = points + 1 end
  end
  return points
end

function M.points(state, p)
  return M.publicPoints(state, p) + M.hiddenPoints(state, p)
end

function M.countPieces(state, p)
  local towns, cities, roads = 0, 0, 0
  for v = 1, #board.vertices do
    if state.owner[v] == p then
      if state.city[v] then cities = cities + 1 else towns = towns + 1 end
    end
  end
  for e = 1, #board.edges do
    if state.road[e] == p then roads = roads + 1 end
  end
  return towns, cities, roads
end

--- How many of each piece a player has left to build.
function M.piecesLeft(state, p)
  local towns, cities, roads = M.countPieces(state, p)
  return board.PIECES.town - towns, board.PIECES.city - cities, board.PIECES.road - roads
end

-- ------------------------------------------------------------------ how good a corner is

--- What a corner makes, by pips per resource. The robber is left out: it moves.
function M.yields(state, v)
  local out = M.zero()
  for _, h in ipairs(board.vertices[v].hexes) do
    local t, n = state.terrain[h], state.number[h]
    if t > 0 and n > 0 then out[t] = out[t] + board.PIPS[n] end
  end
  return out
end

--- The harbour at a corner: nil, 0 for three for one, or the resource for two for one.
function M.harborAt(state, v)
  for _, harbor in ipairs(state.harbors) do
    local edge = board.edges[harbor.edge]
    if edge.a == v or edge.b == v then return harbor.res end
  end
  return nil
end

--- A player's production in pips per resource, cities counted twice.
function M.production(state, p)
  local out = M.zero()
  for v = 1, #board.vertices do
    if state.owner[v] == p then
      local y = M.yields(state, v)
      local times = state.city[v] and 2 or 1
      for i = 1, RES_COUNT do out[i] = out[i] + y[i] * times end
    end
  end
  return out
end

local WEIGHT = { 1.1, 1.1, 0.85, 1.0, 1.0 }

--- How much a settlement here is worth to player p: pips, a little more for what they do not make yet, and a harbour.
function M.townValue(state, p, v)
  local y = M.yields(state, v)
  local have = M.production(state, p)
  local score = 0
  for i = 1, RES_COUNT do
    score = score + y[i] * WEIGHT[i]
    if y[i] > 0 and have[i] == 0 then score = score + 2.5 end
  end
  local harbor = M.harborAt(state, v)
  if harbor == 0 then
    score = score + 1.5
  elseif harbor then
    score = score + (have[harbor] + y[harbor] >= 4 and 3 or 0.8)
  end
  return score
end

return M
