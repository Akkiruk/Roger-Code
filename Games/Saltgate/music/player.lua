-- player.lua
-- SALTGATE's soundtrack on a speaker: a small tracker that never waits. Drive it from the game loop with
-- music.update(dt), or run music.run in parallel with the game (one or the other, not both).
--
--   local music = require("music")     (music/init.lua; or require("music.player"))
--   music.init({ speaker = peripheral.find("speaker"), sound = settings.sound })   -- optional: else it finds both itself
--   music.cue("free_roam")   the game's cues (sg/hints.lua MUSIC_STATES and MUSIC_EVENTS): title free_roam driving
--                            job_fresh_air job_hot_broth job_gulls job_gilded finale heat_low heat_high cuffed wasted
--                            job_complete; the track names work too: roam drive job complete credits
--   music.setDistrict("gilt") gilt lantern cinder brine mid: roam takes that district's arrangement
--   music.update(dt)         every frame
--   music.setVolume(0.5)     0-1
--   music.stop()
--
-- Loops change on the next bar line (the old one fades over what is left of its bar, the new one fades in over
-- its first bar); tracks in one sync group (the chases, the roam districts) change straight into the same bar of
-- the phrase. Stings come in on the next beat; a loop cued while a sting plays waits for the sting to end, and a
-- sting marked resume gives back the loop it cut. An unknown cue does nothing. No speaker, or sound off: silent.

local score = require("music.score")

local M = {}

-- the cue names the game sends, and the track each plays
M.ALIASES = {
  free_roam = "roam", driving = "drive", job_complete = "complete",
  job_fresh_air = "job", job_hot_broth = "job", job_gulls = "job", job_gilded = "job",
}
M.CUES = {
  "title", "free_roam", "driving", "job_fresh_air", "job_hot_broth", "job_gulls", "job_gilded", "finale", "heat_low",
  "heat_high", "cuffed", "wasted", "job_complete",
  "roam", "drive", "job", "complete", "credits",
}
M.TRACKS = {
  "title", "roam", "roam_gilt", "roam_lantern", "roam_cinder", "roam_brine", "drive", "job", "heat_low", "heat_high",
  "cuffed", "wasted", "complete", "finale", "credits",
}
M.DISTRICTS = { gilt = "roam_gilt", lantern = "roam_lantern", cinder = "roam_cinder", brine = "roam_brine", mid = "roam" }

local TPS = score.TICKS_PER_SECOND
-- a note more than this many ticks late is dropped, not played in a heap with the ones after it
local LATE = 6
-- the longest step one update takes: after a stall the music picks up where it was, it does not race to catch up
local MAX_DT = 0.5

local Player = {}
Player.__index = Player

local function defaultLoader(name)
  local ok, def = pcall(require, "music.tracks." .. name)
  if not ok then return nil, tostring(def) end
  if type(def) ~= "table" then return nil, "track file did not return a table" end
  return def
end

local function realMs()
  local os_ = rawget(_G, "os")
  if os_ and os_.epoch then return os_.epoch("utc") end
  return nil
end

--- A player of its own. opts: speaker, enabled (default true), volume (0-1), loader(name) -> track table,
-- clock() -> milliseconds (for the per-tick note budget and for run; default os.epoch, nil under plain Lua).
function M.new(opts)
  opts = opts or {}
  local p = setmetatable({
    speaker = opts.speaker,
    enabled = opts.enabled ~= false,
    master = opts.volume or 1,
    loader = opts.loader or defaultLoader,
    clock = opts.clock,
    now = 0,
    cache = {},
    errors = {},
    cur = nil,
    pending = nil,
    after = nil,
    resumeTo = nil,
    wanted = nil,
    district = nil,
    budgetKey = nil,
    budgetUsed = 0,
    played = 0,
  }, Player)
  if p.clock == nil then p.clock = realMs end
  return p
end

--- The compiled track, or nil (the reason is kept in p.errors[name]).
function Player:load(name)
  if self.cache[name] ~= nil then return self.cache[name] or nil end
  local def, err = self.loader(name)
  local track
  if def then
    local ok, res = pcall(score.compile, def, name)
    if ok then track = res else err = res end
  end
  self.cache[name] = track or false
  if not track then self.errors[name] = err or "missing" end
  return track
end

--- Load and check every track now, so the first cue of each costs nothing. Returns how many failed.
function Player:preload()
  local bad = 0
  for _, name in ipairs(M.TRACKS) do
    if not self:load(name) then bad = bad + 1 end
  end
  return bad
end

