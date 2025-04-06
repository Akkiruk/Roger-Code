local basalt = require("basalt")

-- Initialize the monitor
local monitor = peripheral.find("monitor")
if not monitor then
    print("No monitor found! Please attach a monitor.")
    return
end

-- Clear and set monitor scale
monitor.setTextScale(1)
monitor.clear()

-- Create main frame
local mainFrame = basalt.createFrame()
    :setMonitor("monitor") -- Set output to monitor instead of terminal

-- Create title
local title = mainFrame:addLabel()
    :setText("Debug Test Interface")
    :setPosition(2, 1)
    :setSize(20, 1)

-- Create test buttons
local button1 = mainFrame:addButton()
    :setText("Test Button 1")
    :setPosition(2, 3)
    :setSize(12, 3)
    :onClick(function()
        title:setText("Button 1 Clicked!")
    end)

local button2 = mainFrame:addButton()
    :setText("Test Button 2")
    :setPosition(16, 3)
    :setSize(12, 3)
    :onClick(function()
        title:setText("Button 2 Clicked!")
    end)

-- Add status label
local statusLabel = mainFrame:addLabel()
    :setText("Status: Ready")
    :setPosition(2, 7)
    :setSize(26, 1)

-- Add test function button
local testFunc = mainFrame:addButton()
    :setText("Run Test")
    :setPosition(2, 9)
    :setSize(26, 3)
    :onClick(function()
        statusLabel:setText("Status: Running Test...")
        sleep(1)
        statusLabel:setText("Status: Test Complete!")
    end)

-- Add exit button
local exitButton = mainFrame:addButton()
    :setText("Exit")
    :setPosition(2, 13)
    :setSize(26, 1)
    :setBackground(colors.red)
    :onClick(function()
        basalt.stop()
    end)

-- Start the interface
basalt.autoUpdate()