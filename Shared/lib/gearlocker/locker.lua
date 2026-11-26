-- gearlocker/locker.lua
-- Everything the locker does to the world: the ME Bridge, the three chests, ccvault and its own files.
-- The bridge can't read vault gear stats, so a piece we haven't seen goes out to the staging chest, gets read with
-- vhcctweaks listDetailed, and goes straight back. Each fingerprint is only read once, the cache keeps the rest.

local rules = require("lib.gearshop.rules")
local judge = require("lib.gearlocker.judge")

local M = {}

M.CONFIG_FILE = "gearlocker_config.dat"
M.CACHE_FILE = "gearlocker_cache.dat"

-- only these get read; idols, jewels and the rest have no slot and aren't worth the round trip
local GEAR = {
  ["the_vault:helmet"] = true, ["the_vault:chestplate"] = true, ["the_vault:leggings"] = true,
  ["the_vault:boots"] = true, ["the_vault:sword"] = true, ["the_vault:axe"] = true, ["the_vault:shield"] = true,
  ["the_vault:wand"] = true, ["the_vault:focus"] = true, ["the_vault:magnet"] = true,
}
M.GEAR = GEAR

local WORN_SLOTS = { head = "head", chest = "chest", legs = "legs", feet = "feet", offhand = "offhand" }
local WORN_SECS = 60

local Locker = {}
Locker.__index = Locker

local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  local text = f.readAll()
  f.close()
  return textutils.unserialize(text or "")
end

local function writeFile(path, value)
  local tmp = path .. ".new"
  local f = fs.open(tmp, "w")
  f.write(textutils.serialize(value, { compact = true }))
  f.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
end

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Locker)
  self.dir = opts.dir or "/"
  self.p = opts.peripheral or peripheral
  self.vault = opts.ccvault or ccvault
  self.now = opts.now or function() return os.epoch("utc") / 1000 end
  self.cfg = readFile(fs.combine(self.dir, M.CONFIG_FILE)) or {}
  self.cfg.rules = self.cfg.rules or {}
  self.cfg.spared = self.cfg.spared or {}
  local cache = readFile(fs.combine(self.dir, M.CACHE_FILE)) or {}
  self.cache = cache.pieces or {}
  self.lastScan = cache.at
  self.inMe = {}
  return self
end

function Locker:saveConfig()
  writeFile(fs.combine(self.dir, M.CONFIG_FILE), self.cfg)
end

function Locker:saveCache()
  writeFile(fs.combine(self.dir, M.CACHE_FILE), { at = self.lastScan, pieces = self.cache })
end

function Locker:settings() return judge.settings(self.cfg.rules) end

-- the peripheral for a cfg role, or nil and what's wrong
function Locker:dev(role)
  local name = self.cfg[role]
  if not name then return nil, role .. " not set up" end
  local dev = self.p.wrap(name)
  if not dev then return nil, role .. " " .. name .. " is missing" end
  return dev
end

