-- saltgate_shared_test.lua
-- The pieces of the first game that the open city still drives on: a car's handling (sg/vehicle.lua), the keys as CC
-- sends them (sg/input.lua), the objective arrow (sg/hints.lua) and the sound effects' share of the speaker
-- (sg/sound.lua). (Classic itself is gone; its save format is read by core/save.lua, tested in saltgate_core_test.)

local t = require("testing")
local util = require("sg.util")
local vehicle = require("sg.vehicle")

t.test("shared car: a car speeds up toward its top speed and never past it", function()
  local car = vehicle.new("marlin", 0, 0, 0)
  for _ = 1, 400 do vehicle.update(car, { throttle = 1 }, 0.05, nil) end
  t.truthy(car.v > car.spec.top * 0.85, "near top: " .. car.v)
  t.truthy(car.v <= car.spec.top, "not past top")
  for _ = 1, 60 do vehicle.update(car, { throttle = -1 }, 0.05, nil) end
  t.truthy(car.v <= 0, "the brakes stop it, then it reverses")
  t.truthy(car.v > -car.spec.top * 0.5, "reverse is slow")
end)

t.test("shared car: steering needs speed, and right is a positive turn", function()
  local car = vehicle.new("pipit", 0, 0, 0)
  for _ = 1, 20 do vehicle.update(car, { steer = 1 }, 0.05, nil) end
  t.near(car.h, 0, 0.0001, "no turn standing still")
  for _ = 1, 30 do vehicle.update(car, { throttle = 1, steer = 0 }, 0.05, nil) end
  local before = car.h
  for _ = 1, 10 do vehicle.update(car, { throttle = 1, steer = 1 }, 0.05, nil) end
  t.truthy(car.h > before, "turned right")
end)


t.test("shared car: a car at no health is wrecked and cars that touch are pushed apart", function()
  local car = vehicle.new("pipit", 0, 0, 0)
  vehicle.damage(car, 1000)
  t.truthy(car.wrecked)
  t.eq(car.health, 0)
  local a, b = vehicle.new("marlin", 0, 0, 0), vehicle.new("marlin", 1, 0, math.pi)
  a.v = 20
  local closing = vehicle.bump(a, b)
  t.truthy(closing > 0, "they met")
  t.truthy(util.dist(a.x, a.z, b.x, b.z) > 1, "pushed apart")
  t.truthy(a.v < 20, "a lost speed")
end)


-- ---------------------------------------------------------------- controls: keys as CC sends them

local inputlib = require("sg.input")
local hints = require("sg.hints")

-- the CC:Tweaked 1.101.3 key codes (GLFW)
local KEYS = { w = 87, a = 65, s = 83, d = 68, e = 69, f = 70, x = 88, h = 72, m = 77, p = 80, c = 67, q = 81,
  up = 265, down = 264, left = 263, right = 262, space = 32, leftShift = 340, rightShift = 344, enter = 257,
  numPadEnter = 335, tab = 258, f3 = 292 }

--- Hold a key for some frames the way CC does: key (not held), then a repeat (held) each frame, then key_up.
local function holdFrames(inp, code, frames, each)
  local clock = inp.now
  inp:event(clock, "key", code, false)
  for i = 1, frames do
    if i > 1 then inp:event(clock, "key", code, true) end
    each(inp:read())
    clock = clock + 0.05
    inp:endFrame(clock)
  end
  inp:event(clock, "key_up", code)
end

t.test("shared input: a held key counts every frame, repeats are not new presses, key_up stops it at once", function()
  local inp = inputlib.new(KEYS)
  local frames, uses = 0, 0
  holdFrames(inp, KEYS.w, 30, function(i)
    if i.throttle == 1 then frames = frames + 1 end
  end)
  t.eq(frames, 30, "W held all 30 frames")
  t.eq(inp:read().throttle, 1, "the frame of the key_up still feels the tap")
  inp:endFrame(inp.now + 0.05)
  t.eq(inp:read().throttle, 0, "let go: nothing next frame")
  holdFrames(inp, KEYS.e, 20, function(i) if i.enter then uses = uses + 1 end end)
  t.eq(uses, 1, "holding E is one press, not twenty")
end)

t.test("shared input: a tap shorter than a frame still moves, and two keys at once both count", function()
  local inp = inputlib.new(KEYS)
  inp:event(0, "key", KEYS.a, false)
  inp:event(0.01, "key_up", KEYS.a)
  t.eq(inp:read().steer, -1, "the tap is felt for one frame")
  inp:endFrame(0.05)
  t.eq(inp:read().steer, 0)
  inp:event(0.06, "key", KEYS.w, false)
  inp:event(0.07, "key", KEYS.d, false)
  inp:event(0.08, "key", KEYS.d, true) -- only the last key repeats, as in Minecraft; W stays held
  local i = inp:read()
  t.eq(i.throttle, 1)
  t.eq(i.steer, 1)
  inp:endFrame(0.1)
  i = inp:read()
  t.eq(i.throttle, 1, "W still held without its own repeats")
end)

