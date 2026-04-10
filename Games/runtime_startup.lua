local supervisor = require("lib.roger_supervisor")

local ok, err = pcall(function()
  supervisor.run()
end)

if not ok then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1, 1)
  print("Roger supervisor crashed.")
  print("")
  term.setTextColor(colors.white)
  print(tostring(err))
  print("")
  print("See roger_supervisor.log for details.")
end