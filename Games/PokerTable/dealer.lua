local cfg = require("pokertable_config")
local currency = require("lib.currency")
local pokerLog = require("lib.poker_log")
local pokerProtocol = require("lib.poker_protocol")
local pokerStore = require("lib.poker_store")
local pokerTransport = require("lib.poker_transport")

local M = {}

local logger = pokerLog.new(cfg.DEALER_LOG_FILE, false)

local state = nil
local running = false

local function saveState()
  local ok, err = pokerStore.save(cfg.DEALER_STATE_FILE, state)
  if not ok then
    logger.write("Failed to save dealer state: " .. tostring(err))
  end
  return ok, err
end

local function pushEvent(text)
  local entry = {
    timestamp = os.epoch("local"),
    text = tostring(text),
  }

  state.events[#state.events + 1] = entry
  while #state.events > 25 do
    table.remove(state.events, 1)
  end

  logger.write(entry.text)
  saveState()
end

local function countSeats()
  local count = 0
  local seatId = 1

  while seatId <= state.maxSeats do
    if state.seats[seatId] then
      count = count + 1
    end
    seatId = seatId + 1
  end

  return count
end

local function totalLiability()
  local total = 0
  local seatId = 1

  while seatId <= state.maxSeats do
    local seat = state.seats[seatId]
    if seat then
      total = total + (seat.stack or 0)
    end
    seatId = seatId + 1
  end

  return total
end

local function buildSeatsSnapshot()
  local snapshot = {}
  local seatId = 1

  while seatId <= state.maxSeats do
    local seat = state.seats[seatId]
    snapshot[#snapshot + 1] = {
      seatId = seatId,
      playerName = seat and seat.playerName or nil,
      stack = seat and seat.stack or 0,
      ready = seat and seat.ready or false,
      status = seat and seat.status or "open",
    }
    seatId = seatId + 1
  end

  return snapshot
end

local function buildSummary()
  return {
    tableId = state.tableId,
    dealerId = state.dealerId,
    hostName = state.hostName,
    status = state.status,
    maxSeats = state.maxSeats,
    minBuyIn = state.minBuyIn,
    maxBuyIn = state.maxBuyIn,
    occupiedSeats = countSeats(),
    openSeats = state.maxSeats - countSeats(),
    seats = buildSeatsSnapshot(),
  }
end

local function findSeatBySender(senderId)
  local seatId = 1

  while seatId <= state.maxSeats do
    local seat = state.seats[seatId]
    if seat and seat.senderId == senderId then
      return seat, seatId
    end
    seatId = seatId + 1
  end

  return nil, nil
end

local function findSeatByPlayer(playerName)
  local seatId = 1

  while seatId <= state.maxSeats do
    local seat = state.seats[seatId]
    if seat and seat.playerName == playerName then
      return seat, seatId
    end
    seatId = seatId + 1
  end

  return nil, nil
end

local function findOpenSeat()
  local seatId = 1

  while seatId <= state.maxSeats do
    if not state.seats[seatId] then
      return seatId
    end
    seatId = seatId + 1
  end

  return nil
end

local function sendEnvelope(recipient, kind, payload, correlationId)
  local envelope = pokerProtocol.makeEnvelope(kind, payload, {
    tableId = state.tableId,
    correlationId = correlationId,
  })

  return pokerTransport.sendEnvelope(recipient, envelope)
end

local function broadcastState(reason)
  local summary = buildSummary()
  local seatId = 1

  while seatId <= state.maxSeats do
    local seat = state.seats[seatId]
    if seat and seat.status ~= "removed" then
      sendEnvelope(seat.senderId, pokerProtocol.MESSAGE_TYPES.TABLE_STATE, {
        summary = summary,
        reason = reason,
      })
    end
    seatId = seatId + 1
  end
end

local function removeSeat(seatId)
  local seat = state.seats[seatId]
  if seat then
    pushEvent("Seat " .. tostring(seatId) .. " closed for " .. tostring(seat.playerName))
    state.seats[seatId] = nil
    saveState()
    broadcastState("seat_removed")
  end
end

local function rejectJoin(senderId, messageId, reason)
  sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.JOIN_RESPONSE, {
    ok = false,
    reason = reason,
    summary = buildSummary(),
  }, messageId)
end

local function handleTableInfoRequest(senderId, envelope)
  sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.TABLE_INFO_RESPONSE, {
    ok = true,
    summary = buildSummary(),
  }, envelope.messageId)
end

