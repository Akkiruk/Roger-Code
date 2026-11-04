-- games/catan/seatView.lua
-- A player's own screen, 78 wide: their cards and what they can do. The island is on the wall, so most of the time this shows the
-- hand: five resource tiles, the development cards, points and what the last roll paid.
--
-- To place something (a settlement, a road, a city, the robber) it shows a small island with every place they may pick numbered,
-- the same numbers the wall shows, and the pick in gold. Tapping anywhere on the island picks the nearest place; < and > step
-- through them, best first; PLACE puts it down. The panel beside it says what the pick touches.
--
-- Trading, the cards that ask for a resource, and giving up cards after a 7 are rows of resource tiles to tap.

local board = require("games.catan.board")
local draw = require("games.catan.draw")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

local TOP = seatui.TOP          -- 10
local BOTTOM = 38               -- the last row of ours: the engine's note goes on 39
local W = seatui.W              -- 78
local MINI_W, MINI_CX, MINI_CY, MINI_LAND = 8, 27, 24, 0.88
local SIDE_X = 55
local TILE_W, TILE_GAP = 14, 1

local DEV_TEXT = {
  knight = "Move the robber and rob. Counts to the largest army.",
  roads = "Build two roads for free.",
  plenty = "Take any two resources from the bank.",
  monopoly = "Everyone gives you all of one resource.",
  vp = "One point, kept hidden until the end.",
}

local function short(name, room)
  name = tostring(name or "")
  if #name <= room then return name end
  return name:sub(1, room - 1) .. "."
end

