-- radio.lua
-- The car radio, and the one place that decides which cue of the soundtrack plays. Four stations (content/activities/radio.lua),
-- each a track of music/ with a DJ who says a line now and then; R steps through the stations and off. On foot, in a
-- chase, on a job or at the title the soundtrack follows the game the way the live game's hints do. Pure: the music player
-- is given to it, so the tests give it a recording stand-in.
--
--   local r = radio.new({ data = stationsTable, music = musicModule, station = 1,
--                         onLine = function(station, text) end, onHear = function(station) end })
--   r:setState({ title = bool, car = bool, heat = n, mission = bool, district = "gilt" })
--   r:update(dt)          advance the DJ's timer and keep the right cue playing
--   r:next()              R: the next station, then off, then the first again
--   r:label() -> "98.1 Gull FM" or "radio off"     r.station (0 = off)
--   r:cueFor(state) -> the cue the soundtrack should play, or nil for silence

local M = {}
local R = {}
R.__index = R

M.HEAR_AFTER = 3 -- seconds on a station before it counts as heard

function M.new(opts)
  local data = opts.data
  local self = setmetatable({
    stations = data.stations, lineSeconds = data.lineSeconds or 7, gapSeconds = data.gapSeconds or 40,
    music = opts.music, onLine = opts.onLine, onHear = opts.onHear,
    station = opts.station or 1, state = { car = false, heat = 0 }, cued = nil, dj = 0, line = 0, heard = 0,
    district = nil, enabled = true,
  }, R)
  return self
end

function R:current()
  return self.station > 0 and self.stations[self.station] or nil
end

--- The cue the soundtrack should be playing for a game state.
function R:cueFor(state)
  if state.title then return "title" end
  local heat = state.heat or 0
  if heat >= 3 then return "heat_high" end
  if heat >= 1 then return "heat_low" end
  if state.car then
    local s = self:current()
    if s then return s.track end
    return nil -- a car with the radio off is quiet
  end
  if state.mission then return "job" end
  return "free_roam"
end

function R:setState(state)
  self.state = state
  if state.district and state.district ~= self.district then
    self.district = state.district
    if self.music and self.music.setDistrict then self.music.setDistrict(state.district) end
  end
end

function R:apply()
  local cue = self:cueFor(self.state)
  if cue == self.cued then return end
  self.cued = cue
  local m = self.music
  if not m then return end
  if cue then m.cue(cue) else m.stop() end
end

--- Step to the next station (then off, then the first).
function R:next()
  self.station = self.station + 1
  if self.station > #self.stations then self.station = 0 end
  self.heard = 0
  self.dj = 1.2 -- the new station's DJ speaks soon
  self:apply()
  return self.station
end

function R:tune(i)
  self.station = math.max(0, math.min(#self.stations, i))
  self.heard = 0
  self.dj = 1.2
  self:apply()
end

function R:label()
  local s = self:current()
  if not s then return "radio off" end
  return s.freq .. " " .. s.name
end

function R:update(dt)
  self:apply()
  local s = self:current()
  if not (self.state.car and s) or (self.state.heat or 0) >= 1 then
    self.heard = 0
    return
  end
  self.heard = self.heard + dt
  if self.heard >= M.HEAR_AFTER and self.heard - dt < M.HEAR_AFTER and self.onHear then self.onHear(s) end
  self.dj = self.dj - dt
  if self.dj <= 0 then
    self.dj = self.gapSeconds
    self.line = self.line + 1
    local lines = s.lines
    local text = lines[(self.line - 1) % #lines + 1]
    if self.onLine then self.onLine(s, text) end
  end
end

--- The current station's index in the list (for saving) and back.
function R:saveState() return self.station end

return M
