-- manifest-name: Storage Check
-- manifest-description: Shows how much disk space this computer has, its drives, and its private vhcc folder.
-- Shows how much disk space this computer has, its drives, and its private vhcc folder. It only reads: nothing is written.

local VHCC_MIN_ENTRY_BYTES = 4096        -- the mod counts every file and folder as at least this
local VHCC_DEFAULT_LIMIT = 16 * 1048576  -- maxBytesPerComputer, which Lua has no way to read

local function bytesText(n)
    local digits = tostring(math.floor(n))
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return grouped .. " B"
end

local function sizeText(n)
    if n >= 1000000 then return string.format("%.2f MB", n / 1000000) end
    return string.format("%.1f KB", n / 1000)
end

local function row(label, n)
    print(string.format("  %-5s %-9s (%s)", label, sizeText(n), bytesText(n)))
end

--- Prints one drive. getCapacity is nil for read-only drives, which never reach here.
local function showDrive(title, path)
    print(title)
    local capacity = fs.getCapacity(path)
    local free = fs.getFreeSpace(path)
    if type(capacity) ~= "number" or type(free) ~= "number" then
        print("  size not reported")
        return
    end
    row("Size", capacity)
    row("Used", capacity - free)
    row("Free", free)
end

--- The space the mod counts against a vhcc folder. Sizes are walked from Lua, as the mod has no call for the total.
local function vhccUsage(folder)
    local used = 0
    for _, name in ipairs(vhcc.list(folder)) do
        local path = folder == "" and name or (folder .. "/" .. name)
        if name:sub(-1) == "/" then
            used = used + VHCC_MIN_ENTRY_BYTES + vhccUsage(path:sub(1, -2))
        else
            used = used + math.max(vhcc.getSize(path), VHCC_MIN_ENTRY_BYTES)
        end
    end
    return used
end

local function showVhcc()
    print("Private vhcc folder")
    if type(vhcc) ~= "table" then
        print("  not on this computer")
        return
    end
    if not vhcc.isAvailable() then
        print("  not available here")
        return
    end
    local ok, used = pcall(vhccUsage, "")
    if ok then row("Used", used) else print("  " .. tostring(used)) end
    print("  Limit " .. sizeText(VHCC_DEFAULT_LIMIT) .. " unless changed")
end

print("Storage on computer " .. os.getComputerID())
showDrive("Main disk", "/")
for _, name in ipairs(fs.list("/")) do
    if name ~= "rom" and fs.isDriveRoot(name) then
        showDrive("Drive /" .. name .. " (" .. tostring(fs.getDrive(name)) .. ")", name)
    end
end
showVhcc()
