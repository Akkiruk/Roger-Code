-- gearshop/shop.lua
-- The shop itself: check-in and check-out, filling and emptying display chests, the tab, PAY, the search kiosk and buying
-- gear from players. Everything here runs in the worker coroutine (app.lua), one job at a time, because inventory, detector
-- and money calls wait for the server and lose every event that arrives meanwhile.
--
-- How it stays right across a reboot or a chunk unload, at any step:
--   Items. The chests are the truth. Each display chest has a phase on disk, written before the items move:
--     filling   pieces are on their way in and nothing is on offer yet. After a reboot what arrived goes back and the fill starts again.
--     open      `shown` says what the chest was given. A piece in `shown` that is not in the chest was taken: it goes on a tab,
--               in the same write that takes it out of `shown`, so it is charged once. A piece that comes back comes off.
--     sweeping  the chest is being emptied into the vault. After a reboot whatever is still in it goes on.
--   A piece is only ever moved by moveMany from one inventory to another, so it is in one of them whatever happens.
--   Refused gear (sell chest to returns, or to junk with DONATE): state.moving is written before it moves, and the record
--   of who left it is written with the end of the move; after a reboot finishMove sends on whatever is still behind.
--   Tokens. PAY takes the lines off the tab and writes the amount down as a payment in one write; the payment then goes
--   into the casino's owed book under a tag that can only be booked once (journal.book), and lib.casino.books moves it with
--   its own write-ahead. A sale to the shop for tokens (only with the sellForTokens limit on) is the same the other way round;
--   a sale for store credit only adds to the seller's credit in the sale-booked write. A step repeated after a reboot finds its tag
--   already used and changes nothing.
--
-- A player can be gone at any moment (logged off, or on another server of the network). Every lookup here returns nil and
-- a reason instead of throwing, and whatever could not be done waits: a tab stays a tab, a payout stays owed.
--
-- Stations. The usual layout is one display station per gear type (setup gives each its type). There is no need for a
-- door: a tap on a free station (or the kiosk) checks the player in, and PAY is on every station. The station fills
-- with its type at their level bracket (the nearest bracket with stock), and is theirs until DONE, check-out, walking away from it (stationLeaveDistance), or leaving it untouched for
-- stationIdleMinutes; then it is emptied into the vault and free again. One shopper holds at most stationsPerShopper at
-- once: tapping one more frees the one they used longest ago. Anyone else tapping a held station is told whose it is.
-- A station with no type of its own (old setups, or a wing) still offers its TYPE picker.

local rules = require("lib.gearshop.rules")
local store = require("lib.gearshop.store")
local stockLib = require("lib.gearshop.stock")
local journal = require("lib.casino.journal")
local books = require("lib.casino.books")
local wallet = require("lib.casino.wallet")
local economy = require("lib.casino.economy")

local M = {}
local Shop = {}
Shop.__index = Shop

local NOTE_MS = 8000

local function now() return os.epoch("utc") end

--- "1 token", "5 tokens".
local function tokensText(n)
  return n .. (n == 1 and " token" or " tokens")
end

