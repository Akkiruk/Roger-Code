-- sound.lua
-- Shared sound effects manager for all casino games.
-- Wraps a speaker peripheral and provides named sound constants.
-- Usage:
--   local sound = require("lib.sound")
--   sound.init("top")                     -- wrap speaker on "top"
--   sound.play(sound.SOUNDS.SUCCESS)      -- play a named sound
--   sound.play("minecraft:block.note_block.pling", 0.8)

local peripherals = require("lib.peripherals")
local picks = require("lib.sound_picks")

local speaker = nil

-- Common casino sound effects (game-specific ones can be added via addSounds)
local SOUNDS = {
  ERROR   = picks.ui_error[1],
  SUCCESS = picks.win_big[1],
  FAIL    = picks.lose[1],
  ALL_IN  = picks.chip_stack[1],
  CLEAR   = picks.ui_back[1],
  START   = picks.ui_start[1],
  PUSH    = picks.draw[1],
  CARD_PLACE = picks.card_deal[1],
  BOOT    = picks.ui_boot[1],
  TIMEOUT = picks.ui_timeout[1],
}

--- Initialize the speaker peripheral.
-- @param side string|nil  Side to wrap, or nil to auto-find via peripherals.find
-- @return boolean  true if speaker is available
local function init(side)
  if side and peripheral.hasType(side, "speaker") then
    speaker = peripheral.wrap(side)
  end
  if not speaker then
    speaker = peripherals.find("speaker")
  end
  return speaker ~= nil
end

--- Play a sound effect.
-- @param soundID string  Minecraft resource ID
-- @param volume  number? Volume 0.0-3.0, default 0.5
-- @param pitch   number? Pitch 0.5-2.0, default 1.0
-- @return boolean, string|nil
local function play(soundID, volume, pitch)
  if not speaker then
    return false, "No speaker available"
  end

  if type(soundID) ~= "string" or soundID == "" then
    return false, "Invalid sound ID"
  end

  volume = volume or 0.5
  pitch = pitch or 1.0

  local ok, result = pcall(function()
    return speaker.playSound(soundID, volume, pitch)
  end)

  if not ok then
    return false, tostring(result)
  end

  if result == false then
    return false, "Speaker is busy"
  end

  return true, nil
end

--- Register additional named sounds (game-specific).
-- @param tbl table  Keys = names, values = sound IDs
local function addSounds(tbl)
  assert(type(tbl) == "table", "addSounds expects a table")
  for k, v in pairs(tbl) do
    SOUNDS[k] = v
  end
end

--- Check if the speaker was found.
-- @return boolean
local function isAvailable()
  return speaker ~= nil
end

return {
  init        = init,
  play        = play,
  addSounds   = addSounds,
  isAvailable = isAvailable,
  SOUNDS      = SOUNDS,
}
