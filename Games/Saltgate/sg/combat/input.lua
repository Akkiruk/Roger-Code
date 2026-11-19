-- combat/input.lua
-- The combat keys, one key per action: J fire (hold it), K next target, L next weapon, 1-6 a weapon by number.
-- The core's input object is made after the plugins load, through sg/input.lua's new(), so wrapping that adds the
-- keys to the one the game uses (and hands it to the plugin as ctx.input) without editing the core. A player who is
-- knocked down reads as having pressed nothing: they cannot steer or run until they are back up.
--
-- The core now makes ctx.input before the plugins load, so install also extends that one (keyCodes: CC's keys).
--
--   input.install(getCtx, keyCodes?)   input.uninstall()   input.read(inp) -> { fire, target, weapon, slot }

local M = {}

local saved = nil
local SLOTS = { "one", "two", "three", "four", "five", "six" }

function M.installed() return saved ~= nil end

-- Add the combat keys to one input object (once).
local function extend(inp, keys, ctx)
  if inp._combatKeys then return inp end
  inp._combatKeys = true
  inp.map.fire = { keys.j }
  inp.map.target = { keys.k }
  inp.map.weapon = { keys.l }
  for i, name in ipairs(SLOTS) do inp.map["slot" .. i] = { keys[name] } end
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

function M.install(getCtx, keyCodes)
  if saved then return false end
  local inputlib = require("sg.input")
  saved = inputlib.new
  inputlib.new = function(keys)
    local ctx = getCtx()
    local inp = extend(saved(keys), keys, ctx)
    if ctx then ctx.input = inp end
    return inp
  end
  -- the core makes ctx.input before the plugins load (ctx.input = inputlib.new(keys) in makeContext): extend that one
  local ctx = getCtx()
  local codes = keyCodes or rawget(_G, "keys")
  if ctx and ctx.input and ctx.input.map and codes then extend(ctx.input, codes, ctx) end
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
