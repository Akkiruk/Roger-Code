-- world/view.lua
-- Drawing the real city: a fork of core/view.lua that takes over once the world plugin is installed. The 3D frame (chunk
-- objects in four quarters, cars and people at their heights and tilts), the chase camera that never sinks into a hill,
-- the sky of the hour with its sun, moon, stars and clouds, weather (rain, fog), world-space particles, the heading-up
-- minimap and the whole-city map. Core keeps the interface: builder(), dropper(), draw(ctx, dt), drawMap(ctx, chunks).
--
--   local v = view.new(screen, city)
--   v.sky = { hour = 17.5, kind = "clear", flash = 0 }     set by the plugin each frame
--   v.inside = true                                          the camera is in a room: black round it, a closer camera
--   v:addParticle(p)   p = { x, y, z, vx, vy, vz, life, colour, size, gravity }
--   v.hooks = { function(view, ctx, dt) ... end }            called after the 3D frame, before the minimap

local render = require("sg.render")
local models = require("sg.models")
local chunkmodel = require("sg.world.chunkmodel")
local mapview = require("sg.world.mapview")
local sky = require("sg.world.sky")
local chunkLib = require("sg.core.chunk")
local util = require("sg.util")

local M = {}
local V = {}
V.__index = V

local cos, sin, abs, floor, deg = math.cos, math.sin, math.abs, math.floor, math.deg
local atan2 = math.atan2 or math.atan
local C = rawget(_G, "colors") or {}

-- what the ground is made of in each district: g grass, u paved, l lot, k rock, s sand, m paved by the houses, grass between
local BASE = {
  oldtown = "m", meridian = "u", gilt = "g", lantern = "m", cinder = "l", brine = "l", heron = "g", kestrel = "m", windward = "g", quarry = "k",
}

function M.new(screen, city)
  local v = setmetatable({
    r = render.new(screen), screen = screen, camYaw = nil, mode = "chase", city = city,
    sky = { hour = 17.5, kind = "clear", flash = 0 }, particles = {}, hooks = {}, scenery = {}, frame = 0, tiles = 0,
  }, V)
  v.baseAt = city and function(x, z) return BASE[city:districtAt(x, z).id] end or nil
  -- stars: fixed directions
  local rng = util.rng(99)
  v.stars = {}
  for i = 1, 70 do
    local az, alt = rng() * math.pi * 2, 0.12 + rng() * 0.85
    v.stars[i] = { cos(az) * cos(alt), sin(alt), sin(az) * cos(alt) }
  end
  v.clouds = {}
  for i = 1, 9 do v.clouds[i] = { az = rng() * math.pi * 2, alt = 0.1 + rng() * 0.45, w = 5 + floor(rng() * 8) } end
  return v
end

