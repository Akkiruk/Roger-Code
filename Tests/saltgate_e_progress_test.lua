-- saltgate_e_progress_test.lua
-- SALTGATE stream E, progress and sound: persistent stats, the 40 achievements (each fires once, pays once), the 100%
-- tracker's arithmetic, settings that persist and are applied, and the car radio with the soundtrack's cues.

local t = require("testing")
local kit = require("sg.ui.testkit")
local statsLib = require("sg.progress.stats")
local achLib = require("sg.progress.achievements")
local completionLib = require("sg.progress.completion")
local wallet = require("sg.progress.wallet")
local settingsLib = require("sg.ui.settings")
local radioLib = require("sg.radio")
local saveLib = require("sg.core.save")
local vehicle = require("sg.vehicle")

local function game(opts)
  local ctx = kit.game(opts)
  ctx.eui.titleShown = true
  return ctx
end

-- ---------------------------------------------------------------- stats

t.test("stats: counters, maxima and sets, formatted for the screen", function()
  local s = statsLib.new({})
  s:add("distance", 12.5)
  s:add("distance", 7.5)
  t.eq(s:get("distance"), 20)
  s:max("topSpeed", 90)
  s:max("topSpeed", 60)
  t.eq(s:get("topSpeed"), 90)
  t.truthy(s:member("districts", "gilt"))
  t.truthy(not s:member("districts", "gilt"), "a set member counts once")
  s:member("districts", "cinder")
  t.eq(s:count("districts"), 2)
  t.eq(statsLib.format("d", 1500), "1.5 km")
  t.eq(statsLib.format("d", 80), "80 m")
  t.eq(statsLib.format("t", 3725), "1h 02m")
  t.eq(statsLib.format("m", 12500), "$12,500")
  t.eq(statsLib.format("s", 123.4), "123 km/h")
end)

t.test("stats: the bus feeds them (money, heat, jumps, jobs, districts, arrests) and play moves distance and time", function()
  local ctx = game({ money = 0 })
  local st = ctx.progress.stats
  wallet.add(ctx, 300, "test")
  wallet.spend(ctx, 120, "test")
  t.eq(st:get("moneyEarned"), 300)
  t.eq(st:get("moneySpent"), 120)
  ctx.bus:emit("heat_changed", { level = 4, previous = 0 })
  ctx.bus:emit("heat_changed", { level = 0, previous = 4 })
  t.eq(st:get("maxHeat"), 4)
  t.eq(st:get("heatCleared"), 1)
  ctx.bus:emit("jump", { id = "jump1", distance = 31, landed = true })
  ctx.bus:emit("jump", { id = "jump1", distance = 12, landed = false })
  t.eq(st:get("jumps"), 1)
  t.eq(st:get("longestJump"), 31)
  ctx.bus:emit("mission_end", { id = "a", result = "pass" })
  ctx.bus:emit("mission_end", { id = "a", result = "pass" })
  ctx.bus:emit("mission_end", { id = "b", result = "fail" })
  t.eq(st:get("missionsPassed"), 1, "a mission counts once")
  t.eq(st:get("missionsFailed"), 1)
  ctx.bus:emit("district_enter", { district = "gilt" })
  ctx.bus:emit("district_enter", { district = "gilt" })
  t.eq(st:count("districts"), 1)
  ctx.bus:emit("player_down", { kind = "nabbed" })
  ctx.bus:emit("player_down", { kind = "ko" })
  t.eq(st:get("arrests"), 1)
  t.eq(st:get("knockouts"), 1)
  ctx.bus:emit("vehicle_enter", { stolen = true })
  ctx.bus:emit("vehicle_enter", { stolen = false })
  t.eq(st:get("carsStolen"), 1)
  -- play: walking and driving are different distances, a teleport is neither, the air is timed
  local p = ctx.player
  local progress = ctx.plugins[1]
  progress.update(ctx, 0.05)
  p.x = 3
  progress.update(ctx, 0.05)
  t.near(st:get("onFoot"), 3, 0.001)
  p.x = 500
  progress.update(ctx, 0.05)
  t.near(st:get("onFoot"), 3, 0.001, "a respawn is not walking")
  local car = vehicle.new("marlin", 500, 0, 0, "red")
  car.v, car.airborne = 30, true
  p.car = car
  progress.update(ctx, 0.05)
  car.x = 510
  progress.update(ctx, 0.5)
  t.near(st:get("distance"), 10, 0.001)
  t.eq(st:get("topSpeed"), 108)
  t.near(st:get("airtime"), 0.55, 0.001)
  t.near(st:get("playSeconds"), 0.05 * 4 + 0.5, 0.001)
end)

