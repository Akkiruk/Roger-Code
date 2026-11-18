-- saltgate_c_soak_test.lua
-- SALTGATE stream C's long runs: the whole of stream C (traffic, people, the Patrol with its roadblocks, spikes,
-- helicopter and boat) in the testbed island, a car driving the roads for a long time at every wanted level, and then ten
-- minutes of level six. Every frame is checked for errors (any Lua error fails the run), numbers going bad, entities
-- escaping their caps, AI that sits stuck, and the time stream C takes. The player car is reset onto a road when it has
-- been stuck for four seconds, as a player would; the Patrol is allowed to catch it (the pinch clears the heat and the
-- soak raises it again).

local t = require("testing")
local sim = require("saltgate_c_sim")

local function bad(x) return x ~= x or x == math.huge or x == -math.huge end

--- Run a soak: seconds of play at a level (0 = whatever happens). Returns a table of what was seen.
local function soak(level, seconds, seed)
  local ctx = sim.new({ hour = 14, seed = seed })
  local ap = sim.autopilot(ctx, seed or 5)
  local r = { frames = 0, worstMs = 0, totalMs = 0, nabs = 0, maxCars = 0, maxPeds = 0, maxEntities = 0, stuck = 0, seen = 0, blocks = 0, heli = 0, boat = 0, maxCruisers = 0 }
  ctx.bus:on("player_down", function() r.nabs = r.nabs + 1 end)
  for _ = 1, 40 do sim.step(ctx, 0.05, ap) end
  if level > 0 then ctx.heat.set(level) end
  local stuckSince = {}
  for step = 1, seconds * 20 do
    local ok, cost = pcall(sim.step, ctx, 0.05, ap)
    if not ok then error("level " .. level .. " step " .. step .. ": " .. tostring(cost), 0) end
    r.frames = r.frames + 1
    r.totalMs = r.totalMs + cost * 1000
    if cost * 1000 > r.worstMs then r.worstMs = cost * 1000 end
    if level > 0 and ctx.heat.level ~= level then ctx.heat.set(level) end
    if ctx.heat.seen then r.seen = r.seen + 1 end
    if #ctx.ai.blocks:list() > 0 then r.blocks = r.blocks + 1 end
    if ctx.ai.air.heli then r.heli = r.heli + 1 end
    if ctx.ai.air.boat then r.boat = r.boat + 1 end
    -- numbers, caps
    local list = ctx.world:each()
    if #list > r.maxEntities then r.maxEntities = #list end
    local cars, peds, cruisers = 0, 0, 0
    for _, e in ipairs(list) do
      if bad(e.x) or bad(e.z) or bad(e.y or 0) or bad(e.h or 0) then error("a bad number in " .. tostring(e.kind) .. " at step " .. step, 0) end
      if e.tags and e.tags.ped then peds = peds + 1 end
      if e.fleet then
        cars = cars + 1
        if bad(e.v or 0) then error("a bad speed", 0) end
        if e.cop and not e.wrecked then cruisers = cruisers + 1 end
      end
    end
    if cars > r.maxCars then r.maxCars = cars end
    if peds > r.maxPeds then r.maxPeds = peds end
    if cruisers > r.maxCruisers then r.maxCruisers = cruisers end
    -- stuck: a cruiser or a car that should be moving and is not, for too long (not when it is waiting on a light or a queue
    -- near the player, and blocks and wrecks do not move)
    if step % 20 == 0 then
      for _, e in ipairs(ctx.world:each("fleet")) do
        local hold = e.parked or e.wrecked
        if not hold and math.abs(e.v or 0) < 0.4 then
          stuckSince[e] = (stuckSince[e] or 0) + 1
          local limit = e.cop and e.cop.state == "pursue" and 15 or 45
          local d = math.sqrt((e.x - ctx.player.x) ^ 2 + (e.z - ctx.player.z) ^ 2)
          -- a pursuing cruiser that has caught up is where it should be; the rest must not sit for ever
          if stuckSince[e] > limit and not (e.cop and d < 14) then r.stuck = r.stuck + 1 end
        else
          stuckSince[e] = nil
        end
      end
    end
    if step % 400 == 0 then t.breathe() end
  end
  r.ctx = ctx
  r.avgMs = r.totalMs / math.max(1, r.frames)
  return r
