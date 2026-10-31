-- door.lua
-- The one seam between a table and money. table.lua reaches the wallet, the books, the journal, the stats, the session notes,
-- the network and the lamps only through a door, and this is the only file that opens the real ones for it.
-- With a live seat a door is the module itself. With a pretend seat (pretend.lua: practice, and tournaments) every call lands
-- on that seat's stand-in instead, so the engine's own code runs unchanged and a round "settles" as it always does, with chips.
-- Doors fail closed: a function with no stand-in raises an error while a pretend seat sits, so a call added to table.lua and
-- forgotten here stops a pretend seat instead of reaching tokens. The keep is the other half: Table:pretendSeat swaps
-- self.keep for the seat's own, so a game's rules can only ever see a keep and a shoe made for that seat.
-- Tests/practice_test.lua fails if table.lua requires one of these modules itself or calls something with no stand-in.

local badges = require("lib.casino.badges")
local books = require("lib.casino.books")
local journal = require("lib.casino.journal")
local lamps = require("lib.casino.lamps")
local net = require("lib.casino.net")
local session = require("lib.casino.session")
local stats = require("lib.casino.stats")
local wallet = require("lib.casino.wallet")

local M = {}

M.UNWIND = "casino pretend seat over"   -- what Table:run throws to end a pretend seat from any scene

local REAL = { badges = badges, books = books, journal = journal, lamps = lamps, net = net, session = session, stats = stats, wallet = wallet }

-- The only real calls a pretend seat makes: they find peripherals, and neither can move, write or say anything
local THROUGH = { lamps = { rescan = true }, net = { open = true } }

local stand = nil   -- the stand-ins of the pretend seat sitting now, or nil for a live table

--- The door to a module, by name.
function M.to(name)
  local real = assert(REAL[name], "no door to " .. tostring(name))
  local through = THROUGH[name] or {}
  return setmetatable({}, {
    __index = function(_, key)
      if not stand or through[key] then return real[key] end
      local fn = stand[name] and stand[name][key]
      if fn == nil then error("a pretend seat has no " .. name .. "." .. tostring(key), 2) end
      return fn
    end,
  })
end

--- A pretend seat sits down: from here every door leads to its stand-ins.
function M.enter(stands)
  stand = stands
end

function M.leave()
  stand = nil
end

--- Whether a pretend seat is sitting now.
function M.pretending()
  return stand ~= nil
end

return M
