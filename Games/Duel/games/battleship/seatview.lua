-- games/battleship/seatview.lua
-- A Duel wall, 121x81, always laid out from the top left so regions need no canvas. view.you is there only for a player at their own
-- wall: they get their water while placing, then the enemy's water to fire into with their fleet in the corner. With no view.you,
-- for a covered wall, only shots are drawn, because that is all the view holds. At the end both fleets come out, above the banner.

local hash = require("lib.casino.rng")
local rules = require("games.battleship.rules")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local floor = math.floor
local SIZE, MISS, HIT, SUNK = rules.SIZE, rules.MISS, rules.HIT, rules.SUNK
local SHIPS = rules.SHIPS

local M = {}

local BIG = { x = 6, y = 14, cw = 7, ch = 5 }      -- 70x50, the board you tap
local SMALL = { x = 85, y = 15, cw = 3, ch = 2 }   -- 30x20, your own water while you shoot
local SIDE_X, SIDE_W = 80, 39                      -- the column right of the big board
local SIDE_CX = SIDE_X + floor(SIDE_W / 2)
local BIG_CX = BIG.x + floor(BIG.cw * SIZE / 2)
local PAIR_Y, PAIR_CW, PAIR_CH = 16, 5, 3          -- two boards side by side, 50x30, clear of the banner at row 54
local PAIR_X = { 6, 66 }
local PROMPT_Y, MESSAGE_Y = 11, 66
local LANDING = 0.7                                -- a shot's share of its event spent falling

local function seatColor(position)
  return position == 1 and C.gold or C.blue
end

--- One board. shots is who has fired at it, g the ships in it if we may draw them, last the square to ring, landing a shot in the air.
-- edge is the colour round it, gold when it is waiting on this player.
local function water(c, b, shots, g, last, landing, edge)
  c:frame(b.x - 1, b.y - 1, b.cw * SIZE + 2, b.ch * SIZE + 2, edge or C.ink)
  for y = 1, SIZE do
    for x = 1, SIZE do
      local cx, cy = b.x + (x - 1) * b.cw, b.y + (y - 1) * b.ch
      local shot = shots and shots[y][x] or 0
      if landing and landing.x == x and landing.y == y then shot = 0 end -- the result stays hidden until it lands
      local color = (x + y) % 2 == 0 and C.feltDark or C.panel
      if g and g[y][x] ~= 0 then color = C.mute end
      if shot == HIT then color = C.orange elseif shot == SUNK then color = C.red end
      c:rect(cx, cy, b.cw, b.ch, color)
      if shot == MISS then c:rect(cx + floor(b.cw / 2) - (b.cw > 3 and 1 or 0), cy + floor((b.ch - 1) / 2), b.cw > 3 and 3 or 1, 1, C.text) end
    end
  end
  if last then c:frame(b.x + (last.x - 1) * b.cw, b.y + (last.y - 1) * b.ch, b.cw, b.ch, C.gold) end
end

--- The sights close in on the square.
local function sights(c, b, shot, t)
  local close = 1 - t / LANDING
  local dx, dy = floor(close * b.cw * 2), floor(close * b.ch * 2)
  c:frame(b.x + (shot.x - 1) * b.cw - dx, b.y + (shot.y - 1) * b.ch - dy, b.cw + 2 * dx, b.ch + 2 * dy, C.gold)
end

--- The shot in the air on this board, if the event playing is one by this seat.
local function inFlight(anim, seat)
  local ev = anim and anim.ev
  if ev and ev.type == "shot" and ev.seat == seat and anim.t < LANDING then return ev end
  return nil
end

local function otherOf(view, p)
  return view.players[1] == p and view.players[2] or view.players[1]
end

local function mine(view)
  for _, p in ipairs(view.players) do
    if p.seat == view.seat then return p end
  end
  return nil
end

local function shotWords(last)
  if last.sunk then return "sank the " .. last.sunk .. "!" end
  return last.hit and "HIT" or "missed"
end

--- A ship as a row or column of its squares.
local function shipShape(c, x, y, len, dir, color)
  for i = 0, len - 1 do
    local cx, cy = dir == "h" and x + i * 3 or x, dir == "v" and y + i * 2 or y
    c:rect(cx, cy, 2, 1, color)
  end
