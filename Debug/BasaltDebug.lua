-- Initialize Basalt at the start
local basalt = require("basalt")

-- Global error handler for safer method calls
local function safeCall(func, ...)
    if not func then return nil end
    local success, result = pcall(func, ...)
    return success and result or nil
end

-- Initialize frames
local mainFrame = nil -- Will be initialized in runDebug
local testFrame = nil -- Will be initialized in runDebug

local function createLogFile()
    local logFile = fs.open("basalt_debug.log", "w")
    return logFile
end

local logFile = createLogFile()
local debugResults = {}

local function log(text, color)
    table.insert(debugResults, {text = text, color = color})
    if logFile then
        logFile.writeLine(text)
    end
end

local function printColored(text, color)
    term.setTextColor(color or colors.white)
    print(text)
    term.setTextColor(colors.white)
    log(text, color)
end

-- Function to check if a value exists
local function checkExists(value, name)
    if value then
        printColored("[✓] " .. name .. " exists", colors.lime)
        return true
    else
        printColored("[✗] " .. name .. " not found", colors.red)
        return false
    end
end

-- Function to check if a method exists
local function checkMethod(object, methodName, objectName)
    if object == nil then
        printColored("[✗] Cannot check method: " .. objectName .. " is nil", colors.red)
        return false
    end
    if type(object[methodName]) == "function" then
        printColored("[✓] " .. objectName .. ":" .. methodName .. "() exists", colors.lime)
        return true
    else
        printColored("[✗] " .. objectName .. ":" .. methodName .. "() not found", colors.red)
        return false
    end
end

-- Add validation testing function
local function validateMethod(object, methodName, objectName)
    if object == nil then
        return {exists = false, works = false, error = "Object is nil"}
    end
    
    local result = {exists = false, works = false, error = nil}
    
    if type(object[methodName]) ~= "function" then
        return result
    end
    
    result.exists = true
    
    -- Basic validation tests for common methods
    local success, err = pcall(function()
        if methodName == "setText" then
            object:setText("test")
        elseif methodName == "getValue" then
            object:getValue()
        elseif methodName == "setProgress" then
            object:setProgress(50)
        elseif methodName == "setValue" then
            object:setValue(true)
        end
    end)
    
    result.works = success
    if not success then
        result.error = err
    end
    
    return result
end

-- Comprehensive list of Basalt methods to test
local methodGroups = {
    core = {
        "getMainFrame",
        "createFrame",
        "schedule",
        "stop",
        "run",
        "update"
    },
    frame = {
        "addButton",
        "addLabel",
        "addInput",
        "addCheckbox",
        "addDropdown",
        "addList",
        "addProgram",
        "addScrollbar",
        "addSlider",
        "addFrame",
        "setPosition",
        "setSize",
        "setBackground",
        "setForeground",
        "setTerm"
    },
    elements = {
        button = {
            "getText", "setText", "onClick", "setForeground"
        },
        label = {
            "getText", "setText", "setForeground", "setBackground"
        },
        input = {
            "onChange"
        },
        checkbox = {
            "onChange"
        }
    },
    plugins = {
        "animation",
        "canvas",
        "debug",
        "reactive",
        "state",
        "theme",
        "xml"
    }
}

