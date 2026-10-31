-- games/base.lua
-- Sensible defaults, so a small game only writes what makes it different. See games/README.md.

local config = require("arcade_config")
local Records = require("arcade_records")
local ui = require("arcade_ui")

local function nothing() end

local VIEW_DEFAULTS = {
  seatLabels = { "RED", "BLUE" },
  seatMarks = { "RED", "BLUE" },
  scoreName = "SCORE",
  tick = function() return false end,
  onResume = nothing,
  onEvents = nothing,
  drawSides = nothing,
  demoStep = function() return false end,
  score = function() return 0, 0 end,
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
  L.x0 = math.floor((W - bw) / 2)
  L.y0 = hdr + 2
  L.statusY = L.y0 + bh + 1
  L.sideW = L.x0 - 2
  L.footY = L.statusY + statusH + 1
  return L
end

--- Fill in everything a plugin left out.
local function fill(plugin)
  local view = plugin.view
  for k, v in pairs(VIEW_DEFAULTS) do
    if view[k] == nil then view[k] = v end
  end
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
  view.drawAttract = view.drawAttract or function(W, H)
    ui.text(plugin.title, math.floor(W / 2), 10, ui.C[plugin.color or "hi"], "center", W - 2)
    if plugin.blurb then ui.small(plugin.blurb, math.floor(W / 2), 20, ui.C.line, ui.C.bg, "center", W - 2) end
    return math.floor(H / 2)
  end
  view.debug = view.debug or function(match)
    local s = match.state
    return { turn = s.turn, winner = s.winner, moves = s.moves, history = match.actions }
  end

  plugin.cpuLevels = plugin.cpuLevels or {}
  plugin.color = plugin.color or "hi"
  plugin.accent = plugin.accent or config.PALETTE.yellow
  plugin.chatTag = plugin.chatTag or plugin.id:upper()
  plugin.matchOptions = plugin.matchOptions or function() return {} end
  plugin.newExtras = plugin.newExtras or function() return {} end
  plugin.newStore = plugin.newStore or function(opts)
    opts = opts or {}
    return Records.new({
      path = "arcade_" .. plugin.id .. ".dat", log = opts.log,
      settings = plugin.settings, achievements = plugin.achievements, award = plugin.award,
    })
  end
  plugin.summarize = plugin.summarize or function(match) return { moves = #match.actions } end
  plugin.settingsRows = plugin.settingsRows or function() return {} end
  plugin.changeSetting = plugin.changeSetting or nothing
  plugin.optionsLine = plugin.optionsLine or function() return "" end
  plugin.moveTimer = plugin.moveTimer or function() return 0 end
  plugin.chooseAction = plugin.chooseAction or function() return nil end
  return plugin
end

return { fill = fill, layout = layout }
