-- games/battleship/plugin.lua
-- Battleship as an Arcade game, for a cabinet with two walls back to back, so each player's fleet stays on their own side.
-- Your wall shows your own water while you place ships, then the enemy's water to fire into, with your fleet in the corner.
-- Everything drawn from a fleet takes a viewer: with none, as for a spectator or a covered wall, only shots are shown.

local ai = require("games.battleship.ai")
local base = require("lib.arcade.base")
local hash = require("lib.casino.rng")
local rules = require("games.battleship.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local SIZE, MISS, HIT, SUNK = rules.SIZE, rules.MISS, rules.HIT, rules.SUNK
local SHIPS = rules.SHIPS

local view = { scoreName = "SHIPS SUNK" }

function view.layout(W, H)
  local L = base.grid(W, H, SIZE, SIZE)
  L.btnX, L.btnW = 1, L.sideW - 1
  L.rotateY, L.autoY, L.btnH = L.y0 + 18, L.y0 + 27, 7
  L.debug = { size = SIZE, rotate = { L.btnX, L.rotateY, L.btnW, L.btnH }, auto = { L.btnX, L.autoY, L.btnW, L.btnH } }
  return L
end

local function seatColor(p) return p == 1 and C.red or C.blue end

--- Which way this seat's next ship will lie.
local function shipDir(match, seat)
  return (match.extras.dirs or {})[seat] or "h"
end

function view.score(state) return state.sunk[1], state.sunk[2] end

function view.moveNumber(state) return state.moves + 1 end

--- One seat's water: shots is who has fired at it, fleet is drawn only when given.
local function drawWater(x0, y0, cw, ch, shots, grid, last, landing)
  for y = 1, SIZE do
    for x = 1, SIZE do
      local cx, cy = x0 + (x - 1) * cw, y0 + (y - 1) * ch
      local shot = shots and shots[y][x] or 0
      if landing and landing.x == x and landing.y == y then shot = 0 end -- the result stays hidden until it lands
      local ship = grid and grid[y][x] ~= 0
      local color = (x + y) % 2 == 0 and C.panel or C.blueTint
      if ship then color = C.line end
      if shot == HIT then color = C.warn elseif shot == SUNK then color = C.red end
      ui.fill(cx, cy, cw, ch, color)
      if shot == MISS and cw >= 3 then
        ui.fill(cx + floor(cw / 2) - 1, cy + floor(ch / 2), 2, 1, C.text)
      elseif shot == MISS then
        ui.fill(cx, cy, cw, ch, C.bg)
      end
    end
  end
  if last and shots then ui.frame(x0 + (last[1] - 1) * cw, y0 + (last[2] - 1) * ch, cw, ch, C.hi, 1) end
end

local function drawPlacing(L, s, seat)
  drawWater(L.x0, L.y0, L.cw, L.ch, nil, s.grids[seat])
end

local function drawWaiting(L, match)
  local s = match.state
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.panel)
  local name = (s.turn == 1 and match.red or match.blue)
  ui.small((name and name.name or "A captain") .. " is placing their ships", L.x0 + floor(L.bw / 2), L.y0 + floor(L.bh / 2), C.line, C.panel, "center", L.bw - 2)
end

--- A short seal over a fleet: shown from the first shot, and checked against the fleet at the end.
local function sealOf(s, seat)
  return hash.sha256(rules.fleetText(s, seat)):sub(1, 10)
end

--- The game over: both fleets, with the shots that found them.
local function drawReveal(L, match)
  local s = match.state
  local cw = floor((L.W - 6) / (2 * SIZE))
  local ch = math.max(2, floor(cw / 1.5 + 0.5))
  local rx = L.W - 2 - cw * SIZE
  local y = L.y0 + 2
  ui.small(match.red.name .. "'s fleet", 2, L.y0, C.red, C.bg, "left", cw * SIZE)
  ui.small(match.blue.name .. "'s fleet", rx, L.y0, C.blue, C.bg, "left", cw * SIZE)
  drawWater(2, y, cw, ch, s.shots[2], s.grids[1])
  drawWater(rx, y, cw, ch, s.shots[1], s.grids[2])
  local seals = match.extras.seals or {}
  for seat = 1, 2 do
    local seal = seals[seat]
    if seal and s.fleets[seat][5] then
      local good = seal == sealOf(s, seat)
      ui.small("seal " .. seal .. (good and " matches" or " DOES NOT MATCH"), seat == 1 and 2 or rx, y + ch * SIZE + 1, good and C.ok or C.warn, C.bg, "left", cw * SIZE)
    end
  end
