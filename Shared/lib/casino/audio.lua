-- audio.lua
-- Sounds by what happened, not by file. Every id here is already in use on the pack.

local M = {}

local SOUNDS = {
  tap = { "buildinggadgets:beep", 0.35, 1.3 },
  chip = { "the_vault:coin_single_place", 0.7, 1.1 },
  chipBig = { "lightmanscurrency:coins_clinking", 0.7, 1.0 },
  error = { "the_vault:mob_trap", 0.35, 1.2 },
  deal = { "casinocraft:casinocraft.card.place", 0.7, 1.05 },
  flip = { "casinocraft:casinocraft.card.place", 0.7, 0.85 },
  start = { "the_vault:raid_gate_open", 0.45, 1.2 },
  tick = { "quark:ambient.clock", 0.45, 1.4 },
  spin = { "quark:ambient.clock", 0.4, 0.9 },
  stop = { "the_vault:coin_pile_place", 0.7, 1.0 },
  win = { "the_vault:puzzle_completion_major", 0.8, 1.0 },
  bigWin = { "the_vault:artifact_complete", 0.8, 1.0 },
  lose = { "the_vault:puzzle_completion_fail", 0.45, 1.0 },
  push = { "the_vault:rampage", 0.3, 1.2 },
  warn = { "quark:ambient.clock", 0.6, 0.7 },
}

local speaker = nil

--- Find the speaker. Safe to call again whenever the peripherals change.
function M.init()
  speaker = peripheral.find("speaker")
end

function M.play(name, volumeScale, pitchScale)
  local sound = SOUNDS[name]
  if not (speaker and sound) then return end
  pcall(speaker.playSound, sound[1], sound[2] * (volumeScale or 1), sound[3] * (pitchScale or 1))
end

return M
