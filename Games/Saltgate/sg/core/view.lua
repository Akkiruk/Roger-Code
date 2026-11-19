-- core/view.lua
-- Drawing the streamed world (v2): chunk models from the streamer, cars and people at their heights and tilts, a chase
-- camera that rises and falls with the road and never sinks into a hill, the heading-up minimap with contour lines,
-- the city map, and the HUD widgets registered in core/ui.lua. Built on sg/render.lua's frame and model cache.
--
--   local v = view.new(screen)
--   v:builder() -> function(chunk, lod, yield) -> handle      (give it to core/stream.lua as build)
--   v:dropper() -> function(chunk, handle)
--   v:draw(ctx, dt)            the 3D frame, the minimap, then the widgets
--   v:drawMap(ctx, chunks)     the whole map from every chunk given (a table of chunks)

local render = require("sg.render")
local models = require("sg.models")
local chunkmodel = require("sg.core.chunkmodel")
local mapview = require("sg.core.mapview")
local chunkLib = require("sg.core.chunk")
local vehicles = require("sg.core.vehicles")
local util = require("sg.util")

local M = {}
local V = {}
V.__index = V

local cos, sin, abs, floor, deg = math.cos, math.sin, math.abs, math.floor, math.deg
local atan2 = math.atan2 or math.atan
local C = rawget(_G, "colors") or {}

function M.new(screen)
  local v = setmetatable({ r = render.new(screen), screen = screen, camYaw = nil, mode = "chase" }, V)
  return v
end

