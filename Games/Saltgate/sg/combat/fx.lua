-- combat/fx.lua
-- What combat looks like: tracer streaks, muzzle flashes, puffs, the lock-on bracket and the crosshair, the stars
-- over a knocked-down person, a red flash when you are hit, and the comic "POW!" words. The marks are pixels written
-- into the frame buffer before it is blitted (overlay.lua); the words are text written after it. No blood: a hit is a
-- white puff and a word. Needs only a frame with map3dTo2d and the combat system's state.
--
--   fx.paint(ctx, cb, frame, rows, W, H)      the pixel marks
--   fx.words(ctx, cb, frame, screen)          the "POW!" words (text, after the blit)
--   fx.scale(W, dist) -> pixels a unit is at that distance

local overlay = require("sg.combat.overlay")
local weapons = require("sg.combat.weapons")

local M = {}

local C = rawget(_G, "colors") or rawget(_G, "colours") or {}
local floor, cos, sin, abs, max, min, sqrt = math.floor, math.cos, math.sin, math.abs, math.max, math.min, math.sqrt

--- Pixels one unit of the world covers at a distance, for a 70 degree lens.
function M.scale(W, dist)
  return 0.71 * W / max(dist, 0.5)
end

local function dist(cam, x, y, z)
  return sqrt((x - cam.x) ^ 2 + (y - cam.y) ^ 2 + (z - cam.z) ^ 2)
end

local FADE = { white = { "white", "lightGray", "gray" }, yellow = { "yellow", "orange", "brown" },
  lightGray = { "lightGray", "gray", "gray" } }

local function stars(frame, plot, cam, e, W, t, headY)
  local sx, sy = overlay.project(frame, e.x, (e.y or 0) + headY, e.z)
  if not sx then return end
  local d = dist(cam, e.x, (e.y or 0) + headY, e.z)
  local r = max(3, M.scale(W, d) * 0.5)
  for i = 0, 2 do
    local a = t * 5 + i * 2.09
    local px, py = sx + cos(a) * r, sy + sin(a) * r * 0.35
    plot(px, py, i == 0 and C.white or C.yellow)
    plot(px + 1, py, C.yellow)
  end
end

local function bracket(plot, cx, cy, half, colour)
  local leg = max(2, floor(half * 0.5))
  for _, sx in ipairs({ -1, 1 }) do
    for _, sy in ipairs({ -1, 1 }) do
      local x, y = cx + sx * half, cy + sy * half
      for k = 0, leg do
        plot(x - sx * k, y, colour)
        plot(x, y - sy * k, colour)
      end
    end
  end
  plot(cx, cy, colour)
end

local function aimMarks(ctx, cb, frame, plot, W, cam)
  local p = ctx.player
  if cb.pdown > 0 then return end
  local w = cb:weapon()
  local lock = cb.lock
  if lock and not lock.removed and not lock.knocked then
    local x, z = p.x, p.z
    if p.car then x, z = p.car.x, p.car.z end
    local d = sqrt((lock.x - x) ^ 2 + (lock.z - z) ^ 2)
    local fx0, fy0 = overlay.project(frame, lock.x, (lock.y or 0), lock.z)
    local fx1, fy1 = overlay.project(frame, lock.x, (lock.y or 0) + 1.8, lock.z)
    if fx0 and fx1 then
      local half = max(4, abs(fy0 - fy1) * 0.55)
      local inReach = d <= (w.kind == "melee" and w.range + 0.8 or w.range)
      -- red: a shot would reach; yellow: still out of range
      bracket(plot, fx0, (fy0 + fy1) / 2, half, inReach and C.red or C.yellow)
    end
    return
  end
  if w.kind == "gun" then
    local x, y, z, h = p.x, (p.y or 0) + 1.2, p.z, p.h
    if p.car then x, y, z, h = p.car.x, (p.car.y or 0) + 1.2, p.car.z, p.car.h end
    local sx, sy = overlay.project(frame, x + cos(h) * 14, y, z + sin(h) * 14)
    if sx then
      for k = 2, 3 do
        plot(sx - k, sy, C.white) plot(sx + k, sy, C.white) plot(sx, sy - k, C.white) plot(sx, sy + k, C.white)
      end
    end
  end
  local _ = cam
