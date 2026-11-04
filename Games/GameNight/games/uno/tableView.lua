-- games/uno/tableView.lua
-- The table's wall, 121x81: only what everyone may see. In the middle the draw pile and the discard pile, big, the discard sitting
-- on a block of the colour in play with that colour's name under it, whose turn it is in large letters, which way play goes and
-- who is next, the last few cards played, and what has happened. Round the sides each player: name, score, how many cards they hold
-- (never which), UNO! when they have said it, a red CATCH when they have not, and their clock. Players go round the wall clockwise,
-- up the left and down the right, with arrows between them that turn round on a Reverse. Between hands the middle shows the scores.

local cards = require("games.uno.cards")
local draw = require("games.uno.draw")
local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

local TOP, BOTTOM = 10, 72
local SIDE_W = 32
local LEFT_X, RIGHT_X = 2, 89
local MID_X, MID_W = 36, 51
local CX = MID_X + math.floor(MID_W / 2)
local PANEL_H = 14

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

--- Where each player's panel goes: up the left from the bottom, then down the right from the top, so play goes round clockwise.
local function places(n)
  local left = math.ceil(n / 2)
  local right = n - left
  local out = {}
  local function column(count, x, upward, first)
    local total = count * PANEL_H + (count - 1) * 2
    local y0 = TOP + math.floor((BOTTOM - TOP + 1 - total) / 2)
    for i = 1, count do
      local slot = upward and (count - i) or (i - 1)
      out[first + i - 1] = { x = x, y = y0 + slot * (PANEL_H + 2), side = upward and "left" or "right" }
    end
  end
  column(left, LEFT_X, true, 1)
  if right > 0 then column(right, RIGHT_X, false, left + 1) end
  return out, left, right
end

local function clockOf(view, player, info)
  return player.seat and info and info.clocks and info.clocks[player.seat]
end

