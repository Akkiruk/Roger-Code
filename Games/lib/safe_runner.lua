-- safe_runner.lua
-- Shared error wrapper with crash recovery for all casino games.
-- Wraps a main function in pcall, logs crashes, and reboots.
-- With transfer-at-end, no money moves during the game, so no refund is needed.
-- Usage:
--   local safeRunner = require("lib.safe_runner")
--   safeRunner.run(main)

local sound    = require("lib.sound")
local alert    = require("lib.alert")
local recovery = require("lib.crash_recovery")

local DEBUG = settings.get("casino.debug") or settings.get("blackjack.debug") or false
local function dbg(msg) if DEBUG then print(os.epoch("local"), msg) end end

--- Run `mainFn` inside pcall with crash recovery.
-- On error: clears the recovery file (no money moved), sends an alert, and reboots.
-- @param mainFn function  The game's main loop function
local function run(mainFn)
  local ok, err = pcall(mainFn)
  if not ok then
    dbg("Error: " .. tostring(err))
    -- No money moved during the game (transfer-at-end), so just clear the bet
    local activeBet = recovery.getActiveBet()
    if activeBet and activeBet > 0 then
      print("Game crashed — no tokens were charged (bet: " .. activeBet .. ").")
      sound.play(sound.SOUNDS.ERROR)
      recovery.clearBet()
    end
    alert.send(err)
    if alert.isPlannedExit(err) then
      print("Exited: " .. tostring(err))
      os.reboot()
    else
      print("Error: " .. tostring(err))
      print("Restarting...")
      os.sleep(0.1)
      os.reboot()
    end
  end
end

return {
  run = run,
}
