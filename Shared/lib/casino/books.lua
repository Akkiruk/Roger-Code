-- books.lua
-- How tokens move. The owed book is the truth about who is owed what, and a transfer is one step against it:
--   book     the result goes in the owed book under a tag, once (journal.book)
--   begin    the transfer is written down in that same file before it happens
--   transfer the tokens move, and wallet's audit log says so
--   end      the amount comes off the book and the transfer is crossed off, in one write
-- A reboot or a crash can land between any two of these, and each one left behind can be answered:
--   the audit log has it   it moved, or it was refused
--   no audit line          the crash landed around the transfer itself, so ask the server's ledger. That needs the player
--                          to have touched the table, so the question waits for them and nothing else moves for them until then
-- If the ledger can never say, because a server has no history call or the transfer has slid out of the last 50 entries,
-- the player gets the benefit of the doubt: a payment counts as not made and a charge counts as taken. The host can lose
-- a little that way; a player cannot.

local journal = require("lib.casino.journal")
local wallet = require("lib.casino.wallet")

local M = {}

local MAX_TAG = 58     -- leaves room for a part number within ccvault's 64 characters

--- What became of a transfer left in doubt: true it moved, false it did not, nil if that cannot be told yet.
local function answer(tag, move)
  local logged = wallet.wasSettled(tag)
  if logged ~= nil then return logged end
  local shown, never = wallet.ledgerShows(move.name, tag, move.at)
  if shown ~= nil then return shown end
  if never then return move.amount < 0 end
  return nil
end

--- Answer what a reboot left in doubt, for one player or everyone. Returns true when nothing is left in doubt for them.
function M.resolve(name)
  local clear = true
  for tag, move in pairs(journal.moves()) do
    if not name or move.name == name then
      local moved = answer(tag, move)
      if moved == nil then
        clear = false
      else
        journal.endMove(tag, moved and move.amount or 0)
        journal.log("resolved transfer " .. tag .. " " .. move.name .. " " .. move.amount .. " moved=" .. tostring(moved))
      end
    end
  end
  return clear
end

--- Move what is already in the book: net tokens to the player when positive, from them when negative.
-- A net too big for one transfer goes in several, and a player who owes more than they hold pays what they have.
-- Whatever does not move stays in the book.
-- @param name string     the player
-- @param net number      the amount, whole tokens
-- @param reason string   this must never have been used before: the ledger finds a transfer by it
-- @return moved number, left number, err string|nil
function M.move(name, net, reason)
  net = math.floor(net + 0.5)
  if net == 0 then return 0, 0, nil end
  if not M.resolve(name) then return 0, net, "an earlier transfer is in doubt" end
  reason = tostring(reason):sub(1, MAX_TAG)

  local want = net
  if net < 0 then
    want = -math.min(-net, wallet.balance(name) or -net)
    if want >= 0 then return 0, net, "insufficient balance" end
  end

  local sign = want > 0 and 1 or -1
  local moved, part, err = 0, 0, nil
  while moved ~= want and not err do
    local step = sign * math.min(math.abs(want - moved), wallet.maxTransfer())
    part = part + 1
    local tag = part == 1 and reason or (reason .. "/" .. part)
    if not journal.beginMove(name, step, tag) then
      err = "the book could not be written"
    else
      local ok, why = wallet.send(name, step, tag)
      journal.endMove(tag, ok and step or 0)
      if ok then
        moved = moved + step
      elseif not wallet.lowerCap(why) then
        err = why
      end
    end
  end
  local left = net - moved
  return moved, left, err or (left ~= 0 and "insufficient balance" or nil)
end

return M
