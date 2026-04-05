-- manifest-key: pokertable
-- manifest-name: PokerTable
-- manifest-description: Multiplayer poker table foundation with dealer and seat modes.
-- manifest-category: Games
-- Multiplayer poker table foundation with rednet transport and CCVault escrow.

local cfg = require("pokertable_config")
local pokerLog = require("lib.poker_log")
local dealer = require("dealer")
local seat = require("seat")

local logger = pokerLog.new(cfg.ERROR_LOG_FILE, false)

local function chooseMode()
  print("")
  print("PokerTable")
  print("")
  print("1. Dealer mode")
  print("2. Seat mode")
  print("3. Audit summary")
  print("")

  while true do
    write("Choose mode [1]: ")
    local answer = read()
    if answer == nil or answer == "" or answer == "1" then
      return "dealer"
    end
    if answer == "2" then
      return "seat"
    end
    if answer == "3" then
      return "audit"
    end
    print("Enter 1, 2, or 3.")
  end
end

local function showAuditSummary()
  print("")
  print("Audit Summary")
  print("")
  print("- Same-host enforcement is required for all seats.")
  print("- Buy-ins are deduped by CCVault transaction ID.")
  print("- Cash-outs are deduped by settlement ID.")
  print("- Dealer owns chip state, seat owns wallet access.")
  print("- Dealer and seat state are both persisted for reconnects.")
  print("")
end

local function main(args)
  local mode = nil
  if args[1] == "dealer" or args[1] == "seat" or args[1] == "audit" then
    mode = args[1]
  else
    mode = chooseMode()
  end

  if mode == "audit" then
    showAuditSummary()
    return
  end

  if mode == "dealer" then
    dealer.run()
    return
  end

  seat.run()
end

local ok, err = pcall(function()
  main({ ... })
end)

if not ok then
  logger.write(tostring(err))
  printError(tostring(err))
end