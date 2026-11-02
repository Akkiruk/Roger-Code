-- games/blightmare/content.lua
-- The acts of the story, each one plain data in regions/<id>.lua, so a region can be written or rewritten without touching
-- any other. This file only finds them. Each data module (maps, story, enemies, party, overworld, art) merges what it needs at
-- the bottom of its own file, so this one depends on nothing.

local M = {}

-- In story order. Goals are read in this order too.
M.ORDER = {
  "heart", "plexios", "sindal", "windmill", "empire", "underdark", "vault", "ruin_south", "ruin_north", "ruin_deep", "finale",
}

local loaded

--- A region not there yet is simply not in the game. One that's there and broken must say so.
local function loadRegion(id)
  local name = "games.blightmare.regions." .. id
  local ok, region = pcall(require, name)
  if ok then return region end
  if tostring(region):find("not found", 1, true) then return nil end
  error(region, 0)
end

--- The regions that exist, in order.
function M.regions()
  if loaded then return loaded end
  loaded = {}
  for _, id in ipairs(M.ORDER) do
    local region = loadRegion(id)
    if region then loaded[#loaded + 1] = region end
  end
  return loaded
end

return M
