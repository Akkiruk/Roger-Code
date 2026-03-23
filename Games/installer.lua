-- installer.lua
-- Casino Game Installer & Updater for ComputerCraft
--
-- Bootstrap (paste into CC shell):
--   wget https://raw.githubusercontent.com/Akkiruk/Roger-Code/main/Games/installer.lua
--
-- Usage:
--   installer              -- Interactive menu
--   installer <game>       -- Install/update a specific game
--   installer update       -- Update currently installed game
--   installer self-update  -- Update just the installer

local INSTALLER_VERSION = "1.0.0"
local REPO_OWNER = "Akkiruk"
local REPO_NAME  = "Roger-Code"
local BRANCH     = "main"
local BASE_URL   = "https://raw.githubusercontent.com/"
                    .. REPO_OWNER .. "/" .. REPO_NAME
                    .. "/" .. BRANCH .. "/Games/"
local MANIFEST_URL = BASE_URL .. "manifest.json"
local VERSION_FILE = ".casino_installed"
local LOG_FILE     = "installer_error.log"

local tArgs = { ... }

---------------------------------------------------------------------------
-- Error logging
---------------------------------------------------------------------------
local function logError(msg)
  local f = fs.open(LOG_FILE, "a")
  if f then
    f.writeLine("[" .. os.epoch("local") .. "] " .. tostring(msg))
    f.close()
  end
end

---------------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------------
local W, H = term.getSize()

local function cls()
  term.clear()
  term.setCursorPos(1, 1)
end

local function cprint(color, text)
  term.setTextColor(color)
  print(text)
  term.setTextColor(colors.white)
end

local function cwrite(color, text)
  term.setTextColor(color)
  write(text)
  term.setTextColor(colors.white)
end

local function header(title)
  cls()
  local line = string.rep("-", W)
  cprint(colors.cyan, line)
  cprint(colors.cyan, " " .. title)
  cprint(colors.cyan, line)
  print("")
end

local function progressBar(current, total, width)
  width = width or 20
  local filled = math.floor((current / total) * width)
  return "[" .. string.rep("=", filled)
       .. string.rep(" ", width - filled) .. "] "
       .. current .. "/" .. total
end

---------------------------------------------------------------------------
-- HTTP / file helpers
---------------------------------------------------------------------------
local function download(url)
  -- Always binary to preserve precompiled assets (surface, fonts)
  local ok, response = pcall(function()
    return http.get(url, nil, true)
  end)
  if not ok or not response then
    return nil, "HTTP request failed: " .. tostring(url)
  end
  local data = response.readAll()
  local code = response.getResponseCode()
  response.close()
  if code ~= 200 then
    return nil, "HTTP " .. tostring(code) .. ": " .. tostring(url)
  end
  if not data or #data == 0 then
    return nil, "Empty response: " .. tostring(url)
  end
  return data
end

local function saveFile(path, data)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
  local f = fs.open(path, "wb")
  if not f then
    return false, "Cannot write: " .. path
  end
  f.write(data)
  f.close()
  return true
end

local function downloadAndSave(url, path)
  local data, err = download(url)
  if not data then return false, err end
  return saveFile(path, data)
end

---------------------------------------------------------------------------
-- Manifest
---------------------------------------------------------------------------
local function fetchManifest()
  -- Manifest is JSON text; download as binary then decode
  local data, err = download(MANIFEST_URL)
  if not data then
    return nil, err or "Could not fetch manifest"
  end
  -- Convert binary bytes to string for JSON parse
  local str = data
  if type(str) ~= "string" then
    return nil, "Unexpected manifest data type"
  end
  local manifest = textutils.unserialiseJSON(str)
  if not manifest then
    return nil, "Failed to parse manifest JSON"
  end
  return manifest
end

---------------------------------------------------------------------------
-- Installed state
---------------------------------------------------------------------------
local function loadInstalled()
  if not fs.exists(VERSION_FILE) then return nil end
  local f = fs.open(VERSION_FILE, "r")
  if not f then return nil end
  local raw = f.readAll()
  f.close()
  local ok, info = pcall(function() return textutils.unserialise(raw) end)
  if ok and type(info) == "table" then return info end
  return nil
end

local function saveInstalled(info)
  local f = fs.open(VERSION_FILE, "w")
  if f then
    f.write(textutils.serialise(info))
    f.close()
  end
end