--- The stream's builder: a chunk's triangles in four quarters, each its own object round its own middle, so Pine3D's
-- culling drops the quarters behind the camera.
function V:builder()
  local r = self.r
  local baseAt = self.baseAt
  return function(c, lod, yield)
    local polys, ox, oz = chunkmodel.build(c, lod, yield, baseAt)
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
    return { objs = objs, tris = #polys, lod = lod }
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
  if self.inside then back, up = 5.2, 5.6 end
  local camX, camY, camZ, pitch
  if self.mode == "hood" and car and not self.inside then
    camX, camZ = tx + fx * car.spec.length * 0.2, tz + fz * car.spec.length * 0.2
    camY = ty + 1.55
    pitch = -4 + deg(car.pitch or 0)
  else
    local step = back
    if not self.inside then
      while step > 2 do
        local cx, cz = tx - fx * step, tz - fz * step
        if stream:surface(cx, cz) ~= "building" then break end
        step = step - 1
      end
    end
    camX, camZ = tx - fx * step, tz - fz * step
    camY = ty + up
    local gy = stream:groundAt(camX, camZ, camY + 5)
    if gy and camY < gy + 1.4 then camY = gy + 1.4 end
    self.camY = self.camY and (self.camY + (camY - self.camY) * util.clamp(dt * 6, 0, 1)) or camY
    camY = math.max(self.camY, (gy or -100) + 1.2)
    pitch = -deg(atan2(camY - (ty + 1.2), step + 4))
  end
  self.cam = { x = camX, y = camY, z = camZ, yaw = yaw, pitch = pitch }
  self.r.cam = self.cam
  self.r.frame:setCamera(camX, camY, camZ, 0, deg(yaw), pitch)
end

-- ---------------------------------------------------------------- the sky

local function put(rows, y, x, c)
  local row = rows[y]
  if row and row[x] then row[x] = c end
end

--- Paint the sky of the hour above the horizon and the sea below it, then the sun or moon, stars and clouds.
function V:paintSky()
  local r = self.r
  local cam = self.cam
  local rows = r.buffer.colorValues
  local w, h = r.pw, r.ph
  if self.inside then
    for y = 1, h do
      local row = rows[y]
      for x = 1, w do row[x] = C.black end
    end
    self.horizon = 0
    return
  end
  local frame = r.frame
  local _, hy = frame:map3dTo2d(cam.x + cos(cam.yaw) * 2000, cam.y, cam.z + sin(cam.yaw) * 2000)
  local horizon = floor(hy)
  local s = self.sky
  local night = sky.nightness(s.hour)
  -- the bands: three sky colours dithered into each other, the sea below
  local top, mid, low = C.purple, C.magenta, C.pink
  for y = 1, h do
    local row = rows[y]
    if y < horizon then
      local f = y / math.max(1, horizon)
      local band = f * 2
      local from, to, t
      if band < 1 then from, to, t = top, mid, band else from, to, t = mid, low, band - 1 end
      if t < 0.25 then
        for x = 1, w do row[x] = from end
      elseif t > 0.75 then
        for x = 1, w do row[x] = to end
      else
        local odd = y % 2
        for x = 1, w do row[x] = ((x + odd) % 2 == 0) and to or from end
      end
    else
      local below = (y - horizon < 2) and ((y + 1) % 2 == 0 and C.cyan or C.blue) or C.blue
      for x = 1, w do row[x] = below end
    end
  end
  self.horizon = horizon
  -- stars
  if night > 0.5 and s.kind ~= "fog" and s.kind ~= "storm" then
    local n = math.floor(#self.stars * (night - 0.4) / 0.6)
    for i = 1, n do
      local st = self.stars[i]
      local sx, sy, ahead = frame:map3dTo2d(cam.x + st[1] * 1000, cam.y + st[2] * 1000, cam.z + st[3] * 1000)
      sx, sy = floor(sx), floor(sy)
      if ahead and sy >= 1 and sy < horizon - 1 then put(rows, sy, sx, C.white) end
    end
  end
  -- the sun, and the moon opposite it
  local elev, az = sky.sunAt(s.hour)
  local function disc(dirx, diry, dirz, rad, c1, c2)
    local sx, sy, ahead = frame:map3dTo2d(cam.x + dirx * 2000, cam.y + diry * 2000, cam.z + dirz * 2000)
    if not ahead or sx < -12 or sx > w + 12 then return end
    for dy = -rad, rad do
      local yy = floor(sy + dy)
      if yy >= 1 and yy < horizon then
        local span = floor(math.sqrt(rad * rad - dy * dy) + 0.5)
        for dx = -span, span do
          put(rows, yy, floor(sx + dx), (abs(dy) < rad * 0.5 and abs(dx) < span - 1) and c1 or c2)
        end
      end
    end
  end
  local rad = math.max(3, floor(h / 14))
  if elev > -0.12 and s.kind ~= "storm" then
    local e = math.max(elev, -0.05)
    local ca = cos(az)
    disc(ca * math.sqrt(1 - e * e), e * 0.9, sin(az) * math.sqrt(1 - e * e), rad, elev < 0.25 and C.yellow or C.white, elev < 0.25 and C.orange or C.yellow)
  end
  if night > 0.4 and s.kind ~= "storm" and s.kind ~= "fog" then
    local me = -elev
    disc(-cos(az) * math.sqrt(1 - me * me), math.max(me, 0.08) * 0.9, -sin(az) * math.sqrt(1 - me * me), math.max(2, rad - 1), C.white, C.lightGray)
  end
  -- clouds: low flat shapes that drift
  if s.kind ~= "clear" then
    local count = (s.kind == "cloudy" or s.kind == "rain") and 7 or (s.kind == "storm" and 9 or 3)
    local colour = (s.kind == "rain" or s.kind == "storm") and C.gray or ((night > 0.5) and C.gray or C.white)
    local colour2 = (s.kind == "rain" or s.kind == "storm") and C.black or C.lightGray
    local drift = (self.frame or 0) * 0.0004
    for i = 1, count do
      local cl = self.clouds[i]
      local a = cl.az + drift
      local sx, sy, ahead = frame:map3dTo2d(cam.x + cos(a) * 1000, cam.y + cl.alt * 700, cam.z + sin(a) * 1000)
      if ahead then
        sy = floor(sy)
        for dx = -cl.w, cl.w do
          local edge = abs(dx) > cl.w - 2
          put(rows, sy, floor(sx + dx), edge and colour2 or colour)
          if not edge then put(rows, sy + 1, floor(sx + dx), colour2) end
          if abs(dx) < cl.w - 3 then put(rows, sy - 1, floor(sx + dx), colour) end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------- the scene

local function tilted(car)
  local base = models.car(car.spec, car.colour, car.wrecked)
  local p, r = car.pitch or 0, car.roll or 0
  local cp, sp, cr, sr = cos(p), sin(p), cos(r), sin(r)
  for _, poly in ipairs(base) do
    for k = 1, 3 do
      local x, y, z = poly["x" .. k], poly["y" .. k], poly["z" .. k]
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
  local maxD = self.drawDistance or 260
  local wk = sky.WEATHER[self.sky.kind or "clear"]
  if wk and wk.fog > 0.5 then maxD = math.min(maxD, 150) elseif wk and wk.rain > 1 then maxD = math.min(maxD, 200) end
  local maxD2 = maxD * maxD
  local tiles = 0
  for _, l in pairs(ctx.stream:loaded()) do
    if l.handle and l.handle.objs then
      for _, o in ipairs(l.handle.objs) do
        local dx, dz = o[1] - cam.x, o[3] - cam.z
        local d2 = dx * dx + dz * dz
        if d2 < maxD2 and (dx * fx + dz * fz > -40 or d2 < 50 * 50) then
          list[#list + 1] = o
          tiles = tiles + 1
        end
      end
    end
  end
  self.tiles = tiles
  local r = self.r
  local function close(x, z)
    local dx, dz = x - cam.x, z - cam.z
    return dx * dx + dz * dz < 130 * 130 and (dx * fx + dz * fz) > -8
  end
  for _, car in ipairs(ctx.cars) do
    if close(car.x, car.z) then
      if car == ctx.player.car and (abs(car.pitch or 0) + abs(car.roll or 0) > 0.04) then
        local key = floor(car.h * 20 + 0.5) .. ":" .. floor((car.pitch or 0) * 25 + 0.5) .. ":" .. floor((car.roll or 0) * 25 + 0.5)
          .. ":" .. car.colour .. (car.wrecked and "w" or "")
        if self.tiltKey ~= key then
          self.tiltKey = key
          self.tiltObj = r.frame:newObject(tilted(car), 0, 0, 0)
        end
        r:place(list, self.tiltObj, car.x, car.y or 0, car.z)
      else
        local spec, colour, wrecked = car.spec, car.colour, car.wrecked
        local key = "car:" .. car.kind .. ":" .. colour .. (wrecked and ":w" or "")
        r:place(list, r:variant(key, car.h, function() return models.car(spec, colour, wrecked) end), car.x, car.y or 0, car.z)
      end
    end
  end
  for _, fn in ipairs(self.scenery) do fn(list, self) end
  local p = ctx.player
  if not p.car then
    r:place(list, r:variant("wren", p.h, function() return models.person("orange", false, "gray") end), p.x, (p.y or 0) + 0.05, p.z)
  end
  return list
end

-- ---------------------------------------------------------------- weather and particles

function V:addParticle(p)
  if #self.particles < (self.maxParticles or 160) then self.particles[#self.particles + 1] = p end
end

function V:drawEffects(ctx, dt)
  local r = self.r
  local rows = r.buffer.colorValues
  local w, h = r.pw, r.ph
  local frame = r.frame
  local cam = self.cam
  -- rain: streaks that fall faster than they drift
  local wk = sky.WEATHER[self.sky.kind or "clear"]
  if wk and wk.rain > 0 and not self.inside then
    local n = wk.rain > 1 and 110 or 55
    local f = self.frame
    for i = 1, n do
      local x = (i * 37 + f * (wk.rain > 1 and 3 or 1)) % w + 1
      local y = (i * 53 + f * 7) % h + 1
      put(rows, y, x, C.lightBlue)
      put(rows, y + 1, x, C.white)
    end
  end
  -- particles in the world
  local ps = self.particles
  local keep = 0
  for i = 1, #ps do
    local p = ps[i]
    p.life = p.life - dt
    if p.life > 0 then
      p.vy = p.vy - (p.gravity or 0) * dt
      p.x, p.y, p.z = p.x + p.vx * dt, p.y + p.vy * dt, p.z + p.vz * dt
      local sx, sy, ahead = frame:map3dTo2d(p.x, p.y, p.z)
      if ahead then
        local dx, dz = p.x - cam.x, p.z - cam.z
        local near = dx * dx + dz * dz < 400
        sx, sy = floor(sx), floor(sy)
        put(rows, sy, sx, p.colour)
        if (p.size or 1) > 1 or near then
          put(rows, sy, sx + 1, p.colour)
          if (p.size or 1) > 1 then put(rows, sy + 1, sx, p.colour) end
        end
      end
      keep = keep + 1
      ps[keep] = p
    end
  end
  for i = keep + 1, #ps do ps[i] = nil end
  for _, hook in ipairs(self.hooks) do hook(self, ctx, dt) end
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
end

--- The whole map from every chunk given (keyed or a list). North is up; height shows as contour lines.
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

--- The whole city from city:mapImage(): north up, contour lines where the ground crosses a step.
function V:drawMapImage(ctx, img)
  local r = self.r
  local rows = r.buffer.colorValues
  local W, H = r.pw, r.ph
  local worldW, worldH = img.w * img.res, img.h * img.res
  local scale = math.max(worldW / (W - 2), worldH / (H - 6))
  local ox = (W - worldW / scale) / 2
  local oy = 4 + (H - 4 - worldH / scale) / 2
  local function cell(x, z)
    local u = floor(x / img.res) + 1
    local v = floor(z / img.res) + 1
    local row = img.codes[v]
    if not row or u < 1 or u > img.w then return "x", 0 end
    return row:sub(u, u), (img.heights[v]:byte(u) - 35) * 1.2 - 8
  end
  for y = 1, H do
    local row = rows[y]
    local z = (y - oy) * scale
    for x = 1, W do
      local wx = (x - ox) * scale
      local code, h = cell(wx, z)
      local _, hAbove = cell(wx, z - scale)
      row[x] = mapview.colour(code, h, hAbove)
    end
  end
  local p = ctx.player
  local px, pz = p.x, p.z
  if p.car then px, pz = p.car.x, p.car.z end
  local sx, sy = floor(ox + px / scale), floor(oy + pz / scale)
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
  self.frame = self.frame + 1
  timed("r.camera", function() self:camera(ctx, dt) end)
  timed("r.sky", function() self:paintSky() end)
  local list
  timed("r.scene", function() list = self:scene(ctx) end)
  timed("r.tris", function() self.r.frame:drawObjects(list) end)
  timed("r.fx", function() self:drawEffects(ctx, dt) end)
  timed("r.minimap", function() if not self.inside then self:minimap(ctx) end end)
  timed("r.blit", function() self.r.frame:drawBuffer() end)
  timed("r.hud", function()
    for _, slot in ipairs({ "top-left", "top-right", "objective", "centre", "status", "hints", "bottom-right" }) do
      for _, w in ipairs(ctx.ui.widgets(slot, ctx)) do w.draw(ctx, self.screen) end
    end
  end)
end

return M
