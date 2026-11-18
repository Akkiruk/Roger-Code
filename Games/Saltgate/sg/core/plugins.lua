-- core/plugins.lua
-- How the parts of SALTGATE join the game without editing the main loop: every file in sg/plugins/ is a plugin, found
-- at start and set up in order. A plugin that fails to load is reported and left out, so one broken part never stops
-- the game. Pure apart from the fs and require it is given.
--
-- A plugin file (sg/plugins/<stream>_<thing>.lua, e.g. sg/plugins/b_vehicles.lua) returns:
--   {
--     name = "b_vehicles",          -- the same as the file name
--     order = 20,                   -- set-up order, lower first (default 50); core's own are 0-9
--     needs = { "a_world" },        -- other plugins that must have loaded first (optional)
--     init = function(ctx) end,     -- register screens, widgets, systems, events, save sections, vehicles ...
--     update = function(ctx, dt) end,  -- optional: once a frame while playing (after the world systems)
--     draw = function(ctx) end,     -- optional: after the 3D frame, before the HUD (pixel effects, overlays)
--   }
-- ctx (see core/app.lua): bus, world (entities), stream, roads, content, ui, save, vehicles, budget, player, game,
-- render, log(msg).

local M = {}

--- Plugin names in dir (default "sg/plugins"), sorted.
function M.discover(fs, dir)
  dir = dir or "sg/plugins"
  if not fs or not fs.exists(dir) then return {} end
  local out = {}
  for _, f in ipairs(fs.list(dir)) do
    local name = f:match("^([%w_]+)%.lua$")
    if name then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

--- Load and set up plugins. req: require (or a stand-in); modulePrefix: "sg.plugins.". Returns the loaded list and
-- the failures { name, err }.
function M.load(names, ctx, req, modulePrefix)
  req = req or require
  modulePrefix = modulePrefix or "sg.plugins."
  local loaded, failed, byName = {}, {}, {}
  local candidates = {}
  for _, name in ipairs(names) do
    local ok, p = pcall(req, modulePrefix .. name)
    if not ok then
      failed[#failed + 1] = { name = name, err = tostring(p) }
    elseif type(p) ~= "table" or p.name ~= name then
      failed[#failed + 1] = { name = name, err = "the file must return a table whose name is '" .. name .. "'" }
    else
      p.order = p.order or 50
      candidates[#candidates + 1] = p
    end
  end
  table.sort(candidates, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.name < b.name
  end)
  for _, p in ipairs(candidates) do
    local missing = nil
    for _, need in ipairs(p.needs or {}) do
      if not byName[need] then missing = need end
    end
    if missing then
      failed[#failed + 1] = { name = p.name, err = "needs " .. missing .. ", which did not load" }
    else
      local ok, err = true, nil
      if type(p.init) == "function" then ok, err = pcall(p.init, ctx) end
      if ok then
        loaded[#loaded + 1] = p
        byName[p.name] = p
      else
        failed[#failed + 1] = { name = p.name, err = tostring(err) }
      end
    end
  end
  return loaded, failed
end

return M
