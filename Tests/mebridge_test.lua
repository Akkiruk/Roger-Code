-- mebridge_test.lua
-- Vault Gear and the Gear Locker against a fake me_bridge v2 (the shapes in the AP fork's SPEC.md 2.2 and 3.3).

local testing = require("testing")
local test, eq, truthy = testing.test, testing.eq, testing.truthy

table.unpack = table.unpack or unpack

-- a tiny ME: entries by id, export moves whole units into a chest table
local function fakeBridge(entries, details)
  local me = { calls = {}, chests = {} }
  local function sorted()
    local out = {}
    for _, e in pairs(entries) do if e.count > 0 then out[#out + 1] = e end end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
  end
  local function matches(f, e)
    if f.mod and not e.name:find(f.mod .. ":", 1, true) then return false end
    if f.name then
      local ok = false
      for _, n in ipairs(type(f.name) == "table" and f.name or { f.name }) do ok = ok or n == e.name end
      if not ok then return false end
    end
    if f.uuid and e.uuid ~= f.uuid then return false end
    if f.minCount and e.count < f.minCount then return false end
    return true
  end
  local function copy(e)
    return { id = e.id, type = "item", name = e.name, count = e.count, nbt = true, craftable = false, uuid = e.uuid,
      displayName = e.displayName }
  end
  me.list = function(filter, opts)
    filter, opts = filter or {}, opts or {}
    me.calls[#me.calls + 1] = "list"
    local items, last = {}, nil
    for _, e in ipairs(sorted()) do
      if (not opts.after or e.id > opts.after) and matches(filter, e) then
        if #items >= (opts.limit or 500) then return { items = items, next = last } end
        items[#items + 1] = copy(e)
        last = e.id
      end
    end
    return { items = items }
  end
  me.getDetail = function(id)
    me.calls[#me.calls + 1] = "getDetail"
    local e = entries[id]
    if not e or e.count < 1 then return nil, "NOT_FOUND" end
    return details[id]
  end
  me.getDetails = function(ids)
    me.calls[#me.calls + 1] = "getDetails"
    local out = {}
    for _, id in ipairs(ids) do
      if entries[id] and entries[id].count > 0 then out[id] = details[id] end
    end
    return out
  end
  me.export = function(what, to, opts)
    me.calls[#me.calls + 1] = "export"
    local chest = me.chests[to]
    if not chest then error("unknown target " .. tostring(to)) end
    local want = opts and opts.count or 1
    local keys = {}
    if type(what) == "string" then
      keys[1] = entries[what]
    else
      for _, e in ipairs(sorted()) do if matches(what, e) then keys[#keys + 1] = e end end
    end
    local r = { moved = 0, entries = {}, remainder = want, pending = 0, viaStorageBus = false, more = false }
    for _, e in ipairs(keys) do
      if r.moved >= want then break end
      local n = math.min(want - r.moved, e.count, chest.room)
      if n > 0 then
        e.count = e.count - n
        chest.room = chest.room - n
        chest.got[#chest.got + 1] = e.id
        r.moved = r.moved + n
        r.entries[#r.entries + 1] = { id = e.id, type = "item", name = e.name, count = n }
      end
    end
    r.remainder = want - r.moved
    if r.remainder > 0 then
      r.reason = #keys == 0 and "NOT_FOUND" or (r.moved == 0 and keys[1].count > 0) and "TARGET_FULL" or "NOT_ENOUGH"
    end
    return r
  end
  return me
end

local function vd(o)
  return { itemType = "Gear", level = o.level or 50, rarity = o.rarity or "RARE", state = "IDENTIFIED", name = o.name or "piece",
    equipmentSlot = o.slot or "head", prefixes = {} }
end

local function gearMe()
  local entries = {
    ["a1"] = { id = "a1", name = "the_vault:helmet", count = 1, uuid = "u-1" },
    ["b2"] = { id = "b2", name = "the_vault:boots", count = 1, uuid = "u-2" },
    ["c3"] = { id = "c3", name = "the_vault:sword", count = 1 },
    ["d4"] = { id = "d4", name = "minecraft:dirt", count = 640 },
  }
  local details = {
    a1 = { name = "the_vault:helmet", count = 1, vaultData = vd({ slot = "head" }) },
    b2 = { name = "the_vault:boots", count = 1, vaultData = vd({ slot = "feet" }) },
    c3 = { name = "the_vault:sword", count = 1, vaultData = vd({ slot = "mainhand" }) },
  }
  return fakeBridge(entries, details), entries, details
end

-- the locker keeps its files with fs and textutils; an in-memory copy is enough here
local function withCcGlobals(fn)
  local files, store = {}, {}
  local oldFs, oldTu = rawget(_G, "fs"), rawget(_G, "textutils")
  rawset(_G, "fs", {
    exists = function(p) return files[p] ~= nil end,
    combine = function(a, b) return (a:gsub("/$", "")) .. "/" .. b end,
    delete = function(p) files[p] = nil end,
    move = function(a, b) files[b], files[a] = files[a], nil end,
    open = function(p, mode)
      if mode == "w" then return { write = function(s) files[p] = s end, close = function() end } end
      return { readAll = function() return files[p] end, close = function() end }
    end,
  })
  rawset(_G, "textutils", {
    serialize = function(v) store[#store + 1] = v return tostring(#store) end,
    unserialize = function(s) return store[tonumber(s)] end,
  })
  local ok, err = pcall(fn)
  rawset(_G, "fs", oldFs)
  rawset(_G, "textutils", oldTu)
  if not ok then error(err, 0) end
end

local function newLocker(me)
  local locker = require("lib.gearlocker.locker")
  local devs = { bridge = me, junk = {}, pickup = {} }
  local L = locker.new({
    dir = "/t",
    peripheral = { wrap = function(name) return devs[name] end },
    now = function() return 1000 end,
  })
  L.cfg.bridge, L.cfg.junk, L.cfg.pickup = "bridge", "junk", "pickup"
  return L
end

test("mebridge: locker scan reads gear with getDetails, keys pieces by uuid or id", function()
  withCcGlobals(function()
    local me = gearMe()
    local L = newLocker(me)
    local n, err = L:scan()
    eq(err, nil) eq(n, 3, "three gear keys, the dirt is skipped")
    local fps = {}
    for _, p in ipairs(L:pieces()) do fps[p.fp] = p.id end
    eq(fps["u-1"], "the_vault:helmet") eq(fps["u-2"], "the_vault:boots")
    eq(fps["c3"], "the_vault:sword", "no uuid: goes by its id")
    local exports = 0
    for _, c in ipairs(me.calls) do if c == "export" then exports = exports + 1 end end
    eq(exports, 0, "nothing leaves the ME to be read")
    eq(L:scan(), 0, "second scan reads nothing new")
  end)
end)

test("mebridge: locker send exports by id, then by uuid when VH changed the piece", function()
  withCcGlobals(function()
    local me, entries, details = gearMe()
    me.chests.junk = { room = 10, got = {} }
    me.chests.pickup = { room = 10, got = {} }
    local L = newLocker(me)
    L:scan()
    eq(L:send("u-1", "junk"), 1)
    eq(me.chests.junk.got[1], "a1")
    eq(entries.a1.count, 0)
    -- the boots got a new clientCache: same uuid, new id
    entries.b9 = { id = "b9", name = "the_vault:boots", count = 1, uuid = "u-2" }
    details.b9 = details.b2
    entries.b2.count = 0
    eq(L:take("u-2"), true)
    eq(me.chests.pickup.got[1], "b9")
    local moved, why = L:send("u-2", "junk")
    eq(moved, nil) eq(why, "piece gone")
    me.chests.junk.room = 0
    moved, why = L:send("c3", "junk")
    eq(moved, nil) eq(why, "junk chest full")
    eq(entries.c3.count, 1, "nothing moved")
  end)
end)

test("mebridge: vaultgear routes gear out of a bridge inbox without a staging chest", function()
  local me, entries = gearMe()
  me.chests.home = { room = 10, got = {} }
  local wrapped = { bridge = me, home = { list = function() return {} end, pushItems = function() return 0 end } }
  local oldP = rawget(_G, "peripheral")
  local oldOs = os.epoch
  rawset(_G, "peripheral", {
    wrap = function(n) return wrapped[n] end,
    hasType = function(n, t) if n == "bridge" then return t == "me_bridge" end return wrapped[n] and t == "inventory" end,
    getType = function(n) return n == "bridge" and "me_bridge" or "minecraft:chest" end,
  })
  os.epoch = os.epoch or function() return 0 end
  local ok, err = pcall(function()
    package.loaded["lib.vaultgear.service"] = nil
    local service = require("lib.vaultgear.service")
    local planner = require("lib.vaultgear.planner")
    local storages = planner.normalizeStorages({
      { inventory = "bridge", role = "inbox" },
      { inventory = "home", role = "home", preset_id = "overflow" },
    })
    local state = {}
    local moved = 0
    for _ = 1, 10 do
      local report = service.processInboxes(storages, { bridge = true, home = true }, state, nil, nil)
      eq(#report.errors, 0, report.errors[1])
      moved = moved + report.moved_items
    end
    eq(moved, 3, "every gear piece reached the home")
    eq(entries.d4.count, 640, "dirt stays in the ME")
    eq(#me.chests.home.got, 3)

    local inspect = service.inspectInventory("bridge", nil, nil, 12)
    eq(inspect.error, nil)
    eq(inspect.total_slots, 1, "only the dirt is left")
  end)
  rawset(_G, "peripheral", oldP)
  os.epoch = oldOs
  if not ok then error(err, 0) end
end)

test("mebridge: a full home is an error and the piece stays in the ME", function()
  local me, entries = gearMe()
  me.chests.home = { room = 0, got = {} }
  local wrapped = { bridge = me, home = { list = function() return {} end, pushItems = function() return 0 end } }
  local oldP = rawget(_G, "peripheral")
  local oldOs = os.epoch
  rawset(_G, "peripheral", {
    wrap = function(n) return wrapped[n] end,
    hasType = function(n, t) return n == "bridge" and t == "me_bridge" end,
    getType = function(n) return n == "bridge" and "me_bridge" or "minecraft:chest" end,
  })
  os.epoch = os.epoch or function() return 0 end
  local ok, err = pcall(function()
    local service = require("lib.vaultgear.service")
    local planner = require("lib.vaultgear.planner")
    local storages = planner.normalizeStorages({
      { inventory = "bridge", role = "inbox" },
      { inventory = "home", role = "home", preset_id = "overflow" },
    })
    local report = service.processInboxes(storages, { bridge = true, home = true }, {}, nil, nil)
    eq(report.moved_items, 0)
    truthy(tostring(report.errors[1]):find("TARGET_FULL", 1, true), tostring(report.errors[1]))
    eq(entries.a1.count, 1)
  end)
  rawset(_G, "peripheral", oldP)
  os.epoch = oldOs
  if not ok then error(err, 0) end
end)
