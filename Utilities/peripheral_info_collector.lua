-- Gathers detailed information about all attached peripherals, including methods and documentation,
-- logs it to a file, and uploads the log.

local fs = require("fs")
local uploader -- Will be loaded later if System.uploadlogs is available

-- Configuration
local LOG_FILE_PATH = "peripheral_info.log"
local UPLOAD_RECIPIENT = nil  -- resolved from ccvault host below
local DEBUG_MODE = true -- Set to true for verbose console output during script execution

-- Resolve upload recipient from ccvault host (who placed this computer)
if ccvault and type(ccvault.getHostName) == "function" then
    local ok, name = pcall(ccvault.getHostName)
    if ok and name and type(name) == "string" and name ~= "" then
        UPLOAD_RECIPIENT = name
    end
end

local function script_print(message)
    if DEBUG_MODE then
        print(message)
    end
end

-- Function to write to the log file
local logFileHandle = nil
local function log_message(message)
    if logFileHandle then
        logFileHandle.writeLine(tostring(message))
    else
        print("Error: Log file not open.")
    end
end

-- Safe call wrapper for peripheral methods
local function safePeripheralCall(peripheral, methodName, ...)
    if not peripheral or type(peripheral[methodName]) ~= "function" then
        return false, "Method " .. tostring(methodName) .. " does not exist or is not a function"
    end
    return pcall(peripheral[methodName], peripheral, ...) -- Pass peripheral as 'self'
end

-- Main function to collect peripheral information
local function collectPeripheralInfo()
    script_print("Starting peripheral information collection...")
    logFileHandle = fs.open(LOG_FILE_PATH, "w")
    if not logFileHandle then
        print("Error: Could not open log file '" .. LOG_FILE_PATH .. "' for writing.")
        return false
    end

    log_message("Peripheral Information Log - " .. os.date())
    log_message("==========================================")

    local peripheralNames = peripheral.getNames()
    if not peripheralNames or #peripheralNames == 0 then
        log_message("No peripherals attached.")
        script_print("No peripherals found.")
        logFileHandle.close()
        logFileHandle = nil
        return true -- No peripherals is not an error for collection itself
    end

    script_print("Found peripherals: " .. table.concat(peripheralNames, ", "))

    for i, name in ipairs(peripheralNames) do
        log_message("\n--- Peripheral: " .. name .. " ---")
        script_print("Scanning peripheral: " .. name)

        local pType = peripheral.getType(name)
        log_message("Type: " .. (pType or "unknown"))

        local p = peripheral.wrap(name)
        if not p then
            log_message("Could not wrap peripheral: " .. name)
            script_print("Error wrapping peripheral: " .. name)
            goto continue_peripheral -- Skips to the next iteration
        end

        -- Get general documentation for the peripheral
        log_message("\n  General Documentation:")
        local hasGeneralDoc = false
        local success, doc = safePeripheralCall(p, "getDocumentation")
        if success and doc then
            log_message("    getDocumentation():\n      " .. textutils.serialize(doc, {compact=false}):gsub("\n", "\n      "))
            hasGeneralDoc = true
        end
        success, doc = safePeripheralCall(p, "help")
        if success and doc then
            log_message("    help():\n      " .. textutils.serialize(doc, {compact=false}):gsub("\n", "\n      "))
            hasGeneralDoc = true
        end
        if not hasGeneralDoc then
            log_message("    No general documentation found.")
        end

        -- Get methods
        local methods = peripheral.getMethods(name)
        if methods and #methods > 0 then
            log_message("\n  Methods:")
            for _, methodName in ipairs(methods) do
                log_message("    - " .. methodName)
                script_print("  Checking method: " .. methodName .. " for " .. name)

                -- Get documentation for each method
                local hasMethodDoc = false
                success, doc = safePeripheralCall(p, "getDocumentation", methodName)
                if success and doc then
                    log_message("      getDocumentation(\"" .. methodName .. "\"):\n        " .. textutils.serialize(doc, {compact=false}):gsub("\n", "\n        "))
                    hasMethodDoc = true
                else
                    if DEBUG_MODE and doc then script_print("    getDocumentation("..methodName..") error: " .. tostring(doc)) end
                end
                
                success, doc = safePeripheralCall(p, "help", methodName)
                if success and doc then
                    log_message("      help(\"" .. methodName .. "\"):\n        " .. textutils.serialize(doc, {compact=false}):gsub("\n", "\n        "))
                    hasMethodDoc = true
                else
                     if DEBUG_MODE and doc then script_print("    help("..methodName..") error: " .. tostring(doc)) end
                end

                if not hasMethodDoc then
                    log_message("      No specific documentation found for this method.")
                end
            end
        else
            log_message("  No methods listed for this peripheral.")
        end
        
        ::continue_peripheral::
    end

    logFileHandle.close()
    logFileHandle = nil
    script_print("Peripheral information collection complete. Log saved to " .. LOG_FILE_PATH)
    return true
end

-- Function to upload the log file
local function uploadLog()
    script_print("Attempting to load System.uploadlogs API...")
    local success_load, mod = pcall(require, "System.uploadlogs")
    if success_load and mod and mod.uploadMultipleFilesAPI then
        uploader = mod
        script_print("System.uploadlogs API loaded successfully.")
    else
        print("Failed to load System.uploadlogs API: " .. tostring(mod))
        script_print("Uploadlogs API load error: " .. tostring(mod))
        return
    end

    if not fs.exists(LOG_FILE_PATH) or fs.getSize(LOG_FILE_PATH) == 0 then
        print("Log file is empty or does not exist. Skipping upload.")
        script_print("Log file empty or missing. Skipping upload.")
        return
    end

    if not UPLOAD_RECIPIENT then
        print("No upload recipient — ccvault host not available.")
        return
    end

    print("Attempting to upload log file: " .. LOG_FILE_PATH .. " to " .. UPLOAD_RECIPIENT)
    local uploadedLinks, uploadSuccess = uploader.uploadMultipleFilesAPI({LOG_FILE_PATH}, UPLOAD_RECIPIENT, false)
    
    if uploadSuccess then
        print("Log file uploaded successfully.")
        if uploadedLinks and uploadedLinks[LOG_FILE_PATH] then
            print(LOG_FILE_PATH .. " -> " .. uploadedLinks[LOG_FILE_PATH].standard)
        else
            print("Uploaded, but no link returned for the log file.")
        end
    else
        print("Failed to upload log file.")
        script_print("Upload failed.")
    end
end

-- Run the collection and upload
if collectPeripheralInfo() then
    uploadLog()
end

print("Script finished.")
