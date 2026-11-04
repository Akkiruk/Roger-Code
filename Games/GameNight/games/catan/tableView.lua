-- games/catan/tableView.lua
-- The table's wall: only what everyone may see. The island on the left with every road, settlement, city, harbour and the robber,
-- and while someone is placing a piece the places they may pick, numbered as on their own screen. On the right each player's
-- points, how many cards they hold (never which), their knights and road, who holds the longest road and the largest army, whose
-- turn it is with their clock, and the dice. Along the bottom what has happened, and any trade on offer.

local board = require("games.catan.board")
local draw = require("games.catan.draw")
local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

local BOARD_W, BOARD_CX, BOARD_CY, LAND = 14, 43, 36, 0.93
local PANEL_X, PANEL_W = 87, 34
local BLOCK_Y, BLOCK_H = 15, 8
local LOG_Y = 63

local PHASE_TEXT = {
  roll = "rolls the dice", main = "is building and trading", robber = "moves the robber", steal = "picks whom to rob",
  roads = "builds two free roads", discard = "waits while big hands give up half",
}

local function short(name, room)
  name = tostring(name or "")
  if #name <= room then return name end
  return name:sub(1, room - 1) .. "."
end

local function status(view)
  local who = view.players[view.turn]
  local name = who and who.name or "?"
  if view.phase == "over" then
    local winner = view.players[view.winner]
    return winner and (winner.name .. " wins!") or "Game over"
  end
  if view.phase == "setup" then
    local what = view.placing and view.placing.kind == "road" and "a road" or "a settlement"
    return "Setup round " .. tostring(view.setupRound or 1) .. ": " .. name .. " places " .. what
  end
  if view.offer then
    local from = view.players[view.offer.from]
    return (from and from.name or "?") .. " offers a trade"
  end
  if view.phase == "discard" then return "A seven: big hands give up half" end
  return name .. " " .. (PHASE_TEXT[view.phase] or "")
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

