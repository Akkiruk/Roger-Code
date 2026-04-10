-- manifest-key: sound_browser
-- manifest-name: Sound Browser
-- manifest-category: Utilities
-- Browse the pack's generated sound catalog and save favorites.

local ROOT = fs.getDir(shell.getRunningProgram())
local PROGRAM = nil
local args = { ... }

if ROOT == "" and shell.dir then
  ROOT = shell.dir()
end

PROGRAM = ROOT ~= "" and fs.combine(ROOT, "sound_browser.lua") or "sound_browser.lua"

shell.run(PROGRAM, unpack(args))
