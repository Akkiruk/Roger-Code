-- hilo_view.lua
-- Hi-Lo's table: the card in play, the next card to turn, the streak so far.

local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("hilo_rules")

local C = theme.C
local M = {}

function M.new(ctx)
  return { ctx = ctx, trail = {}, current = nil, multiple = 1, turning = nil }
end

function M.sync(model, state)
  model.trail = {}
  for i, card in ipairs(state.trail) do model.trail[i] = card end
  model.current = state.current
  model.multiple = state.multiple
end

function M.event(model, ev)
  if ev.type == "first" then
    model.current = nil
    model.trail = {}
    return 0.35, "deal"
  elseif ev.type == "reveal" then
    return 0.55, "flip"
  end
  return 0.2, "chip"
end

function M.commit(model, ev)
  if ev.type == "first" or ev.type == "reveal" then
    model.current = ev.card
    model.trail[#model.trail + 1] = ev.card
    if ev.multiple then model.multiple = ev.multiple end
  end
end

function M.draw(c, model, state, anim)
  c:clear(C.felt)
  local cx = math.floor(c.w / 2)
  local top = ui.BAR_H + 2

  -- The streak so far, oldest first
  local xs = ui.fan(cx, math.max(1, #model.trail), ui.SMALL_W, c.w - 10, 1)
  for i, card in ipairs(model.trail) do
    ui.card(c, xs[i], top, card, true)
  end

  local y = top + ui.SMALL_H + 3
  if model.current then ui.card(c, cx - 22, y, model.current, false) end

  if anim and anim.ev.type == "reveal" then
    -- The card lifts as it turns
    ui.card(c, cx + 5, y - math.floor(math.sin(anim.t * math.pi) * 3), anim.t > 0.5 and anim.ev.card or nil, false)
  else
    ui.card(c, cx + 5, y, nil, false)
  end

  c:bigCenter(cx, y + ui.CARD_H + 3, ("x%.2f"):format(model.multiple), C.gold, 2)
  c:textCenter(cx, y + ui.CARD_H + 17, "Guess " .. math.min(state.guesses + 1, rules.MAX_GUESSES)
    .. " of " .. rules.MAX_GUESSES, C.text)
end

return M
