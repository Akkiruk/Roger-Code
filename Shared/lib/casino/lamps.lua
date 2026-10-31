-- lamps.lua
-- A redstone pulse on a big win or a jackpot, for lamps or fireworks. Through a redstone integrator if the computer has one,
-- otherwise the computer's own output, which needs no peripheral. A wall with nothing wired to it is unaffected.
-- Everything goes through M.worker: pulse() only queues, so the integrator's calls never wait in the main loop, and the timing
-- of a pulse cannot hold up a frame. Everything to change about the outputs is in the settings below.

local M = {}

M.SIDES = { "top", "bottom", "back", "left", "right", "front" }  -- the computer's own output: the first with no peripheral on it
M.INTEGRATOR_SIDE = "top"
M.PULSES = {
  bigWin = { count = 3, on = 0.4, off = 0.3 },
  jackpot = { count = 8, on = 0.3, off = 0.2 },
}

local QUEUE_LIMIT = 3
local WAKE = "casino_lamps"

local queue = {}      -- what is waiting to flash
local tidy = true     -- an integrator keeps its output through a reboot, so it is switched off before the first pulse

--- Flash a pulse from M.PULSES. Queued, so this never waits.
function M.pulse(kind)
  if not M.PULSES[kind] or #queue >= QUEUE_LIMIT then return end
  queue[#queue + 1] = kind
  os.queueEvent(WAKE)
end

--- Call when the peripherals change: an integrator that has just arrived may have been left on.
function M.rescan()
  tidy = true
  os.queueEvent(WAKE)
end

--- The side of the computer free to use, or nil if a peripheral is on every one.
local function freeSide()
  for _, side in ipairs(M.SIDES) do
    if not peripheral.isPresent(side) then return side end
  end
  return nil
end

--- Set the output. Only call this from M.worker. A peripheral pulled out halfway through changes nothing here.
local function output(side, on)
  local integrator = peripheral.find("redstoneIntegrator")
  if integrator then
    pcall(integrator.setOutput, M.INTEGRATOR_SIDE, on)
  elseif side then
    pcall(redstone.setOutput, side, on)
  end
end

local function flash(kind)
  local pattern = M.PULSES[kind]
  local side = freeSide()
  for _ = 1, pattern.count do
    output(side, true)
    sleep(pattern.on)
    output(side, false)
    sleep(pattern.off)
  end
end

--- Plays what is queued, for as long as the table runs.
function M.worker()
  while true do
    if tidy then
      tidy = false
      local integrator = peripheral.find("redstoneIntegrator")
      if integrator then pcall(integrator.setOutput, M.INTEGRATOR_SIDE, false) end
    end
    while #queue > 0 do flash(table.remove(queue, 1)) end
    if not tidy then os.pullEvent(WAKE) end
  end
end

return M
