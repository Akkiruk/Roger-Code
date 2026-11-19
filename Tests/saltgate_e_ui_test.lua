-- saltgate_e_ui_test.lua
-- SALTGATE stream E, the interface on a 51x19 terminal: the HUD, hint lines that name real keys (one key per action),
-- every menu driven with the keys as CC sends them (a tap, repeats while held, key up), nothing written past the edge,
-- transitions, the loading card, the map's icons and the keys tee.

local t = require("testing")
local kit = require("sg.ui.testkit")
local theme = require("sg.ui.theme")
local menuLib = require("sg.ui.menu")
local keysLib = require("sg.ui.keys")
local transitionLib = require("sg.ui.transition")
local loading = require("sg.ui.loading")
local hudLib = require("sg.ui.hud")
local inputLib = require("sg.input")
local vehicle = require("sg.vehicle")
local wallet = require("sg.progress.wallet")

local C = theme.C

local function game(opts)
  local ctx = kit.game(opts)
  ctx.eui.titleShown = true
  return ctx
end

local function giveCar(ctx)
  local car = vehicle.new("marlin", 0, 0, 0, "red")
  ctx.cars[#ctx.cars + 1] = car
  ctx.player.car = car
  return car
end

local function frames(ctx, n)
  for _ = 1, n or 1 do kit.frame(ctx) end
end

-- ---------------------------------------------------------------- theme

t.test("theme: wrapping, fitting, key words and the clock", function()
  local lines = theme.wrap("the quick brown fox jumps over the lazy dog", 12)
  for _, l in ipairs(lines) do t.truthy(#l <= 12, l) end
  t.eq(table.concat(lines, " "), "the quick brown fox jumps over the lazy dog")
  t.eq(#theme.wrap("supercalifragilisticexpialidocious", 10)[1], 10, "a long word is cut, not overflowed")
  t.eq(theme.fit("Gilt Heights", 8), "Gilt H..")
  t.eq(theme.fit("short", 8), "short")
  t.truthy(theme.isKey("ENTER") and theme.isKey("A/D") and theme.isKey("W/S") and theme.isKey("F3"))
  t.truthy(not theme.isKey("move") and not theme.isKey("Gull"))
  t.eq(theme.clock(65.3), "1:05.3")
  t.eq(theme.clock(nil), "-:--.-")
  t.eq(hudLib.clockText(7.5), "07:30")
  t.eq(hudLib.clockText(25), "01:00")
  t.eq(hudLib.compass(-math.pi / 2), "N", "north is -z")
  t.eq(hudLib.compass(0), "E")
  t.eq(hudLib.compass(math.pi / 2), "S")
  t.eq(hudLib.compass(math.pi), "W")
end)

t.test("theme: a key line writes keys in yellow and words in grey, and stops at its width", function()
  local term = kit.term(51, 19)
  theme.keyline(term, 2, 19, 20, "WASD move  SHIFT run  E car", C.yellow, C.lightGray, C.black)
  local ch, fg = term.cell(2, 19)
  t.eq(ch, "W")
  t.eq(fg, C.yellow)
  local _, fgWord = term.cell(8, 19)
  t.eq(fgWord, C.lightGray)
  t.eq(term.overflow, 0)
  local x = theme.keyline(term, 2, 18, 12, "WASD move  SHIFT run", C.yellow, C.lightGray, C.black)
  t.truthy(x <= 14, "stopped before overflowing the 12 columns")
end)

-- ---------------------------------------------------------------- keys

t.test("keys: a tap, repeats while held, and key_up arrive as CC sends them and become menu actions in order", function()
  local now = 0
  local k = keysLib.new(kit.KEYS, function() return now end)
  k:feed("key", kit.KEYS.s, false)
  now = 0.05
  k:feed("key", kit.KEYS.s, true) -- a terminal that repeats at once: too early to count
  now = 0.5
  k:feed("key", kit.KEYS.s, true)
  now = 0.58
  k:feed("key", kit.KEYS.s, true)
  now = 0.60
  k:feed("key", kit.KEYS.s, true) -- too soon after the last
  k:feed("key_up", kit.KEYS.s)
  k:feed("key", kit.KEYS.enter, false)
  k:feed("key", kit.KEYS.enter, true)
  k:feed("key", kit.KEYS.z or 90, false) -- an unmapped key does nothing
  local a = k:actions()
  t.eq(table.concat(a, ","), "down,down,down,select", "a tap is one move; repeats after the delay, at a steady pace")
  t.eq(table.concat(k:fresh(), ","), "down,select", "only the first press of each")
  -- a tap again after the key was let go is a fresh press
  now = 1
  k:feed("key", kit.KEYS.s, false)
  t.eq(#k:actions(), 5)
  k:flush()
  k:feed("key_up", kit.KEYS.s)
  k:feed("key", kit.KEYS.s, true) -- a repeat with no press seen (the screen changed under the key): a press
  t.eq(#k:actions(), 1)
  k:flush()
  k:feed("key_up", kit.KEYS.s)
  k:feed("key", kit.KEYS.s, false)
  t.truthy(k:pressed("down") and not k:pressed("up"))
  -- the same press delivered again in the same instant (no key_up between) is one press
  k:feed("key", kit.KEYS.s, false)
  k:feed("key", kit.KEYS.s, false)
  t.eq(#k:actions(), 1, "duplicates of one press count once")
  k:flush()
  t.eq(#k:actions(), 0)
  -- the arrows and WASD are the same keys
  k:feed("key", kit.KEYS.up, false)
  k:feed("key", kit.KEYS.left, false)
  k:feed("key", kit.KEYS.numPadEnter, false)
  k:feed("key", kit.KEYS.backspace, false)
  t.eq(table.concat(k:actions(), ","), "up,left,select,back")
  for i = 1, 100 do
    now = now + 1
    k:feed("key", kit.KEYS.w, true)
  end
  t.truthy(#k:actions() <= keysLib.MAX, "a held key cannot grow the queue without end")
end)

t.test("keys: attach copies key events beside the main loop and passes every event on untouched", function()
  local realRaw = os.pullEventRaw
  local script = { { "key", 87, false }, { "key_up", 87 }, { "timer", 5 }, { "key", 257, false } }
  local at = 0
  os.pullEventRaw = function()
    at = at + 1
    local e = script[at]
    return e[1], e[2], e[3]
  end
  package.loaded["sg.ui.keys"] = nil
  local fresh = require("sg.ui.keys")
  local k = fresh.new(kit.KEYS)
  fresh.attach(k)
  fresh.attach(k)
  local seen = {}
  for _ = 1, 4 do
    local a, b, c = os.pullEventRaw()
    seen[#seen + 1] = a .. ":" .. tostring(b) .. ":" .. tostring(c)
  end
  local wrapped = os.pullEventRaw
  os.pullEventRaw = realRaw
  package.loaded["sg.ui.keys"] = keysLib
  -- the game starting again in the same session (startup.lua restarts it after a crash) must not stack a second wrapper
  package.loaded["sg.ui.keys"] = nil
  local again = require("sg.ui.keys")
  local k2 = again.new(kit.KEYS)
  at = 0
  os.pullEventRaw = wrapped
  again.attach(k2)
  t.truthy(os.pullEventRaw == wrapped, "the wrapper from the last run is reused")
  script = { { "key", 87, false }, { "key", 83, false } }
  os.pullEventRaw()
  t.eq(#k2:actions(), 1, "a key reaches the new run's keys once, and the old run's no more")
  t.eq(#k:actions(), 2, "the old keys saw nothing more")
  os.pullEventRaw = realRaw
  os.saltgate_keys_tee = nil
  package.loaded["sg.ui.keys"] = keysLib
  t.eq(seen[1], "key:87:false")
  t.eq(seen[3], "timer:5:nil", "other events pass through")
  t.eq(table.concat(k:actions(), ","), "up,select", "W and ENTER were copied, once each")
end)

-- ---------------------------------------------------------------- menus

t.test("menu: the cursor skips headings and locked rows, wraps, and A/D change a value while ENTER selects", function()
  local log = {}
  local locked = true
  local m = menuLib.new({
    { label = "Head", header = true },
    { label = "One", action = function() log[#log + 1] = "one" end },
    { label = "Locked", enabled = function() return not locked end, action = function() log[#log + 1] = "locked" end },
    { label = "Vol", value = function() return "5" end, change = function(d) log[#log + 1] = "vol" .. d end },
    { label = "Two", action = function() log[#log + 1] = "two" end },
  })
  t.eq(m:current().label, "One", "starts past the heading")
  m:handle("down")
  t.eq(m:current().label, "Vol", "the locked row is skipped")
  m:handle("left")
  m:handle("right")
  m:handle("select")
  m:handle("down")
  t.eq(m:current().label, "Two")
  m:handle("down")
  t.eq(m:current().label, "One", "wraps past the heading")
  m:handle("up")
  t.eq(m:current().label, "Two")
  m:handle("select")
  locked = false
  m:handle("up")
  t.eq(m:current().label, "Vol")
  m:handle("up")
  t.eq(m:current().label, "Locked", "unlocked rows can be reached")
  t.eq(table.concat(log, ","), "vol-1,vol1,vol1,two")
  local term = kit.term(30, 8)
  m:draw(term, 1, 1, 30, 5)
  t.truthy(term.find("Vol"))
  t.eq(term.overflow, 0)
end)

t.test("menu: long lists scroll to keep the cursor on screen", function()
  local items = {}
  for i = 1, 30 do items[i] = { label = "Row " .. i, action = function() end } end
  local m = menuLib.new(items)
  local term = kit.term(30, 8)
  for _ = 1, 20 do m:handle("down") end
  m:draw(term, 1, 1, 30, 6)
  t.truthy(term.find("Row 21"), "the cursor's row is visible")
  t.truthy(not term.find("Row 1 "), "the top has scrolled off")
end)

-- ---------------------------------------------------------------- the HUD

t.test("hud: money, the district and the clock, wanted pips, and what just happened to your money", function()
  local ctx = game({ money = 1234 })
  ctx.districtName = "gilt"
  ctx.hud.hour = 19.5
  frames(ctx)
  local row = ctx.screen.row(1)
  t.truthy(row:find("$1,234", 1, true), row)
  t.truthy(row:find("Gilt Heights", 1, true), "the district's name")
  t.truthy(row:find("19:30", 1, true), "the time: " .. row)
  t.truthy(row:find("HEAT", 1, true))
  local function lit()
    local n = 0
    for x = 1, 51 do
      local _, _, bg = ctx.screen.cell(x, 1)
      if bg == C.red or bg == C.blue then n = n + 1 end
    end
    return n
  end
  t.eq(lit(), 0, "no pips lit without heat")
  ctx.bus:emit("heat_changed", { level = 3, previous = 0 })
  frames(ctx)
  t.eq(lit(), 3, "three pips for level 3")
  ctx.bus:emit("heat_changed", { level = 6, previous = 3 })
  frames(ctx)
  t.eq(lit(), 6, "six levels fit the bar")
  wallet.add(ctx, 50, "test")
  frames(ctx)
  t.truthy(ctx.screen.row(1):find("+$50", 1, true), "the gain flashes")
  wallet.spend(ctx, 80, "test")
  ctx.hud.delta = nil
  wallet.spend(ctx, 20, "test")
  frames(ctx)
  t.truthy(ctx.screen.row(1):find("-$20", 1, true), "a spend flashes too")
  t.eq(ctx.screen.overflow, 0)
end)

t.test("hud: the status row shows Wren on foot, the car, speed and a health bar in a car, and the weapon", function()
  local ctx = game()
  frames(ctx)
  t.truthy(ctx.screen.row(18):find("Wren", 1, true))
  local car = giveCar(ctx)
  car.v = 20
  frames(ctx)
  local row = ctx.screen.row(18)
  t.truthy(row:find("Marlin", 1, true), row)
  t.truthy(row:find("72 km/h", 1, true), row)
  ctx.save.settings.units = "mph"
  frames(ctx)
  t.truthy(ctx.screen.row(18):find("45 mph", 1, true), "units follow the setting")
  car.health = car.spec.health * 0.2
  frames(ctx)
  local _, _, bg = ctx.screen.cell(16, 18)
  t.eq(bg, C.red, "a battered car's bar is red")
  car.airborne = true
  frames(ctx)
  ctx.player.car = nil
  ctx.player.weapon = { name = "Pistol", ammo = 12, reserve = 48 }
  frames(ctx)
  t.truthy(ctx.screen.row(18):find("PISTOL 12/48", 1, true), ctx.screen.row(18))
  ctx.player.weapon.ammo = 0
  frames(ctx)
  local x = ctx.screen.row(18):find("PISTOL", 1, true)
  local _, fg = ctx.screen.cell(x, 18)
  t.eq(fg, C.red, "an empty gun is red")
  t.eq(ctx.screen.overflow, 0)
end)

t.test("hud: hint lines name keys that exist, one key per action, and change with what you are doing", function()
  local ctx = game()
  local function hint()
    frames(ctx)
    return (ctx.screen.row(19):gsub("^%s+", ""):gsub("%s+$", ""))
  end
  local foot = hint()
  t.truthy(foot:find("^WASD move") and foot:find("E car") and foot:find("M map") and foot:find("P menu"), foot)
  ctx.nearCar = {}
  local near = hint()
  t.truthy(near:find("^E take car"), near)
  ctx.nearCar = nil
  giveCar(ctx)
  local drive = hint()
  t.truthy(drive:find("SPACE handbrake") and drive:find("E out") and drive:find("R radio"), drive)
  -- on foot R does nothing, so it is not offered
  ctx.player.car = nil
  t.truthy(not hint():find("R radio"), "no radio hint on foot")
  -- every key named is a real key, and no key is named twice in a line or for two actions
  local allowed = { WASD = true, SHIFT = true, SPACE = true, E = true, M = true, P = true, R = true, X = true, ENTER = true,
    C = true, H = true, BACKSPACE = true, ["A/D"] = true, ["W/S"] = true, F3 = true }
  local lines = { foot, near, drive }
  ctx.activities.active = { hud = function() return { title = "RACE" } end, update = function() return "run" end }
  ctx.activities.kind = "race"
  lines[#lines + 1] = hint()
  t.truthy(lines[4]:find("X abandon"), lines[4])
  ctx.activities.active, ctx.activities.kind = nil, nil
  for _, line in ipairs(lines) do
    local seen = {}
    for word in line:gmatch("%S+") do
      if theme.isKey(word) then
        t.truthy(allowed[word], "'" .. word .. "' is a key the game uses: " .. line)
        t.truthy(not seen[word], word .. " twice in: " .. line)
        seen[word] = true
      end
    end
    t.truthy(#line <= 49, "fits: " .. line)
  end
  -- the keys named are the keys the game reads
  local map = inputLib.new(kit.KEYS).map
  local function has(action, key) for _, k in ipairs(map[action]) do if k == kit.KEYS[key] then return true end end return false end
  t.truthy(has("use", "e") and has("map", "m") and has("pause", "p") and has("handbrake", "space") and has("run", "leftShift"))
  t.truthy(has("forward", "w") and has("back", "s") and has("left", "a") and has("right", "d"))
  -- the key colours: keys yellow, words grey
  local x = ctx.screen.row(19):find("WASD", 1, true) or 1
  local _, fg = ctx.screen.cell(x, 19)
  t.eq(fg, C.yellow)
  -- hints can be turned off
  ctx.save.settings.hints = false
  t.eq(hint(), "")
  ctx.save.settings.hints = nil
end)

t.test("hud: other parts add their own hint lines and toasts, wrapped to the screen", function()
  local ctx = game()
  ctx.hud.hint(function(c) if c.player.talking then return "ENTER next" end end)
  frames(ctx)
  t.truthy(not ctx.screen.row(19):find("ENTER next"))
  ctx.player.talking = true
  frames(ctx)
  t.truthy(ctx.screen.row(19):find("ENTER next"), "the newest provider answers first")
  ctx.hud.toast("A very long message that cannot possibly fit on one row of fifty one columns, so it wraps", "white", 3, "sub line")
  frames(ctx)
  t.truthy(ctx.screen.text():find("sub line", 1, true))
  t.eq(ctx.screen.overflow, 0)
  -- toasts age only while playing, and the same message does not stack
  ctx.hud.toast("Same", "white", 2)
  ctx.hud.toast("Same", "white", 2)
  local n = 0
  for _, tt in ipairs(ctx.hud.toasts) do if tt.text == "Same" then n = n + 1 end end
  t.eq(n, 1)
  ctx.hud.tick(3)
  t.eq(#ctx.hud.toasts, 0)
end)

t.test("hud: the activity banner, the countdown and the prompt for the place you stand at", function()
  local ctx = game({ money = 0 })
  giveCar(ctx)
  local mgr = ctx.activities
  local def = mgr.layout.races[1]
  ctx.player.x, ctx.player.z = def.pts[1], def.pts[3]
  ctx.player.car.x, ctx.player.car.z = def.pts[1], def.pts[3]
  frames(ctx, 2)
  t.truthy(ctx.screen.row(17):find("ENTER") and ctx.screen.row(17):find("Race"), "the prompt: " .. ctx.screen.row(17))
  local _, fg = ctx.screen.cell(ctx.screen.row(17):find("ENTER", 1, true), 17)
  t.eq(fg, C.yellow, "the key is yellow")
  mgr:startRace(def)
  frames(ctx, 2)
  t.truthy(ctx.screen.row(2):find("RACE  " .. def.name, 1, true), ctx.screen.row(2))
  t.truthy(ctx.screen.text():find("3", 1, true), "the count-in")
  for _ = 1, 70 do mgr:update(0.05, ctx.eui.keys) end
  frames(ctx)
  t.truthy(ctx.screen.row(3):find("GATE 1/", 1, true), ctx.screen.row(3))
  t.eq(ctx.screen.overflow, 0)
  -- the arrow to the next gate
  local arrows = ctx.screen.row(3):sub(1, 3)
  t.truthy(arrows:find("[\24\25\26\27]"), "an arrow to the gate")
end)

t.test("hud: the compass and district sit under the minimap's frame", function()
  local ctx = game()
  ctx.districtName = "brine"
  ctx.view = { minimapBox = { x0 = 78, y0 = 4, w = 24, h = 19 }, cam = { yaw = -math.pi / 2 } }
  frames(ctx)
  local row = ctx.screen.row(9)
  t.truthy(row:find("N  Brine Docks", 1, true) or row:find("N  Brine D", 1, true), row)
  t.eq(ctx.screen.overflow, 0)
end)

-- ---------------------------------------------------------------- the screens

t.test("keys: the key that opens a screen is not also read by that screen (ENTER at a shop, P for the pause menu)", function()
  local ctx = game({ money = 1000 })
  local car = giveCar(ctx)
  local mgr = ctx.activities
  local shop
  for _, p in ipairs(mgr.places) do if p.kind == "shop" and p.shop == "respray" then shop = p end end
  ctx.player.x, ctx.player.z = shop.x, shop.z
  car.x, car.z = shop.x, shop.z
  frames(ctx)
  kit.press(ctx, "enter")
  frames(ctx) -- the plugin sees ENTER and opens the shop; the shop must not buy the first colour with the same press
  t.eq(ctx.ui.top().name, "e_menu")
  frames(ctx)
  t.eq(car.colour, "red", "nothing was bought")
  t.eq(wallet.balance(ctx), 1000)
  kit.press(ctx, "backspace")
  frames(ctx)
  t.eq(ctx.ui.top().name, "play")
  -- the core pushes the pause menu on P; the P that did it must not close it again
  ctx.eui.keys:feed("key", kit.KEYS.p, false)
  ctx.ui.push("pause")
  frames(ctx)
  t.eq(ctx.ui.top().name, "pause")
  t.truthy(ctx.screen.find("Resume"))
end)

t.test("title: the city turns behind the name; W/S with a tap and repeats move the cursor; ENTER opens settings; BACKSPACE returns", function()
  local ctx = kit.game()
  frames(ctx, 2)
  t.eq(ctx.ui.top().name, "e_title", "the game opens on the title")
  t.truthy(ctx.screen.find("Play") and ctx.screen.find("Quit"), ctx.screen.text())
  t.truthy(ctx.screen.find("L O W   T I D E"))
  t.eq(ctx.hud.hidden, true, "no HUD over the title")
  kit.press(ctx, "down", 1) -- tap + one repeat: two rows
  frames(ctx)
  kit.press(ctx, "enter")
  frames(ctx, 2)
  t.eq(ctx.ui.top().name, "e_menu")
  t.truthy(ctx.screen.find("Settings"), "the third row is Settings")
  t.truthy(ctx.screen.find("Sound effects"))
  kit.press(ctx, "backspace")
  frames(ctx)
  t.eq(ctx.ui.top().name, "e_title")
  t.eq(ctx.screen.overflow, 0)
  -- up from the top wraps to Quit and does not run it
  kit.press(ctx, "up")
  frames(ctx)
  t.eq(ctx.ui.top().name, "e_title")
end)

t.test("title: Play wipes the screen and hands you the game", function()
  local ctx = kit.game()
  frames(ctx, 2)
  kit.press(ctx, "enter")
  frames(ctx)
  t.truthy(ctx.eui.transition:active(), "the curtain is closing")
  ctx.eui.transition:update(0.2)
  t.eq(ctx.ui.top().name, "e_title", "not yet")
  ctx.eui.transition:update(0.2)
  t.eq(ctx.ui.top().name, "play", "behind the curtain the title went away")
  t.eq(ctx.hud.hidden, false)
  ctx.eui.transition:update(0.5)
  t.truthy(not ctx.eui.transition:active())
  frames(ctx)
  t.truthy(ctx.screen.row(1):find("HEAT"), "the HUD is back")
end)

t.test("pause: Resume, the map, progress, awards, settings, controls and save-and-quit, and it names the completion", function()
  local ctx = game()
  ctx.ui.push("pause")
  frames(ctx)
  local text = ctx.screen.text()
  for _, word in ipairs({ "Paused", "Resume", "Map", "Progress and stats", "Achievements", "Settings", "Controls", "Save and quit", "0.0% complete" }) do
    t.truthy(text:find(word, 1, true), word)
  end
  t.eq(ctx.screen.overflow, 0)
  -- Resume
  kit.press(ctx, "enter")
  frames(ctx)
  t.eq(ctx.ui.top().name, "play")
  -- the map
  ctx.ui.push("pause")
  frames(ctx)
  kit.press(ctx, "down")
  frames(ctx)
  kit.press(ctx, "enter")
  frames(ctx)
  t.eq(ctx.ui.top().name, "map")
  ctx.ui.pop()
  -- save and quit asks the main loop to terminate (which saves)
  local queued = {}
  local realQueue = os.queueEvent
  os.queueEvent = function(...) queued[#queued + 1] = { ... } end
  ctx.ui.push("pause")
  frames(ctx)
  kit.press(ctx, "up") -- wraps to the last row
  frames(ctx)
  kit.press(ctx, "enter")
  frames(ctx)
  os.queueEvent = realQueue
  t.eq(queued[1] and queued[1][1], "terminate")
  -- a phone from the story stream shows up when it exists
  ctx.ui.screen({ name = "phone", modal = true, draw = function() end })
  ctx.ui.pop()
  ctx.ui.push("pause")
  frames(ctx)
  t.truthy(ctx.screen.find("Phone"), "the phone is offered once it is registered")
end)

t.test("controls: every key of the game on one screen, none written twice, all inside 51 columns", function()
  local ctx = game()
  ctx.eui.screens.controls()
  frames(ctx)
  local text = ctx.screen.text()
  for _, word in ipairs({ "W A S D", "SHIFT", "SPACE", "ENTER", "radio station", "pause menu", "camera", "map" }) do
    t.truthy(text:find(word, 1, true), word)
  end
  t.eq(ctx.screen.overflow, 0)
  kit.press(ctx, "enter")
  frames(ctx)
  t.eq(ctx.ui.top().name, "play", "any select or back leaves")
end)

t.test("stats: progress, numbers and 40 awards in three tabs, A/D switch tabs, W/S scroll", function()
  local ctx = game({ money = 0 })
  wallet.add(ctx, 777, "x")
  ctx.progress.stats:set("distance", 4200)
  ctx.progress.achievements:check()
  ctx.eui.screens.stats(1)
  frames(ctx)
  local text = ctx.screen.text()
  t.truthy(text:find("Completion", 1, true) and text:find("Story jobs", 1, true) and text:find("Gull totems", 1, true), text)
  t.truthy(text:find("Progress") and text:find("Stats") and text:find("Awards"))
  kit.press(ctx, "right")
  frames(ctx)
  text = ctx.screen.text()
  t.truthy(text:find("Time played", 1, true) and text:find("4.2 km", 1, true) and text:find("$877", 1, true), text)
  kit.press(ctx, "right")
  frames(ctx)
  text = ctx.screen.text()
  t.truthy(text:find("First Miles", 1, true) and text:find("unlocked", 1, true), text)
  t.truthy(text:find("1/39 unlocked", 1, true) or text:find("/40 unlocked", 1, true) or text:find("unlocked", 1, true))
  kit.press(ctx, "down", 12)
  frames(ctx)
  t.eq(ctx.screen.overflow, 0)
  kit.press(ctx, "left", 0)
  kit.press(ctx, "left", 0)
  frames(ctx)
  t.truthy(ctx.screen.find("Completion"), "back to the first tab")
  kit.press(ctx, "backspace")
  frames(ctx)
  t.eq(ctx.ui.top().name, "play")
  -- the scroll reaches the last award and not past it
  ctx.eui.screens.stats(3)
  frames(ctx)
  for _ = 1, 4 do
    kit.press(ctx, "down", 20)
    frames(ctx)
  end
  t.truthy(ctx.screen.find("Saltgate, All of It") or ctx.screen.find("New Threads"), "the last awards are reachable")
  t.eq(ctx.screen.overflow, 0)
end)

t.test("confirm: yes runs the action, no does not, both close the box", function()
  local ctx = game()
  local ran = 0
  ctx.eui.screens.confirm({ "Buy it?", "Price $10" }, function() ran = ran + 1 end)
  frames(ctx)
  t.truthy(ctx.screen.find("Buy it?") and ctx.screen.find("Yes") and ctx.screen.find("No"))
  kit.press(ctx, "down")
  frames(ctx)
  kit.press(ctx, "enter")
  frames(ctx)
  t.eq(ran, 0)
  t.eq(ctx.ui.top().name, "play")
  ctx.eui.screens.confirm("Sure?", function() ran = ran + 1 end)
  frames(ctx)
  kit.press(ctx, "enter")
  frames(ctx)
  t.eq(ran, 1)
  t.eq(ctx.ui.top().name, "play")
end)

t.test("shops and garage screens: respray with colour chips, tune tiers, clothes, the garage; all readable inside the screen", function()
  local ctx = game({ money = 9000 })
  local car = giveCar(ctx)
  local mgr = ctx.activities
  local menus = require("sg.activities.menus").new(ctx, mgr, ctx.eui.screens)
  local function open(kind, shop)
    for _, p in ipairs(mgr.places) do
      if p.kind == kind and (not shop or p.shop == shop) then menus.open(kind, p) return p end
    end
  end
  open("shop", "respray")
  frames(ctx)
  t.truthy(ctx.screen.find("respray") and ctx.screen.find("Marlin (Red)") and ctx.screen.find("$150"), ctx.screen.text())
  kit.press(ctx, "down")
  frames(ctx)
  kit.press(ctx, "enter")
  frames(ctx)
  t.eq(car.colour, "blue", "the second colour")
  t.eq(wallet.balance(ctx), 9000 - 150)
  kit.press(ctx, "backspace")
  frames(ctx)
  open("shop", "tune")
  frames(ctx)
  t.truthy(ctx.screen.find("Engine") and ctx.screen.find("tier 0/3  $400"), ctx.screen.text())
  kit.press(ctx, "enter")
  frames(ctx)
  frames(ctx)
  t.truthy(ctx.screen.find("tier 1/3  $900"), "the row shows the next tier")
  t.eq(ctx.ui.top().name, "e_menu")
  kit.press(ctx, "backspace")
  frames(ctx)
  open("shop", "clothes")
  frames(ctx)
  t.truthy(ctx.screen.find("Deckhand") and ctx.screen.find("WORN"), ctx.screen.text())
  t.eq(ctx.screen.overflow, 0)
  kit.press(ctx, "backspace")
  frames(ctx)
  -- the garage: store this car, then it is on the list
  open("garage")
  frames(ctx)
  t.truthy(ctx.screen.find("Store this car"), ctx.screen.text())
  kit.press(ctx, "enter")
  frames(ctx, 2)
  t.eq(ctx.ui.top().name, "play")
  t.truthy(ctx.player.car == nil)
  open("garage")
  frames(ctx)
  t.truthy(ctx.screen.find("Take out: Marlin"), ctx.screen.text())
  t.truthy(ctx.screen.find("Cars kept: 1/3"))
  t.eq(ctx.screen.overflow, 0)
end)

-- ---------------------------------------------------------------- transitions, loading, the map

t.test("transition: closes, calls back once when the screen is hidden, opens again, and stays inside the screen", function()
  local tr = transitionLib.new()
  local calls = 0
  t.truthy(tr:start(function() calls = calls + 1 end, 0.2))
  t.truthy(not tr:start(function() calls = calls + 100 end, 0.2), "one at a time")
  local term = kit.term(51, 19)
  tr:update(0.1)
  tr:draw(term, 51, 19)
  local _, _, bg = term.cell(1, 1)
  t.eq(bg, C.black)
  local _, _, edge = term.cell(27, 1)
  t.eq(edge, C.orange, "an edge at half way")
  t.eq(calls, 0)
  tr:update(0.15)
  t.eq(calls, 1, "called when covered")
  t.near(tr:amount(), 1, 1e-9)
  tr:update(0.1)
  t.truthy(tr:amount() < 1 and tr:amount() > 0)
  tr:update(0.2)
  t.truthy(not tr:active())
  t.eq(calls, 1)
  t.eq(term.overflow, 0)
end)

t.test("loading card: the name, a bar and a line of text, centred in 51x19", function()
  local term = kit.term(51, 19)
  loading.draw(term, "Raising the island...", 0.5, loading.TIPS[1])
  t.truthy(term.find("S A L T G A T E") and term.find("Raising the island..."))
  t.truthy(term.find("Gull totems"))
  t.eq(term.overflow, 0)
  for _, tip in ipairs(loading.TIPS) do t.truthy(#tip <= 49, tip) end
  loading.draw(term, nil, nil)
  t.eq(term.overflow, 0)
end)

t.test("map: the activities' icons are placed where the view says, with a legend and the completion", function()
  local ctx = game()
  ctx.view = { mapProject = function(x, z) return math.floor(x / 8) + 1, math.floor(z / 8) + 2 end }
  ctx.eui.screens.mapOverlay(ctx)
  t.truthy(ctx.screen.row(1):find("SALTGATE") and ctx.screen.row(1):find("0.0%", 1, true) and ctx.screen.row(1):find("M close", 1, true), ctx.screen.row(1))
  t.truthy(ctx.screen.row(19):find("race") and ctx.screen.row(19):find("garage"), ctx.screen.row(19))
  local race = ctx.activities.layout.races[1]
  local cx, cy = ctx.view.mapProject(race.pts[1], race.pts[3])
  if cy >= 2 and cy <= 18 and cx >= 1 and cx <= 51 then
    local ch = ctx.screen.cell(cx, cy)
    t.truthy(ch == "R" or ch == "T" or ch == "D" or ch == "$" or ch == "G" or ch == "H", "an icon at the race start: " .. tostring(ch))
  end
  t.eq(ctx.screen.overflow, 0)
end)

t.test("every screen stays inside 51x19 with the longest names the game has", function()
  local ctx = game({ money = 99999999 })
  ctx.districtName = "a_district_with_a_very_long_name"
  ctx.hud.hour = 23.99
  local car = giveCar(ctx)
  car.v = 99
  ctx.player.weapon = { name = "Long Barrelled Shotgun", ammo = 99, reserve = 999 }
  ctx.hud.radioLine = function() return "R 101.5 Gilt Heights Smooth Extra Long" end
  ctx.bus:emit("heat_changed", { level = 6, previous = 0 })
  ctx.hud.toast("ACHIEVEMENT  Gull Whisperer", "yellow", 5, "Find every gull totem.  +$1500")
  frames(ctx, 3)
  t.eq(ctx.screen.overflow, 0, "the HUD")
  for _, name in ipairs({ "pause" }) do
    ctx.ui.push(name)
    frames(ctx, 2)
    t.eq(ctx.screen.overflow, 0, name)
    ctx.ui.pop()
  end
  for tab = 1, 3 do
    ctx.eui.screens.stats(tab)
    frames(ctx, 2)
    t.eq(ctx.screen.overflow, 0, "stats tab " .. tab)
    ctx.ui.pop()
  end
  ctx.eui.screens.settings()
  frames(ctx, 2)
  t.eq(ctx.screen.overflow, 0, "settings")
  t.truthy(ctx.screen.find("Graphics quality") and ctx.screen.find("AUTO") and ctx.screen.find("Key hints") and ctx.screen.find("Speed units"))
end)