local function handleJoinRequest(senderId, envelope)
  local payload = envelope.payload or {}
  local playerName = payload.playerName
  local seatHostName = payload.hostName
  local requestedSeatId = tonumber(payload.requestedSeatId)

  if type(playerName) ~= "string" or playerName == "" then
    rejectJoin(senderId, envelope.messageId, "Missing player name")
    return
  end

  if seatHostName ~= state.hostName then
    rejectJoin(senderId, envelope.messageId, "Seat host must match dealer host")
    return
  end

  local existingSeat, existingSeatId = findSeatByPlayer(playerName)
  if existingSeat and existingSeat.status ~= "disconnected" and existingSeat.senderId ~= senderId then
    rejectJoin(senderId, envelope.messageId, "Player already has an active seat")
    return
  end

  if existingSeat and (existingSeat.status == "disconnected" or (requestedSeatId and existingSeatId == requestedSeatId)) then
    existingSeat.senderId = senderId
    existingSeat.status = "connected"
    existingSeat.lastSeen = os.epoch("local")
    existingSeat.ready = false
    saveState()
    pushEvent("Seat " .. tostring(existingSeatId) .. " reconnected for " .. playerName)
    sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.JOIN_RESPONSE, {
      ok = true,
      seatId = existingSeatId,
      summary = buildSummary(),
      stack = existingSeat.stack,
      reconnected = true,
    }, envelope.messageId)
    broadcastState("seat_reconnected")
    return
  end

  local seatId = findOpenSeat()
  if not seatId then
    rejectJoin(senderId, envelope.messageId, "Table is full")
    return
  end

  state.seats[seatId] = {
    seatId = seatId,
    playerName = playerName,
    senderId = senderId,
    stack = 0,
    totalBuyIn = 0,
    ready = false,
    status = "connected",
    lastSeen = os.epoch("local"),
    joinedAt = os.epoch("local"),
  }

  saveState()
  pushEvent("Seat " .. tostring(seatId) .. " joined for " .. playerName)

  sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.JOIN_RESPONSE, {
    ok = true,
    seatId = seatId,
    summary = buildSummary(),
    stack = 0,
    reconnected = false,
  }, envelope.messageId)

  broadcastState("seat_joined")
end

local function handleReadyUpdate(senderId, envelope)
  local payload = envelope.payload or {}
  local seat, seatId = findSeatBySender(senderId)

  if not seat then
    return
  end

  seat.ready = payload.ready == true
  seat.lastSeen = os.epoch("local")
  saveState()

  pushEvent("Seat " .. tostring(seatId) .. " ready=" .. tostring(seat.ready))
  broadcastState("ready_update")
end

local function handleHeartbeat(senderId)
  local seat = nil
  local seatId = nil

  seat, seatId = findSeatBySender(senderId)
  if seat then
    seat.lastSeen = os.epoch("local")
    if seat.status == "disconnected" then
      seat.status = "connected"
      pushEvent("Seat " .. tostring(seatId) .. " heartbeat restored connection")
      broadcastState("seat_heartbeat_reconnect")
    end
    saveState()
  end
end

local function handleBuyInNotice(senderId, envelope)
  local payload = envelope.payload or {}
  local seat, seatId = findSeatBySender(senderId)
  local txId = payload.txId
  local amount = math.floor(tonumber(payload.amount) or 0)

  if not seat then
    return
  end

  if type(txId) ~= "string" or txId == "" then
    sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.BUYIN_ACK, {
      ok = false,
      reason = "Missing buy-in transaction ID",
    }, envelope.messageId)
    return
  end

  if amount < state.minBuyIn or amount > state.maxBuyIn then
    sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.BUYIN_ACK, {
      ok = false,
      reason = "Buy-in is outside table limits",
    }, envelope.messageId)
    return
  end

  if state.processedBuyIns[txId] then
    sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.BUYIN_ACK, {
      ok = true,
      stack = seat.stack,
      duplicate = true,
    }, envelope.messageId)
    return
  end

  seat.stack = seat.stack + amount
  seat.totalBuyIn = seat.totalBuyIn + amount
  seat.lastSeen = os.epoch("local")
  state.processedBuyIns[txId] = {
    seatId = seatId,
    amount = amount,
    processedAt = os.epoch("local"),
  }

  saveState()
  pushEvent("Seat " .. tostring(seatId) .. " bought in for " .. tostring(amount) .. " tokens")

  sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.BUYIN_ACK, {
    ok = true,
    stack = seat.stack,
    duplicate = false,
  }, envelope.messageId)

  broadcastState("buyin")
end

