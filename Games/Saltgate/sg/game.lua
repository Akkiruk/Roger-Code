-- game.lua
-- One game of Saltgate: you, the cars, the people, the Harbor Patrol, money and the story, moved forward by update().
-- Pure: no screen, no keyboard, no sound. Input comes in as a table, and what should be heard goes out in g.cues.
--
-- Input fields: throttle (-1..1, W/S), steer (-1..1, A/D; positive is right), handbrake (Space), sprint (Shift), and
-- edges (true for the one step they were pressed): enter (F), horn (H), advance (Enter).

local util = require("sg.util")
local city = require("sg.city")
local vehicle = require("sg.vehicle")
local heatlib = require("sg.heat")
local missions = require("sg.missions")
local ai = require("sg.ai")
local peds = require("sg.peds")

local M = {}
local G = {}
G.__index = G

local cos, sin, abs, floor = math.cos, math.sin, math.abs, math.floor

M.TRAFFIC = 11
M.PEDS = 14
M.TRAFFIC_RADIUS = 125
M.PED_RADIUS = 80
M.RESPRAY_COST = 150
M.WALK, M.RUN = 4.2, 7.5
M.PLAYER_RADIUS = 0.45
M.PARKED_MAX = 8
M.FOOT_TURN = 2.2 -- radians a second; the camera stays right behind, so A/D turn the view at this pace

--- A new game. opts: seed, save (a table from saveData), quiet (no ambient traffic/peds, for tests).
function M.new(opts)
  opts = opts or {}
  local g = setmetatable({}, G)
  g.seed = opts.seed or 1
  g.rng = util.rng(g.seed)
  g.city = city.new(1)
  g.t = 0
  g.cars, g.peds, g.cues, g.messages = {}, {}, {}, {}
  g.heat = heatlib.new()
  g.progress = { done = {}, finished = false }
  g.money = 0
  g.stats = { cars = 0, nabbed = 0, ko = 0, jobs = 0, chopped = 0 }
  g.quiet = opts.quiet
  g.saver = opts.saver
  local start = g.city.places.start
  g.player = { x = start.x, z = start.z, h = start.h or 0, v = 0, health = 100, car = nil }
  if opts.save then g:load(opts.save) end
  g.pickups = g:makePickups()
  g:parkedCars()
  -- first time: show how to walk, get in and drive (opts.tutorial), unless a save says it was done
  if opts.tutorial and not g.tutorialDone then
    g.tutorial = { step = "walk", car = g.startCar }
  end
  g.overlay = nil -- { kind = "nabbed"/"ko", t = seconds }
  g.saveTimer = 60
  g.rammed = 0
  g.notice = {}
  return g
end

-- ---------------------------------------------------------------- the narrow surface missions use

function G:addMoney(n, why)
  self.money = self.money + n
  if n > 0 then self:cue("cash") end
  self.lastMoney = { n = n, why = why, t = 2.5 }
end

