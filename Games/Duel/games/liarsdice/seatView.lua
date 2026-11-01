-- games/liarsdice/seatView.lua
-- A player's wall: the other player's dice along the top, the bid in the middle, their own dice below that, and the picker for a
-- bid on their turn. M.board draws all but the picker, from a public view too, so tableView can use it.
-- A view with no mine is a wall with no viewer: it has no dice to show, so it draws backs.

local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

local BIG_W, BIG_H, BIG_GAP = 15, 10, 3
local SMALL_W, SMALL_H, SMALL_GAP = 10, 7, 2
local DICE = 5
local TOP_Y, BID_Y, OWN_Y, SUMMARY_Y, COUNT_Y, FACE_Y = 11, 21, 35, 47, 48, 56
local DICE_X = 26           -- where both rows of dice start, past the names
local PICK_X = 14           -- where the picker's tiles start, past their labels
local COUNT_W, COUNT_H, COUNT_GAP = 9, 7, 1
local FACE_GAP = 2

-- Where the pips of a face sit on a 3x3 grid, numbered from the top left
local PIPS = { { 5 }, { 1, 9 }, { 1, 5, 9 }, { 1, 3, 7, 9 }, { 1, 3, 5, 7, 9 }, { 1, 3, 4, 6, 7, 9 } }
local FACE_NAMES = { "ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES" }

local function die(c, x, y, big, face, bg, pip)
  local w, h = big and BIG_W or SMALL_W, big and BIG_H or SMALL_H
  c:rect(x, y, w, h, bg)
  if not face then
    c:textCenter(x + math.floor(w / 2), y + math.floor(h / 2), "?", C.mute, bg)
    return
  end
  for _, spot in ipairs(PIPS[face]) do
    local column, row = (spot - 1) % 3, math.floor((spot - 1) / 3)
    if big then
      c:rect(x + 2 + column * 4, y + 1 + row * 3, 3, 2, pip)
    else
      c:rect(x + 1 + column * 3, y + 1 + row * 2, 2, 1, pip)
    end
  end
end

local function findPlayer(view, seat)
  for _, player in ipairs(view.players or {}) do
    if player.seat == seat then return player end
  end
  return nil
end

local function nameOf(view, seat, room)
  local player = findPlayer(view, seat)
  return seatui.short(player and player.name or "?", room or 12)
end

--- Which player goes where: the one this wall belongs to below, the other above.
local function sides(view, info)
  local players = view.players or {}
  local me = view.me or (info and info.seat)
  if players[1] and players[1].seat == me then return players[2], players[1] end
  return players[1], players[2]
end

--- Does this die make the called bid good?
local function counts(last, face)
  return last and (face == last.face or (face == 1 and last.face ~= 1))
end

