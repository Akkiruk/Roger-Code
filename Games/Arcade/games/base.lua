-- games/base.lua
-- Sensible defaults, so a small game only writes what makes it different. See games/README.md.

local config = require("arcade_config")
local Records = require("arcade_records")
local ui = require("arcade_ui")

local floor, max, min = math.floor, math.max, math.min

local function nothing() end

local VIEW_DEFAULTS = {
  seatLabels = { "RED", "BLUE" },
  seatMarks = { "RED", "BLUE" },
  scoreName = "SCORE",
  tick = function() return false end,
  onResume = nothing,
  onEvents = nothing,
  onSelect = nothing,
  drawSides = nothing,
  moveNumber = function(state) return (state.moves or 0) + 1 end,
  hintText = function() return "Try this one" end,
  refusal = function(_, why) return tostring(why) end,
  scoreLine = function() return "in play" end,
  historyLine = function(h) return (h.moves or 0) .. " moves" end,
}

--- A view's layout for a board of bw x bh cells centred under the player cards, with the controls in a row beneath.
local function layout(W, H, bw, bh)
  local hdr = ui.fontHeight() + 4
  local statusH = ui.fontHeight() + 1
  local L = { W = W, H = H, hdr = hdr, statusH = statusH, side = false, bw = bw, bh = bh }
  L.x0 = floor((W - bw) / 2)
  L.y0 = hdr + 2
  L.statusY = L.y0 + bh + 1
  L.sideW = L.x0 - 2
  L.footY = L.statusY + statusH + 1
  return L
end

--- A layout for a board of cols x rows square cells, as large as the wall allows. A cell is 3 wide for every 2 tall,
-- which is what looks square on a monitor. The controls go beside the board when that leaves it bigger.
local function grid(W, H, cols, rows)
  local function candidate(side)
    local hdr, statusH = ui.fontHeight() + 4, ui.fontHeight() + 1
    local ch = floor((H - hdr - statusH - 3 - (side and 0 or 8)) / rows)
    local cw = min(floor(ch * 1.5), floor((W - (side and 28 or 4)) / cols))
    return { cw = cw, ch = min(ch, max(2, floor(cw / 1.5 + 0.5))), side = side }
  end
  local a, b = candidate(true), candidate(false)
  local pick = (a.cw * a.ch >= b.cw * b.ch) and a or b
  local L = layout(W, H, pick.cw * cols, pick.ch * rows)
  L.cw, L.ch, L.side, L.cols, L.rows = pick.cw, pick.ch, pick.side, cols, rows
  L.colX, L.rowY = {}, {}
  for i = 1, cols do L.colX[i] = L.x0 + (i - 1) * pick.cw end
  for i = 1, rows do L.rowY[i] = L.y0 + (i - 1) * pick.ch end
  return L
end

--- The grid cell under a touch, or nil.
local function cellAt(L, px, py)
  if px < L.x0 or px >= L.x0 + L.bw or py < L.y0 or py >= L.y0 + L.bh then return nil end
  return floor((px - L.x0) / L.cw) + 1, floor((py - L.y0) / L.ch) + 1
end

--- A round piece filling a w x h box.
local function disc(x, y, w, h, color)
  local cut = min(floor(w / 4), floor(h / 3))
  for row = 0, h - 1 do
    local edge = min(row, h - 1 - row)
    local inset = edge < cut and (cut - edge) or 0
    ui.fill(x + inset, y + row, w - 2 * inset, 1, color)
  end
end

--- A draughtboard-style grid: every cell filled in one of two shades.
local function boardGrid(L, shade)
  for r = 1, L.rows do
    for c = 1, L.cols do
      ui.fill(L.colX[c], L.rowY[r], L.cw, L.ch, shade(c, r))
    end
  end
end

-- Sounds a board game wants: a piece down for each seat, and a capture.
local SOUNDS = {
  placeRed = { "casinocraft:casinocraft.card.place", 0.7, 1.15 },
  placeBlue = { "casinocraft:casinocraft.card.place", 0.7, 0.8 },
  capture = { "the_vault:coin_single_place", 0.8, 1.0 },
  captureRed = { "the_vault:coin_single_place", 0.8, 1.2 },
  captureBlue = { "the_vault:coin_single_place", 0.8, 0.85 },
}

-- Badges any game earns the same way. A game adds its own with plugin.badges: id -> { name, text, test(m, sd, p, won) }.
local COMMON_BADGES = {
  first_win = { name = "First Win", text = "Win your first game" },
  hot = { name = "On Fire", text = "Win 3 games in a row" },
  machine = { name = "Machine Breaker", text = "Beat the computer on hard" },
  regular = { name = "Regular", text = "Play 25 games" },
}

local function defaultBadges(plugin)
  local defs, badges = {}, plugin.badges or {}
  for id, def in pairs(COMMON_BADGES) do defs[id] = def end
  for id, def in pairs(badges) do defs[id] = { name = def.name, text = def.text } end
  plugin.achievements = defs
  plugin.award = function(ctx)
    for i, sd in ipairs(ctx.sides) do
      local p = ctx.players[i]
      if p then
        local won = ctx.m.winner == sd.num
        if won then
          ctx.grant(p, "first_win")
          if p.streak >= 3 then ctx.grant(p, "hot") end
          if sd.oppCpu == "hard" then ctx.grant(p, "machine") end
        end
        if p.games >= 25 then ctx.grant(p, "regular") end
        for id, def in pairs(badges) do
          if def.test(ctx.m, sd, p, won) then ctx.grant(p, id) end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------- the idle screen

