-- safe_runner.lua
-- Shared error wrapper with crash recovery for all casino games.
-- Wraps a main function in pcall, refunds active bets on crash, and reboots.
-- Usage:
--   local safeRunner = require("lib.safe_runner")
--   safeRunner.run(main)

local currency = require("lib.currency")
local sound    = require("lib.sound")
local alert    = require("lib.alert")
local recovery = require("lib.crash_recovery")

local DEBUG = settings.get("casino.debug") or settings.get("blackjack.debug") or false
local function dbg(msg) if DEBUG then print(os.time(), msg) end end

--- Run `mainFn` inside pcall with crash recovery.
-- On error: refunds any active bet, sends an alert, and reboots.
-- @param mainFn function  The game's main loop function
local function run(mainFn)
  local ok, err = pcall(mainFn)
  if not ok then
    dbg("Error: " .. tostring(err))
    local activeBet = recovery.getActiveBet()
    if activeBet and activeBet > 0 then
      print("Returning " .. activeBet .. " tokens from crashed game...")
      sound.play(sound.SOUNDS.ERROR)
      if currency.payout(activeBet, "crash recovery refund") then
        recovery.clearBet()
        print("Bet returned successfully.")
      else
        alert.log("CRITICAL: Failed to return " .. activeBet .. " tokens during crash")
        print("ERROR: Could not return bet. Contact admin.")
      end
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
