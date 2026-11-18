-- gearshop/node.lua
-- A node: a computer that only lends its chests, monitors and detectors to the shop computer. The shop links to it through
-- its ender modem and uses everything attached here as its own (vhcctweaks 2.2.36), so a node runs no shop code at all.
-- All it does is stay on, say what it is, and answer when the shop's setup page asks who is out there.

local M = {}

local PROTOCOL = "gearshop.v1"

local function enderModem()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") and not name:match("^%d+:") then
      local ok, wireless = pcall(peripheral.call, name, "isWireless")
      if ok and wireless then return name end
    end
  end
  return nil
end

local function show(modem)
  local attached = { inventory = 0, monitor = 0, playerDetector = 0 }
  for _, name in ipairs(peripheral.getNames()) do
    for kind in pairs(attached) do
      if peripheral.hasType(name, kind) then attached[kind] = attached[kind] + 1 end
    end
  end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("GEAR SHOP NODE")
  print("")
  print("This is computer " .. os.getComputerID() .. ".")
  print("")
  print(("Lending %d inventories, %d monitors"):format(attached.inventory, attached.monitor))
  print(("and %d player detectors to the shop."):format(attached.playerDetector))
  print("")
  if modem then
    print("On the shop computer: page 5, then F to find")
    print("this node, or N and its number.")
  else
    term.setTextColor(colors.orange)
    print("No ender modem here. Put one on this computer:")
    print("the shop reaches a node through it.")
  end
end

--- Blank every monitor this node lends: whatever was on it (the installer's "UPDATED / Restarting..." screen, an older
-- program) must not linger. The shop draws on the ones it uses; one with no job yet it marks as not set up.
local function clearMonitors()
  for _, name in ipairs(peripheral.getNames()) do
    if not name:match("^%d+:") and peripheral.hasType(name, "monitor") then
      pcall(peripheral.call, name, "setBackgroundColor", colors.black)
      pcall(peripheral.call, name, "clear")
    end
  end
end

function M.run()
  if not os.getComputerLabel() then pcall(os.setComputerLabel, "Gear Shop node " .. os.getComputerID()) end
  clearMonitors()
  local modem = enderModem()
  if modem then
    pcall(rednet.open, modem)
    pcall(rednet.broadcast, { kind = "node", id = os.getComputerID() }, PROTOCOL)
  end
  show(modem)
  local redraw = os.startTimer(10)
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "rednet_message" and c == PROTOCOL and type(b) == "table" and b.kind == "who" then
      pcall(rednet.send, a, { kind = "node", id = os.getComputerID() }, PROTOCOL)
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
