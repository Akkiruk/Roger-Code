-- games/mancala/plugin.lua
-- Mancala as an Arcade game. Red's pits run along the bottom to its store on the right, and Blue's run along the top to
-- its store on the left, so seeds travel anticlockwise.

local base = require("lib.arcade.base")
local rules = require("games.mancala.rules")
local search = require("games.search")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local PITS = rules.PITS

local LEVELS = {
  easy = { depth = 2, blunder = 0.3 },
  medium = { depth = 5 },
  hard = { depth = 11 },
}

local function eval(s, seat)
  local other = 3 - seat
  local mine, theirs = 0, 0
  for i = 1, PITS do
    mine, theirs = mine + s.pits[seat][i], theirs + s.pits[other][i]
  end
  return (s.stores[seat] - s.stores[other]) * 10 + mine - theirs
end

local view = { scoreName = "SEEDS" }

function view.layout(W, H)
  local cw, ch = math.min(11, floor((W - 2) / (PITS + 2))), 25 -- narrower on half a wall, for the idle screen
  local L = base.layout(W, H, cw * (PITS + 2), ch * 2 + 3)
  L.cw, L.ch, L.side = cw, ch, true
  L.topY, L.bottomY = L.y0, L.y0 + ch + 3
  L.debug = { pits = PITS, topY = L.topY, bottomY = L.bottomY, cw = cw, ch = ch }
  return L
end

local function seatColor(p) return p == 1 and C.red or C.blue end

--- Red's pit i runs left to right from the first column; Blue's runs right to left.
local function pitX(L, seat, i)
  if seat == 1 then return L.x0 + i * L.cw end
  return L.x0 + (PITS + 1 - i) * L.cw
end

local function drawPit(L, x, y, count, color, lit)
  ui.fill(x + 1, y, L.cw - 2, L.ch, lit and C.hiTint or C.panel)
  local perRow = L.cw >= 11 and 3 or 2
  for n = 1, math.min(count, perRow * 7) do
    local col, row = (n - 1) % perRow, floor((n - 1) / perRow)
    ui.fill(x + 2 + col * 3, y + 2 + row * 3, 2, 2, color)
  end
  ui.small(tostring(count), x + floor(L.cw / 2), y + L.ch - 2, C.text, lit and C.hiTint or C.panel, "center")
end

function view.score(state) return state.stores[1], state.stores[2] end

function view.drawBoard(L, match)
  local s = match.state
  local hint = match.hint and os.epoch("local") < match.hintUntil and match.hint
  local flash = match.anim
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.bg)
  for seat = 1, 2 do
    local y = seat == 1 and L.bottomY or L.topY
    for i = 1, PITS do
      local lit = (s.winner == 0 and s.turn == seat and s.pits[seat][i] > 0)
      if flash and flash.side == seat and flash.last == i then lit = true end
      drawPit(L, pitX(L, seat, i), y, s.pits[seat][i], seatColor(seat), lit)
      if hint and seat == s.turn and hint.pit == i then ui.frame(pitX(L, seat, i), y, L.cw, L.ch, C.ok, 1) end
    end
  end
  -- each store sits at its owner's right as they look at their own row
  local storeH = L.bh
  ui.fill(L.x0 + 1, L.y0, L.cw - 2, storeH, C.blueTint)
  ui.text(s.stores[2], L.x0 + floor(L.cw / 2), L.y0 + floor(storeH / 2) - 3, C.text, "center")
  local rx = L.x0 + (PITS + 1) * L.cw
  ui.fill(rx + 1, L.y0, L.cw - 2, storeH, C.redTint)
  ui.text(s.stores[1], rx + floor(L.cw / 2), L.y0 + floor(storeH / 2) - 3, C.text, "center")
end

--- A touch on either row only ever means the mover's pit: there's no other seat's row to play from.
function view.actionAt(L, match, px, py)
  local turn = match.state.turn
  local y = turn == 1 and L.bottomY or L.topY
  if py < y or py >= y + L.ch then return nil end
  for i = 1, PITS do
    local x = pitX(L, turn, i)
    if px >= x and px < x + L.cw then return { kind = "sow", pit = i } end
  end
  return nil
end

function view.hintText(a) return "Hint: the pit marked in green (" .. a.pit .. ")" end

function view.finalLine(match)
  local s = match.state
  if s.forfeit then return (s.winner == 1 and match.red or match.blue).name .. " WINS by forfeit", seatColor(s.winner) end
  if s.winner == 3 then return string.format("DRAW - %d seeds each", s.stores[1]), C.hi end
  local w = s.winner == 1 and match.red or match.blue
  return string.format("%s WINS %d-%d", w.name, s.stores[s.winner], s.stores[3 - s.winner]), seatColor(s.winner)
end

function view.howLine(r, duration)
  local s = r.state
  return string.format("%s  -  %d moves  -  %s  -  seeds %d-%d", r.forfeit and "BY FORFEIT" or "ALL SEEDS IN", s.moves, duration, s.stores[1], s.stores[2])
end

function view.scoreLine(match)
  local s = match.state
  return string.format("move %d - seeds %d-%d", s.moves, s.stores[1], s.stores[2])
end

function view.historyLine(h) return string.format("%d-%d seeds", h.boardsRed or 0, h.boardsBlue or 0) end

function view.onEvents(app, match, events)
  for _, ev in ipairs(events) do
    base.animate(match, 450, { side = ev.side, last = ev.last })
    local name = (ev.seat == 1 and match.red or match.blue).name
    app.audio.play(ev.captured and (ev.seat == 2 and "captureBlue" or "captureRed") or (ev.seat == 2 and "placeBlue" or "placeRed"))
    if match.state.winner == 0 and ev.captured then
      app.setToast(string.format("%s captures %d seeds", name, ev.captured), seatColor(ev.seat), 2000)
    elseif match.state.winner == 0 and ev.again then
      app.setToast(name .. " landed in the store and goes again", seatColor(ev.seat), 1500)
    end
  end
end

local M = {
  id = "mancala", title = "Mancala", blurb = "Sow, capture, fill your store", color = "soft", accent = 0x8BE0A8,
  minSize = { w = 118, h = 60 }, cpuLevels = { "easy", "medium", "hard" },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Red plays the bottom row, with its store on the right. Blue plays the top row, with its store on the left. Seeds travel anticlockwise.",
    "",
    "Tap one of your pits. Its seeds are sown one by one around the board, into your store but never your opponent's.",
    "",
    "If your last seed lands in your store, you go again. If it lands in an empty pit of yours with seeds opposite, you capture both.",
    "",
    "The game ends when one side's pits are empty, and each player keeps what is left on their side. Most seeds wins.",
  },
  badges = {
    harvest = { name = "Big Harvest", text = "Finish with 36 seeds or more", test = function(m, sd, _, won)
      return won and not m.forfeit and sd.boards >= 36
    end },
    close = { name = "By A Seed", text = "Win by two seeds or fewer", test = function(m, sd, _, won)
      return won and not m.forfeit and sd.boards - sd.other <= 2
    end },
  },
}

function M.chooseAction(state, level, opts)
  return search.best(rules, state, eval, LEVELS[level] or LEVELS.medium, opts)
end

function M.summarize(match)
  local s = match.state
  return { moves = s.moves, boardsRed = s.stores[1], boardsBlue = s.stores[2] }
end

return base.fill(M)
