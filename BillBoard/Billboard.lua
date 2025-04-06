local basalt = require("basalt")
local ideas = require("ideas")
local config = require("config")
local troubleshooting = require("troubleshooting")

-- Debug logging helper
local function log(msg)
    local f = fs.open("billboard_debug.log", "a")
    f.write("[" .. os.date() .. "] " .. tostring(msg) .. "\n")
    f.close()
end

-- Initialize peripherals and error handling
local function initializeMonitor()
    log("Searching for monitor...")
    local monitor = peripheral.find("monitor")
    if not monitor then
        log("No monitor found!")
        error("Monitor peripheral not found")
    end
    
    log("Found monitor, setting scale to " .. tostring(config.textScale))
    monitor.setTextScale(config.textScale)
    monitor.clear()
    monitor.setCursorPos(1,1)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    return monitor
end

-- UI Management
local function showSection(section)
    if not section then return end
    section:setVisible(true)
    section:setBackground(colors.black)
    :setTransparency(1)
    
    section:animate()
    :setTransparency(0, 0.5, "easeOut")
    :start()

    -- Add slight floating effect to elements
    for name, element in pairs(section.elements) do
        if element then 
            local origY = element:getPosition()
            element:setVisible(true)
            element:setTransparency(1)
            element:setPosition(element:getPosition(), origY + 2)
            element:animate()
            :setTransparency(0, 0.5, "easeOut")
            :sequence()
            :moveOffset(0, -2, 0.3, "easeOut")
            :start()
        end
    end
end

local function clearDynamicElements(frame)
    local children = frame:getChildren()
    if not children then return end
    local preserve = frame.elements or {}
    for _, child in pairs(children) do
        local shouldKeep = false
        for _, original in pairs(preserve) do
            if child == original then
                shouldKeep = true
                break
            end
        end
        if not shouldKeep then child:remove() end
    end
end

local function hideSection(section)
    if not section then return end
    -- Fade out then hide
    section:animate()
    :setTransparency(1, 0.5, "easeIn")
    :onDone(function()
        clearDynamicElements(section)
        for _, element in pairs(section.elements) do
            if element then element:setVisible(false) end
        end
        section:setVisible(false)
    end)
    :start()

    for _, element in pairs(section.elements) do
        if element then
            element:animate()
            :setTransparency(1, 0.5, "easeIn")
            :start()
        end
    end
end

-- Ideas Management
local function setupIdeaSubmission(frame, section, w, h, ui)  -- Add ui parameter
    local recentIdeas = frame:addList()
    recentIdeas:setPosition(2, 8)
    :setSize(w - 4, 6)
    :setBackground(colors.black)
    :setForeground(colors.lightGray)
    :setSelectedBackground(colors.gray)
    :setSelectedForeground(colors.white)
    :setVisible(false)

    local function updateRecentIdeas()
        recentIdeas:clear()
        local recent = ideas.getRecent(3)
        if #recent > 0 then
            recentIdeas:addItem(" Recent community ideas:")
            for _, idea in ipairs(recent) do
                local timestamp = os.date("%H:%M", idea.timestamp / 1000)
                recentIdeas:addItem(string.format(" • [%s] %s", timestamp, idea.text))
            end
        end
    end

    updateRecentIdeas()
    frame.elements.recentIdeas = recentIdeas

    local button = frame:addButton()
    button:setText("Share Your Idea")
    :setPosition(2, h - 3)
    :setSize(20, 3)
    :setBackground(section.color)
    :setForeground(colors.white)
    :setVisible(false)

    button:onClick(function()
        ui.inputFrame:setVisible(true)
        ui.inputField:setValue("")
        ui.timeoutBar:setProgress(100)
        ui.timeoutWarning:setVisible(true)

        -- Start timeout countdown with pulsing effect when low
        local timeoutDuration = 30 -- seconds
        local startTime = os.epoch("local")
        local warningThreshold = 10 -- seconds

        basalt.schedule(function()
            while true do
                local elapsed = (os.epoch("local") - startTime) / 1000
                local remaining = timeoutDuration - elapsed
                if remaining <= 0 then
                    ui.inputFrame:setVisible(false)
                    ui.timeoutWarning:setVisible(false)
                    break
                end
                
                local progress = (remaining / timeoutDuration) * 100
                ui.timeoutBar:setProgress(progress)
                
                -- Pulse red when time is running low
                if remaining <= warningThreshold then
                    ui.timeoutBar:setProgressColor(
                        math.floor(elapsed * 4) % 2 == 0 
                        and colors.red 
                        or colors.orange
                    )
                end
                
                os.sleep(0.1)
            end
        end)

        ui.submitBtn:onClick(function()
            local input = ui.inputField:getValue()
            if #input > 0 then
                ideas.save(input)
                updateRecentIdeas()
                ui.inputFrame:setVisible(false)
                ui.timeoutWarning:setVisible(false)
                -- Show confirmation on the monitor
                showConfirmation(
                    ui.display, 
                    "Thanks for your idea!\nIt will be reviewed shortly.",
                    2
                )
            end
        end)

        -- Also submit on Enter key
        ui.inputField:onKey(function(self, key)
            if key == keys.enter then
                ui.submitBtn:click()
            end
        end)
    end)

    frame.elements.interactive = button
    return button, updateRecentIdeas
end