--- @param io table      { call(name, method, ...) -> ok, result ; names() -> list ; hasType(name, type) ; types(name) }
function M.new(io, cfg, setup, state)
  local self = setmetatable({
    io = io, cfg = cfg, setup = setup, state = state,
    stock = stockLib.new(io, cfg, store.log),
    stations = {}, all = {}, kiosk = nil,
    chestRole = {}, monitorRole = {},
    notes = {},        -- monitor name -> { text, till }
    watched = {}, watches = 0,
    linked = {},       -- node id -> true once linked
    sizes = {},        -- display chest -> slots
    missing = {},      -- shopper -> how many looks in a row did not find them
    awaiting = {},     -- player -> when to stop waiting for their APPROVE click, so a payment goes through without another tap
    away = {},         -- station id -> how many looks in a row found its shopper walked away from it
    tappedAt = {},     -- player -> the monitor they last tapped, for what is told them once they click APPROVE
    sellView = nil,
    ready = false, status = "Starting", version = 0,
  }, Shop)
  for i, s in ipairs(setup.stations or {}) do
    local d = { id = tostring(i), kind = "station", index = i, chest = s.chest, monitor = s.monitor, detector = s.detector, pos = s.pos,
      category = s.category, gearType = s.gearType }
    self.stations[#self.stations + 1] = d
    self.all[#self.all + 1] = d
  end
  if setup.kiosk and setup.kiosk.chest then
    local k = setup.kiosk
    self.kiosk = { id = "kiosk", kind = "kiosk", chest = k.chest, monitor = k.monitor, detector = k.detector, pos = k.pos }
    self.all[#self.all + 1] = self.kiosk
  end
  for _, d in ipairs(self.all) do
    if d.chest then self.chestRole[d.chest] = { role = d.kind, d = d } end
    if d.monitor then self.monitorRole[d.monitor] = { role = d.kind, d = d } end
  end
  if setup.sell then
    if setup.sell.chest then self.chestRole[setup.sell.chest] = { role = "sell" } end
    if setup.sell.monitor then self.monitorRole[setup.sell.monitor] = { role = "sell" } end
  end
  if setup.intake and setup.intake.chest then self.chestRole[setup.intake.chest] = { role = "intake" } end
  if setup.returns and setup.returns.chest then self.chestRole[setup.returns.chest] = { role = "returns" } end
  if setup.junk and setup.junk.chest then self.chestRole[setup.junk.chest] = { role = "junk" } end
  if setup.door and setup.door.monitor then self.monitorRole[setup.door.monitor] = { role = "door" } end
  if setup.info and setup.info.monitor then self.monitorRole[setup.info.monitor] = { role = "info" } end
  return self
end

function Shop:changed()
  self.version = self.version + 1
end

function Shop:save(why)
  self:changed()
  return store.saveState(self.state, why)
end

function Shop:nextId()
  self.state.seq = self.state.seq + 1
  return self.state.seq
end

--- The state of one display chest.
function Shop:ds(d)
  local all = self.state.displays
  local ds = all[d.id]
  if not ds then
    ds = { shown = {}, prices = {} }
    all[d.id] = ds
  end
  ds.shown, ds.prices = ds.shown or {}, ds.prices or {}
  return ds
end

--- A line for whoever is looking at a monitor.
function Shop:note(monitor, text, ms)
  if not monitor then return end
  self.notes[monitor] = { text = text, till = now() + (ms or NOTE_MS) }
  self:changed()
end

function Shop:noteFor(monitor)
  local note = monitor and self.notes[monitor]
  if note and note.till > now() then return note.text end
  return nil
end

--- A player did something. monitor: the screen they tapped, where a later note for them (after APPROVE) is shown.
function Shop:seen(name, monitor)
  local shopper = name and self.state.shoppers[name]
  if shopper then shopper.last = now() end
  if name then self.missing[name] = nil end
  if name and monitor then self.tappedAt[name] = monitor end
end

-- ---------------------------------------------------------------- players, never throwing

local function hostName()
  return wallet.hostName()
end

--- Ask a player to approve this computer, if they are the one at it and have not yet. Returns true if they were asked.
-- Their click is then waited for (upkeep), and what was held up for it goes through.
function Shop:askApproval(name)
  if wallet.livePlayer() ~= name or wallet.isApproved() then return false end
  if wallet.requestApproval() == nil then return false end
  self.awaiting[name] = now() + 90000
  return true
end

--- Whether a refusal will pass once the player has approved this computer: also a transfer left in doubt by a crash, which only
-- the server's ledger can answer, and the ledger only answers an approved player.
local function needsApproval(err)
  return err ~= nil and (wallet.isRetryable(err) or tostring(err):find("in doubt", 1, true) ~= nil)
end

--- A player's vault level, or nil and why. Works for a player who is offline or on another server.
function Shop:vaultLevel(name)
  if not ccvault or type(ccvault.getPlayerVaultLevel) ~= "function" then return nil, "this server has no vault level lookup" end
  local err
  for _ = 1, 3 do
    local ok, level, why = economy.call(ccvault.getPlayerVaultLevel, name)
    if not ok then return nil, tostring(level) end
    if type(level) == "number" then return level end
    err = tostring(why)
    if not err:find("try again", 1, true) then return nil, err end
  end
  return nil, err
end

--- Every detector the shop can ask where a player is: the ones given a job first, then any other one attached. A display
-- chest needs no detector of its own, so a shop may have only one, anywhere (the position function works server-wide).
function Shop:detectors()
  local list, seen = {}, {}
  local function add(name)
    if name and not seen[name] then
      seen[name] = true
      list[#list + 1] = name
    end
  end
  if self.setup.door then add(self.setup.door.detector) end
  for _, d in ipairs(self.all) do add(d.detector) end
  for _, name in ipairs(self.io.names()) do
    if self.io.hasType(name, "playerDetector") then add(name) end
  end
  return list
end

--- Where a player is. Returns pos, true; or nil, true when a detector answered that they are not here (offline, another
-- server, another dimension); or nil, false when no detector could say.
function Shop:playerPos(name)
  for _, detector in ipairs(self:detectors()) do
    local ok, pos = self.io.call(detector, "getPlayerPos", name)
    if ok and type(pos) == "table" then
      if type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number" then return pos, true end
      return nil, true
    end
  end
  return nil, false
end

local function places(self)
  local list = {}
  if self.setup.door and self.setup.door.pos then list[#list + 1] = self.setup.door.pos end
  -- a shopper at the sell counter is in the shop too
  if self.setup.sell and self.setup.sell.pos then list[#list + 1] = self.setup.sell.pos end
  for _, d in ipairs(self.all) do
    if d.pos then list[#list + 1] = d.pos end
  end
  return list
end

--- Check out whoever has gone: logged off or moved to another server, walked away, or touched nothing for too long.
function Shop:presence()
  local names = {}
  for name in pairs(self.state.shoppers) do names[#names + 1] = name end
  local seenAt = {}
  for _, name in ipairs(names) do
    local shopper = self.state.shoppers[name]
    local why
    if now() - (shopper.last or 0) > self.cfg.idleMinutes * 60000 then
      why = "idle"
    else
      local pos, answered = self:playerPos(name)
      seenAt[name] = pos
      local gone = false
      if answered and not pos then
        gone = true
      elseif pos then
        local spots = places(self)
        gone = #spots > 0
        for _, spot in ipairs(spots) do
          if rules.distance(pos, spot) <= self.cfg.leaveDistance then gone = false end
        end
      end
      if gone then
        self.missing[name] = (self.missing[name] or 0) + 1
        if self.missing[name] >= 2 then why = "left the shop" end
      else
        self.missing[name] = nil
      end
    end
    if why then self:checkOut(name, why) end
  end
  self:freeStations(seenAt)
end

--- Free the stations (and the kiosk) their shoppers have left: walked away from (two looks running), or not used for too
-- long. seenAt: where each shopper was seen just now, when a detector could say.
function Shop:freeStations(seenAt)
  local idle = (self.cfg.stationIdleMinutes or 0) * 60000
  local far = self.cfg.stationLeaveDistance or 0
  for _, d in ipairs(self.all) do
    local ds = self:ds(d)
    local name = ds.shopper
    if ds.phase == "open" and name and self.state.shoppers[name] then
      if not ds.used then ds.used = now() end
      local why
      if idle > 0 and now() - ds.used > idle then
        why = "nobody used it for " .. self.cfg.stationIdleMinutes .. " min"
      else
        local pos = seenAt[name]
        if far > 0 and pos and d.pos and rules.distance(pos, d.pos) > far then
          self.away[d.id] = (self.away[d.id] or 0) + 1
          if self.away[d.id] >= 2 then why = name .. " walked away" end
        else
          self.away[d.id] = nil
        end
      end
      if why then
        store.log("station " .. d.id .. " freed: " .. why)
        if self:release(d) then self:note(d.monitor, "Free again: " .. why .. ".") end
      end
    else
      self.away[d.id] = nil
    end
  end
end

--- How soon a station someone else holds is likely free, for whoever taps it: "" when there is no telling.
function Shop:freeSoon(d)
  if (self.away[d.id] or 0) > 0 then return " Free soon." end
  local idle = (self.cfg.stationIdleMinutes or 0) * 60000
  local used = self:ds(d).used
  if idle > 0 and used then
    local left = math.max(1, math.ceil((idle - (now() - used)) / 60000))
    return " Free in ~" .. left .. " min if unused."
  end
  return ""
end

-- ---------------------------------------------------------------- the network and the peripherals

local function localEnderModem(io)
  for _, name in ipairs(io.names()) do
    if not name:match("^%d+:") and io.hasType(name, "modem") then
      local ok, methods = pcall(peripheral.getMethods, name)
      if ok and type(methods) == "table" then
        for _, method in ipairs(methods) do
          if method == "link" then return name end
        end
      end
    end
  end
  return nil
end
M.localEnderModem = localEnderModem

--- Setup's "stand at it" step: where the owner is, and, when the step offers one, the free detector they stand nearest
-- (within 16 blocks). A detector of its own is optional: without one the position comes through any detector attached,
-- which sees the owner wherever they are on the server. assigned(name) says whether a detector already has a job.
-- Returns { detector = name|nil, pos = {x,y,z}|nil }, or nil and what to tell the owner.
function M.standAt(io, who, wantDetector, assigned)
  local detectors = {}
  for _, name in ipairs(io.names()) do
    if io.hasType(name, "playerDetector") then detectors[#detectors + 1] = name end
  end
  if not who or #detectors == 0 then return nil, "No player detector is attached, or nobody is at the terminal." end
  local result = {}
  if wantDetector then
    local free = {}
    for _, name in ipairs(detectors) do
      if not assigned(name) then free[#free + 1] = name end
    end
    for range = 1, 16 do
      local hits = {}
      for _, name in ipairs(free) do
        local ok, inside = io.call(name, "isPlayerInRange", range, who)
        if ok and inside == true then hits[#hits + 1] = name end
      end
      if #hits == 1 then
        result.detector = hits[1]
        break
      elseif #hits > 1 then
        return nil, "Two detectors are as near as each other. Step closer to yours, press Enter."
      end
    end
  end
  local order = {}
  if result.detector then order[1] = result.detector end
  for _, name in ipairs(detectors) do
    if name ~= result.detector then order[#order + 1] = name end
  end
  for _, name in ipairs(order) do
    local ok, pos = io.call(name, "getPlayerPos", who)
    if ok and type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number" then
      result.pos = { x = pos.x, y = pos.y, z = pos.z }
      break
    end
  end
  if not result.detector and not result.pos then
    return nil, "No detector can see where " .. who .. " is. Press Enter to try again, or S to skip."
  end
  return result
end

--- Link every node that is not linked yet. Links are not saved by the server, so this runs on every boot and again for a
-- node that was not loaded.
function Shop:link()
  local modem = localEnderModem(self.io)
  self.modem = modem
  local all = true
  for _, id in ipairs(self.setup.nodes or {}) do
    if not self.linked[id] then
      local ok, linked, why = false, false, "no ender modem on this computer"
      if modem then ok, linked, why = self.io.call(modem, "link", id) end
      if ok and linked == true then
        self.linked[id] = true
      else
        all = false
        self.linkTrouble = "computer " .. id .. ": " .. tostring(ok and why or linked)
      end
    end
  end
  if all then self.linkTrouble = nil end
  return all
end

function Shop:isVaultChest(name)
  if self.chestRole[name] and self.chestRole[name].role ~= "vault" then return false end
  if not self.io.hasType(name, "inventory") then return false end
  for _, listed in ipairs(self.setup.vault or {}) do
    if listed == name then return true end
  end
  local match = self.cfg.vaultMatch
  if match == "" then return false end
  for _, kind in ipairs(self.io.types(name)) do
    if kind:lower():find(match:lower(), 1, true) then return true end
  end
  return false
end

function Shop:watch(name)
  if self.watched[name] then return true end
  if self.watches >= self.cfg.maxWatches then return false end
  local ok, err = self.io.call(name, "watch")
  if ok then
    self.watched[name] = true
    self.watches = self.watches + 1
  elseif tostring(err):find("too many watches", 1, true) then
    -- the server allows fewer than the limit here says: stop asking
    self.cfg.maxWatches = self.watches
  end
  return ok
end

local function unwatched(self, name)
  if self.watched[name] then
    self.watched[name] = nil
    self.watches = self.watches - 1
  end
end

--- Find the vault chests among what is attached, and watch what can be watched: the chests players touch first.
function Shop:discover()
  for _, name in ipairs(self.io.names()) do
    if self:isVaultChest(name) and not self.stock:has(name) then
      self.stock:add(name)
      self.chestRole[name] = { role = "vault" }
    end
  end
end

function Shop:watchAll()
  for _, d in ipairs(self.all) do self:watch(d.chest) end
  if self.setup.sell and self.setup.sell.chest then self:watch(self.setup.sell.chest) end
  if self.setup.intake and self.setup.intake.chest then self:watch(self.setup.intake.chest) end
  for _, name in ipairs(self.stock.order) do
    if self.watches >= self.cfg.maxWatches then break end
    self:watch(name)
  end
end

--- A peripheral is back (its computer loaded, or a link was made).
function Shop:attached(name)
  local role = self.chestRole[name]
  if not role and self:isVaultChest(name) then
    self.stock:add(name)
    role = { role = "vault" }
    self.chestRole[name] = role
  end
  if not role then return end
  if role.role == "vault" then
    local chest = self.stock.chests[name]
    if chest.indexed and self.watched[name] then return end   -- it never went away
    self.stock:index(name)
    self:watch(name)
  elseif role.d then
    self:watch(name)
    self:mend(role.d)
  elseif role.role == "sell" then
    self:watch(name)
    if self.state.sale then self:finishSale() end
    if self.state.moving then self:finishMove() end
    self:sellScan()
  elseif role.role == "intake" then
    self:watch(name)
    self:intake()
  end
  self:changed()
end

function Shop:detached(name)
  unwatched(self, name)
  if self.stock:has(name) then self.stock:lose(name) end
  self:changed()
end

-- ---------------------------------------------------------------- the tab

local function tabOf(self, name)
  local tab = self.state.tabs[name]
  if not tab then
    tab = {}
    self.state.tabs[name] = tab
  end
  return tab
end

--- What a player has to pay: the pieces on their tab plus anything PAY could not collect before.
function Shop:owes(name)
  local debt = -journal.owedTo(name)
  local pending = self.state.payment
  if pending and pending.name == name then debt = debt + pending.tokens end
  return rules.tabTotal(self.state.tabs[name]) + math.max(0, debt)
end

function Shop:priceOf(d, key)
  local ds = self:ds(d)
  if ds.prices[key] then return ds.prices[key] end
  -- every piece costs its own level's price
  local piece = self.stock.known[key]
  if piece then return rules.price(piece.level or 0, self.cfg) end
  -- a piece the index does not know, on a station: the cheapest price of the level it was showing
  if d.kind == "station" and ds.bracket then return (rules.bracketPrices(ds.bracket, self.cfg)) end
  return rules.price(0, self.cfg)
end

--- Who took a piece from this chest: whoever is nearest it, by its own detector. A checked-in shopper at the chest comes
-- before anyone else standing there. When the detector sees nobody, or there is none, it is the shopper the chest is
-- locked to.
function Shop:taker(d)
  local ds = self:ds(d)
  local names = {}
  for name in pairs(self.state.shoppers) do names[#names + 1] = name end
  table.sort(names)
  local shoppers, others = {}, {}
  if d.detector then
    local ok, list = self.io.call(d.detector, "getPlayersInRange", self.cfg.chargeRange)
    if ok and type(list) == "table" then
      for _, name in ipairs(list) do
        if type(name) == "string" then
          if self.state.shoppers[name] then shoppers[#shoppers + 1] = name else others[#others + 1] = name end
        end
      end
    end
  end
  local near = #shoppers > 0 and shoppers or others
  table.sort(near)
  if #near == 1 then return near[1] end
  if #near > 1 then
    local best, bestDistance
    if d.pos then
      for _, name in ipairs(near) do
        local ok, pos = self.io.call(d.detector, "getPlayerPos", name)
        local distance = ok and type(pos) == "table" and pos.x and rules.distance(pos, d.pos)
        if distance and (not bestDistance or distance < bestDistance) then best, bestDistance = name, distance end
      end
    end
    if best then return best end
    for _, name in ipairs(near) do
      if name == ds.shopper then return name end
    end
    return near[1]
  end
  return ds.shopper or names[1]
end

function Shop:charge(who, d, key)
  local price = self:priceOf(d, key)
  if not who then
    self.state.stats.unaccounted = self.state.stats.unaccounted + 1
    store.log("a piece left chest " .. d.id .. " with nobody to charge: " .. key)
    return
  end
  local piece = self.stock.known[key]
  local ds = self:ds(d)
  local label = piece and piece.label
    or (rules.typeLabel(ds.type or "gear") .. " Lv " .. rules.bracketLabel(ds.bracket or 0))
  table.insert(tabOf(self, who), { key = key, price = price, label = label, at = now() })
  if who == ds.shopper then ds.used = now() end
  self:seen(who)
  self:note(d.monitor, who .. ": " .. label .. " +" .. price .. " (tab " .. self:owes(who) .. ")")
end

--- Take one line with this key off a tab, whoever's it is. Returns the line and the name, or nil.
function Shop:untab(key)
  for name, tab in pairs(self.state.tabs) do
    for i = #tab, 1, -1 do
      if tab[i].key == key then
        local line = table.remove(tab, i)
        if #tab == 0 then self.state.tabs[name] = nil end
        return line, name
      end
    end
  end
  return nil
end

--- Whether a piece with this key was paid for this visit, and could be refunded if it comes back.
function Shop:paidFor(key)
  for _, lines in pairs(self.state.paid) do
    for _, line in ipairs(lines) do
      if line.key == key then return true end
    end
  end
  return false
end

--- A piece paid for this visit came back: its store credit goes back to credit and its tokens back to the player. The
-- tokens are written down as a refund (state.refunds) in the caller's next save, the same write that takes the line off
-- `paid`, and bookPending puts them in the owed book once (tag gs-ref-<id>); settle then pays them, host to player, which
-- needs no touch. Returns the line and the name, or nil. refunded: a set of names, to settle afterwards.
function Shop:unpay(key, refunded)
  local st = self.state
  for name, lines in pairs(st.paid) do
    for i = #lines, 1, -1 do
      local line = lines[i]
      if line.key == key then
        table.remove(lines, i)
        if #lines == 0 then st.paid[name] = nil end
        local credit, tokens = line.credit or 0, line.tokens or 0
        if credit > 0 then
          st.credit[name] = (st.credit[name] or 0) + credit * rules.MILLI
          st.stats.creditSpent = st.stats.creditSpent - credit
        end
        if tokens > 0 then
          st.refunds[#st.refunds + 1] = { id = self:nextId(), name = name, tokens = tokens }
          st.stats.refunded = (st.stats.refunded or 0) + tokens
        end
        st.stats.sold = math.max(0, st.stats.sold - 1)
        if refunded then refunded[name] = true end
        return line, name
      end
    end
  end
  return nil
end

--- Pay out what refunds put in the book, to each player named. A payout needs only their approval, no touch; what
-- cannot go now (offline, the owner's floor) stays owed and goes the next time.
function Shop:settleRefunds(names)
  if not self:bookPending() then return end
  for name in pairs(names) do
    if journal.owedTo(name) > 0 then self:settle(name) end
  end
end

function Shop:tabbed(key)
  for _, tab in pairs(self.state.tabs) do
    for _, line in ipairs(tab) do
      if line.key == key then return true end
    end
  end
  return false
end

-- ---------------------------------------------------------------- display chests

function Shop:chestSize(d)
  if self.sizes[d.chest] then return self.sizes[d.chest] end
  local ok, size = self.io.call(d.chest, "size")
  if ok and type(size) == "number" then
    self.sizes[d.chest] = size
    return size
  end
  return 54
end

--- Compare an open chest with what it was given: charge what is gone, take off the tab what came back.
-- Returns false if the chest could not be read.
function Shop:reconcile(d)
  local ds = self:ds(d)
  if ds.phase ~= "open" then
    if not ds.phase and not ds.shopper then
      -- a chest nobody has open is never left holding anything
      local ok, list = self.io.call(d.chest, "list")
      if ok and type(list) == "table" and next(list) then self:sweep(d, false) end
    end
    return true
  end
  local ok, list = self.io.call(d.chest, "list")
  if not ok or type(list) ~= "table" then return false end
  local have = {}
  for _, item in pairs(list) do
    local key = rules.key(item)
    have[key] = (have[key] or 0) + 1
  end
  local changed, who, asked = false, nil, false
  local gone = {}
  for key, n in pairs(ds.shown) do
    if (have[key] or 0) < n then gone[#gone + 1] = key end
  end
  table.sort(gone)
  for _, key in ipairs(gone) do
    local n, held = ds.shown[key], have[key] or 0
    if not asked then
      who, asked = self:taker(d), true
    end
    for _ = 1, n - held do self:charge(who, d, key) end
    if held > 0 then
      ds.shown[key] = held
    else
      ds.shown[key] = nil
      ds.prices[key] = nil
    end
    changed = true
  end
  local refunded = {}
  for key, held in pairs(have) do
    for _ = 1, held - (ds.shown[key] or 0) do
      -- put back: off the tab if it is still on one, or refunded if it was paid for this visit
      local line, name = self:untab(key)
      local back = nil
      if not line then
        line, name = self:unpay(key, refunded)
        back = line and ((line.tokens or 0) + (line.credit or 0)) or nil
      end
      if not line then break end
      -- it is on display here again, at the price it was charged
      ds.shown[key] = (ds.shown[key] or 0) + 1
      if line.price ~= self:priceOf(d, key) then ds.prices[key] = line.price end
      if name == ds.shopper then ds.used = now() end
      self:seen(name)
      self:note(d.monitor, name .. ": " .. tostring(line.label) .. " put back"
        .. (back and (", " .. back .. " back") or (" (tab " .. self:owes(name) .. ")")))
      changed = true
    end
  end
  if changed then self:save("reconcile") end
  if next(refunded) then self:settleRefunds(refunded) end
  -- charged as taken: what went on the tab is paid now, if the server lets the shop charge them (they approved this
  -- computer; an older vhcctweaks also wants a recent touch). Whatever it will not take stays owed, paid on their next tap.
  if who and #gone > 0 then self:autoPay(who, d.monitor) end
  return true
end

--- Make `shown` what the chest holds now. Returns false if the chest could not be read.
function Shop:adopt(d)
  local ds = self:ds(d)
  local ok, list = self.stock:listKnown(d.chest)
  if not ok or type(list) ~= "table" then return false end
  ds.shown, ds.prices = {}, {}
  for _, item in pairs(list) do
    local key = rules.key(item)
    ds.shown[key] = (ds.shown[key] or 0) + 1
    -- each piece's price is fixed when it goes on display, so a limit changed meanwhile never changes what it is charged
    if self.stock.known[key] then ds.prices[key] = self:priceOf(d, key) end
  end
  return true
end

--- Empty a display chest into the vault. keep: the shopper keeps the chest (a new page is coming).
-- Returns true once the chest is empty.
function Shop:sweep(d, keep)
  local ds = self:ds(d)
  if ds.phase == "open" and not self:reconcile(d) then return false end
  ds.phase = "sweeping"
  ds.shown, ds.prices = {}, {}
  if not keep then
    ds.shopper, ds.type, ds.bracket, ds.page, ds.pages, ds.total, ds.query = nil, nil, nil, nil, nil, nil, nil
    ds.used = nil
    self.away[d.id] = nil
  end
  self:save("sweep-begin")
  local ok, list = self.stock:listKnown(d.chest)
  if not ok or type(list) ~= "table" then return false end
  local slots = {}
  for slot, item in pairs(list) do slots[slot] = rules.key(item) end
  if next(slots) then
    local _, _, stuck = self.stock:put(d.chest, slots)
    if stuck > 0 then
      self.trouble = "The vault has no room for " .. stuck .. " pieces from chest " .. d.id
      store.log(self.trouble)
      return false
    end
  end
  ds.phase = nil
  self.trouble = nil
  self:save("sweep-end")
  return true
end

function Shop:release(d)
  return self:sweep(d, false)
end

--- Put the shopper's pick in their chest: empty it, choose the page, move the pieces, then record what arrived.
function Shop:fill(d)
  local ds = self:ds(d)
  local name = ds.shopper
  if not name then return false end
  if not self:sweep(d, true) then return false end
  local level = (self.state.shoppers[name] or {}).level or self.cfg.defaultLevel
  local list
  if d.kind == "kiosk" then
    list = self.stock:search(ds.query or {}, level)
  else
    list = self.stock:select(ds.type, ds.bracket, level)
  end
  local entries, page, pages = rules.page(list, ds.page, self:chestSize(d))
  ds.page, ds.pages, ds.total = page, pages, #list
  ds.phase = "filling"
  self:save("fill-begin")
  if #entries > 0 then self.stock:take(entries, d.chest) end
  if not self:adopt(d) then return false end
  ds.phase = "open"
  ds.fills = (ds.fills or 0) + 1
  self:save("fill-end")
  return true
end

--- Finish whatever a reboot, an unload or a failed call left half done at this chest.
function Shop:mend(d)
  local ds = self:ds(d)
  local shopperHere = ds.shopper and self.state.shoppers[ds.shopper] ~= nil
  if ds.phase == "filling" then
    if shopperHere then
      -- nothing was on offer yet, so nothing can have been taken: put back what arrived and fill again
      self:fill(d)
    else
      ds.phase = "sweeping"
      self:release(d)
    end
  elseif ds.phase == "sweeping" then
    if shopperHere then self:fill(d) else self:release(d) end
  elseif ds.phase == "open" then
    if shopperHere then
      -- after a restart the pieces on show have not been read yet: without this the monitor names them all level 0
      self.stock:listKnown(d.chest)
      self:reconcile(d)
    else
      self:release(d)
    end
  elseif shopperHere then
    -- stopped between emptying the chest and filling it again
    self:fill(d)
  else
    ds.shopper = nil
    self:reconcile(d)
  end
end

function Shop:open(d, name, kind, bracket, page)
  local ds = self:ds(d)
  ds.shopper, ds.type, ds.bracket, ds.page = name, kind, bracket, page or 1
  ds.used = now()
  return self:fill(d)
end

local function isFree(self, d)
  local ds = self:ds(d)
  return not ds.phase and (not ds.shopper or not self.state.shoppers[ds.shopper])
end

--- The types with stock near a bracket that a chest may show: its wing's, or every type when it has none.
function Shop:typesFor(d, bracket)
  return rules.inCategoryList(self.stock:typesNear(bracket), d.category, self.cfg)
end

--- The stations a shopper holds now, the one they used longest ago first.
function Shop:held(name)
  local list = {}
  for _, d in ipairs(self.stations) do
    if self:ds(d).shopper == name then list[#list + 1] = d end
  end
  table.sort(list, function(a, b)
    local ua, ub = self:ds(a).used or 0, self:ds(b).used or 0
    if ua ~= ub then return ua < ub end
    return a.index < b.index
  end)
  return list
end

--- The next bracket from `from` in direction `step` (-1 or 1) that has some of a type, or nil.
local function nextBracket(counts, from, step)
  local b = from + step
  while b >= 0 and b <= 10 do
    if (counts[b] or 0) > 0 then return b end
    b = b + step
  end
  return nil
end

-- ---------------------------------------------------------------- the door

function Shop:checkIn(name, monitor)
  if not name then
    self:note(monitor, "Could not tell who tapped. Tap again.")
    return false
  end
  if not self.ready then
    self:note(monitor, "The shop is still counting its stock.")
    return false
  end
  local st = self.state
  if st.shoppers[name] then
    self:seen(name)
    self:note(monitor, name .. " is already checked in.")
    return true
  end
  local level, why = self:vaultLevel(name)
  if not level then
    store.log("vault level of " .. name .. ": " .. tostring(why))
    level = self.cfg.defaultLevel
  end
  st.shoppers[name] = { at = now(), last = now(), level = level }
  self:save("checkin")
  local asked = self:askApproval(name)
  self:settle(name)
  -- checked in at the door (if the shop has one) or, the usual way, by tapping a station or the kiosk
  local atDoor = self.setup.door and monitor ~= nil and monitor == self.setup.door.monitor
  local text = "Welcome " .. name .. " (level " .. level .. ")." .. (atDoor and " Tap a station to browse." or "")
  local owes = self:owes(name)
  if owes > 0 then text = text .. " Tab from last time: " .. owes .. "." end
  if asked then text = text .. " Click APPROVE in chat so PAY is one tap." end
  self:note(monitor, text, 15000)
  return true
end

function Shop:checkOut(name, why, monitor)
  local st = self.state
  if not name or not st.shoppers[name] then
    self:note(monitor, (name or "You") .. " is not checked in.")
    return false
  end
  for _, d in ipairs(self.all) do
    if self:ds(d).shopper == name then self:release(d) end
  end
  -- what they still owe is charged on the way out, if the server lets the shop (see autoPay); else it is kept for next time
  self:autoPay(name, monitor)
  st.shoppers[name] = nil
  -- the visit is over: a piece paid for now is theirs, and one brought back later is not refunded
  st.paid[name] = nil
  self.missing[name] = nil
  self:save("checkout")
  store.log(name .. " checked out (" .. tostring(why) .. ")")
  local owes = self:owes(name)
  local text = name .. " checked out."
  if owes > 0 then text = text .. " Tab of " .. owes .. " is kept for next time." end
  self:note(monitor or (self.setup.door and self.setup.door.monitor), text)
  return true
end

-- ---------------------------------------------------------------- money

--- Something new went into the book for a player while a count for them was still waiting: it is not part of what moved.
local function shiftCounts(st, name, delta)
  if st.collecting and st.collecting.name == name then st.collecting.owed = st.collecting.owed + delta end
  if st.paying and st.paying.name == name then st.paying.owed = st.paying.owed + delta end
end

--- A payment or a payout that was written down goes into the owed book, once.
function Shop:bookPending()
  local st = self.state
  local fine = true
  if st.payment then
    if journal.book(st.payment.name, -st.payment.tokens, "gs-pay-" .. st.payment.id) then
      shiftCounts(st, st.payment.name, -st.payment.tokens)
      st.payment = nil
      self:save("pay-booked")
    else
      fine = false
    end
  end
  if st.payout then
    if journal.book(st.payout.name, st.payout.tokens, "gs-sale-" .. st.payout.id) then
      shiftCounts(st, st.payout.name, st.payout.tokens)
      st.payout = nil
      self:save("payout-booked")
    else
      fine = false
    end
  end
  -- refunds (a paid piece put back, store credit put against what is owed): each in the book once, then off the list
  while st.refunds[1] do
    local r = st.refunds[1]
    if journal.book(r.name, r.tokens, "gs-ref-" .. r.id) then
      shiftCounts(st, r.name, r.tokens)
      table.remove(st.refunds, 1)
      self:save("refund-booked")
    else
      fine = false
      break
    end
  end
  return fine
end

--- Count what a transfer moved, once, whatever happened on the way. Before tokens move, what the book said the player
-- owed (or was owed) is written down (`collecting`, `paying`); the difference from what it says once nothing is in doubt for
-- them is what moved. So a crash between the tokens moving and the count, at any point, is counted on the next start and
-- never twice. Returns true if something was counted or cleared.
function Shop:countMoved()
  local st, changed = self.state, false
  local doubt = {}
  for _, move in pairs(journal.moves()) do doubt[move.name] = true end
  local c = st.collecting
  if c and not doubt[c.name] then
    local went = journal.owedTo(c.name) - c.owed
    if went > 0 then st.stats.takings = st.stats.takings + went end
    st.collecting, changed = nil, true
  end
  local p = st.paying
  if p and not doubt[p.name] then
    local went = p.owed - journal.owedTo(p.name)
    if went > 0 then st.stats.paidOut = st.stats.paidOut + went end
    st.paying, changed = nil, true
  end
  return changed
end

--- Ask the server's ledger about transfers a crash cut short (for one player, or everyone), and count the ones that turn
-- out to have gone through. Returns true when nothing is left in doubt.
function Shop:resolve(name)
  local ok, clear = pcall(books.resolve, name)
  if self:countMoved() then self:save("counted") end
  return ok and clear == true
end

--- A transfer a crash cut short is answered before anything else moves for that player: until it is, the book cannot say
-- what they owe or are owed. Returns true when nothing is in doubt for them. Answering needs the server's ledger, and so
-- the player approved and at the shop; when it cannot be answered yet they are asked to approve.
function Shop:answered(name)
  if self:resolve(name) then return true end
  self:askApproval(name)
  return false
end

--- Pay a player what the shop owes them, as far as the owner's floor allows. Returns what moved and why not the rest.
function Shop:settle(name)
  if not self:bookPending() then return 0, "the book could not be written" end
  if not self:answered(name) then return 0, "an earlier transfer is in doubt" end
  local owed = journal.owedTo(name)
  if owed <= 0 then return 0 end
  local pay = owed
  if name ~= hostName() then
    pay = rules.payable(owed, wallet.hostBalance(), self.cfg.ownerFloor)
    if pay <= 0 then return 0, "floor" end
  end
  local id = self:nextId()
  self.state.paying = { name = name, owed = owed }
  self:save("payout-begin")
  local moved, _, err = books.move(name, pay, "gs-out-" .. id)
  if self:countMoved() then self:save("payout-end") end
  if needsApproval(err) then self:askApproval(name) end
  return moved, err
end

--- Take from a player what they owe. Needs their fresh touch and their approval; what cannot move stays owed.
function Shop:collect(name)
  if not self:bookPending() then return 0, 0, "the book could not be written" end
  if not self:answered(name) then return 0, math.max(0, -journal.owedTo(name)), "an earlier transfer is in doubt" end
  local owed = journal.owedTo(name)
  if owed >= 0 then return 0, 0 end
  local id = self:nextId()
  self.state.collecting = { name = name, owed = owed }
  self:save("collect-begin")
  local moved, left, err = books.move(name, owed, "gs-in-" .. id)
  if self:countMoved() then self:save("collect-end") end
  return -moved, -left, err
end

--- Store credit goes first, also against tokens a player already owes (a charge the server would not take, or a tab
-- from before): that much credit is spent and the same is written down as a refund in one save, so the owed book gets it
-- once. The lines it paid for change from tokens to credit, so a piece put back later gives credit back, not tokens.
local function creditAgainstDebt(self, name)
  local st = self.state
  local debt = math.max(0, -journal.owedTo(name))
  local have = math.floor((st.credit[name] or 0) / rules.MILLI)
  local use = math.min(debt, have)
  if use <= 0 then return 0 end
  local left = st.credit[name] - use * rules.MILLI
  st.credit[name] = left > 0 and left or nil
  st.stats.creditSpent = st.stats.creditSpent + use
  st.refunds[#st.refunds + 1] = { id = self:nextId(), name = name, tokens = use }
  local shift = use
  local lines = st.paid[name] or {}
  for i = #lines, 1, -1 do
    if shift <= 0 then break end
    local line = lines[i]
    local n = math.min(line.tokens or 0, shift)
    line.tokens, line.credit, shift = (line.tokens or 0) - n, (line.credit or 0) + n, shift - n
  end
  self:save("credit-begin")
  self:bookPending()
  return use
end

--- Pay a player's tab: store credit first, then tokens (taken now, or owed in the book if they will not move).
-- opts.quiet: charged as taken, so a refusal says nothing (the take's own line on the screen already shows the tab).
-- Returns moved, left, err: tokens taken, tokens still owed, and why not.
function Shop:pay(name, monitor, opts)
  opts = opts or {}
  if not name then
    self:note(monitor, "Could not tell who tapped. Tap again.")
    return 0, 0
  end
  if not opts.quiet then self:seen(name, monitor) end
  -- a piece taken a moment ago is on the tab before it is added up (and is not charged again from in here)
  local was = self.inPay
  self.inPay = true
  for _, d in ipairs(self.all) do
    if self:ds(d).phase == "open" then self:reconcile(d) end
  end
  self.inPay = was
  if not self:bookPending() then
    self:note(monitor, "The shop cannot write its book. Tell the owner.")
    return 0, 0
  end
  local st = self.state
  local lines = st.tabs[name]
  local total = rules.tabTotal(lines)
  local credit, payTokens = 0, 0
  if total > 0 then
    local tokens
    credit, tokens = rules.splitPayment(total, st.credit[name])
    payTokens = tokens
    local id = self:nextId()
    st.tabs[name] = nil
    if credit > 0 then
      local left = st.credit[name] - credit * rules.MILLI
      st.credit[name] = left > 0 and left or nil
      st.stats.creditSpent = st.stats.creditSpent + credit
    end
    -- each line paid is remembered for this visit, with how much of it was credit, so one put back is refunded right
    local paid = st.paid[name] or {}
    local creditLeft = credit
    for _, line in ipairs(lines) do
      local c = math.min(creditLeft, line.price or 0)
      creditLeft = creditLeft - c
      paid[#paid + 1] = { key = line.key, price = line.price, label = line.label, credit = c, tokens = (line.price or 0) - c }
    end
    st.paid[name] = paid
    st.stats.sold = st.stats.sold + #lines
    if tokens > 0 then st.payment = { id = id, name = name, tokens = tokens } end
    self:save("pay-begin")
    self:bookPending()
  end
  local tabCredit, tabLines = credit, (total > 0 and lines or nil)
  credit = credit + creditAgainstDebt(self, name)
  local moved, left, err = self:collect(name)
  -- Paid without a PAY tap (as taken, on a tap, at check-out) and the server took nothing: the lines go back on the tab
  -- as they were, credit and all, rather than sitting as tokens owed. One save puts them back and writes the tokens down
  -- as a refund against the payment just booked (once, tag gs-ref-<id>), so a reboot anywhere here changes nothing owed.
  if opts.auto and tabLines and payTokens > 0 and moved == 0 and not st.payment then
    local mine = st.paid[name] or {}
    local tokensBack = 0
    for _ = 1, #tabLines do
      local line = table.remove(mine)
      if line then tokensBack = tokensBack + (line.tokens or 0) end
    end
    st.paid[name] = #mine > 0 and mine or nil
    local tab = st.tabs[name] or {}
    for i, line in ipairs(tabLines) do table.insert(tab, i, line) end
    st.tabs[name] = tab
    if tabCredit > 0 then
      st.credit[name] = (st.credit[name] or 0) + tabCredit * rules.MILLI
      st.stats.creditSpent = st.stats.creditSpent - tabCredit
      credit = credit - tabCredit
    end
    st.stats.sold = math.max(0, st.stats.sold - #tabLines)
    if tokensBack > 0 then st.refunds[#st.refunds + 1] = { id = self:nextId(), name = name, tokens = tokensBack } end
    self:save("pay-undone")
    self:bookPending()
    left = self:owes(name)
  end
  local paidOut = 0
  if journal.owedTo(name) > 0 then paidOut = self:settle(name) end
  if opts.quiet then
    if moved > 0 or credit > 0 then
      local parts = {}
      if credit > 0 then parts[#parts + 1] = credit .. " credit" end
      if moved > 0 then parts[#parts + 1] = tokensText(moved) end
      self:note(monitor, name .. " paid " .. table.concat(parts, " and ") .. (left > 0 and (", owes " .. left) or "") .. ".")
    end
    return moved, left, err
  end
  local parts = {}
  if credit > 0 then parts[#parts + 1] = credit .. " from store credit" end
  if moved > 0 then parts[#parts + 1] = tokensText(moved) end
  local text
  if #parts > 0 then
    text = name .. " paid " .. table.concat(parts, " and ") .. "."
  elseif paidOut > 0 then
    text = name .. " was paid " .. tokensText(paidOut) .. "."
  elseif left == 0 then
    text = name .. ": nothing to pay."
  else
    text = name .. ":"
  end
  if left > 0 then
    if needsApproval(err) then
      -- once asked, the click is waited for (approvals) and the payment goes through without another tap
      if self:askApproval(name) or self.awaiting[name] then
        text = text .. " Still owes " .. left .. ". Click APPROVE in chat and it is paid."
      else
        text = text .. " Still owes " .. left .. ". Click APPROVE in chat, then tap PAY again."
      end
    elseif tostring(err):find("insufficient", 1, true) then
      text = text .. " Still owes " .. left .. ": not enough tokens. It stays on the tab."
    else
      text = text .. " Still owes " .. left .. " (" .. tostring(err) .. "). It stays on the tab."
    end
  end
  self:note(monitor, text, 15000)
  return moved, left, err
end

--- Charge what a player owes now, without a PAY tap: after a take (quiet), on any tap of a shop screen, and when they
-- are checked out. vhcctweaks takes it if they approved this computer (an older build also wants a touch in the last
-- interactionStaleSeconds); if it will not, it stays owed and the next try collects it. Never asks anything new: an
-- unapproved player at the computer is only shown the one-time APPROVE, as before.
function Shop:autoPay(name, monitor, quiet)
  if quiet == nil then quiet = true end
  if self.inPay or not self.ready or not name or self.cfg.chargeAsTaken == false then return 0, 0 end
  if self:owes(name) <= 0 and not (self.state.tabs[name] and #self.state.tabs[name] > 0) then return 0, 0 end
  -- no economy (a server without ccvault, or it is down): the tab stays a tab
  if not wallet.available() then return 0, 0 end
  self.inPay = true
  local ok, moved, left, err = pcall(self.pay, self, name, monitor, { quiet = quiet, auto = true })
  self.inPay = false
  if not ok then error(moved, 0) end
  return moved, left, err
end

--- A tap on any shop screen by a player who owes something pays it first, before what the tap asked for.
function Shop:collectOnTap(name, monitor)
  if not name or not self.ready or self:owes(name) <= 0 then return end
  self:autoPay(name, monitor, false)
end

-- ---------------------------------------------------------------- display chest buttons

function Shop:stationAction(d, name, action, value)
  local ds = self:ds(d)
  if not name then
    self:note(d.monitor, "Could not tell who tapped. Tap again.")
    return
  end
  self:seen(name, d.monitor)
  -- PAY is on every station: whoever taps it pays their own tab, at anyone's station
  if action == "pay" then
    self:pay(name, d.monitor)
    return
  end
  local shopper = self.state.shoppers[name]
  if isFree(self, d) then
    if not self.ready then return end
    if not shopper then
      -- a tap on a free station checks the player in: there is no need to go to the door first
      if not self:checkIn(name, d.monitor) then return end
      shopper = self.state.shoppers[name]
      if not shopper then return end
    end
    local bracket = rules.bracket(shopper.level)
    local pick
    if d.gearType then
      -- a station of one type: that type at their bracket, or the nearest bracket that has some
      local t = rules.typeCounts(self.stock:summary(), d.gearType)
      local b = t and rules.nearestBracket(t.brackets, bracket)
      if not b then
        self:note(d.monitor, "No " .. rules.typePlural(d.gearType) .. " in stock right now.")
        return
      end
      pick = { type = d.gearType, bracket = b }
    else
      local types = self:typesFor(d, bracket)
      if #types == 0 then
        self:note(d.monitor, "Nothing in stock.")
        return
      end
      -- a type none of their other chests is showing, if there is one
      local showing = {}
      for _, other in ipairs(self.stations) do
        local theirs = self:ds(other)
        if theirs.shopper == name and theirs.type then showing[theirs.type] = true end
      end
      pick = types[1]
      for _, t in ipairs(types) do
        if not showing[t.type] then
          pick = t
          break
        end
      end
    end
    -- one more than they may hold: the one they used longest ago is given back first
    local most = self.cfg.stationsPerShopper or 0
    if most > 0 then
      local mine = self:held(name)
      local i = 1
      while #mine - (i - 1) >= most and mine[i] do
        local old = mine[i]
        if self:release(old) then
          self:note(old.monitor, "Free again: " .. name .. " opened station " .. d.id .. ".")
        end
        i = i + 1
      end
    end
    self:open(d, name, pick.type, pick.bracket, 1)
    return
  end
  if ds.shopper ~= name then
    if ds.shopper and self.state.shoppers[ds.shopper] then
      self:note(d.monitor, "In use by " .. ds.shopper .. "." .. self:freeSoon(d))
    else
      self:note(d.monitor, "Putting gear away. Tap again in a moment.")
    end
    return
  end
  ds.used = now()
  -- what was taken from the page on show is charged (each piece its own price) before the pick changes
  if ds.phase == "open" and not self:reconcile(d) then
    self:note(d.monitor, "This chest is not answering. Try again in a moment.")
    return
  end
  if action == "level" and type(value) == "number" and d.gearType then
    -- a station of one type steps to the next level that has some of it
    local t = rules.typeCounts(self.stock:summary(), d.gearType)
    local b = t and nextBracket(t.brackets, ds.bracket or 0, value < 0 and -1 or 1)
    if not b then
      self:note(d.monitor, "No " .. (value < 0 and "lower" or "higher") .. " level in stock.")
      return
    end
    ds.bracket, ds.page = b, 1
    self:fill(d)
  elseif action == "type" and d.gearType then
    return
  elseif action == "type" and type(value) == "string" and rules.inCategory(value, d.category, self.cfg) then
    local t = self.stock:summary().types[value]
    ds.type, ds.page = value, 1
    if t and (t.brackets[ds.bracket] or 0) == 0 then
      ds.bracket = rules.nearestBracket(t.brackets, ds.bracket) or ds.bracket
    end
    self:fill(d)
  elseif action == "level" and type(value) == "number" then
    ds.bracket = math.max(0, math.min(10, (ds.bracket or 0) + value))
    ds.page = 1
    self:fill(d)
  elseif action == "next" then
    ds.page = (ds.page or 1) + 1
    self:fill(d)
  elseif action == "done" then
    self:release(d)
  end
end

--- The search kiosk: FIND brings what matches to the pickup chest, NEXT the next chestful, DONE sends it back.
function Shop:kioskAction(name, action, query)
  local d = self.kiosk
  if not d then return end
  local ds = self:ds(d)
  if not name then
    self:note(d.monitor, "Could not tell who tapped. Tap again.")
    return
  end
  self:seen(name, d.monitor)
  if not self.state.shoppers[name] and not self:checkIn(name, d.monitor) then return end
  if not isFree(self, d) and ds.shopper ~= name then
    self:note(d.monitor, "In use by " .. tostring(ds.shopper) .. "." .. self:freeSoon(d))
    return
  end
  -- a tap by its shopper keeps the kiosk theirs (it frees itself like a station, freeStations)
  if ds.shopper == name then ds.used = now() end
  if action == "find" then
    if not isFree(self, d) and ds.shopper ~= name then return end
    ds.shopper, ds.page, ds.used = name, 1, now()
    -- the whole search, as the kiosk screen built it (a copy: the screen goes on changing its own)
    query = query or {}
    local stats = {}
    for i, s in ipairs(query.stats or {}) do stats[i] = { a = s.a, min = s.min } end
    ds.query = { type = query.type, lo = query.lo, hi = query.hi, rarity = query.rarity, legendary = query.legendary,
      minGs = query.minGs, stats = stats, sort = query.sort }
    if self:fill(d) then
      self:note(d.monitor, (ds.total or 0) .. " found, best first. Take what you want from the chest.")
    end
  elseif action == "improve" then
    if not isFree(self, d) and ds.shopper ~= name then return end
    local found, why = self:improvements(name, query and query.slot or "any")
    if not found then
      self:note(d.monitor, why)
      return
    end
    if #found == 0 then
      self:note(d.monitor, "Nothing in stock beats what you wear there.")
      return
    end
    local keys = {}
    for i, c in ipairs(found) do keys[i] = c.key end
    ds.shopper, ds.page, ds.used = name, 1, now()
    ds.query = { keys = keys, slot = query and query.slot or "any" }
    if self:fill(d) then
      self:note(d.monitor, (ds.total or 0) .. " better than yours, best first. Take what you want from the chest.")
    end
  elseif action == "next" and ds.shopper == name then
    ds.page = (ds.page or 1) + 1
    self:fill(d)
  elseif action == "done" and ds.shopper == name then
    self:release(d)
  end
end

-- ---------------------------------------------------------------- IMPROVEMENTS

local WORN_MS = 60000
local WORN_SLOTS = { head = "head", chest = "chest", legs = "legs", feet = "feet", mainhand = "weapon", offhand = "offhand" }

--- What a shopper wears, as Gear Score per slot, and their vault level. Read once a minute at most (two main-thread
-- calls). Returns { level, worn = { slot = gearScore } }, or nil and what to tell them.
function Shop:wornBy(name)
  self.wornCache = self.wornCache or {}
  local cached = self.wornCache[name]
  if cached and now() - cached.at < WORN_MS then return cached end
  if not ccvault or type(ccvault.getPlayerEquipment) ~= "function" then return nil, "This server cannot read your gear." end
  local ok, eq, why = economy.call(ccvault.getPlayerEquipment, name)
  if not ok then return nil, "Could not read your gear: " .. tostring(eq) end
  if type(eq) ~= "table" then return nil, (tostring(why):find("offline", 1, true) and "Stand at the kiosk while you are online."
    or ("Could not read your gear: " .. tostring(why))) end
  local level = self:vaultLevel(name) or (self.state.shoppers[name] or {}).level or self.cfg.defaultLevel
  local worn = {}
  for field, slot in pairs(WORN_SLOTS) do
    local item = eq[field]
    local vd = type(item) == "table" and type(item.vaultData) == "table" and item.vaultData
    if vd and type(vd.gearScore) == "number" then worn[slot] = vd.gearScore end
  end
  -- a magnet is worn as a curio
  for _, items in pairs(type(eq.curios) == "table" and eq.curios or {}) do
    for _, item in pairs(items) do
      local vd = type(item) == "table" and item.name == "the_vault:magnet" and type(item.vaultData) == "table" and item.vaultData
      if vd and type(vd.gearScore) == "number" then worn.magnet = math.max(worn.magnet or 0, vd.gearScore) end
    end
  end
  cached = { at = now(), level = level, worn = worn }
  self.wornCache[name] = cached
  return cached
end

--- The pieces in stock that beat what a shopper wears (rules.improvements), and the count for every slot.
function Shop:improvements(name, slot)
  local me, why = self:wornBy(name)
  if not me then return nil, why end
  local found, counts = rules.improvements(self.stock:pieces(), me.worn, me.level, slot, self.cfg)
  self.improveCounts = self.improveCounts or {}
  self.improveCounts[name] = { at = now(), counts = counts, level = me.level }
  self:changed()
  return found, counts
end

-- ---------------------------------------------------------------- buying from players

--- Who is at the sell point: the nearest player online within 8 blocks of it, through any detector. nil when the sell
-- point has no recorded place or nobody is near it.
function Shop:atSell()
  local sell = self.setup.sell
  if not (sell and sell.pos) then return nil end
  local names
  for _, detector in ipairs(self:detectors()) do
    local ok, list = self.io.call(detector, "getOnlinePlayers")
    if ok and type(list) == "table" then
      names = list
      break
    end
  end
  local best, bestDistance
  for _, name in ipairs(names or {}) do
    if type(name) == "string" then
      local pos = self:playerPos(name)
      local distance = pos and rules.distance(pos, sell.pos)
      if distance and distance <= 8 and (not bestDistance or distance < bestDistance) then best, bestDistance = name, distance end
    end
  end
  return best
end

--- Move refused gear from one chest to another: to the returns chest when the shop will not buy it, to the junk chest
-- when its owner gives it away. The move is written down before anything moves, so after a reboot finishMove ends it:
-- what is still in the first chest goes on, and the record of who left what is written with the end of the move.
function Shop:beginMove(kind, from, to, slots, by)
  local keys, any = {}, false
  for _, key in pairs(slots) do
    keys[key] = (keys[key] or 0) + 1
    any = true
  end
  if not any then return true end
  self.state.moving = { kind = kind, from = from, to = to, keys = keys, by = by }
  self:save(kind .. "-begin")
  return self:finishMove()
end

local function countKeys(list)
  local out = {}
  for _, item in pairs(list) do
    local key = rules.key(item)
    out[key] = (out[key] or 0) + 1
  end
  return out
end

function Shop:finishMove()
  local mv = self.state.moving
  if not mv then return true end
  local ok, list = self.io.call(mv.from, "list")
  if not ok or type(list) ~= "table" then return false end
  local moves, picked = {}, {}
  for slot, item in pairs(list) do
    local key = rules.key(item)
    if (picked[key] or 0) < (mv.keys[key] or 0) then
      picked[key] = (picked[key] or 0) + 1
      moves[#moves + 1] = { fromSlot = slot, to = mv.to }
    end
  end
  if #moves > 0 then
    local _, err = self.stock:batch(mv.from, moves)
    if err then store.log(mv.kind .. " from " .. tostring(mv.from) .. ": " .. err) end
  end
  ok, list = self.io.call(mv.from, "list")
  if not ok or type(list) ~= "table" then return false end
  -- a piece no longer in the first chest went (now, or before a reboot); one still there did not fit
  local still, went, stuck = countKeys(list), 0, 0
  for key, n in pairs(mv.keys) do
    local left = math.min(n, still[key] or 0)
    stuck = stuck + left
    if left < n then
      went = went + (n - left)
      if mv.kind == "refuse" then
        self.state.returnsBy[key] = mv.by or "?"
      else
        self.state.returnsBy[key] = nil
      end
    end
  end
  if mv.kind == "donate" then self.state.stats.donated = (self.state.stats.donated or 0) + went end
  self.state.moving = nil
  self:save(mv.kind .. "-done")
  if stuck > 0 then
    self.trouble = "The " .. (mv.kind == "refuse" and "returns" or "junk") .. " chest has no room for " .. stuck .. " pieces"
  end
  return true, went
end

--- The sell screen's list of what happened to the last batch, one entry a piece: { label, level, grade, ok, why }. Pieces
-- that come within half a minute of each other, from the same seller, are one batch. Shown only, never saved.
local BATCH_MS = 30000
function Shop:addToBatch(by, items)
  local b = self.lastBatch
  if not b or now() - b.at > BATCH_MS or (by and b.by and b.by ~= by) then
    b = { items = {} }
    self.lastBatch = b
  end
  b.at, b.by = now(), by or b.by
  for _, item in ipairs(items) do b.items[#b.items + 1] = item end
  self:changed()
end

--- Refused gear in the sell chest goes to the returns chest at once, if there is one. Its reasons stay on the sell screen.
function Shop:refuse(view)
  local returns = self.setup.returns
  if not (returns and returns.chest) or #view.rejected == 0 or self.state.sale or self.state.moving then return false end
  local slots = {}
  for _, entry in ipairs(view.rejected) do slots[entry.slot] = entry.key end
  local by = self:atSell()
  local done = self:beginMove("refuse", self.setup.sell.chest, returns.chest, slots, by)
  if done then
    self.refused = { entries = view.rejected, by = by, at = now() }
    local items = {}
    for _, e in ipairs(view.rejected) do
      items[#items + 1] = { label = e.label, level = e.level, grade = e.grade, ok = false, why = e.why }
    end
    self:addToBatch(by, items)
  end
  return done
end

--- DONATE: the tapper gives their refused gear to the shop for nothing. It goes to the junk chest, never into stock:
-- from the returns chest what was left by them (or by nobody anyone saw), or with no returns chest what the sell chest refused.
function Shop:donate(name, monitor)
  local junk, sell, returns = self.setup.junk, self.setup.sell, self.setup.returns
  if not (junk and junk.chest) or not (sell and sell.chest) then return end
  if not name then
    self:note(monitor, "Could not tell who tapped. Tap again.")
    return
  end
  self:seen(name, monitor)
  if self.state.moving and not self:finishMove() then
    self:note(monitor, "Still moving gear. Try again in a moment.")
    return
  end
  local from, slots = nil, {}
  if returns and returns.chest then
    from = returns.chest
    local ok, list = self.io.call(from, "list")
    if not ok or type(list) ~= "table" then
      self:note(monitor, "The returns chest is not answering.")
      return
    end
    for slot, item in pairs(list) do
      local key = rules.key(item)
      local by = self.state.returnsBy[key]
      if by == name or by == nil or by == "?" then slots[slot] = key end
    end
  else
    from = sell.chest
    self:sellScan()
    for _, entry in ipairs(self.sellView and self.sellView.rejected or {}) do slots[entry.slot] = entry.key end
  end
  if not next(slots) then
    self:note(monitor, "No refused gear of " .. name .. "'s to give.")
    return
  end
  local _, went = self:beginMove("donate", from, junk.chest, slots, name)
  self.refused = nil
  self:note(monitor, "Thank you, " .. name .. ": " .. tostring(went or 0) .. " given to the shop.", 12000)
  self:sellScan()
end

--- Forget who left a piece in the returns chest once it has been taken out.
function Shop:pruneReturns()
  local returns = self.setup.returns
  if not (returns and returns.chest) or self.state.moving or not next(self.state.returnsBy) then return end
  local ok, list = self.io.call(returns.chest, "list")
  if not ok or type(list) ~= "table" then return end
  local present, changed = countKeys(list), false
  for key in pairs(self.state.returnsBy) do
    if not present[key] then
      self.state.returnsBy[key] = nil
      changed = true
    end
  end
  if changed then
    self:save("returns-taken")
    self:changed()
  end
end

--- Look at the sell chest and work out the offer.
function Shop:sellScan(again)
  local sell = self.setup.sell
  if not sell or not sell.chest then return end
  local ok, details = self.io.call(sell.chest, "listDetailed")
  if not ok or type(details) ~= "table" then
    self.sellView = nil
    self:changed()
    return
  end
  self.stock:learn(details)
  local view = { accepted = {}, rejected = {}, returns = {} }
  for slot, detail in pairs(details) do
    local key = rules.key(detail)
    local piece = self.stock.known[key]
    if self:tabbed(key) or self:paidFor(key) then
      view.returns[#view.returns + 1] = { slot = slot, key = key, label = piece.label }
    else
      local yes, why = rules.accepts(piece, self.cfg)
      if yes then
        view.accepted[#view.accepted + 1] = { slot = slot, key = key, label = piece.label, level = piece.level, grade = rules.grade(piece) }
      else
        view.rejected[#view.rejected + 1] = { slot = slot, key = key, label = piece.label, why = why,
          level = piece.level, grade = piece.kind and not piece.unidentified and rules.grade(piece) or nil }
      end
    end
  end
  -- refused gear goes to the returns chest straight away; the chest is then looked at again
  if not again and self:refuse(view) then return self:sellScan(true) end
  view.returnsChest = self.setup.returns and self.setup.returns.chest ~= nil
  self.sellView = view
  self:changed()
end

--- Whether the owner can pay this many tokens and stay at or above the floor.
function Shop:canPay(name, tokens)
  if tokens <= 0 or name == hostName() then return true end
  return rules.payable(tokens, wallet.hostBalance(), self.cfg.ownerFloor) >= tokens
end

function Shop:sell(name, mode, monitor)
  local sell = self.setup.sell
  if not sell or not sell.chest then return end
  if not name then
    self:note(monitor, "Could not tell who tapped. Tap again.")
    return
  end
  self:seen(name, monitor)
  -- with sellForTokens off every sale is store credit, whatever button (or old screen) the tap came from
  mode = rules.saleMode(mode, self.cfg)
  if not self.ready then
    self:note(monitor, "The shop is still counting its stock.")
    return
  end
  if self.state.sale and not self:finishSale() then
    self:note(monitor, "An earlier sale is still being put away. Try again in a moment.")
    return
  end
  -- anything still owed from an earlier sale goes first: this tap is the seller being here
  local paidOld = 0
  if journal.owedTo(name) > 0 then paidOld = self:settle(name) end
  if mode == "tokens" then self:askApproval(name) end
  self:sellScan()
  local view = self.sellView
  if not view then
    self:note(monitor, "The sell chest is not answering.")
    return
  end
  local count = #view.accepted
  if count == 0 and #view.returns == 0 then
    self:note(monitor, paidOld > 0 and (name .. " was paid " .. tokensText(paidOld) .. " from before.") or "Nothing in the chest that the shop buys.")
    return
  end
  if mode == "tokens" and count > 0 then
    local tokens = rules.settleSale(self.state.carry[name], count, self.cfg)
    if not self:canPay(name, tokens) then
      self:note(monitor, "The shop cannot pay tokens right now. STORE CREDIT still works.", 12000)
      return
    end
  end
  local sale = { id = self:nextId(), seller = name, mode = mode, keys = {}, returns = {}, phase = "moving" }
  local slots = {}
  for _, entry in ipairs(view.accepted) do
    sale.keys[entry.key] = (sale.keys[entry.key] or 0) + 1
    slots[entry.slot] = entry.key
  end
  for _, entry in ipairs(view.returns) do
    sale.returns[entry.key] = (sale.returns[entry.key] or 0) + 1
    slots[entry.slot] = entry.key
  end
  self.state.sale = sale
  self:save("sale-begin")
  local _, movedKeys = self.stock:put(sell.chest, slots)
  self:finishSale(movedKeys, monitor)
end

--- Close a sale: count what reached the vault and pay for it. With no count given (after a reboot) the chests say.
-- A sale is paid the way it was begun: one begun for tokens before sellForTokens was turned off is still paid in tokens.
function Shop:finishSale(movedKeys, monitor)
  local st = self.state
  local sale = st.sale
  if not sale then return true end
  local sell = self.setup.sell
  monitor = monitor or (sell and sell.monitor)
  if not movedKeys then
    local ok, list = self.stock:listKnown(sell.chest)
    if not ok or type(list) ~= "table" then return false end
    -- what is still in the chest goes on to the vault first
    local slots, left = {}, {}
    for slot, item in pairs(list) do
      local key = rules.key(item)
      local wanted = (sale.keys[key] or 0) + (sale.returns[key] or 0)
      if (left[key] or 0) < wanted then
        left[key] = (left[key] or 0) + 1
        slots[slot] = key
      end
    end
    local _, went = self.stock:put(sell.chest, slots)
    movedKeys = {}
    local function settle(key, wanted)
      if movedKeys[key] then return end
      local stayed = (left[key] or 0) - (went[key] or 0)
      movedKeys[key] = math.max(0, math.min(wanted - stayed, self.stock:count(key)))
    end
    for key, n in pairs(sale.keys) do settle(key, n + (sale.returns[key] or 0)) end
    for key, n in pairs(sale.returns) do settle(key, n + (sale.keys[key] or 0)) end
  end
  local left = {}
  for key, n in pairs(movedKeys) do left[key] = n end
  local back, refunded = 0, {}
  for key, n in pairs(sale.returns) do
    for _ = 1, math.min(n, left[key] or 0) do
      -- a piece off a tab (or paid for this visit: refunded) that was handed in here is a piece put back, not a sale.
      -- The refund is written in the sale-booked save below, with the rest of the sale.
      left[key] = left[key] - 1
      if self:untab(key) or self:unpay(key, refunded) then back = back + 1 end
    end
  end
  local count = 0
  local bought = {}
  local each = sale.mode == "credit" and ("+" .. rules.showMilli(rules.creditMilli(1, self.cfg)) .. " credit")
    or ("+" .. rules.showMilli(rules.pieceMilli(self.cfg)) .. " tok")
  for key, n in pairs(sale.keys) do
    local got = math.min(n, left[key] or 0)
    count = count + got
    local piece = self.stock.known[key]
    for _ = 1, got do
      bought[#bought + 1] = { label = piece and piece.label or "Gear", level = piece and piece.level,
        grade = piece and rules.grade(piece), ok = true, why = each }
    end
  end
  local text
  if sale.mode == "credit" then
    local milli = rules.creditMilli(count, self.cfg)
    if milli > 0 then st.credit[sale.seller] = (st.credit[sale.seller] or 0) + milli end
    st.stats.creditGiven = st.stats.creditGiven + milli
    text = sale.seller .. " sold " .. count .. " for " .. rules.showMilli(milli) .. " store credit."
  else
    local tokens, carry = rules.settleSale(st.carry[sale.seller], count, self.cfg)
    st.carry[sale.seller] = carry > 0 and carry or nil
    if tokens > 0 then st.payout = { id = sale.id, name = sale.seller, tokens = tokens } end
    text = sale.seller .. " sold " .. count .. " for " .. tokensText(tokens)
      .. (carry > 0 and (" (" .. rules.showMilli(carry) .. " carried over)") or "") .. "."
  end
  if back > 0 then text = text .. " " .. back .. " put back." end
  st.stats.bought = st.stats.bought + count
  st.sale = nil
  self:save("sale-booked")
  if #bought > 0 then self:addToBatch(sale.seller, bought) end
  refunded[sale.seller] = nil   -- the seller is settled just below
  if next(refunded) then self:settleRefunds(refunded) end
  local moved, why = self:settle(sale.seller)
  local owed = journal.owedTo(sale.seller)
  if sale.mode ~= "credit" and owed > 0 then
    text = text .. " " .. owed .. " still to come"
      .. (why == "floor" and ": the shop is short." or (self.awaiting[sale.seller] and ": click APPROVE in chat." or ": paid when you are next here."))
  end
  self:note(monitor, text, 15000)
  self:sellScan()
  return true, moved
end

--- Whatever the owner drops in the intake chest goes into the vault.
function Shop:intake()
  local intake = self.setup.intake
  if not intake or not intake.chest then return end
  local ok, list = self.stock:listKnown(intake.chest)
  if not ok or type(list) ~= "table" then return end
  local slots = {}
  for slot, item in pairs(list) do slots[slot] = rules.key(item) end
  if next(slots) then
    local _, _, stuck = self.stock:put(intake.chest, slots)
    if stuck > 0 then self.trouble = "The vault has no room for " .. stuck .. " pieces from the intake chest" end
  end
  self:changed()
end

-- ---------------------------------------------------------------- start and upkeep

--- Read the vault, then finish whatever was under way when the computer last stopped.
function Shop:boot(progress)
  local started = now()
  self.status = "Linking"
  self:changed()
  -- a node whose chunk loads a moment after this one is waited for, so the shop does not open without its chests
  local tries = 0
  while not self:link() and tries < 20 do
    tries = tries + 1
    self.status = "Waiting for " .. tostring(self.linkTrouble)
    self:changed()
    sleep(1)
  end
  self:discover()
  local linkedAt = now()
  self.status = "Counting stock"
  self:changed()
  self.stock:indexAll(function(done, total)
    self.status = "Counting stock " .. done .. "/" .. total
    self:changed()
    if progress then progress(done, total) end
  end)
  local countedAt = now()
  self:watchAll()
  self.status = "Recovering"
  self:bookPending()
  self:resolve()
  if self.state.sale then self:finishSale() end
  if self.state.moving then self:finishMove() end
  for _, d in ipairs(self.all) do self:mend(d) end
  self:sellScan()
  self:intake()
  self.ready = true
  self.status = "Open"
  self:changed()
  store.log(("open: %d pieces in %d chests; linking %.1fs, counting %.1fs, the rest %.1fs"):format(
    self.stock:summary().total, #self.stock.order, (linkedAt - started) / 1000, (countedAt - linkedAt) / 1000, (now() - countedAt) / 1000))
end

local function due(self, what, seconds)
  self.last = self.last or {}
  local at = os.clock()
  if at - (self.last[what] or -math.huge) >= seconds then
    self.last[what] = at
    return true
  end
  return false
end

--- A player who has just clicked APPROVE gets what was waiting for it: their payout, or their payment.
function Shop:approvals()
  for name, till in pairs(self.awaiting) do
    if now() > till then
      self.awaiting[name] = nil
    elseif wallet.livePlayer() == name and wallet.isApproved() then
      self.awaiting[name] = nil
      self:resolve(name)
      local owed = journal.owedTo(name)
      -- told on the screen they last tapped (a shop with no door has no other place to say it)
      local at = self.tappedAt[name]
      if owed > 0 then
        local moved = self:settle(name)
        if moved > 0 then self:note(at or (self.setup.sell and self.setup.sell.monitor), name .. " was paid " .. tokensText(moved) .. ".") end
      elseif owed < 0 then
        local moved, left = self:collect(name)
        if moved > 0 then
          self:note(at or (self.setup.door and self.setup.door.monitor),
            name .. " paid " .. tokensText(moved) .. "." .. (left > 0 and (" Still owes " .. left .. ".") or ""))
        end
      end
    end
  end
end

--- Whether a chest holds something else than at the last look here. A chest that cannot be read has not changed.
function Shop:differs(name)
  local ok, list = self.io.call(name, "list")
  if not ok or type(list) ~= "table" then return false end
  local parts = {}
  for slot, item in pairs(list) do parts[#parts + 1] = slot .. ":" .. rules.key(item) .. "x" .. tostring(item.count) end
  table.sort(parts)
  local print_ = table.concat(parts, ",")
  self.prints = self.prints or {}
  local was = self.prints[name]
  self.prints[name] = print_
  -- the first look only counts when there is something in the chest
  if was == nil then return print_ ~= "" end
  return was ~= print_
end

--- The slow jobs, a little at a time.
function Shop:upkeep()
  if not self.ready then return end
  if next(self.awaiting) then self:approvals() end
  if due(self, "poll", self.cfg.stationPollSeconds) then
    for _, d in ipairs(self.all) do
      if self:ds(d).phase == "open" then self:reconcile(d) end
    end
    -- The sell and intake chests are looked at as well, watched or not: a watch on a double chest only tells of the half
    -- that touches the computer, so gear put in the other half would sit there unseen. A plain list is cheap, and the
    -- chest is only read in detail when it is not what it was.
    local sell, intake = self.setup.sell, self.setup.intake
    if sell and sell.chest and self:differs(sell.chest) then self:sellScan() end
    if intake and intake.chest and self:differs(intake.chest) then self:intake() end
    if due(self, "returns", 30) then self:pruneReturns() end
  end
  if due(self, "rescan", self.cfg.rescanSeconds) then
    local name = self.stock:nextTurn(self.watched)
    if name then
      local chest = self.stock.chests[name]
      if chest.indexed or self.io.isPresent(name) then
        self.stock:index(name)
        self:watch(name)
      end
    end
  end
  if self.linkTrouble and due(self, "link", 2) then self:link() end
  if due(self, "presence", self.cfg.presenceSeconds) then self:presence() end
  if due(self, "free", 60) then
    -- a chest nobody has open is never left holding anything, even if its change event was missed
    for _, d in ipairs(self.all) do
      if not self:ds(d).phase then self:reconcile(d) end
    end
  end
  if due(self, "mend", 10) then
    self:link()
    self:discover()
    self:bookPending()
    -- a refund booked but not yet paid (a reboot came between): a shopper still here gets it, no touch needed
    for name in pairs(self.state.shoppers) do
      if journal.owedTo(name) > 0 then self:settle(name) end
    end
    if self.state.sale then self:finishSale() end
    if self.state.moving then self:finishMove() end
    for _, d in ipairs(self.all) do
      local ds = self:ds(d)
      local stale = ds.shopper and not self.state.shoppers[ds.shopper]
      if ds.phase == "filling" or ds.phase == "sweeping" or stale or (ds.shopper and not ds.phase) then self:mend(d) end
    end
    if not next(self.state.shoppers) then
      -- nobody is in: nothing stays on display
      for _, d in ipairs(self.all) do
        if self:ds(d).phase then self:mend(d) end
      end
    end
  end
end

return M
