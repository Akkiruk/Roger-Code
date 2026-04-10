local pokerLog = require("lib.poker_log")
local protocol = require("lib.poker_protocol")

local M = {}

local logger = pokerLog.new("pokertable_network.log", false)

local function isModem(name)
  if type(name) ~= "string" or name == "" then
    return false
  end

  if type(peripheral.hasType) == "function" then
    return peripheral.hasType(name, "modem") == true
  end

  return peripheral.getType(name) == "modem"
end

function M.ensureOpen()
  if rednet.isOpen() then
    return true, 0
  end

  local opened = 0
  local names = peripheral.getNames()

  for _, name in ipairs(names) do
    if isModem(name) then
      local ok, err = pcall(function()
        rednet.open(name)
      end)

      if ok then
        opened = opened + 1
      else
        logger.write("Failed to open modem " .. tostring(name) .. ": " .. tostring(err))
      end
    end
  end

  if rednet.isOpen() then
    return true, opened
  end

  return false, "No modem available for rednet"
end

function M.hostTable(tableId)
  assert(type(tableId) == "string", "tableId must be a string")

  local ok, err = pcall(function()
    rednet.host(protocol.DISCOVERY_PROTOCOL, tableId)
  end)

  if not ok then
    return false, tostring(err)
  end

  return true
end

function M.unhostTable()
  pcall(function()
    rednet.unhost(protocol.DISCOVERY_PROTOCOL)
  end)
end

function M.lookupTables(hostname)
  if hostname and hostname ~= "" then
    local exact = rednet.lookup(protocol.DISCOVERY_PROTOCOL, hostname)
    if exact then
      return { exact }
    end
    return {}
  end

  return { rednet.lookup(protocol.DISCOVERY_PROTOCOL) }
end

function M.sendEnvelope(recipient, envelope)
  assert(type(recipient) == "number", "recipient must be a number")

  local ok, err = protocol.validateEnvelope(envelope)
  if not ok then
    return false, err
  end

  local sent = rednet.send(recipient, envelope, protocol.APP_PROTOCOL)
  if not sent then
    logger.write("Failed to send envelope " .. tostring(envelope.kind) .. " to " .. tostring(recipient))
    return false, "send_failed"
  end

  return true
end

function M.receiveEnvelope(timeout)
  local senderId, message = rednet.receive(protocol.APP_PROTOCOL, timeout)
  if not senderId then
    return nil
  end

  local ok, err = protocol.validateEnvelope(message)
  if not ok then
    logger.write("Dropped invalid envelope from " .. tostring(senderId) .. ": " .. tostring(err))
    return nil, nil, err
  end

  return senderId, message
end

function M.request(recipient, envelope, expectedKind, timeoutSeconds, filterFn)
  local sent, sendErr = M.sendEnvelope(recipient, envelope)
  if not sent then
    return nil, sendErr
  end

  local timeoutMs = math.floor((timeoutSeconds or 3) * 1000)
  local deadline = os.epoch("local") + timeoutMs

  while true do
    local remainingMs = deadline - os.epoch("local")
    if remainingMs <= 0 then
      return nil, "timeout"
    end

    local senderId, reply = M.receiveEnvelope(remainingMs / 1000)
    if senderId == recipient and reply and reply.correlationId == envelope.messageId then
      if expectedKind and reply.kind ~= expectedKind then
        logger.write("Ignored mismatched reply kind: " .. tostring(reply.kind))
      elseif type(filterFn) == "function" and not filterFn(reply) then
        logger.write("Ignored filtered reply for envelope " .. tostring(envelope.messageId))
      else
        return reply
      end
    end
  end
end

return M