-- plugins/c_traffic.lua
-- Stream C: the city's cars. See sg/ai/traffic.lua (the population), sg/ai/lane.lua (how one drives the road graph),
-- sg/ai/fleet.lua (physics near you, rails far off) and sg/ai/scene.lua (drawing what the core view does not).
-- Puts ctx.ai.traffic and ctx.ai.signals where other parts can reach them, and keeps ctx.hour from the time_of_day event.

local trafficLib = require("sg.ai.traffic")
local fleet = require("sg.ai.fleet")
local scene = require("sg.ai.scene")
local signals = require("sg.ai.signals")

local P = { name = "c_traffic", order = 20 }

function P.init(ctx)
  ctx.ai = ctx.ai or {}
  ctx.hour = ctx.hour or (ctx.save and ctx.save.world and ctx.save.world.time) or 17
  ctx.bus:on("time_of_day", function(d) ctx.hour = d.hour end, "c_traffic")
  fleet.install(ctx)
  local t = trafficLib.new(ctx)
  ctx.ai.traffic = t
  ctx.ai.signals = signals
  --- The light a car arriving by edge sees at a node now: "green", "amber" or "red" (nil for no light).
  ctx.ai.signalAt = function(nodeId, edge)
    local node = ctx.roads:node(nodeId)
    if node and signals.isSignal(node) then return signals.state(node, edge, ctx.time or 0) end
    return nil
  end
  --- Anyone (gunfire, an explosion, a crash) can frighten the drivers near a place.
  ctx.ai.alarm = function(x, z, radius, kind)
    t:alarm(x, z, radius)
    if ctx.ai.peds then ctx.ai.peds:scare(x, z, radius, kind) end
  end
  ctx.hitDebounce = 0
end

function P.update(ctx, dt)
  scene.ensure(ctx)
  ctx.time = (ctx.time or 0)
  ctx.ai.traffic:update(dt)
  -- the player's car hits other cars hard: a crime (more for hitting a cruiser)
  local p = ctx.player.car
  ctx.hitDebounce = math.max(0, (ctx.hitDebounce or 0) - dt)
  if p and ctx.hitDebounce <= 0 and math.abs(p.v or 0) > 3 then
    for _, car in ipairs(ctx.cars) do
      if car ~= p and car.fleet and car.hitTimer and car.hitTimer > 0.3 and not car.blockHit then
        if (car.x - p.x) ^ 2 + (car.z - p.z) ^ 2 < 36 then
          ctx.hitDebounce = 4
          ctx.bus:emit("crime", { kind = car.cop and "hit_cruiser" or "hit_car", level = car.cop and 2 or 1, x = car.x, z = car.z })
          break
        end
      end
    end
  end
end

return P
