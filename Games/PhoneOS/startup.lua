local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" and shell.dir then
  ROOT = shell.dir()
end

local PROGRAM = ROOT ~= "" and fs.combine(ROOT, "phone_os.lua") or "phone_os.lua"
local ok, err = pcall(shell.run, PROGRAM)

if not ok then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1, 1)
  print("Pocket OS crashed.")
  print("")
  term.setTextColor(colors.white)
  print(tostring(err))
  print("")
  print("Press any key to close.")
  os.pullEvent("key")
end
