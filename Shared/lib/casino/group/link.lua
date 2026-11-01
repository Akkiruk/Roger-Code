-- link.lua
-- How a dealer and its seats talk: plain rednet on one protocol, addressed to one computer, and broadcast only while a seat is
-- looking for its dealer. Nothing is signed or sealed. The owner chose easy over secure, so anyone who goes looking can overhear
-- a private view, and a message is only checked for being the right shape and a believable size, as net.lua does.
--
--   seat to anyone   hello    { host }                        who is out there?
--   dealer to seat   here     { host, title, game, seated, free }  the answer, whatever the host. The seat decides
--   seat to dealer   join     { host }                        give me a number. The same seat again gets the same number
--   dealer to seat   welcome  { number }, full {}             the answer
--   dealer to seat   view     { screen }                      what to draw. Sent again every beat, so it is the heartbeat too
--   seat to dealer   beat     {}                              still here
--   seat to dealer   input    { who, id, value, approved, shown }  a touch, with or without a button under it
--   dealer to seat   order    { tag, name, amount }           move these tokens (see seat.lua)
--   seat to dealer   answer   { tag, moved }                  what moved. A repeated tag gets the same answer
--   dealer to seat   trace    { tag, name, amount, at }       what does the ledger say of an order sent to a computer that has gone?
--   dealer to seat   ask      { who }                         the book holds something for them: have them approve this computer
--   dealer to seat   toast    { text }                        a word on the screen
--
-- here and join also carry the cabinet's key, so a seat only ever joins a dealer of its own cabinet.
--
-- Every message carries a seq from os.epoch("utc"), always rising from one sender, and a receiver drops anything not newer than
-- the last it heard from that sender. The same message heard twice does nothing, and a reboot loses nothing because a resend
-- gets a new seq. What stops tokens moving twice is the tag, not the seq: see seat.lua and dealer.lua.
--
-- The inbox is filled by whichever coroutine owns the events, and read by the main loop, so a wallet call that swallows events
-- never loses a message. It has a limit: a flood costs the oldest lines, and resends cover those.

local net = require("lib.casino.net")

local M = {}

M.PROTOCOL = "casino.group.v1"
M.BEAT_MS = 3000       -- how often a seat and a dealer say they are here
M.QUIET_MS = 9000      -- nothing heard for this long: the other end is gone for now
M.RESEND_MS = 2000     -- how often an unanswered order goes again
M.LOST_MS = 30000      -- a seat's dealer silent for this long: it offers any other it can hear, and stays until it is tapped
M.TOUCH_MS = 30000     -- ccvault's window: a transfer needs a touch this recent on that computer

local INBOX_LIMIT = 256
local MAX_NAME = 36    -- a name, or a host's UUID while they are offline
local MAX_ID = 40
local MAX_TAG = 58     -- what books.lua keeps of a reason
local MAX_TEXT = 200

local function now()
  return os.epoch("utc")
end

local function isFinite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isText(value, limit)
  return type(value) == "string" and value ~= "" and #value <= limit
end

--- A player's name. "@" marks the house's side of the book, so no name may have one.
local function isName(value)
  return isText(value, MAX_NAME) and not value:find("@", 1, true)
end
M.isName = isName

--- A whole count of tokens, either way, that could be real.
local function isTokens(value)
  return isFinite(value) and value == math.floor(value) and math.abs(value) <= net.MAX_TOKENS
end
M.isTokens = isTokens

local function isValue(value)
  return value == nil or type(value) == "boolean" or isFinite(value) or isText(value, MAX_ID)
end

local function isCabinet(value)
  return value == nil or isText(value, MAX_ID)
end

local CHECKS = {
  hello = function(m) return isText(m.host, MAX_NAME) end,
  join = function(m) return isText(m.host, MAX_NAME) and isCabinet(m.cabinet) end,
  beat = function() return true end,
  here = function(m)
    return isText(m.host, MAX_NAME) and isCabinet(m.cabinet) and (m.title == nil or isText(m.title, MAX_TEXT))
      and (m.game == nil or isText(m.game, MAX_TEXT)) and (m.seated == nil or isFinite(m.seated)) and (m.free == nil or isFinite(m.free))
  end,
  welcome = function(m) return isFinite(m.number) and m.number >= 1 and m.number <= 64 and m.number == math.floor(m.number) end,
  full = function() return true end,
  view = function(m)
    local screen = m.screen
    return type(screen) == "table" and isFinite(screen.n) and isText(screen.kind, MAX_ID) and type(screen.buttons) == "table"
  end,
  toast = function(m) return isText(m.text, MAX_TEXT) end,
  input = function(m)
    return isName(m.who) and (m.id == nil or isText(m.id, MAX_ID)) and isValue(m.value) and (m.shown == nil or isFinite(m.shown))
  end,
  order = function(m) return isText(m.tag, MAX_TAG) and isName(m.name) and isTokens(m.amount) and m.amount ~= 0 end,
  answer = function(m) return isText(m.tag, MAX_TAG) and isTokens(m.moved) end,
  trace = function(m) return isText(m.tag, MAX_TAG) and isName(m.name) and isTokens(m.amount) and m.amount ~= 0 and isFinite(m.at) end,
  ask = function(m) return isName(m.who) end,
}

--- Whether a message is one this link can read. Anything else is dropped where it lands.
function M.valid(message)
  if type(message) ~= "table" or not isFinite(message.seq) then return false end
  local check = CHECKS[message.kind]
  if not check then return false end
  local ok, good = pcall(check, message)
  return ok and good == true
end

local Link = {}
Link.__index = Link

--- A link for this computer.
function M.new()
  return setmetatable({ seq = 0, heard = {}, inbox = {} }, Link)
end

--- Open every modem. Safe to call again whenever the peripherals change. Returns whether there is one.
function M.open()
  return net.open()
end

function Link:stamp(kind, payload)
  local message = payload or {}
  self.seq = math.max(now(), self.seq + 1)
  message.kind, message.seq = kind, self.seq
  return message
end

function Link:send(to, kind, payload)
  return (pcall(rednet.send, to, self:stamp(kind, payload), M.PROTOCOL))
end

function Link:broadcast(kind, payload)
  return (pcall(rednet.broadcast, self:stamp(kind, payload), M.PROTOCOL))
end

--- Take a rednet message off the event queue. A stale, repeated or unreadable one goes no further.
function Link:hear(sender, message, protocol)
  if protocol ~= M.PROTOCOL or not isFinite(sender) or not M.valid(message) then return false end
  if message.seq <= (self.heard[sender] or 0) then return false end
  self.heard[sender] = message.seq
  message.from = sender
  local inbox = self.inbox
  inbox[#inbox + 1] = message
  while #inbox > INBOX_LIMIT do table.remove(inbox, 1) end
  return true
end

--- Everything heard since the last call, oldest first.
function Link:drain()
  local list = self.inbox
  self.inbox = {}
  return list
end

return M