---------------------------------------------------------------------------
-- Install / update a game
---------------------------------------------------------------------------
local function installGame(manifest, gameKey, forceConfig)
  local game = manifest.games[gameKey]
  if not game then
    cprint(colors.red, "Unknown game: " .. tostring(gameKey))
    return false
  end

  header("Installing " .. game.name .. " v" .. game.version)

  -- Build download list: { url, destPath }
  local downloads = {}
  local srcDir = game.source_dir

  -- Game code files (always overwrite)
  for _, file in ipairs(game.files or {}) do
    downloads[#downloads + 1] = {
      url  = BASE_URL .. srcDir .. "/" .. file,
      path = file,
    }
  end

  -- Config files (preserve existing on updates unless forced)
  for _, file in ipairs(game.config_files or {}) do
    if forceConfig or not fs.exists(file) then
      downloads[#downloads + 1] = {
        url  = BASE_URL .. srcDir .. "/" .. file,
        path = file,
        tag  = "config",
      }
    else
      cprint(colors.gray, "  Keeping config: " .. file)
    end
  end

  -- Asset files (nfp, fonts, surface, etc.)
  for _, file in ipairs(game.assets or {}) do
    downloads[#downloads + 1] = {
      url  = BASE_URL .. srcDir .. "/" .. file,
      path = file,
    }
  end

  -- Shared libraries
  if manifest.lib and manifest.lib.files then
    for _, file in ipairs(manifest.lib.files) do
      downloads[#downloads + 1] = {
        url  = BASE_URL .. "lib/" .. file,
        path = "lib/" .. file,
      }
    end
  end

  -- Download everything
  local total   = #downloads
  local success = 0
  local failed  = {}

  print("")
  for i, entry in ipairs(downloads) do
    local _, row = term.getCursorPos()
    term.setCursorPos(1, row)
    term.clearLine()

    local label = entry.path
    if entry.tag == "config" then label = label .. " (config)" end

    cwrite(colors.white, "  " .. progressBar(i, total) .. "  " .. label .. " ")

    local ok, err = downloadAndSave(entry.url, entry.path)
    if ok then
      success = success + 1
    else
      failed[#failed + 1] = entry.path
      logError(tostring(err))
    end
    os.sleep(0)
  end

  -- Ensure we move past the progress line
  print("")

  -- Save install record
  saveInstalled({
    game         = gameKey,
    game_version = game.version,
    lib_version  = manifest.lib and manifest.lib.version or "?",
    installed_at = os.epoch("local"),
    updated_at   = os.epoch("local"),
  })

  print("")
  if #failed == 0 then
    cprint(colors.lime, "  Installed " .. success .. "/" .. total .. " files. All good!")
  else
    cprint(colors.yellow, "  Installed " .. success .. "/" .. total .. " files.")
    cprint(colors.red, "  Failed: " .. table.concat(failed, ", "))
    cprint(colors.gray, "  See " .. LOG_FILE .. " for details.")
  end

  print("")
  cprint(colors.white, "Run 'startup' to launch " .. game.name .. ".")
  return #failed == 0
end

---------------------------------------------------------------------------
-- Self-update
---------------------------------------------------------------------------
local function selfUpdate(manifest)
  local remoteVer = manifest.installer_version
  if not remoteVer then
    cprint(colors.gray, "No installer version in manifest.")
    return
  end
  if remoteVer == INSTALLER_VERSION then
    cprint(colors.lime, "Installer is up to date (v" .. INSTALLER_VERSION .. ")")
    return
  end

  cwrite(colors.yellow, "Updating installer v"
    .. INSTALLER_VERSION .. " -> v" .. remoteVer .. "... ")

  local myPath = shell.getRunningProgram()
  local ok, err = downloadAndSave(BASE_URL .. "installer.lua", myPath)
  if ok then
    cprint(colors.lime, "Done!")
    cprint(colors.white, "Run '" .. myPath .. "' again to use the new version.")
  else
    cprint(colors.red, "Failed!")
    logError("Self-update failed: " .. tostring(err))
  end
end

---------------------------------------------------------------------------
-- Game selection menu
---------------------------------------------------------------------------
local function selectGame(manifest)
  header("Select Game")

  local gameList = {}
  for key, game in pairs(manifest.games) do
    gameList[#gameList + 1] = {
      key  = key,
      name = game.name,
      ver  = game.version,
      desc = game.description or "",
    }
  end
  table.sort(gameList, function(a, b) return a.name < b.name end)

  for i, g in ipairs(gameList) do
    cwrite(colors.yellow, "  " .. i .. ". ")
    cwrite(colors.white, g.name)
    cprint(colors.gray, "  v" .. g.ver)
    if g.desc ~= "" then
      cprint(colors.gray, "     " .. g.desc)
    end
  end
  print("")
  cprint(colors.gray, "  0. Cancel")
  print("")
  cwrite(colors.white, "Select: ")
  local choice = tonumber(read())
  if not choice or choice < 1 or choice > #gameList then
    return nil
  end
  return gameList[choice].key
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------
local function main()
  -- CLI: installer self-update
  if tArgs[1] == "self-update" then
    cwrite(colors.white, "Fetching manifest... ")
    local manifest, err = fetchManifest()
    if not manifest then
      cprint(colors.red, "FAILED")
      cprint(colors.red, tostring(err))
      logError(tostring(err))
      return
    end
    cprint(colors.lime, "OK")
    selfUpdate(manifest)
    return
  end

  -- CLI: installer update
  if tArgs[1] == "update" then
    local installed = loadInstalled()
    if not installed then
      cprint(colors.red, "No game installed. Run 'installer' to install.")
      return
    end
    cwrite(colors.white, "Checking for updates... ")
    local manifest, err = fetchManifest()
    if not manifest then
      cprint(colors.red, "FAILED")
      cprint(colors.red, tostring(err))
      logError(tostring(err))
      return
    end
    cprint(colors.lime, "OK")
    installGame(manifest, installed.game, false)
    return
  end

  -- CLI: installer <gamename>
  if tArgs[1] and tArgs[1] ~= "" then
    cwrite(colors.white, "Fetching manifest... ")
    local manifest, err = fetchManifest()
    if not manifest then
      cprint(colors.red, "FAILED")
      cprint(colors.red, tostring(err))
      logError(tostring(err))
      return
    end
    cprint(colors.lime, "OK")
    installGame(manifest, string.lower(tArgs[1]), false)
    return
  end

  -- Interactive mode
  header("Casino Game Installer v" .. INSTALLER_VERSION)

  cwrite(colors.white, "Fetching manifest... ")
  local manifest, err = fetchManifest()
  if not manifest then
    cprint(colors.red, "FAILED")
    cprint(colors.red, tostring(err))
    logError(tostring(err))
    print("")
    cprint(colors.gray, "Check that HTTP is enabled in the server config")
    cprint(colors.gray, "and that github.com is allowed.")
    return
  end
  cprint(colors.lime, "OK")

  -- Offer self-update if available
  if manifest.installer_version
     and manifest.installer_version ~= INSTALLER_VERSION then
    print("")
    cprint(colors.yellow, "Installer update: v"
      .. INSTALLER_VERSION .. " -> v" .. manifest.installer_version)
    cwrite(colors.white, "Update installer now? (y/n) ")
    local ans = read()
    if ans and ans:lower() == "y" then
      selfUpdate(manifest)
      return
    end
  end

  -- Check if a game is already installed
  local installed = loadInstalled()

  if installed then
    local game = manifest.games[installed.game]
    local gameName = game and game.name or installed.game
    print("")

    if game and game.version ~= installed.game_version then
      cprint(colors.yellow, gameName .. " v"
        .. installed.game_version .. " installed")
      cprint(colors.lime, "  Update available: v" .. game.version)
    elseif game then
      cprint(colors.lime, gameName .. " v"
        .. installed.game_version .. " - up to date")
    else
      cprint(colors.gray, "Installed: "
        .. installed.game .. " v" .. (installed.game_version or "?"))
    end

    print("")
    print("  1. Update " .. gameName)
    print("  2. Reinstall " .. gameName .. " (keep config)")
    print("  3. Reinstall " .. gameName .. " (reset config)")
    print("  4. Install different game")
    print("  5. Exit")
    print("")
    cwrite(colors.white, "Select: ")
    local choice = tonumber(read())

    if choice == 1 or choice == 2 then
      installGame(manifest, installed.game, false)
      return
    elseif choice == 3 then
      installGame(manifest, installed.game, true)
      return
    elseif choice == 4 then
      -- fall through to game selection
    else
      return
    end
  end

  -- Game selection
  local gameKey = selectGame(manifest)
  if gameKey then
    installGame(manifest, gameKey, true)
  end
end

-- Top-level error handler with logging
local ok, err = pcall(main)
if not ok then
  logError("CRASH: " .. tostring(err))
  term.setTextColor(colors.red)
  print("\nInstaller crashed: " .. tostring(err))
  print("See " .. LOG_FILE)
  term.setTextColor(colors.white)
end
