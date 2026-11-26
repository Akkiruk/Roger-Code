-- manifest-name: Gear Refill
-- manifest-description: Command computer only. Copies one template gear piece into a chest as every gear type, to replace the gear the Gear Locker lost.
-- Runs on a command computer:
--   top     a plain chest or barrel with the template in slot 1 (a blank piece given level, rarity and legendary by hand)
--   one plain chest or barrel on another side or below: the copies are made in it
--   anything else touching it (optional), like a netherite barrel: where they go. Without one, an AE2 import bus on
--           the plain chest can take them.
-- Copies go through /data (template -> command storage -> plain chest), so the gear data is copied as is, never
-- rebuilt. /data only reaches plain chests and barrels, so the Sophisticated ones can only be the destination; the
-- move there is a normal item move, which keeps the data.
--
--   gear_refill test    one of each type, then stops so they can be checked
--   gear_refill         everything still owed
--   gear_refill status  what's done
--   gear_refill swap    turn the copies already made into copies of a new template on top (say Rare+), one for one

-- the 2026-11-25 loss, by item
local OWED = {
  { "the_vault:wand", 166 }, { "the_vault:rang", 223 }, { "the_vault:trident", 210 }, { "the_vault:sword", 187 },
  { "the_vault:shield", 163 }, { "the_vault:leggings", 187 }, { "the_vault:helmet", 220 },
  { "the_vault:chestplate", 188 }, { "the_vault:boots", 188 }, { "the_vault:battlestaff", 220 },
  { "the_vault:axe", 221 }, { "the_vault:magnet", 198 }, { "the_vault:focus", 129 },
}
local TEMPLATE, OUT = "~ ~1 ~", nil
local STORE = "roger:gear_refill"
local DONE_FILE = "gear_refill_done.txt"
local PATH = "Utilities/gear_refill.lua"

local args = { ... }

-- update from main before doing anything; by commit, since the raw CDN can hand out an old copy for minutes
local function update()
  if not http or args[1] == "noupdate" then return false end
  -- the API is rate limited per server IP (every Roger-Code computer there shares it); main's raw file is the fallback
  local sha = "main"
  local h = http.get("https://api.github.com/repos/Akkiruk/Roger-Code/commits/main")
  if h then
    sha = (h.readAll() or ""):match('"sha"%s*:%s*"(%x+)"') or "main"
    h.close()
  end
  h = http.get("https://raw.githubusercontent.com/Akkiruk/Roger-Code/" .. sha .. "/" .. PATH)
  if not h then return false end
  local new = h.readAll()
  h.close()
  local me = shell.getRunningProgram()
  local f = fs.open(me, "r")
  local old = f.readAll()
  f.close()
  if not new or #new < 100 or new == old or not load(new) then return false end
  f = fs.open(me, "w")
  f.write(new)
  f.close()
  print("Updated to " .. sha:sub(1, 7))
  return true
end

if update() then
  shell.run(shell.getRunningProgram(), "noupdate", table.unpack(args))
  return
end
if args[1] == "noupdate" then table.remove(args, 1) end

if not commands then error("This needs a command computer.", 0) end

-- /data can't write into modded storage (a netherite barrel ignores it), so the copies are made in a plain chest or
-- barrel touching the computer (not the top one), and anything else touching it is where they go
local PLAIN = { ["minecraft:chest"] = true, ["minecraft:barrel"] = true, ["minecraft:trapped_chest"] = true }
local SIDES = { "bottom", "left", "right", "front", "back" }

local out, outSide, dest, destName
for _, side in ipairs(SIDES) do
  local p = peripheral.wrap(side)
  if p and p.list and p.size then
    if PLAIN[peripheral.getType(side)] and not out then out, outSide = p, side
    elseif not dest then dest, destName = p, side end
  end
end
if not out then error("Put a plain chest or barrel against a side or the bottom of this computer.", 0) end

