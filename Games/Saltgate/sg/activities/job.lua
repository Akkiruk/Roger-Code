-- activities/job.lua
-- Taxi shifts and parcel runs. A taxi shift is fare after fare: drive to the person waiting, stop beside them, then to
-- where they are going before the meter's time runs out; each fare pays by distance and time left, less for a battered car,
-- and fares in a row earn a streak bonus. A parcel run is three drops from a depot, each against the clock.
--
--   local j = job.new(ctx, "taxi" | "delivery", spots, origin { x, z }, seed)
--   j:update(dt) -> "run" | "done" | "failed"
--   j.earned  j.count  j.reason  j:hud()  j:markers()
-- Payments go through the wallet; the stats (fares, deliveries) and the job counters in the save are kept here.

local common = require("sg.activities.common")
local wallet = require("sg.progress.wallet")
local util = require("sg.util")

local M = {}
local J = {}
J.__index = J

M.ARRIVE = 7 -- how close, in units
M.ARRIVE_SPEED = 7 -- how slowly (units a second)
M.LEFT_CAR = 6 -- seconds out of the car before the shift ends
M.DROPS = 3

--- Pick a spot between minD and maxD of (x, z), not avoid; the nearest to the middle of that range if none fits.
function M.pick(spots, x, z, minD, maxD, rng, avoid)
  local fit, any = {}, {}
  for _, s in ipairs(spots) do
    if not avoid or s.id ~= avoid then
      local d = common.dist(x, z, s.x, s.z)
      any[#any + 1] = { s = s, d = d }
      if d >= minD and d <= maxD then fit[#fit + 1] = s end
    end
  end
  if #fit > 0 then return fit[rng(#fit)] end
  if #any == 0 then return nil end
  local mid = (minD + maxD) / 2
  table.sort(any, function(a, b) return math.abs(a.d - mid) < math.abs(b.d - mid) end)
  return any[1].s
end

--- What a fare pays: by distance and the time left, less for a damaged car, more for a streak. Whole dollars.
function M.farePay(dist, timeLeft, damage, streak)
  local base = 40 + dist * 0.5 + math.max(0, timeLeft) * 1.5
  local pay = base * (1 - util.clamp(damage * 1.5, 0, 0.5)) * (1 + math.min(streak, 5) * 0.1)
  return math.floor(pay + 0.5)
end

function M.dropPay(dist, timeLeft, damage)
  local base = 70 + dist * 0.6 + math.max(0, timeLeft) * 1.2
  return math.floor(base * (1 - util.clamp(damage * 1.5, 0, 0.5)) + 0.5)
end

function M.new(ctx, kind, spots, origin, seed, section)
  local self = setmetatable({
    ctx = ctx, kind = kind, spots = spots, rng = util.rng(seed or 1), section = section,
    earned = 0, count = 0, streak = 0, out = 0, stage = nil, stop = nil, t = 0, limit = nil, reason = nil,
    healthAtStart = nil, late = false, drops = nil, from = origin,
  }, J)
  if kind == "taxi" then
    self:nextFare(origin.x, origin.z)
  else
    self.drops = {}
    local x, z = origin.x, origin.z
    local last
    for _ = 1, M.DROPS do
      local s = M.pick(spots, x, z, 90, 300, self.rng, last and last.id)
      if s then
        self.drops[#self.drops + 1] = s
        x, z, last = s.x, s.z, s
      end
    end
    self.total = #self.drops
    self:nextDrop(origin.x, origin.z)
  end
  return self
end

local function car(self) return self.ctx.player.car end

function J:nextFare(x, z)
  local pick = M.pick(self.spots, x, z, 70, 260, self.rng, self.stop and self.stop.id)
  if not pick then self.phase = "failed" self.reason = "No fares tonight." return end
  self.stage = "pickup"
  self.stop = pick
  self.limit = nil
  self.t = 0
end

function J:nextDrop(x, z)
  local s = table.remove(self.drops, 1)
  if not s then self.phase = "done" return end
  self.stage = "drop"
  self.stop = s
  self.dist0 = common.dist(x, z, s.x, s.z)
  self.limit = 25 + self.dist0 / 9
  self.t = 0
  local c = car(self)
  self.healthAtStart = c and c.health or 1
end

function J:status() return self.phase or "run" end

local function damageOf(self)
  local c = car(self)
  if not c or not self.healthAtStart or not c.spec then return 0 end
  return util.clamp((self.healthAtStart - c.health) / c.spec.health, 0, 1)
end

function J:arrive(x, z)
  local ctx = self.ctx
  local stats = ctx.progress and ctx.progress.stats
  if self.kind == "taxi" then
    if self.stage == "pickup" then
      local drop = M.pick(self.spots, self.stop.x, self.stop.z, 150, 400, self.rng, self.stop.id)
      if not drop then self.phase = "done" return end
      self.fromStop = self.stop
      self.stop = drop
      self.stage = "ride"
      self.dist0 = common.dist(self.fromStop.x, self.fromStop.z, drop.x, drop.z)
      self.limit = 20 + self.dist0 / 11
      self.t = 0
      local c = car(self)
      self.healthAtStart = c and c.health or 1
      if ctx.hud then ctx.hud.toast("Passenger aboard", "yellow", 2.5, "to " .. drop.name) end
    else
      local pay = M.farePay(self.dist0, self.limit - self.t, damageOf(self), self.streak)
      wallet.add(ctx, pay, "taxi fare")
      self.earned = self.earned + pay
      self.count = self.count + 1
      self.streak = self.streak + 1
      self.section.fares = self.section.fares + 1
      if stats then stats:add("fares", 1) end
      if ctx.hud then ctx.hud.toast("FARE  +$" .. pay, "lime", 3, self.streak > 1 and ("streak x" .. self.streak) or nil) end
      self:nextFare(x, z)
    end
  else
    local pay = M.dropPay(self.dist0, self.limit - self.t, damageOf(self))
    wallet.add(ctx, pay, "delivery")
    self.earned = self.earned + pay
    self.count = self.count + 1
    self.section.deliveries = self.section.deliveries + 1
    if stats then stats:add("deliveries", 1) end
    if ctx.hud then ctx.hud.toast("DELIVERED  +$" .. pay, "lime", 3, self.count .. "/" .. self.total) end
    self:nextDrop(x, z)
    if self.phase == "done" then
      local bonus = self.late and 0 or 150
      if bonus > 0 then
        wallet.add(ctx, bonus, "delivery bonus")
        self.earned = self.earned + bonus
        if ctx.hud then ctx.hud.toast("ALL DROPS ON TIME  +$" .. bonus, "yellow", 3.5) end
      end
    end
  end
end

function J:update(dt)
  if self.phase then return self.phase end
  local x, _, z, c = common.where(self.ctx)
  if not c then
    self.out = self.out + dt
    if self.out > M.LEFT_CAR then
      self.reason = "You left the car."
      self.phase = self.count > 0 and "done" or "failed"
    end
    return self.phase or "run"
  end
  self.out = 0
  if c.wrecked then
    self.reason = "Your car is wrecked."
    self.phase = "failed"
    return self.phase
  end
  self.t = self.t + dt
  if self.limit and self.t > self.limit then
    if self.kind == "taxi" then
      self.reason = "The passenger got out."
      self.phase = self.count > 0 and "done" or "failed"
      return self.phase
    end
    self.late = true -- a late parcel still counts, just with no time bonus and no all-on-time pay
    self.limit = self.t + 9999
  end
  local s = self.stop
  if s and common.dist(x, z, s.x, s.z) <= M.ARRIVE and math.abs(c.v or 0) <= M.ARRIVE_SPEED then
    self:arrive(x, z)
  end
  return self.phase or "run"
end

function J:hud()
  local s = self.stop
  local x, _, z = common.where(self.ctx)
  local d = s and common.dist(x, z, s.x, s.z) or 0
  local title, line
  if self.kind == "taxi" then
    title = "TAXI  fare " .. (self.count + 1) .. "  $" .. self.earned
    if self.stage == "pickup" then
      line = "Pick up at " .. s.name .. "  " .. math.floor(d + 0.5) .. "m"
    else
      line = "Drop at " .. s.name .. "  " .. math.floor(d + 0.5) .. "m  " .. M.timeLeft(self.limit - self.t)
    end
  else
    title = "PARCELS  " .. self.count .. "/" .. (self.total or 0) .. "  $" .. self.earned
    line = "Deliver to " .. (s and s.name or "") .. "  " .. math.floor(d + 0.5) .. "m"
    if self.limit and not self.late then line = line .. "  " .. M.timeLeft(self.limit - self.t) end
  end
  return { title = title, line = line, urgent = self.limit and (self.limit - self.t) < 10 and self.stage ~= "pickup" }
end

function M.timeLeft(sec)
  sec = math.max(0, math.floor(sec))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

function J:markers(out)
  out = out or {}
  local s = self.stop
  if s then
    out[#out + 1] = { kind = "beacon", x = s.x, y = s.y, z = s.z, colour = self.stage == "pickup" and "yellow" or "lime" }
  end
  return out
end

--- Where the objective arrow should point.
function J:target()
  return self.stop
end

return M
