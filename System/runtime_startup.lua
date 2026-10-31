-- Installed as startup.lua on every computer. This file must not depend on the packaged
-- libraries: when one of them is what broke, this is what brings the computer back.
local RECORD_FILE = ".installed_program"
local REPAIR_MARK = ".startup_repair"
local INSTALLER_PATH = "installer.lua"
local INSTALLER_URL = "https://raw.githubusercontent.com/Akkiruk/Roger-Code/main/System/installer.lua"
local RETRY_SECONDS = 60

local homeTerm = term.current()

local function resetTerminal()
  pcall(function()
    term.redirect(homeTerm)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorBlink(false)
    term.clear()
    term.setCursorPos(1, 1)
  end)
end

local function readText(path)
  local handle = fs.exists(path) and fs.open(path, "r") or nil
  if not handle then
    return nil
  end

  local raw = handle.readAll()
  handle.close()
  return raw
end

local function writeText(path, text)
  local ok, handle = pcall(fs.open, path, "w")
  if not ok or not handle then
    return false
  end

  handle.write(text)
  handle.close()
  return true
end

local function installedHash()
  local raw = readText(RECORD_FILE)
  local ok, record = pcall(textutils.unserialise, raw or "")
  if ok and type(record) == "table" then
    return record.package_hash or record.content_hash
  end
  return nil
end

local function ensureInstaller()
  if fs.exists(INSTALLER_PATH) then
    return true
  end

  local ok, response = pcall(http.get, INSTALLER_URL)
  if not ok or not response then
    return false
  end

  local data = response.readAll()
  response.close()
  return type(data) == "string" and data ~= "" and writeText(INSTALLER_PATH, data)
end

local function rescue(failure)
  while true do
    resetTerminal()
    term.setTextColor(colors.red)
    print("Roger supervisor crashed. Repairing...")
    term.setTextColor(colors.white)
    print(tostring(failure))
    print("")

    local before = installedHash()
    if ensureInstaller() then
      pcall(shell.run, INSTALLER_PATH, "update")
    end
    local after = installedHash()

    -- A new package always gets a boot. The same package gets one more, in case its files were damaged.
    if after and (after ~= before or (readText(REPAIR_MARK) ~= after and writeText(REPAIR_MARK, after))) then
      os.reboot()
    end

    resetTerminal()
    term.setTextColor(colors.red)
    print("Still broken after repair.")
    term.setTextColor(colors.white)
    print(tostring(failure))
    print("")
    print("Retrying every " .. RETRY_SECONDS .. " seconds.")
    print("Hold Ctrl+T for a shell.")
    print("See roger_supervisor.log for details.")
    sleep(RETRY_SECONDS)
  end
end

local ok, err = pcall(function()
  require("lib.roger_supervisor").run()
end)

if not ok and not tostring(err):find("Terminated$") then
  resetTerminal()
  pcall(rescue, err)
  resetTerminal()
end
