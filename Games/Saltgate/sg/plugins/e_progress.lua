-- plugins/e_progress.lua
-- Stream E: persistent stats, the 40 achievements and the 100% tracker, kept in save.progress and fed by the bus. Other
-- parts reach it as ctx.progress:
--   ctx.progress.stats          :add :max :get :member :count
--   ctx.progress.achievements   :unlock(id) :check() :list() :count()
--   ctx.progress.completion     :compute() :percent() :display() :provide(id, fn)
--   ctx.progress.wallet         add(ctx, n, reason)  spend(ctx, n, reason)  balance(ctx)

local statsLib = require("sg.progress.stats")
local achLib = require("sg.progress.achievements")
local completionLib = require("sg.progress.completion")
local wallet = require("sg.progress.wallet")

local P = { name = "e_progress", order = 10 }

local CHECK_EVERY = 0.5
local TELEPORT = 40 -- a jump this far in one frame is a respawn or a move, not driving

local function load(ctx, path, what)
  local data, err = ctx.content:data(path)
  if not data then
    ctx.log("e_progress: no " .. what .. " (" .. tostring(err) .. ")")
    return nil
  end
  return data
end

function P.init(ctx)
  local save = ctx.save
  save.progress = save.progress or {}
  local prog = save.progress
  local stats = statsLib.new(prog)
  local config = load(ctx, "activities/progress.lua", "progress config") or { categories = {}, storyTotal = 24 }
  local defs = load(ctx, "activities/achievements.lua", "achievements") or {}
  local completion = completionLib.new(config)

  local api = { stats = stats, completion = completion, wallet = wallet, config = config }
  ctx.progress = api

  -- the built-in parts of the tracker
  completion:provide("story", function()
    local n = 0
    for _ in pairs(ctx.save.story.done or {}) do n = n + 1 end
    local total = math.max(config.storyTotal or 24, n)
    return n, total
  end)
  local ach
  ach = achLib.new({
    defs = defs, stats = stats, section = prog,
    done = function(category)
      local fn = completion.providers[category]
      if fn then return fn() end
      return 0, 0
    end,
    completion = function() return completion:percent() end,
    story = function() return ctx.save.story.finished == true end,
    pay = function(n, reason) wallet.add(ctx, n, reason) end,
    announce = function(def)
      api.announcing = true
      ctx.bus:emit("achievement", { id = def.id })
      api.announcing = false
    end,
  })
  api.achievements = ach
  completion:provide("achievements", function() return ach:trackerCounts() end)

  -- an achievement another part announces (its own id from our list) counts too, without a second payment
  ctx.bus:on("achievement", function(d)
    if not api.announcing and ach:def(d.id) and not ach:has(d.id) then
      prog.achievements[d.id] = math.floor(stats:get("playSeconds"))
    end
  end, "e_progress")

  api.dirty = true
  local bus = ctx.bus
  local function touch() api.dirty = true end
  bus:on("load", function(d)
    if d.data and d.data.progress then
      stats:use(d.data.progress)
      ach:use(d.data.progress)
      prog = d.data.progress
    end
    api.last = nil
    touch()
  end, "e_progress")
  bus:on("money", function(d)
    if d.amount > 0 then stats:add("moneyEarned", d.amount) else stats:add("moneySpent", -d.amount) end
    touch()
  end, "e_progress")
  bus:on("vehicle_enter", function(d)
    if d.stolen then stats:add("carsStolen", 1) touch() end
  end, "e_progress")
  bus:on("heat_changed", function(d)
    stats:max("maxHeat", d.level)
    if d.level == 0 and (d.previous or 0) > 0 then stats:add("heatCleared", 1) end
    touch()
  end, "e_progress")
  bus:on("player_down", function(d)
    stats:add(d.kind == "nabbed" and "arrests" or "knockouts", 1)
  end, "e_progress")
  bus:on("mission_end", function(d)
    if d.result == "pass" then
      if stats:member("missions", d.id) then stats:add("missionsPassed", 1) end
    else
      stats:add("missionsFailed", 1)
    end
    touch()
  end, "e_progress")
  bus:on("jump", function(d)
    if d.landed then
      stats:add("jumps", 1)
      stats:max("longestJump", d.distance or 0)
    end
    touch()
  end, "e_progress")
  bus:on("district_enter", function(d)
    if d.district then stats:member("districts", tostring(d.district)) touch() end
  end, "e_progress")
  bus:on("pickup", touch, "e_progress")
  bus:on("checkpoint", touch, "e_progress")
  bus:on("mission_start", touch, "e_progress")
  api.timer = 0
end

function P.update(ctx, dt)
  local api = ctx.progress
  local stats = api.stats
  stats:add("playSeconds", dt)
  local p = ctx.player
  if p then
    local car = p.car
    local at = car or p
    local last = api.last
    if last then
      local d = math.sqrt((at.x - last.x) ^ 2 + (at.z - last.z) ^ 2)
      if d < TELEPORT then stats:add(car and "distance" or "onFoot", d) end
    end
    api.last = { x = at.x, z = at.z }
    if car then
      stats:max("topSpeed", math.floor(math.abs(car.v or 0) * 3.6 + 0.5))
      if car.airborne then stats:add("airtime", dt) end
    end
  end
  api.timer = api.timer + dt
  if api.timer >= CHECK_EVERY then
    api.timer = 0
    -- distance and time move all the time: check regularly, not only when an event says something changed
    api.achievements:check()
    api.dirty = false
  end
end

return P
