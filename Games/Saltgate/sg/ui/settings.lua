-- ui/settings.lua
-- The settings the player can change, kept in save.settings (written with every save) and applied the moment they change.
-- Pure: side effects (the music volume, the quality level) go through hooks the plugins register.
--
--   local s = settings.new(ctx.save.settings)
--   s:get("musicVolume")   s:set("sound", false)   s:cycle("quality", 1)   s:label("quality") -> "AUTO"
--   s:hook(function(name, value, previous) end)      called after every change (and by s:applyAll())
--   s:applyAll()      push every value to the hooks (at load, so a saved volume is heard from the first note)

local M = {}
local S = {}
S.__index = S

-- name = { default, kind, choices / range, labels }
M.DEFS = {
  sound = { default = true, kind = "bool" },
  music = { default = true, kind = "bool" },
  musicVolume = { default = 0.8, kind = "range", min = 0, max = 1, step = 0.1 },
  quality = { default = "auto", kind = "choice", choices = { "auto", 0, 1, 2, 3 },
    labels = { auto = "AUTO", [0] = "HIGH", [1] = "MEDIUM", [2] = "LOW", [3] = "LOWEST" } },
  hints = { default = true, kind = "bool" },
  units = { default = "kmh", kind = "choice", choices = { "kmh", "mph" }, labels = { kmh = "KM/H", mph = "MPH" } },
}
M.ORDER = { "sound", "music", "musicVolume", "quality", "hints", "units" }

function M.new(section)
  local self = setmetatable({ sec = section, hooks = {} }, S)
  return self
end

function S:use(section) self.sec = section end

function S:get(name)
  local d = M.DEFS[name]
  local v = self.sec[name]
  if v == nil then return d.default end
  if d.kind == "range" then
    v = tonumber(v) or d.default
    if v < d.min then v = d.min elseif v > d.max then v = d.max end
  elseif d.kind == "choice" then
    local ok = false
    for _, c in ipairs(d.choices) do if c == v then ok = true end end
    if not ok then return d.default end
  elseif d.kind == "bool" then
    return v == true
  end
  return v
end

function S:hook(fn) self.hooks[#self.hooks + 1] = fn end

function S:set(name, value)
  local d = M.DEFS[name]
  if not d then return false end
  local previous = self:get(name)
  if d.kind == "range" then
    value = math.floor(value / d.step + 0.5) * d.step
    if value < d.min then value = d.min elseif value > d.max then value = d.max end
    value = math.floor(value * 100 + 0.5) / 100
  end
  self.sec[name] = value
  if value ~= previous then
    for _, h in ipairs(self.hooks) do h(name, value, previous) end
  end
  return true
end

--- Step a choice or range by dir (+1/-1); a bool flips.
function S:cycle(name, dir)
  local d = M.DEFS[name]
  local v = self:get(name)
  if d.kind == "bool" then
    self:set(name, not v)
  elseif d.kind == "range" then
    self:set(name, v + dir * d.step)
  else
    local at = 1
    for i, c in ipairs(d.choices) do if c == v then at = i end end
    at = at + dir
    if at < 1 then at = #d.choices elseif at > #d.choices then at = 1 end
    self:set(name, d.choices[at])
  end
end

--- The value as the menu shows it.
function S:label(name)
  local d = M.DEFS[name]
  local v = self:get(name)
  if d.kind == "bool" then return v and "ON" or "OFF" end
  if d.kind == "range" then return math.floor(v * 100 + 0.5) .. "%" end
  return d.labels[v] or tostring(v)
end

function S:applyAll()
  for _, name in ipairs(M.ORDER) do
    local v = self:get(name)
    for _, h in ipairs(self.hooks) do h(name, v, v) end
  end
end

return M
