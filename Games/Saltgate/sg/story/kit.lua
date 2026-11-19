-- story/kit.lua
-- The verbs a mission script has on top of core/script.lua's: cars to steal, drives under a clock, tails, chases, escorts,
-- shootouts, a jump, a hold, phone texts, a remembered choice, a checkpoint that knows where to put you back. A script
-- gets one `api` and calls these; every one that waits yields until it is done, and every failure is a clear reason the
-- failure screen shows.
--
-- Rules for a script (they make a retry and a load work):
--   * all the work is inside api.step(name, fn, opts): code outside steps runs again on every resume and keeps nothing
--   * what a later step needs goes in api.flag / api.var (kept in the save), or an actor made with { name = "van" }
--     and found again with api.actor("van"); a step that needs the mission car calls api.ensureCar
--   * a step's opts say where the player is put when it starts again: { at = "place", give = { name, kind } }
--
-- Core's: step say choose objective waitUntil wait goTo spawn cutscene setHeat reward flag var fail time
-- Added:
--   step(name, fn, opts)            opts: at (a place), give ({ name, kind }: a car the player is put in), text (a toast)
--   say(who, text)  lines({ { who, text }, ... })     choose(prompt, options) -> index (remembered for a retry)
--   remember(key, value)  recall(key)  tally(key, n)  score(key)       what the story keeps for good
--   car(kind, at, opts) -> actor  ensureCar(name, kind, at, opts)  getIn(name, text)  anyCar(text)
--   drive(place, opts)              opts: text, name (the mission car), timer, noHeat, minHealth, onFoot, radius, stop
--   hold(place, seconds, opts)      stay put: the count pauses while you are away
--   loseHeat(text, opts)            until the Patrol has lost you
--   heat(n)                         at least n stars
--   actor(kind, at, opts) -> actor  opts: name, group, route, count ...      get(name) -> a named actor
--   tail(name, opts)  chase(name, opts)  escort(name, dest, opts)  defeat(group, opts)  survive(seconds, opts)
--   jump(opts)                      leave the ground and land it: opts.text, min (distance), name
--   timer(seconds, text, reason)    a clock on the screen; at zero the mission fails      stopTimer()
--   watch(fn, reason) -> id         every frame; a truthy result (or a string) fails the mission
--   guard(name, reason)             fail the mission if that actor is wrecked or knocked down
--   text(from, message)             a text on the phone         unlock(contact)     toast(message)
--   hint(text)                      what Tam says if you phone her now
--   music(cue)                      title ... job, drive, heat_low, heat_high, finale, credits, complete
--   title(text, sub)                a black card
--   ending(name)                    the story is over: "leave", "stay" or "crown"
--   retrying()                      true while a retry or a load is catching up

local M = {}

local function noop() end