-- Create scrollable debug UI
local function createDebugUI()
    if not mainFrame then
        mainFrame = basalt.getMainFrame() -- Try to get main frame if not set
        if not mainFrame then
            printColored("[✗] Failed to create debug UI: couldn't get main frame", colors.red)
            return nil
        end
    end

    -- Reset the frame
    mainFrame:removeAll()
    mainFrame:setBackground(colors.black)
    mainFrame:show() -- Ensure visibility
    
    -- Title
    local title = mainFrame:addLabel()
    if title then
        title:setText("Basalt Debug Results")
            :setPosition(2, 1)
            :setForeground(colors.yellow)
    end

    -- Create scrollable frame for results
    local resultFrame = mainFrame:addFrame()
    if not resultFrame then
        printColored("[✗] Failed to create result frame", colors.red)
        return nil
    end

    -- Set fixed position and size values for the scrollable area
    local w, h = term.getSize()
    resultFrame:setPosition(1, 3)
        :setSize(w - 2, h - 6)
        :setScrollable(true)
        :show() -- Explicitly show the frame

    -- Add results
    local yPos = 1
    for _, result in ipairs(debugResults) do
        local label = resultFrame:addLabel()
        if label then
            label:setText(result.text)
                :setPosition(1, yPos)
                :setForeground(result.color)
                :show() -- Ensure label visibility
            yPos = yPos + 1
        end
    end

    -- Make the result frame focusable for keyboard navigation
    resultFrame:setFocus()

    -- Enable scrolling with both mouse wheel and keyboard
    resultFrame:onKey(function(self, event, key)
        local currentOffset = self:getOffset()
        if key == keys.up then
            self:setOffset(currentOffset - 1)
        elseif key == keys.down then
            self:setOffset(currentOffset + 1)
        end
    end)

    resultFrame:onScroll(function(self, direction)
        local currentOffset = self:getOffset()
        self:setOffset(currentOffset + direction)
    end)

    -- Navigation controls at fixed position
    local controlsFrame = mainFrame:addFrame()
    if controlsFrame then
        controlsFrame:setPosition(1, h - 2)
            :setSize(w, 3)
            :setBackground(colors.black)

        local exitBtn = controlsFrame:addButton()
        if exitBtn then
            exitBtn:setText("Exit")
                :setPosition(2, 1)
                :setSize(6, 1)
                :onClick(function() 
                    if logFile then
                        logFile.flush()
                        logFile.close()
                        logFile = nil
                    end
                    basalt.stop() 
                end)
        end

        local saveBtn = controlsFrame:addButton()
        if saveBtn then
            saveBtn:setText("Save Log")
                :setPosition(10, 1)
                :setSize(8, 1)
                :onClick(function()
                    local timestamp = os.date("%Y%m%d_%H%M%S")
                    local newLog = fs.open("basalt_debug_" .. timestamp .. ".log", "w")
                    for _, result in ipairs(debugResults) do
                        newLog.writeLine(result.text)
                    end
                    newLog.close()
                    local savedLabel = controlsFrame:addLabel()
                    if savedLabel then
                        savedLabel:setText("Log saved!")
                            :setPosition(20, 1)
                            :setForeground(colors.lime)
                    end
                end)
        end
    end

    return mainFrame
end

-- Enhanced element testing function
local function testElement(elementType, methods)
    printColored("\nTesting " .. elementType .. " element:", colors.yellow)
    if not testFrame then
        printColored("[✗] No test frame available", colors.red)
        return
    end
    
    local addFunc = testFrame["add" .. elementType:sub(1,1):upper() .. elementType:sub(2)]
    if type(addFunc) ~= "function" then
        printColored("[✗] Add function not found for " .. elementType, colors.red)
        return
    end
    
    local element = addFunc(testFrame)
    if not element then
        printColored("[✗] Failed to create " .. elementType, colors.red)
        return
    end
    
    for _, method in ipairs(methods) do
        local result = validateMethod(element, method, elementType)
        if result.exists then
            if result.works then
                printColored("[✓] " .. elementType .. ":" .. method .. "() works", colors.lime)
            else
                printColored("[!] " .. elementType .. ":" .. method .. "() exists but failed: " .. (result.error or "unknown error"), colors.orange)
            end
        else
            printColored("[✗] " .. elementType .. ":" .. method .. "() not found", colors.red)
        end
    end
end

-- Monitor testing
local function checkMonitors()
    print("\nChecking for Connected Monitors...")
    local monitors = {}
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "monitor" then
            monitors[side] = peripheral.wrap(side)
            printColored("[✓] Monitor found on " .. side .. " side", colors.lime)
        end
    end
    
    if next(monitors) == nil then
        printColored("[!] No monitors detected", colors.orange)
        return nil
    end
    
    return monitors
end

