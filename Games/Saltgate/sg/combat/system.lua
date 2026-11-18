-- combat/system.lua
-- The combat for the player and for everyone who shoots at the player (stream C's gangs and Patrol call shoot()).
-- Cartoony: shots are streaks and pops, a person hit enough is knocked down and gets back up, nobody is ever
-- removed. Keyboard aiming is a lock-on: the best target in front is locked, K cycles, J fires, L changes weapon.
-- Pure apart from the ctx it is given: bus, world (entities), stream (collide), cars, player, save.
--
--   local cb = system.new(ctx, { seed = 1 })
--   cb:update(dt, { fire = bool, target = bool, weapon = bool, slot = n or nil })   once a frame, from the player's keys
--   cb:shoot(shooter, weaponId, angle, opts) -> { shots, hits, downed }       any shooter: { x, z, y, h, car, id }
--   cb:give(weaponId, rounds)   cb:select(id)   cb:cycle()   cb:ammo(id) -> mag, reserve
--   cb:hurtPlayer(amount, by)   cb:playerDown() -> bool   cb:hp() -> 0-100
--   cb:spawnGoon(x, z, opts)    cb:dropAmmo(x, z, weaponId, n)    cb:snapshot() / cb:restore(data)
--   cb.lock, cb.fx (the effects to draw), cb.msg (a line for the HUD), cb.current (the weapon id)

local util = require("sg.util")
local weapons = require("sg.combat.weapons")
local knock = require("sg.combat.knock")
local aim = require("sg.combat.aim")
local shoot = require("sg.combat.shoot")
local vehicle = require("sg.vehicle")

local M = {}
local S = {}
S.__index = S

local cos, sin, abs, min, max, sqrt = math.cos, math.sin, math.abs, math.min, math.max, math.sqrt
local atan2 = math.atan2 or math.atan

M.PERSON = { ped = true, cop = true, gang = true, goon = true, person = true, thug = true }
M.ENEMY_SCALE = 0.5 -- what a shot at the player does, against the weapon's knock points
M.REGEN_AFTER = 8
M.REGEN = 3 -- hit points a second
M.PLAYER_DOWN = 3
M.MAX_FX = 90
M.PICKUP_REACH = 2.1

function M.new(ctx, opts)
  opts = opts or {}
  local self = setmetatable({
    ctx = ctx, rng = util.rng(opts.seed or 11), owned = weapons.starter(), current = "popper",
    cool = 0, reloadT = 0, reloading = nil, lock = nil, lockT = 0, manualT = 0, ranked = {},
    fx = {}, active = {}, pdown = 0, lastHurt = 99, flash = 0, msg = nil, msgT = 0, wheelT = 0,
    gunfireT = 0, hpValue = 100, clock = 0, wasInCar = false, beforeCar = nil,
  }, S)
  return self
end

-- ---------------------------------------------------------------- the player's hit points

function S:hp()
  local sp = self.ctx.save and self.ctx.save.player
  if sp then return sp.health or 100 end
  return self.hpValue
end

function S:setHp(v)
  v = util.clamp(v, 0, 100)
  local sp = self.ctx.save and self.ctx.save.player
  if sp then sp.health = v else self.hpValue = v end
end

function S:playerDown() return self.pdown > 0 end

function S:say(text, secs)
  self.msg, self.msgT = text, secs or 2
end

-- ---------------------------------------------------------------- weapons and ammo

function S:ammo(id)
  local st = self.owned[id]
  if not st then return 0, 0 end
  return st.mag, st.reserve
end

function S:weapon() return weapons.get(self.current) end

--- Give a weapon (with ammo) or ammo for one already carried. Returns what was added.
function S:give(id, rounds)
  local w = weapons.get(id)
  if not w then return 0 end
  local st = self.owned[id]
  if not st then
    st = { mag = 0, reserve = 0 }
    self.owned[id] = st
    if w.kind == "gun" then
      st.mag = min(w.mag, rounds or w.crate)
      rounds = max(0, (rounds or w.crate) - st.mag)
    end
  end
  if w.kind ~= "gun" then return 0 end
  local before = st.reserve
  st.reserve = min(w.reserve, st.reserve + (rounds or w.crate))
  return st.reserve - before
end

function S:select(id)
  if not self.owned[id] or id == self.current then return false end
  local w = weapons.get(id)
  if self.ctx.player.car and not w.driveby then
    self:say(w.name .. " does not fit in a car", 1.5)
    return false
  end
  self.current = id
  self.reloadT, self.reloading = 0, nil
  self.cool = 0.15
  self.wheelT = 2
  return true
end

--- The next weapon on the wheel that is carried (and usable where you are), wrapping.
function S:cycle()
  local cur = weapons.get(self.current).slot
  local n = #weapons.LIST
  for i = 1, n do
    local w = weapons.LIST[(cur - 1 + i) % n + 1]
    if self.owned[w.id] and w.id ~= self.current and (w.kind ~= "melee" or not self.ctx.player.car)
      and (not self.ctx.player.car or w.driveby) then
      return self:select(w.id)
    end
  end
  self.wheelT = 2
  return false
end

local function startReload(self, w, st)
  if st.reserve > 0 and st.mag < w.mag and self.reloadT <= 0 then
    self.reloadT, self.reloading = w.reload, w.id
  end
end

-- ---------------------------------------------------------------- effects

local function addFx(self, f)
  local fx = self.fx
  if #fx >= M.MAX_FX then table.remove(fx, 1) end
  f.t = 0
  fx[#fx + 1] = f
end

function S:puff(x, y, z, colour, ttl, r)
  addFx(self, { kind = "puff", x = x, y = y, z = z, c = colour or "white", ttl = ttl or 0.35, r = r or 1 })
end

function S:pop(x, y, z, text)
  addFx(self, { kind = "pop", x = x, y = y, z = z, text = text, ttl = 0.7 })
end

-- ---------------------------------------------------------------- who can be shot

function S:isTarget(e)
  if e == self.ctx.player or e.removed or e.shootable == false then return false end
  if e.tags and e.tags.friend then return false end
  if e.shootable == true then return true end
  if e.tags and (e.tags.person or e.tags.shootable) then return true end
  return M.PERSON[e.kind] == true
end

--- People within r of (x, z), nearest first. withDown also lists those on the ground.
function S:targets(x, z, r, withDown)
  local out = {}
  for _, e in ipairs(self.ctx.world:near(x, z, r)) do
    if self:isTarget(e) and (withDown or not e.knocked) then out[#out + 1] = e end
  end
  return out
end

local function touch(self, e) self.active[e] = true end

-- ---------------------------------------------------------------- one shot

--- Where a shot leaves a shooter (a car's window on the target's side, a person's hand).
local function muzzle(shooter, angle)
  local car = shooter.car
  if car then
    local right = sin(angle - car.h) >= 0 and 1 or -1
    local rx, rz = -sin(car.h), cos(car.h)
    local w = car.spec.width / 2
    local up = car.spec.class == "bike" and 1.5 or 1.0
    return car.x + rx * right * w, (car.y or 0) + up, car.z + rz * right * w
  end
  return shooter.x + cos(angle) * 0.5, (shooter.y or 0) + 1.2, shooter.z + sin(angle) * 0.5
end

local function popWords(self, w)
  return w.words[self.rng() < 0.5 and 1 or (self.rng() < 0.5 and 2 or 3)] or "POP!"
end

local function playerFired(self, shooter) return shooter == self.ctx.player or shooter.isPlayer end

--- What one pellet or swing did.
local function applyHit(self, shooter, w, hit, scale)
  local fromPlayer = playerFired(self, shooter)
  local dmg = w.dmg * (scale or 1)
  if hit.kind == "target" then
    local e = hit.e
    if e.isPlayerBody then
      self:hurtPlayer(dmg * M.ENEMY_SCALE, shooter)
      self:puff(hit.x, hit.y, hit.z, "yellow", 0.3, 1)
      return "hurt"
    end
    local res = knock.hit(e, dmg)
    touch(self, e)
    self:puff(hit.x, hit.y, hit.z, "white", 0.35, 1.2)
    if res == "down" then
      self:pop(hit.x, hit.y + 0.6, hit.z, popWords(self, w))
      -- the shove: knocked a little away from the shooter, only if the way is clear
      local ang = atan2(e.z - shooter.z, e.x - shooter.x)
      local nx, nz = e.x + cos(ang) * 0.7, e.z + sin(ang) * 0.7
      if not self.ctx.stream or not select(3, self.ctx.stream:collide(nx, nz, 0.4, e.y or 0)) then
        if self.ctx.world.move then self.ctx.world:move(e, nx, nz) else e.x, e.z = nx, nz end
      end
      if fromPlayer then
        local cop = e.kind == "cop" or (e.tags and e.tags.cop)
        local hostile = e.hostile or (e.tags and e.tags.hostile)
        if cop then self.ctx.bus:emit("crime", { kind = "cop_assault", level = 2 })
        elseif not hostile then self.ctx.bus:emit("crime", { kind = "assault", level = 1 }) end
      end
      if e.onKnock then e.onKnock(e, shooter) end
    end
    return res
  elseif hit.kind == "car" then
    local car = hit.e
    if not car.wrecked then vehicle.damage(car, dmg * 0.3) end
    self:puff(hit.x, hit.y, hit.z, "lightGray", 0.3, 1)
    if car == self.ctx.player.car and not fromPlayer then self:hurtPlayer(dmg * 0.2, shooter) end
    return "car"
  elseif hit.kind == "wall" then
    self:puff(hit.x, hit.y, hit.z, "lightGray", 0.25, 0.8)
    return "wall"
  end
  return "miss"
end

--- A shooter fires weapon id along angle (radians). shooter: { x, z, y, h, car, id }. opts: noAmmo (default true for
-- anyone but the player), spread (override), assist, scale (knock points scaled), onlyPlayer (a gang's shot).
function S:shoot(shooter, id, angle, opts)
  opts = opts or {}
  local w = weapons.get(id)
  local out = { shots = 0, hits = 0, downed = 0 }
  if not w then return out end
  local ox, oy, oz = muzzle(shooter, angle)
  local fromPlayer = playerFired(self, shooter)
  local reach = w.range + 2
  local list = self:targets(ox, oz, reach)
  local player = self.ctx.player
  if not fromPlayer and not player.car and not self:playerDown() then
    -- everyone else can hit the player on foot
    player.isPlayerBody = true
    player.radius = player.radius or 0.5
    list[#list + 1] = player
  end
  local cars = {}
  for _, c in ipairs(self.ctx.cars or {}) do
    if abs(c.x - ox) < reach + 4 and abs(c.z - oz) < reach + 4 then cars[#cars + 1] = c end
  end
  local copts = { targets = list, cars = cars, stream = self.ctx.stream, ignore = shooter, ignoreCar = shooter.car,
    assist = opts.assist or (fromPlayer and 0.35 or 0), feet = (shooter.y or 0) }
  local spread = opts.spread or w.spread
  for _ = 1, w.pellets do
    local ang = angle + (self.rng() - 0.5) * 2 * spread
    local hit = shoot.cast(copts, ox, oy, oz, ang, w.range)
    out.shots = out.shots + 1
    local res = applyHit(self, shooter, w, hit, opts.scale)
    if res == "hurt" or res == "down" then out.hits = out.hits + 1 end
    if res == "down" then out.downed = out.downed + 1 end
    addFx(self, { kind = "tracer", x0 = ox, y0 = oy, z0 = oz, x1 = hit.x, y1 = hit.y or oy, z1 = hit.z, c = w.tracer, ttl = 0.12 })
  end
  addFx(self, { kind = "muzzle", x = ox, y = oy, z = oz, ttl = 0.07 })
  return out
end

--- A melee swing at the nearest person in front of the shooter (within the weapon's reach and half a turn).
local function swing(self, shooter, w, angle)
  local ox, oz = shooter.x, shooter.z
  local best, bd = nil, w.range
  for _, e in ipairs(self:targets(ox, oz, w.range + 0.6)) do
    local d = sqrt((e.x - ox) ^ 2 + (e.z - oz) ^ 2) - (e.radius or 0.5)
    local a = abs(util.wrap(atan2(e.z - oz, e.x - ox) - angle))
    if d <= bd and a < 1.0 then best, bd = e, d end
  end
  addFx(self, { kind = "swing", x = ox + cos(angle) * 1.0, y = (shooter.y or 0) + 1.1, z = oz + sin(angle) * 1.0, ttl = 0.16 })
  if best then
    return applyHit(self, shooter, w, { kind = "target", e = best, x = best.x, z = best.z, y = (best.y or 0) + 1.2 }, 1)
  end
  return "miss"
end

-- ---------------------------------------------------------------- the player

function S:hurtPlayer(amount, by)
  if self.pdown > 0 or amount <= 0 then return end
  self.lastHurt = 0
  self.flash = 0.25
  self:setHp(self:hp() - amount)
  self.ctx.bus:emit("player_hurt", { amount = amount, by = by })
  if self:hp() <= 0 then self:knockPlayer("ko") end
end

function S:knockPlayer(kind)
  if self.pdown > 0 then return end
  self.pdown = M.PLAYER_DOWN
  self:setHp(0)
  self.ctx.player.knocked = true
  self.lock = nil
  self:say("Knocked down! Back up in a moment", M.PLAYER_DOWN)
  self.ctx.bus:emit("player_down", { kind = kind or "ko" })
end

local function playerShooter(ctx)
  local p = ctx.player
  p.isPlayer = true
  return p.car and { x = p.car.x, z = p.car.z, y = p.car.y, h = p.car.h, car = p.car, isPlayer = true, id = "player" }
    or p
end

--- The point the player aims from and the way they face.
local function aimOrigin(ctx)
  local p = ctx.player
  if p.car then return p.car.x, p.car.z, p.car.h end
  return p.x, p.z, p.h
end

function S:updateLock(dt, force)
  self.lockT = self.lockT - dt
  if self.manualT > 0 then self.manualT = self.manualT - dt end
  if not force and self.lockT > 0 then return end
  self.lockT = 0.2
  local ctx = self.ctx
  local x, z, h = aimOrigin(ctx)
  local w = self:weapon()
  local range = (w.kind == "melee" and 6 or w.range) * 1.1
  local cone = ctx.player.car and aim.CAR_CONE or aim.FOOT_CONE
  local ranked = aim.rank(self:targets(x, z, range), x, z, h, range, cone)
  self.ranked = ranked
  local cur = self.lock
  local valid = false
  if cur and not cur.knocked and not cur.removed then
    local d = sqrt((cur.x - x) ^ 2 + (cur.z - z) ^ 2)
    valid = d <= range * 1.25 and abs(util.wrap(atan2(cur.z - z, cur.x - x) - h)) <= cone * 1.25
  end
  if valid then return end
  self.lock = ranked[1] and ranked[1].e or nil
end

function S:cycleTarget()
  self:updateLock(0, true)
  local nxt = aim.cycle(self.ranked, self.lock)
  if nxt then
    self.lock, self.manualT = nxt, 5
  else
    self.lock = nil
  end
end

local function pickupsNear(self, dt)
  local ctx = self.ctx
  local px, pz = aimOrigin(ctx)
  for _, e in ipairs(ctx.world:each("pickup")) do
    if e.hiddenT then
      e.hiddenT = e.hiddenT - dt
      if e.hiddenT <= 0 then e.hiddenT = nil end
    elseif e.pk and (e.x - px) ^ 2 + (e.z - pz) ^ 2 <= M.PICKUP_REACH ^ 2 then
      local pk = e.pk
      local took = false
      if pk.type == "ammo" or pk.type == "gun" then
        local w = weapons.get(pk.weapon)
        local had = self.owned[pk.weapon] ~= nil
        local added = 0
        if pk.type == "gun" or had then added = self:give(pk.weapon, pk.n or (w and w.crate)) end
        took = added > 0 or (pk.type == "gun" and not had)
        if took then
          if pk.type == "gun" and not had then self:say("Got the " .. w.name .. "!", 2.2) self.wheelT = 2
          else self:say("+" .. added .. " " .. w.short, 1.6) end
        end
      elseif pk.type == "health" then
        if self:hp() < 100 then
          self:setHp(min(100, self:hp() + (pk.n or 40)))
          took = true
          self:say("Patched up", 1.5)
        end
      end
      if took then
        ctx.bus:emit("pickup", { kind = pk.type, id = pk.weapon or pk.type, value = pk.n or 0 })
        if e.respawn then e.hiddenT = e.respawn else ctx.world:remove(e) end
      end
    end
  end
end

--- Drop an ammo crate (or a gun) on the ground.
function S:dropAmmo(x, z, weaponId, n, kind)
  local y = self.ctx.stream and self.ctx.stream:groundAt(x, z, nil) or 0
  return self.ctx.world:add({ kind = "pickup", x = x, y = y, z = z, tags = { pickup = true },
    pk = { type = kind or "ammo", weapon = weaponId, n = n }, radius = 0.6 })
end

--- A practice target (and a gang member for tests): a person with knock points, optionally shooting back.
function S:spawnGoon(x, z, opts)
  opts = opts or {}
  local y = self.ctx.stream and self.ctx.stream:groundAt(x, z, nil) or 0
  return self.ctx.world:add({ kind = "goon", x = x, y = y, z = z, h = opts.h or 0, radius = 0.55, health = 30, maxHealth = 30,
    tags = { person = true, hostile = opts.fights or nil }, shirt = opts.shirt or "purple", fights = opts.fights,
    weapon = opts.weapon or "popper", fireT = 1 + self.rng() * 2 })
end

--- Practice goons that fight back: they turn to face the player and shoot when in sight, with poor aim.
local function goons(self, dt)
  local ctx = self.ctx
  local p = ctx.player
  for _, e in ipairs(ctx.world:each("person")) do
    if e.kind == "goon" and not e.knocked and e.fights and not self:playerDown() then
      local dx, dz = p.x - e.x, p.z - e.z
      local d = sqrt(dx * dx + dz * dz)
      if d < 24 then
        e.h = atan2(dz, dx)
        e.fireT = (e.fireT or 2) - dt
        if e.fireT <= 0 then
          e.fireT = 1.4 + self.rng() * 1.8
          self:shoot(e, e.weapon or "popper", e.h, { spread = 0.1 })
        end
      end
    end
  end
end

--- Once a frame. input: fire (held), target, weapon (pressed), slot (a number key).
function S:update(dt, input)
  input = input or {}
  local ctx = self.ctx
  local p = ctx.player
  self.clock = self.clock + dt
  if self.msgT > 0 then
    self.msgT = self.msgT - dt
    if self.msgT <= 0 then self.msg = nil end
  end
  if self.wheelT > 0 then self.wheelT = self.wheelT - dt end
  if self.flash > 0 then self.flash = self.flash - dt end
  if self.gunfireT > 0 then self.gunfireT = self.gunfireT - dt end
  self.lastHurt = self.lastHurt + dt
  if self.cool > 0 then self.cool = self.cool - dt end
  self:ageFx(dt)

  -- knocked people stand up; flinch timers run out
  for e in pairs(self.active) do
    if e.removed then
      self.active[e] = nil
    else
      knock.update(e, dt)
      if not e.knocked and (e.hurtT or 0) <= 0 then self.active[e] = nil end
    end
  end

  -- the player on the ground, then back up
  if self.pdown > 0 then
    self.pdown = self.pdown - dt
    if self.pdown <= 0 then
      self.pdown = 0
      p.knocked = false
      self:setHp(60)
      self:say("Back on your feet", 1.5)
    end
  elseif self.lastHurt > M.REGEN_AFTER and self:hp() < 100 then
    self:setHp(self:hp() + M.REGEN * dt)
  end

  -- into a car: the best one-handed gun; out again: back to what was in hand
  local inCar = p.car ~= nil
  if inCar and not self.wasInCar then
    local w = self:weapon()
    if not w.driveby then
      self.beforeCar = self.current
      for _, id in ipairs({ "popper", "rattler", "scatter" }) do
        if self.owned[id] then self.current = id break end
      end
      self.wheelT = 2
    end
    self.lock = nil
  elseif not inCar and self.wasInCar then
    if self.beforeCar and self.owned[self.beforeCar] then self.current = self.beforeCar end
    self.beforeCar = nil
    self.lock = nil
  end
  self.wasInCar = inCar

  pickupsNear(self, dt)
  goons(self, dt)

  if self.reloadT > 0 then
    self.reloadT = self.reloadT - dt
    if self.reloadT <= 0 then
      self.reloadT = 0
      local w, st = weapons.get(self.reloading or self.current), self.owned[self.reloading or self.current]
      if w and st then
        local n = min(w.mag - st.mag, st.reserve)
        st.mag, st.reserve = st.mag + n, st.reserve - n
      end
      self.reloading = nil
    end
  end

  if self.pdown > 0 then return end

  if input.slot then
    local w = weapons.inSlot(input.slot)
    if w then
      if self.owned[w.id] then self:select(w.id) else self:say("No " .. w.name .. " yet", 1.2) end
      self.wheelT = 2
    end
  end
  if input.weapon then self:cycle() end
  self:updateLock(dt)
  if input.target then self:cycleTarget() end

  -- the trigger
  local w = self:weapon()
  if input.fire and self.cool <= 0 and self.reloadT <= 0 then
    local shooter = playerShooter(ctx)
    local x, z, h = aimOrigin(ctx)
    local lock = self.lock
    local angle = lock and atan2(lock.z - z, lock.x - x) or h
    if w.kind == "melee" then
      if inCar then
        self:say("No swinging from a car", 1.2)
        self.cool = 0.4
      else
        swing(self, shooter, w, angle)
        p.h = angle
        self.cool = 1 / w.rate
      end
    else
      local st = self.owned[w.id]
      if st and st.mag > 0 then
        self:shoot(shooter, w.id, angle, { assist = lock and 0.5 or 0.2 })
        if not inCar and lock then p.h = angle end
        st.mag = st.mag - 1
        self.cool = 1 / w.rate
        if self.gunfireT <= 0 then
          self.gunfireT = 4
          ctx.bus:emit("crime", { kind = "gunfire", level = 1 })
        end
        if st.mag == 0 then startReload(self, w, st) end
      elseif st and st.reserve > 0 then
        startReload(self, w, st)
      else
        self:say(w.name .. " is out of ammo", 1.5)
        self.cool = 0.5
        -- fall back to the best thing with ammo left
        for _, id in ipairs({ "popper", "rattler", "scatter", "longpop" }) do
          local o = self.owned[id]
          if o and (o.mag > 0 or o.reserve > 0) and (not inCar or weapons.get(id).driveby) then self:select(id) break end
        end
        if self.current == w.id then self:select(inCar and w.id or "fists") end
      end
    end
  end

end

--- Effects must age even if the player is down; called from update, but separated for tests of ageing alone.
function S:ageFx(dt)
  for i = #self.fx, 1, -1 do
    local f = self.fx[i]
    f.t = f.t + dt
    if f.t >= f.ttl then table.remove(self.fx, i) end
  end
end

-- ---------------------------------------------------------------- saving

function S:snapshot()
  local owned = {}
  for id, st in pairs(self.owned) do owned[id] = { mag = st.mag, reserve = st.reserve } end
  return { owned = owned, current = self.current }
end

function S:restore(data)
  if type(data) ~= "table" or type(data.owned) ~= "table" then return end
  local owned = weapons.starter()
  for id, st in pairs(data.owned) do
    local w = weapons.get(id)
    if w and type(st) == "table" then
      owned[id] = { mag = util.clamp(tonumber(st.mag) or 0, 0, w.mag), reserve = util.clamp(tonumber(st.reserve) or 0, 0, w.reserve) }
    end
  end
  self.owned = owned
  if owned[data.current] then self.current = data.current end
end

return M