--- The stream's builder: a chunk's triangles in four quarters, each its own object round its own middle, so Pine3D's
-- culling drops the quarters behind the camera.
function V:builder()
  local r = self.r
  return function(c, lod, yield)
    local polys, ox, oz = chunkmodel.build(c, lod, yield)
    if yield then yield() end
    local q = chunkLib.SIZE / 4
    local parts = { {}, {}, {}, {} }
    for _, p in ipairs(polys) do
      local cx = (p.x1 + p.x2 + p.x3) / 3
      local cz = (p.z1 + p.z2 + p.z3) / 3
      local i = (cx < 0 and 1 or 2) + (cz < 0 and 0 or 2)
      local part = parts[i]
      part[#part + 1] = p
    end
    local objs = {}
    for i, part in ipairs(parts) do
      if #part > 0 then
        local qx = (i == 1 or i == 3) and -q or q
        local qz = (i <= 2) and -q or q
        for _, p in ipairs(part) do
          p.x1, p.x2, p.x3 = p.x1 - qx, p.x2 - qx, p.x3 - qx
          p.z1, p.z2, p.z3 = p.z1 - qz, p.z2 - qz, p.z3 - qz
        end
        objs[#objs + 1] = r.frame:newObject(part, ox + qx, 0, oz + qz)
      end
    end
    return { objs = objs, tris = #polys }
  end
end

function V:dropper()
  return function() end
end

-- ---------------------------------------------------------------- the camera

function V:camera(ctx, dt)
  local p = ctx.player
  local stream = ctx.stream
  local car = p.car
  local tx, ty, tz, th = p.x, p.y or 0, p.z, p.h
  if car then tx, ty, tz, th = car.x, car.y or 0, car.z, car.h end
  if self.camYaw == nil then self.camYaw = th end
  if car then
    self.camYaw = util.turnToward(self.camYaw, th, 5 * dt * (1 + abs(util.wrap(th - self.camYaw))))
  else
    self.camYaw = th
  end
  local yaw = self.camYaw
  local fx, fz = cos(yaw), sin(yaw)
  local back = car and (8.5 + util.clamp(abs(car.v) * 0.08, 0, 3)) or 4.8
  local up = car and 3.6 or 2.5
  if self.mode == "far" then back, up = back * 1.6, up * 1.8 end
  local camX, camY, camZ, pitch
  if self.mode == "hood" and car then
    camX, camZ = tx + fx * car.spec.length * 0.2, tz + fz * car.spec.length * 0.2
    camY = ty + 1.55
    pitch = -4 + deg(car.pitch or 0)
  else
    -- pull in past buildings
    local step = back
    while step > 2 do
      local cx, cz = tx - fx * step, tz - fz * step
      if stream:surface(cx, cz) ~= "building" then break end
      step = step - 1
    end
    camX, camZ = tx - fx * step, tz - fz * step
    camY = ty + up
    -- never under the ground (a hill behind you)
    local gy = stream:groundAt(camX, camZ, camY + 5)
    if gy and camY < gy + 1.4 then camY = gy + 1.4 end
    -- and never under the water: the sea is a surface the camera stays above
    local level = stream:waterAt(camX, camZ)
    if level and camY < level + 0.8 then camY = level + 0.8 end
    -- ease the height so a bump does not shake the picture
    self.camY = self.camY and (self.camY + (camY - self.camY) * util.clamp(dt * 6, 0, 1)) or camY
    camY = math.max(self.camY, (gy or -100) + 1.2, level and level + 0.8 or -100)
    pitch = -deg(atan2(camY - (ty + 1.2), step + 4))
  end
  self.cam = { x = camX, y = camY, z = camZ, yaw = yaw, pitch = pitch }
  -- a cutscene (or anything else) may take the camera: view.override = { x, y, z, yaw (radians), pitch (degrees) }
  local o = self.override
  if o then self.cam = { x = o.x, y = o.y, z = o.z, yaw = o.yaw, pitch = o.pitch } end
  self.r.cam = self.cam
  self.r.frame:setCamera(self.cam.x, self.cam.y, self.cam.z, 0, deg(self.cam.yaw), self.cam.pitch)
end

-- ---------------------------------------------------------------- what plugins add to the picture

--- Add to the 3D scene each frame: fn(ctx, view, list, cam) puts objects in list (with view:place, view:variant or
-- Pine3D objects of its own). Layers run in name order after the core's cars and player. Re-adding a name replaces it.
function V:layer(name, fn)
  self.layers = self.layers or {}
  self.layers[name] = fn
end

--- Add dots to the minimap each frame: fn(ctx, view, dot), dot(x, z, colour) puts a world point on the map (off the
-- edge it is left out; dot(x, z, colour, true) pins it to the edge instead).
function V:minimapLayer(name, fn)
  self.miniLayers = self.miniLayers or {}
  self.miniLayers[name] = fn
end

--- Draw into the pixel buffer each frame, after the 3D and before the blit: fn(ctx, view, rows, cam), rows[y][x] =
-- a colour (y 1..view.r.ph, x 1..view.r.pw). For particles, rain, muzzle flashes, screen flashes. Map a world point
-- to the buffer with view.r.frame:map3dTo2d(x, y, z) -> px, py, inFront.
function V:effectLayer(name, fn)
  self.effects = self.effects or {}
  self.effects[name] = fn
end

--- Put a Pine3D object (from variant or frame:newObject) into the scene at a place.
function V:place(list, obj, x, y, z)
  self.r:place(list, obj, x, y, z)
end

--- A model at a heading, built once per heading step: make() returns a Pine3D model (+x is forward).
function V:variant(key, h, make)
  return self.r:variant(key, h, make)
end

local function sortedNames(t)
  local names = {}
  for k in pairs(t or {}) do names[#names + 1] = k end
  table.sort(names)
  return names
end

--- Where the player should go: ctx.objective (a table, or a function returning one: { text, x, z, kind }), else
-- the story's target (ctx.story.target() -> x, z, kind). nil when there is nowhere.
function M.objective(ctx)
  local o = ctx.objective
  if type(o) == "function" then o = o(ctx) end
  if type(o) == "table" and (o.text or o.x) then return o end
  local story = ctx.story
  if story and type(story.target) == "function" then
    local x, z, kind = story.target()
    if x and z then return { x = x, z = z, kind = kind } end
  end
  return nil
end

-- ---------------------------------------------------------------- the hooks, for any view

--- Give another view (stream A's) the same drawing hooks: layer, minimapLayer, effectLayer, place, variant. It then
-- calls M.sceneHooks, M.minimapHooks, M.effectHooks and M.overrideCamera at the same points as this one.
function M.install(VV)
  VV.layer, VV.minimapLayer, VV.effectLayer = V.layer, V.minimapLayer, V.effectLayer
  VV.place, VV.variant = V.place, V.variant
end

--- After the view's own scene: the objective's beacon, then the plugins' layers. close(x, z) says what is near
-- enough to draw.
function M.sceneHooks(view, ctx, list, cam, isNear)
  local r = view.r
  local o = M.objective(ctx)
  if o and o.x and o.z and isNear(o.x, o.z) then
    local colour = o.colour or (o.kind == "car" and "red" or (o.kind == "giver" and "yellow" or "cyan"))
    local gy = ctx.stream:groundAt(o.x, o.z, o.y) or 0
    r:place(list, r:variant("beacon:" .. colour, 0, function() return models.beacon(colour) end), o.x, gy, o.z)
  end
  for _, name in ipairs(sortedNames(view.layers)) do view.layers[name](ctx, view, list, cam) end
end

--- After the view's own minimap: the objective's dot (pinned to the edge) and the plugins' dots. The map round
-- (px, pz), scale units a pixel, up = (fx, fz), right = (rx, rz), box at (x0, y0) mw x mh pixels.
function M.minimapHooks(view, ctx, rows, px, pz, scale, fx, fz, rx, rz, x0, y0, mw, mh)
  local function dot(x, z, colour, pin)
    local dx, dz = x - px, z - pz
    local u = floor(mw / 2 + (dx * rx + dz * rz) / scale)
    local v = floor(mh / 2 - (dx * fx + dz * fz) / scale)
    if pin then
      u, v = util.clamp(u, 0, mw - 2), util.clamp(v, 0, mh - 2)
    elseif u < 0 or v < 0 or u > mw - 2 or v > mh - 2 then
      return
    end
    rows[y0 + v][x0 + u] = colour
    rows[y0 + v][x0 + u + 1] = colour
    rows[y0 + v + 1][x0 + u] = colour
    rows[y0 + v + 1][x0 + u + 1] = colour
  end
  local o = M.objective(ctx)
  if o and o.x and o.z then dot(o.x, o.z, C[o.colour or "yellow"] or C.yellow, true) end
  for _, name in ipairs(sortedNames(view.miniLayers)) do view.miniLayers[name](ctx, view, dot) end
end

--- The plugins' pixel effects, after the 3D and before the blit.
function M.effectHooks(view, ctx)
  if not view.effects then return end
  local rows = view.r.buffer.colorValues
  for _, name in ipairs(sortedNames(view.effects)) do view.effects[name](ctx, view, rows, view.cam) end
end

--- If something holds the camera (view.override), point it there. Call at the end of the view's camera.
function M.overrideCamera(view)
  local o = view.override
  if not o then return end
  view.cam = { x = o.x, y = o.y, z = o.z, yaw = o.yaw, pitch = o.pitch }
  view.r.cam = view.cam
  view.r.frame:setCamera(o.x, o.y, o.z, 0, deg(o.yaw), o.pitch)
end

-- ---------------------------------------------------------------- the scene

--- A car's model tilted by its pitch and roll (built each frame: only for the cars near you on a slope).
local function tilted(car)
  local base = models.car(car.spec, car.colour, car.wrecked)
  local p, r = car.pitch or 0, car.roll or 0
  local cp, sp, cr, sr = cos(p), sin(p), cos(r), sin(r)
  for _, poly in ipairs(base) do
    for k = 1, 3 do
      local x, y, z = poly["x" .. k], poly["y" .. k], poly["z" .. k]
      -- pitch: nose (+x) up; roll: right side (+z) up
      x, y = x * cp - y * sp, x * sp + y * cp
      y, z = y * cr + z * sr, -y * sr + z * cr
      poly["x" .. k], poly["y" .. k], poly["z" .. k] = x, y, z
    end
  end
  return models.rotated(base, car.h)
end

function V:scene(ctx)
  local list = {}
  local cam = self.cam
  local fx, fz = cos(cam.yaw), sin(cam.yaw)
  local maxD2 = (self.drawDistance or 260) ^ 2
  for _, l in pairs(ctx.stream:loaded()) do
    if l.handle and l.handle.objs then
      for _, o in ipairs(l.handle.objs) do
        local dx, dz = o[1] - cam.x, o[3] - cam.z
        local d2 = dx * dx + dz * dz
        -- behind the camera by more than a quarter's reach, or past the draw distance: not drawn at all
        if d2 < maxD2 and (dx * fx + dz * fz > -40 or d2 < 50 * 50) then list[#list + 1] = o end
      end
    end
  end
  local r = self.r
  local function close(x, z)
    local dx, dz = x - cam.x, z - cam.z
    return dx * dx + dz * dz < 130 * 130 and (dx * fx + dz * fz) > -8
  end
  for _, car in ipairs(ctx.cars) do
    if close(car.x, car.z) then
      if car == ctx.player.car and (abs(car.pitch or 0) + abs(car.roll or 0) > 0.04) then
        -- your car tilts with the road; its model is rebuilt only when the rounded angles change
        local key = floor(car.h * 20 + 0.5) .. ":" .. floor((car.pitch or 0) * 25 + 0.5) .. ":" .. floor((car.roll or 0) * 25 + 0.5)
          .. ":" .. car.colour .. (car.wrecked and "w" or "")
        if self.tiltKey ~= key then
          self.tiltKey = key
          self.tiltObj = r.frame:newObject(tilted(car), 0, 0, 0)
        end
        r:place(list, self.tiltObj, car.x, car.y or 0, car.z)
      else
        local spec, colour, wrecked = car.spec, car.colour, car.wrecked
        -- a class or vehicle with its own look (vehicles.model: bikes, boats, trucks) is built by that; the key
        -- carries the damage stage so a dented model is cached apart from a clean one
        local modeler = vehicles.modelFor(car)
        local stage = car.damageStage or 0
        local key = "car:" .. car.kind .. ":" .. colour .. (wrecked and ":w" or "") .. ":" .. stage
        local make = modeler and function() return modeler(car) end or function() return models.car(spec, colour, wrecked) end
        r:place(list, r:variant(key, car.h, make), car.x, car.y or 0, car.z)
      end
    end
  end
  local p = ctx.player
  if not p.car then
    -- the player's clothes (ctx.player.outfit = { shirt, legs }: the clothes shop changes them)
    local o = p.outfit or {}
    local shirt, legs = o.shirt or "orange", o.legs or "gray"
    r:place(list, r:variant("wren:" .. shirt .. ":" .. legs, p.h, function() return models.person(shirt, false, legs) end), p.x, (p.y or 0) + 0.05, p.z)
  end
  -- the objective's beacon, standing on the ground there, then the plugins' layers
  M.sceneHooks(self, ctx, list, cam, close)
  return list
end

-- ---------------------------------------------------------------- maps

local function sampler(ctx)
  local stream = ctx.stream
  return function(x, z) return stream:chunkAt(x, z) end
end

function V:minimap(ctx)
  local r = self.r
  local rows = r.buffer.colorValues
  local mw = util.clamp(floor(r.pw * 0.24), 16, 70)
  local mh = util.clamp(floor(mw * 0.8), 12, floor(r.ph * 0.5))
  local x0, y0 = r.pw - mw - 1, 4
  local p = ctx.player
  local px, pz = p.x, p.z
  local car = p.car
  if car then px, pz = car.x, car.z end
  local scale = car and (2.4 + util.clamp(abs(car.v) / 25, 0, 1.6)) or 1.8
  local yaw = self.cam and self.cam.yaw or p.h
  local fx, fz = cos(yaw), sin(yaw)
  local rx, rz = -fz, fx
  local at = sampler(ctx)
  local above = {}
  for v = 0, mh - 1 do
    local row = rows[y0 + v]
    local upd = -(v - mh / 2) * scale
    local bx, bz = px + fx * upd, pz + fz * upd
    local heights = {}
    for u = 0, mw - 1 do
      local side = (u - mw / 2) * scale
      local code, h = mapview.sample(at, bx + rx * side, bz + rz * side)
      heights[u] = h
      -- the row above on the screen is the one just drawn: its heights give the contour lines
      row[x0 + u] = mapview.colour(code, h, above[u])
    end
    above = heights
  end
  for u = -1, mw do
    rows[y0 - 1][x0 + u] = C.white
    rows[y0 + mh][x0 + u] = C.white
  end
  for v = -1, mh do
    rows[y0 + v][x0 - 1] = C.white
    rows[y0 + v][x0 + mw] = C.white
  end
  local cx, cy = x0 + floor(mw / 2), y0 + floor(mh / 2)
  for dy = 0, 1 do
    for dx = 0, 1 do rows[cy + dy][cx + dx] = C.orange end
  end
  rows[cy - 2][cx] = C.white
  rows[cy - 2][cx + 1] = C.white
  self.minimapBox = { x0 = x0, y0 = y0, w = mw, h = mh }
  -- dots: the objective (pinned to the edge when it is off the map), then the plugins'
  M.minimapHooks(self, ctx, rows, px, pz, scale, fx, fz, rx, rz, x0, y0, mw, mh)
end

--- The whole map: chunks is a table of chunks (keyed or a list). North is up; height shows as contour lines.
function V:drawMap(ctx, chunks)
  local r = self.r
  local rows = r.buffer.colorValues
  local W, H = r.pw, r.ph
  local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
  local byKey = {}
  for _, c in pairs(chunks) do
    local a, b, cc, d = chunkLib.bounds(c)
    x0, z0, x1, z1 = math.min(x0, a), math.min(z0, b), math.max(x1, cc), math.max(z1, d)
    byKey[chunkLib.key(c.cx, c.cz)] = c
  end
  local at = function(x, z)
    local cx, cz = chunkLib.at(x, z)
    return byKey[chunkLib.key(cx, cz)]
  end
  local scale = math.max((x1 - x0) / (W - 2), (z1 - z0) / (H - 6))
  local ox = (W - (x1 - x0) / scale) / 2
  local oy = 4 + (H - 4 - (z1 - z0) / scale) / 2
  for y = 1, H do
    local row = rows[y]
    local z = z0 + (y - oy) * scale
    for x = 1, W do
      local wx = x0 + (x - ox) * scale
      local code, h = mapview.sample(at, wx, z)
      local _, hAbove = mapview.sample(at, wx, z - scale)
      row[x] = mapview.colour(code, h, hAbove)
    end
  end
  local p = ctx.player
  local px, pz = p.x, p.z
  if p.car then px, pz = p.car.x, p.car.z end
  local sx, sy = floor(ox + (px - x0) / scale), floor(oy + (pz - z0) / scale)
  for dy = -1, 1 do
    for dx = -1, 1 do
      if rows[sy + dy] and rows[sy + dy][sx + dx] then rows[sy + dy][sx + dx] = C.orange end
    end
  end
  r.frame:drawBuffer()
end

-- ---------------------------------------------------------------- a frame

function V:draw(ctx, dt)
  local b = ctx.budget
  local function timed(name, fn)
    if b then b:time(name, fn) else fn() end
  end
  timed("r.camera", function() self:camera(ctx, dt) end)
  timed("r.sky", function() self.r:paintSky(C.blue) end)
  local list
  timed("r.scene", function() list = self:scene(ctx) end)
  timed("r.tris", function() self.r.frame:drawObjects(list) end)
  if not self.override then timed("r.minimap", function() self:minimap(ctx) end) end -- no map over a cutscene
  -- pixel effects (particles, rain, flashes) go into the pixel buffer after the 3D, before it reaches the screen
  if self.effects then
    timed("r.effects", function()
      for _, name in ipairs(sortedNames(self.effects)) do self.effects[name](ctx, self, self.r.buffer.colorValues, self.cam) end
    end)
  end
  timed("r.blit", function() self.r.frame:drawBuffer() end)
  -- the HUD: every registered widget, slot by slot
  timed("r.hud", function()
    for _, slot in ipairs({ "top-left", "top-right", "objective", "centre", "status", "hints", "bottom-right" }) do
      for _, w in ipairs(ctx.ui.widgets(slot, ctx)) do w.draw(ctx, self.screen) end
    end
  end)
end

return M
