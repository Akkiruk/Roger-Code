-- gearlocker/node.lua
-- A node only lends its chests to the locker computer, which links to it through the ender modem (vhcctweaks 2.2.36)
-- and uses them as its own. So it runs nothing but this: stay on, and answer when the locker asks who is out there.

local M = {}

M.PROTOCOL = "gearlocker.v1"

local function enderModem()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") and not name:match("^%d+:") then
      local ok, wireless = pcall(peripheral.call, name, "isWireless")
      if ok and wireless then return name end
    end
  end
end

local function show(modem)
  local chests = 0
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "inventory") then chests = chests + 1 end
  end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("GEAR LOCKER NODE")
  print("")
  print("This is computer " .. os.getComputerID() .. ".")
  print("Lending " .. chests .. " chests to the locker.")
  print("")
  if modem then
    print("On the locker computer, press S to run")
    print("setup again and it finds this node.")
  else
    term.setTextColor(colors.orange)
    print("No ender modem here. Put one on this computer:")
    print("the locker reaches its chests through it.")
  end
end

function M.run()
  if not os.getComputerLabel() then pcall(os.setComputerLabel, "Gear Locker node " .. os.getComputerID()) end
  local modem = enderModem()
  local hello = { kind = "node", id = os.getComputerID() }
  if modem then
    pcall(rednet.open, modem)
    pcall(rednet.broadcast, hello, M.PROTOCOL)
  end
  show(modem)
  local redraw = os.startTimer(10)
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "rednet_message" and c == M.PROTOCOL and type(b) == "table" and b.kind == "who" then
      pcall(rednet.send, a, hello, M.PROTOCOL)
    elseif event == "peripheral" or event == "peripheral_detach" or (event == "timer" and a == redraw) then
      if event == "timer" then redraw = os.startTimer(10) end
      local found = enderModem()
      if found and found ~= modem then pcall(rednet.open, found) end
      modem = found
      show(modem)
    end
  end
end

return M