-- Function to test monitor display
local function createMonitorTestUI(side)
    if not side then
        printColored("[✗] No monitor side specified", colors.red)
        return nil
    end

    print("\nTesting monitor: " .. side)
    local monitor = peripheral.wrap(side)
    if not monitor then
        printColored("[✗] Failed to wrap monitor: " .. side, colors.red)
        return nil
    end

    local monitorFrame = basalt.createFrame()
    if not monitorFrame then
        printColored("[✗] Failed to create monitor frame", colors.red)
        return nil
    end

    local success = pcall(function()
        monitorFrame:setTerm(monitor)
    end)
    
    if not success then
        printColored("[✗] Failed to set terminal for monitor: " .. side, colors.red)
        return nil
    end
    
    local w, h = monitor.getSize()
    
    monitorFrame:addLabel()
        :setText("Monitor Test - " .. side)
        :setPosition(2, 2)
    
    monitorFrame:addLabel()
        :setText("Size: " .. w .. "x" .. h)
        :setPosition(2, 3)
    
    -- Store a reference to the log message instead of trying to write immediately
    local testBtn = monitorFrame:addButton()
    testBtn:setText("Test Button")
        :setPosition(2, 5)
        :setSize(10, 1)
        :onClick(function()
            -- Add to debugResults instead of trying to write to file directly
            table.insert(debugResults, {
                text = "Monitor button clicked on " .. side .. "!",
                color = colors.lime
            })
            -- Update the display to show the new message
            if mainFrame then
                createDebugUI()
            end
        end)

    return monitorFrame
end

-- Main debug flow
local function runDebug()
    print("Starting Basalt Debug Check...")
    print("--------------------------")

    if not basalt then
        printColored("[✗] Basalt is not properly initialized", colors.red)
        return
    end

    -- Initialize main frame with explicit error handling
    local success, result = pcall(function()
        -- First try to get the main frame
        mainFrame = basalt.createFrame()
        if not mainFrame then
            error("Failed to create main frame")
        end
        
        -- Initialize and configure main frame
        mainFrame:setBackground(colors.black)
        mainFrame:setSize("parent.w", "parent.h")
        mainFrame:show()
        
        -- Initialize test frame
        testFrame = basalt.createFrame()
        if not testFrame then
            error("Failed to create test frame")
        end
        
        -- Configure test frame
        testFrame:setSize("parent.w", "parent.h")
        testFrame:show()
    end)

    if not success then
        printColored("[✗] Frame initialization failed: " .. tostring(result), colors.red)
        return
    end

    -- Test core functionality
    print("\nTesting Core Functionality:")
    for _, method in ipairs(methodGroups.core) do
        checkMethod(basalt, method, "basalt")
    end

    -- Test frame methods
    print("\nTesting Frame Methods:")
    for _, method in ipairs(methodGroups.frame) do
        checkMethod(testFrame, method, "frame")
    end

    -- Test plugins
    print("\nTesting Plugin System:")
    for _, plugin in ipairs(methodGroups.plugins) do
        local exists = basalt[plugin] ~= nil
        if exists then
            printColored("[✓] " .. plugin .. " plugin exists", colors.lime)
        else
            printColored("[✗] " .. plugin .. " plugin not found", colors.red)
        end
    end

    -- Test each element type
    for elementType, methods in pairs(methodGroups.elements) do
        testElement(elementType, methods)
    end

    -- Test monitors
    local monitors = checkMonitors()
    local monitorFrames = {}
    
    if monitors then
        for side, _ in pairs(monitors) do
            monitorFrames[side] = createMonitorTestUI(side)
        end
    end

    print("\nDebug Check Complete!")
    print("Results saved to basalt_debug.log")
    print("\nPress Enter to view scrollable results...")
    read() -- Wait for Enter

    -- Clear the terminal before showing UI
    term.clear()
    term.setCursorPos(1,1)

    -- Create and show the debug UI
    local debugUI = createDebugUI()
    if debugUI then
        -- Start Basalt's event loop directly
        basalt.run()
    else
        printColored("[✗] Failed to create debug UI", colors.red)
        -- Close log if UI creation failed
        if logFile then
            logFile.flush()
            logFile.close()
            logFile = nil
        end
    end
end

-- Run the debug process
runDebug()