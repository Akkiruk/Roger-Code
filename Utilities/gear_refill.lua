-- manifest-name: Gear Refill
-- manifest-description: Command computer only. Copies one template gear piece into a chest as every gear type, to replace the gear the Gear Locker lost.
-- Runs on a command computer:
--   top     a plain chest or barrel with the template in slot 1 (a blank piece given level, rarity and legendary by hand)
--   bottom  a plain chest or barrel the copies are made in
--   any other side (optional)  where they go: a netherite barrel or anything else. Without one, an AE2 import bus on the
--           bottom chest can take them.
-- Copies go through /data (template -> command storage -> bottom chest), so the gear data is copied as is, never
-- rebuilt. /data only reaches plain chests and barrels, so the Sophisticated ones can only be the destination; the
-- move there is a normal item move, which keeps the data.
--
--   gear_refill test    one of each type, then stops so they can be checked
--   gear_refill         everything still owed
--   gear_refill status  what's done

-- the 2026-11-25 loss, by item
local OWED = {
  { "the_vault:wand", 166 }, { "the_vault:rang", 223 }, { "the_vault:trident", 210 }, { "the_vault:sword", 187 },
  { "the_vault:shield", 163 }, { "the_vault:leggings", 187 }, { "the_vault:helmet", 220 },
  { "the_vault:chestplate", 188 }, { "the_vault:boots", 188 }, { "the_vault:battlestaff", 220 },
  { "the_vault:axe", 221 }, { "the_vault:magnet", 198 }, { "the_vault:focus", 129 },
}
local TEMPLATE, OUT = "~ ~1 ~", "~ ~-1 ~"
local STORE = "roger:gear_refill"
local DONE_FILE = "gear_refill_done.txt"
local PATH = "Utilities/gear_refill.lua"

local args = { ... }

-- update from main before doing anything; by commit, since the raw CDN can hand out an old copy for minutes
local function update()
  if not http or args[1] == "noupdate" then return false end
  local h = http.get("https://api.github.com/repos/Akkiruk/Roger-Code/commits/main")
  if not h then return false end
  local sha = (h.readAll() or ""):match('"sha"%s*:%s*"(%x+)"')
  h.close()
  if not sha then return false end
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
local out = peripheral.wrap("bottom")
if not out or not out.list then error("Put a plain chest or barrel under this computer.", 0) end
-- /data can't write into modded storage (a netherite barrel ignores it), so the block below has to be vanilla
local below = peripheral.getType("bottom")
if below ~= "minecraft:chest" and below ~= "minecraft:barrel" and below ~= "minecraft:trapped_chest" then
  error("The block under this computer is " .. tostring(below) .. ". It has to be a plain chest or barrel;"
    .. " put the netherite barrel on a side instead.", 0)
end
local dest, destName
for _, side in ipairs({ "left", "right", "front", "back" }) do
  local p = peripheral.wrap(side)
  if p and p.list and p.size then dest, destName = p, side break end
end

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

if mode == "status" then
  local total, left = 0, 0
  for _, row in ipairs(OWED) do
    local n = done[row[1]] or 0
    print(("%-12s %4d / %d"):format(row[1]:gsub("^the_vault:", ""), n, row[2]))
    total, left = total + n, left + row[2] - n
  end
  print(("%d made, %d to go"):format(total, left))
  return
end

local tpl = peripheral.wrap("top")
local first = tpl and tpl.getItemDetail and tpl.getItemDetail(1)
if not first then error("Put the template piece in slot 1 of a plain chest or barrel on top.", 0) end
local vd = first.vaultData
if type(vd) == "table" and vd.level ~= 100 then
  print("Warning: the template is level " .. tostring(vd.level) .. ", not 100.")
end
print(dest and ("Copies go to the " .. destName .. ".") or "No destination on the sides: copies stay in the chest below.")

-- whatever a stopped run left below goes on first
if dest then
  for slot in pairs(out.list()) do out.pushItems(destName, slot) end
end

local function freeSlot()
  local used = out.list()
  for slot = 1, out.size() do
    if not used[slot] then return slot end
  end
end

local function waitFor(what, check)
  local said = false
  local v = check()
  while not v do
    if not said then print(what) said = true end
    sleep(1)
    v = check()
  end
  return v
end

local function place(id)
  local slot = waitFor("The chest below is full, waiting...", freeSlot)
  run(("data modify storage %s item.Slot set value %db"):format(STORE, slot - 1))
  run(("data modify block %s Items append from storage %s item"):format(OUT, STORE))
  local d = out.getItemDetail(slot)
  if not d or d.name ~= id then error("The copy in slot " .. slot .. " isn't " .. id .. ", stopping.", 0) end
  if dest then
    -- gone from the slot some other way (an import bus) counts as delivered too
    waitFor("The " .. destName .. " is full, waiting...", function()
      return out.pushItems(destName, slot) == 1 or out.getItemDetail(slot) == nil
    end)
  end
end

for _, row in ipairs(OWED) do
  local id, want = row[1], row[2]
  if mode == "test" then want = math.min(want, 1) end
  local have = done[id] or 0
  if have < want then
    run(("data modify storage %s item set from block %s Items[{Slot:0b}]"):format(STORE, TEMPLATE))
    run(('data modify storage %s item.id set value "%s"'):format(STORE, id))
    while have < want do
      place(id)
      have = have + 1
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