-- ---------------------------------------------------------------- achievements

t.test("achievements: 40 of them with their own ids, readable names and a prize, each of a kind the checker understands", function()
  local ctx = game()
  local list = ctx.progress.achievements:list()
  t.eq(#list, 40)
  local seen = {}
  for _, a in ipairs(list) do
    t.truthy(not seen[a.id], a.id .. " is unique")
    seen[a.id] = true
    t.truthy(#a.name > 2 and #a.name <= 24, a.id .. " name fits a row")
    t.truthy(#a.desc <= 49, a.id .. " description fits 51 columns: " .. #a.desc)
    t.truthy(a.reward and a.reward > 0, a.id .. " pays something")
  end
  local defs = ctx.content:data("activities/achievements.lua")
  for _, d in ipairs(defs) do
    local kinds = 0
    for _, k in ipairs({ "stat", "set", "done", "story", "completion" }) do if d[k] ~= nil then kinds = kinds + 1 end end
    t.eq(kinds, 1, d.id .. " has exactly one condition")
  end
end)

t.test("achievements: each unlocks once, pays its prize once, announces itself once and survives a save", function()
  local ctx = game({ money = 0 })
  local got = {}
  ctx.bus:on("achievement", function(d) got[#got + 1] = d.id end, "test")
  local st = ctx.progress.stats
  local a = ctx.progress.achievements
  t.eq(a:check(), 0, "nothing yet")
  st:set("distance", 1200)
  t.eq(a:check(), 1)
  t.eq(a:check(), 0, "not again")
  t.eq(#got, 1)
  t.eq(got[1], "first_miles")
  t.eq(wallet.balance(ctx), 100, "the prize")
  st:set("distance", 20000)
  a:check()
  t.eq(#got, 2, "ten km also took road_tripper")
  -- save and load
  local fs, files = kit.memfs()
  ctx.save.progress.achievements.first_miles = ctx.save.progress.achievements.first_miles
  t.truthy(saveLib.write(fs, "s.dat", ctx.save))
  local back = saveLib.read(fs, "s.dat")
  local ctx2 = game({ save = back })
  t.truthy(ctx2.progress.achievements:has("first_miles"))
  t.eq(ctx2.progress.achievements:count(), 2)
  local before = wallet.balance(ctx2)
  ctx2.progress.stats:set("distance", 5000)
  ctx2.progress.achievements:check()
  t.eq(wallet.balance(ctx2), before, "a loaded save is not paid twice")
  t.eq(ctx2.progress.stats:get("distance"), 5000)
end)

t.test("achievements: an id another part announces from our list is marked, not paid for a second time", function()
  local ctx = game({ money = 0 })
  ctx.bus:emit("achievement", { id = "new_threads" })
  t.truthy(ctx.progress.achievements:has("new_threads"))
  t.eq(wallet.balance(ctx), 0)
  t.eq(ctx.progress.achievements:unlock("new_threads"), false)
  ctx.bus:emit("achievement", { id = "not_ours" })
  t.eq(ctx.progress.achievements:count(), 1)
end)

t.test("achievements: sets and tracker counts work (districts, stations, totems capped by what the city has)", function()
  local ctx = game({ money = 0 })
  local st = ctx.progress.stats
  for _, d in ipairs({ "a", "b", "c", "d" }) do st:member("districts", d) end
  ctx.progress.achievements:check()
  t.truthy(not ctx.progress.achievements:has("local_knowledge"), "four districts is not five")
  st:member("districts", "e")
  ctx.progress.achievements:check()
  t.truthy(ctx.progress.achievements:has("local_knowledge"))
  -- "ten jumps" in a city with four jumps asks for all four
  ctx.progress.completion:provide("jumps", function() return 4, 4 end)
  ctx.progress.achievements:check()
  t.truthy(ctx.progress.achievements:has("stunt_double"))
end)

-- ---------------------------------------------------------------- the 100% tracker

t.test("completion: the ten parts weigh exactly 100 and each part alone adds its own weight", function()
  local ctx = game()
  local config = ctx.progress.config
  local sum = 0
  for _, c in ipairs(config.categories) do sum = sum + c.weight end
  t.eq(sum, 100)
  t.eq(#config.categories, 10)
  for _, c in ipairs(config.categories) do
    local comp = completionLib.new(config)
    for _, o in ipairs(config.categories) do
      comp:provide(o.id, function() return o.id == c.id and 7 or 0, 7 end)
    end
    t.near(comp:percent(), c.weight, 1e-9, c.id .. " alone")
  end
  local all = completionLib.new(config)
  for _, o in ipairs(config.categories) do all:provide(o.id, function() return 13, 13 end) end
  t.eq(all:percent(), 100)
  t.eq(all:display(), "100")
  -- one item short never reads 100
  local almost = completionLib.new(config)
  for _, o in ipairs(config.categories) do almost:provide(o.id, function() return o.id == "totems" and 49 or 50, 50 end) end
  t.truthy(almost:percent() < 100 and almost:percent() > 99)
  t.truthy(almost:display() ~= "100", "display " .. almost:display())
  -- a part with nothing in it, or a count past its total, cannot break the sum
  local odd = completionLib.new(config)
  for _, o in ipairs(config.categories) do odd:provide(o.id, function() return 99, 0 end) end
  t.truthy(odd:percent() <= 100)
  local none = completionLib.new(config)
  t.eq(none:percent(), 0)
end)

t.test("completion: the real game's parts all report, and the story counts its jobs", function()
  local ctx = game()
  local res = ctx.progress.completion:compute()
  t.eq(#res.parts, 10)
  for _, p in ipairs(res.parts) do t.truthy(p.total >= 1, p.id .. " has a total") end
  t.eq(res.percent, 0)
  for i = 1, 12 do ctx.save.story.done["m" .. i] = true end
  t.near(ctx.progress.completion:percent(), 15, 1e-9, "half the story is 15 points")
  -- more story jobs than the config thought: the total grows, never past 100%
  for i = 1, 40 do ctx.save.story.done["n" .. i] = true end
  local parts = ctx.progress.completion:compute().parts
  t.eq(parts[1].done, parts[1].total)
end)

-- ---------------------------------------------------------------- settings

t.test("settings: defaults, steps, bounds, labels and hooks", function()
  local s = settingsLib.new({})
  t.eq(s:get("sound"), true)
  t.eq(s:label("quality"), "AUTO")
  s:cycle("quality", 1)
  t.eq(s:label("quality"), "HIGH")
  s:cycle("quality", -1)
  s:cycle("quality", -1)
  t.eq(s:label("quality"), "LOWEST", "it wraps")
  local seen = {}
  s:hook(function(name, v) seen[#seen + 1] = name .. "=" .. tostring(v) end)
  s:set("musicVolume", 0.8)
  s:cycle("musicVolume", -1)
  t.near(s:get("musicVolume"), 0.7, 1e-9)
  s:set("musicVolume", 5)
  t.eq(s:get("musicVolume"), 1, "clamped")
  s:set("musicVolume", -1)
  t.eq(s:get("musicVolume"), 0)
  t.eq(s:label("musicVolume"), "0%")
  s:cycle("units", 1)
  t.eq(s:label("units"), "MPH")
  s:cycle("sound", 1)
  t.eq(s:get("sound"), false)
  t.truthy(#seen >= 4)
  -- a broken saved value falls back to the default
  local bad = settingsLib.new({ quality = "ultra", musicVolume = "loud", units = 5, sound = "yes" })
  t.eq(bad:get("quality"), "auto")
  t.eq(bad:get("musicVolume"), 0.8)
  t.eq(bad:get("units"), "kmh")
  t.eq(bad:get("sound"), false, "only true is true")
end)

t.test("settings: changed in the menu, written at once, and applied again after a restart (sound, music, volume, quality, hints)", function()
  local fs, files = kit.memfs()
  local music = kit.fakeMusic()
  package.loaded["music"] = music
  local ctx = game({ fs = fs })
  ctx.eui.titleShown = true
  ctx.ui.push("pause")
  kit.frame(ctx)
  t.truthy(ctx.screen.find("Paused"), "the pause menu")
  kit.press(ctx, "down", 3) -- a tap and three repeats: Resume > Map > Progress > Achievements > Settings
  kit.frame(ctx)
  kit.press(ctx, "enter")
  kit.frame(ctx)
  t.eq(ctx.ui.top().name, "e_menu")
  kit.frame(ctx)
  t.truthy(ctx.screen.find("Music volume"), "the settings menu")
  kit.press(ctx, "down", 1) -- Music volume (two downs from Sound effects)
  kit.frame(ctx)
  kit.press(ctx, "left", 2) -- 3 steps: 0.8 -> 0.5
  kit.frame(ctx)
  t.near(ctx.save.settings.musicVolume, 0.5, 1e-9)
  t.near(music.volume, 0.5, 1e-9, "applied now")
  kit.press(ctx, "down", 3) -- quality: HIGH, down to Key hints
  kit.frame(ctx)
  kit.press(ctx, "left")
  kit.frame(ctx)
  t.truthy(files["saltgate_save2.dat"], "written to the save at once")
  -- a restart: a fresh game from the file
  local back = saveLib.read(fs, "saltgate_save2.dat")
  t.near(back.settings.musicVolume, 0.5, 1e-9, "persisted")
  local music2 = kit.fakeMusic()
  package.loaded["music"] = music2
  local ctx2 = game({ save = back })
  t.near(music2.volume, 0.5, 1e-9, "applied at start")
  t.near(ctx2.eui.settings:get("musicVolume"), 0.5, 1e-9)
  -- sound off silences the music, back on restores it
  ctx2.eui.settings:set("sound", false)
  t.eq(music2.enabled, false)
  ctx2.eui.settings:set("sound", true)
  t.eq(music2.enabled, true)
  ctx2.eui.settings:set("music", false)
  t.eq(music2.enabled, false)
  -- quality pinned: the budget cannot move it, AUTO gives it back
  local levels = {}
  ctx2.bus:on("quality", function(d) levels[#levels + 1] = d.level end, "test")
  ctx2.eui.settings:set("quality", 3)
  t.eq(ctx2.budget.quality, 3)
  for _ = 1, 300 do ctx2.budget:frame(0.5) end -- very fast frames would step it up
  t.eq(ctx2.budget.quality, 3, "pinned")
  ctx2.eui.settings:set("quality", "auto")
  for _ = 1, 300 do ctx2.budget:frame(0.5) end
  t.truthy(ctx2.budget.quality < 3, "auto steps back up")
  package.loaded["music"] = nil
end)

-- ---------------------------------------------------------------- the radio

local function stations()
  local ctx = game()
  return ctx.content:data("activities/radio.lua")
end

t.test("radio: four stations, each with a real track of the soundtrack, a name, a frequency and lines that fit", function()
  local data = stations()
  t.eq(#data.stations, 4)
  local player = require("music.player")
  local tracks = {}
  for _, n in ipairs(player.TRACKS) do tracks[n] = true end
  local names, freqs = {}, {}
  for _, s in ipairs(data.stations) do
    t.truthy(tracks[s.track], s.id .. " plays a track that exists: " .. s.track)
    t.truthy(not names[s.name] and not freqs[s.freq], "unique")
    names[s.name], freqs[s.freq] = true, true
    t.truthy(#s.lines >= 4)
    for _, line in ipairs(s.lines) do
      t.truthy(#(s.dj .. ": " .. line) <= 98, "DJ line wraps in two rows at most: " .. line)
    end
  end
end)

t.test("radio: R steps through the stations and off, the cue follows, a quiet car is silent, the soundtrack takes over otherwise", function()
  local music = kit.fakeMusic()
  local r = radioLib.new({ data = stations(), music = music, station = 1 })
  r:setState({ car = false, heat = 0 })
  r:update(0.05)
  t.eq(music.last(), "free_roam")
  r:setState({ car = true, heat = 0 })
  r:update(0.05)
  t.eq(music.last(), "drive", "station 1 plays its track")
  r:next()
  t.eq(music.last(), "roam_gilt")
  r:next()
  t.eq(music.last(), "roam_lantern")
  r:next()
  t.eq(music.last(), "roam_cinder")
  local stops = music.stops
  r:next()
  t.eq(r.station, 0)
  t.eq(r:label(), "radio off")
  t.truthy(music.stops > stops, "radio off is silence")
  r:next()
  t.eq(r.station, 1, "and round again")
  -- the law
  r:setState({ car = true, heat = 1 })
  r:update(0.05)
  t.eq(music.last(), "heat_low")
  r:setState({ car = true, heat = 4 })
  r:update(0.05)
  t.eq(music.last(), "heat_high")
  r:setState({ car = true, heat = 0 })
  r:update(0.05)
  t.eq(music.last(), "drive", "back to the station when the heat is off")
  -- jobs and the title
  r:setState({ car = false, heat = 0, mission = true })
  r:update(0.05)
  t.eq(music.last(), "job")
  r:setState({ title = true })
  r:update(0.05)
  t.eq(music.last(), "title")
  -- no repeats: the same cue is not sent every frame
  local n = #music.cues
  for _ = 1, 20 do r:update(0.05) end
  t.eq(#music.cues, n)
  r:setState({ car = false, heat = 0, district = "brine" })
  t.eq(music.district, "brine")
end)

t.test("radio: the DJ talks soon after tuning and then now and then, only in a car with the radio on", function()
  local lines = {}
  local r = radioLib.new({ data = stations(), music = kit.fakeMusic(), station = 1, onLine = function(s, text) lines[#lines + 1] = s.id .. ":" .. text end })
  r:setState({ car = true, heat = 0 })
  for _ = 1, 40 do r:update(0.05) end
  t.truthy(#lines >= 1, "a line within a couple of seconds")
  local first = #lines
  for _ = 1, 100 do r:update(0.5) end -- 50 seconds: another
  t.truthy(#lines > first)
  r:next()
  local n = #lines
  for _ = 1, 40 do r:update(0.05) end
  t.truthy(#lines > n, "the new station's DJ")
  t.truthy(lines[#lines]:find("^gilt:"), "in its own voice")
  local quiet = #lines
  r:setState({ car = false, heat = 0 })
  for _ = 1, 400 do r:update(0.5) end
  t.eq(#lines, quiet, "no DJ on foot")
  r:tune(0)
  r:setState({ car = true, heat = 0 })
  for _ = 1, 400 do r:update(0.5) end
  t.eq(#lines, quiet, "no DJ with the radio off")
end)

t.test("radio: in the game R changes the station in a car, shows it, ignores R on foot, and hearing all four is an achievement", function()
  local music = kit.fakeMusic()
  package.loaded["music"] = music
  local ctx = game()
  local car = vehicle.new("marlin", 0, 0, 0, "red")
  ctx.player.car = car
  ctx.cars[1] = car
  kit.frame(ctx)
  t.eq(ctx.radio.station, 1)
  t.truthy(ctx.hud.radioLine():find("Gull FM"), ctx.hud.radioLine())
  kit.press(ctx, "r")
  kit.frame(ctx)
  t.eq(ctx.radio.station, 2)
  t.eq(music.last(), "roam_gilt")
  t.truthy(ctx.screen.find("Gilt Heights Smooth"), "the toast names the station")
  ctx.player.car = nil
  kit.press(ctx, "r")
  kit.frame(ctx)
  t.eq(ctx.radio.station, 2, "R does nothing on foot")
  t.eq(music.last(), "free_roam")
  -- the station is remembered
  t.eq(ctx.save.settings.station, 2)
  -- hearing: three seconds on each
  ctx.player.car = car
  kit.frame(ctx)
  for i = 1, 4 do
    ctx.radio:tune(i)
    for _ = 1, 70 do ctx.radio:update(0.05) end
  end
  t.eq(ctx.progress.stats:count("stations"), 4)
  t.truthy(ctx.progress.achievements:has("dial_hopper"))
  package.loaded["music"] = nil
end)

t.test("radio: with no music module the radio still works and nothing breaks", function()
  package.loaded["music"] = nil
  local saved = package.preload["music"]
  package.preload["music"] = function() error("no music here") end
  local ok, ctx = pcall(game)
  package.preload["music"] = saved
  t.truthy(ok, tostring(ctx))
  t.truthy(ctx.radio, "the radio exists")
  ctx.player.car = vehicle.new("marlin", 0, 0, 0, "red")
  kit.frame(ctx)
  kit.press(ctx, "r")
  kit.frame(ctx)
  t.eq(ctx.radio.station, 2)
end)
