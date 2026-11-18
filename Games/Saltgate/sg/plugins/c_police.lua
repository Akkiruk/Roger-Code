-- plugins/c_police.lua
-- Stream C: the Harbor Patrol. Six wanted levels (sg/heat/wanted.lua), cruisers that chase, box in and PIT
-- (sg/heat/cops.lua), roadblocks and spike strips (sg/heat/blocks.lua), a helicopter with a searchlight and a patrol boat
-- (sg/heat/air.lua), the "last seen" search circle that closes as line of sight is lost, hideouts and bribes.
--
-- Listens to  crime {kind, level, x?, z?, silent?}   level = the stars the crime is worth (1-6)
--             vehicle_enter {stolen}   respawn   player_down   load   save   time_of_day
-- Emits       heat_changed {level, previous}   player_down {kind = "nabbed"}   money {amount, reason, total} (a bribe)
-- ctx.heat is the wanted state: level, seen, radius, cx, cz, unseen, total, flash; plus
--   ctx.heat.set(n)             set the level outright (0 ends it; a mission's alarm, the Paint & Pray)
--   ctx.heat.bribe() -> ok, cost | false, why     pay off one level when no patrol can see you
--   ctx.heat.hideouts()         the hideouts near you (chunk spawns of kind "hideout")
--   ctx.ai.cops, ctx.ai.blocks, ctx.ai.air      the parts, for tests and other plugins

local wantedLib = require("sg.heat.wanted")
local copsLib = require("sg.heat.cops")
local blocksLib = require("sg.heat.blocks")
local airLib = require("sg.heat.air")
local scene = require("sg.ai.scene")
local saveLib = require("sg.core.save")

local P = { name = "c_police", order = 30, needs = { "c_traffic", "c_peds" } }

local floor, cos, sin = math.floor, math.cos, math.sin

local function blankSection() return { busted = 0, bribes = 0, maxLevel = 0, lost = 0 } end

local function put(t, x, y, text, fg, bg)
  t.setCursorPos(x, y)
  t.setTextColour(fg or colours.white)
  t.setBackgroundColour(bg or colours.black)
  t.write(text)
end

function P.init(ctx)
  saveLib.section("heat", { version = 1, owner = "c_police", blank = blankSection })
  ctx.save.heat = ctx.save.heat or blankSection()
  local h = wantedLib.new()
  ctx.heat = h
  ctx.ai = ctx.ai or {}
  local cops = copsLib.new(ctx, ctx.ai.traffic)
  local blocks = blocksLib.new(ctx, ctx.ai.peds)
  local air = airLib.new(ctx)
  cops.avoid = {}
  ctx.ai.cops, ctx.ai.blocks, ctx.ai.air = cops, blocks, air

  local function who()
    return ctx.player.car or ctx.player
  end
  local function changed(before)
    if h.level ~= before then
      local s = ctx.save.heat
      if h.level > (s.maxLevel or 0) then s.maxLevel = h.level end
      ctx.bus:emit("heat_changed", { level = h.level, previous = before })
    end
  end

  function h.set(n)
    local before = h.level
    local t = who()
    if before == 0 and n > 0 then h.cx, h.cz = t.x, t.z end
    wantedLib.set(h, n)
    changed(before)
  end

  function h.bribe()
    if h.level < 1 then return false, "nothing to pay off" end
    if h.level > 4 then return false, "too hot" end
    if h.seen then return false, "they can see you" end
    local cost = 150 * h.level
    local pl = ctx.save.player
    if (pl.money or 0) < cost then return false, "not enough money" end
    pl.money = pl.money - cost
    ctx.bus:emit("money", { amount = -cost, reason = "bribe", total = pl.money })
    ctx.save.heat.bribes = (ctx.save.heat.bribes or 0) + 1
    h.set(h.level - 1)
    return true, cost
  end

  --- Hideouts: spawn records of kind "hideout" in the chunks round you.
  function h.hideouts()
    local out = {}
    local p = who()
    local seen = {}
    for dz = -1, 1 do
      for dx = -1, 1 do
        local c = ctx.stream:chunkAt(p.x + dx * 88, p.z + dz * 88)
        if c and not seen[c] then
          seen[c] = true
          for _, sp in ipairs(c.spawns or {}) do
            if sp[1] == "hideout" then out[#out + 1] = { x = sp[2], z = sp[3] } end
          end
        end
      end
    end
    return out
  end

  ctx.bus:on("crime", function(d)
    if d.silent then return end
    local before = h.level
    local t = who()
    if before == 0 then h.cx, h.cz = d.x or t.x, d.z or t.z end
    wantedLib.crime(h, d.level or 1, d.kind)
    changed(before)
  end, "c_police")

  -- stealing a car with someone looking is a crime
  ctx.bus:on("vehicle_enter", function(d)
    if d.stolen then
      local t = who()
      if #ctx.world:near(t.x, t.z, 14, "ped") > 0 then
        ctx.bus:emit("crime", { kind = "carjack", level = 1 })
      end
    end
  end, "c_police")

  local function standDown()
    local before = h.level
    wantedLib.set(h, 0)
    cops:release()
    blocksLib.mend(ctx)
    changed(before)
  end
  ctx.bus:on("respawn", standDown, "c_police")
  ctx.bus:on("player_down", function(d)
    if d.kind == "ko" then standDown() end
  end, "c_police")
  ctx.bus:on("save", function(d) d.data.heat = ctx.save.heat end, "c_police")
  ctx.bus:on("load", function(d)
    if d.data and d.data.heat then ctx.save.heat = d.data.heat end
    ctx.save.heat = ctx.save.heat or blankSection()
  end, "c_police")

  -- ------------------------------------------------------------ the HUD: stars, what the Patrol knows, and the alarm
  ctx.ui.widget({ name = "c_wanted", slot = "top-right", priority = 80,
    visible = function(c) return c.heat and (c.heat.level > 0 or c.heat.flash > 0) end,
    draw = function(c, t)
      local w = (c.screen.getSize())
      local flash = floor((c.time or 0) * 4) % 2 == 0
      local lit = c.heat.seen and (flash and colours.red or colours.blue) or colours.yellow
      local x = w - 7
      for i = 1, wantedLib.MAX do
        if i <= c.heat.level then put(t, x + i - 1, 1, "*", lit) else put(t, x + i - 1, 1, ".", colours.grey) end
      end
      local text
      if c.heat.seen then
        text = "SPOTTED"
      else
        text = string.format("LOST %d%%", floor(wantedLib.progress(c.heat) * 100))
      end
      put(t, x - #text - 1, 1, text, c.heat.seen and (flash and colours.red or colours.white) or colours.lightGrey)
    end })
  ctx.ui.widget({ name = "c_wanted_flash", slot = "centre", priority = 90,
    visible = function(c) return c.heat and c.heat.flash > 0 and floor((c.time or 0) * 6) % 2 == 0 end,
    draw = function(c, t)
      local w = (c.screen.getSize())
      local text = " WANTED " .. string.rep("*", c.heat.level) .. " "
      put(t, math.max(1, floor((w - #text) / 2)), 5, text, colours.white, colours.red)
    end })

  -- ------------------------------------------------------------ drawing what the Patrol brings
  scene.layer(ctx, "police", function(c, view, list, cam)
    local am = require("sg.ai.models")
    local r = view.r
    local hel = air.heli
    if hel then
      r:place(list, r:variant("c_heli", hel.h, am.heli), hel.x, hel.y, hel.z)
      r:place(list, r:variant("c_rotor", hel.spin, am.rotor), hel.x, hel.y + 2.15, hel.z)
      if air.spot then r:place(list, r:variant("c_pool", 0, am.lightPool), air.spot.x, air.spot.y, air.spot.z) end
    end
    local boat = air.boat
    if boat then r:place(list, r:variant("c_boat", boat.h, am.boat), boat.x, boat.y or 0, boat.z) end
    for _, s in ipairs(c.world:each("spikes")) do
      local dx, dz = s.x - cam.x, s.z - cam.z
      if dx * dx + dz * dz < 120 * 120 then
        local w = floor(s.w)
        r:place(list, r:variant("c_spikes:" .. w, s.h, function() return am.spikes(w) end), s.x, s.y + 0.02, s.z)
      end
    end
  end)
  scene.minimap(ctx, "police", function(c, view, dot)
    local C = colors
    local flash = floor((c.time or 0) * 4) % 2 == 0
    for _, car in ipairs(c.world:each("cop")) do
      if car.cop and car.cop.state ~= "patrol" and not car.wrecked then dot(car.x, car.z, flash and C.red or C.blue) end
    end
    if air.heli then dot(air.heli.x, air.heli.z, C.yellow) end
    if air.boat then dot(air.boat.x, air.boat.z, C.cyan) end
    if h.level > 0 and not h.seen and h.radius > 4 then
      for k = 0, 35 do
        local a = k / 36 * math.pi * 2
        dot(h.cx + cos(a) * h.radius, h.cz + sin(a) * h.radius, C.white)
      end
    end
  end)
end

function P.update(ctx, dt)
  local h = ctx.heat
  local cops, blocks, air = ctx.ai.cops, ctx.ai.blocks, ctx.ai.air
  local t = ctx.player.car or ctx.player
  local before = h.level
  local seenCops, nabbed = cops:update(dt, h)
  local seenAir = air:update(dt, h)
  blocks:update(dt, h, cops.avoid)
  -- laying low: parked in a hideout, out of sight
  local hidden = false
  ctx.hideT = (ctx.hideT or 0) - dt
  if ctx.hideT <= 0 then
    ctx.hideT = 1
    ctx.hideouts = h.level > 0 and h.hideouts() or {}
  end
  if math.abs(t.v or 0) < 3 then
    for _, sp in ipairs(ctx.hideouts or {}) do
      if (sp.x - t.x) ^ 2 + (sp.z - t.z) ^ 2 < 49 then hidden = true break end
    end
  end
  local res = wantedLib.update(h, dt, seenCops or seenAir, t.x, t.z, hidden)
  if res == "lost" then
    ctx.save.heat.lost = (ctx.save.heat.lost or 0) + 1
    cops:release()
    blocksLib.mend(ctx)
  end
  if nabbed and h.level > 0 then
    ctx.save.heat.busted = (ctx.save.heat.busted or 0) + 1
    wantedLib.set(h, 0)
    cops:release()
    blocksLib.mend(ctx)
    ctx.bus:emit("player_down", { kind = "nabbed" })
  end
  if h.level ~= before then
    local s = ctx.save.heat
    if h.level > (s.maxLevel or 0) then s.maxLevel = h.level end
    ctx.bus:emit("heat_changed", { level = h.level, previous = before })
  end
end

return P
