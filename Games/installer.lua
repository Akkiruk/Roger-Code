-- installer.lua
-- Program Installer & Updater for ComputerCraft
--
-- Bootstrap (paste into CC shell):
--   wget https://raw.githubusercontent.com/Akkiruk/Roger-Code/main/Games/installer.lua
--
-- Usage:
--   installer              -- Interactive menu
--   installer <name>       -- Install/update a specific program
--   installer update       -- Update currently installed program
--   installer self-update  -- Update just the installer

local INSTALLER_VERSION = "1.1.4"
local REPO_OWNER = "Akkiruk"
local REPO_NAME  = "Roger-Code"
local BRANCH     = "main"
local API_URL    = "https://api.github.com/repos/"
                    .. REPO_OWNER .. "/" .. REPO_NAME
local RAW_ROOT   = "https://raw.githubusercontent.com/"
                    .. REPO_OWNER .. "/" .. REPO_NAME .. "/"
local REPO_URL   = RAW_ROOT .. BRANCH .. "/"
local MANIFEST_URL = REPO_URL .. "Games/manifest.json"
local VERSION_FILE = ".installed_program"
local PHONE_HOST_MARKER_FILE = ".phone_os_host_claimed"
local LOG_FILE     = "installer_error.log"
local LOCKDOWN_FILE = "vhcc_lockdown.txt"
local UNLOCK_FILE   = ".vhcc_unlock"
local API_HEADERS  = {
  ["User-Agent"] = "Roger-Code-Installer",
  ["Accept"] = "application/vnd.github+json",
}

