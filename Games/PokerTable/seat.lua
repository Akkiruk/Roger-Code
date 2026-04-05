local cfg = require("pokertable_config")
local currency = require("lib.currency")
local pokerBank = require("lib.poker_bank")
local pokerLog = require("lib.poker_log")
local pokerProtocol = require("lib.poker_protocol")
local pokerTransport = require("lib.poker_transport")

local M = {}

local logger = pokerLog.new(cfg.SEAT_LOG_FILE, false)

local running = false
local seatState = {
  summary = nil,
  pendingBuyInId = nil,
  pendingBuyInReply = nil,
  pendingCashOutId = nil,
  pendingCashOutReply = nil,
  pendingCashOutAckId = nil,
  pendingCashOutAck = nil,
}

local function printSummary(summary)
  print("")
  print("Table: " .. tostring(summary.tableId))
  print("Dealer: " .. tostring(summary.dealerId))
  print("Host: " .. tostring(summary.hostName))
  print("Status: " .. tostring(summary.status))
  print("Buy-in: " .. tostring(summary.minBuyIn) .. " - " .. tostring(summary.maxBuyIn) .. " tokens")
  print("Open seats: " .. tostring(summary.openSeats))
  print("")

  local index = 1
  while summary.seats and summary.seats[index] do
    local seat = summary.seats[index]
    if seat.playerName then
      print(
        string.format(
          "Seat %d | %-12s | stack=%d | ready=%s | %s",
          seat.seatId,
          tostring(seat.playerName),
          seat.stack or 0,
          tostring(seat.ready),
          tostring(seat.status)
        )
      )
    else
      print("Seat " .. tostring(seat.seatId) .. " | <open>")
    end
    index = index + 1
  end

  print("")
end

local function promptInteger(label, defaultValue, minimumValue, maximumValue)
  while true do
    write(label .. " [" .. tostring(defaultValue) .. "]: ")
    local raw = read()
    local value = tonumber(raw)

    if raw == nil or raw == "" then
      return defaultValue
    end

    if value then
      value = math.floor(value)
      if value >= minimumValue and value <= maximumValue then
        return value
      end
    end

    print("Enter a whole number between " .. tostring(minimumValue) .. " and " .. tostring(maximumValue) .. ".")
  end
end