local function handleCashOutRequest(senderId, envelope)
  local seat, seatId = findSeatBySender(senderId)
  local settlementId = nil
  local amount = 0
  local pending = nil
  local pendingId = nil

  if not seat then
    return
  end

  for pendingId, pending in pairs(state.pendingSettlements) do
    if pending.seatId == seatId then
      sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.CASHOUT_AUTHORIZED, {
        seatId = seatId,
        settlementId = pendingId,
        amount = pending.amount,
      }, envelope.messageId)
      return
    end
  end

  amount = seat.stack
  settlementId = pokerProtocol.generateId("cashout")

  state.pendingSettlements[settlementId] = {
    seatId = seatId,
    amount = amount,
    playerName = seat.playerName,
    createdAt = os.epoch("local"),
  }

  seat.status = "cashing_out"
  seat.ready = false
  saveState()

  pushEvent("Seat " .. tostring(seatId) .. " requested cash-out for " .. tostring(amount) .. " tokens")

  sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.CASHOUT_AUTHORIZED, {
    seatId = seatId,
    settlementId = settlementId,
    amount = amount,
  }, envelope.messageId)
end

local function handleCashOutComplete(senderId, envelope)
  local payload = envelope.payload or {}
  local settlementId = payload.settlementId
  local txId = payload.txId
  local pending = nil
  local seat = nil

  if type(settlementId) ~= "string" or settlementId == "" then
    return
  end

  if state.processedSettlements[settlementId] then
    sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.CASHOUT_COMPLETE_ACK, {
      ok = true,
      duplicate = true,
      settlementId = settlementId,
    }, envelope.messageId)
    return
  end

  pending = state.pendingSettlements[settlementId]
  if not pending then
    sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.CASHOUT_COMPLETE_ACK, {
      ok = false,
      reason = "Unknown settlement",
      settlementId = settlementId,
    }, envelope.messageId)
    return
  end

  seat = state.seats[pending.seatId]
  if not seat or seat.senderId ~= senderId then
    sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.CASHOUT_COMPLETE_ACK, {
      ok = false,
      reason = "Seat does not match settlement",
      settlementId = settlementId,
    }, envelope.messageId)
    return
  end

  state.processedSettlements[settlementId] = {
    seatId = pending.seatId,
    amount = pending.amount,
    txId = txId,
    processedAt = os.epoch("local"),
  }
  state.pendingSettlements[settlementId] = nil
  saveState()

  sendEnvelope(senderId, pokerProtocol.MESSAGE_TYPES.CASHOUT_COMPLETE_ACK, {
    ok = true,
    duplicate = false,
    settlementId = settlementId,
  }, envelope.messageId)

  removeSeat(pending.seatId)
end

local function checkSeatTimeouts()
  local now = os.epoch("local")
  local changed = false
  local seatId = 1

  while seatId <= state.maxSeats do
    local seat = state.seats[seatId]
    if seat and seat.status == "connected" and (now - (seat.lastSeen or now)) > (cfg.HEARTBEAT_TIMEOUT * 1000) then
      seat.status = "disconnected"
      seat.ready = false
      changed = true
      pushEvent("Seat " .. tostring(seatId) .. " marked disconnected")
    end
    seatId = seatId + 1
  end

  if changed then
    saveState()
    broadcastState("seat_timeout")
  end
end

local function printStatus()
  print("")
  print("Table: " .. state.tableId)
  print("Host: " .. tostring(state.hostName))
  print("Seats: " .. tostring(countSeats()) .. "/" .. tostring(state.maxSeats))
  print("Buy-in: " .. tostring(state.minBuyIn) .. " - " .. tostring(state.maxBuyIn) .. " tokens")
  print("Table liability: " .. tostring(totalLiability()) .. " tokens")
  print("Pending settlements: " .. tostring(next(state.pendingSettlements) ~= nil))
  print("")

  local seatId = 1
  while seatId <= state.maxSeats do
    local seat = state.seats[seatId]
    if seat then
      print(
        string.format(
          "Seat %d | %-12s | stack=%d | ready=%s | %s",
          seatId,
          tostring(seat.playerName),
          seat.stack,
          tostring(seat.ready),
          tostring(seat.status)
        )
      )
    else
      print("Seat " .. tostring(seatId) .. " | <open>")
    end
    seatId = seatId + 1
  end

  print("")
end

local function networkLoop()
  while running do
    local senderId, envelope = pokerTransport.receiveEnvelope(1)
    if envelope then
      if envelope.kind == pokerProtocol.MESSAGE_TYPES.TABLE_INFO_REQUEST then
        handleTableInfoRequest(senderId, envelope)
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.JOIN_REQUEST then
        handleJoinRequest(senderId, envelope)
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.READY_UPDATE then
        handleReadyUpdate(senderId, envelope)
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.HEARTBEAT then
        handleHeartbeat(senderId)
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.BUYIN_NOTICE then
        handleBuyInNotice(senderId, envelope)
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.CASHOUT_REQUEST then
        handleCashOutRequest(senderId, envelope)
      elseif envelope.kind == pokerProtocol.MESSAGE_TYPES.CASHOUT_COMPLETE then
        handleCashOutComplete(senderId, envelope)
      end
    end

    checkSeatTimeouts()
  end
