-- plugins/b_vehicles.lua
-- Stream B's vehicles (v2 only): 18 more vehicle definitions (13 cars, 4 bikes, trucks with trailers, boats, the police
-- helicopter) read from content/vehicles, per-class physics, damage you can see, and ctx.fleet for spawning them.
--   ctx.fleet:spawn(kind, x, z, h, { paint, stripe, tune, trailer })    ctx.fleet:snapshot(car) / build(data, x, z, h)
--   sg/vehicles/custom.lua           paint, stripes and tune tiers as data, with prices (for the garage and shops)
-- Today's six cars keep today's physics exactly; everything with a class goes through sg/vehicles/physics.lua.

local catalog = require("sg.vehicles.catalog")
local install = require("sg.vehicles.install")
local fleetLib = require("sg.vehicles.fleet")
local vmodels = require("sg.vehicles.models")
local overlay = require("sg.combat.overlay")
local vehicleLib = require("sg.vehicle")

local floor, cos, sin, max, min = math.floor, math.cos, math.sin, math.max, math.min
local C = rawget(_G, "colors") or rawget(_G, "colours") or {}

local function playing(ctx)
  return function()
    local top = ctx.ui.top()
    return top ~= nil and top.name == "play"
  end
end

--- Smoke over a smoking car, flames over a burning one, a thin curl off a wreck.
local function paintSmoke(ctx, fleet, frame, rows, W, H)
  local cam = ctx.view and ctx.view.cam
  if not cam then return end
  local plot = overlay.plotter(rows, W, H)
  local fx, fz = cos(cam.yaw), sin(cam.yaw)
  local t = fleet.clock
  for _, car in ipairs(ctx.cars) do
    local stage = car.stage or 0
    if stage >= 2 or car.wrecked then
      local dx, dz = car.x - cam.x, car.z - cam.z
      local d2 = dx * dx + dz * dz
      if d2 < 60 * 60 and dx * fx + dz * fz > 0 then
        local d = math.sqrt(d2)
        local k = 0.71 * W / max(d, 1)
        local hx, hz = car.x + cos(car.h) * car.spec.length * 0.3, car.z + sin(car.h) * car.spec.length * 0.3
        local top = (car.y or 0) + car.spec.height
        local n = stage >= 3 and 4 or 3
        for i = 0, n - 1 do
          local ph = (t * 0.8 + i / n + (car.id or 0) * 0.37) % 1
          local sx, sy = overlay.project(frame, hx + sin(t * 2 + i) * 0.3, top + ph * 3.0, hz)
          if sx then
            local size = max(1, min(5, floor(k * (0.5 + ph * 0.9) + 0.5)))
            overlay.rect(plot, sx - size / 2, sy - size / 2, size, ph < 0.45 and C.gray or C.lightGray)
          end
        end
        if stage >= 3 and not car.wrecked then
          for i = 0, 2 do
            local flick = (t * 9 + i * 1.7 + (car.id or 0)) % 1
            local sx, sy = overlay.project(frame, hx + (i - 1) * 0.4, top - 0.2 + flick * 0.9, hz)
            if sx then
              local size = max(1, min(3, floor(k * 0.4 + 0.5)))
              overlay.rect(plot, sx - size / 2, sy - size / 2, size, flick < 0.5 and C.yellow or C.orange)
            end
          end
        end
      end
    end
  end
end

local function wrapScene(view, ctx)
  if type(view.scene) ~= "function" or view.vehicleSceneWrapped then return end
  view.vehicleSceneWrapped = true
  local orig = view.scene
  view.scene = function(self, c)
    local list = orig(self, c)
    local cam, r = self.cam, self.r
    if not cam then return list end
    local fx, fz = cos(cam.yaw), sin(cam.yaw)
    for _, car in ipairs(c.cars) do
      local tr = car.trailer
      if tr then
        local dx, dz = tr.x - cam.x, tr.z - cam.z
        if dx * dx + dz * dz < 130 * 130 and dx * fx + dz * fz > -10 then
          local key = "trailer:" .. tr.kind .. ":" .. tr.colour
          r:place(list, r:variant(key, tr.h, function() return vmodels.build(tr.spec, tr.colour, false) end), tr.x, tr.y or 0, tr.z)
        end
      end
    end
    return list
  end
end

return {
  name = "b_vehicles",
  order = 10,

  init = function(ctx)
    local count, problems = catalog.load(ctx.content, ctx.vehicles, vehicleLib)
    for _, p in ipairs(problems) do ctx.log("b_vehicles: " .. p) end
    ctx.log("b_vehicles: " .. count .. " vehicles defined")
    install.install()
    local fleet = fleetLib.new(ctx)
    ctx.fleet = fleet
    if ctx.view and ctx.view.r then
      overlay.install(ctx.view.r.frame, playing(ctx))
      wrapScene(ctx.view, ctx)
    end
    overlay.add("b_vehicles", function(frame, rows, W, H) paintSmoke(ctx, fleet, frame, rows, W, H) end)
    if fs and fs.exists and fs.exists("saltgate_b_demo.flag") then
      require("sg.combat.showroom").vehicles(ctx, fleet)
    end
  end,

  update = function(ctx, dt)
    if ctx.view and ctx.view.r then overlay.install(ctx.view.r.frame, playing(ctx)) end
    ctx.fleet:update(dt)
  end,
}
