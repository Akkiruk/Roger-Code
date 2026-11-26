-- manifest-name: Gear Refill
-- manifest-description: Command computer only. Copies one template gear piece into a chest as every gear type, to replace the gear the Gear Locker lost.
-- Runs on a command computer. A chest on top holds the template (slot 1): a blank piece given the level, rarity and
-- legendary flag by hand. The chest underneath gets the copies; an AE2 import bus on it takes them into the ME.
-- Copies go through /data (template -> command storage -> chest), so the gear data is copied as is, never rebuilt.
-- Both chests need to be plain ones that keep an Items list (vanilla chest or barrel).
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

if not commands then error("This needs a command computer.", 0) end
local out = peripheral.wrap("bottom")
if not out or not out.list then error("Put the output chest under this computer.", 0) end

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
  if not ok then error("Command failed: " .. cmd .. "\n" .. table.concat(lines or {}, "\n"), 0) end
  return lines
end

local mode = ... or "all"

if mode == "status" then
  local total, left = 0, 0
  for _, row in ipairs(OWED) do
    local n = done[row[1]] or 0
    print(("%-22s %4d / %d"):format(row[1]:gsub("^the_vault:", ""), n, row[2]))
    total, left = total + n, left + row[2] - n
  end
  print(("%d made, %d to go"):format(total, left))
  return
end

local tpl = peripheral.wrap("top")
local first = tpl and tpl.getItemDetail and tpl.getItemDetail(1)
if not first then error("Put the template piece in slot 1 of the chest on top.", 0) end
local vd = first.vaultData
if type(vd) == "table" and vd.level ~= 100 then
  print("Warning: the template is level " .. tostring(vd.level) .. ", not 100.")
end

local function freeSlot()
  local used = out.list()
  for slot = 1, out.size() do
    if not used[slot] then return slot end
  end
end

local function place()
  local slot = freeSlot()
  while not slot do
    -- full: the import bus empties it
    sleep(1)
    slot = freeSlot()
  end
  -- /item replace refused the template chest ("not a container"), so the copy goes through command storage
  run(("data modify storage %s item.Slot set value %db"):format(STORE, slot - 1))
  run(("data modify block %s Items append from storage %s item"):format(OUT, STORE))
  return slot
end

for _, row in ipairs(OWED) do
  local id, want = row[1], row[2]
  if mode == "test" then want = math.min(want, 1) end
  local have = done[id] or 0
  if have < want then
    run(("data modify storage %s item set from block %s Items[{Slot:0b}]"):format(STORE, TEMPLATE))
    run(('data modify storage %s item.id set value "%s"'):format(STORE, id))
    while have < want do
      local slot = place()
      if have == 0 then
        local d = out.getItemDetail(slot)
        if not d or d.name ~= id then error("The copy in slot " .. slot .. " isn't " .. id .. ", stopping.", 0) end
      end
      have = have + 1
      done[id] = have
      saveDone()
    end
    print(("%s: %d"):format(id:gsub("^the_vault:", ""), have))
  end
end

if mode == "test" then
  print("One of each is in the chest below. Check them, then run gear_refill for the rest.")
  -- the test pieces count, so the full run makes one fewer of each
else
  print("All done.")
end