local function wrap(text, width)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if #line + #word + 1 > width and line ~= "" then
      lines[#lines + 1] = line
      line = word
    else
      line = line == "" and word or (line .. " " .. word)
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

local function resText(list)
  local parts = {}
  for i = 1, 5 do
    if (list[i] or 0) > 0 then parts[#parts + 1] = list[i] .. " " .. board.RES_NAME[i] end
  end
  if #parts == 0 then return "nothing" end
  return table.concat(parts, ", ")
end

local function total(list)
  local sum = 0
  for i = 1, 5 do sum = sum + ((list or {})[i] or 0) end
  return sum
end

-- ------------------------------------------------------------------ what the seat is showing

--- Which screen this view calls for.
local function screenOf(view)
  local p = view.me
  if not p then return "watch" end
  if view.phase == "over" then return "hand" end
  if view.placing and view.placing.p == p and view.placing.spots and #view.placing.spots > 0 then return "place" end
  if view.phase == "discard" and (view.mustDiscard or 0) > 0 then return "discard" end
  local offer = view.offer
  if offer and offer.from ~= p and offer.answers[p] == "wait" then return "answer" end
  if offer and offer.from == p then return "offering" end
  if view.turn == p and view.phase == "steal" then return "steal" end
  if view.turn == p and view.phase == "main" then
    local mode = view.mode
    if mode == "trade" or mode == "plenty" or mode == "monopoly" or mode == "dev" or mode == "build" then return mode end
  end
  return "hand"
end
M.screenOf = screenOf

-- ------------------------------------------------------------------ pieces of the screen

--- A row of five resource tiles. counts is shown big; sub under the name. Returns their places, for regions.
local function tiles(c, y, h, counts, sub, dim)
  local places = {}
  for i = 1, 5 do
    local x = 2 + (i - 1) * (TILE_W + TILE_GAP) + 1
    local bg = (dim and dim[i]) and C.panel2 or draw.RES[i]
    local ink = (dim and dim[i]) and C.mute or draw.RES_INK[i]
    c:rect(x, y, TILE_W, h, bg)
    c:textCenter(x + math.floor(TILE_W / 2), y, board.RES_NAME[i], ink, bg)
    local text = tostring(counts[i] or 0)
    if h >= 7 then
      c:bigCenter(x + math.floor(TILE_W / 2), y + 1, text, ink, 1)
    else
      c:textCenter(x + math.floor(TILE_W / 2), y + 2, text, ink, bg)
    end
    if sub and sub[i] then c:textCenter(x + math.floor(TILE_W / 2), y + h - 1, sub[i], ink, bg) end
    places[i] = { x = x, y = y, w = TILE_W, h = h }
  end
  return places
end

local function header(c, view, text, color)
  c:rect(1, TOP, W, 1, C.feltDark)
  c:text(3, TOP, short(text, 56), color or C.gold, C.feltDark)
  local me = view.players[view.me]
  if me then
    local points = (me.total or me.points) .. " PTS"
    if (view.hidden or 0) > 0 and not me.total then points = me.points .. "+" .. view.hidden .. " PTS" end
    c:text(W - #points - 1, TOP, points, C.gold, C.feltDark)
    c:rect(W - #points - 4, TOP, 2, 1, draw.playerColor(me))
  end
end

local function devLine(view)
  local counts, order = {}, {}
  for _, card in ipairs(view.dev or {}) do
    local key = card.k .. (card.new and "*" or "")
    if not counts[key] then order[#order + 1] = key end
    counts[key] = (counts[key] or 0) + 1
  end
  if #order == 0 then return "No development cards" end
  local parts = {}
  for _, key in ipairs(order) do
    local new = key:sub(-1) == "*"
    local kind = new and key:sub(1, -2) or key
    local name = board.DEV_NAME[kind] or kind
    parts[#parts + 1] = (counts[key] > 1 and (counts[key] .. "x ") or "") .. name .. (new and " (new)" or "")
  end
  return "Cards: " .. table.concat(parts, ", ")
end

local function turnText(view)
  local p = view.me
  local who = view.players[view.turn]
  if view.phase == "over" then
    local winner = view.players[view.winner]
    return winner and (view.winner == p and "YOU WIN!" or (string.upper(winner.name) .. " WINS")) or "GAME OVER"
  end
  if view.phase == "setup" then
    if view.turn == p then return "SETUP: YOUR PLACEMENT" end
    return "SETUP: " .. string.upper(short(who and who.name, 12)) .. " IS PLACING"
  end
  if view.phase == "discard" then return "A SEVEN! WAITING FOR DISCARDS" end
  if view.turn == p then
    if view.phase == "roll" then return "YOUR TURN: ROLL THE DICE" end
    if view.phase == "robber" then return "YOUR TURN: MOVE THE ROBBER" end
    return "YOUR TURN"
  end
  return string.upper(short(who and who.name, 12)) .. "'S TURN"
end

--- The hand, and everything a player wants to know between moves.
local function handScreen(c, view)
  header(c, view, turnText(view))
  local hand = view.hand
  tiles(c, TOP + 2, 7, hand)
  local y = TOP + 10
  for _, line in ipairs(wrap(devLine(view), W - 4)) do
    if y <= TOP + 11 then c:text(3, y, line, C.text) end
    y = y + 1
  end
  y = TOP + 13
  local me = view.players[view.me]
  if view.dice then
    local roller = view.players[view.turn]
    local got = me and total(me.gain) > 0 and (" You got " .. resText(me.gain) .. ".") or ""
    c:text(3, y, short("Last roll " .. (view.dice[1] + view.dice[2]) .. "." .. got, W - 4), C.win)
  elseif me and total(me.gain) > 0 then
    c:text(3, y, short("Your settlement gave you " .. resText(me.gain) .. ".", W - 4), C.win)
  end
  if view.note then c:text(3, y + 1, short(view.note, W - 4), C.gold) end
  -- Costs, lit where they can be paid now
  y = TOP + 16
  local rows = {
    { "ROAD", { 1, 1, 0, 0, 0 }, view.left and view.left.road },
    { "SETTLEMENT", { 1, 1, 1, 1, 0 }, view.left and view.left.town },
    { "CITY", { 0, 0, 0, 2, 3 }, view.left and view.left.city },
    { "CARD", { 0, 0, 1, 1, 1 }, nil },
  }
  c:text(3, y, "BUILD COSTS", C.mute)
  for i, row in ipairs(rows) do
    local can = true
    for r = 1, 5 do
      if (hand[r] or 0) < row[2][r] then can = false end
    end
    local line = y + i
    c:text(3, line, row[1], can and C.win or C.text)
    local x = 15
    for r = 1, 5 do
      local n = row[2][r]
      if n > 0 then
        local chip = (n > 1 and n or "") .. board.RES_SHORT[r]
        c:text(x, line, " " .. chip .. " ", draw.RES_INK[r], draw.RES[r])
        x = x + #chip + 3
      end
    end
    if row[3] then c:text(36, line, row[3] .. " left", C.mute) end
  end
  -- Everyone at the table, on the last rows
  local sy = BOTTOM - 4
  c:text(3, sy, "THE TABLE", C.mute)
  for q, player in ipairs(view.players) do
    local col = 3 + ((q - 1) % 2) * 38
    local row = sy + 1 + math.floor((q - 1) / 2)
    c:rect(col, row, 2, 1, draw.playerColor(player))
    local text = ("%s %d pts, %d cards"):format(short(player.name, 10), player.total or player.points, player.cards)
    c:text(col + 3, row, text, view.turn == q and C.gold or C.text)
  end
  -- Harbours this player can use
  local rates = {}
  local base = 4
  for r = 1, 5 do
    if view.ratios then base = math.min(base, view.ratios[r] == 2 and base or view.ratios[r]) end
  end
  for r = 1, 5 do
    if view.ratios and view.ratios[r] == 2 then rates[#rates + 1] = "2:1 " .. board.RES_NAME[r] end
  end
  c:text(47, y, "BANK RATES", C.mute)
  table.insert(rates, 1, base .. ":1 for anything")
  if #rates == 1 then
    c:text(47, y + 1, rates[1], C.text)
  else
    for i, rate in ipairs(rates) do
      if i <= 5 then c:text(47, y + i, rate, C.text) end
    end
  end
  -- Longest road and largest army
  local holders = {}
  if view.longest ~= 0 then holders[#holders + 1] = "Longest road: " .. view.players[view.longest].name end
  if view.army ~= 0 then holders[#holders + 1] = "Largest army: " .. view.players[view.army].name end
  if #holders > 0 then c:text(3, BOTTOM, short(table.concat(holders, "   "), W - 4), C.mute) end
end

local function buildScreen(c, view)
  header(c, view, "BUILD: PICK WHAT TO BUILD")
  tiles(c, TOP + 2, 7, view.hand)
  local y = TOP + 11
  local left = view.left or {}
  c:text(3, y, "ROAD        1 BRICK, 1 WOOD                 " .. tostring(left.road) .. " left", C.text)
  c:text(3, y + 1, "SETTLEMENT  1 BRICK, 1 WOOD, 1 WOOL, 1 GRAIN  " .. tostring(left.town) .. " left", C.text)
  c:text(3, y + 2, "CITY        2 GRAIN, 3 ORE (on a settlement)  " .. tostring(left.city) .. " left", C.text)
  c:text(3, y + 3, "CARD        1 WOOL, 1 GRAIN, 1 ORE           " .. tostring(view.deck) .. " left", C.text)
  local lines = wrap("A settlement needs your road to reach it and no building on a corner next to it. A road joins your roads or buildings. "
    .. "Greyed out means you cannot pay for it or there is nowhere to put it yet.", W - 4)
  for i, line in ipairs(lines) do c:text(3, y + 5 + i, line, C.mute) end
end

local function devScreen(c, view)
  header(c, view, "YOUR DEVELOPMENT CARDS")
  local y = TOP + 2
  if #(view.dev or {}) == 0 then
    c:text(3, y, "You have no development cards. Buy one from BUILD.", C.text)
  end
  for _, card in ipairs(view.dev or {}) do
    if y <= BOTTOM - 3 then
      local ready = card.k ~= "vp" and not card.new and view.canPlay and view.canPlay[card.k]
      c:rect(3, y, 18, 1, ready and C.blue or C.panel2)
      c:text(4, y, board.DEV_NAME[card.k] or card.k, ready and C.text or C.mute, ready and C.blue or C.panel2)
      local note = DEV_TEXT[card.k] or ""
      if card.new then note = "Bought this turn: play it from your next turn." end
      c:text(23, y, short(note, W - 24), C.text)
      y = y + 2
    end
  end
  c:text(3, BOTTOM - 1, "One card a turn. A knight can also be played before you roll.", C.mute)
end

local function giveTiles(c, view, y, list, label, sub)
  c:text(3, y - 1, label, C.gold)
  return tiles(c, y, 6, list, sub)
end

local function tradeScreen(c, view)
  header(c, view, "TRADE: TAP WHAT YOU GIVE AND WANT")
  local hand = view.hand
  local haveSub = {}
  for i = 1, 5 do haveSub[i] = "have " .. hand[i] end
  giveTiles(c, view, TOP + 3, view.give or {}, "YOU GIVE", haveSub)
  local rateSub = {}
  for i = 1, 5 do rateSub[i] = "bank " .. (view.ratios and view.ratios[i] or 4) .. ":1" end
  giveTiles(c, view, TOP + 11, view.get or {}, "YOU WANT", rateSub)
  local y = TOP + 18
  c:text(3, y, "Give " .. resText(view.give or {}) .. ", want " .. resText(view.get or {}), C.text)
  local lines = wrap("BANK lights up when what you give matches your rates (4:1, or a harbour's 3:1 or 2:1) for as many as you want. "
    .. "OFFER asks every player: you pick one who accepts. CLEAR starts again.", W - 4)
  for i, line in ipairs(lines) do c:text(3, y + 1 + i, line, C.mute) end
end

local function pickScreen(c, view, title, help)
  header(c, view, title)
  local pick = view.pick or {}
  local sub = {}
  for i = 1, 5 do sub[i] = "have " .. view.hand[i] end
  c:text(3, TOP + 2, "TAP TO PICK", C.gold)
  tiles(c, TOP + 3, 7, pick, sub)
  for i, line in ipairs(wrap(help, W - 4)) do c:text(3, TOP + 12 + i, line, C.text) end
end

local function answerScreen(c, view)
  local offer = view.offer
  local from = view.players[offer.from]
  header(c, view, string.upper(short(from and from.name, 12)) .. " OFFERS YOU A TRADE")
  c:text(3, TOP + 2, "YOU GET", C.gold)
  tiles(c, TOP + 3, 6, offer.give)
  c:text(3, TOP + 10, "YOU GIVE", C.gold)
  tiles(c, TOP + 11, 6, offer.get)
  local can = true
  for i = 1, 5 do
    if view.hand[i] < offer.get[i] then can = false end
  end
  c:text(3, TOP + 18, "You have " .. resText(view.hand), C.text)
  c:text(3, TOP + 20, can and "ACCEPT, and they choose who to trade with." or "You do not have the cards to accept.", can and C.mute or C.orange)
end

local function offeringScreen(c, view)
  local offer = view.offer
  header(c, view, "YOUR OFFER TO THE TABLE")
  c:text(3, TOP + 2, "Give " .. resText(offer.give), C.text)
  c:text(3, TOP + 3, "Want " .. resText(offer.get), C.text)
  local y = TOP + 5
  for q, answer in ipairs(offer.answers) do
    if q ~= view.me then
      local player = view.players[q]
      c:rect(3, y, 2, 1, draw.playerColor(player))
      c:text(6, y, short(player.name, 16), C.text)
      local word = answer == "yes" and "ACCEPTS" or (answer == "no" and "no thanks" or "thinking...")
      c:text(24, y, word, answer == "yes" and C.win or C.mute)
      y = y + 2
    end
  end
  c:text(3, y + 1, "Tap a name below to trade, or CANCEL.", C.mute)
end

local function stealScreen(c, view)
  header(c, view, "ROB WHOM?")
  local y = TOP + 3
  for _, q in ipairs(view.victims or {}) do
    local player = view.players[q]
    c:rect(3, y, 2, 1, draw.playerColor(player))
    c:text(6, y, short(player.name, 16) .. "  " .. player.cards .. " cards  " .. player.points .. " points", C.text)
    y = y + 2
  end
  c:text(3, y + 1, "You take one card at random from them.", C.mute)
end

-- ------------------------------------------------------------------ placing on the small island

local KIND_TITLE = { town = "PLACE A SETTLEMENT", city = "BUILD A CITY", road = "PLACE A ROAD", robber = "MOVE THE ROBBER" }

local function geometry()
  return draw.layout(MINI_W, MINI_CX, MINI_CY, MINI_LAND)
end

--- What a spot touches, in lines for the side panel.
local function spotLines(view, kind, spot)
  local lines = {}
  local function hexLine(h)
    local t, n = view.terrain[h], view.number[h]
    if t == 0 then return { "DESERT", C.accent } end
    local text = (n > 0 and (n .. " ") or "") .. board.RES_NAME[t]
    if view.robber == h then text = text .. " (robber)" end
    return { text, draw.RES[t] }
  end
  if kind == "robber" then
    lines[#lines + 1] = hexLine(spot)
    local seen = {}
    for _, v in ipairs(board.hexes[spot].corners) do
      local owner = view.owner[v]
      if owner ~= 0 and owner ~= view.me and not seen[owner] then
        seen[owner] = true
        lines[#lines + 1] = { "Rob " .. view.players[owner].name .. " (" .. view.players[owner].cards .. ")", draw.playerColor(view.players[owner]) }
      end
    end
    if #lines == 1 then lines[#lines + 1] = { "Nobody to rob here", C.mute } end
    return lines
  end
  local corners = {}
  if kind == "road" then
    local edge = board.edges[spot]
    corners = { edge.a, edge.b }
    local hexes = board.edges[spot].hexes
    for _, h in ipairs(hexes) do lines[#lines + 1] = hexLine(h) end
    return lines
  end
  corners = { spot }
  for _, v in ipairs(corners) do
    for _, h in ipairs(board.vertices[v].hexes) do lines[#lines + 1] = hexLine(h) end
    for _, harbor in ipairs(view.harbors) do
      local edge = board.edges[harbor.edge]
      if edge.a == v or edge.b == v then
        lines[#lines + 1] = { harbor.res == 0 and "Harbour 3:1" or ("Harbour 2:1 " .. board.RES_NAME[harbor.res]), C.text }
      end
    end
  end
  return lines
end

local function placeScreen(c, view)
  local placing = view.placing
  local geo = geometry()
  -- The island on the left
  draw.island(c, geo, view, false)
  local kind = placing.kind
  local x = SIDE_X
  c:rect(x - 1, TOP, W - x + 2, BOTTOM - TOP + 1, C.panel)
  c:text(x, TOP + 1, KIND_TITLE[kind] or "PLACE", C.gold, C.panel)
  local sel = placing.sel
  local label = sel and (kind == "robber" and board.hexLabel(sel) or tostring(sel)) or "-"
  c:big(x, TOP + 3, label, C.gold, 2)
  local y = TOP + 16
  if sel then
    for _, line in ipairs(spotLines(view, kind, sel)) do
      if y <= TOP + 22 then
        c:rect(x, y, 2, 1, line[2])
        c:text(x + 3, y, short(line[1], W - x - 3), C.text, C.panel)
        y = y + 1
      end
    end
  end
  local help = "Tap the map near a spot, or < >. Then PLACE."
  if view.phase == "setup" and kind == "town" then help = "Best spots first. Tap the map or < >, then PLACE." end
  for i, line in ipairs(wrap(help, W - x - 1)) do c:text(x, TOP + 23 + i, line, C.mute, C.panel) end
  local hand = view.hand
  local hx = x
  for r = 1, 5 do
    local text = board.RES_SHORT[r] .. hand[r]
    c:text(hx, BOTTOM, text, draw.RES_INK[r], draw.RES[r])
    hx = hx + #text + 1
  end
end

--- Every cell of the small island goes to the nearest place on offer, so a tap anywhere near one picks it.
local regionCache = { key = nil, list = nil }

local function placeRegions(view)
  local placing = view.placing
  local key = placing.kind .. ":" .. table.concat(placing.spots, ",")
  if regionCache.key == key then return regionCache.list end
  local geo = geometry()
  local points = {}
  for i, spot in ipairs(placing.spots) do
    local at
    if placing.kind == "robber" then
      at = geo.hexAt[spot]
    elseif placing.kind == "road" then
      at = geo.edgeAt[spot]
    else
      at = geo.vertexAt[spot]
    end
    points[i] = { spot = spot, x = at.x, y = at.y }
  end
  local reach = (placing.kind == "robber" and 9 or 6) * 2
  local list = {}
  for y = TOP + 1, BOTTOM do
    local run = nil
    for x = 1, SIDE_X - 2 do
      local best, bestD = nil, reach * reach
      for _, point in ipairs(points) do
        local dx, dy = (x - point.x) * 2, (y - point.y) * 3
        local d = dx * dx + dy * dy
        if d < bestD then best, bestD = point.spot, d end
      end
      if run and run.value == best and best then
        run.w = run.w + 1
      else
        if run and run.value then list[#list + 1] = run end
        run = { id = "spot", value = best, x = x, y = y, w = 1, h = 1 }
      end
    end
    if run and run.value then list[#list + 1] = run end
  end
  regionCache.key, regionCache.list = key, list
  return list
end

-- ------------------------------------------------------------------ the screen

local function watchScreen(c, view)
  local geo = geometry()
  draw.island(c, geo, view, false)
  local x = SIDE_X
  c:rect(x - 1, TOP, W - x + 2, BOTTOM - TOP + 1, C.panel)
  c:text(x, TOP + 1, "CATAN", C.gold, C.panel)
  local y = TOP + 3
  for p, player in ipairs(view.players) do
    c:rect(x, y, 2, 1, draw.playerColor(player))
    c:text(x + 3, y, short(player.name, 12) .. " " .. (player.total or player.points), view.turn == p and C.gold or C.text, C.panel)
    y = y + 2
  end
  for i, line in ipairs(wrap("Watching. Sit down at the next game to play.", W - x - 1)) do c:text(x, y + i, line, C.mute, C.panel) end
end

function M.draw(c, view, anim, info)
  if not view or not view.terrain then return end
  local screen = screenOf(view)
  if screen == "watch" then
    watchScreen(c, view)
  elseif screen == "place" then
    placeScreen(c, view)
  elseif screen == "discard" then
    pickScreen(c, view, "A SEVEN: GIVE UP " .. view.mustDiscard .. " CARDS",
      "Tap a resource to give one up (picked: " .. total(view.pick) .. " of " .. view.mustDiscard .. "). CLEAR to start again.")
  elseif screen == "plenty" then
    pickScreen(c, view, "YEAR OF PLENTY: TAKE TWO", "Tap two resources (the same one twice is fine), then TAKE 2.")
  elseif screen == "monopoly" then
    pickScreen(c, view, "MONOPOLY: PICK ONE", "Tap one resource. Everyone gives you all they have of it.")
  elseif screen == "answer" then
    answerScreen(c, view)
  elseif screen == "offering" then
    offeringScreen(c, view)
  elseif screen == "steal" then
    stealScreen(c, view)
  elseif screen == "trade" then
    tradeScreen(c, view)
  elseif screen == "dev" then
    devScreen(c, view)
  elseif screen == "build" then
    buildScreen(c, view)
  else
    handScreen(c, view)
  end
  if anim and anim.ev.type == "roll" and anim.t < 0.7 then
    local k = math.floor(anim.t * 18)
    draw.die(c, W - 17, TOP + 12, k % 6 + 1)
    draw.die(c, W - 9, TOP + 12, (k * 5 + 3) % 6 + 1)
  end
end

--- Taps on the screen itself: the island while placing, and the resource tiles while trading or picking.
function M.regions(view)
  if not view or not view.me then return {} end
  local screen = screenOf(view)
  if screen == "place" then return placeRegions(view) end
  local list = {}
  local function row(id, y, h)
    for i = 1, 5 do
      local x = 2 + (i - 1) * (TILE_W + TILE_GAP) + 1
      list[#list + 1] = { id = id, value = i, x = x, y = y, w = TILE_W, h = h }
    end
  end
  if screen == "trade" then
    row("give", TOP + 3, 6)
    row("get", TOP + 11, 6)
  elseif screen == "discard" or screen == "plenty" or screen == "monopoly" then
    row("pick", TOP + 3, 7)
  end
  return list
end

return M
