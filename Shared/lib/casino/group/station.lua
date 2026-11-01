-- station.lua
-- One interface over a seat, wherever it is. The dealer does not know which kind it has:
--   show(screen)              put a screen up
--   toast(text)               a word on it
--   ask(who)                  have this player approve this computer in chat
--   order(tag, name, amount)  move tokens. A remote seat answers later through the link. A wall on this computer moves them here
--                             and returns what moved, because its book is the dealer's own
--   heard(time), quiet(time)  whether it has been heard from lately
-- A remote seat also has trace(tag, name, amount, at), for an order another computer was sent and can no longer answer.
-- Input comes back to the dealer as (seat, who, buttonId, value), from the link or from a touch on this computer's own wall.

local books = require("lib.casino.books")
local journal = require("lib.casino.journal")
local link = require("lib.casino.group.link")

local M = {}

local function now()
  return os.epoch("utc")
end

-- ------------------------------------------------------------------ a seat computer, through the link

local Remote = {}
Remote.__index = Remote

function M.remote(wire, id, number)
  return setmetatable({ wire = wire, id = id, number = number, heardAt = now(), remote = true }, Remote)
end

function Remote:show(screen)
  self.wire:send(self.id, "view", { screen = screen })
end

function Remote:toast(text)
  self.wire:send(self.id, "toast", { text = text })
end

function Remote:ask(who)
  self.wire:send(self.id, "ask", { who = who })
end

function Remote:order(tag, name, amount)
  self.wire:send(self.id, "order", { tag = tag, name = name, amount = amount })
  return nil
end

--- Ask this computer what the ledger says of an order that went to another one. Nothing moves.
function Remote:trace(tag, name, amount, at)
  self.wire:send(self.id, "trace", { tag = tag, name = name, amount = amount, at = at })
end

function Remote:heard(time)
  self.heardAt = time or now()
end

function Remote:quiet(time)
  return (time or now()) - self.heardAt > link.QUIET_MS
end

-- ------------------------------------------------------------------ a wall on the dealer's own computer

local Wall = {}
Wall.__index = Wall

function M.wall(front, number)
  return setmetatable({ front = front, number = number, heardAt = now() }, Wall)
end

function Wall:show(screen)
  self.front:show(screen)
end

function Wall:toast(text)
  self.front:toast(text)
end

function Wall:ask(who)
  self.front:ask(who)
end

--- The book here is the dealer's own, so what a Poker Table does is right: books.move takes what moved off it.
function Wall:order(tag, name, amount)
  local moved, _, err = books.move(name, amount, tag)
  if moved ~= amount then journal.log("move " .. tag .. " " .. name .. " wanted " .. amount .. " moved " .. moved .. ": " .. tostring(err)) end
  return moved
end

function Wall:heard(time)
  self.heardAt = time or now()
end

function Wall:quiet()
  return false
end

return M