local function demoRng(n)
  if n then return math.random(n) end
  return math.random()
end

--- One move of the demo game. Returns true when it changed.
local function demoStep(plugin, demo, t, choose)
  if not demo.state or (demo.finishedAt and t - demo.finishedAt > 5000) then
    demo.state, demo.nextAt, demo.finishedAt = plugin.rules.new({ first = math.random(2) }), t + 1200, nil
    demo.match = { state = demo.state, extras = plugin.newExtras(), hintUntil = 0, actions = {} }
    return true
  end
  if demo.finishedAt or t < demo.nextAt then return false end
  local action = choose(demo.state, "easy", { maxNodes = 200 })
  local _, events = plugin.rules.step(demo.state, action, demoRng)
  if plugin.view.onDemoEvents then plugin.view.onDemoEvents(demo.match, events or {}) end
  demo.nextAt = t + 900
  if demo.state.winner ~= 0 then demo.finishedAt = t end
  return true
end

--- The title over a live demo of the board. Returns the y for the prompt.
local function drawAttract(plugin, W, H, demo)
  local L = plugin.view.layout(W, H)
  ui.text(plugin.title, floor(W / 2), 1, ui.C[plugin.color] or ui.C.hi, "center", W - 2)
  if demo.match then plugin.view.drawBoard(L, demo.match, nil) end
  if L.side and plugin.blurb then ui.small(plugin.blurb, floor(W / 2), L.y0 - 1, ui.C.line, ui.C.bg, "center", W - 2) end
  return L.statusY
end

-- ---------------------------------------------------------------- filling in

--- Fill in everything a plugin left out.
local function fill(plugin)
  local view = plugin.view
  for k, v in pairs(VIEW_DEFAULTS) do
    if view[k] == nil then view[k] = v end
  end
  view.score = view.score or function() return nil end
  view.prompt = view.prompt or function(state, name)
    return name .. " to move", state.turn == 1 and ui.C.red or ui.C.blue
  end
  view.finalLine = view.finalLine or function(match)
    local s = match.state
    if s.winner == 3 then return "DRAW", ui.C.hi end
    local w = s.winner == 1 and match.red or match.blue
    return w.name .. (s.forfeit and " WINS by forfeit" or " WINS"), s.winner == 1 and ui.C.red or ui.C.blue
  end
  view.howLine = view.howLine or function(r, duration)
    return string.format("%s  -  %d moves  -  %s", r.forfeit and "BY FORFEIT" or "PLAYED OUT", r.moves or 0, duration)
  end
  view.announceWin = view.announceWin or function(match)
    local s = match.state
    local w, l = s.winner == 1 and match.red or match.blue, s.winner == 1 and match.blue or match.red
    return string.format("%s beat %s at %s%s", w.name, l.name, plugin.title, s.forfeit and " by forfeit" or "")
  end
  view.drawAttract = view.drawAttract or function(W, H, demo) return drawAttract(plugin, W, H, demo) end
  view.demoStep = view.demoStep or function(demo, t, choose) return demoStep(plugin, demo, t, choose) end
  view.debug = view.debug or function(match)
    local s = match.state
    local out = { turn = s.turn, winner = s.winner, moves = s.moves, history = match.actions }
    if plugin.rules.snapshot then
      out.snapshot = plugin.rules.snapshot(s)
      out.legal = {}
      for i, a in ipairs(plugin.rules.legalActions(s)) do out.legal[i] = plugin.rules.key(a) end
    end
    return out
  end

  plugin.cpuLevels = plugin.cpuLevels or {}
  plugin.color = plugin.color or "hi"
  plugin.accent = plugin.accent or config.PALETTE.yellow
  plugin.chatTag = plugin.chatTag or plugin.id:upper()
  plugin.matchOptions = plugin.matchOptions or function() return {} end
  plugin.newExtras = plugin.newExtras or function() return {} end
  plugin.settings = plugin.settings or {}
  if plugin.settings.timer == nil then plugin.settings.timer = 0 end
  if not plugin.achievements then defaultBadges(plugin) end
  plugin.newStore = plugin.newStore or function(opts)
    opts = opts or {}
    return Records.new({
      path = "arcade_" .. plugin.id .. ".dat", log = opts.log,
      settings = plugin.settings, achievements = plugin.achievements, award = plugin.award,
    })
  end
  plugin.summarize = plugin.summarize or function(match) return { moves = #match.actions } end
  plugin.settingsRows = plugin.settingsRows or function(store)
    local timer = store:setting("timer")
    return { { "timer", "MOVE TIMER: " .. (timer > 0 and (timer .. "s") or "OFF") } }
  end
  plugin.changeSetting = plugin.changeSetting or function(store, id, cycle)
    if id == "timer" then store:setting("timer", cycle({ 0, 15, 30, 60 }, store:setting("timer"))) end
  end
  plugin.optionsLine = plugin.optionsLine or function(store)
    local timer = store:setting("timer")
    return timer > 0 and ("TIMER " .. timer .. "s") or "TIMER OFF"
  end
  plugin.moveTimer = plugin.moveTimer or function(store) return store:setting("timer") or 0 end
  plugin.chooseAction = plugin.chooseAction or function() return nil end
  return plugin
end

return {
  fill = fill, layout = layout, grid = grid, cellAt = cellAt, disc = disc, boardGrid = boardGrid, SOUNDS = SOUNDS,
}