local function gainText(gain)
  local parts = {}
  for i = 1, 5 do
    if (gain[i] or 0) > 0 then parts[#parts + 1] = "+" .. gain[i] .. " " .. board.RES_NAME[i] end
  end
  return table.concat(parts, " ")
end

--- One player's block: their colour, name, points, card counts, what they hold, their clock.
local function playerBlock(c, view, p, y, info, anim)
  local player = view.players[p]
  local acting = view.turn == p and view.phase ~= "over"
  local color = draw.playerColor(player)
  local bg = C.panel
  c:rect(PANEL_X, y, PANEL_W, BLOCK_H - 1, bg)
  if acting then c:frame(PANEL_X - 1, y - 1, PANEL_W + 2, BLOCK_H + 1, C.gold) end
  c:rect(PANEL_X, y, 2, BLOCK_H - 1, color)
  local name = short(player.name, 16)
  c:text(PANEL_X + 3, y, name, acting and C.gold or C.text, bg)
  if player.bot then c:text(PANEL_X + 4 + #name, y, "CPU", C.mute, bg) end
  -- Points, big. At the end the hidden cards are turned over
  local points = player.total or player.points
  local text = tostring(points)
  c:big(PANEL_X + PANEL_W - c:bigWidth(text, 1) - 1, y + 1, text, view.winner == p and C.win or C.gold, 1)
  c:text(PANEL_X + 3, y + 1, ("Cards %d  Dev %d"):format(player.cards, player.devs), C.text, bg)
  c:text(PANEL_X + 3, y + 2, ("Knights %d  Road %d"):format(player.knights, player.road), C.mute, bg)
  local badges = {}
  if view.longest == p then badges[#badges + 1] = { "ROAD+2", C.gold } end
  if view.army == p then badges[#badges + 1] = { "ARMY+2", C.red } end
  local bx = PANEL_X + 3
  for _, badge in ipairs(badges) do
    c:text(bx, y + 3, " " .. badge[1] .. " ", C.ink, badge[2])
    bx = bx + #badge[1] + 3
  end
  local gain = gainText(player.gain or {})
  if gain ~= "" then c:text(PANEL_X + 3, y + 4, short(gain, PANEL_W - 5), C.win, bg) end
  -- What they are doing, and how long they have
  local line, lineColor = nil, C.mute
  if player.discard and player.discard > 0 then
    line, lineColor = "Gives up " .. player.discard .. " cards", C.orange
  elseif view.offer and view.offer.from ~= p then
    local answer = view.offer.answers[p]
    if answer == "wait" then line = "Thinking about it..." elseif answer == "yes" then line, lineColor = "Will trade", C.win
    elseif answer == "no" then line = "No thanks" end
  elseif player.idle and player.idle > 0 and not player.bot then
    line, lineColor = "Away: short clock", C.orange
  end
  if line then c:text(PANEL_X + 3, y + 5, short(line, PANEL_W - 5), lineColor, bg) end
  local clock = player.seat and info and info.clocks and info.clocks[player.seat]
  if clock and clock.total and clock.total > 0 then
    local share = math.max(0, math.min(1, clock.left / clock.total))
    local w = PANEL_W - 3
    c:rect(PANEL_X + 3, y + 6, w, 1, C.ink)
    local filled = math.floor(w * share + 0.5)
    if filled > 0 then c:rect(PANEL_X + 3, y + 6, filled, 1, share < 0.25 and C.red or C.gold) end
    local secs = math.ceil(clock.left / 1000)
    local label = ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
    c:text(PANEL_X + PANEL_W - #label - 1, y + 5, label, share < 0.25 and C.red or C.text, bg)
  elseif acting and player.bot then
    c:text(PANEL_X + 3, y + 6, "thinking...", C.mute, bg)
  end
end

local function dice(c, view, anim)
  local y = 48
  local a, b = view.dice and view.dice[1], view.dice and view.dice[2]
  local rolling = anim and anim.ev.type == "roll" and anim.t < 0.7
  if rolling then
    local k = math.floor(anim.t * 18)
    a, b = k % 6 + 1, (k * 5 + 3) % 6 + 1
  end
  c:text(PANEL_X, y - 1, "DICE", C.mute)
  if not a then
    draw.die(c, PANEL_X, y, 0, C.panel2)
    draw.die(c, PANEL_X + 9, y, 0, C.panel2)
    return
  end
  local seven = not rolling and a + b == 7
  draw.die(c, PANEL_X, y, a, C.text, seven and C.red or C.ink)
  draw.die(c, PANEL_X + 9, y, b, C.text, seven and C.red or C.ink)
  if not rolling then
    c:big(PANEL_X + 19, y, "=" .. (a + b), seven and C.red or C.gold, 1)
  end
end

local function logLines(c, view)
  c:rect(2, LOG_Y - 2, 83, 10, C.feltDark)
  local lines = view.log or {}
  for i, line in ipairs(lines) do
    local fresh = i == #lines
    local text = short(line, 81)
    local y = LOG_Y + i - 1
    c:text(3, y, text, fresh and C.text or C.mute, C.feltDark)
    -- Each player's name in their own colour, so who did what can be read at a glance
    for _, player in ipairs(view.players) do
      local name = tostring(player.name or "")
      local from = name ~= "" and 1 or nil
      while from do
        local s, e = text:find(name, from, true)
        if not s then break end
        c:text(2 + s, y, name, draw.playerColor(player), C.feltDark)
        from = e + 1
      end
    end
  end
end

local function offerBox(c, view)
  local offer = view.offer
  local y = 58
  c:rect(PANEL_X - 1, y, PANEL_W + 2, 15, C.panel)
  local from = view.players[offer.from]
  c:text(PANEL_X, y + 1, short((from and from.name or "?") .. " OFFERS", PANEL_W), C.gold, C.panel)
  local function list(label, res, row)
    c:text(PANEL_X, row, label, C.mute, C.panel)
    local x = PANEL_X + 7
    for i = 1, 5 do
      if res[i] > 0 then
        local text = res[i] .. " " .. board.RES_NAME[i]
        c:text(x, row, " " .. text .. " ", draw.RES_INK[i], draw.RES[i])
        x = x + #text + 3
      end
    end
  end
  list("GIVES", offer.give, y + 3)
  list("WANTS", offer.get, y + 5)
  local row = y + 7
  for q, answer in ipairs(offer.answers) do
    if q ~= offer.from then
      local player = view.players[q]
      local word = answer == "yes" and "yes" or (answer == "no" and "no" or "...")
      local color = answer == "yes" and C.win or (answer == "no" and C.mute or C.text)
      c:text(PANEL_X, row, short(player.name, 14), draw.playerColor(player), C.panel)
      c:text(PANEL_X + 16, row, word, color, C.panel)
      row = row + 1
    end
  end
end

-- What each thing costs, as resource numbers in order, and what it is worth
local COSTS = {
  { "ROAD", { 1, 2 }, "" }, { "TOWN", { 1, 2, 3, 4 }, "1 PT" }, { "CITY", { 4, 4, 5, 5, 5 }, "2 PTS" },
  { "CARD", { 3, 4, 5 }, "DEV" },
}

--- The bank's cards and a card of what things cost, each resource a chip in its own colour.
local function bankBox(c, view)
  local y = 57
  c:text(PANEL_X, y, "BANK", C.mute)
  local deck = "DEV CARDS " .. tostring(view.deck)
  c:text(PANEL_X + PANEL_W - #deck, y, deck, C.mute)
  local x = PANEL_X
  for i = 1, 5 do
    local text = " " .. board.RES_SHORT[i] .. tostring(view.bank[i]) .. " "
    c:text(x, y + 1, text, draw.RES_INK[i], draw.RES[i])
    x = x + #text + 1
  end
  c:rect(PANEL_X - 1, y + 3, PANEL_W + 2, 10, C.panel)
  c:text(PANEL_X, y + 3, "BUILD COSTS", C.mute, C.panel)
  for row, item in ipairs(COSTS) do
    local ry = y + 3 + row * 2
    c:text(PANEL_X, ry, item[1], C.text, C.panel)
    local cx = PANEL_X + 6
    for _, r in ipairs(item[2]) do
      c:text(cx, ry, board.RES_SHORT[r], draw.RES_INK[r], draw.RES[r])
      cx = cx + 3
    end
    c:text(PANEL_X + PANEL_W - #item[3], ry, item[3], C.gold, C.panel)
  end
end

--- A word across the island for a big moment.
local function shout(c, text, color)
  local w = c:bigWidth(text, 1) + 6
  local x = BOARD_CX - math.floor(w / 2)
  c:rect(x, 32, w, 9, C.ink)
  c:frame(x, 32, w, 9, color)
  c:bigCenter(BOARD_CX, 34, text, color, 1)
end

--- A piece that has just gone down blinks gold for a moment.
local function blink(c, geo, view, anim)
  if not anim or anim.t > 0.8 or math.floor(anim.t * 8) % 2 == 1 then return end
  local ev = anim.ev
  if ev.type == "town" or ev.type == "city" then
    local x, y = draw.vertexCell(geo, ev.v)
    c:rect(x - 1, y - 1, 3, 2, C.gold)
  elseif ev.type == "road" then
    for _, at in ipairs(geo.channel[ev.e] or {}) do c:rect(at.x, at.y, 1, 1, C.gold) end
  elseif ev.type == "robber" then
    local x, y = draw.hexCell(geo, ev.h)
    c:frame(x - 6, y - 3, 12, 8, C.red)
  end
end

function M.draw(c, view, anim, info)
  if not view or not view.terrain then return end
  local geo = draw.layout(BOARD_W, BOARD_CX, BOARD_CY, LAND)
  draw.island(c, geo, view, true)
  blink(c, geo, view, anim)

  c:text(PANEL_X, 11, "TURN " .. tostring(math.max(1, view.turnNo or 0)), C.gold)
  if view.phase == "setup" then c:text(PANEL_X, 11, "SETUP          ", C.gold) end
  for i, line in ipairs(wrap(status(view), PANEL_W)) do
    if i <= 2 then c:text(PANEL_X, 11 + i, line, C.text) end
  end
  for p = 1, #view.players do playerBlock(c, view, p, BLOCK_Y + (p - 1) * BLOCK_H, info, anim) end
  dice(c, view, anim)
  logLines(c, view)
  if view.offer then offerBox(c, view) else bankBox(c, view) end

  -- Who is placing what, under the island, so the numbers on it make sense from across the room
  local placing = view.placing
  if placing and placing.spots and #placing.spots > 0 then
    local who = view.players[placing.p]
    local what = ({ town = "a settlement", city = "a city", road = "a road", robber = "the robber" })[placing.kind] or "a piece"
    local pick = placing.kind == "robber" and board.hexLabel(placing.sel or 1) or tostring(placing.sel or "")
    local text = (who and who.name or "?") .. " is placing " .. what .. ": " .. pick
    c:text(3, LOG_Y - 2, " " .. short(text, 78) .. " ", C.ink, draw.playerColor(who))
  end

  if anim then
    local ev = anim.ev
    if ev.type == "seven" then
      shout(c, "SEVEN! ROBBER", C.red)
    elseif ev.type == "win" then
      shout(c, string.upper(short(view.players[ev.p].name, 10)) .. " WINS", C.win)
    elseif ev.type == "longest" and ev.p ~= 0 then
      shout(c, "LONGEST ROAD", C.gold)
    elseif ev.type == "army" then
      shout(c, "LARGEST ARMY", C.gold)
    elseif ev.type == "turn" and view.players[ev.p] then
      shout(c, string.upper(short(view.players[ev.p].name, 10)) .. "'S TURN", draw.playerColor(view.players[ev.p]))
    elseif ev.type == "start" then
      shout(c, "NEW ISLAND", C.gold)
    end
  end
end

return M
