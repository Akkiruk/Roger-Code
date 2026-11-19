-- activities/markers.lua
-- What the activities put in the 3D world: gull totems, postcards, race gates, the ghost car, beacons over the places you
-- can use, stunt jump flags. A marker is { kind, x, y, z, h, colour }; the models are built once per kind and heading
-- through the renderer's variant cache, and the view's scene list gets only the nearest ones.
--
--   markers.install(ctx, source)   wrap view:scene so source(ctx) -> markers are added to every frame
--   markers.append(list, view, ctx, items)   add them to a scene list now

local models = require("sg.models")
local theme = require("sg.ui.theme")
local C = theme.C

local M = {}

M.MAX = 22

local function totem(colour)
  local l = {}
  models.box(l, -0.4, 0, -0.4, 0.4, 3.6, 0.4, C.brown, C.brown, C.black)
  models.box(l, -0.8, 1.3, -0.15, 0.8, 1.6, 0.15, C.brown, C.brown, C.brown) -- the arms
  models.box(l, -0.55, 3.6, -0.55, 0.55, 4.7, 0.55, colour, colour, C.lightGray)
  models.box(l, 0.55, 4.0, -0.15, 1.3, 4.3, 0.15, C.orange, C.orange, C.orange) -- the beak
  models.box(l, -0.12, 4.7, -0.12, 0.12, 9, 0.12, C.yellow, C.yellow, C.yellow) -- a mast you can see from the road
  return l
end

local function card()
  local l = {}
  models.box(l, -0.08, 0, -0.08, 0.08, 1.4, 0.08, C.gray, C.gray, C.gray)
  models.box(l, -0.1, 1.4, -0.8, 0.1, 2.3, 0.8, C.pink, C.white, C.white)
  models.box(l, -0.11, 1.55, -0.6, 0.11, 1.65, 0.6, C.magenta, C.magenta, C.magenta)
  return l
end

local function gate(colour, top)
  local l = {}
  local w = 6.5
  models.box(l, -0.3, 0, -w - 0.3, 0.3, 4.5, -w + 0.3, colour, colour, C.white)
  models.box(l, -0.3, 0, w - 0.3, 0.3, 4.5, w + 0.3, colour, colour, C.white)
  models.box(l, -0.2, 4.5, -w, 0.2, 5.1, w, top or colour, top or colour, top or colour)
  return l
end

local function flag()
  local l = {}
  models.box(l, -0.1, 0, -0.1, 0.1, 4, 0.1, C.white, C.white, C.white)
  models.box(l, -0.05, 2.9, 0.1, 0.05, 3.9, 1.9, C.cyan, C.cyan, C.cyan)
  return l
end

local BUILD = {
  totem = function() return totem(C.white) end,
  card = card,
  gate = function() return gate(C.cyan, C.white) end,
  gate_next = function() return gate(C.yellow, C.orange) end,
  gate_finish = function() return gate(C.lime, C.white) end,
  flag = flag,
}

function M.append(list, view, ctx, items)
  local r = view.r
  local n = 0
  for _, m in ipairs(items) do
    if n >= M.MAX then break end
    n = n + 1
    local y = m.y or 0
    if m.kind == "beacon" then
      r:place(list, r:variant("e:beacon:" .. (m.colour or "yellow"), 0, function() return models.beacon(m.colour or "yellow") end), m.x, y, m.z)
    elseif m.kind == "ghost" and m.spec then
      local spec = m.spec
      local key = "e:ghost:" .. tostring(spec.name)
      r:place(list, r:variant(key, m.h or 0, function() return models.car(spec, "cyan", false) end), m.x, y, m.z)
    elseif BUILD[m.kind] then
      local kind = m.kind
      r:place(list, r:variant("e:" .. kind, m.h or 0, BUILD[kind]), m.x, y, m.z)
    end
  end
end

--- Wrap view:scene. source(ctx) returns the markers for this frame. Safe to call again (it wraps once).
function M.install(ctx, source)
  local view = ctx.view
  if not view or type(view.scene) ~= "function" or view._eMarkers then return false end
  view._eMarkers = true
  local orig = view.scene
  view.scene = function(self, c)
    local list = orig(self, c)
    local ok, items = pcall(source, c)
    if ok and items then M.append(list, self, c, items) end
    return list
  end
  return true
end

return M