function Player:resolve(name)
  name = M.ALIASES[name] or name
  if name == "roam" and self.district and M.DISTRICTS[self.district] then
    local id = M.DISTRICTS[self.district]
    if self:load(id) then return id end
  end
  return name
end

local function firstRowAt(track, tick)
  local rows = track.rows
  for i = 1, #rows do
    if rows[i].tick >= tick then return i end
  end
  return #rows + 1
end

function Player:start(track, at, offset, fade)
  offset = offset or 0
  self.cur = {
    track = track,
    t0 = at - offset,
    idx = firstRowAt(track, offset),
    fadeFrom = fade and at or nil,
  }
end

--- The next bar line (or beat) of what is playing, as an absolute tick.
function Player:boundary(kind)
  local cur = self.cur
  local tr = cur.track
  if kind == "now" then return self.now end
  local unit = kind == "beat" and tr.beatTicks or tr.barTicks
  local pos = self.now - cur.t0
  local b = math.ceil(pos / unit - 1e-9) * unit
  if b > tr.length then b = tr.length end
  return cur.t0 + b
end

--- Play a cue: true if there is such a track, false (and nothing changes) if not.
function Player:cue(name)
  if type(name) ~= "string" then return false end
  local id = self:resolve(name)
  local tr = self:load(id)
  if not tr then return false end
  self.wanted = M.ALIASES[name] or name
  -- a sting sent again after it has played (a state cue repeated) does not play twice; any other cue resets this
  if self.spent == tr then return true end
  self.spent = nil
  local cur = self.cur
  if self.pending and self.pending.track == tr then return true end
  if cur and cur.track == tr then
    -- cued back to what is playing: forget a switch that was waiting
    self.pending = nil
    if tr.loop then self.after = nil end
    return true
  end
  if not cur then
    self.pending, self.after = nil, nil
    self:start(tr, self.now, 0, false)
    self:update(0) -- from silence the first notes sound now, not on the next frame
    return true
  end
  if not cur.track.loop and tr.loop then
    -- a sting is playing: the loop comes when it ends
    self.after = tr
    self.pending = nil
    return true
  end
  if not tr.loop then
    if cur.track.loop then self.resumeTo = cur.track end
  else
    self.after = nil
  end
  local at = self:boundary(tr.enter)
  self.pending = { track = tr, at = at, from = self.now }
  return true
end

--- Which district roam is in (gilt, lantern, cinder, brine, mid). Roaming already: it changes on the next bar line,
-- into the same bar of the tune.
function Player:setDistrict(d)
  if d == self.district then return end
  self.district = d
  if self.wanted == "roam" then self:cue("roam") end
end

function Player:stop()
  self.cur, self.pending, self.after, self.resumeTo, self.wanted, self.spent = nil, nil, nil, nil, nil, nil
end

function Player:setVolume(v)
  v = tonumber(v) or 1
  if v < 0 then v = 0 elseif v > 1 then v = 1 end
  self.master = v
end

function Player:setEnabled(on) self.enabled = on and true or false end
function Player:setSpeaker(sp) self.speaker = sp end

--- The name of the track playing now, or nil.
function Player:current()
  return self.cur and self.cur.track.name or nil
end

function Player:switch(tr, at)
  local old = self.cur
  local offset, fade = 0, tr.loop
  local ot = old and old.track
  if ot and ot.loop and tr.loop and ot.sync and ot.sync == tr.sync and ot.barTicks == tr.barTicks then
    local bar = math.floor((at - old.t0) / ot.barTicks + 1e-9)
    offset = (bar % tr.bars) * tr.barTicks
    if offset >= tr.length then offset = 0 end
    fade = false
  end
  self.pending = nil
  self:start(tr, at, offset, fade)
end

function Player:finish(at)
  local tr = self.cur.track
  local nextTrack = self.after or (tr.resume and self.resumeTo) or nil
  self.after = nil
  self.resumeTo = nil
  self.spent = tr
  if nextTrack then
    self:start(nextTrack, at, 0, true)
  else
    self.cur = nil
  end
end

function Player:gain(at)
  local g = self.master
  local pend = self.pending
  if pend and pend.at > pend.from then
    local f = (at - pend.from) / (pend.at - pend.from)
    if f > 1 then f = 1 elseif f < 0 then f = 0 end
    g = g * (1 - 0.6 * f)
  end
  local cur = self.cur
  if cur.fadeFrom then
    local f = (at - cur.fadeFrom) / cur.track.barTicks
    if f >= 1 then
      cur.fadeFrom = nil
    else
      g = g * (0.45 + 0.55 * math.max(0, f))
    end
  end
  return g
