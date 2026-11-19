-- render.lua
-- The Pine3D frame SALTGATE draws into, its palette, the cache of moving models (one per shape and heading step), the
-- sky, and a plain text panel. The city, the camera and the HUD are drawn by sg/core/view.lua and sg/world/view.lua.

local Pine3D = require("pine3d.Pine3D")
local util = require("sg.util")
local models = require("sg.models")

local M = {}
local R = {}
R.__index = R

local floor, cos, sin, abs = math.floor, math.cos, math.sin, math.abs
local C = colors

-- Saltgate at dusk: the palette every screen is given
M.PALETTE = {
  white = 0xF2EEE3, orange = 0xE07A3F, magenta = 0xD9467F, lightBlue = 0x8EC3DE,
  yellow = 0xF2CC4B, lime = 0x6FBF5B, pink = 0xF2A497, gray = 0x4A4E59,
  lightGray = 0x9D9C96, cyan = 0x33B1AA, purple = 0x5A4785, blue = 0x2C5C9E,
  brown = 0x7A4B36, green = 0x2E6A4B, red = 0xD8413A, black = 0x17181E,
}

function M.applyPalette(t)
  if not t.setPaletteColour then return end
  for name, rgb in pairs(M.PALETTE) do t.setPaletteColour(C[name], rgb) end
end

function M.resetPalette(t)
  if not t.setPaletteColour or not term.nativePaletteColour then return end
  for i = 0, 15 do
    local c = 2 ^ i
    t.setPaletteColour(c, term.nativePaletteColour(c))
  end
end

local HEADS = 32

--- A renderer drawing to target (a term or monitor).
function M.new(target)
  local r = setmetatable({ target = target, camYaw = nil, variants = {}, pool = {}, frames = 0 }, R)
  r:setTarget(target)
  return r
end

function R:setTarget(target)
  self.target = target
  local w, h = target.getSize()
  self.cw, self.ch = w, h
  local previous = term.redirect(target)
  self.frame = Pine3D.newFrame(1, 1, w, h)
  term.redirect(previous)
  self.frame:setFoV(70)
  self.buffer = self.frame.buffer
  self.buffer.fastClear = function() end -- the sky is painted each frame instead
  -- betterblittle mixes colours by how alike they look in the screen's palette: tell it about ours
  local blittle = require("pine3d.betterblittle")
  if target.getPaletteColour or target.getPaletteColor then blittle.recomputeColorDistances(target) end
  self.pw, self.ph = self.frame.width, self.frame.height
end

local function collapse(r, model, x, y, z)
  return r.frame:newObject(model, x, y, z)
end

-- ---------------------------------------------------------------- moving things

--- A Pine3D object for a shape key at heading h: built once per (key, heading step), then reused.
function R:variant(key, h, make)
  local set = self.variants[key]
  if not set then
    set = { base = make() }
    self.variants[key] = set
  end
  local idx = floor((h % util.TAU) / util.TAU * HEADS + 0.5) % HEADS
  local obj = set[idx]
  if not obj then
    obj = collapse(self, models.rotated(set.base, idx * util.TAU / HEADS), 0, 0, 0)
    set[idx] = obj
  end
  return obj
end

function R:place(list, template, x, y, z)
  local n = #list + 1
  local o = self.pool[n]
  if not o then
    o = {}
    self.pool[n] = o
  end
  o[1], o[2], o[3], o[4], o[5], o[6], o[7], o[8], o[9] = x, y, z, nil, nil, nil, template[7], template[8], nil
  list[n] = o
end

--- The sky above the horizon; below it, below (default the asphalt grey: in the old city the roads are this background;
-- the streamed world passes the sea blue).
function R:paintSky(below)
  local cam = self.cam
  local _, hy = self.frame:map3dTo2d(cam.x + cos(cam.yaw) * 2000, cam.y, cam.z + sin(cam.yaw) * 2000)
  local horizon = floor(hy)
  local rows = self.buffer.colorValues
  local w = self.pw
  for y = 1, self.ph do
    local c
    if y < horizon then
      local f = y / math.max(1, horizon)
      if f < 0.3 then c = C.purple elseif f < 0.62 then c = C.magenta elseif y < horizon - 2 then c = C.pink else c = C.orange end
    else
      c = below or C.gray
    end
    local row = rows[y]
    for x = 1, w do row[x] = c end
  end
  -- the sun sets in the west, low over the sea
  local sx, sy, ahead = self.frame:map3dTo2d(cam.x - 2000, cam.y + 110, cam.z - 200)
  if ahead and sx > -10 and sx < w + 10 then
    local rad = math.max(3, floor(self.ph / 14))
    for dy = -rad, rad do
      local row = rows[floor(sy + dy)]
      if row and floor(sy + dy) < horizon then
        local span = floor(math.sqrt(rad * rad - dy * dy) + 0.5)
        for dx = -span, span do
          local x = floor(sx + dx)
          if x >= 1 and x <= w then row[x] = (abs(dy) < rad * 0.5 and abs(dx) < span - 1) and C.yellow or C.orange end
        end
      end
    end
  end
  self.horizon = horizon
end

-- ---------------------------------------------------------------- text on top

local function put(t, x, y, text, fg, bg)
  if y < 1 then return end
  t.setCursorPos(x, y)
  t.setTextColour(fg or C.white)
  t.setBackgroundColour(bg or C.black)
  t.write(text)
end

local function wrap(text, width)
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    if #line == 0 then line = word
    elseif #line + 1 + #word <= width then line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if #line > 0 then lines[#lines + 1] = line end
  return lines
end
M.wrap = wrap

local function centre(t, y, text, fg, bg, width)
  local x = floor((width - #text) / 2) + 1
  put(t, math.max(1, x), y, text, fg, bg)
end

--- A plain panel of text lines over black, for the pause screen and help.
function R:panel(lines)
  local t = self.target
  t.setBackgroundColour(C.black)
  t.clear()
  local top = math.max(1, floor((self.ch - #lines) / 2))
  for i, line in ipairs(lines) do
    centre(t, top + i - 1, line[1], line[2] or C.white, C.black, self.cw)
  end
end

return M