end

function view.drawBoard(L, match, viewer)
  local s = match.state
  if s.winner ~= 0 or match.replay then
    if match.red then return drawReveal(L, match) end
    return drawWater(L.x0, L.y0, L.cw, L.ch, s.shots[s.winner], nil) -- the idle demo has no players to name
  end
  if s.phase == "setup" then
    if viewer == s.turn then return drawPlacing(L, s, viewer) end
    return drawWaiting(L, match)
  end
  local seat = viewer or s.turn
  local shot = match.anim
  local t = base.animT(match)
  local landing = shot and t and t < 0.7 and shot.seat == seat
  drawWater(L.x0, L.y0, L.cw, L.ch, s.shots[seat], nil, not landing and s.lastShot[seat] or nil, landing and shot or nil)
  if landing then
    -- the sights close in on the square
    local close = 1 - t / 0.7
    local cx, cy = L.colX[shot.x], L.rowY[shot.y]
    local dx, dy = floor(close * L.cw * 2), floor(close * L.ch * 2)
    ui.frame(cx - dx, cy - dy, L.cw + 2 * dx, L.ch + 2 * dy, C.hi, 1)
  end
end

--- ROTATE and RANDOM while placing, then the fleet list and your own water in the corner.
function view.drawSides(L, match, leftX, rightX, w, viewer)
  local s = match.state
  if not viewer then return end
  if s.phase == "setup" then
    if viewer == s.turn then
      ui.button("rotate", L.btnX, L.rotateY, L.btnW, L.btnH, shipDir(match, viewer) == "h" and "ACROSS" or "DOWN", C.panel, { small = true })
      ui.button("auto", L.btnX, L.autoY, L.btnW, L.btnH, "RANDOM", C.panel, { small = true })
    end
    return
  end
  local y = L.y0 + 18
  ui.small("ENEMY", leftX, y, C.hi, C.bg, "left", w)
  local enemy = 3 - viewer
  for n, ship in ipairs(SHIPS) do
    local down = s.fleets[enemy][n].hits == ship.len
    ui.small(ship.name, leftX, y + n * 2, down and C.line or C.text, C.bg, "left", w)
  end
  local seals = match.extras.seals or {}
  ui.small("SEALS", leftX, y + 14, C.hi, C.bg, "left", w)
  ui.small(seals[1] or "-", leftX, y + 15, C.red, C.bg, "left", w)
  ui.small(seals[2] or "-", leftX, y + 16, C.blue, C.bg, "left", w)
  ui.small("YOURS", rightX, y, C.hi, C.bg, "left", w)
  local cw = math.max(1, math.min(2, floor(w / SIZE)))
  drawWater(rightX, y + 2, cw, 1, s.shots[enemy], s.grids[viewer], s.lastShot[enemy])
end

function view.actionAt(L, match, px, py, viewer)
  local s = match.state
  if s.phase == "setup" then
    if px >= L.btnX and px < L.btnX + L.btnW then
      if py >= L.rotateY and py < L.rotateY + L.btnH then return { kind = "select", seat = viewer } end
      if py >= L.autoY and py < L.autoY + L.btnH then return { kind = "auto" } end
    end
    local x, y = base.cellAt(L, px, py)
    if not x then return nil end
    return { kind = "place", x = x, y = y, dir = shipDir(match, viewer) }
  end
  local x, y = base.cellAt(L, px, py)
  if not x then return nil end
  return { kind = "fire", x = x, y = y }
end

function view.onSelect(match, action)
  local dirs = match.extras.dirs or {}
  dirs[action.seat] = shipDir(match, action.seat) == "h" and "v" or "h"
  match.extras.dirs = dirs
end

