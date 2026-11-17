-- gearshop/store.lua
-- What the shop keeps on disk: the owner's limits, which peripheral is which, and the running state (who is checked in,
-- every tab, store credit, what each display chest was given). Each is one file written whole (journal.save: beside the
-- target, then swapped in, the last good copy kept), so a step that changes several things lands as one or not at all.
-- Tokens themselves are not here: what is owed either way lives in the casino's owed book (lib.casino.journal), and
-- lib.casino.books moves it.

local journal = require("lib.casino.journal")
local rules = require("lib.gearshop.rules")

local M = {}

M.CONFIG_FILE = "gearshop_config.dat"
M.SETUP_FILE = "gearshop_setup.dat"
M.STATE_FILE = "gearshop_state.dat"
M.ROLE_FILE = "gearshop_role.dat"
M.LOG_FILE = "gearshop.log"
local LOG_MAX_BYTES = 64000

function M.log(message)
  journal.appendLine(M.LOG_FILE, LOG_MAX_BYTES, os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(message))
end

-- ---------------------------------------------------------------- limits

--- The owner's limits over the defaults. A value of the wrong type falls back to its default.
function M.loadConfig()
  local saved = journal.load(M.CONFIG_FILE) or {}
  local cfg = {}
  for key, default in pairs(rules.DEFAULTS) do
    local value = saved[key]
    if type(value) == type(default) then cfg[key] = value else cfg[key] = default end
  end
  return cfg
end

--- Only what differs from the defaults is written, so a later change of a default still reaches the shop.
function M.saveConfig(cfg)
  local out = {}
  for key, default in pairs(rules.DEFAULTS) do
    local value = cfg[key]
    if type(value) == type(default) and type(value) ~= "table" and value ~= default then out[key] = value end
    if type(value) == "table" then out[key] = value end
  end
  return journal.save(M.CONFIG_FILE, out)
end

-- ---------------------------------------------------------------- which peripheral is which

function M.newSetup()
  return {
    v = 1,
    nodes = {},      -- ids of the computers whose peripherals this one uses through its ender modem
    door = nil,      -- { monitor, pos }
    sell = nil,      -- { monitor, chest }
    kiosk = nil,     -- { monitor, chest, detector, pos }
    intake = nil,    -- { chest }
    stations = {},   -- { { monitor, chest, detector, pos }, ... }
    vault = {},      -- vault chests named by hand, besides everything the vaultMatch limit finds
  }
end

function M.loadSetup()
  local setup = journal.load(M.SETUP_FILE)
  if type(setup) ~= "table" or setup.v ~= 1 then return M.newSetup() end
  setup.nodes = setup.nodes or {}
  setup.stations = setup.stations or {}
  setup.vault = setup.vault or {}
  return setup
end

function M.saveSetup(setup)
  return journal.save(M.SETUP_FILE, setup)
end

-- ---------------------------------------------------------------- the running state

function M.newState()
  return {
    v = 1,
    seq = 0,          -- numbers sales, payments and transfers, so each has a tag no other ever had
    shoppers = {},    -- name -> { at, last, level }: who is checked in
    tabs = {},        -- name -> { { key, price, label, at }, ... }: pieces taken and not yet paid for
    credit = {},      -- name -> store credit, thousandths of a token
    carry = {},       -- name -> the fraction of a token a seller is still owed, thousandths
    displays = {},    -- "1".."n" and "kiosk" -> { shopper, type, bracket, page, phase, shown = { key = n }, prices = { key = price } }
    sale = nil,       -- a sale under way: { id, seller, mode, keys, returns, phase }
    payout = nil,     -- a sale's tokens on their way into the owed book: { id, name, tokens }
    payment = nil,    -- a tab's tokens on their way into the owed book: { id, name, tokens }
    collecting = nil, -- tokens being taken from a player: { name, owed }, what the book said before, so what moved is counted once
    paying = nil,     -- tokens being paid to a player: { name, owed }, the same the other way
    stats = { sold = 0, takings = 0, creditSpent = 0, bought = 0, paidOut = 0, creditGiven = 0, unaccounted = 0 },
  }
end

function M.loadState()
  local state = journal.load(M.STATE_FILE)
  if type(state) ~= "table" or state.v ~= 1 then return M.newState() end
  local fresh = M.newState()
  for key, value in pairs(fresh) do
    if state[key] == nil then state[key] = value end
  end
  for key, value in pairs(fresh.stats) do
    if state.stats[key] == nil then state.stats[key] = value end
  end
  return state
end

--- Write the state. `why` names the step, for the log and for the crash tests, and changes nothing.
function M.saveState(state, why)
  local ok = journal.save(M.STATE_FILE, state)
  if not ok then M.log("could not write the state at " .. tostring(why)) end
  return ok
end

-- ---------------------------------------------------------------- controller or node

function M.loadRole()
  if not fs.exists(M.ROLE_FILE) then return nil end
  local h = fs.open(M.ROLE_FILE, "r")
  if not h then return nil end
  local text = (h.readAll() or ""):gsub("%s+", "")
  h.close()
  if text == "shop" or text == "node" then return text end
  return nil
end

function M.saveRole(role)
  local h = fs.open(M.ROLE_FILE, "w")
  if not h then return false end
  h.write(role)
  h.close()
  return true
end

return M
