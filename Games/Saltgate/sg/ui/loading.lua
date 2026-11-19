-- ui/loading.lua
-- The loading card: the game's name, a bar and a line of what is happening, for the app (or a plugin) to draw between
-- steps. A loading card costs one call and never touches the 3D frame, so it is safe to draw before anything else exists.
--
--   loading.draw(term, text, fraction)     fraction 0..1 (nil: no bar)
--   loading.TIPS                            lines to show while waiting

local theme = require("sg.ui.theme")
local C = theme.C

local M = {}

M.TIPS = {
  "Gull totems hide all over town. Touch to find.",
  "Miss one race gate and you can still carry on.",
  "Fares pay by distance and the time you have left.",
  "Your best race run becomes a ghost. Beat it.",
  "The radio has four stations: R changes them.",
  "Property pays rent every game day.",
}

function M.draw(t, text, fraction, tip)
  local w, h = t.getSize()
  theme.fill(t, 1, 1, w, h, C.black)
  local y = math.floor(h / 2) - 2
  theme.centre(t, y, "S A L T G A T E", C.yellow, C.black, w)
  theme.centre(t, y + 1, "L O W   T I D E", C.orange, C.black, w)
  if fraction then
    local bw = math.min(30, w - 6)
    theme.bar(t, math.floor((w - bw) / 2) + 1, y + 3, bw, fraction, C.orange, C.gray)
  end
  theme.centre(t, y + 5, text or "Loading...", C.white, C.black, w)
  if tip then theme.centre(t, h - 1, theme.fit(tip, w - 2), C.lightGray, C.black, w) end
end

return M
