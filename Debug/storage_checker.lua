local function formatBytes(bytes)
    local units = {"B", "KB", "MB", "GB"}
    local size = bytes
    local unit = 1
    
    while size > 1024 and unit < #units do
        size = size / 1024
        unit = unit + 1
    end
    
    return string.format("%.2f %s", size, units[unit])
end

-- Get all available drives
local function getDrives()
    local drives = {}
    for _, side in ipairs(peripheral.getNames()) do
        if disk.isPresent(side) then
            table.insert(drives, {name = side, isDisk = true})
        end
    end
    table.insert(drives, {name = "root", isDisk = false})
    return drives
end

-- Get storage info for a path
local function getStorageInfo(path)
    local used = 0
    local files = fs.list(path)
    
    for _, file in ipairs(files) do
        local fullPath = fs.combine(path, file)
        if fs.isDir(fullPath) then
            used = used + getStorageInfo(fullPath)
        else
            used = used + fs.getSize(fullPath)
        end
    end
    
    return used
end

-- Print header
print("=== Storage Usage Report ===")
print()

-- Check each drive
for _, drive in ipairs(getDrives()) do
    local path = drive.isDisk and drive.name or ""
    print("Drive: " .. (drive.isDisk and drive.name or "Computer"))
    
    local freeSpace = drive.isDisk and disk.getSize(drive.name) or fs.getFreeSpace("/")
    local usedSpace = getStorageInfo(path)
    local totalSpace = usedSpace + freeSpace
    
    print("Total Space: " .. formatBytes(totalSpace))
    print("Used Space:  " .. formatBytes(usedSpace))
    print("Free Space:  " .. formatBytes(freeSpace))
    print("Usage:       " .. string.format("%.1f%%", (usedSpace / totalSpace) * 100))
    print()
end

print("Press any key to exit")
os.pullEvent("key")