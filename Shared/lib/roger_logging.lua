local M = {}

local DEFAULT_LEVEL = "INFO"
local DEFAULT_NAMESPACE = "Roger"
local DEFAULT_BUNDLE_DIR = ".roger_logs"
local DEFAULT_MAX_PART_BYTES = 180000
local DEFAULT_MAX_LINES_PER_FILE = 400
local DEFAULT_MAX_BYTES_PER_FILE = 64000

local appendLine = nil
local ensureDir = nil
local readWholeFile = nil
local writeWholeFile = nil
local getAttributes = nil
local isCandidateLogFile = nil
local listBundleCandidates = nil
local buildSummaryBlock = nil
local buildFileSection = nil
local buildBundleParts = nil
local uploadBundleParts = nil

local function normalizeLevel(level)
  local raw = tostring(level or DEFAULT_LEVEL)
  if raw == "" then
    return DEFAULT_LEVEL
  end
  return string.upper(raw)
end

local function normalizeNamespace(namespace)
  local raw = tostring(namespace or DEFAULT_NAMESPACE)
  if raw == "" then
    return DEFAULT_NAMESPACE
  end
  return raw
end

ensureDir = function(path)
  if type(path) ~= "string" or path == "" then
    return true
  end

  if fs.exists(path) then
    return fs.isDir(path)
  end

  local ok, err = pcall(function()
    fs.makeDir(path)
  end)
  if not ok then
    return false, tostring(err)
  end

  return true
end

appendLine = function(path, message, level, namespace, echoToTerminal)
  assert(type(path) == "string", "path must be a string")

  local handle = fs.open(path, "a")
  if not handle then
    return false, "Cannot open log file: " .. path
  end

  local line = "[" .. os.epoch("local") .. "]"
    .. " [" .. normalizeLevel(level) .. "]"
    .. " [" .. normalizeNamespace(namespace) .. "] "
    .. tostring(message)

  handle.writeLine(line)
  handle.close()

  if echoToTerminal then
    print(line)
  end

  return true
end

readWholeFile = function(path)
  if not fs.exists(path) or fs.isDir(path) then
    return nil
  end

  local handle = fs.open(path, "r")
  if not handle then
    return nil
  end

  local data = handle.readAll()
  handle.close()
  return data
end

writeWholeFile = function(path, content)
  local handle = fs.open(path, "w")
  if not handle then
    return false, "Cannot open output file: " .. tostring(path)
  end

  handle.write(content)
  handle.close()
  return true
end

getAttributes = function(path)
  local size = 0
  local modified = 0

  if type(fs.attributes) == "function" then
    local ok, attrs = pcall(function()
      return fs.attributes(path)
    end)
    if ok and type(attrs) == "table" then
      size = tonumber(attrs.size) or size
      modified = tonumber(attrs.modified) or modified
    end
  elseif type(fs.getSize) == "function" and fs.exists(path) and not fs.isDir(path) then
    local ok, result = pcall(function()
      return fs.getSize(path)
    end)
    if ok and tonumber(result) then
      size = tonumber(result)
    end
  end

  return {
    size = size,
    modified = modified,
  }
end

isCandidateLogFile = function(path)
  local name = string.lower(tostring(path or ""))
  if name == "" then
    return false
  end

  if name == ".installed_program" or name == ".roger_managed_files" or name == "debug.txt" then
    return true
  end

  if name == "settings" or name == "vhcc_lockdown.txt" or name == ".vhcc_unlock" then
    return true
  end

  if name:match("%.log$") then
    return true
  end

  return false
end