local function playerPanel(c, view, p, at, info)
  local player = view.players[p]
  local x, y = at.x, at.y
  local acting = view.turn == p and (view.phase == "play" or view.phase == "drawn" or view.phase == "color")
  local caught = view.window and view.window.p == p
  local bg = C.panel
  c:rect(x, y, SIDE_W, PANEL_H, bg)
  if acting then
    c:frame(x - 1, y - 1, SIDE_W + 2, PANEL_H + 2, C.gold)
    c:rect(x, y, SIDE_W, 1, C.gold)
  end
  local nameBg = acting and C.gold or bg
  local nameInk = acting and C.ink or C.text
  local name = short(player.name, 16)
  c:text(x + 1, y, name, nameInk, nameBg)
  if player.bot then c:text(x + 2 + #name, y, "CPU", acting and C.ink or C.mute, nameBg) end
  if view.dealer == p and view.phase ~= "goal" then c:text(x + 6 + #name, y, "D", acting and C.ink or C.orange, nameBg) end
  local score = tostring(player.score)
  c:text(x + SIDE_W - #score - 5, y, score .. " pts", acting and C.ink or C.gold, nameBg)
  -- How many cards: big, and as small backs
  local count = tostring(player.count)
  local countInk = player.count == 1 and C.gold or C.text
  if view.phase == "goal" then count, countInk = "-", C.mute end
  if view.phase ~= "goal" then c:big(x + 2, y + 2, count, countInk, 1) end
  if view.phase ~= "goal" then c:text(x + 2, y + 8, player.count == 1 and "card" or "cards", C.mute, bg) end
  local px, py = x + 13, y + 2
  local shown = math.min(player.count, 18)
  for i = 1, shown do
    local col = (i - 1) % 6
    local row = math.floor((i - 1) / 6)
    draw.pip(c, px + col * 3, py + row * 3)
  end
  if player.count > 18 then c:text(px + 18, py + 7, "+" .. (player.count - 18), C.mute, bg) end
  -- What they are doing
  local line, ink, back = nil, C.mute, bg
  if caught then
    line, ink, back = " NO UNO! CATCH! ", C.text, C.red
  elseif player.said and player.count == 1 then
    line, ink, back = " UNO! ", C.ink, C.gold
  elseif view.phase == "scored" then
    if player.gain and player.gain > 0 then
      line, ink = "+" .. player.gain .. " this hand", C.win
    elseif not player.bot then
      line, ink = player.ready and "Ready" or "Reading the scores", player.ready and C.win or C.mute
    end
  elseif player.idle and player.idle > 0 and not player.bot then
    line, ink = "Away: short clock", C.orange
  elseif acting and view.phase == "drawn" then
    line, ink = "Drew a card", C.text
  elseif acting and view.phase == "color" then
    line, ink = "Naming the colour", C.text
  end
  if line then c:text(x + 2, y + 10, short(line, SIDE_W - 3), ink, back) end
  local clock = clockOf(view, player, info)
  if clock and clock.total and clock.total > 0 then
    local share = math.max(0, math.min(1, clock.left / clock.total))
    local w = SIDE_W - 10
    c:rect(x + 2, y + 12, w, 1, C.ink)
    local filled = math.floor(w * share + 0.5)
    if filled > 0 then c:rect(x + 2, y + 12, filled, 1, share < 0.25 and C.red or C.gold) end
    local secs = math.ceil(clock.left / 1000)
    local label = ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
    c:text(x + SIDE_W - #label - 1, y + 12, label, share < 0.25 and C.red or C.text, bg)
  elseif acting and player.bot then
    c:text(x + 2, y + 12, "thinking...", C.mute, bg)
  end
end

--- Arrows between the panels, pointing the way play goes.
local function arrows(c, view, at, left, right)
  local clockwise = (view.dir or 1) == 1
  local function mark(x, y, up)
    c:text(x, y, up and "^" or "v", C.gold)
    c:text(x + 2, y, up and "^" or "v", C.gold)
  end
  for i = 1, left - 1 do
    local a = at[i]
    mark(a.x + math.floor(SIDE_W / 2) - 1, a.y - 2, clockwise)
  end
  for i = left + 1, left + right - 1 do
    local a = at[i]
    mark(a.x + math.floor(SIDE_W / 2) - 1, a.y + PANEL_H + 1, not clockwise)
  end
end

local function statusLine(view)
  local who = view.players[view.turn]
  local name = who and who.name or "?"
  if view.phase == "goal" then
    local chooser = view.players[view.chooser or 0]
    return (chooser and chooser.name or "Someone") .. " is picking how long a game to play"
  end
  if view.window and not view.window.noticed then
    local off = view.players[view.window.p]
    return (off and off.name or "?") .. " has one card and did not say UNO!"
  end
  if view.phase == "color" then return name .. " names the first colour" end
  if view.phase == "drawn" then return name .. " drew: play it or keep it" end
  if view.phase == "play" then return name .. " plays or draws" end
  return ""
end

local function center(c, view, info)
  local who = view.players[view.turn]
  -- Whose turn, big
  local name = string.upper(short(who and who.name or "?", 10))
  local ink = C.gold
  c:bigCenter(CX, 11, name, ink, 1)
  local status = statusLine(view)
  c:textCenter(CX + 1, 18, short(status, MID_W), view.window and C.orange or C.text)
  local goal = view.goal == 0 and "ONE HAND WINS" or ("FIRST TO " .. tostring(view.goal))
  c:textCenter(CX + 1, 19, "HAND " .. tostring(view.handNo) .. "   " .. goal, C.mute)

  -- The draw pile
  local dx, dy = MID_X + 1, 24
  draw.back(c, dx, dy, 16, 14)
  c:textCenter(dx + 8, dy + 15, tostring(view.deck) .. " to draw", C.mute)
  -- The discard on a block of the colour in play
  local color = view.color
  local box = color and draw.INK[color] or C.panel2
  local bx, by, bw, bh = MID_X + 21, 21, 30, 22
  c:rect(bx, by, bw, bh, box)
  if view.top then
    draw.card(c, bx + 5, by + 2, 20, 18, view.top, { color = color })
  end
  local word = color and cards.COLOR_WORD[color] or "PICK A COLOUR"
  if color then
    c:bigCenter(bx + math.floor(bw / 2), by + bh + 2, word, box, 1)
  else
    c:textCenter(bx + math.floor(bw / 2) + 1, by + bh + 2, word, C.text)
  end

  -- Which way, and who is next
  local nextP = ((view.turn - 1 + (view.dir or 1)) % #view.players) + 1
  local nextName = view.players[nextP] and view.players[nextP].name or "?"
  c:textCenter(dx + 8, dy + 17, (view.dir or 1) == 1 and "clockwise" or "anticlockwise", C.gold)
  c:textCenter(dx + 8, dy + 18, "next: " .. short(nextName, 10), C.text)

  -- The last few cards played
  local ry = 51
  c:text(MID_X + 1, ry, "LAST PLAYS", C.mute)
  local recent = view.recent or {}
  local first = math.max(1, #recent - 6)
  local x = MID_X + 1
  for i = first, #recent do
    local item = recent[i]
    draw.mini(c, x, ry + 1, item.card, item.color)
    local by_ = item.p and view.players[item.p]
    c:text(x, ry + 5, short(by_ and by_.name or "start", 6), i == #recent and C.text or C.mute)
    x = x + 7
  end
end

local function logBox(c, view)
  local y = 59
  c:rect(MID_X, y - 1, MID_W, 9, C.feltDark)
  local lines = view.log or {}
  local from = math.max(1, #lines - 6)
  local row = y
  for i = from, #lines do
    c:text(MID_X + 1, row, short(lines[i], MID_W - 2), i == #lines and C.text or C.mute, C.feltDark)
    row = row + 1
  end
end

--- Between hands, and at the end: who won the hand and everyone's score.
local function scores(c, view)
  local last = view.lastHand
  local winner = last and view.players[last.winner]
  if winner then
    c:bigCenter(CX, 12, string.upper(short(winner.name, 10)), C.win, 1)
    c:textCenter(CX + 1, 19, "wins hand " .. last.hand .. " and scores " .. last.points, C.text)
  end
  local goal = view.goal == 0 and "One hand wins" or ("First to " .. tostring(view.goal))
  c:textCenter(CX + 1, 21, goal, C.mute)
  local y = 24
  c:rect(MID_X, y - 1, MID_W, 3 + #view.players * 2, C.panel)
  c:text(MID_X + 2, y, "PLAYER", C.mute, C.panel)
  c:text(MID_X + 20, y, "LEFT", C.mute, C.panel)
  c:text(MID_X + 28, y, "+", C.mute, C.panel)
  c:text(MID_X + 38, y, "SCORE", C.mute, C.panel)
  for p, player in ipairs(view.players) do
    local row = y + p * 2
    local top = view.winner == p or (view.phase ~= "over" and last and last.winner == p)
    local ink = top and C.gold or C.text
    c:text(MID_X + 2, row, short(player.name, 16), ink, C.panel)
    local r = last and last.rows and last.rows[p]
    if r then
      c:text(MID_X + 20, row, tostring(r.cards), C.mute, C.panel)
      if last.winner == p then c:text(MID_X + 28, row, "+" .. last.points, C.win, C.panel) end
    end
    c:text(MID_X + 38, row, tostring(player.score), ink, C.panel)
    if view.goal and view.goal > 0 then
      local w = 9
      local share = math.min(1, player.score / view.goal)
      c:rect(MID_X + 44 - 1, row, w - 2, 1, C.ink)
      local filled = math.floor((w - 2) * share + 0.5)
      if filled > 0 then c:rect(MID_X + 43, row, filled, 1, top and C.gold or C.win) end
    end
  end
  if view.phase == "scored" then
    c:textCenter(CX + 1, y + 4 + #view.players * 2, "Tap NEXT HAND on your screen", C.gold)
  end
end

local function goalScreen(c, view)
  draw.logo(c, CX, 20, 3)
  local chooser = view.players[view.chooser or 0]
  local lines = wrap((chooser and chooser.name or "The first seat") .. " picks how long a game: first to 500 points, first to 200, or one hand.", MID_W - 2)
  for i, line in ipairs(lines) do c:textCenter(CX + 1, 42 + i, line, C.text) end
  c:textCenter(CX + 1, 48, "Match the colour, the number or the symbol.", C.mute)
  c:textCenter(CX + 1, 49, "Say UNO before your second-last card!", C.gold)
end

--- A word across the middle for a big moment.
local function shout(c, text, color, scale, top)
  scale = scale or 1
  while scale > 1 and c:bigWidth(text, scale) > MID_W + 20 do scale = scale - 1 end
  local w = c:bigWidth(text, scale) + 8
  local h = 6 * scale + 4
  local x = CX - math.floor(w / 2)
  local y = top or (32 - math.floor(h / 2))
  c:rect(x, y, w, h, C.ink)
  c:frame(x, y, w, h, color)
  c:bigCenter(CX, y + 2, text, color, scale)
end

local SHOUTS = {
  skip = { "SKIP!", C.orange, 2 }, reverse = { "REVERSE!", C.orange, 2 }, draw2 = { "+2", C.red, 2 }, draw4 = { "+4", C.red, 2 },
  uno = { "UNO!", C.gold, 2 }, catch = { "CAUGHT!", C.red, 2 }, shuffle = { "SHUFFLE", C.text, 1 },
}

function M.draw(c, view, anim, info)
  if not view or not view.players then return end
  local at, left, right = places(#view.players)
  for p = 1, #view.players do playerPanel(c, view, p, at[p], info) end
  arrows(c, view, at, left, right)
  if view.phase == "goal" then
    goalScreen(c, view)
  elseif view.phase == "scored" or view.phase == "over" then
    scores(c, view)
    logBox(c, view)
  else
    center(c, view, info)
    logBox(c, view)
  end
  if anim then
    local ev = anim.ev
    local entry = SHOUTS[ev.type]
    if ev.type == "uno" and anim.t > 0.85 then entry = nil end
    if ev.type == "draw4" and anim.t > 0.5 then entry = nil end
    -- Once the scores are up, the last plays' moments would only cover them
    local scoring = view.phase == "scored" or view.phase == "over"
    if scoring and ev.type ~= "handwin" and ev.type ~= "win" then
      -- nothing
    elseif entry then
      shout(c, entry[1], entry[2], entry[3])
    elseif ev.type == "wild" or (ev.type == "draw4" and anim.t > 0.5) or ev.type == "color" then
      local word = cards.COLOR_WORD[ev.color or ""]
      if word then shout(c, word, draw.INK[ev.color], 2) end
    elseif ev.type == "handwin" and view.players[ev.p] then
      shout(c, string.upper(short(view.players[ev.p].name, 8)) .. " +" .. tostring(ev.points or 0), C.win, 2, 42)
    elseif ev.type == "win" and view.players[ev.p] then
      shout(c, string.upper(short(view.players[ev.p].name, 8)) .. " WINS", C.win, 2, 42)
    elseif ev.type == "deal" then
      shout(c, "HAND " .. tostring(ev.hand or view.handNo), C.gold, 2)
    end
  end
end

return M
