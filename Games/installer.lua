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

local INSTALLER_VERSION = "1.1.6"
local REPO_OWNER = "Akkiruk"
local REPO_NAME = "Roger-Code"
local SOURCE_BRANCH = "main"
local DEPLOY_BRANCH = "deploy-index"
local RAW_ROOT = "https://raw.githubusercontent.com/" .. REPO_OWNER .. "/" .. REPO_NAME .. "/"
local DEPLOY_URL = RAW_ROOT .. DEPLOY_BRANCH .. "/"
local LATEST_URL = DEPLOY_URL .. "latest.json"
local VERSION_FILE = ".installed_program"
local MANAGED_FILES = ".roger_managed_files"
local PHONE_HOST_MARKER_FILE = ".phone_os_host_claimed"
local LOG_FILE = "installer_error.log"
local LOCKDOWN_FILE = "vhcc_lockdown.txt"
local UNLOCK_FILE = ".vhcc_unlock"
local API_URL = "https://api.github.com/repos/" .. REPO_OWNER .. "/" .. REPO_NAME
local API_HEADERS = {
  ["User-Agent"] = "Roger-Code-Installer",
  ["Accept"] = "application/vnd.github+json",
}
local CONTENTS_API_ROOT = API_URL .. "/contents/"
local CONTENTS_API_HEADERS = {
  ["User-Agent"] = "Roger-Code-Installer",
  ["Accept"] = "application/vnd.github.raw+json",
}
local RESERVED_LOCAL_PATHS = {
  [VERSION_FILE] = true,
  [MANAGED_FILES] = true,
  [PHONE_HOST_MARKER_FILE] = true,
  [LOG_FILE] = true,
  ["updater.log"] = true,
  ["crash_recovery.log"] = true,
  ["phone_os_startup.log"] = true,
  ["vaultgear_error.log"] = true,
  ["vhcc_lockdown.txt"] = true,
  ["installer.lua"] = true,
}

local tArgs = { ... }
-- Forward declarations keep Lua 5.1 local scope intact for helpers used
-- by earlier-defined functions in this file.
local readManagedFiles = nil

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
  local safeTotal = total > 0 and total or 1
  local filled = math.floor((current / safeTotal) * width)
  return "[" .. string.rep("=", filled)
    .. string.rep(" ", width - filled) .. "] "
    .. current .. "/" .. total
end

---------------------------------------------------------------------------
-- HTTP / file helpers
---------------------------------------------------------------------------
local function download(url, headers)
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

local function readFile(path, binary)
  if not fs.exists(path) then
    return nil
  end
  local mode = binary and "rb" or "r"
  local f = fs.open(path, mode)
  if not f then
    return nil
  end
  local data = f.readAll()
  f.close()
  return data
end

local function computeSha256(data)
  if textutils and type(textutils.sha256) == "function" then
    return textutils.sha256(data)
  end
  return nil
end

local function verifyHash(data, expected)
  if type(expected) ~= "string" or expected == "" then
    return true
  end

  local actual = computeSha256(data)
  if not actual then
    return true
  end

  return string.lower(actual) == string.lower(expected)
end

local function withCacheBust(url)
  local separator = url:find("?", 1, true) and "&" or "?"
  return url .. separator .. "t=" .. tostring(os.epoch("local"))
end

local function removePath(path)
  if fs.exists(path) then
    fs.delete(path)
  end
end