listBundleCandidates = function(options)
  local bundleDir = tostring(options.bundleDir or DEFAULT_BUNDLE_DIR)
  local paths = {}
  local entries = fs.list("")

  for _, entry in ipairs(entries) do
    if entry ~= bundleDir and not fs.isDir(entry) and isCandidateLogFile(entry) then
      paths[#paths + 1] = entry
    end
  end

  table.sort(paths, function(left, right)
    local leftAttrs = getAttributes(left)
    local rightAttrs = getAttributes(right)
    if leftAttrs.modified == rightAttrs.modified then
      return left < right
    end
    return leftAttrs.modified > rightAttrs.modified
  end)

  return paths
end

local function trimToLastLines(raw, maxLines)
  local lines = {}
  for line in tostring(raw or ""):gmatch("([^\n]*)\n?") do
    if line == "" and #lines > 0 and lines[#lines] == "" then
      break
    end
    lines[#lines + 1] = line
  end

  if #lines <= maxLines then
    return table.concat(lines, "\n"), 0
  end

  local kept = {}
  for index = #lines - maxLines + 1, #lines do
    kept[#kept + 1] = lines[index]
  end
  return table.concat(kept, "\n"), #lines - maxLines
end

buildSummaryBlock = function(paths)
  local lines = {}
  local installInfo = nil
  local installRaw = readWholeFile(".installed_program")

  if installRaw and type(textutils.unserialise) == "function" then
    local ok, parsed = pcall(function()
      return textutils.unserialise(installRaw)
    end)
    if ok and type(parsed) == "table" then
      installInfo = parsed
    end
  end

  lines[#lines + 1] = "Roger-Code Log Bundle"
  lines[#lines + 1] = "Generated at: " .. tostring(os.epoch("local"))

  local label = nil
  if type(os.getComputerLabel) == "function" then
    label = os.getComputerLabel()
  elseif type(os.computerLabel) == "function" then
    label = os.computerLabel()
  end

  local computerId = nil
  if type(os.getComputerID) == "function" then
    computerId = os.getComputerID()
  elseif type(os.computerID) == "function" then
    computerId = os.computerID()
  end

  lines[#lines + 1] = "Computer ID: " .. tostring(computerId or "unknown")
  lines[#lines + 1] = "Computer Label: " .. tostring(label or "<none>")

  if installInfo then
    lines[#lines + 1] = "Installed Program: " .. tostring(installInfo.program or installInfo.name or "unknown")
    lines[#lines + 1] = "Installed Version: " .. tostring(installInfo.version or "unknown")
    lines[#lines + 1] = "Installed Commit: " .. tostring(installInfo.source_commit or "unknown")
    lines[#lines + 1] = "Package Hash: " .. tostring(installInfo.package_hash or installInfo.content_hash or "unknown")
  else
    lines[#lines + 1] = "Installed Program: <missing .installed_program>"
  end

  lines[#lines + 1] = "Included Files: " .. tostring(#paths)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Files:"

  for _, path in ipairs(paths) do
    local attrs = getAttributes(path)
    lines[#lines + 1] = "- " .. path .. " | size=" .. tostring(attrs.size) .. " | modified=" .. tostring(attrs.modified)
  end

  return table.concat(lines, "\n")
end

buildFileSection = function(path, options)
  local maxLines = tonumber(options.maxLinesPerFile) or DEFAULT_MAX_LINES_PER_FILE
  local maxBytes = tonumber(options.maxBytesPerFile) or DEFAULT_MAX_BYTES_PER_FILE
  local attrs = getAttributes(path)
  local raw = readWholeFile(path) or ""
  local normalized = raw:gsub("\r\n", "\n")
  local trimmedBytes = 0
  local trimmedLines = 0

  if #normalized > maxBytes then
    trimmedBytes = #normalized - maxBytes
    normalized = normalized:sub(#normalized - maxBytes + 1)
    local firstNewline = normalized:find("\n", 1, true)
    if firstNewline then
      normalized = normalized:sub(firstNewline + 1)
    end
  end

  normalized, trimmedLines = trimToLastLines(normalized, maxLines)

  local lines = {}
  lines[#lines + 1] = "===== FILE: " .. path .. " ====="
  lines[#lines + 1] = "size=" .. tostring(attrs.size) .. ", modified=" .. tostring(attrs.modified)
  if trimmedBytes > 0 or trimmedLines > 0 then
    lines[#lines + 1] = "truncated=true, dropped_bytes=" .. tostring(trimmedBytes) .. ", dropped_lines=" .. tostring(trimmedLines)
  else
    lines[#lines + 1] = "truncated=false"
  end
  lines[#lines + 1] = ""
  if normalized == "" then
    lines[#lines + 1] = "<empty>"
  else
    lines[#lines + 1] = normalized
  end
  lines[#lines + 1] = ""

  return table.concat(lines, "\n")
end

buildBundleParts = function(options)
  local bundleDir = tostring(options.bundleDir or DEFAULT_BUNDLE_DIR)
  local maxPartBytes = tonumber(options.maxPartBytes) or DEFAULT_MAX_PART_BYTES
  local timestamp = tostring(os.epoch("local"))
  local paths = listBundleCandidates(options)
  local summary = buildSummaryBlock(paths)
  local sections = {}
  local parts = {}
  local current = {}
  local currentSize = 0
  local payloadBudget = math.max(32000, maxPartBytes - 4096)

  for _, path in ipairs(paths) do
    sections[#sections + 1] = buildFileSection(path, options)
  end

  if #sections == 0 then
    sections[1] = "===== FILES =====\nNo log files matched the bundle rules.\n"
  end

  for _, section in ipairs(sections) do
    if currentSize > 0 and (currentSize + #section + 2) > payloadBudget then
      parts[#parts + 1] = current
      current = {}
      currentSize = 0
    end

    current[#current + 1] = section
    currentSize = currentSize + #section + 2
  end

  if #current > 0 then
    parts[#parts + 1] = current
  end

  local ok, err = ensureDir(bundleDir)
  if not ok then
    return nil, err
  end

  local outputParts = {}
  for index, sectionList in ipairs(parts) do
    local headerLines = {
      summary,
      "",
      "Bundle Part " .. tostring(index) .. " of " .. tostring(#parts),
      "",
    }
    local content = table.concat(headerLines, "\n") .. table.concat(sectionList, "\n")
    local path = fs.combine(bundleDir, "rogerlogs_" .. timestamp .. "_part" .. string.format("%02d", index) .. ".txt")
    local writeOk, writeErr = writeWholeFile(path, content)
    if not writeOk then
      return nil, writeErr
    end

    outputParts[#outputParts + 1] = {
      path = path,
      size = #content,
    }
  end

  return outputParts, {
    bundleDir = bundleDir,
    timestamp = timestamp,
    files = paths,
  }
end

uploadBundleParts = function(parts)
  if not shell or type(shell.run) ~= "function" then
    return nil, "shell.run is unavailable"
  end

  if not shell.resolveProgram or not shell.resolveProgram("pastebin") then
    return nil, "pastebin program is unavailable"
  end

  if not http then
    return nil, "HTTP API is disabled"
  end

  local results = {}
  for index, part in ipairs(parts) do
    print("")
    print("Uploading log bundle part " .. tostring(index) .. "/" .. tostring(#parts) .. ": " .. tostring(part.path))

    local ok, shellOk, shellErr = pcall(function()
      return shell.run("pastebin", "put", part.path)
    end)

    if not ok then
      return nil, tostring(shellOk)
    end

    if shellOk == false then
      return nil, tostring(shellErr or "pastebin upload failed")
    end

    results[#results + 1] = {
      path = part.path,
      uploaded = true,
    }
  end

  return results
end

function M.write(path, message, options)
  local opts = options or {}
  return appendLine(path, message, opts.level, opts.namespace, opts.echoToTerminal)
end

function M.open(path, options)
  assert(type(path) == "string", "path must be a string")

  local opts = options or {}
  local defaultLevel = normalizeLevel(opts.defaultLevel)
  local namespace = normalizeNamespace(opts.namespace)
  local echoToTerminal = opts.echoToTerminal == true
  local logger = {}

  logger.file = path
  logger.namespace = namespace

  logger.write = function(message, level)
    return appendLine(path, message, level or defaultLevel, namespace, echoToTerminal)
  end

  logger.info = function(message)
    return appendLine(path, message, "INFO", namespace, echoToTerminal)
  end

  logger.warn = function(message)
    return appendLine(path, message, "WARN", namespace, echoToTerminal)
  end

  logger.error = function(message)
    return appendLine(path, message, "ERROR", namespace, echoToTerminal)
  end

  logger.debug = function(message)
    return appendLine(path, message, "DEBUG", namespace, echoToTerminal)
  end

  return logger
end

function M.collectBundle(options)
  return buildBundleParts(options or {})
end

function M.uploadBundle(parts)
  return uploadBundleParts(parts or {})
end

return M