-- Main Application Setup
local function setupDisplay()
    local mainFrame = basalt.getMainFrame()
    local monitor = initializeMonitor()
    local w, h = monitor.getSize()

    -- Create the monitor display frame
    local display = mainFrame:addFrame()
    display:setSize(w, h)
    :setBackground(colors.black)
    :setMonitor(peripheral.getName(monitor))

    -- Enhanced terminal input frame
    local terminalFrame = mainFrame:addFrame()
    terminalFrame:setBackground(colors.black)
    :setSize(term.getSize())

    local inputFrame = terminalFrame:addFrame()
    inputFrame:setSize("parent.w", "parent.h")
    :setBackground(colors.black)
    :setVisible(false)

    -- Add instruction label
    local instructionLabel = inputFrame:addLabel()
    instructionLabel:setText("=== Share Your Automation Idea ===\n\nType your idea below and click Submit\nOr press Enter to save")
    :setPosition(2, 1)
    :setSize("parent.w - 4", 2)
    :setForeground(colors.yellow)
    :setBackground(colors.black)

    local inputField = inputFrame:addInput()
    inputField:setPosition(2, 6)
    :setSize("parent.w - 4", 1)
    :setBackground(colors.gray)
    :setForeground(colors.white)
    :setPlaceholder("Type your idea here...")

    local submitBtn = inputFrame:addButton()
    submitBtn:setText("Submit")
    :setPosition(2, 8)
    :setSize(8, 1)
    :setBackground(colors.green)
    :setForeground(colors.white)

    -- Add warning label for timeout
    local timeoutWarning = inputFrame:addLabel()
    timeoutWarning:setText("Time remaining to submit:")
    :setPosition(2, "parent.h - 3")
    :setSize("parent.w - 4", 1)
    :setForeground(colors.yellow)
    :setBackground(colors.black)

    -- Update timeout bar position to be right below warning
    local timeoutBar = inputFrame:addProgressBar()
    timeoutBar:setPosition(2, "parent.h - 2")
    :setSize("parent.w - 4", 1)
    :setProgress(100)
    :setProgressColor(colors.orange)
    :setBackgroundColor(colors.gray)

    return {
        display = display,
        inputFrame = inputFrame,
        inputField = inputField,
        submitBtn = submitBtn,
        timeoutBar = timeoutBar,
        timeoutWarning = timeoutWarning,
        w = w,
        h = h
    }
end

local function setupSections(ui)
    local sections = {}
    for i, sectionConfig in ipairs(config.sections) do
        local frame = ui.display:addFrame()
        frame:setSize(ui.w, ui.h)
        :setBackground(colors.black)
        :setVisible(false)

        local title = frame:addLabel()
        title:setText(sectionConfig.title)
        :setPosition(2, 2)
        :setSize(ui.w - 4, 3)
        :setForeground(sectionConfig.color)
        :setVisible(true)

        local description = frame:addLabel()
        description:setText(sectionConfig.description)
        :setPosition(2, 6)
        :setSize(ui.w - 4, 3)
        :setForeground(colors.white)
        :setVisible(true)

        frame.elements = {
            title = title,
            description = description
        }

        if sectionConfig.isInteractive then
            local button, updateIdeas = setupIdeaSubmission(frame, sectionConfig, ui.w, ui.h, ui)  -- Pass ui
            button:onClick(function()
                ui.inputFrame:setVisible(true)
                ui.inputField:setValue("")

                ui.submitBtn:onClick(function()
                    local input = ui.inputField:getValue()
                    if #input > 0 then
                        ideas.save(input)
                        updateIdeas()
                        ui.inputFrame:setVisible(false)
                    end
                end)
            end)
        end

        sections[i] = frame
    end
    return sections
end

-- Add this function near other UI functions
local function showConfirmation(display, text, duration)
    local w, h = display:getSize()
    local popup = display:addFrame()
    popup:setSize(w - 10, 5)
    :setPosition(6, math.floor(h/2) - 2)
    :setBackground(colors.green)
    :setZ(100)  -- Ensure it's on top

    local msg = popup:addLabel()
    msg:setText(text)
    :setPosition(2, 2)
    :setForeground(colors.white)
    :setBackground(colors.green)

    -- Fade in
    popup:setTransparency(1)
    popup:animate()
    :setTransparency(0, 0.3, "easeOut")
    :start()

    -- Schedule removal
    basalt.schedule(function()
        os.sleep(duration or 2)
        popup:animate()
        :setTransparency(1, 0.3, "easeIn")
        :onDone(function() 
            popup:remove()
        end)
        :start()
    end)
end

-- Main execution
local function main()
    log("Starting Billboard application")
    
    local ok, err = pcall(ideas.init)
    if not ok then
        log("Failed to initialize ideas: " .. tostring(err))
        error("Failed to initialize ideas storage: " .. tostring(err))
    end

    log("Setting up display")
    local ui = setupDisplay()
    if not ui then
        log("Failed to setup display")
        error("Failed to setup display")
    end

    log("Setting up sections")
    local sections = setupSections(ui)
    local currentSection = 1
    
    log("Showing first section")
    showSection(sections[1])

    parallel.waitForAll(
        function()
            local ok, err = pcall(function()
                basalt.run()
            end)
            if not ok then
                log("Basalt error: " .. tostring(err))
                error("Basalt error: " .. tostring(err))
            end
        end,
        function()
            while true do
                os.sleep(config.displayTime)
                hideSection(sections[currentSection])
                currentSection = currentSection % #sections + 1
                log("Switching to section " .. currentSection)
                showSection(sections[currentSection])
            end
        end
    )
end

log("Starting main function")
main()