-- activities/jumps.lua
-- Stunt jumps: leave the ground near a marked launch point, heading its way, stay up and land on your wheels at least
-- its distance away. Each is paid the first time; the best distance is kept. Every jump (marked or not) is announced with
-- the "jump" event (id, distance, landed).
--
--   local j = jumps.new(ctx, layout, section)
--   j:update(dt)    watches the player's car: takeoff, flight, landing
--   j:counts() -> done, total       j:best(id)       j:markers(x, z)

local common = require("sg.activities.common")
local wallet = require("sg.progress.wallet")

local M = {}
local J = {}
J.__index = J

M.LAUNCH_REACH = 16 -- how close to the marker you take off
M.AIR_MIN = 0.45 -- seconds in the air before it counts as a jump
M.PAY = 200
M.SHOW = 90

function M.new(ctx, layout, section)
  return setmetatable({ ctx = ctx, section = section, list = layout.jumps or {}, flight = nil }, J)
end

function J:use(section) self.section = section end

function J:counts()
  local n = 0
  for _, it in ipairs(self.list) do
    if self.section.jumps[it.id] then n = n + 1 end
  end
  return n, #self.list
end

function J:best(id) return self.section.jumps[id] end

local function launchFor(self, car)
  local best, bd = nil, M.LAUNCH_REACH
  for _, j in ipairs(self.list) do
    local d = common.dist(car.x, car.z, j.x, j.z)
    if d < bd then
      -- heading roughly the way the jump faces
      local diff = math.abs((car.h - j.h + math.pi) % (2 * math.pi) - math.pi)
      if diff < 1.1 then best, bd = j, d end
    end
  end
  return best
end

function J:update(dt)
  local car = self.ctx.player.car
  if not car then
    self.flight = nil
    return
  end
  local f = self.flight
  if car.airborne and not f then
    self.flight = { x0 = car.x, z0 = car.z, t = 0, jump = launchFor(self, car) }
  elseif f then
    f.t = f.t + dt
    if not car.airborne then
      self.flight = nil
      if f.t >= M.AIR_MIN then
        local dist = common.dist(f.x0, f.z0, car.x, car.z)
        local clean = not car.wrecked and math.abs(car.roll or 0) < 1.0 and math.abs(car.pitch or 0) < 1.0
        local j = f.jump
        self.ctx.bus:emit("jump", { id = j and j.id or "free", distance = dist, landed = clean })
        if j and clean and dist >= j.min then
          local first = self.section.jumps[j.id] == nil
          if first or dist > self.section.jumps[j.id] then self.section.jumps[j.id] = dist end
          if first then
            local pay = M.PAY + math.floor(dist)
            wallet.add(self.ctx, pay, "stunt jump")
            if self.ctx.hud then
              local d, total = self:counts()
              self.ctx.hud.toast("STUNT JUMP  " .. math.floor(dist + 0.5) .. " m", "cyan", 4, "+$" .. pay .. "  " .. d .. "/" .. total)
            end
          elseif self.ctx.hud then
            self.ctx.hud.toast(math.floor(dist + 0.5) .. " m", "lightGray", 2.5, "best " .. math.floor(self.section.jumps[j.id] + 0.5) .. " m")
          end
        elseif self.ctx.hud and dist >= 8 then
          self.ctx.hud.toast(clean and "Nice air" or "Rough landing", "lightGray", 2)
        end
      end
    end
  end
end

function J:markers(x, z, out)
  out = out or {}
  for _, h in ipairs(common.near(self.list, x, z, M.SHOW)) do
    local j = h.item
    out[#out + 1] = { kind = "flag", x = j.x, y = j.y, z = j.z, h = j.h, d2 = h.d2 }
  end
  return out
end

return M
