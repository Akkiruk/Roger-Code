-- ai/scene.lua
-- How stream C draws what the core's view does not: people, cars far enough away to run without physics, the helicopter,
-- the boat, roadblocks and the searchlight, plus dots on the minimap. The v2 view draws only ctx.cars and the player,
-- so this wraps ctx.view's scene() and minimap() on the instance (the view's own code is untouched) and adds layers.
-- A layer that errors three times is switched off and logged, so a bad model never stops the game. Pure but for the view.
--
--   scene.layer(ctx, name, function(ctx, view, list, cam) end)       add things to the scene's object list
--   scene.minimap(ctx, name, function(ctx, view, dot) end)          dot(x, z, colour) paints a minimap pixel
--   scene.ensure(ctx)                                                call every frame: (re)installs the wrappers

local M = {}

local cos, sin, abs, floor = math.cos, math.sin, math.abs, math.floor

local function state(ctx)
  local st = ctx.aiScene
  if not st then
    st = { layers = {}, mini = {}, errors = {} }
    ctx.aiScene = st
  end
  return st
end

function M.layer(ctx, name, fn)
  local st = state(ctx)
  st.layers[#st.layers + 1] = { name = name, fn = fn }
end

function M.minimap(ctx, name, fn)
  local st = state(ctx)
  st.mini[#st.mini + 1] = { name = name, fn = fn }
end

local function run(ctx, st, set, view, ...)
  for _, l in ipairs(set) do
    if not l.dead then
      local ok, err = pcall(l.fn, ctx, view, ...)
      if not ok then
        l.fails = (l.fails or 0) + 1
        if ctx.log then ctx.log("c scene layer " .. l.name .. ": " .. tostring(err)) end
        if l.fails >= 3 then l.dead = true end
      end
    end
  end
end

--- Where a world point lands on the minimap: the same maths as the view's own minimap (heading up).
local function mapper(ctx, view)
  local b = view.minimapBox
  if not b or not view.r or not view.r.buffer then return nil end
  local rows = view.r.buffer.colorValues
  local p = ctx.player
  local car = p.car
  local px, pz = p.x, p.z
  if car then px, pz = car.x, car.z end
  local scale = car and (2.4 + math.max(0, math.min(1.6, abs(car.v) / 25))) or 1.8
  local yaw = view.cam and view.cam.yaw or p.h
  local fx, fz = cos(yaw), sin(yaw)
  local rx, rz = -fz, fx
  return function(x, z, colour)
    local dx, dz = x - px, z - pz
    local u = floor(b.w / 2 + (dx * rx + dz * rz) / scale)
    local v = floor(b.h / 2 - (dx * fx + dz * fz) / scale)
    if u >= 0 and u < b.w and v >= 0 and v < b.h then rows[b.y0 + v][b.x0 + u] = colour end
  end
end

function M.ensure(ctx)
  local view = ctx.view
  if not view then return end
  local st = state(ctx)
  if view.scene ~= st.scene then
    local orig = view.scene
    st.scene = function(self, c)
      local list = orig(self, c)
      run(ctx, st, st.layers, self, list, self.cam)
      return list
    end
    view.scene = st.scene
  end
  if view.minimap ~= st.minimap then
    local orig = view.minimap
    st.minimap = function(self, c)
      orig(self, c)
      if #st.mini > 0 then
        local dot = mapper(ctx, self)
        if dot then run(ctx, st, st.mini, self, dot) end
      end
    end
    view.minimap = st.minimap
  end
end

return M