-- the same block by world position, for /data
local cx, cy, cz = commands.getBlockPosition()
for _, d in ipairs({ { 0, -1, 0 }, { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }) do
  local info = commands.getBlockInfo(cx + d[1], cy + d[2], cz + d[3])
  if info and PLAIN[info.name] then
    if OUT then error("Only one plain chest or barrel can touch the computer (besides the template on top).", 0) end
    OUT = ("~%d ~%d ~%d"):format(d[1], d[2], d[3])
  end
end
if not OUT then error("Couldn't find the plain chest or barrel by position.", 0) end

local function loadDone()
  if not fs.exists(DONE_FILE) then return {} end
  local h = fs.open(DONE_FILE, "r")
  local t = textutils.unserialise(h.readAll()) or {}
  h.close()
  return t
end

local done = loadDone()
local function saveDone()
  local h = fs.open(DONE_FILE, "w")
  h.write(textutils.serialise(done))
  h.close()
end

local function run(cmd)
  local ok, lines = commands.exec(cmd)
  local text = table.concat(lines or {}, "\n")
  -- /data says this when the value was already right
  if not ok and not text:find("Nothing changed", 1, true) then error("Command failed: " .. cmd .. "\n" .. text, 0) end
  return lines
end

local mode = args[1] or "all"

local tpl = peripheral.wrap("top")
local first = tpl and tpl.getItemDetail and tpl.getItemDetail(1)
if not first then error("Put the template piece in slot 1 of a plain chest or barrel on top.", 0) end
local tplLevel = type(first.vaultData) == "table" and first.vaultData.level or nil
if tplLevel ~= 100 then print("Warning: the template is level " .. tostring(tplLevel) .. ", not 100.") end

-- what's already made: copies sitting in the destination or the plain chest (unidentified, the template's level)
local OWES = {}
for _, row in ipairs(OWED) do OWES[row[1]] = true end
local function countCopies(inv)
  local n = {}
  if not inv then return n end
  for slot, it in pairs(inv.list()) do
    if OWES[it.name] then
      local d = inv.getItemDetail(slot)
      local v = d and d.vaultData
      if type(v) == "table" and v.level == tplLevel and tostring(v.state):upper() ~= "IDENTIFIED" then
        n[it.name] = (n[it.name] or 0) + it.count
      end
    end
  end
  return n
end
local inDest, inOut = countCopies(dest), countCopies(out)
for id in pairs(OWES) do
  done[id] = math.max(done[id] or 0, (inDest[id] or 0) + (inOut[id] or 0))
end
saveDone()

if mode == "status" then
  local total, left = 0, 0
  for _, row in ipairs(OWED) do
    local n = done[row[1]]
    print(("%-12s %4d / %d"):format(row[1]:gsub("^the_vault:", ""), n, row[2]))
    total, left = total + n, left + math.max(0, row[2] - n)
  end
  print(("%d made, %d to go"):format(total, left))
  return
end

print(dest and ("Copies are made " .. outSide .. " and go to the " .. destName .. ".")
  or ("Nothing else touching the computer: copies stay in the plain " .. outSide .. " chest."))

local function waitFor(what, check)
  local said = false
  while not check() do
    if not said then print(what) said = true end
    sleep(1)
  end
end

