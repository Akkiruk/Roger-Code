-- installer.lua
-- Program Installer & Updater for ComputerCraft
--
-- Bootstrap (paste into CC shell):
--   wget https://raw.githubusercontent.com/Akkiruk/Roger-Code/main/System/installer.lua
--
-- Usage:
--   installer              -- The desktop: point, click, scroll
--   installer <name>       -- Install/update a specific program
--   installer update       -- Update currently installed program
--   installer self-update  -- Update just the installer
--   installer wipe         -- Delete everything except the installer script

local INSTALLER_VERSION = "2.0.0"
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
local INSTALLER_HASH_FILE = ".installer_hash"
local DOWNLOAD_ATTEMPTS = 4
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
local HIDDEN_STANDALONE_PROGRAMS = {
  peripheral_info_collector = true,
  test_ccvault = true,
  test_ccvault_full = true,
}
local STANDALONE_SKIP_SUFFIXES = {
  ".bak",
  ".old",
  ".log",
  ".md",
}
local INSTALL_STATE_SCHEMA = 2
local DEFAULT_UPDATE_INTERVAL = 60
local UPDATED_ARG = "--installer-updated"
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
  [INSTALLER_HASH_FILE] = true,
  [UNLOCK_FILE] = true,
}

local tArgs = { ... }
-- Forward declarations keep Lua 5.1 local scope intact for helpers used
-- by earlier-defined functions in this file.
local readManagedFiles = nil
local fetchLatestMainCommit = nil

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

local function unpackArgs(args, startIndex)
  if table.unpack then
    return table.unpack(args, startIndex or 1)
  end
  return unpack(args, startIndex or 1)
end