--- A new api for a script: everything core's has, plus the kit.
function M.extend(api, host)
  local k = setmetatable({}, { __index = api })
  local w = host.world

  local function actorOf(name)
    local a = host.actors[name]
    if not a then error("no actor '" .. tostring(name) .. "' (make it in this step, or call ensureCar)", 3) end
    return a
  end

  local function goal(kind, data)
    data = data or {}
    data.kind = kind
    host.goal = data
    return data
  end

  -- ------------------------------------------------------------ the script's shape

  function k.step(name, fn, opts)
    host.stepOpts[name] = opts or {}
    api.step(name, fn)
  end

  function k.retrying() return host.fast end

  function k.say(who, text)
    if host.fast then return end
    api.say(who, text)
  end

  function k.lines(list)
    for _, l in ipairs(list) do k.say(l[1], l[2]) end
  end

  function k.choose(prompt, options)
    local picks = api.var("_picks")
    if not picks then
      picks = {}
      api.var("_picks", picks)
    end
    if host.fast and picks[prompt] then return picks[prompt] end
    local pick = api.choose(prompt, options)
    picks[prompt] = pick
    return pick
  end

  function k.cutscene(shots)
    if host.fast then return end
    api.cutscene(shots)
  end

  function k.title(text, sub)
    k.cutscene({ { black = true, title = text .. (sub and ("\n" .. sub) or ""), seconds = 2.6, fade = "both" } })
  end

  function k.remember(key, value) host.story.flags[key] = value end
  function k.recall(key) return host.story.flags[key] end
  function k.tally(key, n)
    local t = host.story.tally
    t[key] = (t[key] or 0) + (n or 1)
    return t[key]
  end
  function k.score(key) return host.story.tally[key] or 0 end

  function k.text(from, message)
    if host.fast then return end
    host:phoneText(from, message)
  end
  function k.unlock(who) host:unlock(who) end
  function k.toast(message, kind)
    if host.fast then return end
    host:card(kind or "toast", message)
  end
  function k.hint(text) host.hint = text end
  function k.music(cue) host:music(cue) end

  function k.ending(name)
    host.story.ending = name
    host.story.finished = true
    host.story.flags.ending = name
    host:music("credits")
  end

  -- ------------------------------------------------------------ cars and places

  function k.car(kind, at, opts)
    opts = opts or {}
    opts.vehicle = kind
    opts.name = opts.name or "car"
    local a = host:spawn("car", at, opts)
    if opts.watch ~= false then
      k.watch(function()
        if w:state(a) == "wrecked" then return "the " .. (opts.label or "car") .. " is wrecked" end
      end)
    end
    return a
  end

  function k.ensureCar(name, kind, at, opts)
    local a = host.actors[name]
    if a and w:state(a) ~= "wrecked" and w:state(a) ~= "gone" then
      k.watch(function()
        if w:state(a) == "wrecked" then return "the " .. ((opts and opts.label) or "car") .. " is wrecked" end
      end)
      return a
    end
    opts = opts or {}
    opts.name = name
    return k.car(kind, at, opts)
  end

  function k.getIn(name, text)
    local a = actorOf(name)
    k.objective(text or "Get in the car.", a)
    goal("enter", { name = name })
    api.waitUntil(function() return w:inCar(a) end)
  end

  function k.anyCar(text)
    k.objective(text or "Get into any car (walk up to one, press E).")
    goal("anycar")
    api.waitUntil(function() local p = w:player() return p and p.car ~= nil end)
  end

  function k.drive(place, opts)
    opts = opts or {}
    local actor = opts.name and actorOf(opts.name) or nil
    k.objective(opts.text or ("Go to " .. tostring(place) .. "."), place)
    goal("go", { place = place, name = opts.name })
    if opts.timer then k.timer(opts.timer, opts.timerText, opts.timerReason) end
    local spec = { car = not opts.onFoot, actor = actor, radius = opts.radius, speed = (opts.stop == false) and nil or 9 }
    if opts.onFoot then spec.speed = nil end
    local hot = false
    local ok = api.waitUntil(function()
      if not w:inPlace(place, spec) then
        hot = false
        host.holdNote = nil
        return false
      end
      if opts.noHeat and w:heat() > 0 then
        hot = true
        host.holdNote = opts.hotText or "Lose the Patrol first."
        return false
      end
      if hot then host.holdNote = nil end
      if actor and opts.minHealth and w:health(actor) < opts.minHealth then
        host:failNow(opts.failText or "the car is too damaged")
        return false
      end
      return true
    end, opts.timeout)
    host.holdNote = nil
    if opts.timer then k.stopTimer() end
    if not ok then api.fail(opts.failText or "out of time") end
  end

  --- Core's goTo, on the kit's drive (so the clock, the HUD and the checks are the same): on foot unless opts.car.
  function k.goTo(place, opts)
    opts = opts or {}
    k.drive(place, { text = opts.text, onFoot = not opts.car, radius = opts.radius, timeout = opts.timeout,
      failText = opts.failText })
    return true
  end

  --- A lift between levels (a lift up a building, a goods hoist): a short card over black, then you are at the place,
  -- at its height; with your car, or on foot (opts.onFoot: the car stays where it was). For places no road climbs to.
  function k.lift(place, opts)
    opts = opts or {}
    k.cutscene({ { black = true, title = opts.title or "...", seconds = opts.seconds or 1.5 } })
    w:moveTo(place, opts.onFoot)
  end

  function k.hold(place, seconds, opts)
    opts = opts or {}
    k.objective(opts.text or "Hold position.", place)
    goal("hold", { place = place, seconds = seconds })
    local held = 0
    local last = api.time()
    api.waitUntil(function()
      local now = api.time()
      local dt = now - last
      last = now
      if w:inPlace(place, { radius = opts.radius or 2 }) then
        held = held + dt
        host.holdNote = nil
      else
        host.holdNote = opts.away or "Get back to the spot!"
      end
      return held >= seconds
    end)
    host.holdNote = nil
  end

  function k.loseHeat(text, opts)
    opts = opts or {}
    k.objective(text or "Lose the Harbor Patrol.")
    goal("loseheat")
    local ok = api.waitUntil(function() return w:heat() <= 0 end, opts.timeout)
    if not ok then api.fail(opts.failText or "the Patrol is still on you") end
  end

  function k.heat(n) w:setHeat(n) end

  function k.actor(kind, at, opts)
    return host:spawn(kind, at, opts or {})
  end

  -- ------------------------------------------------------------ the set pieces

  function k.tail(name, opts)
    opts = opts or {}
    local a = actorOf(name)
    local min, max = opts.min or 7, opts.max or 70
    k.objective(opts.text or "Follow them. Stay back, but keep them in sight.", a)
    goal("tail", { name = name })
    local far, near
    local ok = api.waitUntil(function()
      local st = w:state(a)
      if st == "arrived" then return true end
      if st == "wrecked" or st == "down" or st == "escaped" or st == "gone" then
        host:failNow("the target is gone")
        return false
      end
      local d = w:distTo(a)
      local now = api.time()
      if d > max then
        far = far or now
        if now - far > (opts.grace or 8) then host:failNow("you lost them") end
      else
        far = nil
      end
      if d < min then
        near = near or now
        if now - near > (opts.spot or 5) then host:failNow("they spotted you") end
      else
        near = nil
      end
      host.holdNote = (d > max * 0.75 and "Closer. You are losing them.") or (d < min * 1.5 and "Ease off. Don't crowd them.") or nil
      return false
    end, opts.timeout)
    host.holdNote = nil
    if not ok and opts.timeout then api.fail("out of time") end
  end

  function k.chase(name, opts)
    opts = opts or {}
    local a = actorOf(name)
    k.objective(opts.text or "Don't let them get away. Ram them to a stop.", a)
    goal("chase", { name = name })
    local ok = api.waitUntil(function()
      local st = w:state(a)
      if st == "caught" or st == "wrecked" then return true end
      if st == "escaped" or st == "arrived" or st == "gone" then
        host:failNow(opts.failText or "they got away")
        return false
      end
      return false
    end, opts.timeout)
    if not ok and opts.timeout then api.fail(opts.failText or "they got away") end
  end

  function k.escort(name, dest, opts)
    opts = opts or {}
    local a = actorOf(name)
    local max = opts.max or 90
    w:route(a, dest)
    k.objective(opts.text or "Keep them safe all the way there.", a)
    goal("escort", { name = name, place = dest })
    local far
    api.waitUntil(function()
      local st = w:state(a)
      if st == "arrived" then return true end
      if st == "wrecked" or st == "down" or st == "gone" then
        host:failNow(opts.failText or "they didn't make it")
        return false
      end
      if w:distTo(a) > max then
        far = far or api.time()
        if api.time() - far > 9 then host:failNow("you left them behind") end
      else
        far = nil
      end
      return false
    end, opts.timeout)
  end

  function k.defeat(group, opts)
    opts = opts or {}
    local text = opts.text or "Knock them all down."
    k.objective(text, group)
    goal("defeat", { group = group })
    local ok = api.waitUntil(function()
      local left = w:remaining(group)
      host.holdNote = left > 0 and (text .. " (" .. left .. " left)") or nil
      return left <= 0
    end, opts.timeout)
    host.holdNote = nil
    if not ok then api.fail(opts.failText or "out of time") end
  end

  function k.survive(seconds, opts)
    opts = opts or {}
    local text = opts.text or "Hold out."
    k.objective(text)
    goal("survive", { seconds = seconds })
    local start = api.time()
    api.waitUntil(function()
      local left = math.max(0, math.ceil(seconds - (api.time() - start)))
      host.holdNote = text .. " " .. left .. "s"
      return api.time() - start >= seconds
    end)
    host.holdNote = nil
  end

  function k.jump(opts)
    opts = opts or {}
    k.objective(opts.text or "Make the jump.", opts.place)
    goal("jump", { min = opts.min or 8 })
    w:clearFlight()
    api.waitUntil(function()
      local f = w:flight()
      if not f then return false end
      if not f.landed then
        host:failNow(opts.failText or "you missed the landing")
        return false
      end
      if f.distance >= (opts.min or 8) then return true end
      w:clearFlight()
      return false
    end, opts.timeout)
  end

  -- ------------------------------------------------------------ clocks and rules

  function k.timer(seconds, text, reason)
    host.timer = { left = seconds, total = seconds, text = text or "TIME", reason = reason or "out of time" }
  end
  function k.stopTimer() host.timer = nil end

  function k.watch(fn, reason)
    local id = #host.watches + 1
    host.watches[id] = { fn = fn, reason = reason or "failed" }
    return id
  end
  --- Fail the mission if the named actor is wrecked or knocked down.
  function k.guard(name, reason)
    local a = actorOf(name)
    return k.watch(function()
      local st = w:state(a)
      if st == "wrecked" or st == "down" then return reason end
    end, reason)
  end
  function k.unwatch(id)
    if host.watches[id] then host.watches[id] = { fn = noop, reason = "" } end
  end

  function k.get(name) return host.actors[name] end

  return k
end

return M
