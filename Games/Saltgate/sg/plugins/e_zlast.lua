-- plugins/e_zlast.lua
-- Stream E: the last plugin to draw each frame. It draws the transition curtain over everything the others drew, and forgets
-- the frame's keys (ui/keys.lua keeps them until now so every plugin and screen in a frame sees the same ones).

local P = { name = "e_zlast", order = 99, needs = { "e_ui" } }

function P.draw(ctx)
  local eui = ctx.eui
  if eui.transition:active() then
    eui.transition:update(eui.dt or 0.05)
    local w, h = ctx.screen.getSize()
    eui.transition:draw(ctx.screen, w, h)
  end
  eui.keys:flush()
end

return require("sg.ui.guard").plugin(P)