function G:message(text, seconds, cue)
  self.messages[#self.messages + 1] = { text = text, t = seconds or 3 }
  while #self.messages > 3 do table.remove(self.messages, 1) end
  if cue then self:cue(cue) end
end

function G:cue(name)
  self.cues[#self.cues + 1] = name
end

--- Show lines of talk; the game waits while they are up. onEnd runs after the last.
function G:dialogue(lines, onEnd)
  if not lines or #lines == 0 then
    if onEnd then onEnd() end
    return
  end
  self.talk = { lines = lines, index = 1, onEnd = onEnd }
  self:cue("talk")
end

function G:spawnCar(kind, x, z, h, colour)
  local car = vehicle.new(kind, x, z, h, colour)
  self.cars[#self.cars + 1] = car
  return car
end

function G:save()
  if self.saver then self.saver(self:saveData()) end
end

function G:saveData()
  local done = {}
  for id in pairs(self.progress.done) do done[#done + 1] = id end
  return { version = 1, money = self.money, done = done, finished = self.progress.finished, stats = self.stats,
    tutorialDone = self.tutorialDone or nil }
end

function G:load(data)
  if type(data) ~= "table" then return end
  self.money = tonumber(data.money) or 0
  for _, id in ipairs(data.done or {}) do
    if missions.BY_ID[id] then self.progress.done[id] = true end
  end
  self.progress.finished = data.finished and true or false
  self.tutorialDone = data.tutorialDone and true or nil
  if type(data.stats) == "table" then
    for k, v in pairs(data.stats) do
      if type(v) == "number" and self.stats[k] then self.stats[k] = v end
    end
  end
  -- a returning player wakes up at Juno's door, not the lockup
  if next(self.progress.done) then
    local j = self.city.places.juno
    self.player.x, self.player.z = j.x + 4, j.z
  end
end

-- ---------------------------------------------------------------- the world's furniture

function G:makePickups()
  local list = {}
  local r = util.rng(4242)
  local used = {}
  local count = 0
  while count < 16 do
    local i, j = r(city.N) - 1, r(city.N) - 1
    local key = i .. "," .. j
    if not used[key] then
      used[key] = true
      local x, z = city.ringPoint(i, j, r() * city.ringLength())
      list[#list + 1] = { x = x, z = z, value = 20 + r(5) * 10, t = 0 }
      count = count + 1
    end
  end
  return list
end

--- A few cars parked at the kerb near where the story starts, so there is always something to take.
function G:parkedCars()
  local function park(kind, place, dx, dz, h, colour)
    local p = self.city.places[place]
    local car = self:spawnCar(kind, p.x + dx, p.z + dz, h, colour)
    car.parked = true
    return car
  end
  self.startCar = park("marlin", "start", 10, -4.5, 0, "red")
  park("pipit", "juno", 14, -4.5, 0, "cyan")
  park("tidewater", "rusty", -6, 0, math.pi / 2)
  park("marlin", "hospital", 8, 4.5, math.pi, "green")
end

-- ---------------------------------------------------------------- spawning

local function farFromCars(g, x, z, gap)
  for _, car in ipairs(g.cars) do
    if util.dist2(car.x, car.z, x, z) < gap * gap then return false end
  end
  return true
end

--- A lane point at a distance between lo and hi from the player: k, l, d, x, z, h.
function G:laneSpot(lo, hi)
  local p = self.player
  for _ = 1, 12 do
    local k, l = self.rng(city.N + 1) - 1, self.rng(city.N + 1) - 1
    local exits = city.exits(k, l)
    local d = exits[self.rng(#exits)]
    local t = 8 + self.rng() * (city.P - 16)
    local x, z = city.lanePoint(k, l, d, t)
    local dist = util.dist(p.x, p.z, x, z)
    if dist >= lo and dist <= hi and farFromCars(self, x, z, 8) then
      local dir = city.DIRS[d + 1]
      return k + dir[1], l + dir[2], d, x, z, city.DIR_HEADING[d + 1]
    end
  end
  return nil
end

function G:countCars(kind)
  local n = 0
  for _, car in ipairs(self.cars) do
    if car.ai and car.ai.mode == kind then n = n + 1 end
  end
  return n
end

function G:spawnTraffic()
  local k, l, d, x, z, h = self:laneSpot(45, M.TRAFFIC_RADIUS - 10)
  if not k then return nil end
  local kind = vehicle.TRAFFIC_TYPES[self.rng(#vehicle.TRAFFIC_TYPES)]
  local colour = nil
  if kind == "pipit" or kind == "marlin" then colour = vehicle.BODY_COLOURS[self.rng(#vehicle.BODY_COLOURS)] end
  local car = self:spawnCar(kind, x, z, h, colour)
  car.v = 8
  ai.init(car, "traffic", k, l, d)
  return car
end

function G:spawnCop(lo, hi)
  local k, l, d, x, z, h = self:laneSpot(lo or 55, hi or 105)
  if not k then return nil end
  local car = self:spawnCar("cruiser", x, z, h)
  car.v = 14
  ai.init(car, "cop", k, l, d)
  return car
end

function G:spawnPed()
  local p = self.player
  for _ = 1, 8 do
    local i, j = self.rng(city.N) - 1, self.rng(city.N) - 1
    local s = self.rng() * city.ringLength()
    local x, z = city.ringPoint(i, j, s)
    local dist = util.dist(p.x, p.z, x, z)
    if dist > 22 and dist < M.PED_RADIUS - 5 then
      local ped = peds.new(self, i, j, s, self.rng() < 0.5 and -1 or 1)
      self.peds[#self.peds + 1] = ped
      return ped
    end
  end
  return nil
end

--- Keep the streets busy near you, and clear what is far away.
function G:populate()
  local p = self.player
  local wantCops = heatlib.copsFor(self.heat.level)
  -- cars left at the kerb stay put while you are about, but only the nearest few
  local parked = {}
  for _, car in ipairs(self.cars) do
    if car.parked and not car.wrecked and car ~= p.car and not car.mission then parked[#parked + 1] = car end
  end
  local dropParked = {}
  if #parked > M.PARKED_MAX then
    table.sort(parked, function(a, b) return util.dist2(p.x, p.z, a.x, a.z) < util.dist2(p.x, p.z, b.x, b.z) end)
    for k = M.PARKED_MAX + 1, #parked do dropParked[parked[k]] = true end
  end
  for i = #self.cars, 1, -1 do
    local car = self.cars[i]
    local d = util.dist(p.x, p.z, car.x, car.z)
    local mode = car.ai and car.ai.mode
    local far = M.TRAFFIC_RADIUS + 15
    if mode == "cop" and self.heat.level > 0 then far = 170 end
    local keep = car == p.car or car.mission or (car.parked and not car.wrecked and not dropParked[car])
    if not keep and (d > far or (car.wrecked and (car.burn or 0) > 14) or dropParked[car]) then
      table.remove(self.cars, i)
    end
  end
  if not self.quiet then
    if self:countCars("traffic") < M.TRAFFIC then self:spawnTraffic() end
  end
  if self:countCars("cop") < wantCops then self:spawnCop() end
  for i = #self.peds, 1, -1 do
    local ped = self.peds[i]
    local d = util.dist(p.x, p.z, ped.x, ped.z)
    if d > M.PED_RADIUS + 15 or (ped.state == "down" and ped.t <= 0) or (ped.state == "run" and ped.t <= 0 and d > 25) then
      table.remove(self.peds, i)
    end
  end
  if not self.quiet and #self.peds < M.PEDS then self:spawnPed() end
end

-- ---------------------------------------------------------------- you

function G:speed()
  local p = self.player
  if p.car then return abs(p.car.v) end
  return abs(p.v)
end

--- The nearest car you could get into, within reach.
function G:nearestCar(reach)
  local p = self.player
  local best, bestD = nil, (reach or 4.2) ^ 2
  for _, car in ipairs(self.cars) do
    if not car.wrecked then
      local d = util.dist2(p.x, p.z, car.x, car.z)
      if d < bestD then best, bestD = car, d end
    end
  end
  return best
end

--- Does any cruiser see you right now?
function G:copSees()
  for _, car in ipairs(self.cars) do
    if car.ai and car.ai.mode == "cop" and car.ai.los and not car.wrecked then return true end
  end
  return false
end

function G:crime(amount, reason, needWitness)
  if needWitness and not self:copSees() then
    -- nobody in uniform saw it: a passer-by phones it in, sometimes
    if self.rng() > 0.45 then return end
  end
  if heatlib.add(self.heat, amount, reason) > 0 then self:cue("heat") end
end

function G:enterCar(car)
  local p = self.player
  if car.ai then
    -- pull the driver out
    local dx, dz = vehicle.doorPoint(car)
    local runner = peds.runner(self, dx, dz, util.headingTo(p.x, p.z, dx, dz))
    self.peds[#self.peds + 1] = runner
    if car.ai.mode == "cop" then
      self:crime(2, "stole a cruiser")
    else
      self:crime(1, "carjacking", true)
    end
    car.ai = nil
    self:cue("door")
  elseif car.spec.police then
    self:crime(2, "stole a cruiser")
  end
  car.parked = nil
  p.car = car
  self.stats.cars = self.stats.cars + 1
  self:cue("door")
end

function G:exitCar()
  local p = self.player
  local car = p.car
  if not car then return end
  local x, z = vehicle.doorPoint(car)
  x, z = city.collide(self.city, x, z, M.PLAYER_RADIUS)
  if abs(car.v) > 8 then
    -- bailing out at speed hurts
    self:hurt(12)
  end
  p.car = nil
  car.parked = true
  p.x, p.z, p.h, p.v = x, z, car.h, 0
  self:cue("door")
end

function G:hurt(amount)
  local p = self.player
  p.health = math.max(0, p.health - amount)
  self.hurtFlash = 0.4
end

local function footMove(g, input, dt)
  local p = g.player
  local turn = M.FOOT_TURN
  p.h = util.wrap(p.h + (input.steer or 0) * turn * dt)
  local throttle = input.throttle or 0
  local top = (input.sprint and M.RUN or M.WALK)
  local want = throttle * top
  if throttle < 0 then want = throttle * M.WALK * 0.6 end
  p.v = util.approach(p.v, want, 25 * dt)
  local nx, nz = p.x + cos(p.h) * p.v * dt, p.z + sin(p.h) * p.v * dt
  nx, nz = city.collide(g.city, nx, nz, M.PLAYER_RADIUS)
  p.x, p.z = nx, nz
end

-- ---------------------------------------------------------------- endings of a life

function G:respawn(place)
  local p = self.player
  if p.car then
    p.car.parked = true
    p.car = nil
  end
  local spot = self.city.places[place]
  p.x, p.z, p.h, p.v, p.health = spot.x, spot.z, spot.h or 0, 0, 100
  heatlib.clear(self.heat)
  -- every cruiser goes back to patrol and far ones are gone
  for i = #self.cars, 1, -1 do
    local car = self.cars[i]
    if car.ai and car.ai.mode == "cop" then table.remove(self.cars, i) end
  end
end

function G:nabbed()
  local fine = math.min(self.money, math.max(50, floor(self.money * 0.1)))
  self.money = self.money - fine
  self.stats.nabbed = self.stats.nabbed + 1
  missions.fail(self, "nabbed by the Harbor Patrol")
  self.overlay = { kind = "nabbed", t = 3.5, fine = fine }
  self:cue("nabbed")
end

function G:knockedOut()
  local bill = math.min(self.money, 100)
  self.money = self.money - bill
  self.stats.ko = self.stats.ko + 1
  missions.fail(self, "you got knocked out")
  self.overlay = { kind = "ko", t = 3.5, fine = bill }
  self:cue("ko")
end

-- ---------------------------------------------------------------- services

function G:services(dt)
  local p = self.player
  local car = p.car
  local places = self.city.places
  local function near(name, extra)
    local pl = places[name]
    local r = pl.r + (extra or 0)
    return util.dist2(p.x, p.z, pl.x, pl.z) <= r * r
  end
  local function notice(key, text)
    if (self.notice[key] or 0) <= 0 then
      self:message(text, 3)
      self.notice[key] = 6
    end
  end
  for k, v in pairs(self.notice) do self.notice[k] = v - dt end
  -- Paint & Pray: a new coat and the Patrol forgets you
  if car and near("respray") then
    if self.heat.level > 0 and abs(car.v) < 6 then
      if self.money >= M.RESPRAY_COST then
        self.money = self.money - M.RESPRAY_COST
        heatlib.clear(self.heat)
        local colours = vehicle.BODY_COLOURS
        car.colour = colours[self.rng(#colours)]
        car.health = math.min(car.spec.health, car.health + car.spec.health * 0.5)
        self:message("Paint & Pray: fresh coat, no heat.  -" .. util.money(M.RESPRAY_COST), 4, "spray")
        for _, c in ipairs(self.cars) do
          if c.ai and c.ai.mode == "cop" then c.ai.los = false end
        end
      else
        notice("spray", "Paint & Pray: a respray is " .. util.money(M.RESPRAY_COST) .. ". Come back with cash.")
      end
    end
  end
  -- Rusty's: sell what you drive in (not during a job that ends here)
  local rustyJob = false
  if self.mission then
    local step = self.mission.def.steps[self.mission.index]
    rustyJob = step and step.place == "rusty"
  end
  if car and near("rusty") and not rustyJob and not car.mission then
    if car.spec.police then
      notice("chop", "Rusty: \"A Patrol cruiser? Get that out of my yard!\"")
    elseif self.heat.level > 0 then
      notice("chop", "Rusty: \"Not with heat on you. Lose them first.\"")
    elseif abs(car.v) < 2 then
      local value = vehicle.chopValue(car)
      self:exitCar()
      for i, c in ipairs(self.cars) do
        if c == car then table.remove(self.cars, i) break end
      end
      self.stats.chopped = self.stats.chopped + 1
      self:addMoney(value, "chop")
      self:message("Rusty bought the " .. car.spec.name .. " for " .. util.money(value), 4)
    else
      notice("chopslow", "Rusty's Chop Yard: stop here to sell the car.")
    end
  end
  -- cash on the pavement
  for _, cash in ipairs(self.pickups) do
    if cash.t > 0 then
      cash.t = cash.t - dt
    elseif util.dist2(p.x, p.z, cash.x, cash.z) < (car and 3.2 or 1.8) ^ 2 then
      self:addMoney(cash.value, "cash")
      cash.t = 120
      self:message("+" .. util.money(cash.value), 2)
    end
  end
end

-- ---------------------------------------------------------------- the story

function G:storyTick(dt)
  if self.mission then
    missions.update(self, dt)
    return
  end
  local def = missions.nextMission(self.progress)
  if not def then return end
  local giver = self.city.places[def.giver]
  local p = self.player
  if util.dist2(p.x, p.z, giver.x, giver.z) <= (giver.r + 1) ^ 2 then
    if self.heat.level > 0 then
      if (self.notice.giver or 0) <= 0 then
        self:message("Lose your heat before you go see " .. (def.giver == "juno" and "Juno" or "Rusty") .. ".", 3)
        self.notice.giver = 6
      end
      return
    end
    if self.giverCooldown and self.giverCooldown > 0 then return end
    if p.car and abs(p.car.v) > 4 then return end
    self:message(def.title, 3, "start")
    self:dialogue(def.intro, function() missions.start(self, def) end)
    self.giverCooldown = 4
  end
end

-- ---------------------------------------------------------------- the first-time tutorial

--- Walk to the red car, press E, drive to Juno's marker. Each step waits for you; X skips the lot.
function G:tutorialTick(input)
  local tut = self.tutorial
  if not tut then return end
  local p = self.player
  if input.skip then
    self:endTutorial("Tutorial skipped. P shows the controls any time.")
    return
  end
  if tut.step == "walk" then
    local car = tut.car
    if p.car then
      tut.step = "drive"
      self:cue("start")
    elseif not car or car.wrecked or util.dist2(p.x, p.z, car.x, car.z) < 4.5 * 4.5 then
      tut.step = "enter"
      self:cue("start")
    end
  elseif tut.step == "enter" then
    if p.car then
      tut.step = "drive"
      self:cue("start")
    end
  elseif tut.step == "drive" then
    local j = self.city.places.juno
    if util.dist2(p.x, p.z, j.x, j.z) <= (j.r + 1) ^ 2 then
      self:endTutorial("That's it. Juno has your first job. P shows the controls any time.")
    end
  end
end

function G:endTutorial(text)
  self.tutorial = nil
  self.tutorialDone = true
  self:message(text, 4)
  self:save()
end

-- ---------------------------------------------------------------- one step

function G:update(dt, input)
  input = input or {}
  dt = util.clamp(dt, 0, 0.25)
  self.t = self.t + dt

  -- messages and flashes run down even during talk
  for i = #self.messages, 1, -1 do
    local m = self.messages[i]
    m.t = m.t - dt
    if m.t <= 0 then table.remove(self.messages, i) end
  end
  if self.lastMoney then
    self.lastMoney.t = self.lastMoney.t - dt
    if self.lastMoney.t <= 0 then self.lastMoney = nil end
  end
  if self.hurtFlash then
    self.hurtFlash = self.hurtFlash - dt
    if self.hurtFlash <= 0 then self.hurtFlash = nil end
  end

  if self.talk then
    if input.advance or input.enter then
      local talk = self.talk
      talk.index = talk.index + 1
      if talk.index > #talk.lines then
        self.talk = nil
        if talk.onEnd then talk.onEnd() end
      else
        self:cue("talk")
      end
    end
    return
  end

  if self.overlay then
    self.overlay.t = self.overlay.t - dt
    if self.overlay.t <= 0 then
      local kind = self.overlay.kind
      self.overlay = nil
      self:respawn(kind == "nabbed" and "precinct" or "hospital")
      self:save()
    end
    return
  end

  if self.giverCooldown then self.giverCooldown = self.giverCooldown - dt end
  local p = self.player

  -- getting in and out
  if input.enter then
    if p.car then
      self:exitCar()
    else
      local car = self:nearestCar()
      if car then self:enterCar(car) end
    end
  end
  if input.horn then self:cue("horn") end

  -- every car moves
  local heatLevel = self.heat.level
  local sight = heatlib.SIGHT
  local playerImpact = 0
  for _, car in ipairs(self.cars) do
    local carInput
    if car == p.car then
      carInput = input
    elseif car.ai and not car.wrecked then
      if car.ai.mode == "cop" then
        ai.copSees(self, car, dt, sight)
        carInput = ai.cop(self, car, dt, heatLevel)
      else
        carInput = ai.traffic(self, car, dt)
      end
    end
    local impact = vehicle.update(car, carInput, dt, self.city)
    if car == p.car then playerImpact = impact end
    if car.wrecked then car.burn = (car.burn or 0) + dt end
  end
  if playerImpact > 9 then self:cue("crash") end

  -- cars against cars
  self.rammed = math.max(0, self.rammed - dt)
  local cars = self.cars
  for a = 1, #cars - 1 do
    local ca = cars[a]
    for b = a + 1, #cars do
      local cb = cars[b]
      local closing = vehicle.bump(ca, cb)
      if closing > 0 then
        local mine = ca == p.car or cb == p.car
        if mine and closing > 6 then self:cue("crash") end
        local other = ca == p.car and cb or (cb == p.car and ca or nil)
        if other and other.ai and other.ai.mode == "cop" and closing > 7 and self.rammed <= 0 and abs(p.car.v) > abs(other.v) then
          self.rammed = 4
          self:crime(1, "rammed a cruiser")
        end
      end
    end
  end

  if p.car then
    local car = p.car
    p.x, p.z, p.h = car.x, car.z, car.h
    if car.wrecked then
      self:message("Your " .. car.spec.name .. " is wrecked!", 3, "crash")
      self:exitCar()
      self:hurt(25)
    end
  else
    footMove(self, input, dt)
    -- cars hitting you on foot
    for _, car in ipairs(self.cars) do
      local reach = car.spec.radius * 0.8 + M.PLAYER_RADIUS
      if abs(car.v) > 4 and util.dist2(car.x, car.z, p.x, p.z) < reach * reach then
        self:hurt((abs(car.v) - 3) * 3)
        local away = util.headingTo(car.x, car.z, p.x, p.z)
        p.x, p.z = city.collide(self.city, p.x + cos(away) * 1.5, p.z + sin(away) * 1.5, M.PLAYER_RADIUS)
        car.v = car.v * 0.6
        self:cue("thud")
      end
    end
  end

  -- people
  for _, ped in ipairs(self.peds) do
    local what, car = peds.update(self, ped, dt)
    if what == "hit" then
      self:cue("thud")
      if car == p.car then self:crime(1, "hit a pedestrian", true) end
    end
  end

  -- heat
  local seen = self:copSees()
  local caught = false
  if heatLevel > 0 and self:speed() < 2.5 then
    for _, car in ipairs(self.cars) do
      if car.ai and car.ai.mode == "cop" and not car.wrecked and util.dist2(car.x, car.z, p.x, p.z) < 6.5 * 6.5 then
        caught = true
        break
      end
    end
  end
  local result = heatlib.update(self.heat, dt, seen, caught)
  if result == "pinched" then
    self:nabbed()
    return
  elseif result == "cooled" then
    self:cue(self.heat.level == 0 and "lost" or "cool")
    if self.heat.level == 0 then self:message("You lost the Patrol.", 3) end
  end

  self:tutorialTick(input)
  self:services(dt)
  self:storyTick(dt)

  if p.health <= 0 then
    self:knockedOut()
    return
  end

  self:populate()

  self.saveTimer = self.saveTimer - dt
  if self.saveTimer <= 0 then
    self.saveTimer = 60
    self:save()
  end
end

--- Drain the cues (sounds) since the last call.
function G:takeCues()
  local cues = self.cues
  self.cues = {}
  return cues
end

M.missions = missions
return M
