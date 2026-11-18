-- gearshop/stock.lua
-- The vault: which chest and slot every piece is in, and the only code that moves pieces in or out of it.
--
-- The chests themselves are the truth. This index is rebuilt from them on every boot (listDetailed, one call a chest) and
-- kept current afterwards: by the shop's own moves, by inventory_changed for the chests it can watch, and by looking at the
-- others in turn. What a piece is (type, level, rarity, modifiers) is remembered by its key, so a piece that comes back from
-- a display chest is never read in detail twice: a plain list() says which slot it landed in.
--
-- Moves go through moveMany. The server stops a batch when its time for the tick is spent and says how far it got, so every
-- batch here is sent again from where it stopped until it is done.
--
-- io.call(name, method, ...) returns ok, result and never throws: a chest on a computer that has unloaded just fails.

local rules = require("lib.gearshop.rules")

local M = {}
local Stock = {}
Stock.__index = Stock

function M.new(io, cfg, log)
  return setmetatable({
    io = io, cfg = cfg, log = log or function() end,
    chests = {},   -- name -> { name, size, slots = { slot = key }, used, indexed, cat }
    order = {},    -- chest names, sorted
    known = {},    -- key -> piece (rules.piece)
    homes = {},    -- key -> the chest a piece on display came from
    turn = 0,      -- whose turn it is to be looked at
    summaryCache = nil,
  }, Stock)
end

local function natural(a, b)
  local an, bn = tonumber(a:match("(%d+)$")), tonumber(b:match("(%d+)$"))
  local ap, bp = a:gsub("%d+$", ""), b:gsub("%d+$", "")
  if ap == bp and an and bn then return an < bn end
  return a < b
end

