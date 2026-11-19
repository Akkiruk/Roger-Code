-- activities/genlayout.lua
-- Writes content/activities/layout.lua from a city. Run it from the Saltgate folder with desktop Lua whenever the city
-- changes (or by the integrator when a new city lands):
--   lua sg/activities/genlayout.lua testbed                       the step 0 testbed island
--   lua sg/activities/genlayout.lua content/world/*.sgc           the packed chunks of the real city
-- Prints what it placed and what the city could not give (fewer than 20 places to jump, and so on).

package.path = "./?.lua;" .. package.path
local layout = require("sg.activities.layout")
local chunkLib = require("sg.core.chunk")

local args = { ... }
local chunks = {}
if args[1] == "testbed" or #args == 0 then
  for k, c in pairs(require("sg.core.testbed").chunks()) do chunks[k] = c end
else
  for _, path in ipairs(args) do
    local h = assert(io.open(path, "rb"))
    local text = h:read("*a")
    h:close()
    local list = assert(chunkLib.unpackMany(text))
    for _, c in ipairs(list) do chunks[chunkLib.key(c.cx, c.cz)] = c end
  end
end

local out, warnings = layout.generate(chunks, { seed = 1 })
local h = assert(io.open("content/activities/layout.lua", "wb"))
h:write(layout.serialise(out))
h:close()
for k, n in pairs(layout.counts(out)) do print(k, n) end
for _, w in ipairs(warnings) do print("WARNING: " .. w) end
for _, p in ipairs(layout.check(out, chunks)) do print("PROBLEM: " .. p) end
