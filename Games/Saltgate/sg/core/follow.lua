-- core/follow.lua
-- The simplest driver that uses the road graph: keep to the right-hand lane of the edge you are on, look a few units
-- ahead along its curve, and at the end pick a way out (or the next edge of a planned path). Used by the v2 test
-- traffic and the bench's autopilot; stream C's AI does the real thing. Pure.
--
--   local f = follow.new(roads, x, z [, rng])        -- starts on the nearest edge (nil when no road is near)
--   local input = follow.input(f, car, dt)           -- throttle and steer for vehicle.update / drive.step
--   f.edge, f.s, f.dir (1 = a->b, -1 = b->a), f.route (optional list of edges to take)

local roadgraph = require("sg.core.roadgraph")
local util = require("sg.util")

local M = {}

M.LOOK = 7
M.LANE = 2.2

function M.new(roads, x, z, rng)
  local e, s = roads:nearest(x, z, 40)
  if not e then return nil end
  local dir = 1
  if e.lanes ~= 1 and rng and rng() < 0.5 then dir = -1 end
  return { roads = roads, edge = e, s = s, dir = dir, rng = rng or math.random, route = nil }
end

local function nextEdge(f)
  local e = f.edge
  local at = f.dir == 1 and e.b or e.a
  local choice
  if f.route and #f.route > 0 then
    choice = table.remove(f.route, 1)
  else
    local exits = f.roads:exits(at, e)
    if #exits == 0 then return false end
    -- avoid going straight back unless there is nothing else
    local n = #exits
    if n > 1 then n = n - 1 end
    choice = exits[math.floor(f.rng() * n) + 1] or exits[1]
  end
  f.edge = choice
  if choice.a == at then
    f.dir, f.s = 1, 0
  else
    f.dir, f.s = -1, choice.length
  end
  return true
end

--- Throttle and steer toward a point a little ahead in the lane.
function M.input(f, car, dt)
  local e = f.edge
  if not f.roads:edge(e.id) then
    -- its chunk left: find a road again
    local again = M.new(f.roads, car.x, car.z, f.rng)
    if not again then return { throttle = -0.5, steer = 0 } end
    f.edge, f.s, f.dir = again.edge, again.s, again.dir
    e = f.edge
  end
  -- how far along the edge the car is now
  local near, s = f.roads:nearest(car.x, car.z, 30)
  if near == e then f.s = s end
  local target = f.s + f.dir * M.LOOK
  if target > e.length or target < 0 then
    if not nextEdge(f) then
      f.dir = -f.dir
    end
    e = f.edge
    target = f.s + f.dir * M.LOOK * 0.5
  end
  target = math.max(0, math.min(e.length, target))
  local side = (e.lanes == 1) and 0 or M.LANE * f.dir
  local tx, _, tz = f.roads:pointAt(e, target, side)
  local want = util.headingTo(car.x, car.z, tx, tz)
  local diff = util.wrap(want - car.h)
  local speed = math.min(e.speed or 12, math.abs(diff) > 0.5 and 7 or (e.speed or 12))
  return { throttle = util.clamp((speed - car.v) * 0.4, -1, 1), steer = util.clamp(diff * 2.5, -1, 1) }
end

M.other = roadgraph.other
return M
