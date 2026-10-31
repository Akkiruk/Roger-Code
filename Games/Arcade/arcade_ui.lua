-- arcade_ui.lua
-- Drawing on a surface: text, panels, buttons. Coordinates are surface cells (0-based). At text scale 0.5 a 6x6
-- monitor is about 120x81 cells. Games draw through this module, so every game shares one look and one touch map.

local M = {}

-- Palette slots (values are set from arcade_config.PALETTE by the app)
M.C = {
  bg = colors.black, panel = colors.gray, line = colors.lightGray, text = colors.white,
  red = colors.red, blue = colors.blue, redTint = colors.brown, blueTint = colors.lightBlue,
  hi = colors.yellow, hiTint = colors.magenta, tie = colors.pink, ok = colors.green, warn = colors.orange,
  accent = colors.purple, info = colors.cyan, soft = colors.lime,
}
local C = M.C

local surfaceApi, font, screen

function M.init(surfaceLib, fontObj, scr)
  surfaceApi, font, screen = surfaceLib, fontObj, scr
end

function M.setScreen(scr) screen = scr end
function M.screen() return screen end

function M.fontHeight() return font.height end

function M.textWidth(str) return (surfaceApi.getTextSize(tostring(str), font)) end

--- Fit a string into maxWidth cells with the pixel font, shortening with ".." when needed.
local function fit(str, maxWidth)
  str = tostring(str)
  if M.textWidth(str) <= maxWidth then return str end
  while #str > 1 do
    str = str:sub(1, #str - 1)
    if M.textWidth(str .. "..") <= maxWidth then return str .. ".." end
  end
  return str
end
M.fit = fit

--- Pixel-font text. align: "left" (x is the left edge), "center" (x is the centre), "right" (x is the right edge).
function M.text(str, x, y, color, align, maxWidth)
  str = maxWidth and fit(str, maxWidth) or tostring(str)
  local w = M.textWidth(str)
  local dx = x
  if align == "center" then dx = x - math.floor(w / 2) elseif align == "right" then dx = x - w end
  if dx < 0 then dx = 0 end
  screen:drawText(str, font, dx, y, color)
  return w
end

--- Native small text (one cell per character).
function M.small(str, x, y, fg, bg, align, maxWidth)
  str = tostring(str)
  if maxWidth and #str > maxWidth then str = str:sub(1, math.max(0, maxWidth - 2)) .. ".." end
  local dx = x
  if align == "center" then dx = x - math.floor(#str / 2) elseif align == "right" then dx = x - #str end
  if dx < 0 then dx = 0 end
  screen:drawString(str, dx, y, bg or C.bg, fg or C.text)
  return #str
end

--- Split text into lines of at most width characters, at spaces.
function M.wrap(text, width)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if line ~= "" and #line + 1 + #word > width then
      lines[#lines + 1] = line
      line = word
    else
      line = line == "" and word or (line .. " " .. word)
    end
  end
  lines[#lines + 1] = line
  return lines
end

--- A name with the pixel font if it fits, otherwise native text.
function M.name(name, x, y, maxW, color, align, bg)
  align = align or "left"
  if M.textWidth(name) <= maxW then
    M.text(name, x, y, color, align)
    return font.height
  end
  M.small(name, x, y + math.floor((font.height - 1) / 2), color, bg or C.bg, align, maxW)
  return 1
end

function M.fill(x, y, w, h, color)
  if w > 0 and h > 0 then screen:fillRect(x, y, w, h, color, nil, " ") end
end

function M.frame(x, y, w, h, color, thick)
  thick = thick or 1
  M.fill(x, y, w, thick, color)
  M.fill(x, y + h - thick, w, thick, color)
  M.fill(x, y, thick, h, color)
  M.fill(x + w - thick, y, thick, h, color)
end

--- Draw a solid line in a colour.
function M.line(x1, y1, x2, y2, color)
  screen:drawLine(x1, y1, x2, y2, color, nil, " ")
end

function M.ellipse(x, y, w, h, color)
  screen:fillEllipse(x, y, w, h, color, nil, " ")
end

--- A monitor that ignores rows already showing, so a wall that stays still sends nothing. Draw through it with
-- surface:output. Make a new one whenever the monitor is cleared.
function M.changedRows(monitor)
  local shown, cx, cy = {}, 1, 1
  return {
    getSize = monitor.getSize,
    setCursorPos = function(x, y) cx, cy = x, y end,
    blit = function(text, fg, bg)
      local row = cx .. text .. fg .. bg
      if shown[cy] ~= row then
        shown[cy] = row
        monitor.setCursorPos(cx, cy)
        monitor.blit(text, fg, bg)
      end
    end,
  }
end

-- ---------------------------------------------------------------- buttons

local buttons = {}

function M.clearButtons() buttons = {} end
function M.buttons() return buttons end
function M.setButtons(list) buttons = list end

--- Draw and register a button. opts: label, color, fg, enabled (default true), small (native text)
function M.button(id, x, y, w, h, label, color, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local bg = enabled and (color or C.panel) or C.panel
  local fg = opts.fg or (enabled and ((bg == C.hi or bg == C.ok or bg == C.soft or bg == C.warn or bg == C.info or bg == C.text) and C.bg or C.text) or C.line)
  M.fill(x, y, w, h, bg)
  if opts.frame then M.frame(x, y, w, h, opts.frame) end
  if label and label ~= "" then
    local ty = y + math.floor((h - (opts.small and 1 or font.height)) / 2)
    if opts.small or M.textWidth(label) > w - 2 then
      M.small(label, x + math.floor(w / 2), y + math.floor((h - 1) / 2), fg, bg, "center", w - 1)
    else
      M.text(label, x + math.floor(w / 2), ty, fg, "center")
    end
  end
  buttons[#buttons + 1] = { id = id, x = x, y = y, w = w, h = h, label = label, enabled = enabled, data = opts.data }
end

--- Register a touch area without drawing anything.
function M.region(id, x, y, w, h, data)
  buttons[#buttons + 1] = { id = id, x = x, y = y, w = w, h = h, enabled = true, data = data }
end

--- Which enabled button covers surface cell (px, py)? Later buttons win.
function M.hit(px, py)
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    if b.enabled and px >= b.x and px < b.x + b.w and py >= b.y and py < b.y + b.h then return b end
  end
  return nil
end

return M