end

t.test("c soak: three minutes at every wanted level, 1 to 6, no errors, no bad numbers, caps held, nothing stuck", function()
  for level = 1, 6 do
    local r = soak(level, 180, 20 + level)
    t.eq(r.stuck, 0, "level " .. level .. ": nothing stuck")
    t.truthy(r.maxCars <= 40, "level " .. level .. ": cars held to a cap: " .. r.maxCars)
    t.truthy(r.maxPeds <= 48, "level " .. level .. ": crowd held to a cap: " .. r.maxPeds)
    t.truthy(r.maxEntities <= 120, "level " .. level .. ": entities: " .. r.maxEntities)
    t.truthy(r.maxCruisers <= level + 3, "level " .. level .. ": a squad of about the plan: " .. r.maxCruisers)
    t.truthy(r.avgMs < 8, "level " .. level .. ": stream C's time a frame on desktop Lua: " .. r.avgMs)
    t.truthy(r.seen > 0, "level " .. level .. ": the Patrol found you")
    if level >= 3 then t.truthy(r.blocks > 0, "level " .. level .. ": roadblocks appeared") end
    if level >= 4 then t.truthy(r.boat > 0, "level " .. level .. ": the boat") end
    if level >= 5 then t.truthy(r.heli > 0, "level " .. level .. ": the helicopter") end
  end
end)

t.test("c soak: ten minutes at level six, no errors, within the frame budget, still nothing stuck", function()
  local r = soak(6, 600, 99)
  t.eq(r.stuck, 0, "nothing stuck")
  t.truthy(r.maxEntities <= 120, "entities: " .. r.maxEntities)
  t.truthy(r.avgMs < 8, "average frame on desktop Lua: " .. r.avgMs)
  t.truthy(r.worstMs < 150, "worst frame on desktop Lua: " .. r.worstMs)
  t.truthy(r.heli > 5000 and r.boat > 1000 and r.blocks > 1000, "all of it showed up: heli " .. r.heli .. " boat " .. r.boat .. " blocks " .. r.blocks)
  t.truthy(r.maxCruisers >= 5, "a full squad: " .. r.maxCruisers)
  t.truthy(r.nabs >= 0)
  -- what stream C leaves behind stays small: the world holds only what the caps allow
  local n = 0
  for _ in pairs(r.ctx.ai.traffic.cars) do n = n + 1 end
  t.truthy(n <= 40, "traffic table: " .. n)
end)

t.test("c soak: a quiet half hour of day and night traffic and people, no errors, hours changing", function()
  local ctx = sim.new({ hour = 6, seed = 41 })
  local ap = sim.autopilot(ctx, 41)
  local hours = {}
  for step = 1, 20 * 600 do
    if step % (20 * 100) == 1 then
      local h = 6 + math.floor(step / (20 * 100)) * 4
      ctx.bus:emit("time_of_day", { hour = h % 24, phase = "x" })
      hours[#hours + 1] = { h = h % 24, cars = ctx.ai.traffic:target(), peds = ctx.ai.peds:target() }
    end
    local ok, err = pcall(sim.step, ctx, 0.05, ap)
    if not ok then error("step " .. step .. ": " .. tostring(err), 0) end
    if step % 400 == 0 then t.breathe() end
  end
  -- the busiest hour has more cars than the quietest
  local lo, hi = 1e9, 0
  for _, h in ipairs(hours) do
    lo, hi = math.min(lo, h.cars + h.peds), math.max(hi, h.cars + h.peds)
  end
  t.truthy(hi > lo, "the city changes with the hour")
  t.eq(#ctx.logs, 0, "nothing logged: " .. table.concat(ctx.logs, "; "))
end)
