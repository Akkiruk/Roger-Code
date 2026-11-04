-- games/catan/bot.lua
-- The computer's choices, for its own players and for a person whose clock ran out. Each function looks at the state and says what
-- to do; rules.lua does it. Nothing here changes the state or rolls a die, so every choice is the same for the same game.
--
-- How it plays: settle on good numbers and a spread of resources, then aim each turn at the build it is closest to (a city, a
-- settlement where it has room, a road toward the next good spot, or a development card), trade with the bank when that finishes
-- the build, play a knight when the robber sits on it or the largest army is in reach, and put the robber on the leader.

local board = require("games.catan.board")
local core = require("games.catan.core")

local M = {}

M.MAX_STEPS = 24   -- moves in one turn before it ends the turn whatever it still wants

local function best(list, score)
  local top, value = nil, nil
  for _, item in ipairs(list) do
    local s = score(item)
    if value == nil or s > value then top, value = item, s end
  end
  return top, value
end

-- ------------------------------------------------------------------ setup

function M.setupTown(state, p)
  return (best(core.townSpots(state, p, true), function(v) return core.townValue(state, p, v) end))
end

--- The setup road from a new settlement: toward the best corner two steps away that could still take a settlement.
function M.setupRoad(state, p, town)
  local spots = core.roadSpots(state, p, town)
  return (best(spots, function(e)
    local edge = board.edges[e]
    local mid = edge.a == town and edge.b or edge.a
    local value = 0
    for _, w in ipairs(board.vertices[mid].near) do
      if w ~= town and core.spacious(state, w) then value = math.max(value, core.townValue(state, p, w)) end
    end
    return value - e * 0.0001
  end))
end

-- ------------------------------------------------------------------ roads toward somewhere

