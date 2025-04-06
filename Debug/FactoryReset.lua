-- FactoryReset.lua
-- This script will wipe all data and reset the computer to its factory state.

local function factoryReset()
    print("WARNING: This will delete all files and reboot the computer.")
    print("Type 'YES' to confirm.")
    local confirmation = read()

    if confirmation == "YES" then
        print("Deleting all files...")
        -- Delete all files in the root directory
        for _, file in ipairs(fs.list("/")) do
            if file ~= "rom" then -- Do not delete the ROM directory
                fs.delete(file)
            end
        end

        print("Factory reset complete. Rebooting...")
        os.reboot()
    else
        print("Factory reset canceled.")
    end
end

factoryReset()