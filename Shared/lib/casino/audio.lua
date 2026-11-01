-- audio.lua
-- Sounds by what happened, not by file. The sounds live in lib/sound_picks.lua, and any name in
-- there can be played here too.

local picks = require("lib.sound_picks")

local M = {}

local SOUNDS = {
  tap = picks.ui_tap, chip = picks.chip_one, chipBig = picks.chip_stack, error = picks.ui_error,
  deal = picks.card_deal, flip = picks.card_flip, start = picks.ui_start, tick = picks.ui_tick,
  spin = picks.wheel_tick, stop = picks.wheel_stop, win = picks.win_small, bigWin = picks.win_big,
  lose = picks.lose, push = picks.draw, warn = picks.ui_warning,
}

local speaker = nil

--- Find the speaker. Safe to call again whenever the peripherals change.
function M.init()
  speaker = peripheral.find("speaker")
end

function M.play(name, volumeScale, pitchScale)
  local sound = SOUNDS[name] or picks[name]
  if not (speaker and sound) then return end
  pcall(speaker.playSound, sound[1], sound[2] * (volumeScale or 1), sound[3] * (pitchScale or 1))
end

return M