end

--- Setup, on your own wall: your water, the fleet to place and which way the next ship lies.
local function drawPlacing(c, view, me, enemy)
  local you = view.you
  water(c, BIG, nil, you.grid, nil, nil, not (me.ready or me.late) and C.gold or nil)
  local cx = SIDE_CX
  if me.ready or me.late then
    c:textCenter(BIG_CX, PROMPT_Y, me.ready and "Fleet ready. Waiting for " .. seatui.short(enemy.name, 14) or "You ran out of time", me.ready and C.win or C.orange)
  else
    local ship = SHIPS[me.placed + 1]
    c:textCenter(BIG_CX, PROMPT_Y, ("Tap where your %s goes (%d)"):format(ship.name, ship.len), C.gold)
  end
  c:textCenter(cx, 13, "YOUR FLEET", C.gold)
  for n, ship in ipairs(SHIPS) do
    local y = 13 + n * 2
    local color = n <= me.placed and C.win or (n == me.placed + 1 and C.gold or C.mute)
    c:text(SIDE_X, y, (n == me.placed + 1 and "> " or "  ") .. ship.name, color)
    shipShape(c, SIDE_X + 15, y, ship.len, "h", color)
  end
  if not me.ready and not me.late then
    local ship = SHIPS[me.placed + 1]
    c:textCenter(cx, 27, you.dir == "h" and "ACROSS" or "DOWN", C.text)
    local across = (ship.len * 3 - 1)
    shipShape(c, you.dir == "h" and cx - floor(across / 2) or cx - 1, 29, ship.len, you.dir, C.gold)
    c:textCenter(cx, 40, "The ship runs right or down", C.mute)
    c:textCenter(cx, 41, "from the square you tap", C.mute)
  end
  local status = enemy.ready and " is ready" or (enemy.late and " ran out of time" or (" has placed " .. enemy.placed .. " of 5"))
  c:textCenter(cx, 45, seatui.short(enemy.name, 14) .. status, C.text)
  c:textCenter(cx, 48, "Stake " .. ui.group(view.stake), C.gold)
end

--- Each side's five ships, and what has become of them.
local function fleetLists(c, view, me, enemy, y)
  local you = view.you
  c:text(SIDE_X, y, "YOURS", C.gold)
  c:text(SIDE_X + 20, y, "ENEMY", C.gold)
  for n, ship in ipairs(SHIPS) do
    local row = y + n * 2
    local gone = me.lost[n]
    local hits = you.hits[n] or 0
    local line = gone and ship.name .. " sunk" or (hits > 0 and ("%s %d/%d"):format(ship.name, hits, ship.len) or ship.name)
    c:text(SIDE_X, row, line, gone and C.red or (hits > 0 and C.orange or C.text))
    c:text(SIDE_X + 20, row, enemy.lost[n] and ship.name .. " sunk" or ship.name, enemy.lost[n] and C.red or C.text)
  end
end

--- The seals, so neither side can say a ship moved. Checked against the fleets at the end.
local function sealLine(c, x, y, p, w)
  if not p.seal then return end
  local text, color = seatui.short(p.name, 10) .. " seal " .. p.seal, C.mute
  if p.proof then
    local good = hash.sha256(p.proof):sub(1, 10) == p.seal
    text, color = text .. (good and " matches" or " DOES NOT MATCH"), good and C.win or C.orange
  end
  c:text(x, y, text:sub(1, w), color)
end

local function lastLine(c, view, me, enemy)
  local shooter = view.turn == me.seat and enemy or me
  if not shooter.last then return end
  local who = shooter == me and "You" or seatui.short(shooter.name, 14)
  c:textCenter(BIG_CX, MESSAGE_Y, who .. " " .. shotWords(shooter.last), shooter.last.hit and C.orange or C.text)
end