function view.prompt(state, name, viewer)
  local color = state.turn == 1 and C.red or C.blue
  if state.phase == "setup" then
    if viewer == state.turn then
      local ship = SHIPS[state.placed[state.turn] + 1]
      return string.format("Place your %s (%d)", ship.name, ship.len), color
    end
    return name .. " is placing ships", color
  end
  if viewer == state.turn then return name .. ": pick a square and fire", color end
  return name .. " is taking aim", color
end

function view.finalLine(match)
  local s = match.state
  local w = s.winner == 1 and match.red or match.blue
  if s.forfeit then return w.name .. " WINS by forfeit", seatColor(s.winner) end
  return w.name .. " sank the whole fleet!", seatColor(s.winner)
end

function view.howLine(r, duration)
  local s = r.state
  return string.format("%s  -  %d shots  -  %s  -  ships %d-%d", r.forfeit and "BY FORFEIT" or "FLEET SUNK", s.moves, duration, s.sunk[1], s.sunk[2])
end

function view.scoreLine(match)
  local s = match.state
  return string.format("%d shots - ships %d-%d", s.moves, s.sunk[1], s.sunk[2])
end

function view.historyLine(h) return string.format("%d shots", h.moves or 0) end

function view.onEvents(app, match, events)
  for _, ev in ipairs(events) do
    if ev.type == "shot" then
      base.animate(match, 600, { x = ev.x, y = ev.y, seat = ev.seat })
      local name = (ev.seat == 1 and match.red or match.blue).name
      if ev.sunk then
        app.audio.play(ev.seat == 2 and "captureBlue" or "captureRed")
        app.setToast(string.format("%s sank the %s!", name, ev.sunk), seatColor(ev.seat), 3000)
      elseif ev.hit then
        app.audio.play("capture")
        app.setToast(name .. " scored a hit!", seatColor(ev.seat), 1500)
      else
        app.audio.play(ev.seat == 2 and "placeBlue" or "placeRed")
      end
    elseif ev.type == "placed" then
      app.audio.play("select")
      -- seal each fleet as it is finished, so neither side can say the other moved a ship
      if match.state.placed[ev.seat] == #SHIPS then
        local seals = match.extras.seals or {}
        seals[ev.seat] = sealOf(match.state, ev.seat)
        match.extras.seals = seals
      end
    end
  end
end

--- What tests read back. It holds shots only: the fleets stay out of the dump.
function view.debug(match)
  local s = match.state
  return { turn = s.turn, winner = s.winner, moves = s.moves, phase = s.phase, snapshot = rules.snapshot(s), placed = s.placed }
end

local M = {
  id = "battleship", title = "Battleship", blurb = "Two walls, one divider, no peeking", color = "info", accent = 0x3CD3E6,
  minSize = { w = 98, h = 64 }, walls = 2, private = true, noHints = true,
  cpuLevels = { "easy", "medium", "hard" },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Each player hides five ships on their own wall: Carrier 5, Battleship 4, Cruiser 3, Submarine 3, Destroyer 2. Keep to your side of the divider.",
    "",
    "Place ships one at a time: tap the square a ship starts on, use ACROSS or DOWN to turn it, or tap RANDOM to place the rest for you. Ships can touch but not overlap.",
    "",
    "Then take turns firing at the enemy's water on your wall. A hit does not earn another shot. When every square of a ship is hit it sinks, and both players are told.",
    "",
    "Sink all five to win. If your opponent walks round to your wall, it hides your fleet until they leave.",
  },
  badges = {
    unscathed = { name = "Unsinkable", text = "Win without losing a ship", test = function(m, sd, _, won)
      return won and not m.forfeit and sd.other == 0
    end },
    sharp = { name = "Sharpshooter", text = "Win with 35 of your own shots or fewer", test = function(m, _, _, won)
      return won and not m.forfeit and m.moves <= 70
    end },
  },
}

function M.chooseAction(state, level)
  return ai.choose(state, level)
end

function M.summarize(match)
  local s = match.state
  return { moves = s.moves, boardsRed = s.sunk[1], boardsBlue = s.sunk[2] }
end

return base.fill(M)
