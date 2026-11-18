-- combat/input.lua
-- The combat keys, one key per action: J fire (hold it), K next target, L next weapon, 1-6 a weapon by number.
-- The core's input object is made after the plugins load, through sg/input.lua's new(), so wrapping that adds the
-- keys to the one the game uses (and hands it to the plugin as ctx.input) without editing the core. A player who is
-- knocked down reads as having pressed nothing: they cannot steer or run until they are back up.
--
--   input.install(getCtx)   input.uninstall()   input.read(inp) -> { fire, target, weapon, slot }

local M = {}

local saved = nil
local SLOTS = { "one", "two", "three", "four", "five", "six" }

function M.installed() return saved ~= nil end

function M.install(getCtx)
  if saved then return false end
  local inputlib = require("sg.input")
  saved = inputlib.new
  inputlib.new = function(keys)
    local inp = saved(keys)
    inp.map.fire = { keys.j }
    inp.map.target = { keys.k }
    inp.map.weapon = { keys.l }
    for i, name in ipairs(SLOTS) do inp.map["slot" .. i] = { keys[name] } end
    local ctx = getCtx()
    if ctx then ctx.input = inp end
    local read = inp.read
    inp.read = function(self)
      local r = read(self)
      local cb = ctx and ctx.combat
      if cb and cb:playerDown() then
        r.throttle, r.steer, r.handbrake, r.sprint, r.enter = 0, 0, false, false, false
      end
      return r
    end
    return inp
  end
  return true
end

function M.uninstall()
  if not saved then return false end
  require("sg.input").new = saved
  saved = nil
  return true
end

--- This frame's combat keys from the game's input object.
function M.read(inp)
  local out = { fire = false, target = false, weapon = false }
  if not inp then return out end
  out.fire = inp:down("fire")
  out.target = inp:pressedAction("target")
  out.weapon = inp:pressedAction("weapon")
  for i = 1, #SLOTS do
    if inp:pressedAction("slot" .. i) then out.slot = i end
  end
  return out
end

return M