--- The shooting, on your own wall: the enemy's water big, yours small.
local function drawShooting(c, view, me, enemy, anim)
  local mineInAir = inFlight(anim, me.seat)
  local theirsInAir = inFlight(anim, enemy.seat)
  local yours = view.turn == me.seat
  if view.you.confirm then
    c:textCenter(BIG_CX, PROMPT_Y, "Give up and lose " .. ui.group(view.stake) .. "?", C.orange)
  elseif yours then
    c:textCenter(BIG_CX, PROMPT_Y, "YOUR SHOT: tap a square of the enemy's water", C.gold)
  else
    c:textCenter(BIG_CX, PROMPT_Y, seatui.short(enemy.name, 14) .. " is taking aim", C.text)
  end
  water(c, BIG, me.shots, nil, not mineInAir and me.last or nil, mineInAir, yours and C.gold or nil)
  if mineInAir then sights(c, BIG, mineInAir, anim.t) end
  c:textCenter(SIDE_CX, 13, "YOUR WATER", C.gold)
  water(c, SMALL, enemy.shots, view.you.grid, not theirsInAir and enemy.last or nil, theirsInAir)
  if theirsInAir then sights(c, SMALL, theirsInAir, anim.t) end
  fleetLists(c, view, me, enemy, 37)
  c:text(SIDE_X, 50, "Stake " .. ui.group(view.stake), C.gold)
  c:text(SIDE_X + 20, 50, "Shots " .. view.moves, C.text)
  for position, p in ipairs(view.players) do
    sealLine(c, SIDE_X, 51 + position * 2, p, SIDE_W)
  end
  if not (mineInAir or theirsInAir) then lastLine(c, view, me, enemy) end
end

local function pairBoard(position)
  return { x = PAIR_X[position], y = PAIR_Y, cw = PAIR_CW, ch = PAIR_CH }
end

--- Both waters: what anyone may see while the match is on, and both fleets once it is over.
function M.drawBoth(c, view, anim)
  local cx = floor(c.w / 2) + 1
  if view.over then
    c:textCenter(cx, PROMPT_Y, view.how == "void" and "NO MATCH" or "BOTH FLEETS REVEALED", C.gold)
  elseif view.phase == "setup" then
    c:textCenter(cx, PROMPT_Y, "The captains are placing their ships", C.gold)
  else
    for _, p in ipairs(view.players) do
      if p.seat == view.turn then c:textCenter(cx, PROMPT_Y, seatui.short(p.name, 14) .. " is taking aim", C.gold) end
    end
  end
  for position, p in ipairs(view.players) do
    local b = pairBoard(position)
    local other = otherOf(view, p)
    local air = inFlight(anim, other.seat)
    c:text(b.x, b.y - 2, seatui.short(p.name, 16) .. "'s water", seatColor(position))
    local mark = "Lost " .. other.sunk .. " of 5"
    if view.phase == "setup" then mark = p.ready and "Ready" or (p.late and "Out of time" or ("Placed " .. p.placed .. " of 5")) end
    c:text(b.x + b.cw * SIZE - #mark, b.y - 2, mark, C.text)
    water(c, b, other.shots, p.grid, not air and other.last or nil, air)
    if air then sights(c, b, air, anim.t) end
    sealLine(c, b.x, b.y + b.ch * SIZE + 2, p, b.cw * SIZE)
  end
end

function M.draw(c, view, anim)
  if not view.players then return end
  local me = view.you and mine(view)
  if view.over or not me then return M.drawBoth(c, view, anim) end
  local enemy = otherOf(view, me)
  if view.phase == "setup" then return drawPlacing(c, view, me, enemy) end
  drawShooting(c, view, me, enemy, anim)
end

--- The squares that can be tapped now. Only ever live on this seat's turn.
function M.regions(view)
  local list = {}
  local you = view.you
  if not you or view.over or you.confirm or not view.players then return list end
  local me = mine(view)
  if not me then return list end
  local id = nil
  if view.phase == "setup" and not me.ready and not me.late then
    id = "place"
  elseif view.phase == "fire" and view.turn == view.seat then
    id = "fire"
  end
  if not id then return list end
  for y = 1, SIZE do
    for x = 1, SIZE do
      if id == "place" or me.shots[y][x] == 0 then
        list[#list + 1] = { id = id, value = rules.cell(x, y), x = BIG.x + (x - 1) * BIG.cw, y = BIG.y + (y - 1) * BIG.ch, w = BIG.cw, h = BIG.ch }
      end
    end
  end
  return list
end

return M
