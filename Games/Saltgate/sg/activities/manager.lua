-- activities/manager.lua
-- The side activities as one thing the game talks to: it holds the layout and the save section, owns the places you
-- can use (race starts, taxi ranks, depots, shops, garages, properties), runs the one activity that is active, and
-- answers the HUD (what to show, what to prompt) and the 100% tracker (how many of each are done).
--
--   local m = manager.new(ctx, { layout = table, catalog = shops table, config = progress config })
--   m:update(dt, keys)      once a frame while playing: finds, jumps, rent, the active activity, ENTER and X
--   m:prompt() -> { text, key } or nil      what ENTER would do here
--   m:hud() -> { title, line, sub, centre, centreColour, urgent } or nil      the active activity
--   m:markers() -> world markers      m:mapMarkers() -> { x, z, icon, colour, label }
--   m:counts(category) -> done, total
--   m.open = function(kind, place) end   set by the plugin: opens a shop, garage or property screen

local common = require("sg.activities.common")
local collectLib = require("sg.activities.collect")
local jumpsLib = require("sg.activities.jumps")
local raceLib = require("sg.activities.race")
local jobLib = require("sg.activities.job")
local services = require("sg.activities.services")
local wallet = require("sg.progress.wallet")
local util = require("sg.util")

local M = {}
local A = {}
A.__index = A

M.DAY_SECONDS = 1200 -- with no clock from the world, a game day is twenty minutes
M.PLACE_SHOW = 110

local MEDAL_RANK = { gold = 3, silver = 2, bronze = 1, none = 0 }

function M.new(ctx, opts)
  local layout = opts.layout or {}
  local save = ctx.save
  save.activities = common.ensure(save.activities or {})
  local self = setmetatable({
    ctx = ctx, layout = layout, catalog = opts.catalog, config = opts.config or {}, section = save.activities,
    active = nil, kind = nil, sinceClock = 0, lastHour = nil, seed = 1,
  }, A)
  self.collect = collectLib.new(ctx, layout, self.section)
  self.jumps = jumpsLib.new(ctx, layout, self.section)
  self.shops = services.shops(ctx, self.catalog, self.section)
  self.property = services.property(ctx, layout, self.section)
  self.garage = services.garage(ctx, self.catalog, self.property, self.section)
  self:buildPlaces()
  ctx.bus:on("time_of_day", function(d) self:onTime(d.hour) end, "e_activities")
  ctx.bus:on("load", function(d)
    if d.data and d.data.activities then self:use(d.data.activities) end
  end, "e_activities")
  return self
end

--- Point everything at a (re)loaded save section.
function A:use(section)
  self.section = common.ensure(section)
  self.ctx.save.activities = self.section
  self.collect:use(self.section)
  self.jumps:use(self.section)
  self.shops:use(self.section)
  self.property:use(self.section)
  self.garage:use(self.section)
end

-- ---------------------------------------------------------------- places

