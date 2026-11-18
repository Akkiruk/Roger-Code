-- story/cutscene.lua
-- A cutscene is a list of camera shots played one after another, with letterbox bars, a caption or a line of talk, and a
-- fade between shots. X skips all of it; ENTER moves to the next shot. Pure: it works out the camera, the screen draws it.
--
-- A shot:
--   at      where the camera is: a place name, { x, z [, y] } or "player"
--   look    what it looks at: a place name, { x, z [, y] } or "player"   (default "player")
--   height  camera height above the ground at `at` (default 5; an explicit y in `at` wins)
--   seconds how long (default 3)
--   drift   { dx, dz, dy } the camera slides this far over the shot (a dolly)
--   orbit   degrees the camera swings round what it looks at over the shot
--   caption text shown big in the lower bar
--   say     { who, text } a spoken line under the picture
--   title   text shown on its own centred (a title card, over black when black = true)
--   black   true: the shot is a black screen (a card), not the world
--   fade    "in" | "out" | "both": fade from or to black
--
--   local c = cutscene.new(shots, resolve)    resolve(spec) -> x, y, z  (nil y: the ground)
--   c:update(dt)  c:next()  c:skip()  c.done  c:shot()  c:camera() -> { x, y, z, yaw, pitch (degrees) }
--   c:fade() -> 0 (clear) .. 1 (black)

local text = require("sg.story.text")

local M = {}
local C = {}
C.__index = C

M.DEFAULT_SECONDS = 3
M.FADE = 0.45

--- Check a shot list; returns true or false and why (tests use it on every cutscene in the story).
function M.validate(shots)
  if type(shots) ~= "table" or #shots == 0 then return false, "no shots" end
  for i, s in ipairs(shots) do
    if type(s) ~= "table" then return false, "shot " .. i .. " is not a table" end
    if not s.black and s.at == nil and not s.title then return false, "shot " .. i .. " has no camera" end
    if s.seconds ~= nil and (type(s.seconds) ~= "number" or s.seconds <= 0 or s.seconds > 20) then
      return false, "shot " .. i .. ": seconds must be 0-20"
    end
    if s.caption and not text.fits(s.caption, text.SCREEN - 4, 2) then return false, "shot " .. i .. ": caption too long" end
    if s.title and not text.fits(s.title, text.SCREEN - 4, 2) then return false, "shot " .. i .. ": title too long" end
    if s.say then
      if type(s.say) ~= "table" or type(s.say[1]) ~= "string" or type(s.say[2]) ~= "string" then
        return false, "shot " .. i .. ": say is { who, text }"
      end
      if not text.fits(s.say[2], text.TEXT, text.ROWS) then return false, "shot " .. i .. ": the line does not fit" end
    end
  end
  return true
end

function M.new(shots, resolve)
  local c = setmetatable({ shots = shots, resolve = resolve, index = 1, t = 0, done = false, skipped = false }, C)
  if #shots == 0 then c.done = true end
  return c
end

function C:shot() return self.shots[self.index] end

local function length(shot) return shot.seconds or M.DEFAULT_SECONDS end

function C:next()
  if self.done then return end
  self.index = self.index + 1
  self.t = 0
  if self.index > #self.shots then self.done = true end
end

function C:skip()
  self.skipped, self.done = true, true
end

function C:update(dt)
  if self.done then return end
  self.t = self.t + dt
  local s = self:shot()
  if s and self.t >= length(s) then self:next() end
end

--- 0 clear .. 1 black, for the current moment of the shot.
function C:fade()
  local s = self:shot()
  if not s then return 0 end
  if s.black then return 1 end
  local f = s.fade
  if not f then return 0 end
  local len = length(s)
  local k = 0
  if f == "in" or f == "both" then k = math.max(k, 1 - math.min(1, self.t / M.FADE)) end
  if f == "out" or f == "both" then k = math.max(k, 1 - math.min(1, (len - self.t) / M.FADE)) end
  return k
end

--- The camera for now: from `at` (with the drift and orbit applied) looking at `look`.
function C:camera()
  local s = self:shot()
  if not s or s.black or s.at == nil then return nil end
  local ax, ay, az = self.resolve(s.at)
  local lx, ly, lz = self.resolve(s.look or "player")
  if not ax or not lx then return nil end
  local k = math.min(1, self.t / length(s))
  ay = (type(s.at) == "table" and s.at[3]) or ((ay or 0) + (s.height or 5))
  if s.drift then
    ax = ax + (s.drift[1] or 0) * k
    az = az + (s.drift[2] or 0) * k
    ay = ay + (s.drift[3] or 0) * k
  end
  ly = (ly or 0) + 1
  if s.orbit then
    local a = math.rad(s.orbit) * k
    local dx, dz = ax - lx, az - lz
    ax = lx + dx * math.cos(a) - dz * math.sin(a)
    az = lz + dx * math.sin(a) + dz * math.cos(a)
  end
  local dx, dz = lx - ax, lz - az
  local flat = math.sqrt(dx * dx + dz * dz)
  local atan2 = math.atan2 or math.atan
  return { x = ax, y = ay, z = az, yaw = atan2(dz, dx), pitch = -math.deg(atan2(ay - ly, math.max(flat, 0.1))) }
end

return M
