-- run.lua
-- Runs the casino's rules tests. They are pure Lua: no monitor, no ccvault, no Minecraft.
--   lua5.1 Tests/run.lua                 every Tests/*_test.lua (CI runs this before publishing the deploy index)
-- Also runs inside the emulator through tools/casinotest/unit.mjs in craftos-agent.
-- A return outside a game's target range fails the run, so a wrong paytable cannot ship.

local root = (arg and arg[0] or ""):match("^(.*)[/\\]Tests[/\\]run%.lua$") or "."
package.path = table.concat({
  root .. "/Shared/?.lua",
  root .. "/Tests/?.lua",
}, ";") .. ";" .. package.path

-- Each game's rules live in its own folder, the root of its computer once installed
for _, game in ipairs({
  "Arcade", "Baccarat", "Blackjack", "CasinoHub", "CrazyEights", "HiLo", "HorseRacing", "PokerTable",
  "Roulette", "Slots", "ThreeCardPoker", "UltimateHoldem", "VideoPoker",
}) do
  package.path = root .. "/Games/" .. game .. "/?.lua;" .. package.path
end

local testing = require("testing")

local listed = {}
local files = rawget(_G, "TEST_FILES")
if files then
  listed = files
else
  local pipe = io.popen('ls "' .. root .. '/Tests"')
  for name in pipe:lines() do
    if name:match("_test%.lua$") then listed[#listed + 1] = name:gsub("%.lua$", "") end
  end
  pipe:close()
end

for _, name in ipairs(listed) do
  require(name)
end

local failed = testing.finish()
if os.exit and not rawget(_G, "TEST_FILES") then os.exit(failed > 0 and 1 or 0) end
return failed
