-- arcade_play.lua
-- The match screen every game shares: player cards, status line, controls, pause. The game draws the board.

local config = require("arcade_constants")
local matches = require("arcade_match")
local seats = require("arcade_seats")
local ui = require("arcade_ui")

local M = {}
local C = ui.C
local floor, max, min = math.floor, math.max, math.min

local app, S, env

function M.bind(appTable)
  app, S, env = appTable, appTable.S, appTable.env
end

local function nowMs() return os.epoch("local") end

local function rankText(name)
  local rank = app.store:rank(name, "elo")
  if rank then return "#" .. rank end
  return "-"
end

local function playerCard(num, slot, x, w, active)
  local color = num == 1 and C.red or C.blue
  local hdr = env.L.hdr
  ui.fill(x, 0, w, hdr, C.panel)
  ui.fill(num == 1 and x or x + w - 2, 0, 2, hdr, color)
  local tx = num == 1 and x + 4 or x + w - 4
  local align = num == 1 and "left" or "right"
  ui.name(slot.name, tx, 1, w - 8, active and C.text or C.line, align, C.panel)
  local sub
  if slot.cpu then
    sub = "COMPUTER"
  elseif slot.guest then
    sub = "GUEST - UNRANKED"
  else
    local p = app.store:get(slot.name)
    sub = p and string.format("%d ELO  %s  W%d L%d", p.elo, rankText(slot.name), p.wins, p.losses) or "NEW PLAYER"
  end
  ui.small(sub, tx, hdr - 3, active and color or C.line, C.panel, align, w - 8)
  if active then
    ui.fill(x, hdr - 1, w, 1, color)
  end
end

local function statusLine(g, viewer)
  local mover = matches.moverSlot(g)
  if g.paused then return "PAUSED", C.warn end
  if g.awaySince and nowMs() - g.awaySince > config.PRESENCE_WARN * 1000 and seats.isHuman(mover) then
    return "Waiting for " .. mover.name .. " to come back...", C.warn
  end
  if g.thinking then return mover.name .. " is thinking...", C.info end
  return app.plugin.view.prompt(g.state, mover.name, viewer)
end

local function drawControls(g, L, viewer)
  local view = app.plugin.view
  local hintOn = not matches.moverSlot(g).cpu and #app.plugin.cpuLevels > 0 and not app.plugin.noHints
  local soundLabel = app.prefs.sound and "SOUND ON" or "SOUND OFF"
  local bx1, bx2 = 1, L.x0 + L.bw + 1
  local bw = L.sideW - 1
  if L.side and bw >= 10 then
    local y = L.y0
    ui.button("menu", bx1, y, bw, 7, "MENU", C.panel, { small = true })
    ui.button("hint", bx1, y + 9, bw, 7, "HINT", C.panel, { small = true, enabled = hintOn })
    ui.button("resign", bx2, y, bw, 7, g.confirmResign and "SURE?" or "RESIGN", g.confirmResign and C.warn or C.panel, { small = true })
    ui.button("sound", bx2, y + 9, bw, 7, soundLabel, C.panel, { small = true })
    view.drawSides(L, g, bx1, bx2, bw, viewer)
  else
    local y = L.footY
    local w = floor((env.W - 10) / 4)
    ui.button("menu", 2, y, w, 7, "MENU", C.panel, { small = true })
    ui.button("hint", 2 + (w + 2), y, w, 7, "HINT", C.panel, { small = true, enabled = hintOn })
    ui.button("resign", 2 + 2 * (w + 2), y, w, 7, g.confirmResign and "SURE?" or "RESIGN", g.confirmResign and C.warn or C.panel, { small = true })
    ui.button("sound", 2 + 3 * (w + 2), y, w, 7, soundLabel, C.panel, { small = true })
  end
end

local function drawPause(g)
  ui.clearButtons() -- nothing behind the box answers
  local W, H = env.W, env.H
  local w, h = min(W - 10, 60), 36
  local x, y = floor((W - w) / 2), floor((H - h) / 2)
  ui.fill(x, y, w, h, C.panel)
  ui.frame(x, y, w, h, C.hi, 1)
  ui.text("PAUSED", floor(W / 2), y + 3, C.hi, "center")
  ui.button("resume", x + 3, y + 13, w - 6, 8, "RESUME", C.ok, { small = true })
  local label = "ABANDON (NO RATING CHANGE)"
  if seats.isRated(g) then
    label = g.abandonBy and (g.abandonBy .. " WANTS TO STOP - TAP TO AGREE") or "ASK TO STOP (NO RATING CHANGE)"
  end
  ui.button("abandon", x + 3, y + 23, w - 6, 8, label, C.warn, { small = true })
end

--- Draw a match. final shows the finished board under its headline. viewer is the seat whose wall this is, when a
-- game keeps things hidden; nil draws only what anyone may see. A wall its opponent is standing at shows that view too.
function M.draw(g, final, viewer)
  local covered = viewer and g.covered[viewer]
  if covered then viewer = nil end
  local s = g.state
  local L = env.L
  local view = app.plugin.view
  ui.screen():clear(C.bg, nil, " ")
  ui.clearButtons()
  local W = env.W
  local cardW = floor((W - 30) / 2)
  playerCard(1, g.red, 0, cardW, s.turn == 1 and s.winner == 0)
  playerCard(2, g.blue, W - cardW, cardW, s.turn == 2 and s.winner == 0)
  -- centre: the score and the move timer
  local cx = floor(W / 2)
  ui.fill(cardW, 0, W - 2 * cardW, L.hdr, C.bg)
  local a, b = view.score(s)
  if a then
    ui.text(a, cx - 4, 1, C.red, "right")
    ui.text("-", cx, 1, C.line, "center")
    ui.text(b, cx + 4, 1, C.blue, "left")
  end
  ui.small("MOVE " .. view.moveNumber(s), cx, L.hdr - 3, C.line, C.bg, "center")
  if g.deadline and not g.paused then
    local left = max(0, g.deadline - nowMs()) / 1000
    local frac = min(1, left / g.timer)
    local bw = (W - 2 * cardW) - 2
    ui.fill(cardW + 1, L.hdr - 1, bw, 1, C.panel)
    ui.fill(cardW + 1, L.hdr - 1, floor(bw * frac), 1, left < 5 and C.warn or C.ok)
  end

  view.drawBoard(L, g, viewer)

  local text, color
  if g.replay then
    text, color = "REPLAY - TAP TO STOP", C.hi
  elseif final then
    text, color = view.finalLine(g)
  elseif covered then
    text, color = "Hidden: your opponent is at this wall", C.warn
  else
    text, color = statusLine(g, viewer)
    if S.toast and nowMs() <= S.toast.untilAt then text, color = S.toast.text, S.toast.color end
  end
  ui.fill(0, L.statusY, env.W, L.statusH, C.bg)
  if ui.textWidth(text) <= env.W - 2 then
    ui.text(text, floor(env.W / 2), L.statusY, color, "center")
  else
    ui.small(text, floor(env.W / 2), L.statusY + 3, color, C.bg, "center", env.W - 2)
  end

  if g.replay then
    ui.region("stopReplay", 0, 0, env.W, env.H)
    return
  end
  if final then
    ui.small("TOUCH FOR RESULTS", floor(env.W / 2), L.statusY + L.statusH, C.line, C.bg, "center")
    ui.region("skipFinal", 0, 0, env.W, env.H)
    return
  end
  drawControls(g, L, viewer)
  if g.paused then drawPause(g) end
end

return M