function Stock:add(name)
  if self.chests[name] then return self.chests[name] end
  local chest = { name = name, slots = {}, used = 0, indexed = false }
  self.chests[name] = chest
  self.order[#self.order + 1] = name
  table.sort(self.order, natural)
  return chest
end

function Stock:has(name)
  return self.chests[name] ~= nil
end

--- A chest whose computer unloaded: its pieces cannot be offered until it is back and read again.
function Stock:lose(name)
  local chest = self.chests[name]
  if chest then
    chest.indexed = false
    self.summaryCache = nil
  end
end

--- Remember what these items are. details: { slot = detail }, as listDetailed gives.
function Stock:learn(details)
  for _, detail in pairs(details) do
    local key = type(detail) == "table" and detail.name and rules.key(detail)
    if key and not self.known[key] then self.known[key] = rules.piece(detail) end
  end
end

--- list() of any inventory, with every item in it known afterwards. Returns ok, { slot = item }.
function Stock:listKnown(name)
  local ok, list = self.io.call(name, "list")
  if not ok or type(list) ~= "table" then return false, list end
  for _, item in pairs(list) do
    if not self.known[rules.key(item)] then
      local fine, details = self.io.call(name, "listDetailed")
      if not fine or type(details) ~= "table" then return false, details end
      self:learn(details)
      return true, details
    end
  end
  return true, list
end

local function categorise(self, chest)
  local counts, best, most = {}, nil, 0
  for _, key in pairs(chest.slots) do
    local piece = self.known[key]
    local kind = piece and piece.type or "?"
    counts[kind] = (counts[kind] or 0) + 1
    if counts[kind] > most then best, most = kind, counts[kind] end
  end
  chest.cat = best
end

--- Read one chest. The first read is in detail; after that only when it holds something not seen before.
function Stock:index(name)
  local chest = self.chests[name]
  if not chest then return false, "not a vault chest" end
  if not chest.size then
    local ok, size = self.io.call(name, "size")
    if not ok or type(size) ~= "number" then return false, size end
    chest.size = size
  end
  local ok, list
  if chest.indexed then
    ok, list = self:listKnown(name)
  else
    ok, list = self.io.call(name, "listDetailed")
    if ok and type(list) == "table" then self:learn(list) else ok = false end
  end
  if not ok then
    chest.indexed = false
    self.summaryCache = nil
    return false, list
  end
  local slots, used = {}, 0
  for slot, item in pairs(list) do
    slots[slot] = rules.key(item)
    used = used + 1
  end
  chest.slots, chest.used, chest.indexed = slots, used, true
  categorise(self, chest)
  self.summaryCache = nil
  return true
end

--- Read every chest. progress(done, total) is called as it goes.
function Stock:indexAll(progress)
  for i, name in ipairs(self.order) do
    self:index(name)
    if progress then progress(i, #self.order) end
  end
end

--- The next chest in turn among those `skip` does not name, for the slow look at chests that cannot be watched.
function Stock:nextTurn(skip)
  local n = #self.order
  for _ = 1, n do
    self.turn = self.turn % n + 1
    local name = self.order[self.turn]
    if not (skip and skip[name]) then return name end
  end
  return nil
end

-- ---------------------------------------------------------------- what is in stock

local function each(self, fn)
  for _, name in ipairs(self.order) do
    local chest = self.chests[name]
    if chest.indexed then
      for slot, key in pairs(chest.slots) do
        local piece = self.known[key]
        if piece then fn(piece, name, slot) end
      end
    end
  end
end

--- Counts for the pickers and the admin view: { total, forSale, types = { type = { total, brackets = { b = n } } }, typeList,
-- chests, slots, used, unread }.
function Stock:summary()
  if self.summaryCache then return self.summaryCache end
  local s = { total = 0, forSale = 0, types = {}, typeList = {}, chests = #self.order, slots = 0, used = 0, unread = 0 }
  for _, name in ipairs(self.order) do
    local chest = self.chests[name]
    if chest.indexed then
      s.slots, s.used = s.slots + (chest.size or 0), s.used + chest.used
    else
      s.unread = s.unread + 1
    end
  end
  each(self, function(piece)
    s.total = s.total + 1
    if rules.forSale(piece, self.cfg) then
      s.forSale = s.forSale + 1
      local t = s.types[piece.type]
      if not t then
        t = { type = piece.type, total = 0, brackets = {} }
        s.types[piece.type] = t
        s.typeList[#s.typeList + 1] = piece.type
      end
      local b = rules.bracket(piece.level)
      t.total = t.total + 1
      t.brackets[b] = (t.brackets[b] or 0) + 1
    end
  end)
  table.sort(s.typeList)
  self.summaryCache = s
  return s
end

--- Every type with stock, each at the bracket nearest the wanted one that has any: { { type, bracket, count }, ... }.
function Stock:typesNear(bracket)
  local out = {}
  local s = self:summary()
  for _, kind in ipairs(s.typeList) do
    local t = s.types[kind]
    local b = rules.nearestBracket(t.brackets, bracket)
    if b then out[#out + 1] = { type = kind, bracket = b, count = t.brackets[b] } end
  end
  return out
end

--- Pieces of one type (or its family: "the_vault:idol" is every idol) in one bracket, nearest the level first: { { chest, slot, key, level }, ... }.
function Stock:select(kind, bracket, level)
  local list = {}
  each(self, function(piece, chest, slot)
    if rules.ofType(piece.type, kind) and rules.bracket(piece.level) == bracket and rules.forSale(piece, self.cfg) then
      list[#list + 1] = { chest = chest, slot = slot, key = piece.key, level = piece.level }
    end
  end)
  return rules.order(list, level)
end

--- Pieces a search asked for, nearest the level first.
function Stock:search(query, level)
  local list = {}
  each(self, function(piece, chest, slot)
    if rules.forSale(piece, self.cfg) and rules.matches(piece, query) then
      list[#list + 1] = { chest = chest, slot = slot, key = piece.key, level = piece.level }
    end
  end)
  return rules.order(list, level)
end

--- How many slots of the vault hold this key.
function Stock:count(key)
  local n = 0
  each(self, function(piece)
    if piece.key == key then n = n + 1 end
  end)
  return n
end

-- ---------------------------------------------------------------- moving

--- moveMany, sent again from where the server stopped until every move has been tried.
-- @return moved table (one count per move, 0 for a move that did not happen), err string|nil
function Stock:batch(from, moves)
  local out, at, stalls, err = {}, 1, 0, nil
  local max = math.max(1, self.cfg.maxBatchMoves or 256)
  while at <= #moves do
    local part = {}
    for j = at, math.min(#moves, at + max - 1) do part[#part + 1] = moves[j] end
    local ok, result = self.io.call(from, "moveMany", part)
    if not ok or type(result) ~= "table" then
      err = tostring(result)
      break
    end
    local done = math.min(tonumber(result.done) or 0, #part)
    for j = 1, done do out[at + j - 1] = tonumber(type(result.moved) == "table" and result.moved[j]) or 0 end
    if done == 0 then
      stalls = stalls + 1
      if stalls >= 3 then
        err = "the server moved nothing"
        break
      end
    else
      stalls = 0
    end
    at = at + done
  end
  for i = 1, #moves do out[i] = out[i] or 0 end
  return out, err
end

--- Take pieces out of the vault into another inventory. entries: { { chest, slot, key }, ... }. Returns how many went.
function Stock:take(entries, to)
  local byChest, names = {}, {}
  for _, entry in ipairs(entries) do
    if not byChest[entry.chest] then
      byChest[entry.chest] = {}
      names[#names + 1] = entry.chest
    end
    table.insert(byChest[entry.chest], entry)
  end
  local count = 0
  for _, name in ipairs(names) do
    local chest, moves = self.chests[name], {}
    for i, entry in ipairs(byChest[name]) do moves[i] = { fromSlot = entry.slot, to = to } end
    local moved, err = self:batch(name, moves)
    for i, entry in ipairs(byChest[name]) do
      if moved[i] > 0 and chest.slots[entry.slot] == entry.key then
        chest.slots[entry.slot] = nil
        chest.used = chest.used - 1
        self.homes[entry.key] = name
        count = count + 1
      end
    end
    if err then
      self.log("taking from " .. name .. ": " .. err)
      self:index(name)
    end
  end
  self.summaryCache = nil
  return count
end

local function hasRoom(chest, planned, avoid)
  return chest.indexed and chest.size and not avoid[chest.name]
    and chest.used + (planned[chest.name] or 0) < chest.size
end

--- Where a piece goes: back where it came from, else a chest of its type, else an empty chest, else anywhere with room.
local function target(self, key, planned, avoid)
  local piece = self.known[key]
  local kind = piece and piece.type or "?"
  local home = self.homes[key] and self.chests[self.homes[key]]
  if home and hasRoom(home, planned, avoid) then return home end
  local empty, any
  for _, name in ipairs(self.order) do
    local chest = self.chests[name]
    if hasRoom(chest, planned, avoid) then
      local holds = chest.used + (planned[name] or 0)
      if chest.cat == kind and holds > 0 then return chest end
      if holds == 0 and not empty then empty = chest end
      any = any or chest
    end
  end
  if empty then
    empty.cat = kind
    return empty
  end
  return any
end

--- Put items from another inventory into the vault. slots: { slot = key }, every key already known (listKnown).
-- @return moved number, movedKeys { key = n }, stuck number (what could not be put anywhere)
function Stock:put(from, slots)
  local pending = {}
  for slot, key in pairs(slots) do pending[#pending + 1] = { slot = slot, key = key } end
  table.sort(pending, function(a, b) return a.slot < b.slot end)
  local total, movedKeys, touched, avoid = 0, {}, {}, {}
  for _ = 1, 6 do
    if #pending == 0 then break end
    local moves, sent, planned, rest = {}, {}, {}, {}
    for _, p in ipairs(pending) do
      local chest = target(self, p.key, planned, avoid)
      if chest then
        moves[#moves + 1] = { fromSlot = p.slot, to = chest.name }
        planned[chest.name] = (planned[chest.name] or 0) + 1
        p.to = chest
        sent[#sent + 1] = p
      else
        rest[#rest + 1] = p
      end
    end
    if #moves == 0 then break end
    local moved, err = self:batch(from, moves)
    for i, p in ipairs(sent) do
      if moved[i] > 0 then
        p.to.used = p.to.used + 1
        touched[p.to.name] = true
        movedKeys[p.key] = (movedKeys[p.key] or 0) + 1
        self.homes[p.key] = nil
        total = total + 1
      else
        avoid[p.to.name] = true
        rest[#rest + 1] = p
      end
    end
    pending = rest
    if err then
      self.log("putting from " .. from .. ": " .. err)
      break
    end
  end
  -- which slot each piece landed in
  for name in pairs(touched) do self:index(name) end
  self.summaryCache = nil
  return total, movedKeys, #pending
end

return M
