-- render.lua
-- Draws Saltgate with Pine3D: a chase camera over the city, a dusk sky and the sea behind, a minimap in the corner and
-- the HUD in text on top. Works on any advanced terminal or monitor; Pine3D's 2x3 pixels per character are the
-- resolution, so a monitor's text scale sets how sharp (and how slow) the picture is.

local Pine3D = require("pine3d.Pine3D")
local util = require("sg.util")
local city = require("sg.city")
local models = require("sg.models")
local bigtext = require("sg.bigtext")
local missions = require("sg.missions")
local heatlib = require("sg.heat")
local vehicle = require("sg.vehicle")
local hints = require("sg.hints")

local M = {}
local R = {}
R.__index = R

local floor, cos, sin, abs, deg, atan2 = math.floor, math.cos, math.sin, math.abs, math.deg, math.atan2 or math.atan
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
local MAP_RES = 2
M.CAR_CAM_RATE = 5

-- the job givers: where they stand from their place, which way they face, what they wear
M.NPCS = {
  juno = { dx = 0, dz = 1.2, h = -math.pi / 2, shirt = "yellow", legs = "red", stall = true },
  rusty_door = { dx = 1.2, dz = 0, h = math.pi, shirt = "brown", legs = "blue" },
}

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

--- Build the city's models once (tiles at two levels of detail, the pier) and the map raster. yield is called now
-- and then so a slow computer does not time out.
function R:build(g, yield)
  local tiles = {}
  for i = 0, city.N - 1 do
    for j = 0, city.N - 1 do
      local tile = g.city.tiles[i][j]
      local full, ox, oz = models.tile(tile, false)
      local lod = models.tile(tile, true)
      tiles[#tiles + 1] = { x = ox, z = oz, full = collapse(self, full, ox, 0, oz), lod = collapse(self, lod, ox, 0, oz) }
    end
    if yield then yield() end
  end
  local fronts = {}
  for _, part in ipairs(models.waterfront()) do
    fronts[#fronts + 1] = collapse(self, part.model, part.x, 0, part.z)
  end
  -- the people who give the jobs, at their spots, and Juno's noodle stall
  for name, npc in pairs(M.NPCS) do
    local pl = g.city.places[name]
    local nx, nz = pl.x + npc.dx, pl.z + npc.dz
    fronts[#fronts + 1] = collapse(self, models.rotated(models.person(npc.shirt, false, npc.legs), npc.h), nx, 0.12, nz)
    if npc.stall then
      fronts[#fronts + 1] = collapse(self, models.stall(), pl.x, 0.12, pl.z + npc.dz - 0.6)
    end
  end
  self.static = { tiles = tiles, fronts = fronts }
  self:buildMap(g, yield)
end

-- ---------------------------------------------------------------- the map raster

local MAP_CODE = { sea = "s", road = "r", walk = "w", building = "b", grass = "g", tree = "t", lot = "l", pier = "p", water = "o" }
local MAP_COLOUR = { s = C.blue, r = C.gray, w = C.lightGray, b = C.black, g = C.lime, t = C.green, l = C.lightGray, p = C.brown, o = C.blue }

function R:buildMap(g, yield)
  local x0, z0 = -city.EDGE - 4, -city.EDGE - 4
  local x1, z1 = city.SIZE + city.EDGE + 4, city.pier.z1 + 4
  local rows = {}
  local cols = floor((x1 - x0) / MAP_RES)
  for v = 0, floor((z1 - z0) / MAP_RES) do
    local line = {}
    local wz = z0 + (v + 0.5) * MAP_RES
    for u = 0, cols do
      line[u + 1] = MAP_CODE[city.surface(g.city, x0 + (u + 0.5) * MAP_RES, wz)] or "s"
    end
    rows[v + 1] = table.concat(line)
    if yield and v % 40 == 0 then yield() end
  end
  self.map = { x0 = x0, z0 = z0, rows = rows, cols = cols + 1 }
end

function R:mapColour(x, z)
  local map = self.map
  local row = map.rows[floor((z - map.z0) / MAP_RES) + 1]
  if not row then return C.blue end
  local u = floor((x - map.x0) / MAP_RES) + 1
  if u < 1 or u > map.cols then return C.blue end
  local code = row:sub(u, u)
  return MAP_COLOUR[code] or C.blue
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

local function carKey(car)
  return "car:" .. car.kind .. ":" .. car.colour .. (car.wrecked and ":w" or "")
end

-- ---------------------------------------------------------------- camera and sky

function R:camera(g, mode, dt)
  local p = g.player
  local car = p.car
  local tx, tz, th = p.x, p.z, p.h
  if self.camYaw == nil then self.camYaw = th end
  if car then
    -- behind the car, catching up quickly; in reverse it keeps looking the way the car faces
    self.camYaw = util.turnToward(self.camYaw, th, M.CAR_CAM_RATE * (dt or 0.05) * (1 + abs(util.wrap(th - self.camYaw))))
  else
    -- on foot the camera is locked behind you: A/D turn the view, W always walks into the screen
    self.camYaw = th
  end
  local yaw = self.camYaw
  local fx, fz = cos(yaw), sin(yaw)
  local camX, camY, camZ, pitch
  local talkTo = nil
  if g.talk then
    for name, npc in pairs(M.NPCS) do
      local pl = g.city.places[name]
      if util.dist2(p.x, p.z, pl.x, pl.z) < 64 then talkTo = { pl = pl, npc = npc } end
    end
  end
  if talkTo then
    -- a two-shot from the street: you on one side, the one talking on the other
    local pl, npc = talkTo.pl, talkTo.npc
    local nx, nz = pl.x + npc.dx, pl.z + npc.dz
    local ox, oz = cos(npc.h), sin(npc.h) -- the way they face: out to the street
    local midX, midZ = (nx + p.x) / 2, (nz + p.z) / 2
    camX, camZ, camY = midX + ox * 3.5 - oz * 5.5, midZ + oz * 3.5 + ox * 5.5, 2.3
    yaw = atan2(midZ - camZ, midX - camX)
    self.camYaw = th
    pitch = -6
  elseif mode == "hood" and car then
    camX, camZ = car.x + fx * (car.spec.length * 0.2), car.z + fz * (car.spec.length * 0.2)
    camY = (car.spec.van and 2.3 or 1.55)
    pitch = -4
  else
    local far = mode == "far"
    local back = car and (far and 13 or 8.5) + util.clamp(abs(car.v) * 0.08, 0, 3) or (far and 8 or 4.8)
    local up = car and (far and 6 or 3.6) or (far and 4.5 or 2.5)
    -- pull in if a building is between you and the camera
    local step = back
    while step > 2 do
      local cx, cz = tx - fx * step, tz - fz * step
      if not city.buildingAt(g.city, cx, cz) then break end
      step = step - 1
    end
    camX, camZ, camY = tx - fx * step, tz - fz * step, up
    local lookY = car and 1.2 or 1.3
    pitch = -deg(atan2(up - lookY, step + 4))
  end
  self.cam = { x = camX, y = camY, z = camZ, yaw = yaw, pitch = pitch }
  self.frame:setCamera(camX, camY, camZ, 0, deg(yaw), pitch)
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

-- ---------------------------------------------------------------- the scene

function R:scene(g)
  local list = {}
  local cam = self.cam
  local fx, fz = cos(cam.yaw), sin(cam.yaw)
  for _, t in ipairs(self.static.tiles) do
    local dx, dz = t.x - cam.x, t.z - cam.z
    local d2 = dx * dx + dz * dz
    local ahead = dx * fx + dz * fz
    if d2 < 270 * 270 and (ahead > -40 or d2 < 70 * 70) then
      list[#list + 1] = d2 < 115 * 115 and t.full or t.lod
    end
  end
  for _, o in ipairs(self.static.fronts) do list[#list + 1] = o end

  local near2 = 120 * 120
  local function close(x, z)
    local dx, dz = x - cam.x, z - cam.z
    return dx * dx + dz * dz < near2 and (dx * fx + dz * fz) > -6
  end
  for _, car in ipairs(g.cars) do
    if close(car.x, car.z) then
      local spec, colour, wrecked = car.spec, car.colour, car.wrecked
      self:place(list, self:variant(carKey(car), car.h, function() return models.car(spec, colour, wrecked) end), car.x, 0, car.z)
      if wrecked and (car.burn or 0) < 14 and floor(g.t * 6) % 2 == 0 then
        self:place(list, self:variant("flames", 0, models.flames), car.x, 0, car.z)
      end
    end
  end
  for _, ped in ipairs(g.peds) do
    if close(ped.x, ped.z) then
      local down = ped.state == "down"
      local key = "ped:" .. ped.shirt .. (down and ":d" or "")
      local shirt = ped.shirt
      self:place(list, self:variant(key, ped.h, function() return models.person(shirt, down) end), ped.x, 0.12, ped.z)
    end
  end
  local p = g.player
  if not p.car then
    self:place(list, self:variant("wren", p.h, function() return models.person("orange", false, "gray") end), p.x, 0.12, p.z)
  end
  for _, cash in ipairs(g.pickups) do
    if cash.t <= 0 and close(cash.x, cash.z) then
      self:place(list, self:variant("cash", g.t * 2, models.cash), cash.x, 0.5 + 0.2 * sin(g.t * 3), cash.z)
    end
  end
  -- the job marker, and the services you can use
  local tx, tz, kind = hints.target(g)
  if tx and close(tx, tz) and not g.talk then
    local colour = kind == "giver" and "yellow" or (kind == "car" and "red" or "cyan")
    local beaconY = kind == "car" and 2 or 0
    self:place(list, self:variant("beacon:" .. colour, 0, function() return models.beacon(colour) end), tx, beaconY, tz)
  end
  local spray = g.city.places.respray
  if g.heat.level > 0 and close(spray.x, spray.z) then
    self:place(list, self:variant("beacon:magenta", 0, function() return models.beacon("magenta") end), spray.x, 0, spray.z)
  end
  return list
end

-- ---------------------------------------------------------------- minimap and the big map

function R:minimap(g)
  local rows = self.buffer.colorValues
  local mw = util.clamp(floor(self.pw * 0.24), 16, 70)
  local mh = util.clamp(floor(mw * 0.8), 12, floor(self.ph * 0.5))
  local x0, y0 = self.pw - mw - 1, 4
  local p = g.player
  local scale = p.car and (2.4 + util.clamp(abs(p.car.v) / 25, 0, 1.6)) or 1.8
  local cx, cy = x0 + floor(mw / 2), y0 + floor(mh / 2)
  -- heading-up: the top of the minimap is the way the camera looks, so left and right agree with the 3D view
  local yaw = self.cam and self.cam.yaw or p.h
  local fx, fz = cos(yaw), sin(yaw)
  local rx, rz = -fz, fx
  for v = 0, mh - 1 do
    local row = rows[y0 + v]
    local up = -(v - mh / 2) * scale
    local bx, bz = p.x + fx * up, p.z + fz * up
    for u = 0, mw - 1 do
      local side = (u - mw / 2) * scale
      row[x0 + u] = self:mapColour(bx + rx * side, bz + rz * side)
    end
  end
  local function toMap(wx, wz)
    local dx, dz = wx - p.x, wz - p.z
    return floor((dx * rx + dz * rz) / scale + mw / 2), floor(-(dx * fx + dz * fz) / scale + mh / 2)
  end
  -- frame
  for u = -1, mw do
    rows[y0 - 1][x0 + u] = C.white
    rows[y0 + mh][x0 + u] = C.white
  end
  for v = -1, mh do
    rows[y0 + v][x0 - 1] = C.white
    rows[y0 + v][x0 + mw] = C.white
  end
  local function blip(wx, wz, c, clampToEdge)
    local u, v = toMap(wx, wz)
    if clampToEdge then
      u, v = util.clamp(u, 0, mw - 2), util.clamp(v, 0, mh - 2)
    elseif u < 0 or v < 0 or u > mw - 2 or v > mh - 2 then
      return
    end
    rows[y0 + v][x0 + u] = c
    rows[y0 + v][x0 + u + 1] = c
    rows[y0 + v + 1][x0 + u] = c
    rows[y0 + v + 1][x0 + u + 1] = c
  end
  local places = g.city.places
  blip(places.respray.x, places.respray.z, C.magenta, false)
  blip(places.rusty.x, places.rusty.z, C.lime, false)
  local flash = floor(g.t * 4) % 2 == 0
  for _, car in ipairs(g.cars) do
    if car.ai and car.ai.mode == "cop" and g.heat.level > 0 then blip(car.x, car.z, flash and C.red or C.blue, false) end
  end
  local tx, tz, kind = hints.target(g)
  if tx then blip(tx, tz, kind == "giver" and C.yellow or (kind == "car" and C.red or C.cyan), true) end
  -- north: a red pip on the rim
  local nu, nv = toMap(p.x, p.z - 1000)
  local half = math.min(mw, mh) / 2 - 1
  local du, dv = nu - mw / 2, nv - mh / 2
  local len = math.sqrt(du * du + dv * dv)
  if len > 0 then
    local px = util.clamp(floor(mw / 2 + du / len * half), 0, mw - 2)
    local py = util.clamp(floor(mh / 2 + dv / len * half), 0, mh - 2)
    rows[y0 + py][x0 + px] = C.red
    rows[y0 + py][x0 + px + 1] = C.red
  end
  -- you: a white dot with an orange nose (straight up on foot; the car's way when the camera lags a turn)
  rows[cy][cx] = C.white
  rows[cy][cx + 1] = C.white
  rows[cy + 1][cx] = C.white
  rows[cy + 1][cx + 1] = C.white
  local nx, ny = toMap(p.x + cos(p.h) * 2.4 * scale, p.z + sin(p.h) * 2.4 * scale)
  nx, ny = nx + x0, ny + y0
  if rows[ny] and rows[ny][nx] then rows[ny][nx] = C.orange end
  self.minimapBox = { x0 = x0, y0 = y0, w = mw, h = mh }
end

--- The whole city map, filling the screen, with the places marked. Returns where each icon goes in characters.
function R:bigMap(g)
  local rows = self.buffer.colorValues
  local W, H = self.pw, self.ph
  for y = 1, H do
    local row = rows[y]
    for x = 1, W do row[x] = C.blue end
  end
  local spanX = city.SIZE + 2 * city.EDGE + 8
  local spanZ = city.pier.z1 + city.EDGE + 8
  local scale = math.max(spanX / (W - 4), spanZ / (H - 8))
  local ox = (W - spanX / scale) / 2
  local oy = 4 + (H - 4 - spanZ / scale) / 2
  local wx0, wz0 = -city.EDGE - 4, -city.EDGE - 4
  for y = 1, H do
    local wz = wz0 + (y - oy) * scale
    local row = rows[y]
    for x = 1, W do
      row[x] = self:mapColour(wx0 + (x - ox) * scale, wz)
    end
  end
  local function toScreen(wx, wz)
    return ox + (wx - wx0) / scale, oy + (wz - wz0) / scale
  end
  local p = g.player
  local px, py = toScreen(p.x, p.z)
  local icons = {}
  for _, name in ipairs({ "juno", "rusty", "respray", "hospital", "precinct", "ferry", "gilt_lot", "crane" }) do
    local pl = g.city.places[name]
    local sx, sy = toScreen(pl.x, pl.z)
    icons[#icons + 1] = { x = floor(sx / 2) + 1, y = floor(sy / 3) + 1, icon = pl.icon, colour = pl.color, label = pl.label }
  end
  local tx, tz = hints.target(g)
  if tx then
    local sx, sy = toScreen(tx, tz)
    icons[#icons + 1] = { x = floor(sx / 2) + 1, y = floor(sy / 3) + 1, icon = "*", colour = "yellow", label = "job" }
  end
  icons[#icons + 1] = { x = floor(px / 2) + 1, y = floor(py / 3) + 1, icon = "@", colour = "orange", label = "you" }
  return icons
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

function R:hud(g, cameraMode)
  local t = self.target
  local W, H = self.cw, self.ch
  local p = g.player
  -- top bar
  put(t, 1, 1, string.rep(" ", W), C.white, C.black)
  put(t, 2, 1, util.money(g.money), C.lime, C.black)
  if g.lastMoney then
    local n = g.lastMoney.n
    put(t, 3 + #util.money(g.money), 1, (n >= 0 and "+" or "") .. util.money(n), n >= 0 and C.yellow or C.red, C.black)
  end
  local area = city.areaName(g.city, p.x, p.z)
  if W >= 40 then put(t, 16, 1, area:sub(1, W - 32), C.lightGray, C.black) end
  -- heat: five pips, flashing while the Patrol is on you
  local level = g.heat.level
  local flash = floor(g.t * 4) % 2 == 0
  local hx = W - 15
  put(t, hx, 1, "HEAT", level > 0 and C.white or C.gray, C.black)
  for i = 1, heatlib.MAX do
    local bg = C.gray
    if i <= level then bg = (flash and g:copSees()) and C.blue or C.red end
    put(t, hx + 4 + i * 2 - 1, 1, " ", C.white, bg)
  end

  local overlay = g.overlay ~= nil
  local mapCols = self.minimapBox and math.ceil((self.minimapBox.w + 3) / 2) + 1 or 0
  local left = W - mapCols

  -- where to go: an arrow (from where the camera looks) and how far, then the objective in words
  local objective = (not overlay and not g.talk) and hints.objective(g) or nil
  local tx, tz = hints.target(g)
  local tutorial = g.tutorial ~= nil
  local row = 2
  if tx and not overlay and not g.talk then
    local word, dist = hints.direction(p.x, p.z, self.cam and self.cam.yaw or p.h, tx, tz)
    local head = " " .. hints.ARROWS[word] .. " " .. floor(dist + 0.5) .. "m "
    put(t, 1, row, head, C.black, tutorial and C.cyan or C.yellow)
    local x = #head + 1
    local timeLeft = missions.timeLeft(g)
    if timeLeft then
      local s = math.max(0, floor(timeLeft))
      local clock = string.format(" %d:%02d ", floor(s / 60), s % 60)
      put(t, x + 1, row, clock, C.white, timeLeft < 15 and C.red or C.gray)
      x = x + #clock + 1
    end
    if tutorial then put(t, x + 1, row, "TUTORIAL  X skip", C.cyan, C.black) end
    row = row + 1
  end
  if objective then
    local lines = wrap(objective, math.max(12, left - 2))
    for i = 1, math.min(3, #lines) do
      put(t, 1, row, " " .. lines[i] .. " ", tutorial and C.cyan or C.white, C.black)
      row = row + 1
    end
  elseif not overlay and not g.talk and not g.mission and missions.nextMission(g.progress) then
    local def = missions.nextMission(g.progress)
    local who = def.giver == "juno" and "Mama Juno" or "Rusty"
    for _, line in ipairs(wrap(who .. " has work. Follow the arrow.", math.max(12, left - 2))) do
      put(t, 1, row, " " .. line .. " ", C.lightGray, C.black)
      row = row + 1
    end
  end

  -- messages, in the middle
  local my = math.max(row + 1, floor(H * 0.42))
  for _, m in ipairs(g.messages) do
    for _, line in ipairs(wrap(m.text, W - 4)) do
      if my < H - 2 then centre(t, my, " " .. line .. " ", C.white, C.black, W) end
      my = my + 1
    end
  end

  -- talk: a box at the bottom
  if g.talk then
    local line = g.talk.lines[g.talk.index]
    local body = wrap(line[2], W - 4)
    local top = H - #body - 1
    for y = top - 1, H do put(t, 1, y, string.rep(" ", W), C.white, C.black) end
    put(t, 2, top - 1, line[1], line[1] == "Wren" and C.orange or C.yellow, C.black)
    for i, text in ipairs(body) do put(t, 3, top - 1 + i, text, C.white, C.black) end
    self:hintLine(hints.line(g))
    return
  end

  -- status: what you drive (or you), how fast, and how much punishment is left
  if not overlay then
    local sy = H - 1
    local narrow = W < 40
    local bar = narrow and 5 or 10
    put(t, 1, sy, string.rep(" ", math.min(W, 34)), C.white, C.black)
    if p.car then
      local car = p.car
      local label = narrow and car.spec.name:match("(%S+)$") or car.spec.name
      local spd = vehicle.speedo(car) .. (narrow and "" or " km/h")
      put(t, 2, sy, label, C.white, C.black)
      put(t, 3 + #label, sy, spd, C.lightGray, C.black)
      local hp = car.health / car.spec.health
      local x = 4 + #label + #spd
      put(t, x, sy, string.rep(" ", floor(hp * bar + 0.5)), C.white, hp > 0.35 and C.lime or C.red)
      put(t, x + floor(hp * bar + 0.5), sy, string.rep(" ", bar - floor(hp * bar + 0.5)), C.white, C.gray)
    else
      put(t, 2, sy, "Wren", C.orange, C.black)
      local hp = p.health / 100
      put(t, 7, sy, string.rep(" ", floor(hp * bar + 0.5)), C.white, hp > 0.35 and C.lime or C.red)
      put(t, 7 + floor(hp * bar + 0.5), sy, string.rep(" ", bar - floor(hp * bar + 0.5)), C.white, C.gray)
    end
  end
  self:hintLine(hints.line(g))
  if g.hurtFlash then put(t, 1, H - 1, " ", C.white, C.red) end
end

--- The bottom line: which keys do what right now. Keys in yellow, what they do in grey.
function R:hintLine(text)
  local t = self.target
  local W, H = self.cw, self.ch
  put(t, 1, H, string.rep(" ", W), C.white, C.black)
  local x = 2
  for word, gap in text:gmatch("(%S+)(%s*)") do
    if x + #word - 1 > W then break end
    put(t, x, H, word, hints.isKey(word) and C.yellow or C.lightGray, C.black)
    x = x + #word + #gap
  end
end

-- ---------------------------------------------------------------- frames

--- One game frame. cameraMode: "chase", "far" or "hood".
function R:draw(g, cameraMode, dt)
  self:camera(g, cameraMode, dt)
  self:paintSky()
  self.frame:drawObjects(self:scene(g))
  local rows = self.buffer.colorValues
  if g.overlay then
    local word = g.overlay.kind == "nabbed" and "CUFFED" or "LIGHTS OUT"
    local scale = math.max(1, floor(self.pw / (#word * 4 + 4)))
    local x = floor((self.pw - bigtext.width(word, scale)) / 2) + 1
    local y = floor(self.ph * 0.35)
    local flash = floor(g.t * 4) % 2 == 0
    local colour = g.overlay.kind == "nabbed" and (flash and C.red or C.blue) or C.red
    bigtext.draw(rows, word, x, y, scale, colour, C.black)
  else
    self:minimap(g)
  end
  self.frame:drawBuffer()
  self:hud(g, cameraMode)
  if g.overlay then
    local t = self.target
    local fine = g.overlay.fine
    local text
    if g.overlay.kind == "nabbed" then
      text = fine > 0 and "The Harbor Patrol took " .. util.money(fine) .. " off you." or "Nothing on you worth taking. Lucky."
    else
      text = fine > 0 and "St. Gull's sends a bill: " .. util.money(fine) or "St. Gull's patches you up for free."
    end
    centre(t, math.min(self.ch - 2, floor(self.ch * 0.72)), " " .. text .. " ", C.white, C.black, self.cw)
  end
  self.frames = self.frames + 1
end

--- The title: the city turning slowly behind the name.
function R:title(g, time, lines)
  local tower = g.city.places.gilt_door
  -- circle the middle of town, high up, looking past the Gilt Tower toward the sunset
  local mid = city.SIZE / 2
  local a = 2.2 + sin(time * 0.05) * 0.9
  local cx, cz = mid + cos(a) * 150, mid + sin(a) * 150
  local yaw = atan2(tower.z - cz, tower.x - cx)
  self.cam = { x = cx, y = 55, z = cz, yaw = yaw, pitch = -14 }
  self.frame:setCamera(cx, 55, cz, 0, deg(yaw), -14)
  self:paintSky()
  self.frame:drawObjects(self:scene(g))
  local rows = self.buffer.colorValues
  local word = "SALTGATE"
  local scale = math.max(1, floor(self.pw / (#word * 4 + 6)))
  local x = floor((self.pw - bigtext.width(word, scale)) / 2) + 1
  bigtext.draw(rows, word, x, math.max(2, floor(self.ph * 0.12)), scale, C.yellow, C.black)
  self.frame:drawBuffer()
  local t = self.target
  local y = math.floor(self.ch * 0.12 + scale * 5 / 3) + 2
  centre(t, y, " L O W   T I D E ", C.orange, C.black, self.cw)
  local by = math.max(y + 2, self.ch - #lines)
  for i, line in ipairs(lines) do
    centre(t, by + i - 1, " " .. line[1] .. " ", line[2] or C.white, C.black, self.cw)
  end
end

--- The big map screen.
function R:drawMap(g)
  local icons = self:bigMap(g)
  self.frame:drawBuffer()
  local t = self.target
  for _, ic in ipairs(icons) do
    if ic.y >= 2 and ic.y <= self.ch - 1 and ic.x >= 1 and ic.x <= self.cw then
      put(t, ic.x, ic.y, ic.icon, C[ic.colour] or C.white, C.black)
    end
  end
  put(t, 1, 1, string.rep(" ", self.cw), C.white, C.black)
  centre(t, 1, "SALTGATE", C.yellow, C.black, self.cw)
  local legend = "J Juno  R Rusty  $ Chop  P Respray  H Hospital  F Ferry  * Job  @ You"
  if #legend > self.cw then legend = "J Juno $ Chop P Spray * Job @ You" end
  put(t, 1, self.ch, string.rep(" ", self.cw), C.white, C.black)
  centre(t, self.ch, legend, C.lightGray, C.black, self.cw)
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