local function normalizePath(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function pathSetFromList(paths)
  local set = {}
  for _, path in ipairs(paths or {}) do
    set[normalizePath(path)] = true
  end
  return set
end

local function listFilesRecursive(root, prefix, out)
  out = out or {}
  prefix = prefix or ""
  if not fs.exists(root) then
    return out
  end

  for _, name in ipairs(fs.list(root)) do
    local child = fs.combine(root, name)
    local rel = prefix ~= "" and (prefix .. "/" .. name) or name
    if fs.isDir(child) then
      listFilesRecursive(child, rel, out)
    else
      out[#out + 1] = normalizePath(rel)
    end
  end

  return out
end

local function cleanupStaleRuntimeArtifacts()
  removePath(".install_staging")
  removePath(".update_staging")
end

local function isLegacyPayloadPath(path)
  if path:sub(1, 4) == "lib/" then
    return true
  end

  if path:find("/", 1, true) then
    return false
  end

  if path:match("%.lua$") or path:match("%.nfp$") then
    return true
  end

  return path == "font"
    or path == "surface"
    or path == "gothic"
    or path == "logo.nfp"
end

local function pruneLegacyPayload(desiredPaths)
  local existingManaged = readManagedFiles()
  if #existingManaged > 0 then
    return
  end

  local desired = pathSetFromList(desiredPaths)
  local files = listFilesRecursive(".", "", {})
  for _, rel in ipairs(files) do
    local normalized = normalizePath(rel)
    if isLegacyPayloadPath(normalized)
      and not desired[normalized]
      and not RESERVED_LOCAL_PATHS[normalized] then
      removePath(normalized)
    end
  end
end

local function downloadAndSaveVerified(url, finalPath, expectedSha)
  local data, err = download(url)
  if not data then
    return false, err
  end

  if not verifyHash(data, expectedSha) then
    return false, "Hash mismatch for " .. tostring(url)
  end

  if fs.exists(finalPath) then
    fs.delete(finalPath)
  end

  return saveFile(finalPath, data)
end

local function fetchDeployJson(path, label)
  local rawUrl = withCacheBust(DEPLOY_URL .. path)
  local data, err = download(rawUrl)
  if data then
    local parsed, parseErr = parseJson(data, label)
    if parsed then
      return parsed
    end
    err = parseErr
  end

  local apiUrl = withCacheBust(CONTENTS_API_ROOT .. path .. "?ref=" .. DEPLOY_BRANCH)
  data, err = download(apiUrl, CONTENTS_API_HEADERS)
  if not data then
    return nil, err
  end
  return parseJson(data, label)
end

local function fetchLatestIndex()
  return fetchDeployJson("latest.json", "deploy index")
end

local function fetchProgramSpec(specPath)
  return fetchDeployJson(specPath, "program spec")
end

local function fetchLatestMainCommit()
  local data, err = download(API_URL .. "/commits/" .. SOURCE_BRANCH, API_HEADERS)
  if not data then
    return nil, err
  end

  local info, parseErr = parseJson(data, "commit metadata")
  if not info then
    return nil, parseErr
  end

  if type(info.sha) ~= "string" or info.sha == "" then
    return nil, "Commit metadata did not include a SHA"
  end

  return info.sha
end

local function buildCommitUrl(commit, repoPath)
  return RAW_ROOT .. commit .. "/" .. repoPath
end

---------------------------------------------------------------------------
-- Installed state
---------------------------------------------------------------------------
local function loadInstalled()
  if not fs.exists(VERSION_FILE) then
    return nil
  end
  local raw = readFile(VERSION_FILE, false)
  if not raw then
    return nil
  end

  local ok, info = pcall(function()
    return textutils.unserialise(raw)
  end)
  if ok and type(info) == "table" then
    return info
  end
  return nil
end

local function saveInstalled(info)
  local f = fs.open(VERSION_FILE, "w")
  if f then
    f.write(textutils.serialise(info))
    f.close()
  end
end

readManagedFiles = function()
  if not fs.exists(MANAGED_FILES) then
    return {}
  end

  local raw = readFile(MANAGED_FILES, false) or ""
  local items = {}
  local seen = {}
  for line in raw:gmatch("[^\r\n]+") do
    local path = line:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    if path ~= "" and not seen[path] then
      seen[path] = true
      items[#items + 1] = path
    end
  end
  table.sort(items)
  return items
end

local function saveManagedFiles(paths)
  local seen = {}
  table.sort(paths)
  local f = fs.open(MANAGED_FILES, "w")
  if not f then
    return
  end
  for _, path in ipairs(paths) do
    if path ~= "" and not seen[path] then
      seen[path] = true
      f.writeLine(path)
    end
  end
  f.close()
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
-- Package install helpers
---------------------------------------------------------------------------
local function removeStaleFiles(previouslyManaged, desiredPaths)
  local wanted = {}
  for _, path in ipairs(desiredPaths) do
    wanted[path] = true
  end

  for _, path in ipairs(previouslyManaged) do
    if not wanted[path] and path ~= VERSION_FILE and path ~= MANAGED_FILES then
      removePath(path)
    end
  end
end

local function wipeManagedFiles(paths)
  local wiped = {}
  for _, path in ipairs(paths or {}) do
    local normalized = normalizePath(path)
    if normalized ~= ""
      and not wiped[normalized]
      and normalized ~= VERSION_FILE
      and normalized ~= MANAGED_FILES
      and not RESERVED_LOCAL_PATHS[normalized] then
      removePath(normalized)
      wiped[normalized] = true
    end
  end
end

local function installFromSpec(spec, forceConfig, installedBefore)
  local unlockOk, unlockResult = beginWriteWindow("install")
  if not unlockOk then
    cprint(colors.red, "Could not open update window: " .. tostring(unlockResult))
    logError("Install unlock failed: " .. tostring(unlockResult))
    return false
  end
  local createdUnlock = unlockResult == true

  local program = spec.program or {}
  local build = spec.build or {}
  header("Installing " .. tostring(program.name or program.key or "program")
    .. " v" .. tostring(program.version or "?"))

  local shouldClaimPhoneHost = program.key == "phone_os" and not fs.exists(PHONE_HOST_MARKER_FILE)
  local managedPaths = {}
  local failed = {}
  local total = #(spec.install and spec.install.files or {})
  local success = 0
  local previouslyManaged = readManagedFiles()
  cleanupStaleRuntimeArtifacts()

  for _, entry in ipairs(spec.install.files or {}) do
    managedPaths[#managedPaths + 1] = entry.install_path
  end

  removeStaleFiles(previouslyManaged, managedPaths)
  pruneLegacyPayload(managedPaths)

  if forceConfig then
    local resetPaths = {}
    for _, path in ipairs(previouslyManaged) do
      resetPaths[#resetPaths + 1] = path
    end
    for _, path in ipairs(managedPaths) do
      resetPaths[#resetPaths + 1] = path
    end
    wipeManagedFiles(resetPaths)
  end

  print("")
  for index, entry in ipairs(spec.install.files or {}) do
    local _, row = term.getCursorPos()
    term.setCursorPos(1, row)
    term.clearLine()

    local label = entry.install_path or "?"
    if entry.preserve_existing then
      label = label .. " (config)"
    end
    cwrite(colors.white, "  " .. progressBar(index, total) .. "  " .. label .. " ")

    if entry.preserve_existing and not forceConfig and fs.exists(entry.install_path) then
      success = success + 1
      cprint(colors.gray, "")
    else
      local ok, err = downloadAndSaveVerified(
        buildCommitUrl(build.commit, entry.repo_path),
        entry.install_path,
        entry.sha256
      )
      if ok then
        success = success + 1
      else
        failed[#failed + 1] = entry.install_path
        logError(tostring(err))
      end
    end
    os.sleep(0)
  end

  print("")

  local installedOk = false
  if #failed == 0 then
    saveManagedFiles(managedPaths)
    saveInstalled({
      schema_version = 1,
      program = program.key,
      name = program.name,
      version = program.version,
      source_commit = build.commit,
      package_hash = build.package_hash,
      content_hash = build.package_hash,
      spec_path = (spec._spec_path or ""),
      installed_at = installedBefore and installedBefore.installed_at or os.epoch("local"),
      updated_at = os.epoch("local"),
    })
    installedOk = true
  end

  local phoneHostResult = nil
  local phoneHostErr = nil
  if installedOk then
    local claimOk, claimInfo = claimPhoneHostIfNeeded(shouldClaimPhoneHost)
    if claimOk then
      phoneHostResult = claimInfo
    else
      phoneHostErr = claimInfo
      logError("Phone host claim failed: " .. tostring(claimInfo))
    end
  end

  if installedOk then
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
  if installedOk then
    cprint(colors.white, "Run 'startup' to launch " .. tostring(program.name or program.key) .. ".")
  end

  endWriteWindow(createdUnlock)
  return installedOk
end

---------------------------------------------------------------------------
-- Version comparison
---------------------------------------------------------------------------
local function isNewer(remoteVer, localVer)
  if not remoteVer or not localVer then
    return remoteVer ~= localVer
  end
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
    if r > l then
      return true
    end
    if r < l then
      return false
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Self-update
---------------------------------------------------------------------------
local function selfUpdate(index, silent)
  local installer = index and index.installer or nil
  if type(installer) ~= "table" then
    if not silent then
      cprint(colors.gray, "No installer metadata in deploy index.")
    end
    return false
  end

  local needsUpdate = isNewer(installer.version, INSTALLER_VERSION)
  if not needsUpdate then
    local myPath = shell.getRunningProgram()
    local currentData = readFile(myPath, true)
    local currentHash = currentData and computeSha256(currentData) or nil
    if currentHash and installer.sha256 then
      needsUpdate = string.lower(currentHash) ~= string.lower(installer.sha256)
    end
  end

  if not needsUpdate then
    if not silent then
      cprint(colors.lime, "Installer is up to date (v" .. INSTALLER_VERSION .. ")")
    end
    return false
  end

  if not silent then
    cwrite(colors.yellow, "Updating installer v"
      .. INSTALLER_VERSION .. " -> v" .. tostring(installer.version or "?") .. "... ")
  end

  local unlockOk, unlockResult = beginWriteWindow("installer-self-update")
  if not unlockOk then
    if not silent then
      cprint(colors.red, "Failed!")
    end
    logError("Self-update unlock failed: " .. tostring(unlockResult))
    return false
  end
  local createdUnlock = unlockResult == true

  local commit = installer.commit
  if not commit or commit == "" then
    commit = fetchLatestMainCommit()
  end
  if not commit then
    if not silent then
      cprint(colors.red, "Failed!")
    end
    endWriteWindow(createdUnlock)
    logError("Self-update could not resolve source commit")
    return false
  end

  local myPath = shell.getRunningProgram()
  local data, err = download(buildCommitUrl(commit, installer.path))
  if data and verifyHash(data, installer.sha256) then
    local ok, saveErr = saveFile(myPath, data)
    if ok then
      if not silent then
        cprint(colors.lime, "Done! Restarting...")
      end
      endWriteWindow(createdUnlock)
      shell.run(myPath, table.unpack(tArgs))
      return true
    end
    err = saveErr
  elseif data then
    err = "Installer hash mismatch"
  end

  if not silent then
    cprint(colors.red, "Failed!")
  end
  endWriteWindow(createdUnlock)
  logError("Self-update failed: " .. tostring(err))
  return false
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

  return "Other"
end

local function buildProgramGroups(index)
  local grouped = {}

  for key, prog in pairs(index.programs or {}) do
    local category = getProgramCategory(prog)
    if not grouped[category] then
      grouped[category] = {}
    end

    grouped[category][#grouped[category] + 1] = {
      key = key,
      name = prog.name,
      ver = prog.version,
      desc = prog.description or "",
    }
  end

  for _, entries in pairs(grouped) do
    table.sort(entries, function(a, b)
      return a.name < b.name
    end)
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
  if perPage < 3 then
    perPage = 3
  end

  local totalPages = math.max(1, math.ceil(#items / perPage))
  local page = 1

  while true do
    header(title)

    local startIdx = (page - 1) * perPage + 1
    local endIdx = math.min(page * perPage, #items)

    for i = startIdx, endIdx do
      renderEntry(i, items[i])
    end

    print("")

    if totalPages > 1 then
      local nav = "Page " .. page .. "/" .. totalPages
      if page < totalPages then
        nav = nav .. "  [n]ext"
      end
      if page > 1 then
        nav = nav .. "  [p]rev"
      end
      cprint(colors.lightGray, "  " .. nav)
    end
    cprint(colors.gray, "  0. Back")
    cwrite(colors.white, "Select: ")

    local input = read()
    if not input then
      return nil
    end
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
    local nameVer = p.name .. " v" .. tostring(p.ver or "?")
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

local function selectProgram(index)
  while true do
    local folders = buildProgramGroups(index)
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

local function installByKey(index, programKey, forceConfig)
  local programEntry = index.programs and index.programs[programKey] or nil
  if not programEntry then
    cprint(colors.red, "Unknown program: " .. tostring(programKey))
    return false
  end

  local spec, specErr = fetchProgramSpec(programEntry.spec_path)
  if not spec then
    cprint(colors.red, "Could not fetch package spec: " .. tostring(specErr))
    logError("Spec fetch failed for " .. tostring(programKey) .. ": " .. tostring(specErr))
    return false
  end
  spec._spec_path = programEntry.spec_path

  return installFromSpec(spec, forceConfig, loadInstalled())
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------
local function main()
  local index, indexErr = fetchLatestIndex()
  if index then
    local didUpdate = selfUpdate(index, false)
    if didUpdate then
      return
    end
  end

  if tArgs[1] == "self-update" then
    if not index then
      cprint(colors.red, "Could not fetch deploy index: " .. tostring(indexErr))
      logError(tostring(indexErr))
    end
    return
  end

  if tArgs[1] == "update" then
    local installed = loadInstalled()
    if not installed then
      cprint(colors.red, "No program installed. Run 'installer' to install.")
      return
    end
    if not index then
      cprint(colors.red, "Could not fetch deploy index: " .. tostring(indexErr))
      logError(tostring(indexErr))
      return
    end
    local key = installed.program or installed.game
    installByKey(index, key, false)
    return
  end

  if tArgs[1] and tArgs[1] ~= "" then
    if not index then
      cprint(colors.red, "Could not fetch deploy index: " .. tostring(indexErr))
      logError(tostring(indexErr))
      return
    end
    installByKey(index, string.lower(tArgs[1]), false)
    return
  end

  header("Program Installer v" .. INSTALLER_VERSION)

  if not index then
    cprint(colors.red, "Could not fetch deploy index: " .. tostring(indexErr))
    logError(tostring(indexErr))
    print("")
    cprint(colors.gray, "Check that HTTP is enabled in the server config")
    cprint(colors.gray, "and that github.com is allowed.")
    return
  end
  cprint(colors.lime, "Deploy index loaded. " .. INSTALLER_VERSION)

  local installed = loadInstalled()
  if not installed and fs.exists(".casino_installed") then
    local raw = readFile(".casino_installed", false)
    if raw then
      local parseOk, info = pcall(function()
        return textutils.unserialise(raw)
      end)
      if parseOk and type(info) == "table" then
        installed = info
      end
    end
  end

  if installed then
    local key = installed.program or installed.game
    local prog = index.programs and index.programs[key] or nil
    local progName = prog and prog.name or key
    local instVer = installed.version or "?"
    print("")

    if prog and ((installed.source_commit or "") ~= (prog.commit or "")
        or (installed.package_hash or installed.content_hash or "") ~= (prog.package_hash or "")) then
      cprint(colors.yellow, progName .. " v" .. instVer .. " installed")
      cprint(colors.lime, "  Update available: v" .. tostring(prog.version or "?"))
    elseif prog then
      cprint(colors.lime, progName .. " v" .. instVer .. " - up to date")
    else
      cprint(colors.gray, "Installed: " .. tostring(key) .. " v" .. tostring(instVer))
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
      installByKey(index, key, false)
      return
    elseif choice == 3 then
      installByKey(index, key, true)
      return
    elseif choice == 4 then
      -- fall through
    else
      return
    end
  end

  local programKey = selectProgram(index)
  if programKey then
    installByKey(index, programKey, true)
  end
end

local ok, err = pcall(main)
if not ok then
  logError("CRASH: " .. tostring(err))
  term.setTextColor(colors.red)
  print("\nInstaller crashed: " .. tostring(err))
  print("See " .. LOG_FILE)
  term.setTextColor(colors.white)
end