function Locker:missing()
  local out = {}
  for _, role in ipairs({ "bridge", "staging", "junk", "pickup", "monitor" }) do
    local _, why = self:dev(role)
    if why then out[#out + 1] = why end
  end
  return out
end

-- everything in staging back into ME, one import per item name
function Locker:recover()
  local bridge, why = self:dev("bridge")
  if not bridge then return nil, why end
  local staging, swhy = self:dev("staging")
  if not staging then return nil, swhy end
  local names = {}
  for _, stack in pairs(staging.list() or {}) do names[stack.name] = (names[stack.name] or 0) + stack.count end
  local back = 0
  for name, n in pairs(names) do
    local ok, moved = pcall(bridge.importItemFromPeripheral, { name = name, count = n }, self.cfg.staging)
    if ok and type(moved) == "number" then back = back + moved end
  end
  return back
end

local function hasNbt(entry)
  local nbt = entry.nbt
  if type(nbt) ~= "table" then return nbt ~= nil end
  if nbt.id and nbt.tag == nil then return false end
  return next(nbt) ~= nil
end

function Locker:scan(onProgress)
  local bridge, why = self:dev("bridge")
  if not bridge then return nil, why end
  local staging, swhy = self:dev("staging")
  if not staging then return nil, swhy end
  local list, err = bridge.listItems()
  if type(list) ~= "table" then return nil, "can't list the ME: " .. tostring(err) end

  local seen, todo = {}, {}
  for _, e in ipairs(list) do
    if GEAR[e.name] and e.fingerprint and hasNbt(e) then
      seen[e.fingerprint] = e.amount or 1
      if not self.cache[e.fingerprint] then todo[#todo + 1] = e end
    end
  end

  -- leftovers from a stopped scan would land in the wrong slots
  if next(staging.list() or {}) then self:recover() end
  local size = staging.size()
  local done = 0
  if onProgress then onProgress(0, #todo) end
  local i = 1
  while i <= #todo do
    local batch = {}
    for slot = 1, size do
      local e = todo[i]
      if not e then break end
      i = i + 1
      local ok, moved = pcall(bridge.exportItemToPeripheral,
        { fingerprint = e.fingerprint, count = 1, toSlot = slot - 1 }, self.cfg.staging)
      if ok and moved == 1 then batch[slot] = e else done = done + 1 end
    end
    if next(batch) then
      local details = staging.listDetailed and staging.listDetailed()
      if type(details) ~= "table" then
        details = {}
        for slot in pairs(batch) do details[slot] = staging.getItemDetail(slot) end
      end
      for slot, e in pairs(batch) do
        local piece = rules.piece(details[slot])
        -- a stack that moved under us reads as something else; leave it uncached and try again next scan
        if piece and piece.id == e.name then
          piece.fp = e.fingerprint
          self.cache[e.fingerprint] = piece
        end
        done = done + 1
      end
      self:recover()
    end
    if onProgress then onProgress(done, #todo) end
  end

  for fp in pairs(self.cache) do
    if not seen[fp] then self.cache[fp] = nil end
  end
  self.inMe = seen
  self.lastScan = self.now()
  self:saveCache()
  return #todo
end

function Locker:pieces()
  local out = {}
  for fp, piece in pairs(self.cache) do
    piece.fp = fp
    piece.amount = self.inMe[fp] or 1
    out[#out + 1] = piece
  end
  return out
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil, "missing" end
  local ok, value, why = pcall(fn, ...)
  if not ok then return nil, tostring(value) end
  if value == nil then return nil, tostring(why) end
  return value
end

-- same reading as the Gear Shop's Shop:readPlayer, minus the shop bits
function Locker:readPlayer()
  local name = self.cfg.player
  if not name then return nil, "no player set" end
  local cached = self.worn
  if cached and cached.name == name and self.now() - cached.at < WORN_SECS then return cached end
  local cv = self.vault
  if type(cv) ~= "table" or type(cv.getPlayerEquipment) ~= "function" then return nil, "this server can't read gear" end
  local eq, why = call(cv.getPlayerEquipment, name)
  if type(eq) ~= "table" then
    return nil, tostring(why):find("offline", 1, true) and (name .. " is offline") or ("can't read your gear: " .. tostring(why))
  end
  local r = { at = self.now(), name = name, worn = {}, trinkets = {} }
  for _ = 1, 3 do
    local lvl, lwhy = call(cv.getPlayerVaultLevel, name)
    if type(lvl) == "number" then r.level = lvl break end
    if not tostring(lwhy):find("try again", 1, true) then break end
  end
  local function piece(d) return type(d) == "table" and d.name and rules.piece(d) or nil end
  for field, slot in pairs(WORN_SLOTS) do r.worn[slot] = piece(eq[field]) end
  r.worn.weapon = piece(eq.weapon) or piece(eq.mainhand)
  local limited = eq.weapon == nil and eq.hotbar == nil
  for _, items in pairs(type(eq.curios) == "table" and eq.curios or {}) do
    for _, item in pairs(items) do
      if type(item) == "table" and type(item.name) == "string" then
        if item.name == "the_vault:magnet" then r.worn.magnet = piece(item) else r.trinkets[#r.trinkets + 1] = item.name end
      end
    end
  end
  local temper = call(cv.getPlayerTemper, name)
  if type(temper) == "table" then
    local function lv(c) return type(temper[c]) == "table" and tonumber(temper[c].level) or 0 end
    r.temper = { might = lv("might"), magic = lv("magic"), vigor = lv("vigor") }
  end
  local gp = call(cv.getPlayerGearPower, name)
  if type(gp) == "table" then
    r.gearScore = gp.shown ~= false and tonumber(gp.gearScore) or nil
    r.greed = tonumber(gp.greedTier)
  end
  local skills = call(cv.getPlayerSkills, name)
  if type(skills) == "table" and type(skills.abilities) == "table" then r.skills = skills.abilities else limited = true end
  local stats = call(cv.getPlayerStats, name)
  if type(stats) == "table" then
    r.totals, r.caps = {}, {}
    for id, st in pairs(stats) do
      local a = tostring(id):gsub("^the_vault:", "")
      if type(st) == "table" then
        r.totals[a] = tonumber(st.uncapped) or tonumber(st.value)
        if tonumber(st.limit) then r.caps[a] = tonumber(st.limit) end
      end
    end
  else
    limited = true
  end
  if not r.caps and type(cv.getLimits) == "function" then
    local ok, limits = pcall(cv.getLimits)
    if ok and type(limits) == "table" and type(limits.statCaps) == "table" then
      r.caps = {}
      for id, cap in pairs(limits.statCaps) do
        if type(cap) == "table" and tonumber(cap.base) then r.caps[(tostring(id):gsub("^the_vault:", ""))] = tonumber(cap.base) end
      end
    end
  end
  r.limited = limited or nil
  self.worn = r
  return r
end

local function fpOf(x)
  if type(x) == "string" then return x end
  if type(x) == "table" then return x.fp or (x.piece and x.piece.fp) end
end

function Locker:send(fp, role)
  local bridge, why = self:dev("bridge")
  if not bridge then return nil, why end
  if not self.cfg[role] or not self.p.wrap(self.cfg[role]) then return nil, role .. " chest is missing" end
  local want = self.inMe[fp] or 1
  local ok, moved, err = pcall(bridge.exportItemToPeripheral, { fingerprint = fp, count = want }, self.cfg[role])
  if not ok then return nil, tostring(moved) end
  if type(moved) ~= "number" or moved < 1 then return nil, err and tostring(err) or (role .. " chest full or piece gone") end
  if moved >= want then
    self.cache[fp] = nil
    self.inMe[fp] = nil
  else
    self.inMe[fp] = want - moved
  end
  return moved
end

function Locker:pull(list)
  local moved, failed = 0, {}
  for _, x in ipairs(list or {}) do
    local fp = fpOf(x)
    local ok, why = self:send(fp, "junk")
    if ok then moved = moved + 1 else failed[#failed + 1] = { fp = fp, why = why } end
  end
  if moved > 0 then self:saveCache() end
  return moved, failed
end

function Locker:take(fp)
  local ok, why = self:send(fpOf(fp), "pickup")
  if not ok then return nil, why end
  self:saveCache()
  return true
end

function Locker:spare(fp, on)
  self.cfg.spared[fp] = on and true or nil
  self:saveConfig()
end

return M