local tArgs = { ... }
local resolvedRawBase = nil

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
local function download(url, headers)
  -- Always binary to preserve precompiled assets (surface, fonts)
  local ok, response = pcall(function()
    return http.get(url, headers, true)
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

local function parseJson(data, label)
  if type(data) ~= "string" then
    return nil, "Unexpected " .. tostring(label or "JSON") .. " data type"
  end

  local decoded = textutils.unserialiseJSON(data)
  if type(decoded) ~= "table" then
    return nil, "Failed to parse " .. tostring(label or "JSON")
  end

  return decoded
end

local function resolveRawBase()
  if resolvedRawBase then
    return resolvedRawBase
  end

  local data, err = download(API_URL .. "/commits/" .. BRANCH, API_HEADERS)
  if not data then
    return nil, err or "Could not resolve latest repo commit"
  end

  local info, parseErr = parseJson(data, "commit metadata")
  if not info then
    return nil, parseErr
  end

  if type(info.sha) ~= "string" or info.sha == "" then
    return nil, "Commit metadata did not include a SHA"
  end

  resolvedRawBase = RAW_ROOT .. info.sha .. "/"
  return resolvedRawBase
end

local function buildRepoUrl(path, rawBase)
  return (rawBase or REPO_URL) .. path
end

---------------------------------------------------------------------------
-- Manifest
---------------------------------------------------------------------------
local function fetchManifest()
  local urls = {}
  local rawBase, baseErr = resolveRawBase()
  if rawBase then
    urls[#urls + 1] = { url = buildRepoUrl("Games/manifest.json", rawBase), rawBase = rawBase }
  end
  urls[#urls + 1] = { url = MANIFEST_URL, rawBase = REPO_URL }

  local lastErr = baseErr

  for _, candidate in ipairs(urls) do
    local data, err = download(candidate.url)
    if data then
      local manifest, parseErr = parseJson(data, "manifest JSON")
      if manifest then
        if not manifest.programs and manifest.games then
          manifest.programs = manifest.games
        end
        manifest._raw_base = candidate.rawBase
        return manifest
      end
      lastErr = parseErr
    else
      lastErr = err
    end
  end

  return nil, lastErr or "Could not fetch manifest"
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

local function beginWriteWindow(tag)
  if not fs.exists(LOCKDOWN_FILE) then
    return true, false
  end

  if fs.exists(UNLOCK_FILE) then
    return true, false
  end

  local f = fs.open(UNLOCK_FILE, "w")
  if not f then
    return false, "Cannot create lockdown unlock file"
  end

  f.write(textutils.serialise({
    source = tag or "installer",
    openedAt = os.epoch("local"),
  }))
  f.close()
  return true, true
end

local function endWriteWindow(createdUnlock)
  if createdUnlock and fs.exists(UNLOCK_FILE) then
    fs.delete(UNLOCK_FILE)
  end
end

local function writePhoneHostMarker(info)
  local f = fs.open(PHONE_HOST_MARKER_FILE, "w")
  if not f then
    return false, "Cannot write phone host marker"
  end

  f.write(textutils.serialise(info))
  f.close()
  return true
end

local function claimPhoneHostIfNeeded(shouldClaim)
  if not shouldClaim then
    return true
  end

  if not ccvault or type(ccvault.claimHost) ~= "function" then
    return false, "ccvault.claimHost is unavailable"
  end

  local ok, result, err = pcall(ccvault.claimHost)
  if not ok then
    return false, tostring(result)
  end
  if type(result) ~= "table" then
    return false, tostring(err or "host claim failed")
  end

  local markerOk, markerErr = writePhoneHostMarker({
    claimed_at = os.epoch("local"),
    computer_id = (ccvault.getComputerId and ccvault.getComputerId()) or os.getComputerID(),
    host_name = result.hostName,
    changed = result.changed == true,
  })
  if not markerOk then
    return false, markerErr
  end

  return true, result
end

---------------------------------------------------------------------------
-- Install / update a game
---------------------------------------------------------------------------
local function installProgram(manifest, progKey, forceConfig)
  local prog = manifest.programs[progKey]
  if not prog then
    cprint(colors.red, "Unknown program: " .. tostring(progKey))
    return false
  end

  local unlockOk, unlockResult = beginWriteWindow("install")
  if not unlockOk then
    cprint(colors.red, "Could not open update window: " .. tostring(unlockResult))
    logError("Install unlock failed: " .. tostring(unlockResult))
    return false
  end
  local createdUnlock = unlockResult == true

  header("Installing " .. prog.name .. " v" .. prog.version)

  local installedBefore = loadInstalled()
  local shouldClaimPhoneHost = progKey == "phone_os"
    and not fs.exists(PHONE_HOST_MARKER_FILE)

  -- Build download list: { url, destPath }
  local downloads = {}
  local srcDir = prog.source_dir
  local rawBase = manifest._raw_base or REPO_URL

  -- Code files (always overwrite)
  for _, file in ipairs(prog.files or {}) do
    downloads[#downloads + 1] = {
      url  = buildRepoUrl(srcDir .. "/" .. file, rawBase),
      path = file,
    }
  end

  -- Config files (preserve existing on updates unless forced)
  for _, file in ipairs(prog.config_files or {}) do
    if forceConfig or not fs.exists(file) then
      downloads[#downloads + 1] = {
        url  = buildRepoUrl(srcDir .. "/" .. file, rawBase),
        path = file,
        tag  = "config",
      }
    else
      cprint(colors.gray, "  Keeping config: " .. file)
    end
  end

  -- Asset files (nfp, fonts, surface, etc.)
  for _, file in ipairs(prog.assets or {}) do
    downloads[#downloads + 1] = {
      url  = buildRepoUrl(srcDir .. "/" .. file, rawBase),
      path = file,
    }
  end

  -- Shared libraries (only if this program uses them)
  if prog.uses_lib and manifest.lib and manifest.lib.files then
    for _, file in ipairs(manifest.lib.files) do
      downloads[#downloads + 1] = {
        url  = buildRepoUrl("Games/lib/" .. file, rawBase),
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
    program      = progKey,
    version      = prog.version,
    lib_version  = prog.uses_lib and manifest.lib and manifest.lib.version or nil,
    installed_at = installedBefore and installedBefore.installed_at or os.epoch("local"),
    updated_at   = os.epoch("local"),
  })

  local phoneHostResult = nil
  local phoneHostErr = nil
  if #failed == 0 then
    local claimOk, claimInfo = claimPhoneHostIfNeeded(shouldClaimPhoneHost)
    if claimOk then
      phoneHostResult = claimInfo
    else
      phoneHostErr = claimInfo
      logError("Phone host claim failed: " .. tostring(claimInfo))
    end
  end

  print("")
  if #failed == 0 then
    cprint(colors.lime, "  Installed " .. success .. "/" .. total .. " files. All good!")
  else
    cprint(colors.yellow, "  Installed " .. success .. "/" .. total .. " files.")
    cprint(colors.red, "  Failed: " .. table.concat(failed, ", "))
    cprint(colors.gray, "  See " .. LOG_FILE .. " for details.")
  end

  if phoneHostResult then
    local hostName = phoneHostResult.hostName or "Unknown"
    local claimVerb = phoneHostResult.changed and "assigned" or "confirmed"
    cprint(colors.lime, "  Phone host " .. claimVerb .. ": " .. tostring(hostName))
  elseif phoneHostErr then
    cprint(colors.yellow, "  Phone host was not assigned.")
    cprint(colors.yellow, "  " .. tostring(phoneHostErr))
  end

  print("")
  cprint(colors.white, "Run 'startup' to launch " .. prog.name .. ".")
  endWriteWindow(createdUnlock)
  return #failed == 0
end

---------------------------------------------------------------------------
-- Version comparison (same as updater.lua)
---------------------------------------------------------------------------
local function isNewer(remoteVer, localVer)
  if not remoteVer or not localVer then return remoteVer ~= localVer end
  local rParts = {}
  for p in tostring(remoteVer):gmatch("(%d+)") do
    rParts[#rParts + 1] = tonumber(p) or 0
  end
  local lParts = {}
  for p in tostring(localVer):gmatch("(%d+)") do
    lParts[#lParts + 1] = tonumber(p) or 0
  end
  for i = 1, math.max(#rParts, #lParts) do
    local r = rParts[i] or 0
    local l = lParts[i] or 0
    if r > l then return true end
    if r < l then return false end
  end
  return false
end

---------------------------------------------------------------------------
-- Self-update (auto-restarts if updated)
---------------------------------------------------------------------------
local function selfUpdate(manifest, silent)
  local remoteVer = manifest.installer_version
  local remoteHash = manifest.installer_hash
  if not remoteVer then
    if not silent then cprint(colors.gray, "No installer version in manifest.") end
    return false
  end

  local needsUpdate = isNewer(remoteVer, INSTALLER_VERSION)

  -- Also check content hash if versions match but hash differs
  if not needsUpdate and remoteHash then
    -- Read our own file to compute a simple length check as fallback
    -- (full hash comparison requires the manifest generator to provide it)
    needsUpdate = false -- version-based is authoritative when hashes aren't stored locally
  end

  if not needsUpdate then
    if not silent then
      cprint(colors.lime, "Installer is up to date (v" .. INSTALLER_VERSION .. ")")
    end
    return false
  end

  if not silent then
    cwrite(colors.yellow, "Updating installer v"
      .. INSTALLER_VERSION .. " -> v" .. remoteVer .. "... ")
  end

  local unlockOk, unlockResult = beginWriteWindow("installer-self-update")
  if not unlockOk then
    if not silent then cprint(colors.red, "Failed!") end
    logError("Self-update unlock failed: " .. tostring(unlockResult))
    return false
  end
  local createdUnlock = unlockResult == true

  local myPath = shell.getRunningProgram()
  local rawBase = manifest and manifest._raw_base or REPO_URL
  local ok, err = downloadAndSave(buildRepoUrl("Games/installer.lua", rawBase), myPath)
  if ok then
    if not silent then
      cprint(colors.lime, "Done! Restarting...")
    end
    endWriteWindow(createdUnlock)
    -- Re-run ourselves with the same arguments
    shell.run(myPath, table.unpack(tArgs))
    -- Exit this (old) instance after the new one finishes
    return true
  else
    if not silent then cprint(colors.red, "Failed!") end
    endWriteWindow(createdUnlock)
    logError("Self-update failed: " .. tostring(err))
    return false
  end
end

---------------------------------------------------------------------------
-- Program selection menu
---------------------------------------------------------------------------
local function getProgramCategory(prog)
  if type(prog) ~= "table" then
    return "Other"
  end

  if type(prog.category) == "string" and prog.category ~= "" then
    return prog.category
  end

  local sourceDir = tostring(prog.source_dir or "")
  if sourceDir:match("^Utilities/") or sourceDir == "Utilities" then
    return "Utilities"
  end
  if sourceDir:match("^Games/") then
    return "Games"
  end

  return "Other"
end

local function buildProgramGroups(manifest)
  local grouped = {}

  for key, prog in pairs(manifest.programs or {}) do
    local category = getProgramCategory(prog)
    if not grouped[category] then
      grouped[category] = {}
    end

    grouped[category][#grouped[category] + 1] = {
      key  = key,
      name = prog.name,
      ver  = prog.version,
      desc = prog.description or "",
    }
  end

  for _, entries in pairs(grouped) do
    table.sort(entries, function(a, b) return a.name < b.name end)
  end

  local folders = {}
  for category, entries in pairs(grouped) do
    folders[#folders + 1] = {
      key = category,
      name = category,
      count = #entries,
      entries = entries,
    }
  end

  table.sort(folders, function(a, b)
    local order = {
      Games = 1,
      Utilities = 2,
      Other = 3,
    }
    local aOrder = order[a.name] or 99
    local bOrder = order[b.name] or 99
    if aOrder ~= bOrder then
      return aOrder < bOrder
    end
    return a.name < b.name
  end)

  return folders
end

local function selectFromList(title, items, renderEntry)
  local perPage = H - 7
  if perPage < 3 then perPage = 3 end

  local totalPages = math.max(1, math.ceil(#items / perPage))
  local page = 1

  while true do
    header(title)

    local startIdx = (page - 1) * perPage + 1
    local endIdx   = math.min(page * perPage, #items)

    for i = startIdx, endIdx do
      renderEntry(i, items[i])
    end

    print("")

    if totalPages > 1 then
      local nav = "Page " .. page .. "/" .. totalPages
      if page < totalPages then nav = nav .. "  [n]ext" end
      if page > 1 then nav = nav .. "  [p]rev" end
      cprint(colors.lightGray, "  " .. nav)
    end
    cprint(colors.gray, "  0. Back")
    cwrite(colors.white, "Select: ")

    local input = read()
    if not input then return nil end
    input = input:lower():gsub("^%s+", ""):gsub("%s+$", "")

    if input == "n" and page < totalPages then
      page = page + 1
    elseif input == "p" and page > 1 then
      page = page - 1
    else
      local choice = tonumber(input)
      if not choice or choice == 0 then
        return nil
      end
      if choice >= 1 and choice <= #items then
        return items[choice]
      end
    end
  end
end

local function selectProgramFromFolder(folder)
  return selectFromList(folder.name, folder.entries, function(i, p)
    local prefix = string.format("  %d. ", i)
    local nameVer = p.name .. " v" .. p.ver
    local remaining = W - #prefix - #nameVer - 2
    local suffix = ""
    if remaining > 5 and p.desc ~= "" then
      if #p.desc > remaining then
        suffix = " " .. p.desc:sub(1, remaining - 2) .. ".."
      else
        suffix = " " .. p.desc
      end
    end
    cwrite(colors.yellow, prefix)
    cwrite(colors.white, nameVer)
    cprint(colors.gray, suffix)
  end)
end

local function selectProgram(manifest)
  while true do
    local folders = buildProgramGroups(manifest)
    local folder = selectFromList("Select Folder", folders, function(i, entry)
      cwrite(colors.yellow, string.format("  %d. ", i))
      cwrite(colors.white, entry.name)
      cprint(colors.gray, " (" .. tostring(entry.count) .. ")")
    end)

    if not folder then
      return nil
    end

    local program = selectProgramFromFolder(folder)
    if program then
      return program.key
    end
  end
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------
local function main()
  -- Always self-update first, regardless of CLI mode
  -- Fetch manifest early so we can check installer version
  local earlyManifest, earlyErr = fetchManifest()
  if earlyManifest then
    local didUpdate = selfUpdate(earlyManifest, false)
    if didUpdate then return end -- new version already ran and finished
  end

  -- Use the already-fetched manifest for subsequent operations
  local manifest = earlyManifest

  -- CLI: installer self-update
  if tArgs[1] == "self-update" then
    if not manifest then
      cprint(colors.red, "Could not fetch manifest: " .. tostring(earlyErr))
      logError(tostring(earlyErr))
    end
    -- Already handled above
    return
  end

  -- CLI: installer update
  if tArgs[1] == "update" then
    local installed = loadInstalled()
    if not installed then
      cprint(colors.red, "No program installed. Run 'installer' to install.")
      return
    end
    if not manifest then
      cprint(colors.red, "Could not fetch manifest: " .. tostring(earlyErr))
      logError(tostring(earlyErr))
      return
    end
    -- Support old .casino_installed format (game key) and new format (program key)
    local key = installed.program or installed.game
    installProgram(manifest, key, false)
    return
  end

  -- CLI: installer <name>
  if tArgs[1] and tArgs[1] ~= "" then
    if not manifest then
      cprint(colors.red, "Could not fetch manifest: " .. tostring(earlyErr))
      logError(tostring(earlyErr))
      return
    end
    installProgram(manifest, string.lower(tArgs[1]), false)
    return
  end

  -- Interactive mode
  header("Program Installer v" .. INSTALLER_VERSION)

  if not manifest then
    cprint(colors.red, "Could not fetch manifest: " .. tostring(earlyErr))
    logError(tostring(earlyErr))
    print("")
    cprint(colors.gray, "Check that HTTP is enabled in the server config")
    cprint(colors.gray, "and that github.com is allowed.")
    return
  end
  cprint(colors.lime, "Manifest loaded. " .. INSTALLER_VERSION)

  -- Check if a program is already installed
  local installed = loadInstalled()

  -- Support old .casino_installed format
  if not installed and fs.exists(".casino_installed") then
    local f = fs.open(".casino_installed", "r")
    if f then
      local raw = f.readAll()
      f.close()
      local parseOk, info = pcall(function() return textutils.unserialise(raw) end)
      if parseOk and type(info) == "table" then
        installed = info
      end
    end
  end

  if installed then
    local key = installed.program or installed.game
    local prog = manifest.programs[key]
    local progName = prog and prog.name or key
    local instVer = installed.version or installed.game_version or "?"
    print("")

    if prog and prog.version ~= instVer then
      cprint(colors.yellow, progName .. " v" .. instVer .. " installed")
      cprint(colors.lime, "  Update available: v" .. prog.version)
    elseif prog then
      cprint(colors.lime, progName .. " v" .. instVer .. " - up to date")
    else
      cprint(colors.gray, "Installed: " .. tostring(key) .. " v" .. instVer)
    end

    print("")
    print("  1. Update " .. progName)
    print("  2. Reinstall " .. progName .. " (keep config)")
    print("  3. Reinstall " .. progName .. " (reset config)")
    print("  4. Install different program")
    print("  5. Exit")
    print("")
    cwrite(colors.white, "Select: ")
    local choice = tonumber(read())

    if choice == 1 or choice == 2 then
      installProgram(manifest, key, false)
      return
    elseif choice == 3 then
      installProgram(manifest, key, true)
      return
    elseif choice == 4 then
      -- fall through to program selection
    else
      return
    end
  end

  -- Program selection
  local progKey = selectProgram(manifest)
  if progKey then
    installProgram(manifest, progKey, true)
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