--- One player's row of dice. reveal is how many dice of this row have turned over so far, or nil for all of them.
local function hand(c, view, player, x, y, big, reveal)
  local step = (big and BIG_W + BIG_GAP or SMALL_W + SMALL_GAP)
  local h = big and BIG_H or SMALL_H
  local dice = player.dice
  if player.seat == view.me and not dice then dice = view.mine end
  local last = player.dice and view.last or nil
  local slots = math.max(player.left, player.dice and #player.dice or 0)
  for index = 1, DICE do
    local at = x + (index - 1) * step
    if index > slots then
      c:rect(at, y, big and BIG_W or SMALL_W, h, big and C.feltDark or C.felt) -- a die they have lost
    else
      local face = dice and dice[index] or nil
      if reveal and index > reveal then face = nil end
      if face then
        local hit = counts(last, face)
        die(c, at, y, big, face, hit and C.gold or C.card, C.ink)
      else
        die(c, at, y, big, nil, C.panel2, C.mute)
      end
    end
  end
end

--- How many dice of each row have turned while the reveal plays. All of them once it has, or at a table with no reveal playing.
local function turning(view, anim)
  if not anim or not anim.ev or anim.ev.type ~= "reveal" then return nil, nil end
  local top, bottom = 0, 0
  local players = view.players or {}
  local total = 0
  for _, player in ipairs(players) do total = total + (player.dice and #player.dice or 0) end
  local shown = math.floor((anim.t or 1) * (total + 1))
  top = math.min(shown, DICE)
  bottom = math.max(0, shown - top)
  return top, bottom
end

local function topRow(c, view, player, x, w, reveal)
  c:rect(x + 1, TOP_Y - 1, w - 2, SMALL_H + 2, C.feltDark)
  if not player then return end
  local acting = view.phase == "bid" and view.turn == player.seat
  c:text(x + 3, TOP_Y, seatui.short(player.name, DICE_X - x - 5), acting and C.gold or C.text, C.feltDark)
  c:text(x + 3, TOP_Y + 2, player.left .. (player.left == 1 and " die" or " dice"), C.mute, C.feltDark)
  hand(c, view, player, x + DICE_X - 1, TOP_Y, false, reveal)
  local right = x + DICE_X + 5 * (SMALL_W + SMALL_GAP) + 1
  c:text(right, TOP_Y, "STAKE", C.mute, C.feltDark)
  c:text(right, TOP_Y + 1, tostring(view.stake or 0), C.gold, C.feltDark)
  c:text(right, TOP_Y + 3, "IN PLAY", C.mute, C.feltDark)
  c:text(right, TOP_Y + 4, (view.total or 0) .. " dice", C.text, C.feltDark)
end

--- The earlier bids of this round, newest first, up the right of the bid panel.
local function earlier(c, view, x, y)
  local bids = view.bids or {}
  local row = 0
  for index = #bids - 1, 1, -1 do
    if row >= 5 then return end
    local bid = bids[index]
    c:text(x, y + row * 2, nameOf(view, bid.seat, 8), C.mute, C.feltDark)
    c:text(x + 9, y + row * 2, bid.count .. " x " .. bid.face, C.text, C.feltDark)
    row = row + 1
  end
end

--- The middle of the wall: what is bid, or what the last call found.
local function bidPanel(c, view, anim, x, w)
  local h = 13
  local flash = anim and anim.ev and anim.ev.type == "bid"
  c:rect(x + 1, BID_Y, w - 2, h, flash and C.gold or C.feltDark)
  c:rect(x + 2, BID_Y + 1, w - 4, h - 2, C.feltDark)
  if anim and anim.ev and anim.ev.type == "liar" then
    c:bigCenter(x + math.floor(w / 2), BID_Y + 1, "LIAR!", C.red, 2)
    return
  end
  local bid = view.bid or ((view.phase ~= "bid") and view.last) or nil
  if bid then
    local who = bid.seat or bid.bidder
    c:text(x + 4, BID_Y + 2, nameOf(view, who, 16), C.text, C.feltDark)
    c:text(x + 4, BID_Y + 4, "bids", C.mute, C.feltDark)
    c:text(x + 4, BID_Y + 7, FACE_NAMES[bid.face] or "", C.gold, C.feltDark)
    c:text(x + 4, BID_Y + 9, bid.face == 1 and "Only ones count" or "Ones count too", C.mute, C.feltDark)
    local count = tostring(bid.count)
    c:big(x + 34, BID_Y, count, C.gold, 2)
    c:big(x + 36 + c:bigWidth(count, 2), BID_Y + 4, "x", C.text, 1)
    die(c, x + 42 + c:bigWidth(count, 2), BID_Y + 1, true, bid.face, C.card, C.ink)
  elseif view.phase == "bid" then
    c:text(x + 4, BID_Y + 2, "ROUND " .. tostring(view.round or 1), C.gold, C.feltDark)
    c:text(x + 4, BID_Y + 4, "No bid yet", C.text, C.feltDark)
    local last = view.last
    if last then
      c:text(x + 4, BID_Y + 7, nameOf(view, last.caller, 12) .. " called " .. last.count .. " x " .. last.face .. ": there were " .. last.actual, C.mute, C.feltDark)
      c:text(x + 4, BID_Y + 9, nameOf(view, last.loser, 12) .. " lost a die and opens", C.mute, C.feltDark)
    end
  end
  earlier(c, view, x + 88, BID_Y + 1)
end

--- After a call, what it found, between the dice and the result banner.
local function summary(c, view, anim, x, w)
  local last = view.last
  if not last then return end
  if anim and anim.ev and anim.ev.type == "liar" then return end
  if anim and anim.ev and anim.ev.type == "reveal" and (anim.t or 1) < 0.85 then return end
  local cx = x + math.floor(w / 2)
  c:textCenter(cx, SUMMARY_Y, nameOf(view, last.caller, 14) .. " called LIAR on " .. last.count .. " x " .. last.face .. ". There " ..
    (last.actual == 1 and "was 1" or ("were " .. last.actual)), C.text)
  local text = nameOf(view, last.loser, 12) .. " loses a die"
  if c:bigWidth(text, 1) <= w - 4 then
    c:bigCenter(cx, SUMMARY_Y + 1, text, C.gold, 1)
  else
    c:textCenter(cx, SUMMARY_Y + 1, text, C.gold)
  end
end

--- Everything but the picker. Fits a 121 wide wall from row 10 to row 53, above where a result banner lands.
function M.board(c, view, anim, info, x, w)
  local above, below = sides(view, info)
  local revealTop, revealBottom = turning(view, anim)
  topRow(c, view, above, x, w, revealTop)
  bidPanel(c, view, anim, x, w)
  if below then
    local acting = view.phase == "bid" and view.turn == below.seat
    c:text(x + 3, OWN_Y + 1, seatui.short(below.name, DICE_X - x - 5), acting and C.gold or C.text)
    c:text(x + 3, OWN_Y + 3, below.left .. (below.left == 1 and " die" or " dice"), C.mute)
    hand(c, view, below, x + DICE_X - 1, OWN_Y, true, revealBottom)
  end
  if view.phase ~= "bid" then summary(c, view, anim, x, w) end
end

--- Where a picker's tiles go. Both the picture and the touches use this, so they cannot disagree.
local function tiles(view)
  local list = {}
  for count = 1, view.total or 0 do
    list[#list + 1] = { id = "count", value = count, live = view.counts and view.counts[count],
      x = PICK_X + (count - 1) * (COUNT_W + COUNT_GAP), y = COUNT_Y, w = COUNT_W, h = COUNT_H }
  end
  for face = 1, 6 do
    list[#list + 1] = { id = "face", value = face, live = view.faces and view.faces[face],
      x = PICK_X + (face - 1) * (BIG_W + FACE_GAP), y = FACE_Y, w = BIG_W, h = BIG_H }
  end
  return list
end

local function picker(c, view)
  local draft = view.draft
  c:text(3, COUNT_Y + 1, "HOW", C.gold)
  c:text(3, COUNT_Y + 2, "MANY?", C.gold)
  c:text(3, FACE_Y + 3, "WHICH", C.gold)
  c:text(3, FACE_Y + 4, "FACE?", C.gold)
  for _, tile in ipairs(tiles(view)) do
    local chosen = (tile.id == "count" and draft.count == tile.value) or (tile.id == "face" and draft.face == tile.value)
    if tile.id == "count" then
      local bg = chosen and C.gold or (tile.live and C.panel2 or C.feltDark)
      local fg = chosen and C.ink or (tile.live and C.text or C.line)
      c:rect(tile.x, tile.y, tile.w, tile.h, bg)
      local label = tostring(tile.value)
      local cx = tile.x + math.floor(tile.w / 2)
      if c:bigWidth(label, 1) <= tile.w then
        c:bigCenter(cx + 1, tile.y + 1, label, fg, 1)
      else
        c:textCenter(cx, tile.y + 3, label, fg, bg)
      end
    else
      if chosen then c:rect(tile.x - 1, tile.y - 1, tile.w + 2, tile.h + 2, C.gold) end
      die(c, tile.x, tile.y, true, tile.value, tile.live and C.card or C.feltDark, tile.live and C.ink or C.line)
    end
  end
end

--- Whose move it is, in the room the picker uses on the other player's turn.
local function waiting(c, view, x, w)
  local cx = x + math.floor(w / 2)
  local text = view.turn == view.me and "Your turn" or (nameOf(view, view.turn, 16) .. " to bid")
  if view.bid and view.turn ~= view.me then text = nameOf(view, view.turn, 16) .. " to raise or call" end
  c:textCenter(cx, SUMMARY_Y + 3, text, C.text)
  c:textCenter(cx, SUMMARY_Y + 5, "Ones count as any face unless ones are bid", C.mute)
end

function M.draw(c, view, anim, info)
  local x, _, w = seatui.area(c)
  M.board(c, view, anim, info, x, w)
  if view.phase == "bid" then
    if view.draft then picker(c, view) else waiting(c, view, x, w) end
  end
end

function M.regions(view)
  local list = {}
  if not view.draft then return list end
  for _, tile in ipairs(tiles(view)) do
    if tile.live then
      list[#list + 1] = { id = tile.id, value = tile.value, x = tile.x, y = tile.y, w = tile.w, h = tile.h }
    end
  end
  return list
end

return M