local function parseInstallerArgs(rawArgs)
  local args = {}
  local updatedTo = nil
  local updatedFrom = nil
  local index = 1

  while index <= #rawArgs do
    local value = rawArgs[index]
    if value == UPDATED_ARG then
      updatedTo = rawArgs[index + 1]
      updatedFrom = rawArgs[index + 2]
      index = index + 3
    else
      args[#args + 1] = value
      index = index + 1
    end
  end

  return args, updatedTo, updatedFrom
end

---------------------------------------------------------------------------
-- HTTP / file helpers
---------------------------------------------------------------------------
local function download(url, headers)
  local ok, response, reason, failedResponse = pcall(function()
    return http.get(url, headers, true)
  end)
  if not ok or not response then
    if failedResponse then
      reason = tostring(reason) .. " " .. tostring(failedResponse.getResponseCode())
      failedResponse.close()
    end
    return nil, "HTTP request failed: " .. tostring(url) .. " (" .. tostring(ok and reason or response) .. ")"
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

local function basename(path)
  local normalized = normalizePath(path)
  local name = normalized:match("([^/]+)$")
  return name or normalized
end

local function fileNameNoExt(path)
  local name = basename(path)
  return (name:gsub("%.lua$", ""))
end

local function shouldSkipStandaloneUtility(path)
  local name = string.lower(basename(path))
  if name == "manifest.json" then
    return true
  end

  for _, suffix in ipairs(STANDALONE_SKIP_SUFFIXES) do
    if name:sub(-#suffix) == suffix then
      return true
    end
  end

  return false
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
  local data, err
  for attempt = 1, DOWNLOAD_ATTEMPTS do
    data, err = download(url)
    if data then
      break
    end
    logError("Attempt " .. attempt .. ": " .. tostring(err))
    if attempt < DOWNLOAD_ATTEMPTS then
      os.sleep(attempt)
    end
  end
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

local repoTextCache = {}

local function fetchRepoText(path, ref)
  local repoPath = normalizePath(path)
  local targetRef = tostring(ref or SOURCE_BRANCH)
  local cacheKey = targetRef .. ":" .. repoPath
  if repoTextCache[cacheKey] then
    return repoTextCache[cacheKey]
  end

  local rawUrl = withCacheBust(RAW_ROOT .. targetRef .. "/" .. repoPath)
  local data, err = download(rawUrl)
  if not data then
    local apiUrl = withCacheBust(CONTENTS_API_ROOT .. repoPath .. "?ref=" .. targetRef)
    data, err = download(apiUrl, CONTENTS_API_HEADERS)
    if not data then
      return nil, err
    end
  end

  repoTextCache[cacheKey] = data
  return data
end

local function fetchRepoTree(ref)
  local url = withCacheBust(API_URL .. "/git/trees/" .. tostring(ref or SOURCE_BRANCH) .. "?recursive=1")
  local data, err = download(url, API_HEADERS)
  if not data then
    return nil, err
  end
  return parseJson(data, "repo tree")
end

local function splitPreviewLines(text, limit)
  local lines = {}
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
    if limit and #lines >= limit then
      break
    end
  end
  return lines
end

local function parseStandaloneMetadata(fileName, text)
  local key = string.lower(fileNameNoExt(fileName))
  local name = fileNameNoExt(fileName)
  local description = ""

  for _, line in ipairs(splitPreviewLines(text, 12)) do
    local value = line:match('^%s*%-%-%s*manifest%-key:%s*(.+)%s*$')
    if value and value ~= "" then
      key = value
    else
      value = line:match('^%s*%-%-%s*manifest%-name:%s*(.+)%s*$')
      if value and value ~= "" then
        name = value
      else
        value = line:match('^%s*%-%-%s*manifest%-description:%s*(.+)%s*$')
        if value and value ~= "" and description == "" then
          description = value
        else
          value = line:match('^%s*%-%-%s*(.+)%s*$')
          if value
            and #value > 10
            and not value:match('^manifest%-(key|name|description|category):')
            and not value:match('^%S+%.lua$')
            and not value:match('^[-=]+$')
            and description == "" then
            description = value
          end
        end
      end
    end
  end

  return {
    key = key,
    name = name,
    description = description,
    category = "Utilities",
    entrypoint = fileName,
    source_root = "Utilities",
  }
end

local function findRequiredLibModules(text)
  local modules = {}
  local seen = {}

  local function addModule(module)
    if module and module ~= "" and module:sub(1, 4) == "lib." and not seen[module] then
      seen[module] = true
      modules[#modules + 1] = module
    end
  end

  for module in tostring(text or ""):gmatch('require%s*%(%s*"(lib%.[^"]+)"%s*%)') do
    addModule(module)
  end
  for module in tostring(text or ""):gmatch("require%s*%(%s*'(lib%.[^']+)'%s*%)") do
    addModule(module)
  end
  for module in tostring(text or ""):gmatch('require%s+"(lib%.[^"]+)"') do
    addModule(module)
  end
  for module in tostring(text or ""):gmatch("require%s+'(lib%.[^']+)'") do
    addModule(module)
  end

  table.sort(modules)
  return modules
end

local function buildStandaloneLibClosure(fileName, commit)
  local queue = { "Utilities/" .. fileName }
  local seenRepoPaths = { ["Utilities/" .. fileName] = true }
  local closure = {}
  local seenLibs = {}
  local index = 1

  while index <= #queue do
    local repoPath = queue[index]
    index = index + 1

    local text = fetchRepoText(repoPath, commit)
    if text then
      for _, module in ipairs(findRequiredLibModules(text)) do
        local libRelative = module:sub(5):gsub('%.', '/') .. ".lua"
        local libRepoPath = "Shared/lib/" .. libRelative
        if not seenLibs[libRelative] then
          seenLibs[libRelative] = true
          closure[#closure + 1] = libRelative
        end
        if not seenRepoPaths[libRepoPath] then
          seenRepoPaths[libRepoPath] = true
          queue[#queue + 1] = libRepoPath
        end
      end
    end
  end

  table.sort(closure)
  return closure
end

local function buildInstallFileEntry(commit, repoPath, installPath, preserveExisting)
  local data, err = fetchRepoText(repoPath, commit)
  if not data then
    return nil, err
  end

  local entry = {
    repo_path = repoPath,
    install_path = installPath,
    sha256 = computeSha256(data) or "",
  }
  if preserveExisting then
    entry.preserve_existing = true
  end
  return entry
end

local function buildStandaloneUtilitySpec(repoPath, commit)
  local fileName = basename(repoPath)
  local fileData, fileErr = fetchRepoText(repoPath, commit)
  if not fileData then
    return nil, fileErr
  end

  local meta = parseStandaloneMetadata(fileName, fileData)
  local installFiles = {}
  local runtimeFiles = {
    { repo_path = "System/runtime_startup.lua", install_path = "startup.lua" },
    { repo_path = "Shared/lib/roger_supervisor.lua", install_path = "lib/roger_supervisor.lua" },
    { repo_path = "Shared/lib/updater.lua", install_path = "lib/updater.lua" },
    { repo_path = "Shared/lib/runtime_exit.lua", install_path = "lib/runtime_exit.lua" },
    { repo_path = repoPath, install_path = fileName },
  }

  for _, item in ipairs(runtimeFiles) do
    local entry, entryErr = buildInstallFileEntry(commit, item.repo_path, item.install_path, item.preserve_existing)
    if not entry then
      return nil, entryErr
    end
    installFiles[#installFiles + 1] = entry
  end

  local libModules = {}
  for _, libRelative in ipairs(buildStandaloneLibClosure(fileName, commit)) do
    local repoLibPath = "Shared/lib/" .. libRelative
    local entry, entryErr = buildInstallFileEntry(commit, repoLibPath, "lib/" .. libRelative, false)
    if not entry then
      return nil, entryErr
    end
    installFiles[#installFiles + 1] = entry
    libModules[#libModules + 1] = "lib." .. libRelative:gsub('%.lua$', ''):gsub('/', '.')
  end

  table.sort(installFiles, function(a, b)
    if a.install_path == b.install_path then
      return a.repo_path < b.repo_path
    end
    return a.install_path < b.install_path
  end)

  local hashLines = {}
  for _, entry in ipairs(installFiles) do
    hashLines[#hashLines + 1] = tostring(entry.install_path) .. "|" .. tostring(entry.repo_path) .. "|"
      .. tostring(entry.preserve_existing == true) .. "|" .. tostring(entry.sha256 or "")
  end
  local packageHash = computeSha256(table.concat(hashLines, "\n")) or tostring(commit) .. ":" .. meta.key
  local version = "tree-" .. tostring(commit):sub(1, 7)

  return {
    schema_version = 1,
    program = {
      key = meta.key,
      name = meta.name,
      category = meta.category,
      description = meta.description,
      source_root = meta.source_root,
      entrypoint = meta.entrypoint,
      version = version,
    },
    build = {
      commit = commit,
      generated_at = tostring(os.epoch("utc") or os.epoch("local")),
      package_hash = packageHash,
    },
    install = {
      preserve = {},
      files = installFiles,
    },
    runtime = {
      boot_mode = "supervisor",
      system_entrypoint = "startup.lua",
      app_entrypoint = fileName,
      auto_restart = false,
      update_interval = DEFAULT_UPDATE_INTERVAL,
      requires_updater = true,
      lib_modules = libModules,
    },
  }
end

local function buildRepoTreeStandaloneIndex()
  local commit, commitErr = fetchLatestMainCommit()
  if not commit then
    return nil, commitErr
  end

  local tree, treeErr = fetchRepoTree(SOURCE_BRANCH)
  if not tree or type(tree.tree) ~= "table" then
    return nil, treeErr or "Repo tree missing entries"
  end

  local installerData, installerErr = fetchRepoText("System/installer.lua", commit)
  if not installerData then
    return nil, installerErr
  end

  local installerVersion = installerData:match('local%s+INSTALLER_VERSION%s*=%s*"([^"]+)"') or INSTALLER_VERSION
  local index = {
    schema_version = 1,
    generated_at = tostring(os.epoch("utc") or os.epoch("local")),
    repo = {
      owner = REPO_OWNER,
      name = REPO_NAME,
      branch = SOURCE_BRANCH,
    },
    installer = {
      version = installerVersion,
      commit = commit,
      path = "System/installer.lua",
      sha256 = computeSha256(installerData) or "",
    },
    programs = {},
    _inline_specs = {},
    _catalog_source = "repo tree",
  }

  local repoPaths = {}
  for _, entry in ipairs(tree.tree) do
    if entry.type == "blob" and type(entry.path) == "string" then
      local utilityFile = entry.path:match('^Utilities/([^/]+%.lua)$')
      if utilityFile and not shouldSkipStandaloneUtility(utilityFile) then
        local hiddenKey = string.lower(fileNameNoExt(utilityFile))
        if not HIDDEN_STANDALONE_PROGRAMS[hiddenKey] then
          repoPaths[#repoPaths + 1] = normalizePath(entry.path)
        end
      end
    end
  end
  table.sort(repoPaths)

  for _, repoPath in ipairs(repoPaths) do
    local spec, specErr = buildStandaloneUtilitySpec(repoPath, commit)
    if spec then
      local program = spec.program or {}
      index.programs[program.key] = {
        name = program.name,
        category = program.category,
        description = program.description,
        version = program.version,
        commit = commit,
        package_hash = spec.build and spec.build.package_hash or "",
      }
      index._inline_specs[program.key] = spec
    else
      logError("Repo tree utility discovery failed for " .. tostring(repoPath) .. ": " .. tostring(specErr))
    end
  end

  return index
end

local function mergeRepoTreeStandalonePrograms(index, directIndex)
  if type(index) ~= "table" then
    return directIndex
  end
  if type(directIndex) ~= "table" then
    return index
  end

  index.programs = index.programs or {}
  index._inline_specs = index._inline_specs or {}

  for key, spec in pairs(directIndex._inline_specs or {}) do
    index._inline_specs[key] = spec
  end

  for key, program in pairs(directIndex.programs or {}) do
    local existing = index.programs[key]
    if not existing then
      index.programs[key] = program
    else
      if existing.name == key then
        existing.name = program.name
      end
      if (not existing.description or existing.description == "") and program.description and program.description ~= "" then
        existing.description = program.description
      end
      if not existing.category or existing.category == "" then
        existing.category = program.category
      end
    end
  end

  if not index.installer and directIndex.installer then
    index.installer = directIndex.installer
  end

  index._catalog_source = "deploy index + repo tree"
  return index
end

local function fetchLatestIndex()
  local deployIndex, deployErr = fetchDeployJson("latest.json", "deploy index")
  local directIndex, directErr = buildRepoTreeStandaloneIndex()

  if deployIndex and directIndex then
    return mergeRepoTreeStandalonePrograms(deployIndex, directIndex)
  end

  if deployIndex then
    deployIndex._catalog_source = "deploy index"
    return deployIndex
  end

  if directIndex then
    return directIndex
  end

  return nil, "Deploy index failed: " .. tostring(deployErr) .. "; repo tree failed: " .. tostring(directErr)
end

local function fetchProgramSpec(specPath)
  return fetchDeployJson(specPath, "program spec")
end

fetchLatestMainCommit = function()
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

local function buildInstalledRecord(spec, previous)
  local program = spec.program or {}
  local build = spec.build or {}
  local runtime = spec.runtime or {}
  local existing = previous or {}
  local now = os.epoch("local")

  return {
    schema_version = INSTALL_STATE_SCHEMA,
    program = program.key,
    name = program.name,
    category = program.category or existing.category,
    version = program.version,
    source_commit = build.commit,
    package_hash = build.package_hash,
    content_hash = build.package_hash,
    spec_path = spec._spec_path or existing.spec_path or "",
    installed_at = existing.installed_at or now,
    updated_at = now,
    last_package_update_at = now,
    boot_mode = runtime.boot_mode or "supervisor",
    system_entrypoint = runtime.system_entrypoint or "startup.lua",
    app_entrypoint = runtime.app_entrypoint or program.entrypoint or "",
    auto_restart = runtime.auto_restart ~= false,
    update_interval = tonumber(runtime.update_interval) or DEFAULT_UPDATE_INTERVAL,
  }
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

local HOST_CLAIM_WAIT_MS = 60000

local function claimPhoneHostIfNeeded(shouldClaim)
  if not shouldClaim then
    return true
  end

  if not ccvault or type(ccvault.claimHost) ~= "function" then
    return false, "ccvault.claimHost is unavailable"
  end

  -- Since vhcctweaks 2.2.35 a claim lands when the player clicks [CONFIRM] in chat, so wait for it
  local ok, result, err = pcall(ccvault.claimHost)
  if not ok then
    return false, tostring(result)
  end
  if type(result) ~= "table" then
    print(tostring(err or "Confirm the host claim in chat."))
    local deadline = os.epoch("utc") + HOST_CLAIM_WAIT_MS
    while os.epoch("utc") < deadline do
      os.sleep(0.5)
      local infoOk, info = pcall(ccvault.getSessionInfo)
      if infoOk and type(info) == "table" and info.isSelfPlay then
        result = { hostName = info.playerName, changed = true }
        break
      end
    end
    if type(result) ~= "table" then
      return false, "host claim was not confirmed in chat"
    end
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

  -- The claimer is here and is now the owner, the one moment this cannot be refused. Failing to lock must not fail the install
  if type(ccvault.isTerminalLocked) == "function" and type(ccvault.setTerminalLock) == "function" then
    local checked, locked = pcall(ccvault.isTerminalLocked)
    if checked and locked == false then pcall(ccvault.setTerminalLock, true) end
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

local function addPreservedPath(set, path)
  local normalized = normalizePath(path)
  if normalized == "" or normalized == "." then
    return
  end

  set[normalized] = true

  local current = normalized
  while true do
    local parent = fs.getDir(current)
    if parent == nil or parent == "" or parent == "." or parent == current then
      break
    end
    set[normalizePath(parent)] = true
    current = parent
  end
end

local function wipePathRecursive(path, preserved, stats)
  local normalized = normalizePath(path)
  if normalized == "" or normalized == "." or preserved[normalized] then
    return
  end

  if not fs.exists(path) then
    return
  end

  if fs.isReadOnly(path) then
    return
  end

  if fs.isDir(path) then
    for _, name in ipairs(fs.list(path)) do
      wipePathRecursive(fs.combine(path, name), preserved, stats)
    end

    if fs.exists(path) and #fs.list(path) == 0 and not preserved[normalized] then
      fs.delete(path)
      stats.removed_dirs = stats.removed_dirs + 1
    end
    return
  end

  fs.delete(path)
  stats.removed_files = stats.removed_files + 1
end

local function wipeComputerKeepInstaller()
  local runningProgram = normalizePath(shell.getRunningProgram() or "installer.lua")
  if runningProgram == "" then
    runningProgram = "installer.lua"
  end

  local preserved = {}
  addPreservedPath(preserved, runningProgram)
  addPreservedPath(preserved, "installer.lua")
  addPreservedPath(preserved, UNLOCK_FILE)

  local stats = {
    removed_files = 0,
    removed_dirs = 0,
  }

  for _, name in ipairs(fs.list(".")) do
    wipePathRecursive(name, preserved, stats)
  end

  return stats, runningProgram
end

local function confirmFullWipe()
  cprint(colors.red, "WARNING: this will delete everything on this computer except the installer script and protected system files.")
  cprint(colors.red, "Programs, configs, logs, managed files, and local data will be removed.")
  print("")
  cwrite(colors.white, "Type WIPE to continue: ")
  local input = read()
  return type(input) == "string" and input:upper() == "WIPE"
end

local function runFullWipe(interactive)
  header("Wipe Computer")

  if interactive ~= false and not confirmFullWipe() then
    cprint(colors.yellow, "Wipe cancelled.")
    return false
  end

  local unlockOk, unlockResult = beginWriteWindow("installer-wipe")
  if not unlockOk then
    cprint(colors.red, "Could not open update window: " .. tostring(unlockResult))
    logError("Wipe unlock failed: " .. tostring(unlockResult))
    return false
  end

  local createdUnlock = unlockResult == true
  local ok, statsOrErr, installerPath = pcall(wipeComputerKeepInstaller)
  endWriteWindow(createdUnlock)

  if not ok then
    cprint(colors.red, "Wipe failed: " .. tostring(statsOrErr))
    logError("Wipe failed: " .. tostring(statsOrErr))
    return false
  end

  cprint(colors.lime, "Computer wiped.")
  cprint(colors.white, "Kept: " .. tostring(installerPath))
  cprint(colors.gray, "Read-only system paths like rom are preserved.")
  cprint(colors.gray, "Removed files: " .. tostring(statsOrErr.removed_files))
  cprint(colors.gray, "Removed directories: " .. tostring(statsOrErr.removed_dirs))
  print("")
  cprint(colors.white, "The installer remains so you can reinstall anything later.")
  return true
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
    local bar = "  " .. progressBar(index, total, 12) .. "  "
    local room = math.max(1, W - #bar - 1)
    cwrite(colors.white, bar .. label:sub(math.max(1, #label - room + 1)) .. " ")

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
    saveInstalled(buildInstalledRecord(spec, installedBefore))
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
local function selfUpdate(index, silent, commandArgs)
  local installer = index and index.installer or nil
  if type(installer) ~= "table" then
    if not silent then
      cprint(colors.red, "No installer metadata in deploy index.")
    end
    return "error", "No installer metadata in deploy index"
  end

  local needsUpdate = isNewer(installer.version, INSTALLER_VERSION)
  if not needsUpdate then
    local myPath = shell.getRunningProgram()
    local currentData = readFile(myPath, true)
    -- textutils.sha256 does not exist in game: fall back to the hash of the last installer saved here.
    local currentHash = currentData and computeSha256(currentData) or readFile(INSTALLER_HASH_FILE, false)
    if currentHash and installer.sha256 then
      needsUpdate = string.lower(currentHash) ~= string.lower(installer.sha256)
    end
  end

  if not needsUpdate then
    if not silent then
      cprint(colors.lime, "Installer is up to date (v" .. INSTALLER_VERSION .. ")")
    end
    return "current"
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
    return "error", tostring(unlockResult)
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
    return "error", "Could not resolve installer source commit"
  end

  local myPath = shell.getRunningProgram()
  local data, err = download(buildCommitUrl(commit, installer.path))
  if data and verifyHash(data, installer.sha256) then
    local ok, saveErr = saveFile(myPath, data)
    if ok then
      saveFile(INSTALLER_HASH_FILE, tostring(installer.sha256 or ""))
      if not silent then
        cprint(colors.lime, "Done! Restarting...")
      end
      endWriteWindow(createdUnlock)
      local args = commandArgs or tArgs
      shell.run(myPath, UPDATED_ARG, tostring(installer.version or "?"), tostring(INSTALLER_VERSION), unpackArgs(args))
      return "updated"
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
  return "error", tostring(err)
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
      Apps = 2,
      Utilities = 3,
      Other = 4,
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

local function installByKey(index, programKey, forceConfig)
  local programEntry = index.programs and index.programs[programKey] or nil
  if not programEntry then
    cprint(colors.red, "Unknown program: " .. tostring(programKey))
    return false
  end

  local spec = index._inline_specs and index._inline_specs[programKey] or nil
  if not spec then
    local specErr
    spec, specErr = fetchProgramSpec(programEntry.spec_path)
    if not spec then
      cprint(colors.red, "Could not fetch package spec: " .. tostring(specErr))
      logError("Spec fetch failed for " .. tostring(programKey) .. ": " .. tostring(specErr))
      return false
    end
    spec._spec_path = programEntry.spec_path
  else
    spec._spec_path = programEntry.spec_path or ("repo-tree:" .. tostring(programKey))
  end

  return installFromSpec(spec, forceConfig, loadInstalled())
end

---------------------------------------------------------------------------
-- The desktop: a windowed installer driven by the mouse, or by the keyboard on a computer that has none.
-- Everything is drawn on the terminal. The install code itself still just prints: it runs inside a window.
---------------------------------------------------------------------------
local function isColour()
  return term.isColour ~= nil and term.isColour()
end

--- A colour, or its stand-in on a computer with no colour screen.
local function shade(colour, mono)
  if isColour() then
    return colour
  end
  return mono
end

local function theme()
  return {
    desk = shade(colors.cyan, colors.gray),
    bar = shade(colors.blue, colors.black),
    barText = colors.white,
    pane = colors.white,
    paneText = colors.black,
    mute = colors.gray,
    side = colors.lightGray,
    picked = shade(colors.purple, colors.black),
    pickedText = colors.white,
    good = shade(colors.green, colors.gray),
    warn = shade(colors.orange, colors.gray),
    bad = shade(colors.red, colors.black),
    task = colors.gray,
  }
end

--- Text cut or padded to exactly width.
local function fit(text, width)
  text = tostring(text or "")
  if width <= 0 then
    return ""
  end
  if #text > width then
    if width <= 2 then
      return text:sub(1, width)
    end
    return text:sub(1, width - 2) .. ".."
  end
  return text .. string.rep(" ", width - #text)
end

local function put(x, y, text, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg)
  term.setBackgroundColor(bg)
  term.write(text)
end

local function fillBox(x, y, w, h, bg)
  local row = string.rep(" ", math.max(0, w))
  term.setBackgroundColor(bg)
  for j = y, y + h - 1 do
    term.setCursorPos(x, j)
    term.write(row)
  end
end

--- Split text into lines of at most width, at spaces.
local function wrapText(text, width)
  local lines, line = {}, ""
  for word in tostring(text or ""):gmatch("%S+") do
    if line ~= "" and #line + 1 + #word > width then
      lines[#lines + 1] = line
      line = word
    else
      line = line == "" and word or (line .. " " .. word)
    end
  end
  if line ~= "" then
    lines[#lines + 1] = line
  end
  return lines
end

--- Is the installed copy of a program behind the catalog?
local function hasUpdate(installed, prog)
  return (installed.source_commit or "") ~= (prog.commit or "")
    or (installed.package_hash or installed.content_hash or "") ~= (prog.package_hash or "")
end

--- A click only counts on what is on top: regions are hit newest first.
local function regionAt(regions, x, y)
  for i = #regions, 1, -1 do
    local r = regions[i]
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
      return r
    end
  end
  return nil
end

--- A small window with buttons. buttons is a list of { id, label }; Enter picks the first, Esc the last.
local function dialog(title, message, buttons, danger)
  local T = theme()
  local w = math.min(W - 2, 38)
  local lines = wrapText(message, w - 4)
  local h = math.min(H - 2, #lines + 5)
  local x, y = math.floor((W - w) / 2) + 1, math.floor((H - h) / 2) + 1
  local regions = {}

  fillBox(x, y, w, h, T.pane)
  put(x, y, fit(" " .. title, w), T.barText, danger and T.bad or T.bar)
  for i = 1, h - 5 + #lines do
    if lines[i] and y + 1 + i < y + h - 2 + 1 then
      put(x + 2, y + 1 + i, fit(lines[i], w - 4), T.paneText, T.pane)
    end
  end

  local bx = x + w - 2
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    local label = " " .. b.label .. " "
    bx = bx - #label
    local colour = i == 1 and (danger and T.bad or T.good) or T.side
    put(bx, y + h - 2, label, i == 1 and colors.white or colors.black, colour)
    regions[#regions + 1] = { x = bx, y = y + h - 2, w = #label, h = 1, id = b.id }
    bx = bx - 1
  end

  while true do
    local event, a, b, c = os.pullEvent()
    if event == "mouse_click" then
      local hit = regionAt(regions, b, c)
      if hit then
        return hit.id
      end
    elseif event == "key" and not b then
      if a == keys.enter then
        return buttons[1].id
      elseif a == keys.backspace or a == keys.tab or a == keys.q then
        return buttons[#buttons].id
      end
    end
  end
end

--- Run something that prints, inside a window, and wait for the player to close it.
-- fn gets to print and read as usual. Returns what it returned.
local function inWindow(title, fn, buttons)
  local T = theme()
  local x, y, w, h = 2, 2, W - 2, H - 2
  if W < 40 then
    x, y, w, h = 1, 1, W, H
  end
  fillBox(x, y, w, h, T.pane)
  put(x, y, fit(" " .. title, w), T.barText, T.bar)
  local screen = window.create(term.current(), x, y + 1, w, h - 2, true)
  screen.setBackgroundColor(colors.black)
  screen.setTextColor(colors.white)
  screen.clear()

  local outerW, outerH = W, H
  local previous = term.redirect(screen)
  W, H = term.getSize()
  term.setCursorPos(1, 1)
  local ok, result = pcall(fn)
  term.redirect(previous)
  W, H = outerW, outerH
  if not ok then
    logError(tostring(result))
    if tostring(result):find("Terminated", 1, true) then
      error(result, 0)
    end
  end

  fillBox(x, y + h - 1, w, 1, T.pane)
  local regions = {}
  local list = buttons(ok and result)
  local bx = x + w - 1
  for i = #list, 1, -1 do
    local b = list[i]
    local label = " " .. b.label .. " "
    bx = bx - #label
    put(bx, y + h - 1, label, i == 1 and colors.white or colors.black, i == 1 and T.good or T.side)
    regions[#regions + 1] = { x = bx, y = y + h - 1, w = #label, h = 1, id = b.id }
    bx = bx - 1
  end
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "mouse_click" then
      local hit = regionAt(regions, b, c)
      if hit then
        return ok and result, hit.id
      end
    elseif event == "key" and not b and (a == keys.enter or a == keys.q) then
      return ok and result, list[1].id
    end
  end
end

--- The list of programs for a folder, with what each one is on this computer.
local function folderEntries(folder, index, installed)
  local key = installed and (installed.program or installed.game) or nil
  local out = {}
  for _, entry in ipairs(folder.entries) do
    local prog = index.programs and index.programs[entry.key] or {}
    local state = ""
    if entry.key == key then
      state = hasUpdate(installed, prog) and "update" or "installed"
    end
    out[#out + 1] = { key = entry.key, name = entry.name, ver = entry.ver, desc = entry.desc, state = state, category = prog.category }
  end
  return out
end

local function allFolder(index)
  local entries = {}
  for _, folder in ipairs(buildProgramGroups(index)) do
    for _, entry in ipairs(folder.entries) do
      entries[#entries + 1] = entry
    end
  end
  table.sort(entries, function(a, b)
    return a.name < b.name
  end)
  return { key = "all", name = "All", count = #entries, entries = entries }
end

local function loadInstalledRecord()
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
  return installed
end

--- Throw away anything typed before the desktop was up: the Enter that started the installer must not press a button.
local function dropWaitingInput()
  os.queueEvent("installer_ready")
  os.pullEvent("installer_ready")
end

local function runDesktop(index, notice)
  dropWaitingInput()
  local T = theme()
  local s = { folder = 1, sel = 1, top = 1, menu = false, regions = {}, lastClick = 0, lastRow = nil, notice = notice }
  local installed, folders, entries

  local function reload()
    installed = loadInstalledRecord()
    folders = buildProgramGroups(index)
    table.insert(folders, 1, allFolder(index))
    s.folder = math.min(s.folder, #folders)
    entries = folderEntries(folders[s.folder], index, installed)
    s.sel = math.max(1, math.min(s.sel, #entries))
  end

  local function selected()
    return entries[s.sel]
  end

  local function pickFolder(i)
    s.folder, s.sel, s.top = i, 1, 1
    entries = folderEntries(folders[i], index, installed)
  end

  --- Layout for this terminal. A narrow screen, such as a pocket computer, swaps the sidebar for a row of arrows.
  local function geometry()
    local narrow = W < 40
    local sideW = narrow and 0 or 14
    local detailH = H >= 16 and 6 or 4
    local listY = narrow and 3 or 2
    local listH = H - detailH - listY
    return { narrow = narrow, sideW = sideW, detailH = detailH, listX = sideW + 1, listY = listY, listW = W - sideW - 1, listH = math.max(1, listH) }
  end

  local function keepInView(g)
    if s.sel < s.top then
      s.top = s.sel
    elseif s.sel >= s.top + g.listH then
      s.top = s.sel - g.listH + 1
    end
    s.top = math.max(1, math.min(s.top, math.max(1, #entries - g.listH + 1)))
  end

  local function button(x, y, label, bg, fg, id)
    local text = " " .. label .. " "
    put(x, y, text, fg, bg)
    s.regions[#s.regions + 1] = { x = x, y = y, w = #text, h = 1, id = id }
    return x + #text + 1
  end

  local function drawSidebar(g)
    if g.narrow then
      local folder = folders[s.folder]
      put(1, 2, fit("", W), T.paneText, T.side)
      button(1, 2, "<", T.side, T.paneText, "prevFolder")
      button(W - 2, 2, ">", T.side, T.paneText, "nextFolder")
      put(5, 2, fit(folder.name .. " (" .. folder.count .. ")", W - 8), T.paneText, T.side)
      return
    end
    fillBox(1, 2, g.sideW, H - 2, T.side)
    for i, folder in ipairs(folders) do
      local y = 2 + i
      if y >= H then
        break
      end
      local active = i == s.folder
      local text = fit(" " .. folder.name, g.sideW - 4) .. string.format("%3d ", folder.count)
      put(1, y, text, active and T.pickedText or T.paneText, active and T.picked or T.side)
      s.regions[#s.regions + 1] = { x = 1, y = y, w = g.sideW, h = 1, id = "folder", value = i }
    end
  end

  local function drawList(g)
    fillBox(g.listX, g.listY, g.listW + 1, g.listH, T.pane)
    keepInView(g)
    for row = 0, g.listH - 1 do
      local i = s.top + row
      local entry = entries[i]
      local y = g.listY + row
      if entry then
        local picked = i == s.sel
        local bg = picked and T.picked or T.pane
        local mark = entry.state == "update" and "^" or (entry.state == "installed" and "*" or " ")
        local ver = "v" .. tostring(entry.ver or "?")
        local nameW = g.listW - #ver - 4
        put(g.listX, y, " " .. mark .. " " .. fit(entry.name, nameW), picked and T.pickedText or T.paneText, bg)
        put(g.listX + 3 + nameW, y, " " .. ver, picked and T.pickedText or T.mute, bg)
        s.regions[#s.regions + 1] = { x = g.listX, y = y, w = g.listW, h = 1, id = "row", value = i }
      end
    end
    -- scrollbar: the part of the list on show, and a click above or below it pages
    local barX = W
    local total = #entries
    if total > g.listH then
      fillBox(barX, g.listY, 1, g.listH, T.side)
      local thumbH = math.max(1, math.floor(g.listH * g.listH / total))
      local room = g.listH - thumbH
      local thumbY = g.listY + math.floor(room * (s.top - 1) / math.max(1, total - g.listH) + 0.5)
      fillBox(barX, thumbY, 1, thumbH, T.bar)
      s.regions[#s.regions + 1] = { x = barX, y = g.listY, w = 1, h = thumbY - g.listY, id = "pageUp" }
      s.regions[#s.regions + 1] = { x = barX, y = thumbY + thumbH, w = 1, h = g.listY + g.listH - thumbY - thumbH, id = "pageDown" }
    end
  end

  local function drawDetails(g)
    local y = H - g.detailH
    local x = g.listX
    local w = W - x + 1
    fillBox(x, y, w, g.detailH, shade(colors.lightBlue, colors.lightGray))
    local entry = selected()
    local bg = shade(colors.lightBlue, colors.lightGray)
    if not entry then
      put(x + 1, y + 1, fit("Nothing here yet", w - 2), T.paneText, bg)
      return
    end
    put(x + 1, y, fit(entry.name .. " v" .. tostring(entry.ver or "?"), w - 2), colors.black, bg)
    local status = entry.state == "update" and "Update available" or (entry.state == "installed" and "Installed here" or "Not installed")
    if g.detailH >= 6 then
      put(x + 1, y + 1, fit(status, w - 2), T.mute, bg)
      local lines = wrapText(entry.desc, w - 2)
      if lines[1] then put(x + 1, y + 2, fit(lines[1], w - 2), colors.black, bg) end
      if lines[2] then put(x + 1, y + 3, fit(lines[2], w - 2), colors.black, bg) end
    end
    local by = H - 2
    local bx = x + 1
    if entry.state == "update" then
      bx = button(bx, by, "Update", T.good, colors.white, "update")
      button(bx, by, "Reset", T.side, colors.black, "reset")
    elseif entry.state == "installed" then
      bx = button(bx, by, "Reinstall", T.good, colors.white, "update")
      button(bx, by, "Reset", T.side, colors.black, "reset")
    else
      button(bx, by, "Install", T.good, colors.white, "install")
    end
  end

  local function drawTaskbar()
    put(1, H, fit("", W), colors.white, T.task)
    button(1, H, "Menu", s.menu and T.picked or T.task, colors.white, "menu")
    local text = s.notice
    if not text then
      if installed then
        local key = installed.program or installed.game
        local prog = index.programs and index.programs[key] or nil
        text = tostring(prog and prog.name or installed.name or key) .. " on this computer"
      else
        text = "Nothing installed yet"
      end
    end
    put(8, H, fit(text, W - 8), colors.lightGray, T.task)
  end

  local function drawMenu()
    if not s.menu then
      return
    end
    local items = { { "refresh", "Refresh list" }, { "wipe", "Wipe computer" }, { "exit", "Exit" } }
    local w = 16
    local y = H - #items - 1
    fillBox(1, y - 1, w, #items + 2, T.task)
    for i, item in ipairs(items) do
      local row = y + i - 1
      put(1, row, fit("  " .. item[2], w), colors.white, T.task)
      s.regions[#s.regions + 1] = { x = 1, y = row, w = w, h = 1, id = item[1], inMenu = true }
    end
  end

  local function draw()
    W, H = term.getSize()
    s.regions = {}
    local g = geometry()
    term.setBackgroundColor(T.desk)
    term.clear()
    put(1, 1, fit(" Roger Installer", W), T.barText, T.bar)
    put(W - 12, 1, "v" .. INSTALLER_VERSION, colors.lightGray, T.bar)
    put(W - 2, 1, " X ", colors.white, T.bad)
    s.regions[#s.regions + 1] = { x = W - 2, y = 1, w = 3, h = 1, id = "exit" }
    drawSidebar(g)
    drawList(g)
    drawDetails(g)
    drawTaskbar()
    drawMenu()
  end

  local function restartChoice(ok)
    if ok then
      return { { id = "restart", label = "Restart now" }, { id = "close", label = "Later" } }
    end
    return { { id = "close", label = "Close" } }
  end

  local function install(entry, forceConfig)
    local _, choice = inWindow("Installing " .. entry.name, function()
      return installByKey(index, entry.key, forceConfig)
    end, restartChoice)
    if choice == "restart" then
      term.setBackgroundColor(colors.black)
      term.clear()
      os.reboot()
    end
    reload()
  end

  local function act(id, value)
    local entry = selected()
    if id == "folder" then
      pickFolder(value)
    elseif id == "prevFolder" then
      pickFolder((s.folder - 2) % #folders + 1)
    elseif id == "nextFolder" then
      pickFolder(s.folder % #folders + 1)
    elseif id == "pageUp" then
      s.sel = math.max(1, s.sel - geometry().listH)
    elseif id == "pageDown" then
      s.sel = math.min(#entries, s.sel + geometry().listH)
    elseif id == "update" and entry then
      install(entry, false)
    elseif id == "reset" and entry then
      local yes = dialog("Reset " .. entry.name, "Reinstall and put its settings back to their defaults? Saved records are kept.", {
        { id = "yes", label = "Reset" }, { id = "no", label = "Cancel" },
      }, true)
      if yes == "yes" then
        install(entry, true)
      end
    elseif id == "install" and entry then
      local question = "Install " .. entry.name .. " on this computer?"
      if installed then
        local name = installed.name or installed.program or installed.game
        question = "Replace " .. tostring(name) .. " with " .. entry.name .. "? Saved records are kept."
      end
      if dialog("Install", question, { { id = "yes", label = "Install" }, { id = "no", label = "Cancel" } }) == "yes" then
        install(entry, true)
      end
    elseif id == "menu" then
      s.menu = not s.menu
      return true
    elseif id == "refresh" then
      local fresh, err = fetchLatestIndex()
      if fresh then
        index = fresh
        s.notice = "List refreshed"
        reload()
      else
        s.notice = "Could not refresh"
        logError("Refresh failed: " .. tostring(err))
      end
    elseif id == "wipe" then
      inWindow("Wipe Computer", function()
        return runFullWipe(true)
      end, function()
        return { { id = "close", label = "Close" } }
      end)
      reload()
    elseif id == "exit" then
      return "exit"
    end
    return nil
  end

  reload()
  while true do
    draw()
    local event, a, b, c = os.pullEvent()
    local result
    if event == "mouse_click" then
      local hit = regionAt(s.regions, b, c)
      local wasOpen = s.menu
      if wasOpen and not (hit and (hit.inMenu or hit.id == "menu")) then
        s.menu = false -- a click outside an open menu closes it and does nothing else
      elseif hit and hit.id == "row" then
        s.menu = false
        local now = os.epoch("utc")
        local double = s.lastRow == hit.value and now - s.lastClick < 500
        s.sel, s.lastRow, s.lastClick = hit.value, hit.value, now
        if double then
          -- a double click does what the main button does
          local entry = selected()
          result = act(entry.state == "" and "install" or "update")
          s.lastRow = nil
        end
      elseif hit then
        if hit.id ~= "menu" then s.menu = false end
        result = act(hit.id, hit.value)
      end
      s.notice = (hit and (hit.id == "refresh")) and s.notice or nil
    elseif event == "mouse_scroll" then
      s.top = s.top + a
      s.sel = math.max(1, math.min(#entries, s.sel + a))
    elseif event == "key" and (not b or a == keys.up or a == keys.down) then -- holding a key only ever scrolls
      if a == keys.up then
        s.sel = math.max(1, s.sel - 1)
      elseif a == keys.down then
        s.sel = math.min(#entries, s.sel + 1)
      elseif a == keys.left then
        result = act("prevFolder")
      elseif a == keys.right then
        result = act("nextFolder")
      elseif a == keys.pageUp then
        result = act("pageUp")
      elseif a == keys.pageDown then
        result = act("pageDown")
      elseif a == keys.enter then
        local entry = selected()
        if entry then
          result = act(entry.state == "" and "install" or "update")
        end
      elseif a == keys.m then
        s.menu = not s.menu
      elseif a == keys.r then
        result = act("reset")
      elseif a == keys.w then
        result = act("wipe")
      elseif a == keys.q then
        result = "exit"
      end
    end
    if result == "exit" then
      return
    end
  end
end

local function leaveDesktop()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------
local function main()
  local commandArgs, updatedTo, updatedFrom = parseInstallerArgs(tArgs)
  local index, indexErr = fetchLatestIndex()
  if not index then
    cprint(colors.red, "Installer self-check failed: " .. tostring(indexErr))
    cprint(colors.red, "Refusing to continue because installer freshness could not be verified.")
    print("")
    cprint(colors.gray, "Check that HTTP is enabled in the server config")
    cprint(colors.gray, "and that github.com is allowed.")
    logError("Installer self-check failed: " .. tostring(indexErr))
    return
  end

  local selfUpdateStatus, selfUpdateErr = selfUpdate(index, true, commandArgs)
  if selfUpdateStatus == "updated" then
    return
  end
  if selfUpdateStatus == "error" then
    cprint(colors.red, "Installer self-update failed: " .. tostring(selfUpdateErr or "Unknown error"))
    cprint(colors.red, "Refusing to continue until the installer is verified current.")
    logError("Installer self-update failed: " .. tostring(selfUpdateErr))
    return
  end

  if updatedTo then
    cprint(colors.lime, "Installer updated to v" .. tostring(updatedTo)
      .. (updatedFrom and updatedFrom ~= "" and (" from v" .. tostring(updatedFrom)) or "") .. ".")
    print("")
  end

  if commandArgs[1] == "self-update" then
    cprint(colors.lime, "Installer is up to date (v" .. INSTALLER_VERSION .. ")")
    return
  end

  if commandArgs[1] == "update" then
    local installed = loadInstalled()
    if not installed then
      cprint(colors.red, "No program installed. Run 'installer' to install.")
      return
    end
    local key = installed.program or installed.game
    installByKey(index, key, false)
    return
  end

  if commandArgs[1] == "wipe" then
    runFullWipe(true)
    return
  end

  if commandArgs[1] and commandArgs[1] ~= "" then
    installByKey(index, string.lower(commandArgs[1]), false)
    return
  end

  local notice = updatedTo and ("Installer updated to v" .. tostring(updatedTo)) or nil
  runDesktop(index, notice)
  leaveDesktop()
end

local ok, err = pcall(main)
if not ok then
  logError("CRASH: " .. tostring(err))
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.red)
  print("\nInstaller crashed: " .. tostring(err))
  print("See " .. LOG_FILE)
  term.setTextColor(colors.white)
end
