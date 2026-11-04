-- catan_test.lua
-- Catan on Game Night: the island and its fair numbers, setup, what a roll pays, the robber and a 7, every build and what it costs,
-- the development cards, the longest road (broken ones too), the largest army, trades with the bank, harbours and players, winning
-- at 10, the computer players always moving legally, whole games played by the computer to the end, the group contract, what each
-- seat may see, both pictures drawing, and the free table's wallet refusing every money call.
--   node tools/casinotest/unit.mjs catan        (in craftos-agent)

local kit = require("group_kit")
local testing = require("testing")
local eq, test, truthy = testing.eq, testing.test, testing.truthy

local plugin = kit.plugin("GameNight", "catan")
local rules = plugin.rules

-- The game's own modules, loaded the way the plugin loaded them
local function gameModule(name)
  local saved = package.path
  local root = "."
  for part in package.path:gmatch("[^;]+") do
    root = part:match("^(.*)[/\\]Tests[/\\]%?%.lua$") or root
  end
  package.path = root .. "/Games/GameNight/?.lua;" .. saved
  local mod = require("games.catan." .. name)
  package.path = saved
  return mod
end
local board = gameModule("board")
local core = gameModule("core")
local bot = gameModule("bot")

local function humans(n)
  local list = {}
  for i = 1, n do list[i] = { seat = i, name = "P" .. i, stack = 0 } end
  return list
end

local function fresh(n, seed)
  return (rules.new(humans(n or 0), 1, testing.fastRng(seed or 1), {}))
end

--- An empty board in the main part of player 1's turn, nothing built, everyone's hand empty.
local function blank(n, seed)
  local state = fresh(n or 0, seed)
  for v = 1, #board.vertices do
    state.owner[v] = 0
    state.city[v] = false
  end
  for e = 1, #board.edges do state.road[e] = 0 end
  for _, player in ipairs(state.players) do player.res = core.zero() end
  state.phase, state.turn, state.turnNo = "main", 1, 5
  state.bank = { 19, 19, 19, 19, 19 }
  return state
end

local function seatOf(state, p)
  return state.players[p].seat
end

local function humanIndex(state, seat)
  return rules.playerOfSeat(state, seat)
end