end

function M.paint(ctx, cb, frame, rows, W, H)
  local cam = ctx.view and ctx.view.cam
  if not cam then return end
  local plot = overlay.plotter(rows, W, H)
  -- effects
  for _, f in ipairs(cb.fx) do
    local u = f.t / f.ttl
    if f.kind == "tracer" then
      local ax, ay = overlay.project(frame, f.x0, f.y0, f.z0)
      local bx, by = overlay.project(frame, f.x1, f.y1, f.z1)
      if ax and bx then
        local from, to = max(0, u * 1.3 - 0.4), min(1, u * 1.3)
        local x0, y0 = ax + (bx - ax) * from, ay + (by - ay) * from
        local x1, y1 = ax + (bx - ax) * to, ay + (by - ay) * to
        overlay.line(plot, x0, y0, x1, y1, C[f.c] or C.yellow)
        plot(x1, y1, C.white)
      end
    elseif f.kind == "muzzle" then
      local sx, sy = overlay.project(frame, f.x, f.y, f.z)
      if sx then
        overlay.rect(plot, sx - 1, sy - 1, 3, C.yellow)
        plot(sx, sy, C.white)
      end
    elseif f.kind == "puff" then
      local sx, sy = overlay.project(frame, f.x, f.y, f.z)
      if sx then
        local d = dist(cam, f.x, f.y, f.z)
        local size = max(1, min(6, floor(M.scale(W, d) * f.r * (0.25 + u * 0.55) + 0.5)))
        local ramp = FADE[f.c] or FADE.white
        local colour = C[ramp[u < 0.4 and 1 or (u < 0.75 and 2 or 3)]] or C.white
        overlay.rect(plot, sx - size / 2, sy - size / 2, size, colour)
      end
    elseif f.kind == "swing" then
      local sx, sy = overlay.project(frame, f.x, f.y, f.z)
      if sx then
        local r = 2 + u * 4
        overlay.line(plot, sx - r, sy - r, sx + r, sy + r, C.white)
        overlay.line(plot, sx - r, sy + r, sx + r, sy - r, C.white)
      end
    end
  end
  -- stars over everyone knocked down
  for e in pairs(cb.active) do
    if e.knocked and not e.removed then stars(frame, plot, cam, e, W, cb.clock, 2.1) end
  end
  if cb.pdown > 0 then stars(frame, plot, cam, ctx.player.car or ctx.player, W, cb.clock, 1.0) end
  aimMarks(ctx, cb, frame, plot, W, cam)
  -- hit flash: a red edge
  if cb.flash > 0 then
    for x = 1, W do
      plot(x, 1, C.red) plot(x, 2, C.red) plot(x, H, C.red) plot(x, H - 1, C.red)
    end
    for y = 1, H do
      plot(1, y, C.red) plot(2, y, C.red) plot(W, y, C.red) plot(W - 1, y, C.red)
    end
  end
end

--- The comic words, written over the finished picture.
function M.words(ctx, cb, frame, screen)
  for _, f in ipairs(cb.fx) do
    if f.kind == "pop" then
      local sx, sy = overlay.project(frame, f.x, f.y + f.t * 1.5, f.z)
      if sx then
        local w, h = screen.getSize()
        local col = floor(sx / 2 - #f.text / 2) + 1
        local row = floor(sy / 3) + 1
        if row >= 3 and row <= h - 2 and col >= 1 and col + #f.text - 1 <= w then
          screen.setCursorPos(col, row)
          screen.setTextColour(C.yellow)
          screen.setBackgroundColour(C.red)
          screen.write(f.text)
        end
      end
    end
  end
end

--- The weapon wheel as pieces { text, colour } for the HUD: the six numbers with the one in hand in brackets (dim if
-- not carried), then its name.
function M.wheel(cb)
  local out = {}
  for _, w in ipairs(weapons.LIST) do
    local has = cb.owned[w.id] ~= nil
    local current = w.id == cb.current
    out[#out + 1] = { (current and "[" or " ") .. w.slot .. (current and "]" or " "), current and "yellow" or (has and "white" or "gray") }
  end
  out[#out + 1] = { " " .. weapons.get(cb.current).name, "lightGray" }
  return out
end

return M