--- The road to build next toward the best place for a settlement within three roads, and that place. nil if there is none.
function M.roadTarget(state, p)
  local dist, first, queue = {}, {}, {}
  for v = 1, #board.vertices do
    local owner = state.owner[v]
    if owner == p or (owner == 0 and core.roadTo(state, p, v)) then
      dist[v] = 0
      queue[#queue + 1] = v
    end
  end
  local head = 1
  while head <= #queue do
    local v = queue[head]
    head = head + 1
    if dist[v] < 3 then
      for _, e in ipairs(board.vertices[v].edges) do
        if state.road[e] == 0 then
          local edge = board.edges[e]
          local w = edge.a == v and edge.b or edge.a
          if dist[w] == nil then
            dist[w] = dist[v] + 1
            first[w] = first[v] or e
            -- Nobody builds through someone else's settlement
            if state.owner[w] == 0 then queue[#queue + 1] = w end
          end
        end
      end
    end
  end
  local target, value = nil, nil
  for v, d in pairs(dist) do
    if d >= 1 and core.spacious(state, v) then
      local s = core.townValue(state, p, v) - 2.2 * d - v * 0.0001
      if value == nil or s > value then target, value = v, s end
    end
  end
  if not target then return nil end
  return first[target], target
end

--- Any road at all that keeps a network growing, for when a road has to be placed (road building, a clock run out).
function M.anyRoad(state, p)
  local e = M.roadTarget(state, p)
  if e then return e end
  local spots = core.roadSpots(state, p)
  return spots[1]
end

-- ------------------------------------------------------------------ what to aim for

--- The build to save for: whichever of a city or a settlement is closer, then a road toward room, then a card.
function M.goal(state, p)
  local player = state.players[p]
  local townsLeft, citiesLeft, roadsLeft = core.piecesLeft(state, p)
  local options = {}
  if townsLeft > 0 and #core.townSpots(state, p, false) > 0 then options[#options + 1] = "town" end
  if citiesLeft > 0 and #core.citySpots(state, p) > 0 then options[#options + 1] = "city" end
  if #options > 0 then
    return (best(options, function(kind)
      local _, short = core.missing(player.res, board.COST[kind])
      return -short + (kind == "city" and 0.5 or 0)
    end))
  end
  if roadsLeft > 0 and townsLeft > 0 and M.roadTarget(state, p) then return "road" end
  if #state.devDeck > 0 then return "dev" end
  return nil
end

--- One bank trade that brings the goal closer, if the cards to spare can finish it. Returns give, get.
function M.bankTrade(state, p, goal)
  if not goal then return nil end
  local res = state.players[p].res
  local cost = board.COST[goal]
  local miss, short = core.missing(res, cost)
  if short == 0 then return nil end
  local ratios = core.ratios(state, p)
  local lots, pick, pickLots = 0, nil, 0
  for i = 1, 5 do
    if miss[i] == 0 then
      local spare = math.floor((res[i] - cost[i]) / ratios[i])
      lots = lots + spare
      if spare > pickLots then pick, pickLots = i, spare end
    end
  end
  if lots < short or not pick then return nil end
  local want = nil
  for i = 1, 5 do
    if miss[i] > 0 and state.bank[i] > 0 and not want then want = i end
  end
  if not want then return nil end
  local give, get = core.zero(), core.zero()
  give[pick] = ratios[pick]
  get[want] = 1
  return give, get
end

-- ------------------------------------------------------------------ the robber

--- Where the robber hurts the leaders most and this player least, and whom to rob there.
function M.robber(state, p)
  local points = {}
  local top = 0
  for q = 1, #state.players do
    points[q] = core.publicPoints(state, q)
    if q ~= p and points[q] > top then top = points[q] end
  end
  local h = best(core.robberSpots(state), function(hex)
    local n = state.number[hex]
    local pips = n > 0 and board.PIPS[n] or 0
    local score = 0
    for _, v in ipairs(board.hexes[hex].corners) do
      local owner = state.owner[v]
      if owner ~= 0 then
        local weight = state.city[v] and 2 or 1
        if owner == p then
          score = score - weight * pips * 3
        else
          local lead = 1 + points[owner] / 4 + (points[owner] == top and 1 or 0)
          score = score + weight * pips * lead + (core.total(state.players[owner].res) > 0 and 1 or 0)
        end
      end
    end
    return score - hex * 0.0001
  end)
  return h, M.victim(state, p, core.victims(state, p, h))
end

--- Whom to rob from a list: the most points anyone can see, then the most cards.
function M.victim(state, p, list)
  return (best(list, function(q)
    return core.publicPoints(state, q) * 100 + core.total(state.players[q].res) - q * 0.01
  end))
end

-- ------------------------------------------------------------------ cards

--- Which cards to give up when a seven comes: from the biggest piles, keeping what the goal needs.
function M.discard(state, p, count)
  local res = core.copy(state.players[p].res)
  local goal = M.goal(state, p)
  local cost = goal and board.COST[goal] or core.zero()
  local out = core.zero()
  for _ = 1, count do
    local pick, value = nil, nil
    for i = 1, 5 do
      if res[i] > 0 then
        local s = res[i] - cost[i] * 1.5
        if value == nil or s > value then pick, value = i, s end
      end
    end
    if not pick then break end
    res[pick] = res[pick] - 1
    out[pick] = out[pick] + 1
  end
  return out
end

--- Whether to take another player's offer. give is what the offerer gives, get what they want from this player.
function M.accepts(state, p, offer)
  local res = state.players[p].res
  if not core.canAfford(res, offer.get) then return false end
  if core.points(state, offer.from) >= 8 then return false end
  if core.total(offer.give) < core.total(offer.get) then return false end
  local goal = M.goal(state, p)
  local cost = goal and board.COST[goal] or core.zero()
  local helps = false
  for i = 1, 5 do
    -- It never gives away what its own next build needs, and it wants something it is short of
    if offer.get[i] > 0 and res[i] - offer.get[i] < cost[i] then return false end
    if offer.give[i] > 0 and res[i] < cost[i] then helps = true end
  end
  return helps
end

--- A development card worth playing now, with what it needs: "knight", "roads", "plenty" { a, b }, "monopoly" r. Or nil.
function M.devPlay(state, p, beforeRoll)
  local player = state.players[p]
  if state.devPlayed then return nil end
  local have = {}
  for _, card in ipairs(player.dev) do
    if card.t < state.turnNo then have[card.k] = true end
  end
  if have.knight then
    local blocked = false
    for _, v in ipairs(board.hexes[state.robber].corners) do
      if state.owner[v] == p then blocked = true end
    end
    local holder = state.army
    local mine = player.knights + 1
    local takesArmy = holder ~= p and mine >= 3 and (holder == 0 or mine > state.players[holder].knights)
    if blocked or takesArmy then return "knight" end
  end
  if beforeRoll then return nil end
  local goal = M.goal(state, p)
  if have.roads then
    local _, _, roadsLeft = core.piecesLeft(state, p)
    if roadsLeft >= 1 and M.roadTarget(state, p) then return "roads" end
  end
  if have.plenty and goal then
    local miss, short = core.missing(player.res, board.COST[goal])
    if short >= 1 and short <= 2 then
      local picks = {}
      for i = 1, 5 do
        for _ = 1, miss[i] do picks[#picks + 1] = i end
      end
      picks[2] = picks[2] or (state.bank[5] > 0 and 5 or 4)
      if state.bank[picks[1]] > 0 and state.bank[picks[2]] > (picks[1] == picks[2] and 1 or 0) then return "plenty", picks end
    end
  end
  if have.monopoly then
    -- What the others hold of a resource is public arithmetic: all 19, less the bank's, less this player's own
    local pick, most = nil, 0
    for i = 1, 5 do
      local held = board.BANK - state.bank[i] - player.res[i]
      if held > most then pick, most = i, held end
    end
    if pick and most >= 4 then return "monopoly", pick end
  end
  return nil
end

--- The next move of a computer player in the main part of its turn. Returns a command for rules.lua:
-- { "city", v }, { "town", v }, { "road", e }, { "dev" }, { "play", kind, extra }, { "bank", give, get } or { "end" }.
function M.step(state, p)
  local player = state.players[p]
  if (state.steps or 0) >= M.MAX_STEPS then return { "end" } end
  local res = player.res
  local townsLeft, citiesLeft, roadsLeft = core.piecesLeft(state, p)

  if citiesLeft > 0 and core.canAfford(res, board.COST.city) then
    local v = best(core.citySpots(state, p), function(spot) return core.townValue(state, p, spot) - spot * 0.0001 end)
    if v then return { "city", v } end
  end
  if townsLeft > 0 and core.canAfford(res, board.COST.town) then
    local v = best(core.townSpots(state, p, false), function(spot) return core.townValue(state, p, spot) - spot * 0.0001 end)
    if v then return { "town", v } end
  end
  local kind, extra = M.devPlay(state, p, false)
  if kind then return { "play", kind, extra } end

  local goal = M.goal(state, p)
  if goal == "road" and roadsLeft > 0 and core.canAfford(res, board.COST.road) then
    local e = M.roadTarget(state, p)
    if e then return { "road", e } end
  end
  if #state.devDeck > 0 and core.canAfford(res, board.COST.dev) then
    -- A card when there is nothing better, or when the hand is big enough to fear a seven
    local after = core.copy(res)
    for i = 1, 5 do after[i] = after[i] - board.COST.dev[i] end
    local keep = goal and goal ~= "dev" and core.canAfford(after, board.COST[goal])
    if goal == "dev" or goal == nil or keep or core.total(res) >= 8 then return { "dev" } end
  end
  local give, get = M.bankTrade(state, p, goal)
  if give then return { "bank", give, get } end
  return { "end" }
end

return M