--- A path of corners joined by sides, as a list of sides.
local function pathEdges(corners)
  local list = {}
  for i = 1, #corners - 1 do
    local e = board.edgeBetween(corners[i], corners[i + 1])
    truthy(e, "corners " .. corners[i] .. " and " .. corners[i + 1] .. " are joined")
    list[#list + 1] = e
  end
  return list
end

--- A simple path of n sides along the coast, as corners.
local function coastPath(n, from)
  local corners = { board.edges[board.coast[from or 1]].a }
  local at = corners[1]
  local used = {}
  while #corners < n + 1 do
    local nextOne = nil
    for _, e in ipairs(board.vertices[at].edges) do
      local edge = board.edges[e]
      local other = edge.a == at and edge.b or edge.a
      if edge.coast and not used[e] and not nextOne then
        nextOne = other
        used[e] = true
      end
    end
    truthy(nextOne, "the coast goes on")
    corners[#corners + 1] = nextOne
    at = nextOne
  end
  return corners
end

local function act(state, p, id, value, rng)
  return rules.act(state, seatOf(state, p), id, value, rng or testing.fastRng(7))
end

-- ------------------------------------------------------------------ the island

test("catan: the island has 19 hexes, 54 corners, 72 sides and 9 harbours apart", function()
  eq(#board.hexes, 19, "hexes")
  eq(#board.vertices, 54, "corners")
  eq(#board.edges, 72, "sides")
  eq(#board.coast, 30, "coastal sides")
  eq(#board.harborSides, 9, "harbours")
  local used = {}
  for _, e in ipairs(board.harborSides) do
    local edge = board.edges[e]
    truthy(edge.coast, "a harbour is on the coast")
    truthy(not used[edge.a] and not used[edge.b], "no two harbours share a corner")
    used[edge.a], used[edge.b] = true, true
  end
  for v, vertex in ipairs(board.vertices) do
    truthy(#vertex.edges == 2 or #vertex.edges == 3, "corner " .. v .. " has 2 or 3 sides")
    truthy(#vertex.hexes >= 1 and #vertex.hexes <= 3, "corner " .. v .. " touches 1 to 3 hexes")
  end
  for h, hex in ipairs(board.hexes) do
    eq(#hex.corners, 6, "hex " .. h .. " corners")
    eq(#hex.sides, 6, "hex " .. h .. " sides")
  end
  -- Corner numbers go in reading order
  for v = 2, #board.vertices do
    local a, b = board.vertices[v - 1], board.vertices[v]
    truthy(a.y2 < b.y2 or (a.y2 == b.y2 and a.x2 < b.x2), "corners read top to bottom, left to right")
  end
end)

test("catan: every island is fair: the right tiles, numbers off the desert, no 6 or 8 together", function()
  for seed = 1, 150 do
    local state = fresh(0, seed)
    local terrains, numbers = {}, {}
    for h = 1, 19 do
      local t, n = state.terrain[h], state.number[h]
      terrains[t] = (terrains[t] or 0) + 1
      if t == 0 then
        eq(n, 0, "the desert has no number")
        eq(state.robber, h, "the robber starts on the desert")
      else
        truthy(n >= 2 and n <= 12 and n ~= 7, "a land hex has a number")
        numbers[n] = (numbers[n] or 0) + 1
      end
      for _, other in ipairs(board.hexes[h].near) do
        local a, b = state.number[h], state.number[other]
        truthy(not ((a == 6 or a == 8) and (b == 6 or b == 8)), "seed " .. seed .. ": 6s and 8s apart")
      end
    end
    eq(terrains[0], 1, "one desert")
    eq(terrains[1], 3, "hills")
    eq(terrains[2], 4, "forest")
    eq(terrains[3], 4, "pasture")
    eq(terrains[4], 4, "fields")
    eq(terrains[5], 3, "mountains")
    for n = 2, 12 do
      if n ~= 7 then eq(numbers[n] or 0, (n == 2 or n == 12) and 1 or 2, "tokens of " .. n) end
    end
    local kinds = {}
    for _, harbor in ipairs(state.harbors) do kinds[harbor.res] = (kinds[harbor.res] or 0) + 1 end
    eq(kinds[0], 4, "four 3:1 harbours")
    for r = 1, 5 do eq(kinds[r], 1, "one 2:1 harbour of each") end
    eq(#state.devDeck, 25, "25 development cards")
    if seed % 50 == 0 then testing.breathe() end
  end
end)

test("catan: the computer fills the table to four, and one or two people get a full game", function()
  for n = 0, 4 do
    local state = fresh(n, 3)
    eq(#state.players, 4, n .. " people make four players")
    local people = 0
    for _, player in ipairs(state.players) do
      if not player.bot then people = people + 1 end
    end
    eq(people, n, "people at the table")
  end
  local five = rules.new(humans(5), 1, testing.fastRng(1), {})
  eq(#five.players, 4, "never more than four")
end)

-- ------------------------------------------------------------------ setup

test("catan: setup goes in snake order, two settlements and roads each, and the second pays out", function()
  local state = fresh(0, 11)
  local order = {}
  local rng = testing.fastRng(5)
  while state.phase == "setup" do
    local p = rules.current(state)
    if state.setup.need == "town" then order[#order + 1] = p end
    local before = state.setup.at
    local ev = rules.act(state, nil, "bot", nil, rng)
    truthy(ev and #ev > 0, "the computer places")
    if state.setup.need == "road" and state.setup.at == before and before > 4 then
      -- The second settlement just went down: its resources came with it
      local got = 0
      for _, h in ipairs(board.vertices[state.setup.town].hexes) do
        if state.terrain[h] > 0 then got = got + 1 end
      end
      eq(core.total(state.players[p].res), got, "the second settlement pays one of each land around it")
    end
  end
  eq(table.concat(order, ","), "1,2,3,4,4,3,2,1", "snake order")
  for p = 1, 4 do
    local towns, cities, roads = core.countPieces(state, p)
    eq(towns, 2, "two settlements")
    eq(cities, 0, "no city")
    eq(roads, 2, "two roads")
  end
  eq(state.phase, "roll", "then player 1 rolls")
  eq(state.turn, 1, "player 1")
end)

test("catan: a setup settlement keeps the distance rule and its road touches it", function()
  local state = fresh(1, 2)
  local p = humanIndex(state, 1)
  -- Let the computer go until it is the person's turn
  local rng = testing.fastRng(3)
  while rules.current(state) ~= p do rules.act(state, nil, "bot", nil, rng) end
  eq(state.setup.need, "town", "a settlement first")
  -- A corner beside someone's settlement is refused
  local taken = nil
  for v = 1, 54 do
    if state.owner[v] ~= 0 then taken = v end
  end
  if taken then
    local near = board.vertices[taken].near[1]
    eq(act(state, p, "spot", near), nil, "next to a settlement is not on offer")
  end
  local view = rules.viewFor(state, 1)
  truthy(view.placing and #view.placing.spots > 0, "the places are shown")
  local spot = view.placing.spots[3]
  truthy(act(state, p, "spot", spot), "pick a spot")
  eq(rules.viewFor(state, 1).placing.sel, spot, "it is picked")
  truthy(act(state, p, "next"), "step on")
  truthy(act(state, p, "prev"), "and back")
  eq(rules.viewFor(state, 1).placing.sel, spot, "back where it was")
  truthy(act(state, p, "place"), "placed")
  eq(state.owner[spot], p, "the settlement is down")
  eq(state.setup.need, "road", "then its road")
  for _, e in ipairs(rules.viewFor(state, 1).placing.spots) do
    local edge = board.edges[e]
    truthy(edge.a == spot or edge.b == spot, "a setup road touches its settlement")
  end
  truthy(act(state, p, "place"), "the road")
end)

-- ------------------------------------------------------------------ rolling

test("catan: a roll pays every settlement once and every city twice, never the robber's hex", function()
  local state = blank(0)
  local h = nil
  for i = 1, 19 do
    if state.number[i] == 8 and not h then h = i end
  end
  local corners = board.hexes[h].corners
  state.owner[corners[1]] = 1
  state.owner[corners[3]] = 2
  state.city[corners[3]] = true
  state.phase = "roll"
  -- An rng that rolls 3 and 5
  local dice = { 3, 5 }
  local at = 0
  local rng = { below = function(_, n) at = at + 1 return dice[at] - 1 end }
  local t = state.terrain[h]
  local others1 = 0
  for _, other in ipairs(board.vertices[corners[1]].hexes) do
    if other ~= h and state.number[other] == 8 then others1 = others1 + 1 end
  end
  rules.act(state, nil, "bot", nil, rng)
  eq(state.dice[1] + state.dice[2], 8, "rolled 8")
  truthy(state.players[1].res[t] >= 1, "the settlement collects")
  eq(state.players[2].res[t] >= 2, true, "the city collects two")
  -- Again with the robber on it
  local before = core.copy(state.players[1].res)
  state.robber = h
  state.phase, at = "roll", 0
  rules.act(state, nil, "bot", nil, rng)
  if others1 == 0 then eq(state.players[1].res[t], before[t], "the robber's hex pays nothing") end
end)

test("catan: a short bank pays nobody when two are owed, and the only one owed what is left", function()
  local state = blank(0)
  local h = nil
  for i = 1, 19 do
    if state.number[i] == 6 and not h then h = i end
  end
  local t = state.terrain[h]
  local corners = board.hexes[h].corners
  state.owner[corners[1]] = 1
  state.city[corners[1]] = true
  state.owner[corners[4]] = 2
  state.bank[t] = 2
  state.phase = "roll"
  local dice = { 3, 3, 3, 3 }
  local at = 0
  local rng = { below = function() at = at + 1 return dice[at] - 1 end }
  -- Owed 3 together with only 2 in the bank: unless another 6 pays the same resource, nobody gets it
  local sameElsewhere = false
  for i = 1, 19 do
    if i ~= h and state.number[i] == 6 and state.terrain[i] == t then sameElsewhere = true end
  end
  rules.act(state, nil, "bot", nil, rng)
  if not sameElsewhere then
    eq(state.players[1].res[t], 0, "player 1 gets none")
    eq(state.players[2].res[t], 0, "player 2 gets none")
    eq(state.bank[t], 2, "the bank keeps it")
    -- Only one owed: they get what is left
    state.owner[corners[4]] = 0
    state.phase = "roll"
    rules.act(state, nil, "bot", nil, rng)
    eq(state.players[1].res[t], 2, "the only one owed takes the last two")
    eq(state.bank[t], 0, "the bank is empty")
  end
end)

test("catan: a 7 makes big hands give up half, then the robber moves and robs", function()
  local state = blank(2)
  local p1, p2 = humanIndex(state, 1), humanIndex(state, 2)
  state.turn = p1
  state.phase = "roll"
  state.players[p1].res = { 3, 3, 2, 0, 0 } -- 8 cards: gives up 4
  state.players[p2].res = { 2, 2, 2, 1, 0 } -- 7 cards: keeps them all
  local botP = nil
  for p, player in ipairs(state.players) do
    if player.bot then
      player.res = { 5, 5, 0, 0, 0 } -- 10: gives up 5
      botP = botP or p
    end
  end
  local dice = { 3, 4 }
  local at = 0
  local rng = { below = function(_, n) at = at + 1 return (dice[at] or 1) - 1 end }
  truthy(act(state, p1, "roll", nil, rng), "rolled")
  eq(state.phase, "discard", "the discard comes first")
  eq(core.total(state.players[botP].res), 5, "the computer gave up half at once")
  eq(state.discard[p1], 4, "player 1 owes four")
  eq(state.discard[p2], 0, "seven cards is safe")
  local waiting = rules.waitingOn(state)
  eq(#waiting, 1, "only the one who owes is waited on")
  eq(waiting[1], seatOf(state, p1), "player 1")
  eq(act(state, p1, "confirm"), nil, "not yet: nothing picked")
  for _ = 1, 3 do truthy(act(state, p1, "pick", 1), "pick a brick") end
  eq(act(state, p1, "pick", 1), nil, "only three bricks")
  truthy(act(state, p1, "pick", 2), "and a wood")
  eq(act(state, p1, "pick", 2), nil, "four is enough")
  truthy(act(state, p1, "confirm"), "given up")
  eq(core.total(state.players[p1].res), 4, "half left")
  eq(state.phase, "robber", "now the robber")
  -- Put player 2 beside a hex and rob there
  local target = state.robber == 1 and 2 or 1
  state.owner[board.hexes[target].corners[1]] = p2
  truthy(act(state, p1, "spot", target), "pick the hex")
  truthy(act(state, p1, "place"), "move the robber")
  eq(state.robber, target, "it moved")
  eq(core.total(state.players[p2].res), 6, "player 2 was robbed")
  eq(core.total(state.players[p1].res), 5, "player 1 has the card")
  eq(state.phase, "main", "on with the turn")
  -- The robber may not stay where it is
  state.phase = "robber"
  eq(act(state, p1, "spot", target), nil, "not the same hex")
end)

test("catan: with two to rob the roller chooses", function()
  local state = blank(2)
  local p1, p2 = humanIndex(state, 1), humanIndex(state, 2)
  local other = p1 == 1 and 2 or 1
  if other == p2 then other = 3 end
  state.turn = p1
  local target = state.robber == 1 and 2 or 1
  state.owner[board.hexes[target].corners[1]] = p2
  state.owner[board.hexes[target].corners[4]] = other
  state.players[p2].res = { 1, 0, 0, 0, 0 }
  state.players[other].res = { 0, 1, 0, 0, 0 }
  state.phase = "robber"
  truthy(act(state, p1, "spot", target), "pick")
  truthy(act(state, p1, "place"), "move")
  eq(state.phase, "steal", "choose whom")
  local view = rules.viewFor(state, seatOf(state, p1))
  eq(#view.victims, 2, "two to choose from")
  eq(act(state, p1, "steal", 99), nil, "not someone who is not there")
  truthy(act(state, p1, "steal", other), "rob the other one")
  eq(state.players[p1].res[2], 1, "took the wood")
  eq(state.phase, "main", "on with the turn")
end)

-- ------------------------------------------------------------------ building

test("catan: each build costs what it should and only goes where it may", function()
  local state = blank(1)
  local p = humanIndex(state, 1)
  state.turn = p
  local corners = coastPath(4)
  state.owner[corners[1]] = p
  local edges = pathEdges(corners)
  state.road[edges[1]] = p
  -- No cards: nothing can be built
  eq(act(state, p, "build", "road"), nil, "no road without cards")
  state.players[p].res = { 1, 1, 0, 0, 0 }
  truthy(act(state, p, "menu", "build"), "the build menu")
  truthy(act(state, p, "build", "road"), "a road")
  truthy(act(state, p, "spot", edges[2]), "on the next side")
  truthy(act(state, p, "place"), "placed")
  eq(state.road[edges[2]], p, "the road is down")
  eq(core.total(state.players[p].res), 0, "it cost a brick and a wood")
  eq(state.bank[1], 20, "back to the bank")
  -- A road must join the network
  state.players[p].res = { 1, 1, 0, 0, 0 }
  truthy(act(state, p, "build", "road"), "another road")
  local far = nil
  for e = 1, 72 do
    local edge = board.edges[e]
    if state.road[e] == 0 and not core.roadTo(state, p, edge.a) and not core.roadTo(state, p, edge.b) and state.owner[edge.a] ~= p and state.owner[edge.b] ~= p then far = e end
  end
  eq(act(state, p, "spot", far), nil, "a side away from the network is not on offer")
  truthy(act(state, p, "back"), "back")
  -- A settlement needs a road to it and room
  state.players[p].res = { 1, 1, 1, 1, 0 }
  eq(core.spacious(state, corners[2]), false, "right beside the first settlement")
  truthy(core.spacious(state, corners[3]), "two along is free")
  truthy(act(state, p, "build", "town"), "a settlement")
  truthy(act(state, p, "spot", corners[3]), "at the end of the road")
  truthy(act(state, p, "place"), "placed")
  eq(state.owner[corners[3]], p, "the settlement is down")
  eq(core.total(state.players[p].res), 0, "it cost one of four")
  -- A city goes on a settlement and costs 2 grain and 3 ore
  state.players[p].res = { 0, 0, 0, 2, 2 }
  eq(act(state, p, "build", "city"), nil, "short of ore")
  state.players[p].res = { 0, 0, 0, 2, 3 }
  truthy(act(state, p, "build", "city"), "a city")
  truthy(act(state, p, "spot", corners[1]), "on the first settlement")
  truthy(act(state, p, "place"), "placed")
  truthy(state.city[corners[1]], "a city now")
  eq(core.total(state.players[p].res), 0, "it cost five")
  eq(core.publicPoints(state, p), 3, "a city and a settlement")
  -- Pieces run out
  local towns = core.piecesLeft(state, p)
  eq(towns, 4, "four settlements left")
end)

test("catan: a road cannot go on through someone else's settlement", function()
  local state = blank(1)
  local p = humanIndex(state, 1)
  local other = p == 1 and 2 or 1
  state.turn = p
  local corners = coastPath(3)
  local edges = pathEdges(corners)
  state.owner[corners[1]] = p
  state.road[edges[1]] = p
  state.owner[corners[2]] = other
  local spots = core.roadSpots(state, p)
  for _, e in ipairs(spots) do
    truthy(e ~= edges[2], "the side past the other settlement is closed")
  end
end)

-- ------------------------------------------------------------------ development cards

test("catan: a card is bought for wool, grain and ore, and cannot be played the turn it is bought", function()
  local state = blank(1)
  local p = humanIndex(state, 1)
  state.turn = p
  state.devDeck[#state.devDeck] = "knight"
  state.players[p].res = { 0, 0, 1, 1, 1 }
  truthy(act(state, p, "buydev"), "bought")
  eq(#state.players[p].dev, 1, "a card in hand")
  eq(core.total(state.players[p].res), 0, "it cost three")
  eq(#state.devDeck, 24, "one fewer in the deck")
  eq(act(state, p, "play", "knight"), nil, "not the turn it was bought")
  truthy(act(state, p, "end"), "end the turn")
  -- Round to this player again
  while state.turn ~= p or state.phase ~= "roll" do
    local ev = rules.act(state, nil, "bot", nil, testing.fastRng(state.turnNo))
    truthy(ev, "the computer plays its turn")
  end
  truthy(act(state, p, "play", "knight"), "a knight before the roll")
  eq(state.phase, "robber", "the robber moves")
  eq(state.players[p].knights, 1, "one knight played")
  local target = state.robber == 5 and 6 or 5
  truthy(act(state, p, "spot", target), "pick")
  truthy(act(state, p, "place"), "move")
  truthy(state.phase == "roll" or state.phase == "steal", "back to the roll")
end)

test("catan: one card a turn; road building, year of plenty and monopoly do what they say", function()
  local state = blank(1)
  local p = humanIndex(state, 1)
  state.turn = p
  local corners = coastPath(5)
  local edges = pathEdges(corners)
  state.owner[corners[1]] = p
  state.road[edges[1]] = p
  state.players[p].dev = { { k = "roads", t = 1 }, { k = "plenty", t = 1 }, { k = "monopoly", t = 1 }, { k = "vp", t = 1 } }
  eq(act(state, p, "play", "vp"), nil, "a victory point is never played")
  truthy(act(state, p, "play", "roads"), "road building")
  eq(state.phase, "roads", "two free roads")
  truthy(act(state, p, "spot", edges[2]), "first")
  truthy(act(state, p, "place"), "placed")
  truthy(act(state, p, "spot", edges[3]), "second")
  truthy(act(state, p, "place"), "placed")
  eq(state.phase, "main", "done")
  eq(core.total(state.players[p].res), 0, "free")
  eq(act(state, p, "play", "plenty"), nil, "one card a turn")
  -- Next turn: plenty
  state.devPlayed, state.turnNo = false, state.turnNo + 1
  truthy(act(state, p, "play", "plenty"), "year of plenty")
  truthy(act(state, p, "pick", 5), "ore")
  truthy(act(state, p, "pick", 5), "ore again")
  truthy(act(state, p, "confirm"), "take them")
  eq(state.players[p].res[5], 2, "two ore")
  eq(state.bank[5], 17, "from the bank")
  -- And monopoly
  state.devPlayed, state.turnNo = false, state.turnNo + 1
  local others = 0
  for q, player in ipairs(state.players) do
    if q ~= p then
      player.res = { 0, 0, 0, q, 0 }
      others = others + q
    end
  end
  truthy(act(state, p, "play", "monopoly"), "monopoly")
  truthy(act(state, p, "pick", 4), "grain")
  truthy(act(state, p, "confirm"), "take it all")
  eq(state.players[p].res[4], others, "everyone's grain")
  for q, player in ipairs(state.players) do
    if q ~= p then eq(player.res[4], 0, "none left") end
  end
  eq(core.hiddenPoints(state, p), 1, "the victory point card counts, unseen")
  eq(rules.viewFor(state, nil).players[p].points, core.publicPoints(state, p), "the wall shows only public points")
end)

-- ------------------------------------------------------------------ longest road and largest army

test("catan: the longest road needs five, a tie keeps the holder, and a settlement can break it", function()
  local state = blank(0)
  local corners = coastPath(7)
  local edges = pathEdges(corners)
  for i = 1, 4 do state.road[edges[i]] = 1 end
  core.updateLongest(state)
  eq(core.longestRoad(state, 1), 4, "four sides")
  eq(state.longest, 0, "four is not enough")
  state.road[edges[5]] = 1
  core.updateLongest(state)
  eq(state.longest, 1, "five is")
  -- Player 2 matches it elsewhere: a tie, so player 1 keeps it
  local other = coastPath(5, 16)
  local otherEdges = pathEdges(other)
  for _, e in ipairs(otherEdges) do
    truthy(state.road[e] == 0, "a separate road")
    state.road[e] = 2
  end
  core.updateLongest(state)
  eq(core.longestRoad(state, 2), 5, "player 2 has five")
  eq(state.longest, 1, "a tie keeps the holder")
  -- Player 3 settles in the middle of player 1's road: 2 and 3 sides now
  state.owner[corners[3]] = 3
  core.updateLongest(state)
  eq(core.longestRoad(state, 1), 3, "broken in two")
  eq(state.longest, 2, "player 2 takes it")
  -- A branching road counts its longest trail, not every side
  local branch = blank(0)
  local trunk = coastPath(3)
  local trunkEdges = pathEdges(trunk)
  for _, e in ipairs(trunkEdges) do branch.road[e] = 1 end
  for _, e in ipairs(board.vertices[trunk[2]].edges) do
    if branch.road[e] == 0 then branch.road[e] = 1 end
  end
  eq(core.longestRoad(branch, 1), 3, "a fork is not one road")
  -- Nobody holds it when the holder drops and two others tie
  state.owner[corners[3]] = 0
  state.longest = 1
  for i = 1, 5 do state.road[edges[i]] = 0 end
  core.updateLongest(state)
  eq(state.longest, 2, "only player 2 has five now")
end)

test("catan: the largest army takes three knights and passes only to more", function()
  local state = blank(2)
  local p1, p2 = humanIndex(state, 1), humanIndex(state, 2)
  local function knight(p)
    state.turn, state.phase, state.devPlayed, state.turnNo = p, "main", false, state.turnNo + 1
    state.players[p].dev = { { k = "knight", t = 1 } }
    truthy(act(state, p, "play", "knight"), "a knight")
    local target = state.robber % 19 + 1
    truthy(act(state, p, "spot", target), "pick")
    truthy(act(state, p, "place"), "move")
    if state.phase == "steal" then act(state, p, "steal", core.victims(state, p, state.robber)[1]) end
  end
  knight(p1)
  knight(p1)
  eq(state.army, 0, "two is not an army")
  knight(p1)
  eq(state.army, p1, "three is")
  knight(p2)
  knight(p2)
  knight(p2)
  eq(state.army, p1, "matching it is not enough")
  knight(p2)
  eq(state.army, p2, "four beats three")
  eq(core.publicPoints(state, p2), 2, "worth two")
end)

-- ------------------------------------------------------------------ trading

test("catan: the bank takes four, three at a 3:1 harbour, two at its own harbour", function()
  local state = blank(1)
  local p = humanIndex(state, 1)
  state.turn = p
  state.players[p].res = { 4, 0, 0, 0, 0 }
  local give, get = { 4, 0, 0, 0, 0 }, { 0, 0, 0, 0, 1 }
  truthy(core.bankTradeOk(state, p, give, get), "four for one")
  truthy(not core.bankTradeOk(state, p, { 3, 0, 0, 0, 0 }, get), "not three without a harbour")
  truthy(not core.bankTradeOk(state, p, give, { 0, 0, 0, 1, 1 }), "not two for four")
  truthy(not core.bankTradeOk(state, p, give, { 1, 0, 0, 0, 0 }), "not the same thing back")
  truthy(act(state, p, "menu", "trade"), "trade")
  for _ = 1, 4 do truthy(act(state, p, "give", 1), "give brick") end
  eq(act(state, p, "give", 1), nil, "only four to give")
  truthy(act(state, p, "get", 5), "get ore")
  truthy(act(state, p, "bank"), "with the bank")
  eq(state.players[p].res[5], 1, "an ore")
  eq(state.players[p].res[1], 0, "the bricks went")
  -- Harbours
  local three, two = nil, nil
  for _, harbor in ipairs(state.harbors) do
    if harbor.res == 0 and not three then three = harbor end
    if harbor.res == 3 then two = harbor end
  end
  state.owner[board.edges[three.edge].a] = p
  eq(core.ratios(state, p)[1], 3, "3:1")
  state.owner[board.edges[two.edge].b] = p
  eq(core.ratios(state, p)[3], 2, "2:1 for wool")
  eq(core.ratios(state, p)[1], 3, "still 3:1 for the rest")
  state.players[p].res = { 0, 0, 4, 0, 0 }
  truthy(core.bankTradeOk(state, p, { 0, 0, 4, 0, 0 }, { 1, 1, 0, 0, 0 }), "four wool for two at 2:1")
end)

test("catan: an offer goes round the table, the computer answers, and the offerer picks who", function()
  local state = blank(2)
  local p1, p2 = humanIndex(state, 1), humanIndex(state, 2)
  state.turn = p1
  state.players[p1].res = { 2, 0, 0, 0, 0 }
  state.players[p2].res = { 0, 0, 0, 0, 1 }
  for _, player in ipairs(state.players) do
    if player.bot then player.res = { 0, 0, 0, 0, 3 } end
  end
  truthy(act(state, p1, "menu", "trade"), "trade")
  truthy(act(state, p1, "give", 1), "give a brick")
  truthy(act(state, p1, "give", 1), "two bricks")
  truthy(act(state, p1, "get", 5), "for an ore")
  truthy(act(state, p1, "offer"), "offered")
  truthy(state.offer, "an offer is open")
  local waiting = rules.waitingOn(state)
  eq(#waiting, 2, "the offerer and the other person")
  eq(act(state, p2, "end"), nil, "a responder can only answer")
  truthy(act(state, p2, "accept"), "accepted")
  eq(state.offer.answers[p2], "yes", "yes")
  local seen = rules.viewFor(state, nil).offer
  truthy(seen and seen.answers[p2] == "yes", "the wall shows who said yes")
  truthy(act(state, p1, "with", p2), "trade with player 2")
  eq(state.players[p1].res[5], 1, "player 1 has the ore")
  eq(state.players[p2].res[1], 2, "player 2 has the bricks")
  eq(state.offer, false, "closed")
  -- Nobody takes it: it closes by itself
  state.players[p1].res = { 1, 0, 0, 0, 0 }
  truthy(act(state, p1, "menu", "trade"), "trade again")
  truthy(act(state, p1, "give", 1), "a brick")
  truthy(act(state, p1, "get", 3), "for wool nobody has")
  truthy(act(state, p1, "offer"), "offered")
  eq(state.offer, false, "nobody could take it, so it closed")
end)

-- ------------------------------------------------------------------ winning and the clock

test("catan: ten points on your own turn wins", function()
  local state = blank(1)
  local p = humanIndex(state, 1)
  state.turn = p
  local count = 0
  for v = 1, 54 do
    if count < 4 and core.spacious(state, v) then
      state.owner[v] = p
      state.city[v] = true
      count = count + 1
    end
  end
  eq(core.points(state, p), 8, "eight points")
  state.players[p].dev = { { k = "vp", t = 1 } }
  eq(core.points(state, p), 9, "nine with the card")
  state.players[p].res = { 0, 0, 1, 1, 1 }
  state.devDeck[#state.devDeck] = "vp"
  truthy(act(state, p, "buydev"), "buy a card")
  eq(state.phase, "over", "a second VP card wins it")
  eq(state.winner, p, "the winner")
  truthy(rules.done(state), "the round is done")
  eq(rules.result(state, 1).kind, "win", "the winner's result")
  eq(rules.result(state, nil).kind, "win", "the table's line")
  eq(rules.nets(state)[1], 0, "free: nothing changes hands")
end)

test("catan: a clock run out plays the turn out, and the next clock is short", function()
  local state = blank(1)
  local p = humanIndex(state, 1)
  state.turn, state.phase = p, "roll"
  eq(rules.turnMs(state, 1), rules.TURN_MS, "a whole turn")
  local id = rules.auto(state, 1)
  local ev = rules.act(state, 1, id, nil, testing.fastRng(9))
  truthy(ev and #ev > 0, "the clock moved the game on")
  truthy(state.turn ~= p or state.phase ~= "roll", "rolled")
  if state.phase == "main" and state.turn == p then
    rules.act(state, 1, rules.auto(state, 1), nil, testing.fastRng(9))
  end
  eq(state.players[p].idle >= 1, true, "noted")
  eq(rules.turnMs(state, 1), rules.IDLE_MS, "a short clock until they press")
end)

-- ------------------------------------------------------------------ the computer, and whole games

local function legalCheck(state)
  -- Nothing ever goes negative, and the cards add up to 19 of each
  for r = 1, 5 do
    local total = state.bank[r]
    truthy(state.bank[r] >= 0, "the bank never goes below nought")
    for _, player in ipairs(state.players) do
      truthy(player.res[r] >= 0, "a hand never goes below nought")
      total = total + player.res[r]
    end
    eq(total, 19, "every " .. board.RES_NAME[r] .. " is somewhere")
  end
  for p = 1, #state.players do
    local towns, cities, roads = core.countPieces(state, p)
    truthy(towns <= 5 and cities <= 4 and roads <= 15, "pieces within the box")
  end
  -- The distance rule holds across the whole board
  for v = 1, 54 do
    if state.owner[v] ~= 0 then
      for _, n in ipairs(board.vertices[v].near) do eq(state.owner[n], 0, "no two buildings side by side") end
    end
  end
end

test("catan: whole games played by the computer finish with a winner on ten", function()
  local turns, sevens = 0, 0
  for seed = 1, 12 do
    local state = fresh(0, seed * 7)
    local rng = testing.fastRng(seed)
    local steps = 0
    while not rules.done(state) do
      steps = steps + 1
      truthy(steps < 6000, "seed " .. seed .. " never ended")
      eq(#rules.waitingOn(state), 0, "nobody is waited on with only the computer")
      local ev = rules.act(state, nil, "bot", nil, rng)
      truthy(ev and #ev > 0, "the computer always moves")
      for _, e in ipairs(ev) do
        if e.type == "seven" then sevens = sevens + 1 end
      end
      if steps % 25 == 0 then legalCheck(state) end
    end
    legalCheck(state)
    truthy(state.winner > 0, "a winner")
    truthy(core.points(state, state.winner) >= 10, "seed " .. seed .. ": the winner has ten (turn " .. state.turnNo .. ")")
    turns = turns + state.turnNo
    testing.breathe()
  end
  truthy(sevens > 0, "sevens came up")
  truthy(turns / 12 < 160, "games end in a sensible number of turns: " .. turns / 12)
end)

--- Steer a person the way the computer would, mostly, and press at random the rest of the time.
local function sensible(state, seat, actions, rng)
  if rng:below(100) < 25 then return nil end
  local p = rules.playerOfSeat(state, seat)
  local live = {}
  for _, action in ipairs(actions) do
    if not action.disabled then live[action.id .. ":" .. tostring(action.value)] = action end
  end
  local function has(id, value) return live[id .. ":" .. tostring(value)] ~= nil end
  if has("place", nil) and rng:below(100) < 80 then return "place" end
  if has("confirm", nil) then return "confirm" end
  if state.phase == "discard" then
    local give = bot.discard(state, p, state.discard[p])
    local pick = state.players[p].ui.pick
    for r = 1, 5 do
      if pick[r] < give[r] then return "pick", r end
    end
  end
  if has("roll", nil) then return "roll" end
  if has("accept", nil) and rng:below(2) == 0 then return "accept" end
  if has("decline", nil) then return "decline" end
  if state.phase == "main" and state.players[p].ui.mode == "main" then
    local command = bot.step(state, p)
    if command[1] == "end" then return "end" end
    if command[1] == "city" or command[1] == "town" or command[1] == "road" then return "menu", "build" end
    if command[1] == "dev" then return "menu", "build" end
    return "end"
  end
  if has("buydev", nil) then return "buydev" end
  for _, kind in ipairs({ "city", "town", "road" }) do
    if has("build", kind) then return "build", kind end
  end
  return nil
end

test("catan: keeps the group contract with people, the computer and run-out clocks", function()
  kit.fuzz(plugin, { rounds = 6, seats = { 1, 2, 3, 4 }, absent = 8, pick = sensible, steps = 30000 })
end)

test("catan: no seat ever sees another's cards, and the wall sees none", function()
  local state = fresh(3, 21)
  local rng = testing.fastRng(4)
  for _ = 1, 400 do
    if rules.done(state) then break end
    local waiting = rules.waitingOn(state)
    if #waiting == 0 then
      rules.act(state, nil, "bot", nil, rng)
    else
      local seat = waiting[1]
      rules.act(state, seat, rules.auto(state, seat), nil, rng)
    end
    local public = rules.viewFor(state, nil)
    eq(public.hand, nil, "the wall has no hand")
    eq(public.dev, nil, "the wall has no cards")
    for seat = 1, 3 do
      local view = rules.viewFor(state, seat)
      eq(view.me, rules.playerOfSeat(state, seat), "a seat sees itself")
      for _, player in ipairs(view.players) do
        eq(player.res, nil, "nobody's hand is in the player list")
        eq(player.dev, nil, "nobody's cards are in the player list")
        eq(player.ui, nil, "nobody's menu is in the player list")
      end
    end
  end
end)

-- ------------------------------------------------------------------ pictures

local canvas = require("lib.casino.canvas")
local seatui = require("lib.casino.group.seatui")

local function drawn(c)
  local colors = {}
  for y = 1, c.h do
    for ch in c:rowColors(y):gmatch(".") do colors[ch] = true end
  end
  local n = 0
  for _ in pairs(colors) do n = n + 1 end
  return n
end

test("catan: the wall and a seat draw every stage of a game without a mistake", function()
  local state = fresh(2, 33)
  local rng = testing.fastRng(8)
  local stage = 0
  local function look()
    local wall = canvas.new(nil, 121, 81)
    plugin.tableView.draw(wall, rules.viewFor(state, nil), nil, { waiting = {}, seats = {}, clocks = {} })
    truthy(drawn(wall) >= 8, "the wall has a picture")
    for seat = 1, 2 do
      local c = canvas.new(nil, seatui.W, seatui.H)
      local view = rules.viewFor(state, seat)
      plugin.seatView.draw(c, view, nil, { seat = seat, name = "P" .. seat })
      truthy(drawn(c) >= 5, "a seat has a picture")
      local regions = plugin.seatView.regions(view)
      for _, r in ipairs(regions) do
        truthy(r.x >= 1 and r.y >= seatui.TOP and r.x + r.w - 1 <= seatui.W and r.y + r.h - 1 <= 39, "a region stays in the game's area")
      end
    end
    stage = stage + 1
  end
  for _ = 1, 3000 do
    if rules.done(state) then break end
    look()
    local waiting = rules.waitingOn(state)
    if #waiting == 0 then
      rules.act(state, nil, "bot", nil, rng)
    else
      local seat = waiting[rng:below(#waiting) + 1]
      local id, value = sensible(state, seat, rules.actions(state, seat), rng)
      if not id or not rules.act(state, seat, id, value, rng) then rules.act(state, seat, rules.auto(state, seat), nil, rng) end
    end
    if stage % 40 == 0 then testing.breathe() end
  end
  look()
  truthy(stage > 50, "many stages drawn")
end)

-- ------------------------------------------------------------------ free play

test("game night: the free wallet refuses every money call and the books refuse everything", function()
  local free = require("lib.casino.group.free")
  local real = { livePlayer = function() return "Ann" end, hostName = function() return "Owner" end, balance = function() return 5 end,
    send = function() return true end }
  local wallet = free.wallet(real)
  eq(wallet.livePlayer(), "Ann", "who touched still works")
  eq(wallet.hostName(), "Owner", "who owns it still works")
  eq(wallet.isApproved(), false, "nobody is ever approved for money")
  for _, name in ipairs({ "balance", "send", "hostBalance", "requestApproval", "ledgerMoved", "ledgerShows", "wasSettled" }) do
    local ok = pcall(function() return wallet[name]("Ann", 10) end)
    truthy(not ok, "wallet." .. name .. " refuses")
  end
  for _, name in ipairs({ "move", "resolve" }) do
    local ok = pcall(function() return free.books[name]("Ann", 10) end)
    truthy(not ok, "books." .. name .. " refuses")
  end
  -- The cabinet is free, and every net is nought
  local saved = package.path
  local root = "."
  for part in package.path:gmatch("[^;]+") do
    root = part:match("^(.*)[/\\]Tests[/\\]%?%.lua$") or root
  end
  package.path = root .. "/Games/GameNight/?.lua;" .. saved
  package.loaded["games.registry"] = nil
  local registry = require("games.registry")
  package.loaded["games.registry"] = nil
  package.path = saved
  eq(registry.free, true, "Game Night is a free cabinet")
  truthy(registry.find("catan"), "with Catan on it")
end)