end

local function commandLoop()
  print("Dealer commands: status, close, help")

  while running do
    write("dealer> ")
    local command = string.lower((read() or "") or "")

    if command == "status" then
      printStatus()
    elseif command == "help" then
      print("status  - show current table state")
      print("close   - close the table and notify seats")
      print("help    - show commands")
    elseif command == "close" then
      if countSeats() > 0 or next(state.pendingSettlements) then
        print("Refusing to close while seats or pending settlements still exist.")
        print("Cash out all seats first so host liability returns to zero.")
      else
        state.status = "closed"
        saveState()
        broadcastState("table_closed")

        local seatId = 1
        while seatId <= state.maxSeats do
          local seat = state.seats[seatId]
          if seat then
            sendEnvelope(seat.senderId, pokerProtocol.MESSAGE_TYPES.TABLE_CLOSED, {
              reason = "dealer_closed",
              summary = buildSummary(),
            })
          end
          seatId = seatId + 1
        end

        running = false
      end
    elseif command ~= "" then
      print("Unknown command. Type 'help'.")
    end
  end
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

local function buildDefaultTableId(hostName)
  local compactHost = string.lower(tostring(hostName or "host")):gsub("[^%w]", "")
  if compactHost == "" then
    compactHost = "host"
  end
  return compactHost .. "-" .. tostring(os.getComputerID())
end

local function newState()
  local hostName = currency.getHostName()
  if not hostName or hostName == "" then
    error("Dealer computer is missing a CCVault host owner")
  end

  local tableIdDefault = buildDefaultTableId(hostName)
  write("Table ID [" .. tableIdDefault .. "]: ")
  local tableId = read()
  if not tableId or tableId == "" then
    tableId = tableIdDefault
  end

  local maxSeats = promptInteger("Max seats", cfg.DEFAULT_MAX_SEATS, 2, 8)
  local minBuyIn = promptInteger("Minimum buy-in", cfg.DEFAULT_MIN_BUY_IN, 1, 1000000)
  local maxBuyIn = promptInteger("Maximum buy-in", cfg.DEFAULT_MAX_BUY_IN, minBuyIn, 1000000)

  return {
    tableId = tableId,
    dealerId = os.getComputerID(),
    hostName = hostName,
    status = "lobby",
    maxSeats = maxSeats,
    minBuyIn = minBuyIn,
    maxBuyIn = maxBuyIn,
    seats = {},
    events = {},
    pendingSettlements = {},
    processedBuyIns = {},
    processedSettlements = {},
    createdAt = os.epoch("local"),
  }
end

local function loadOrCreateState()
  local savedState = pokerStore.load(cfg.DEALER_STATE_FILE, nil)

  if type(savedState) == "table" and savedState.status ~= "closed" then
    print("Saved table state found for " .. tostring(savedState.tableId) .. ".")
    write("Resume saved table? [Y/n]: ")
    local answer = string.lower((read() or "") or "")
    if answer == "" or answer == "y" or answer == "yes" then
      savedState.events = savedState.events or {}
      savedState.pendingSettlements = savedState.pendingSettlements or {}
      savedState.processedBuyIns = savedState.processedBuyIns or {}
      savedState.processedSettlements = savedState.processedSettlements or {}
      savedState.seats = savedState.seats or {}
      return savedState
    end
  end

  return newState()
end

function M.run()
  local networkOk, networkInfo = pokerTransport.ensureOpen()
  if not networkOk then
    error(tostring(networkInfo))
  end

  state = loadOrCreateState()
  saveState()

  local hostOk, hostErr = pokerTransport.hostTable(state.tableId)
  if not hostOk then
    error("Could not host table discovery: " .. tostring(hostErr))
  end

  running = true

  print("")
  print("Poker table dealer online.")
  print("Table ID: " .. state.tableId)
  print("Host: " .. tostring(state.hostName))
  print("")
  printStatus()

  local ok, err = pcall(function()
    parallel.waitForAny(networkLoop, commandLoop)
  end)

  pokerTransport.unhostTable()

  if not ok then
    logger.write("Dealer loop crashed: " .. tostring(err))
    error(err)
  end

  print("Dealer closed.")
end

return M