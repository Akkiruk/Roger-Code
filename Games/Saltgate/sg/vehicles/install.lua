-- vehicles/install.lua
-- Hooks stream B's vehicles into the core without editing it. The core's loop calls drive.step for every car,
-- vehicle.bump for every pair and models.car for every model, all through module tables, so wrapping them routes:
--   drive.step   to vehicles/physics.lua for any vehicle with a class (a bike, a boat, a truck, the new cars); today's
--                six cars (no class) keep today's physics exactly
--   vehicle.bump to weight-aware bumping when either vehicle has a class
--   models.car   to vehicles/models.lua for any vehicle with a class and any damaged or striped car
-- install() is safe to call twice; uninstall() puts everything back (the tests do).
--
--   install.install()   install.uninstall()   install.installed() -> bool

local M = {}

local saved = nil

function M.installed() return saved ~= nil end

function M.install()
  if saved then return false end
  local drive = require("sg.core.drive")
  local vehicle = require("sg.vehicle")
  local physics = require("sg.vehicles.physics")
  local vmodels = require("sg.vehicles.models")
  local origStep, origBump = drive.step, vehicle.bump
  saved = { step = origStep, bump = origBump }
  drive.step = function(car, input, dt, world, opts)
    if physics.handles(car) then return physics.step(car, input, dt, world, opts) end
    return origStep(car, input, dt, world, opts)
  end
  vehicle.bump = function(a, b)
    if a.spec.class or b.spec.class then return physics.bump(a, b) end
    return origBump(a, b)
  end
  vmodels.install()
  return true
end

function M.uninstall()
  if not saved then return false end
  require("sg.core.drive").step = saved.step
  require("sg.vehicle").bump = saved.bump
  require("sg.vehicles.models").uninstall()
  saved = nil
  return true
end

return M