local function discoverTables()
  local discovered = {}
  local dealerIds = pokerTransport.lookupTables()
  local index = 1

  while dealerIds[index] do
    local dealerId = dealerIds[index]
    local requestEnvelope = pokerProtocol.makeEnvelope(pokerProtocol.MESSAGE_TYPES.TABLE_INFO_REQUEST, {})
    local reply = pokerTransport.request(
      dealerId,
      requestEnvelope,
      pokerProtocol.MESSAGE_TYPES.TABLE_INFO_RESPONSE,
      cfg.NETWORK_TIMEOUT
    )

    if reply and reply.payload and reply.payload.summary then
      discovered[#discovered + 1] = reply.payload.summary
    end

    index = index + 1
  end

  return discovered
end

local function chooseTable(activeSession)
  local tables = nil
  local choice = nil
  local index = nil

  if type(activeSession) == "table" and activeSession.tableId and activeSession.dealerId then
    print("Saved seat session found for table " .. tostring(activeSession.tableId) .. ".")
    write("Reconnect to saved table? [Y/n]: ")
    local answer = string.lower((read() or "") or "")
    if answer == "" or answer == "y" or answer == "yes" then
      return {
        tableId = activeSession.tableId,
        dealerId = activeSession.dealerId,
        hostName = activeSession.hostName,
        minBuyIn = activeSession.minBuyIn,
        maxBuyIn = activeSession.maxBuyIn,
      }, true
    end
  end

  tables = discoverTables()
  if #tables == 0 then
    return nil, false, "No discoverable poker tables found"
  end

  print("")
  print("Available tables:")
  print("")

  index = 1
  while tables[index] do
    local summary = tables[index]
    print(
      string.format(
        "%d. %s | dealer=%d | host=%s | open=%d | buy-in=%d-%d",
        index,
        tostring(summary.tableId),
        tonumber(summary.dealerId) or 0,
        tostring(summary.hostName),
        tonumber(summary.openSeats) or 0,
        tonumber(summary.minBuyIn) or 0,
        tonumber(summary.maxBuyIn) or 0
      )
    )
    index = index + 1
  end

  print("")
  choice = promptInteger("Choose table number", 1, 1, #tables)
  return tables[choice], false
end

local function joinTable(summary, activeSession)
  local identity = nil
  local joinEnvelope = nil
  local joinReply = nil
  local requestedSeatId = activeSession and activeSession.seatId or nil

  identity = pokerBank.authenticate(cfg.AUTH_TIMEOUT)
  if not identity then
    return nil, nil, "Authentication failed"
  end

  local hostOk, hostErr = pokerBank.ensureHost(summary.hostName)
  if not hostOk then
    return nil, nil, hostErr
  end

  joinEnvelope = pokerProtocol.makeEnvelope(pokerProtocol.MESSAGE_TYPES.JOIN_REQUEST, {
    playerName = identity.playerName,
    hostName = identity.hostName,
    seatComputerId = identity.computerId,
    requestedSeatId = requestedSeatId,
  }, {
    tableId = summary.tableId,
  })

  joinReply = pokerTransport.request(
    summary.dealerId,
    joinEnvelope,
    pokerProtocol.MESSAGE_TYPES.JOIN_RESPONSE,
    cfg.NETWORK_TIMEOUT
  )

  if not joinReply or not joinReply.payload or not joinReply.payload.ok then
    local reason = joinReply and joinReply.payload and joinReply.payload.reason or "join failed"
    return nil, nil, reason
  end

  summary = joinReply.payload.summary or summary
  return identity, joinReply.payload, nil
end

local function performInitialBuyIn(summary, joinPayload)
  local balance = currency.getPlayerBalance()
  local defaultBuyIn = summary.minBuyIn
  local amount = nil
  local buyInOk = nil
  local txId = nil
  local buyInEnvelope = nil
  local buyInReply = nil

  print("Player balance: " .. tostring(balance) .. " tokens")

  if balance < summary.minBuyIn then
    return false, "Player balance is below the table minimum buy-in"
  end

  if type(joinPayload.stack) == "number" and joinPayload.stack > 0 then
    print("Reconnected with existing stack: " .. tostring(joinPayload.stack) .. " tokens")
    return true, nil, joinPayload.stack
  end

  amount = promptInteger("Buy-in amount", defaultBuyIn, summary.minBuyIn, math.min(summary.maxBuyIn, balance))

  buyInOk, txId = pokerBank.buyIn(summary.tableId, amount)
  if not buyInOk then
    return false, "Buy-in transfer failed"
  end

  buyInEnvelope = pokerProtocol.makeEnvelope(pokerProtocol.MESSAGE_TYPES.BUYIN_NOTICE, {
    seatId = joinPayload.seatId,
    amount = amount,
    txId = txId,
  }, {
    tableId = summary.tableId,
  })

  buyInReply = pokerTransport.request(
    summary.dealerId,
    buyInEnvelope,
    pokerProtocol.MESSAGE_TYPES.BUYIN_ACK,
    cfg.NETWORK_TIMEOUT
  )

  if not buyInReply or not buyInReply.payload or not buyInReply.payload.ok then
    return false, "Dealer did not accept the buy-in notice"
  end

  return true, nil, buyInReply.payload.stack
end

local function sendReadyUpdate(activeSession, ready)
  local envelope = pokerProtocol.makeEnvelope(pokerProtocol.MESSAGE_TYPES.READY_UPDATE, {
    seatId = activeSession.seatId,
    ready = ready,
  }, {
    tableId = activeSession.tableId,
  })

  pokerTransport.sendEnvelope(activeSession.dealerId, envelope)
end

local function sendHeartbeat(activeSession)
  local envelope = pokerProtocol.makeEnvelope(pokerProtocol.MESSAGE_TYPES.HEARTBEAT, {
    seatId = activeSession.seatId,
  }, {
    tableId = activeSession.tableId,
  })

  pokerTransport.sendEnvelope(activeSession.dealerId, envelope)
end

local function startRebuy(activeSession)
  local balance = currency.getPlayerBalance()

  if seatState.pendingBuyInId or seatState.pendingBuyInReply then
    print("A rebuy is already waiting for dealer acknowledgement.")
    return
  end

  if balance < activeSession.minBuyIn then
    print("Your balance is below the table minimum buy-in.")
    return
  end

  local amount = promptInteger(
    "Rebuy amount",
    activeSession.minBuyIn,
    activeSession.minBuyIn,
    math.min(activeSession.maxBuyIn, balance)
  )
  local ok = nil
  local txId = nil
  local envelope = nil

  ok, txId = pokerBank.buyIn(activeSession.tableId, amount)
  if not ok then
    print("Rebuy transfer failed.")
    return
  end

  envelope = pokerProtocol.makeEnvelope(pokerProtocol.MESSAGE_TYPES.BUYIN_NOTICE, {
    seatId = activeSession.seatId,
    amount = amount,
    txId = txId,
  }, {
    tableId = activeSession.tableId,
  })

  seatState.pendingBuyInId = envelope.messageId
  seatState.pendingBuyInReply = nil
  pokerTransport.sendEnvelope(activeSession.dealerId, envelope)
  print("Rebuy sent. Waiting for dealer acknowledgement...")
end

local function startCashOut(activeSession)
  if seatState.pendingCashOutId or seatState.pendingCashOutReply or seatState.pendingCashOutAckId then
    print("A cash-out is already in progress.")
    return
  end

  local envelope = pokerProtocol.makeEnvelope(pokerProtocol.MESSAGE_TYPES.CASHOUT_REQUEST, {
    seatId = activeSession.seatId,
  }, {
    tableId = activeSession.tableId,
  })

  seatState.pendingCashOutId = envelope.messageId
  seatState.pendingCashOutReply = nil
  pokerTransport.sendEnvelope(activeSession.dealerId, envelope)
  print("Cash-out requested. Waiting for dealer authorization...")
end

local function networkLoop(activeSession)
  while running do
    local senderId, envelope = pokerTransport.receiveEnvelope(1)

    if envelope and senderId == activeSession.dealerId then
      if envelope.kind == pokerProtocol.MESSAGE_TYPES.TABLE_STATE then
        if envelope.payload and envelope.payload.summary then
          seatState.summary = envelope.payload.summary

          local index = 1
          while seatState.summary.seats and seatState.summary.seats[index] do
            local seat = seatState.summary.seats[index]
            if seat.seatId == activeSession.seatId then
              activeSession.stack = seat.stack or activeSession.stack
              pokerBank.updateSession({ stack = activeSession.stack })
              break
            end
            index = index + 1
          end
        end
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.BUYIN_ACK then
        if envelope.correlationId == seatState.pendingBuyInId then
          seatState.pendingBuyInReply = envelope.payload
          seatState.pendingBuyInId = nil
        end
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.CASHOUT_AUTHORIZED then
        if envelope.correlationId == seatState.pendingCashOutId then
          seatState.pendingCashOutReply = envelope.payload
          seatState.pendingCashOutId = nil
        end
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.CASHOUT_COMPLETE_ACK then
        if envelope.correlationId == seatState.pendingCashOutAckId then
          seatState.pendingCashOutAck = envelope.payload
          seatState.pendingCashOutAckId = nil
        end
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.TABLE_CLOSED then
        print("Dealer closed the table.")
        running = false
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.TABLE_EVENT then
        if envelope.payload and envelope.payload.text then
          logger.write("Dealer event: " .. tostring(envelope.payload.text))
        end
      end
    end

    if seatState.pendingBuyInReply and seatState.pendingBuyInReply.ok then
      local newStack = seatState.pendingBuyInReply.stack or activeSession.stack
      activeSession.stack = newStack
      pokerBank.updateSession({ stack = newStack })
      print("Buy-in accepted. New stack: " .. tostring(newStack) .. " tokens")
      seatState.pendingBuyInReply = nil
    end

    if seatState.pendingCashOutReply then
      local reply = seatState.pendingCashOutReply
      local settlementId = reply.settlementId
      local amount = math.floor(tonumber(reply.amount) or 0)
      local ok = nil
      local txId = nil
      local duplicate = nil
      local ackEnvelope = nil

      seatState.pendingCashOutReply = nil

      ok, txId, duplicate = pokerBank.cashOut(activeSession.tableId, settlementId, amount)
      if not ok then
        print("Cash-out failed locally. Session remains open.")
      else
        ackEnvelope = pokerProtocol.makeEnvelope(pokerProtocol.MESSAGE_TYPES.CASHOUT_COMPLETE, {
          seatId = activeSession.seatId,
          settlementId = settlementId,
          txId = txId,
          duplicate = duplicate,
        }, {
          tableId = activeSession.tableId,
        })

        seatState.pendingCashOutAckId = ackEnvelope.messageId
        seatState.pendingCashOutAck = nil
        pokerTransport.sendEnvelope(activeSession.dealerId, ackEnvelope)
        print("Cash-out paid: " .. tostring(amount) .. " tokens. Waiting for dealer acknowledgement...")
      end
    end

    if seatState.pendingCashOutAck and seatState.pendingCashOutAck.ok then
      pokerBank.clearSession()
      seatState.pendingCashOutAck = nil
      print("Cash-out complete. Session closed.")
      running = false
    end
  end
end

local function heartbeatLoop(activeSession)
  while running do
    sendHeartbeat(activeSession)
    os.sleep(cfg.HEARTBEAT_INTERVAL)
  end
end

local function commandLoop(activeSession)
  print("Seat commands: status, ready, unready, rebuy, cashout, help")

  while running do
    write("seat> ")
    local command = string.lower((read() or "") or "")

    if command == "status" then
      local latestSession = pokerBank.getActiveSession() or activeSession
      print("")
      print("Seat: " .. tostring(latestSession.seatId))
      print("Player: " .. tostring(latestSession.playerName))
      print("Stack: " .. tostring(latestSession.stack) .. " tokens")
      print("Host: " .. tostring(latestSession.hostName))
      if seatState.summary then
        printSummary(seatState.summary)
      else
        print("")
      end
    elseif command == "ready" then
      sendReadyUpdate(activeSession, true)
      print("Marked ready.")
    elseif command == "unready" then
      sendReadyUpdate(activeSession, false)
      print("Marked unready.")
    elseif command == "rebuy" then
      startRebuy(activeSession)
    elseif command == "cashout" or command == "quit" then
      startCashOut(activeSession)
    elseif command == "help" then
      print("status   - show seat and table state")
      print("ready    - mark seat ready")
      print("unready  - clear ready state")
      print("rebuy    - buy more chips with a new CCVault transfer")
      print("cashout  - request host -> player payout and leave the table")
      print("help     - show commands")
    elseif command ~= "" then
      print("Unknown command. Type 'help'.")
    end
  end
end

function M.run()
  local networkOk, networkInfo = pokerTransport.ensureOpen()
  if not networkOk then
    error(tostring(networkInfo))
  end

  local activeSession = pokerBank.getActiveSession()
  local summary = nil
  local reusedSession = nil
  local identity = nil
  local joinPayload = nil
  local joinErr = nil
  local buyInOk = nil
  local buyInErr = nil
  local stack = nil
  local runOk = nil
  local runErr = nil

  summary, reusedSession, joinErr = chooseTable(activeSession)
  if not summary then
    error(joinErr or "No table selected")
  end

  printSummary(summary)

  identity, joinPayload, joinErr = joinTable(summary, activeSession)
  if not identity then
    error(joinErr or "Join failed")
  end

  buyInOk, buyInErr, stack = performInitialBuyIn(summary, joinPayload)
  if not buyInOk then
    error(buyInErr or "Buy-in failed")
  end

  activeSession = {
    tableId = summary.tableId,
    dealerId = summary.dealerId,
    seatId = joinPayload.seatId,
    playerName = identity.playerName,
    hostName = identity.hostName,
    minBuyIn = summary.minBuyIn,
    maxBuyIn = summary.maxBuyIn,
    stack = stack or 0,
  }

  pokerBank.beginSession(activeSession)
  seatState.summary = summary
  running = true

  print("Joined seat " .. tostring(activeSession.seatId) .. " with stack " .. tostring(activeSession.stack) .. " tokens.")

  runOk, runErr = pcall(function()
    parallel.waitForAny(
      function() networkLoop(activeSession) end,
      function() heartbeatLoop(activeSession) end,
      function() commandLoop(activeSession) end
    )
  end)

  if not runOk then
    logger.write("Seat loop crashed: " .. tostring(runErr))
    error(runErr)
  end
end

return M