function A:buildPlaces()
  local L = self.layout
  local places = {}
  local function add(p) places[#places + 1] = p end
  for _, r in ipairs(L.races or {}) do
    add({ kind = "race", id = r.id, def = r, name = r.name, x = r.pts[1], z = r.pts[3], y = r.pts[2], radius = 12, icon = "R", colour = "orange" })
  end
  for _, t in ipairs(L.taxi or {}) do add({ kind = "taxi", id = t.id, name = t.name, x = t.x, z = t.z, y = t.y, radius = 9, icon = "T", colour = "yellow" }) end
  for _, t in ipairs(L.depots or {}) do add({ kind = "depot", id = t.id, name = t.name, x = t.x, z = t.z, y = t.y, radius = 9, icon = "D", colour = "brown" }) end
  for _, s in ipairs(L.shops or {}) do
    add({ kind = "shop", shop = s.kind, id = s.id, name = s.name, x = s.x, z = s.z, y = s.y, h = s.h, radius = 7, icon = "$", colour = "magenta" })
  end
  for _, g in ipairs(L.garages or {}) do add({ kind = "garage", id = g.id, name = g.name, x = g.x, z = g.z, y = g.y, h = g.h, radius = 7, icon = "G", colour = "cyan" }) end
  for _, p in ipairs(L.properties or {}) do
    add({ kind = "property", id = p.id, def = p, name = p.name, x = p.x, z = p.z, y = p.y, h = p.h, radius = 7, icon = "H", colour = "green" })
  end
  self.places = places
end

local function bestOf(self, id)
  local s = self.section.races[id]
  return s and s.best
end

--- What ENTER does at a place, as words ("Race Harbor Dash  best 1:02.3").
function A:describe(p)
  if p.kind == "race" then
    local best = bestOf(self, p.id)
    return "Race " .. p.name .. (best and ("  best " .. raceLib.clock(best)) or ""), "ENTER"
  elseif p.kind == "taxi" then
    return "Start a taxi shift at " .. p.name, "ENTER"
  elseif p.kind == "depot" then
    return "Take a parcel run from " .. p.name, "ENTER"
  elseif p.kind == "shop" then
    local what = { respray = "respray", tune = "tune your car", clothes = "buy clothes" }
    return p.name .. ": " .. (what[p.shop] or "shop"), "ENTER"
  elseif p.kind == "garage" then
    return p.name .. ": your cars", "ENTER"
  elseif p.kind == "property" then
    if self.property:owned(p.id) then return p.name .. ": yours, " .. util.money(p.def.income) .. " a day", nil end
    return p.name .. ": buy for " .. util.money(p.def.price), "ENTER"
  end
  return p.name, "ENTER"
end

--- The place you could use right now: the nearest within its radius.
function A:placeHere()
  local x, _, z = common.where(self.ctx)
  local best, bd = nil, math.huge
  for _, p in ipairs(self.places) do
    local d = common.dist(x, z, p.x, p.z)
    if d <= p.radius and d < bd then best, bd = p, d end
  end
  return best
end

function A:prompt()
  if self.active then return nil end
  local p = self.here
  if not p then return nil end
  local text, key = self:describe(p)
  if not key then return { text = text } end
  return { text = text, key = key }
end

--- Use a place (what ENTER does).
function A:use_(p)
  local ctx = self.ctx
  local car = ctx.player.car
  -- a race or a shift in the middle of a story job would fail the job behind your back: one thing at a time
  local host = ctx.story and ctx.story.host
  if (p.kind == "race" or p.kind == "taxi" or p.kind == "depot") and host and host.state == "running" then
    self:say("Finish the job first.")
    return
  end
  if p.kind == "race" then
    if not car then self:say("Drive a car to the line.") return end
    self:startRace(p.def)
  elseif p.kind == "taxi" or p.kind == "depot" then
    if not car or (car.spec and car.spec.police) then self:say("You need a car for that.") return end
    self:startJob(p.kind == "taxi" and "taxi" or "delivery", p)
  elseif self.open then
    self.open(p.kind, p)
  end
end

function A:say(text)
  if self.ctx.hud then self.ctx.hud.toast(text, "lightGray", 2.5) end
end

-- ---------------------------------------------------------------- activities

function A:startRace(def)
  local store = self.section.races[def.id]
  local car = self.ctx.player.car
  self.active = raceLib.new(self.ctx, def, store and store.best, store and store.ghost)
  self.activeDef = def
  self.carSpec = car and car.spec
  self.kind = "race"
  self.ctx.bus:emit("checkpoint", { id = "race:" .. def.id, name = def.name })
end

function A:startJob(kind, place)
  self.seed = self.seed + 1
  local x, _, z = common.where(self.ctx)
  self.active = jobLib.new(self.ctx, kind, self.layout.spots or {}, { x = x, z = z }, self.seed * 977 + math.floor(x + z), self.section.jobs)
  self.activeDef = place
  self.kind = kind
  if self.active:status() == "failed" then
    self:say(self.active.reason or "Nothing to do.")
    self.active, self.kind = nil, nil
  end
end

function A:cancel(reason)
  if not self.active then return end
  local kind = self.kind
  if kind == "taxi" or kind == "delivery" then
    local j = self.active
    if self.ctx.hud then
      self.ctx.hud.toast(kind == "taxi" and "Shift over" or "Run over", "lightGray", 3,
        j.count .. (kind == "taxi" and " fares" or " drops") .. ", " .. util.money(j.earned))
    end
  elseif self.ctx.hud then
    self.ctx.hud.toast(reason or "Race abandoned", "lightGray", 2.5)
  end
  self.active, self.kind, self.activeDef = nil, nil, nil
end

function A:finishRace(r)
  local def = self.activeDef
  local res = r.result
  local store = self.section.races[def.id]
  if not store then
    store = { medal = "none" }
    self.section.races[def.id] = store
  end
  if res.new then
    store.best = res.time
    store.ghost = r:ghostData()
  end
  if (MEDAL_RANK[res.medal] or 0) > (MEDAL_RANK[store.medal] or 0) then store.medal = res.medal end
  local stats = self.ctx.progress and self.ctx.progress.stats
  if stats then
    stats:add("racesRun", 1)
    if res.medal == "gold" then stats:add("racesGold", 1) end
  end
  -- each medal pays once at its best: the difference when you improve, the full prize the first time
  local pay = def.pay[res.medal] or 0
  local paid = store.paid or 0
  local due = math.max(0, pay - paid)
  if due > 0 then
    wallet.add(self.ctx, due, "race: " .. def.name)
    store.paid = pay
  end
  res.pay = due
  if self.ctx.hud then
    local medal = res.medal == "none" and "Finished" or (res.medal:upper() .. "!")
    self.ctx.hud.toast(medal .. "  " .. raceLib.clock(res.time), res.medal == "gold" and "yellow" or "white", 6,
      (res.new and "new best  " or "") .. (due > 0 and ("+$" .. due) or ""))
  end
  self.ctx.bus:emit("checkpoint", { id = "race_done:" .. def.id, name = def.name })
end

-- ---------------------------------------------------------------- time

function A:onTime(hour)
  self.worldClock = true
  if self.lastHour then
    local d = hour - self.lastHour
    if d < -12 then d = d + 24 elseif d < 0 then d = 0 end
    if d > 0 then self.property:advance(d) end
  end
  self.lastHour = hour
  self.sinceClock = 0
end

-- ---------------------------------------------------------------- the frame

function A:update(dt, keys)
  local ctx = self.ctx
  self.collect:update(dt)
  self.jumps:update(dt)
  -- no clock from the world, ever (it sends time_of_day): a day passes in M.DAY_SECONDS
  self.sinceClock = self.sinceClock + dt
  if not self.worldClock and self.sinceClock > 5 then self.property:advance(dt * 24 / M.DAY_SECONDS) end
  local active = self.active
  if active then
    local status = active:update(dt)
    if keys and keys:pressed("abandon") then
      self:cancel()
      return
    end
    if status == "done" or status == "failed" then
      if self.kind == "race" then
        if status == "done" then
          self:finishRace(active)
        elseif ctx.hud then
          ctx.hud.toast(active.reason or "Race over", "red", 4)
        end
      else
        if ctx.hud then
          ctx.hud.toast(self.kind == "taxi" and "Shift over" or (status == "done" and "Run complete" or "Run failed"),
            status == "done" and "lime" or "red", 4, (active.reason or "") .. (active.count > 0 and (" " .. active.count .. " done, " .. util.money(active.earned)) or ""))
        end
      end
      self.active, self.kind, self.activeDef = nil, nil, nil
    end
    self.here = nil
    return
  end
  self.here = self:placeHere()
  if self.here and keys and keys:pressed("select") then
    local text, key = self:describe(self.here)
    local _ = text
    if key then self:use_(self.here) end
  end
end

-- ---------------------------------------------------------------- what the HUD and the map ask

function A:hud()
  if not self.active then return nil end
  local h = self.active:hud()
  h.kind = self.kind
  return h
end

function A:markers()
  local x, _, z = common.where(self.ctx)
  local out = {}
  if self.active then
    if self.kind == "race" then
      self.active:markers(out, self.carSpec)
    else
      self.active:markers(out)
    end
    return out
  end
  self.collect:markers(x, z, out)
  self.jumps:markers(x, z, out)
  for _, h in ipairs(common.near(self.places, x, z, M.PLACE_SHOW)) do
    local p = h.item
    local colour = p.kind == "race" and "orange" or (p.kind == "property" and self.property:owned(p.id) and "lime") or (p.kind == "property" and "white") or p.colour
    out[#out + 1] = { kind = "beacon", x = p.x, y = p.y or 0, z = p.z, colour = colour, d2 = h.d2 }
  end
  table.sort(out, function(a, b) return (a.d2 or 0) < (b.d2 or 0) end)
  return out
end

--- Icons for the big map.
function A:mapMarkers()
  local out = {}
  for _, p in ipairs(self.places) do
    local colour = p.colour
    if p.kind == "property" then colour = self.property:owned(p.id) and "lime" or "white" end
    out[#out + 1] = { x = p.x, z = p.z, icon = p.icon, colour = colour, label = p.name }
  end
  if self.active and self.active.stop then
    local s = self.active.stop
    out[#out + 1] = { x = s.x, z = s.z, icon = "*", colour = "yellow", label = s.name }
  end
  return out
end

--- Where the objective arrow should point while something is active: x, z, label.
function A:target()
  local a = self.active
  if not a then return nil end
  if self.kind == "race" then
    local g = a.route.gates[math.min(a.next, #a.route.gates)]
    if g then return g.x, g.z, "gate" end
  elseif a.stop then
    return a.stop.x, a.stop.z, a.stop.name
  end
  return nil
end

-- ---------------------------------------------------------------- the 100% tracker

function A:counts(category)
  if category == "totems" then return self.collect:counts("totem") end
  if category == "postcards" then return self.collect:counts("postcard") end
  if category == "jumps" then return self.jumps:counts() end
  if category == "races" then
    local done, total = 0, #(self.layout.races or {})
    for _, r in ipairs(self.layout.races or {}) do
      if self.section.races[r.id] and self.section.races[r.id].best then done = done + 1 end
    end
    return done, total
  end
  if category == "taxi" then return math.min(self.section.jobs.fares, self.config.taxiTarget or 20), self.config.taxiTarget or 20 end
  if category == "delivery" then return math.min(self.section.jobs.deliveries, self.config.deliveryTarget or 20), self.config.deliveryTarget or 20 end
  if category == "property" then return self.property:counts() end
  if category == "garage" then
    local goals = self.config.garageGoals or {}
    local done = 0
    for _, g in ipairs(goals) do if self.section.goals[g] then done = done + 1 end end
    return done, #goals
  end
  return 0, 0
end

return M
