-- arcade_journal.lua
-- The match on disk, so a reboot loses nothing and a result counts exactly once:
--   playing   every action so far, written before the screen shows it
--   finished  the outcome is known and waiting to go into the records
--   recorded  the records hold it (they remember the match id), so the entry is cleared
-- There is one open match at a time. Rules are pure, so seed + actions rebuilds the state exactly.

local M = {}

local FILE = "arcade_match.dat"

local function read(path)
  if not fs.exists(path) then return nil end
  local handle = fs.open(path, "r")
  if not handle then return nil end
  local text = handle.readAll()
  handle.close()
  local ok, value = pcall(textutils.unserialise, text or "")
  if ok and type(value) == "table" then return value end
  return nil
end

--- Write beside the target and swap, keeping the last good copy, so a reboot mid-write loses at most one step.
function M.save(entry)
  local tmp, bak = FILE .. ".tmp", FILE .. ".bak"
  local handle = fs.open(tmp, "w")
  if not handle then return false end
  handle.write(textutils.serialise(entry))
  handle.close()
  if fs.exists(bak) then fs.delete(bak) end
  if fs.exists(FILE) then fs.move(FILE, bak) end
  fs.move(tmp, FILE)
  return true
end

function M.load()
  return read(FILE) or read(FILE .. ".bak")
end

function M.clear()
  for _, suffix in ipairs({ "", ".bak", ".tmp" }) do
    if fs.exists(FILE .. suffix) then fs.delete(FILE .. suffix) end
  end
end

--- A unique match id: the time, and a random tail in case two matches start in one millisecond.
function M.newId()
  return string.format("%.0f-%04x", os.epoch("utc"), math.random(0, 0xFFFF))
end

--- A small seeded generator for games with chance in them. Same seed, same numbers, so any match can be replayed.
--- trackedRng also returns a function that says where the generator has got to: trackedRng(position - 1) carries on from
-- exactly there, so a saved game keeps the numbers it would have had.
function M.trackedRng(seed)
  local state = seed % 2147483646 + 1
  return function(n)
    state = state * 16807 % 2147483647 -- small enough to stay exact in a double
    local value = state - 1
    if n then return value % n + 1 end
    return value / 2147483646
  end, function() return state end
end

function M.rng(seed)
  return (M.trackedRng(seed))
end

return M
