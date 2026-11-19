-- progress/stats.lua
-- The numbers kept for good: miles driven, money earned, jumps landed ... and the sets (districts seen, stations
-- heard). They live in the save's progress section (stats = { name = number }, sets = { name = { member = true } }),
-- so they are written with every save. Pure.
--
--   local s = stats.new(save.progress)
--   s:add("distance", 12)   s:max("topSpeed", 90)   s:get("distance")
--   s:member("districts", "gilt") -> true when it is new      s:count("districts")

local M = {}
local S = {}
S.__index = S

-- what each stat is called on the stats screen, in the order shown: { key, label, kind } (kind: "n" | "m" money | "d" distance | "t" time | "s" speed)
M.LIST = {
  { "playSeconds", "Time played", "t" },
  { "distance", "Driven", "d" },
  { "onFoot", "Walked", "d" },
  { "topSpeed", "Top speed", "s" },
  { "airtime", "Time in the air", "t" },
  { "moneyEarned", "Money earned", "m" },
  { "moneySpent", "Money spent", "m" },
  { "missionsPassed", "Jobs done", "n" },
  { "missionsFailed", "Jobs failed", "n" },
  { "carsStolen", "Cars taken", "n" },
  { "maxHeat", "Highest wanted level", "n" },
  { "heatCleared", "Patrols lost", "n" },
  { "arrests", "Times cuffed", "n" },
  { "knockouts", "Times knocked out", "n" },
  { "jumps", "Stunt jumps landed", "n" },
  { "longestJump", "Longest jump", "d" },
  { "racesRun", "Races finished", "n" },
  { "racesGold", "Race golds", "n" },
  { "fares", "Taxi fares", "n" },
  { "deliveries", "Parcels delivered", "n" },
  { "rentEarned", "Rent collected", "m" },
}

function M.new(section)
  section.stats = section.stats or {}
  section.sets = section.sets or {}
  return setmetatable({ sec = section }, S)
end

--- Point at a (re)loaded progress section.
function S:use(section)
  section.stats = section.stats or {}
  section.sets = section.sets or {}
  self.sec = section
end

function S:get(key) return self.sec.stats[key] or 0 end

function S:add(key, n)
  self.sec.stats[key] = (self.sec.stats[key] or 0) + (n or 1)
  return self.sec.stats[key]
end

function S:max(key, v)
  if v > (self.sec.stats[key] or 0) then self.sec.stats[key] = v end
  return self.sec.stats[key] or 0
end

function S:set(key, v) self.sec.stats[key] = v end

--- Add a member to a set; true when it was not there.
function S:member(set, name)
  local s = self.sec.sets[set]
  if not s then
    s = {}
    self.sec.sets[set] = s
  end
  if s[name] then return false end
  s[name] = true
  return true
end

function S:count(set)
  local n = 0
  for _ in pairs(self.sec.sets[set] or {}) do n = n + 1 end
  return n
end

--- A stat as the stats screen shows it.
function M.format(kind, v)
  v = v or 0
  if kind == "m" then
    return require("sg.util").money(v)
  elseif kind == "d" then
    if v >= 1000 then return string.format("%.1f km", v / 1000) end
    return string.format("%d m", math.floor(v + 0.5))
  elseif kind == "t" then
    local s = math.floor(v + 0.5)
    if s >= 3600 then return string.format("%dh %02dm", math.floor(s / 3600), math.floor(s / 60) % 60) end
    if s >= 60 then return string.format("%dm %02ds", math.floor(s / 60), s % 60) end
    return s .. "s"
  elseif kind == "s" then
    return math.floor(v + 0.5) .. " km/h"
  end
  return tostring(math.floor(v + 0.5))
end

return M
