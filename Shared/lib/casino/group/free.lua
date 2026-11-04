-- free.lua
-- A free cabinet (Game Night) runs the group engine with no money at all. install() runs first thing in its startup.lua, before
-- anything else is required, and puts stand-ins in front of the wallet and the books for every module on that computer:
--   wallet  keeps only what says who someone is and who owns the computer: who touched, the host's name, the terminal lock. Every
--           balance, transfer, ledger read and approval prompt raises an error instead of reaching ccvault. isApproved is always false.
--   books   every call raises an error. Nothing on a free computer may move a token.
-- The dealer and the seats also check cabinet.free at every money step and never get this far, so these stand-ins are the second
-- lock, not the first: a money call added to the engine and missed for free play stops the table instead of moving tokens.

local M = {}

-- Identity and the terminal lock. None of them moves, books or asks for anything
local THROUGH = { available = true, livePlayer = true, hostName = true, terminalLocked = true, lockIfOwner = true, wantsLock = true }

local function refuse(module)
  return setmetatable({}, {
    __index = function(_, key)
      error("a free table has no " .. module .. "." .. tostring(key), 2)
    end,
    __newindex = function()
      error("a free table's " .. module .. " cannot be changed", 2)
    end,
  })
end

--- The wallet a free computer sees, built over the real one.
function M.wallet(real)
  local stand = {}
  for name in pairs(THROUGH) do
    if type(real[name]) == "function" then stand[name] = real[name] end
  end
  stand.isApproved = function() return false end
  stand.free = true
  return setmetatable(stand, getmetatable(refuse("wallet")))
end

M.books = refuse("books")

--- Put the stand-ins in place for every require on this computer from now on. Must run before anything requires the wallet.
function M.install()
  local real = require("lib.casino.wallet")
  if real.free then return end
  package.loaded["lib.casino.wallet"] = M.wallet(real)
  package.loaded["lib.casino.books"] = M.books
end

return M
