local M = {}

local nextMessageId = 0

M.VERSION = 1
M.APP_PROTOCOL = "roger.pokertable.app.v1"
M.DISCOVERY_PROTOCOL = "roger.pokertable.discovery.v1"

M.MESSAGE_TYPES = {
  TABLE_INFO_REQUEST = "table_info_request",
  TABLE_INFO_RESPONSE = "table_info_response",
  JOIN_REQUEST = "join_request",
  JOIN_RESPONSE = "join_response",
  READY_UPDATE = "ready_update",
  HEARTBEAT = "heartbeat",
  STACK_SET = "stack_set",
  STACK_ACK = "stack_ack",
  LEAVE_REQUEST = "leave_request",
  LEAVE_ACK = "leave_ack",
  HAND_SETTLEMENT = "hand_settlement",
  HAND_SETTLEMENT_ACK = "hand_settlement_ack",
  TABLE_STATE = "table_state",
  TABLE_EVENT = "table_event",
  TABLE_CLOSED = "table_closed",
}

function M.generateId(prefix)
  nextMessageId = nextMessageId + 1
  return table.concat({
    tostring(prefix or "msg"),
    tostring(os.getComputerID()),
    tostring(os.epoch("local")),
    tostring(nextMessageId),
  }, "-")
end

function M.makeEnvelope(kind, payload, opts)
  assert(type(kind) == "string", "kind must be a string")

  local options = opts or {}

  return {
    app = "PokerTable",
    version = M.VERSION,
    kind = kind,
    messageId = options.messageId or M.generateId(kind),
    correlationId = options.correlationId,
    tableId = options.tableId,
    senderId = os.getComputerID(),
    timestamp = os.epoch("local"),
    payload = payload or {},
  }
end

function M.validateEnvelope(envelope)
  if type(envelope) ~= "table" then
    return false, "envelope must be a table"
  end

  if envelope.app ~= "PokerTable" then
    return false, "unexpected app"
  end

  if envelope.version ~= M.VERSION then
    return false, "unsupported version"
  end

  if type(envelope.kind) ~= "string" or envelope.kind == "" then
    return false, "missing kind"
  end

  if type(envelope.messageId) ~= "string" or envelope.messageId == "" then
    return false, "missing message id"
  end

  if envelope.payload ~= nil and type(envelope.payload) ~= "table" then
    return false, "payload must be a table"
  end

  return true
end

return M