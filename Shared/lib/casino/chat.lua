-- chat.lua
-- Whispers through a chat box, if the computer has one. Every message goes to one named player: a table never talks to the
-- whole server, and nothing here may carry another player's cards. With no chat box, tell() does nothing and returns false.
-- A chat box call waits a server tick and throws away every event that arrives meanwhile, so tell() only queues. M.worker, in a
-- coroutine of its own, is the only thing that ever sends. The box has a cooldown, so messages go out one at a time, a refused
-- message is tried again a few times, and a queue left to grow gives up its oldest. A whisper that never lands costs nothing:
-- the wall and the owed book still say everything, so a lost one is logged and forgotten.

local journal = require("lib.casino.journal")

local M = {}

M.GAP_MS = 1100    -- the box's cooldown is 1 second, and a send landing just inside it would be refused
M.TRIES = 3        -- sends a message gets before it is dropped
M.LIMIT = 12       -- messages held: a full poker table's hands, twice over
M.LINE = 44        -- what fits one line of chat beside the prefix. Anything a player must read at a glance stays inside it

local PREFIX = "CASINO"
local WAKE = "casino_chat"

local box = nil    -- the chat box, or nil
local outbox = {}  -- { player, text, tries }, oldest first

--- Find the chat box. Safe to call again whenever the peripherals change. Finding one is not a call on it, so this can run
-- anywhere. Returns whether there is one.
function M.scan()
  box = peripheral.find("chatBox")
  if box and #outbox > 0 then os.queueEvent(WAKE) end
  return box ~= nil
end

function M.available()
  return box ~= nil
end

function M.pending()
  return #outbox
end

--- Whisper to one player. Queued, so this never waits. Returns whether it was queued.
function M.tell(player, text)
  if not box or type(player) ~= "string" or player == "" then return false end
  if #outbox >= M.LIMIT then table.remove(outbox, 1) end
  outbox[#outbox + 1] = { player = player, text = text, tries = 0 }
  os.queueEvent(WAKE)
  return true
end

--- The queue can move while a send waits for its tick, so the message is found again and not assumed to be first.
local function forget(item)
  for index, held in ipairs(outbox) do
    if held == item then
      table.remove(outbox, index)
      return
    end
  end
end

--- One send. Only call this from M.worker.
local function pump()
  local item = outbox[1]
  local ok, sent, why = pcall(box.sendMessageToPlayer, item.text, item.player, PREFIX)
  if ok and sent then
    forget(item)
    return
  end
  item.tries = item.tries + 1
  if item.tries >= M.TRIES then
    forget(item)
    journal.log("whisper to " .. item.player .. " dropped: " .. tostring(ok and why or sent))
  end
end

--- Sends what is queued, for as long as the table runs. It sleeps on an event, so a table with no chat box wakes for nothing.
function M.worker()
  while true do
    while box and #outbox > 0 do
      pump()
      sleep(M.GAP_MS / 1000)
    end
    os.pullEvent(WAKE)
  end
end

return M