t.test("shared input: E and F are one action, arrows are WASD, X skips, a lost key_up does not stick forever", function()
  local inp = inputlib.new(KEYS)
  inp:event(0, "key", KEYS.e, false)
  inp:event(0, "key", KEYS.f, false)
  t.truthy(inp:read().enter)
  inp:endFrame(0.05)
  t.truthy(not inp:read().enter, "once")
  inp:event(0.1, "key", KEYS.up, false)
  inp:event(0.1, "key", KEYS.left, false)
  t.eq(inp:read().throttle, 1)
  t.eq(inp:read().steer, -1)
  inp:event(0.1, "key", KEYS.x, false)
  t.truthy(inp:read().skip)
  inp:endFrame(0.1 + inputlib.STALE + 0.5)
  t.eq(inp:read().throttle, 0, "no key_up came, but the key went quiet")
  inp:event(1, "key_up", KEYS.s) -- a key_up for a key never seen down changes nothing
  t.eq(inp:read().throttle, 0)
end)


t.test("shared hints: the arrow points where the target is from the camera", function()
  -- facing east (yaw 0): +z is to the right
  t.eq((hints.direction(0, 0, 0, 50, 0)), "ahead")
  t.eq((hints.direction(0, 0, 0, 0, 50)), "right")
  t.eq((hints.direction(0, 0, 0, 0, -50)), "left")
  t.eq((hints.direction(0, 0, 0, -50, 0)), "behind")
  -- facing south (yaw pi/2): west (-x) is to the right
  t.eq((hints.direction(0, 0, math.pi / 2, -50, 0)), "right")
  local _, d = hints.direction(0, 0, 0, 30, 40)
  t.near(d, 50, 0.001)
end)


local soundlib = require("sg.sound")

t.test("shared sound: effects keep to their share of the speaker, and wait rather than vanish", function()
  local calls = 0
  local speaker = { playNote = function() calls = calls + 1 return true end }
  local s = soundlib.new(speaker, 2)
  soundlib.play(s, "pass") -- several notes at once
  soundlib.play(s, "cash")
  local most = 0
  for _ = 1, 40 do
    local before = calls
    soundlib.update(s, 0.05, false)
    most = math.max(most, calls - before)
  end
  t.truthy(most <= 2, "never more than 2 at once: " .. most)
  local total = #soundlib.CUES.pass + #soundlib.CUES.cash
  t.eq(calls, total, "every note played, a little later if need be")
  local free = soundlib.new(speaker)
  t.eq(free.cap, 7, "without music the effects may use 7")
end)

t.test("shared input: a mouse click (as CC sends it) is ENTER, unless a screen with options takes it; SPACE is ENTER too, but not just after a screen opens", function()
  local inp = inputlib.new(KEYS)
  inp:event(1, "mouse_click", 1, 20, 7)
  t.truthy(inp:pressedAction("advance"), "a click advances")
  local x, y, button = inp:clicked()
  t.eq(x, 20) t.eq(y, 7) t.eq(button, 1)
  inp:takeClick()
  t.truthy(not inp:pressedAction("advance"), "a click a screen took (an option, or beside the options) does not")
  t.eq(inp:clicked(), nil)
  inp:endFrame(1.05)
  inp:event(1.1, "mouse_click", 2, 5, 5)
  inp:endFrame(1.15)
  t.truthy(not inp:pressedAction("advance"), "a click lasts one frame")
  -- SPACE: ENTER on screens that stop play (they are the only readers of "advance"); still the handbrake in play
  inp:event(2, "key", KEYS.space, false)
  t.truthy(inp:pressedAction("advance"), "SPACE advances talk")
  t.truthy(inp:read().handbrake, "and is the handbrake in a car")
  inp:event(2, "key_up", KEYS.space)
  inp:endFrame(2.05)
  -- a talk opens while you brake: SPACE does not skip its first line
  inp:guardSpace(3)
  inp:event(3.1, "key", KEYS.space, false)
  t.truthy(not inp:pressedAction("advance"), "SPACE just after a screen opens is still the handbrake")
  inp:event(3.1, "key_up", KEYS.space)
  inp:endFrame(3.15)
  inp:event(3.5, "key", KEYS.space, false)
  t.truthy(inp:pressedAction("advance"), "a moment later it advances")
  inp:event(3.5, "key_up", KEYS.space)
  inp:endFrame(3.55)
  inp:event(4, "key", KEYS.enter, false)
  t.truthy(inp:pressedAction("advance"), "ENTER as ever")
end)
