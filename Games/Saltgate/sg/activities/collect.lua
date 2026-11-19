-- activities/collect.lua
-- The 50 gull totems and 10 postcards: walk or drive within reach and they are yours, once, for good. Found ones are
-- kept in save.activities.found. Each find pays, announces itself ("pickup" event) and counts toward the 100% tracker.
--
--   local c = collect.new(ctx, layout, section)
--   c:update(dt)           look for finds near the player
--   c:counts(kind) -> found, total          kind: "totem" | "postcard"
--   c:markers(x, z) -> markers for the unfound ones near (x, z)

local common = require("sg.activities.common")
local wallet = require("sg.progress.wallet")

local M = {}
local C = {}
C.__index = C

M.REACH = 2.8
M.VALUE = { totem = 40, postcard = 120 }
M.SHOW = 70 -- how far away a marker is drawn

function M.new(ctx, layout, section)
  return setmetatable({ ctx = ctx, section = section, lists = { totem = layout.totems or {}, postcard = layout.postcards or {} } }, C)
end

function C:use(section) self.section = section end

function C:counts(kind)
  local n = 0
  for _, it in ipairs(self.lists[kind]) do
    if self.section.found[kind][it.id] then n = n + 1 end
  end
  return n, #self.lists[kind]
end

function C:has(kind, id) return self.section.found[kind][id] == true end

--- Collect one item now (also what a walk-over does).
function C:take(kind, it)
  if self.section.found[kind][it.id] then return false end
  self.section.found[kind][it.id] = true
  local value = M.VALUE[kind]
  wallet.add(self.ctx, value, kind)
  self.ctx.bus:emit("pickup", { kind = kind, id = it.id, value = value })
  local found, total = self:counts(kind)
  if self.ctx.hud then
    if kind == "totem" then
      self.ctx.hud.toast("Gull totem " .. found .. "/" .. total, "lime", 3.5, "+$" .. value)
    else
      self.ctx.hud.toast(it.name .. ": " .. it.text, "pink", 8, "Postcard " .. found .. "/" .. total)
    end
  end
  return true
end

function C:update(dt)
  local x, y, z = common.where(self.ctx)
  local r2 = M.REACH * M.REACH
  for _, kind in ipairs({ "totem", "postcard" }) do
    for _, it in ipairs(self.lists[kind]) do
      if not self.section.found[kind][it.id] then
        local dx, dz = it.x - x, it.z - z
        if dx * dx + dz * dz <= r2 and math.abs((it.y or 0) - y) < 4.5 then self:take(kind, it) end
      end
    end
  end
end

function C:markers(x, z, out)
  out = out or {}
  for _, kind in ipairs({ "totem", "postcard" }) do
    for _, h in ipairs(common.near(self.lists[kind], x, z, M.SHOW)) do
      local it = h.item
      if not self.section.found[kind][it.id] then
        out[#out + 1] = { kind = kind == "totem" and "totem" or "card", x = it.x, y = it.y, z = it.z, h = 0, d2 = h.d2 }
      end
    end
  end
  return out
end

return M
