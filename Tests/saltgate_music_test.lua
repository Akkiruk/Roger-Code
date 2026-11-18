-- saltgate_music_test.lua
-- SALTGATE's soundtrack without a speaker: every track parses and stays inside what a CC:Tweaked speaker can play,
-- loops come round cleanly, and cues change on bar lines (or beats, for stings) the way the player promises.

local t = require("testing")
local score = require("music.score")
local music = require("music.player")

local TPS = score.TICKS_PER_SECOND

--- A speaker that writes down what it is asked to play, at the tick the test says it is.
local function fakeSpeaker()
  local sp = { log = {}, tick = 0 }
  sp.playNote = function(inst, vol, pitch)
    sp.log[#sp.log + 1] = { tick = sp.tick, inst = inst, vol = vol, pitch = pitch }
    return true
  end
  return sp
end

local function newPlayer(sp)
  return music.new({ speaker = sp, clock = false })
end

--- Step a player tick by tick for n ticks.
local function run(p, sp, ticks, onTick)
  for _ = 1, ticks do
    if sp then sp.tick = sp.tick + 1 end
    p:update(1 / TPS)
    if onTick then onTick(sp and sp.tick) end
  end
end

local function allTracks()
  local p = newPlayer(nil)
  local out = {}
  for _, name in ipairs(music.TRACKS) do
    local tr = p:load(name)
    if not tr then error("track " .. name .. " does not load: " .. tostring(p.errors[name]), 0) end
    out[name] = tr
  end
  return out
end

-- ---------------------------------------------------------------- the tracks

t.test("saltgate music: every track loads and compiles", function()
  local p = newPlayer(nil)
  t.eq(p:preload(), 0, "tracks that fail to load")
  for _, name in ipairs(music.TRACKS) do
    t.truthy(p:load(name), name .. ": " .. tostring(p.errors[name]))
  end
end)

t.test("saltgate music: every cue and every district has a track", function()
  local p = newPlayer(nil)
  for _, cue in ipairs(music.CUES) do
    t.truthy(p:load(p:resolve(cue)), "cue " .. cue)
  end
  for d, id in pairs(music.DISTRICTS) do
    t.truthy(p:load(id), "district " .. d)
  end
end)

t.test("saltgate music: notes are in range, on real instruments, and within the speaker's notes per tick", function()
  for name, tr in pairs(allTracks()) do
    local last = -1
    for i, row in ipairs(tr.rows) do
      t.truthy(row.tick > last, name .. " row " .. i .. " ticks go forward")
      t.truthy(row.tick == math.floor(row.tick), name .. " row " .. i .. " on a whole tick")
      t.truthy(row.tick < tr.length, name .. " row " .. i .. " inside the track")
      last = row.tick
      t.truthy(#row.notes >= 1 and #row.notes <= score.MAX_NOTES, name .. " tick " .. row.tick .. ": " .. #row.notes .. " notes")
      for _, n in ipairs(row.notes) do
        t.truthy(score.INSTRUMENTS[n[1]], name .. ": instrument " .. tostring(n[1]))
        t.truthy(n[2] >= 0 and n[2] <= 24 and n[2] == math.floor(n[2]), name .. ": pitch " .. tostring(n[2]))
        t.truthy(n[3] > 0 and n[3] <= 1, name .. ": volume " .. tostring(n[3]))
      end
    end
  end
  -- 6 for music leaves the 8 a tick (CC:Tweaked's max_notes_per_tick) room for the game's sound effects
  t.truthy(score.MAX_NOTES <= 8, "music's budget fits the speaker")
end)

t.test("saltgate music: loops are whole bars, stings are short and end", function()
  for name, tr in pairs(allTracks()) do
    t.truthy(tr.barTicks > 0 and tr.beatTicks > 0, name .. " has a bar")
    if tr.loop then
      t.eq(tr.length % tr.barTicks, 0, name .. " loop length in whole bars")
      t.eq(tr.loopTick % tr.barTicks, 0, name .. " loops back to a bar line")
      t.truthy(tr.loopTick < tr.length, name .. " has something to loop")
      t.truthy(tr.length / TPS >= 15, name .. " loop is at least 15 s")
    else
      t.truthy(tr.length / TPS <= 10, name .. " sting is short (" .. tr.length / TPS .. " s)")
    end
  end
  local list = allTracks()
  for _, cue in ipairs({ "title", "roam", "drive", "job", "heat_low", "heat_high", "finale", "credits" }) do
    t.truthy(list[cue].loop, cue .. " loops")
  end
  for _, cue in ipairs({ "cuffed", "wasted", "complete" }) do
    t.truthy(not list[cue].loop, cue .. " is a sting")
  end
  t.truthy(list.complete.resume, "complete gives the music back")
end)

t.test("saltgate music: tracks that share a sync group share the bar and the phrase", function()
  local groups = {}
  for name, tr in pairs(allTracks()) do
    if tr.sync then
      local g = groups[tr.sync]
      if g then
        t.eq(tr.barTicks, g.barTicks, name .. " bar length in " .. tr.sync)
        t.eq(tr.bars, g.bars, name .. " bars in " .. tr.sync)
      else
        groups[tr.sync] = tr
      end
    end
  end
  t.truthy(groups.roam and groups.chase, "roam and chase groups exist")
end)

t.test("saltgate music: the compiler catches bad lines", function()
  local function bad(def, what)
    local ok, err = pcall(score.compile, def, "bad")
    t.truthy(not ok, what .. " is refused")
    t.truthy(type(err) == "string" and err:find("bad", 1, true), what .. " names the track: " .. tostring(err))
  end
  local v = { { name = "a", inst = "harp" } }
  bad({ voices = v, patterns = { m = { a = "C5 . . ." } }, order = { "m" } }, "a part bar")
  bad({ voices = v, patterns = { m = { a = "G5" .. string.rep(" .", 15) } }, order = { "m" } }, "pitch 25")
  bad({ voices = v, patterns = { m = { a = "H4" .. string.rep(" .", 15) } }, order = { "m" } }, "a non-note")
  bad({ voices = { { name = "a", inst = "kazoo" } }, patterns = { m = { a = "C5" .. string.rep(" .", 15) } }, order = { "m" } }, "an instrument")
  bad({ voices = v, patterns = { m = { a = "C4+D4+E4+F4+G4+A4+B4" .. string.rep(" .", 15) } }, order = { "m" } }, "7 notes at once")
  bad({ voices = v, patterns = { m = { b = "C5" .. string.rep(" .", 15) } }, order = { "m" } }, "an unknown voice")
  t.eq(score.pitch("F#3"), 0, "F#3")
  t.eq(score.pitch("C5"), 18, "C5")
  t.eq(score.pitch("F#5"), 24, "F#5")
  t.eq(score.name(13), "G4", "13")
  t.eq(score.transpose("C4+Eb4' . k", 5), "F4+Ab4' . k", "transpose")
end)

t.test("saltgate music: every cue the game sends has a track", function()
  local hints = require("sg.hints")
  local p = newPlayer(nil)
  local n = 0
  for _, list in ipairs({ hints.MUSIC_STATES, hints.MUSIC_EVENTS }) do
    for _, cue in ipairs(list) do
      t.truthy(p:load(p:resolve(cue)), "the game's cue " .. cue)
      n = n + 1
    end
  end
  t.truthy(n >= 13, "the game's cue list was read (" .. n .. ")")
  t.eq(p:resolve("free_roam"), "roam", "free_roam")
  t.eq(p:resolve("driving"), "drive", "driving")
  t.eq(p:resolve("job_gulls"), "job", "a job")
  t.eq(p:resolve("job_complete"), "complete", "job_complete")
end)

t.test("saltgate music: the game's cue pattern (job_complete, then the state again) plays the sting and goes on", function()
  local sp = fakeSpeaker()
  local p = newPlayer(sp)
  p:cue("driving")
  run(p, sp, 50)
  p:cue("job_complete")
  run(p, sp, 1)
  p:cue("driving") -- the game sends the state cue again the next frame
  run(p, sp, 12)
  t.eq(p:current(), "complete", "the sting plays")
  run(p, sp, p:load("complete").length + 2)
  t.eq(p:current(), "drive", "driving music after it")
  -- cuffed is sent as a state for as long as the arrest screen shows, then whatever comes next
  p:cue("cuffed")
  for _ = 1, 100 do
    p:cue("cuffed")
    run(p, sp, 1)
  end
  t.eq(p:current(), nil, "cuffed played once and stopped, though it was sent every frame")
  p:cue("free_roam")
  t.eq(p:current(), "roam", "roam after the arrest screen")
end)

-- ---------------------------------------------------------------- the player

t.test("saltgate music: a loop comes round to the same notes", function()
  for _, name in ipairs({ "title", "roam", "drive", "job", "heat_low", "heat_high", "finale", "credits" }) do
    local sp = fakeSpeaker()
    local p = newPlayer(sp)
    local tr = p:load(name)
    t.truthy(p:cue(name), name .. " cued")
    local span = tr.length - tr.loopTick
    run(p, sp, tr.length + span + 5)
    -- the notes of the looped section, first time and second time, line up note for note
    local first, second = {}, {}
    for _, n in ipairs(sp.log) do
      local at = n.tick
      if at >= tr.loopTick and at < tr.length then
        first[#first + 1] = (at - tr.loopTick) .. n.inst .. n.pitch
      elseif at >= tr.length and at < tr.length + span then
        second[#second + 1] = (at - tr.length) .. n.inst .. n.pitch
      end
    end
    t.truthy(#first > 0, name .. " played its loop")
    t.eq(#second, #first, name .. " second time round has as many notes")
    for i = 1, #first do
      if first[i] ~= second[i] then error(name .. " differs on the loop at note " .. i .. ": " .. first[i] .. " vs " .. tostring(second[i]), 0) end
    end
    t.eq(p:current(), name, name .. " still playing")
  end
end)

t.test("saltgate music: a loop cued over a loop starts on the next bar line, fading the old one", function()
  local sp = fakeSpeaker()
  local p = newPlayer(sp)
  p:cue("roam")
  local roam = p:load("roam")
  run(p, sp, roam.barTicks + 7)
  t.truthy(p:cue("drive"), "drive cued")
  t.eq(p:current(), "roam", "roam plays out its bar")
  local switchedAt
  run(p, sp, roam.barTicks, function(tick)
    if not switchedAt and p:current() == "drive" then switchedAt = tick end
  end)
  t.truthy(switchedAt, "drive started")
  -- the bar line after the cue is 2 bars in
  t.eq(switchedAt % roam.barTicks, 0, "switch on a bar line (tick " .. tostring(switchedAt) .. ")")
  t.eq(switchedAt, 2 * roam.barTicks, "the next bar line, not a later one")
  for _, n in ipairs(sp.log) do
    if n.tick < switchedAt then t.truthy(n.inst ~= "pling" and n.inst ~= "guitar", "no drive notes before the switch") end
  end
end)

t.test("saltgate music: walking into a district changes roam's colour in the same bar of the tune", function()
  local sp = fakeSpeaker()
  local p = newPlayer(sp)
  p:cue("roam")
  local roam = p:load("roam")
  run(p, sp, roam.barTicks * 3 + 5)
  p:setDistrict("gilt")
  t.eq(p:current(), "roam", "waits for the bar line")
  run(p, sp, roam.barTicks)
  t.eq(p:current(), "roam_gilt", "now Gilt Heights")
  -- at the bar line (4 bars in) gilt took over at its own bar 5
  local pos = p.now - p.cur.t0
  t.truthy(pos >= 4 * roam.barTicks and pos < 5 * roam.barTicks, "same bar of the phrase (" .. pos .. ")")
  p:setDistrict("mid")
  run(p, sp, roam.barTicks)
  t.eq(p:current(), "roam", "back in Old Saltgate")
  p:setDistrict("nowhere")
  run(p, sp, roam.barTicks)
  t.eq(p:current(), "roam", "an unknown district keeps the plain roam")
  -- a district set before roaming is used when roam is cued
  local q = newPlayer(nil)
  q:setDistrict("lantern")
  q:cue("roam")
  t.eq(q:current(), "roam_lantern", "lantern from the start")
end)

t.test("saltgate music: heat going up or down keeps the chase's bar", function()
  local p = newPlayer(nil)
  p:cue("heat_low")
  local low = p:load("heat_low")
  run(p, nil, low.barTicks * 5 + 3)
  p:cue("heat_high")
  run(p, nil, low.barTicks)
  t.eq(p:current(), "heat_high", "heat_high in")
  local pos = p.now - p.cur.t0
  t.truthy(pos >= 6 * low.barTicks and pos < 7 * low.barTicks, "bar 7 of the chase (" .. pos .. ")")
  p:cue("heat_low")
  run(p, nil, low.barTicks)
  t.eq(p:current(), "heat_low", "back down")
end)

t.test("saltgate music: stings come in on the beat and give the music back", function()
  local sp = fakeSpeaker()
  local p = newPlayer(sp)
  p:cue("roam")
  local roam = p:load("roam")
  local complete = p:load("complete")
  run(p, sp, roam.barTicks + 5)
  p:cue("complete")
  local startedAt
  run(p, sp, roam.beatTicks, function(tick)
    if not startedAt and p:current() == "complete" then startedAt = tick end
  end)
  t.truthy(startedAt, "complete started within a beat")
  t.eq(startedAt % roam.beatTicks, 0, "on a beat")
  run(p, sp, complete.length + 2)
  t.eq(p:current(), "roam", "roam came back after complete")

  -- a loop cued while a sting plays waits for the sting
  p:cue("cuffed")
  run(p, sp, roam.beatTicks + 1)
  t.eq(p:current(), "cuffed", "cuffed playing")
  p:cue("drive")
  t.eq(p:current(), "cuffed", "drive waits")
  run(p, sp, p:load("cuffed").length)
  t.eq(p:current(), "drive", "drive after cuffed")

  -- wasted with nothing after it: silence
  p:cue("wasted")
  run(p, sp, roam.barTicks + p:load("wasted").length)
  t.eq(p:current(), nil, "silent after wasted")
  local n = #sp.log
  run(p, sp, 40)
  t.eq(#sp.log, n, "nothing plays after the sting")
end)

t.test("saltgate music: unknown cues, repeats and stop", function()
  local sp = fakeSpeaker()
  local p = newPlayer(sp)
  t.eq(p:cue("nope"), false, "unknown cue")
  t.eq(p:cue(nil), false, "nil cue")
  t.eq(p:cue(42), false, "number cue")
  t.eq(p:current(), nil, "nothing started")
  run(p, sp, 10)
  t.eq(#sp.log, 0, "still silent")
  p:cue("title")
  run(p, sp, 30)
  local t0 = p.cur.t0
  t.eq(p:cue("title"), true, "same cue again")
  t.eq(p.cur.t0, t0, "not restarted")
  t.eq(p:cue("nope"), false, "unknown cue while playing")
  t.eq(p:current(), "title", "title keeps playing")
  -- cue away then straight back: the switch is forgotten
  p:cue("drive")
  p:cue("title")
  run(p, sp, 200)
  t.eq(p:current(), "title", "title, not drive")
  p:stop()
  local n = #sp.log
  run(p, sp, 100)
  t.eq(#sp.log, n, "stop is silent")
  t.eq(p:current(), nil, "nothing playing")
end)

t.test("saltgate music: volume, sound off and no speaker", function()
  local sp = fakeSpeaker()
  local p = newPlayer(sp)
  p:cue("drive")
  run(p, sp, 80)
  local loud = 0
  for _, n in ipairs(sp.log) do loud = math.max(loud, n.vol) end
  t.truthy(loud > 0, "notes played")
  sp.log = {}
  p:setVolume(0.5)
  run(p, sp, 80)
  local half = 0
  for _, n in ipairs(sp.log) do half = math.max(half, n.vol) end
  t.truthy(half > 0 and half <= loud * 0.5 + 1e-9, "half volume")
  sp.log = {}
  p:setVolume(0)
  run(p, sp, 80)
  t.eq(#sp.log, 0, "volume 0 plays nothing")
  p:setVolume(5)
  t.eq(p.master, 1, "volume capped at 1")
  p:setVolume(-1)
  t.eq(p.master, 0, "volume floored at 0")

  local off = fakeSpeaker()
  local q = music.new({ speaker = off, enabled = false, clock = false })
  q:cue("drive")
  run(q, off, 200)
  t.eq(#off.log, 0, "sound off: silent")
  t.eq(q:current(), "drive", "but it keeps its place")
  q:setEnabled(true)
  run(q, off, 40)
  t.truthy(#off.log > 0, "sound back on plays")

  local none = music.new({ clock = false })
  t.truthy(none:cue("heat_high"), "cues work with no speaker")
  run(none, nil, 400)
  none:stop()

  local broken = music.new({ speaker = { playNote = function() error("speaker gone") end }, clock = false })
  broken:cue("finale")
  run(broken, nil, 200)
  local full = music.new({ speaker = { playNote = function() return false end }, clock = false })
  full:cue("finale")
  run(full, nil, 200)
  t.eq(full.played, 0, "a full speaker's refusals are not counted as played")
end)

t.test("saltgate music: a slow frame never sends more than the music's notes per tick", function()
  local sp = fakeSpeaker()
  local p = newPlayer(sp)
  p:cue("heat_high")
  for _ = 1, 40 do
    local before = #sp.log
    p:update(0.25)
    t.truthy(#sp.log - before <= score.MAX_NOTES, "at most " .. score.MAX_NOTES .. " in one update")
  end
  local before = #sp.log
  p:update(30)
  t.truthy(#sp.log - before <= score.MAX_NOTES, "a long stall does not burst")
  -- with a real clock, updates in the same 50 ms share the budget
  local ms = 1000
  local sp2 = fakeSpeaker()
  local q = music.new({ speaker = sp2, clock = function() return ms end })
  q:cue("heat_high")
  for _ = 1, 10 do q:update(0.1) end
  t.truthy(#sp2.log <= score.MAX_NOTES, "one tick of real time, one budget (" .. #sp2.log .. ")")
  ms = ms + 50
  q:update(0.05)
  t.truthy(#sp2.log > 0, "the next tick plays again")
end)

t.test("saltgate music: the module's own player follows the game's sound setting", function()
  local sp = fakeSpeaker()
  music.init({ speaker = sp, sound = true, clock = false })
  t.truthy(music.cue("title"), "cue")
  for _ = 1, 60 do music.update(0.05) end
  t.truthy(#sp.log > 0, "plays")
  t.eq(music.current(), "title", "current")
  music.setVolume(0.3)
  music.setDistrict("brine")
  music.cue("roam")
  for _ = 1, 120 do music.update(0.05) end
  t.eq(music.current(), "roam_brine", "district")
  music.stop()
  t.eq(music.current(), nil, "stopped")
  t.eq(music.cue("not_a_cue"), false, "missing cue is a no-op")

  local quiet = fakeSpeaker()
  music.init({ speaker = quiet, sound = false, clock = false })
  music.cue("title")
  for _ = 1, 60 do music.update(0.05) end
  t.eq(#quiet.log, 0, "sound = false is silent")
  music.init({ speaker = quiet, sound = true, music = false, clock = false })
  music.cue("title")
  for _ = 1, 60 do music.update(0.05) end
  t.eq(#quiet.log, 0, "music = false is silent")
  music.init({ speaker = false, sound = true, clock = false })
  music.cue("title")
  for _ = 1, 60 do music.update(0.05) end
  music.stop()
end)
