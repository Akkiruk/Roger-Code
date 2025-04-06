local troubleshooting = {}

-- Basic connectivity check
function troubleshooting.checkMonitor()
    local monitor = peripheral.find("monitor")
    if not monitor then
        return false, "No monitor found"
    end
    
    -- Try basic operations to ensure monitor is responsive
    local ok, err = pcall(function()
        monitor.getCursorPos()
        monitor.getSize()
    end)
    
    if not ok then
        return false, "Monitor not responding: " .. tostring(err)
    end
    
    return true, monitor
end

-- Recovery attempts for common issues
function troubleshooting.attemptRecovery(issue)
    if issue == "monitor" then
        -- Try re-detecting monitor
        os.sleep(1)
        return troubleshooting.checkMonitor()
    end
    return false, "No recovery method for: " .. tostring(issue)
end

-- Generate diagnostic info
function troubleshooting.getDiagnostics()
    local info = {
        timestamp = os.date(),
        computerID = os.getComputerID(),
        peripherals = peripheral.getNames(),
    }
    return info
end

return troubleshooting