-- everything in the plain chest into the destination, all slots at once
local function flush()
  if not dest then return end
  local jobs = {}
  for slot in pairs(out.list()) do
    jobs[#jobs + 1] = function()
      waitFor("The " .. destName .. " is full, waiting...", function()
        out.pushItems(destName, slot)
        return out.getItemDetail(slot) == nil
      end)
    end
  end
  if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
end

-- the template as text, once per type, so a whole chest of copies is one command
local function itemText(id)
  run(("data modify storage %s item set from block %s Items[{Slot:0b}]"):format(STORE, TEMPLATE))
  run(('data modify storage %s item.id set value "%s"'):format(STORE, id))
  local ok, lines = commands.exec(("data remove storage %s item.Slot"):format(STORE))
  ok, lines = commands.exec(("data get storage %s item"):format(STORE))
  local text = ok and table.concat(lines or {}, ""):match("(%b{})%s*$")
  if not text then error("Couldn't read the template back: " .. table.concat(lines or {}, " "), 0) end
  return text
end

local function copies(text, n)
  local list = {}
  for slot = 0, n - 1 do list[#list + 1] = "{Slot:" .. slot .. "b," .. text:sub(2) end
  run(("data modify block %s Items set value [%s]"):format(OUT, table.concat(list, ",")))
end

flush()

-- swap: the copies already made become copies of the template now on top (a new roll type, say), one for one.
-- The old copies of a type are all identical, so they share one nbt hash; only that group is touched.
if mode == "swap" then
  if not dest then error("Swap needs the barrel with the copies touching the computer.", 0) end
  local swapped = 0
  for _, row in ipairs(OWED) do
    local id = row[1]
    local text = itemText(id)
    copies(text, 1)
    local newHash = (out.getItemDetail(1) or {}).nbt
    run(("data modify block %s Items set value []"):format(OUT))
    if not newHash then error("Couldn't read the new copy of " .. id .. ", stopping.", 0) end

    local groups = {}
    for slot, it in pairs(dest.list()) do
      if it.name == id and it.nbt and it.nbt ~= newHash then
        local d = dest.getItemDetail(slot)
        local v = d and d.vaultData
        if type(v) == "table" and v.level == tplLevel and tostring(v.state):upper() ~= "IDENTIFIED" then
          local g = groups[it.nbt] or { n = 0, slots = {} }
          g.n = g.n + it.count
          g.slots[#g.slots + 1] = slot
          groups[it.nbt] = g
        end
      end
    end
    local oldHash, old
    for h, g in pairs(groups) do
      if not old or g.n > old.n then oldHash, old = h, g end
    end
    for h, g in pairs(groups) do
      if h ~= oldHash then print(("%s: left %d other unidentified pieces alone"):format(id, g.n)) end
    end

    local left = old and old.n or 0
    while left > 0 do
      -- pull up to a chest's worth of old copies into the plain chest, one per slot
      local jobs, take = {}, math.min(left, out.size())
      local k = 0
      for _, from in ipairs(old.slots) do
        local here = (dest.getItemDetail(from) or {}).count or 0
        for _ = 1, here do
          if k >= take then break end
          k = k + 1
          local to = k
          jobs[#jobs + 1] = function() out.pullItems(destName, from, 1, to) end
        end
        if k >= take then break end
      end
      if #jobs == 0 then break end
      parallel.waitForAll(table.unpack(jobs))
      local n = 0
      for slot, it in pairs(out.list()) do
        if it.nbt ~= oldHash then
          flush()
          error("Something other than an old copy came out in slot " .. slot .. "; put it back, stopping.", 0)
        end
        n = n + it.count
      end
      if n == 0 then break end
      copies(text, n)
      flush()
      left, swapped = left - n, swapped + n
    end
    print(("%s: swapped %d"):format(id:gsub("^the_vault:", ""), old and old.n - left or 0))
  end
  print(("Swapped %d in all."):format(swapped))
  return
end

for _, row in ipairs(OWED) do
  local id, want = row[1], row[2]
  if mode == "test" then want = math.min(want, 1) end
  local have = done[id]
  if have < want then
    local text = itemText(id)
    while have < want do
      waitFor("The plain chest isn't empty, waiting...", function() return next(out.list()) == nil end)
      local n = math.min(want - have, out.size())
      copies(text, n)
      local d = out.getItemDetail(1)
      if not d or d.name ~= id or type(d.vaultData) ~= "table" or d.vaultData.level ~= tplLevel then
        error("The copies in the plain chest don't look like the template, stopping.", 0)
      end
      flush()
      have = have + n
      done[id] = have
      saveDone()
    end
    print(("%s: %d"):format(id:gsub("^the_vault:", ""), have))
  end
end

if mode == "test" then
  print("One of each is made. Check them, then run gear_refill for the rest.")
else
  print("All done.")
end