end

function Player:emit(row, at)
  local sp = self.speaker
  if not self.enabled or not sp then return end
  local playNote = sp.playNote
  if type(playNote) ~= "function" and type(playNote) ~= "table" then return end
  local ms = self.clock and self.clock()
  local key = ms and math.floor(ms / 50) or self.callKey
  if key ~= self.budgetKey then
    self.budgetKey = key
    self.budgetUsed = 0
  end
  local g = self:gain(at)
  for _, n in ipairs(row.notes) do
    if self.budgetUsed >= score.MAX_NOTES then return end
    local vol = n[3] * g
    if vol >= 0.02 then
      self.budgetUsed = self.budgetUsed + 1
      local ok, res = pcall(playNote, n[1], vol, n[2])
      if ok and res ~= false then self.played = self.played + 1 end
    end
  end
end

--- Advance the music by dt seconds and play what is due.
function Player:update(dt)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > MAX_DT then dt = MAX_DT end
  self.callKey = (self.callKey or 0) + 1
  self.now = self.now + dt * TPS
  -- a hair of slack: twenty updates of 0.05 s should land on tick 20, not just short of it
  local now = self.now + 1e-6
  for _ = 1, 10000 do
    local cur = self.cur
    if not cur then return end
    local tr = cur.track
    local row = tr.rows[cur.idx]
    local rowAt = row and cur.t0 + row.tick or math.huge
    local endAt = cur.t0 + tr.length
    local switchAt = self.pending and self.pending.at or math.huge
    if switchAt <= now and switchAt <= rowAt and switchAt <= endAt then
      self:switch(self.pending.track, switchAt)
    elseif endAt <= now and endAt <= rowAt then
      if tr.loop then
        cur.t0 = endAt - tr.loopTick
        cur.idx = firstRowAt(tr, tr.loopTick)
      else
        self:finish(endAt)
      end
    elseif rowAt <= now then
      cur.idx = cur.idx + 1
      if now - rowAt <= LATE then self:emit(row, rowAt) end
    else
      return
    end
  end
end

--- Run forever (for parallel.waitForAny with the game): an update every tick, timed by the real clock.
function Player:run()
  local os_ = rawget(_G, "os")
  local last = self.clock and self.clock()
  while true do
    local id = os_.startTimer(1 / TPS)
    repeat
      local ev, arg = os_.pullEventRaw("timer")
    until ev == "timer" and arg == id
    local ms = self.clock and self.clock()
    local dt = (ms and last) and (ms - last) / 1000 or 1 / TPS
    last = ms
    self:update(dt)
  end
end

-- ---------------------------------------------------------------- the game's one player

local shared

local function readSettings()
  local fs_ = rawget(_G, "fs")
  if not fs_ or not fs_.exists or not fs_.exists("saltgate_settings.lua") then return {} end
  local ok, t = pcall(dofile, "saltgate_settings.lua")
  if ok and type(t) == "table" then return t end
  return {}
end

--- Set up the game's player. opts: speaker (false for none), sound (the game's sound setting), music (false: no
-- music but keep the effects), volume. Left out, sound and music come from saltgate_settings.lua and the speaker
-- is the first one attached.
function M.init(opts)
  opts = opts or {}
  local s = readSettings()
  local sound = opts.sound
  if sound == nil then sound = s.sound end
  local musicOn = opts.music
  if musicOn == nil then musicOn = s.music end
  local enabled = sound ~= false and musicOn ~= false
  local speaker = opts.speaker
  if speaker == nil and enabled then
    local per = rawget(_G, "peripheral")
    if per and per.find then
      local ok, sp = pcall(per.find, "speaker")
      if ok then speaker = sp end
    end
  end
  if speaker == false then speaker = nil end
  local old = shared
  shared = M.new({ speaker = speaker, enabled = enabled, volume = opts.volume or (old and old.master), loader = opts.loader,
    clock = opts.clock })
  return shared
end

local function get()
  if not shared then M.init() end
  return shared
end

function M.player() return get() end
function M.cue(name) return get():cue(name) end
function M.stop() return get():stop() end
function M.setVolume(v) return get():setVolume(v) end
function M.setDistrict(d) return get():setDistrict(d) end
function M.setEnabled(on) return get():setEnabled(on) end
function M.setSpeaker(sp) return get():setSpeaker(sp) end
function M.update(dt) return get():update(dt) end
function M.current() return get():current() end
function M.preload() return get():preload() end
function M.run() return get():run() end

return M
