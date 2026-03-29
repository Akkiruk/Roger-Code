-- manifest-key: sound_browser
-- manifest-name: Sound Browser
-- manifest-category: Utilities
-- Browse the pack's generated sound catalog and save favorites.

local updater = require("lib.updater")

local ROOT = fs.getDir(shell.getRunningProgram())
local PROGRAM = nil
local args = { ... }

if ROOT == "" and shell.dir then
  ROOT = shell.dir()
end

PROGRAM = ROOT ~= "" and fs.combine(ROOT, "sound_browser.lua") or "sound_browser.lua"

updater.checkForUpdates()
shell.run(PROGRAM, unpack(args))
