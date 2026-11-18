-- vehicles/catalog.lua
-- Reads the vehicle files in content/vehicles and registers every definition with the core (core/vehicles.lua) and
-- with today's car table (sg/vehicle.lua TYPES, so vehicle.new(kind) builds them and the model cache can find their
-- shape). A definition is registered once; loading twice changes nothing.
--
--   catalog.load(content, vehicles, vehicleLib) -> count, problems
--   catalog.FILES   the data files, in order

local M = {}

M.FILES = { "vehicles/cars.lua", "vehicles/bikes.lua", "vehicles/trucks.lua", "vehicles/boats.lua", "vehicles/air.lua" }

--- content: core/content.lua's object; vehicles: core/vehicles.lua; vehicleLib: sg/vehicle.lua (or nil to skip TYPES).
function M.load(content, vehicles, vehicleLib)
  local count, problems = 0, {}
  for _, file in ipairs(M.FILES) do
    local list, err = content:data(file)
    if not list then
      problems[#problems + 1] = file .. ": " .. tostring(err)
    else
      for _, def in ipairs(list) do
        if not vehicles.get(def.id) then
          local ok, derr = vehicles.validate(def)
          if ok then
            vehicles.define(def)
            if vehicleLib and vehicleLib.TYPES and not vehicleLib.TYPES[def.id] then vehicleLib.TYPES[def.id] = def end
            count = count + 1
          else
            problems[#problems + 1] = file .. ": " .. tostring(derr)
          end
        end
      end
    end
  end
  local tune, terr = content:data("vehicles/tune.lua")
  if tune then
    require("sg.vehicles.custom").setData(tune)
  else
    problems[#problems + 1] = "vehicles/tune.lua: " .. tostring(terr)
  end
  return count, problems
end

return M
