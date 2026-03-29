local sound = require("lib.sound")
local catalog = require("lib.sound_catalog")
local soundMetadata = require("lib.sound_metadata")
local soundRoles = require("lib.sound_roles")
local reviewStore = require("lib.sound_review_store")

local PROGRAM_NAME = "Sound Browser"
local VERSION = "2.0.0"
local LOG_FILE = "sound_browser.log"

local ROOT = fs.getDir(shell.getRunningProgram())
local REVIEW_FILE = nil
local LEGACY_FAVORITES_FILE = nil
local state = nil

local appendLog = nil
local trimText = nil
local formatNumber = nil
local visibleRows = nil
local setStatus = nil
local currentRole = nil
local selectedSound = nil
local selectedMeta = nil
local currentRoleVerdict = nil
local normalizeTagList = nil
local promptLine = nil
local cycleRole = nil
local clampSelection = nil
local ensureScroll = nil
local matchesFilter = nil
local recalcMatches = nil
local refreshSpeaker = nil
local playSelected = nil
local promptFilter = nil
local clearFilter = nil
local adjustVolume = nil
local adjustPitch = nil
local moveSelection = nil
local pageSelection = nil
local toggleBucket = nil
local setRoleVerdict = nil
local promptManualTags = nil
local promptRoleNote = nil
local promptSoundNote = nil
local saveReviews = nil
local loadLegacyFavorites = nil
local drawScreen = nil
local runBrowser = nil

if ROOT == "" and shell.dir then
  ROOT = shell.dir()
end

REVIEW_FILE = ROOT ~= "" and fs.combine(ROOT, "sound_browser_reviews.lua") or "sound_browser_reviews.lua"
LEGACY_FAVORITES_FILE = ROOT ~= "" and fs.combine(ROOT, "sound_browser_favorites.lua") or "sound_browser_favorites.lua"

state = {
  filter = "",
  matches = {},
  selected = 0,
  scroll = 0,
  volume = 1.0,
  pitch = 1.0,
  status = "Loading sound catalog...",
  speakerSide = nil,
  role_index = 1,
  review_data = reviewStore.load(REVIEW_FILE),
}

appendLog = function(message)
  local handle = fs.open(LOG_FILE, "a")
  if not handle then
    return
  end

  handle.writeLine("[" .. tostring(os.epoch("local")) .. "] " .. tostring(message))
  handle.close()
end

trimText = function(value, maxLen)
  local text = tostring(value or "")
  if maxLen <= 0 then
    return ""
  end
  if #text <= maxLen then
    return text
  end
  if maxLen <= 2 then
    return text:sub(1, maxLen)
  end
  return text:sub(1, maxLen - 2) .. ".."
end

formatNumber = function(value)
  return string.format("%.1f", value or 0)
end

visibleRows = function()
  local _, height = term.getSize()
  return math.max(4, height - 10)
end

setStatus = function(message)
  state.status = tostring(message or "")
  appendLog(state.status)
end

currentRole = function()
  return soundRoles.LIST[state.role_index] or soundRoles.LIST[1]
end

selectedSound = function()
  if state.selected <= 0 then
    return nil
  end

  return state.matches[state.selected]
end

selectedMeta = function()
  local soundId = selectedSound()
  if not soundId then
    return nil
  end

  return soundMetadata.get(soundId)
end

currentRoleVerdict = function(soundId)
  local role = currentRole()
  if not role or not soundId then
    return ""
  end

  return reviewStore.getRoleVerdict(state.review_data, role.id, soundId)
end

normalizeTagList = function(text)
  local items = {}
  local seen = {}
  local token = nil

  for piece in string.gmatch(string.lower(tostring(text or "")), "[^,%s]+") do
    token = piece:gsub("^%s+", ""):gsub("%s+$", "")
    if token ~= "" and not seen[token] then
      seen[token] = true
      items[#items + 1] = token
    end
  end

  table.sort(items)
  return items
end

promptLine = function(label)
  local _, height = term.getSize()
  local value = nil

  term.setCursorBlink(false)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.setCursorPos(1, height)
  term.clearLine()
  write(label)
  term.setCursorBlink(true)
  value = read() or ""
  term.setCursorBlink(false)
  return value
end

cycleRole = function(delta)
  local nextIndex = state.role_index + delta

  if nextIndex < 1 then
    nextIndex = #soundRoles.LIST
  elseif nextIndex > #soundRoles.LIST then
    nextIndex = 1
  end

  state.role_index = nextIndex
  setStatus("Focused role: " .. currentRole().label)
end

clampSelection = function()
  if #state.matches == 0 then
    state.selected = 0
    state.scroll = 0
    return
  end

  if state.selected < 1 then
    state.selected = 1
  elseif state.selected > #state.matches then
    state.selected = #state.matches
  end
end

ensureScroll = function()
  local rows = visibleRows()

  clampSelection()

  if state.selected <= 0 then
    state.scroll = 0
    return
  end

  if state.selected <= state.scroll then
    state.scroll = state.selected - 1
  end

  if state.selected > state.scroll + rows then
    state.scroll = state.selected - rows
  end

  if state.scroll < 0 then
    state.scroll = 0
  end
end

matchesFilter = function(soundId)
  local filter = string.lower(state.filter or "")
  local meta = soundMetadata.get(soundId)
  local manualTags = reviewStore.getManualTags(state.review_data, soundId)
  local bucket = reviewStore.getBucket(state.review_data, soundId)
  local value = nil
  local roleValue = string.match(filter, "^role:(.+)$")
  local tagValue = string.match(filter, "^tag:(.+)$")
  local namespaceValue = string.match(filter, "^ns:(.+)$")
  local bucketValue = string.match(filter, "^bucket:(.+)$")

  if filter == "" then
    return true
  end

  if roleValue then
    role = trimText(string.lower(roleValue), 100)
    for _, roleId in ipairs(meta.role_candidates or {}) do
      if roleId == role then
        return true
      end
    end
    return false
  end

  if tagValue then
    value = string.lower(tagValue)
    for _, tag in ipairs(meta.auto_tags or {}) do
      if tag == value then
        return true
      end
    end
    for _, tag in ipairs(manualTags or {}) do
      if string.lower(tag) == value then
        return true
      end
    end
    return false
  end

  if namespaceValue then
    return meta.namespace == string.lower(namespaceValue)
  end

  if bucketValue then
    return bucket == string.lower(bucketValue)
  end

  if string.find(string.lower(soundId), filter, 1, true) then
    return true
  end

  for _, tag in ipairs(meta.auto_tags or {}) do
    if string.find(tag, filter, 1, true) then
      return true
    end
  end

  for _, tag in ipairs(manualTags or {}) do
    if string.find(string.lower(tag), filter, 1, true) then
      return true
    end
  end

  return false
end

recalcMatches = function()
  local matches = {}

  for _, soundId in ipairs(catalog.SOUNDS or {}) do
    if matchesFilter(soundId) then
      matches[#matches + 1] = soundId
    end
  end

  state.matches = matches
  clampSelection()

  if state.selected == 0 and #state.matches > 0 then
    state.selected = 1
  end

  ensureScroll()
end

refreshSpeaker = function(side)
  state.speakerSide = side

  if sound.init(side) then
    return true
  end

  return false
end

playSelected = function()
  local soundId = selectedSound()
  local attempts = 0
  local ok = false
  local err = nil

  if not soundId then
    setStatus("No sound selected.")
    return
  end

  if not sound.isAvailable() then
    setStatus("No speaker found. Pass a side or attach a speaker.")
    return
  end

  while attempts < 5 do
    attempts = attempts + 1
    ok, err = sound.play(soundId, state.volume, state.pitch)
    if ok then
      setStatus("Played " .. soundId .. " at vol " .. formatNumber(state.volume) .. ", pitch " .. formatNumber(state.pitch))
      return
    end
    os.sleep(0.05)
  end

  setStatus("Could not play " .. soundId .. ": " .. tostring(err or "unknown error"))
end

promptFilter = function()
  local input = promptLine("Filter: ")

  state.filter = input
  recalcMatches()

  if state.filter == "" then
    setStatus("Filter cleared.")
  else
    setStatus("Filter set to \"" .. trimText(state.filter, 48) .. "\"")
  end
end

clearFilter = function()
  state.filter = ""
  recalcMatches()
  setStatus("Filter cleared.")
end

adjustVolume = function(delta)
  state.volume = math.max(0, math.min(3, math.floor((state.volume + delta) * 10 + 0.5) / 10))
  setStatus("Volume set to " .. formatNumber(state.volume))
end

adjustPitch = function(delta)
  state.pitch = math.max(0.5, math.min(2, math.floor((state.pitch + delta) * 10 + 0.5) / 10))
  setStatus("Pitch set to " .. formatNumber(state.pitch))
end

moveSelection = function(delta)
  if #state.matches == 0 then
    return
  end

  state.selected = state.selected + delta
  clampSelection()
  ensureScroll()
end

pageSelection = function(delta)
  moveSelection(delta * visibleRows())
end

toggleBucket = function(bucket)
  local soundId = selectedSound()
  local nextBucket = nil

  if not soundId then
    setStatus("No sound selected.")
    return
  end

  nextBucket = reviewStore.toggleBucket(state.review_data, soundId, bucket)
  recalcMatches()
  if nextBucket then
    setStatus("Marked " .. soundId .. " as " .. nextBucket .. ".")
  else
    setStatus("Cleared bucket for " .. soundId .. ".")
  end
end

setRoleVerdict = function(verdict)
  local soundId = selectedSound()
  local role = currentRole()

  if not soundId or not role then
    setStatus("No sound selected.")
    return
  end

  reviewStore.setRoleVerdict(state.review_data, role.id, soundId, verdict or "")
  if verdict and verdict ~= "" then
    setStatus("Set " .. role.label .. " verdict for " .. soundId .. " to " .. verdict .. ".")
  else
    setStatus("Cleared " .. role.label .. " verdict for " .. soundId .. ".")
  end
end

promptManualTags = function()
  local soundId = selectedSound()
  local input = nil
  local tags = nil

  if not soundId then
    setStatus("No sound selected.")
    return
  end

  input = promptLine("Manual tags (comma separated): ")
  tags = normalizeTagList(input)
  reviewStore.setManualTags(state.review_data, soundId, tags)
  recalcMatches()
  setStatus("Saved " .. tostring(#tags) .. " manual tags for " .. soundId .. ".")
end

promptRoleNote = function()
  local soundId = selectedSound()
  local role = currentRole()
  local note = nil

  if not soundId or not role then
    setStatus("No sound selected.")
    return
  end

  note = promptLine("Role note for " .. role.id .. ": ")
  reviewStore.setRoleNote(state.review_data, role.id, soundId, note)
  setStatus("Saved role note for " .. soundId .. ".")
end

promptSoundNote = function()
  local soundId = selectedSound()
  local note = nil

  if not soundId then
    setStatus("No sound selected.")
    return
  end

  note = promptLine("Sound note: ")
  reviewStore.setSoundNote(state.review_data, soundId, note)
  setStatus("Saved sound note for " .. soundId .. ".")
end

saveReviews = function()
  local ok, err = reviewStore.save(REVIEW_FILE, state.review_data)

  if not ok then
    setStatus("Could not save reviews: " .. tostring(err))
    return
  end

  setStatus("Saved review data to " .. REVIEW_FILE)
end

loadLegacyFavorites = function()
  local ok = nil
  local loaded = nil

  if fs.exists(REVIEW_FILE) or not fs.exists(LEGACY_FAVORITES_FILE) then
    return
  end

  ok, loaded = pcall(function()
    return dofile(LEGACY_FAVORITES_FILE)
  end)

  if not ok or type(loaded) ~= "table" then
    return
  end

  for _, soundId in ipairs(loaded.favorites or {}) do
    if type(soundId) == "string" and soundId ~= "" then
      state.review_data.favorites[soundId] = true
    end
  end
end

drawScreen = function()
  local width, height = term.getSize()
  local rows = visibleRows()
  local listStartY = 8
  local footerY = height - 1
  local soundId = selectedSound()
  local meta = selectedMeta()
  local role = currentRole()
  local manualTags = soundId and reviewStore.getManualTags(state.review_data, soundId) or {}
  local bucket = soundId and reviewStore.getBucket(state.review_data, soundId) or nil
  local roleVerdict = soundId and currentRoleVerdict(soundId) or ""
  local roleScore = (soundId and role) and soundMetadata.scoreForRole(soundId, role.id) or 0
  local soundNote = soundId and reviewStore.getSoundNote(state.review_data, soundId) or ""
  local roleNote = (soundId and role) and reviewStore.getRoleNote(state.review_data, role.id, soundId) or ""
  local summaryLine = nil
  local tagsLine = nil
  local manualLine = nil
  local row = nil
  local index = nil
  local rowSoundId = nil
  local rowBucket = nil

  term.setCursorBlink(false)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()

  term.setCursorPos(1, 1)
  term.write(trimText(PROGRAM_NAME .. " v" .. VERSION, width))

  term.setCursorPos(1, 2)
  term.setTextColor(colors.lightGray)
  term.write(trimText(
    "Speaker: " .. (sound.isAvailable() and "ready" or "missing") ..
    "  Showing: " .. tostring(#state.matches) .. "/" .. tostring(catalog.SOUND_COUNT or #(catalog.SOUNDS or {})) ..
    "  Role: " .. role.label,
    width
  ))

  term.setCursorPos(1, 3)
  term.setTextColor(colors.yellow)
  term.write(trimText("Filter: " .. (state.filter ~= "" and state.filter or "(none)"), width))

  summaryLine = "Bucket: " .. tostring(bucket or "-") ..
    "  Verdict: " .. (roleVerdict ~= "" and roleVerdict or "-") ..
    "  Score: " .. tostring(roleScore) ..
    "  Vol: " .. formatNumber(state.volume) ..
    "  Pitch: " .. formatNumber(state.pitch)

  term.setCursorPos(1, 4)
  term.setTextColor(colors.cyan)
  term.write(trimText(summaryLine, width))

  if meta then
    tagsLine = "Auto: " .. table.concat(meta.auto_tags or {}, ", ")
    term.setCursorPos(1, 5)
    term.setTextColor(colors.lightGray)
    term.write(trimText(tagsLine, width))

    term.setCursorPos(1, 6)
    term.setTextColor(colors.orange)
    term.write(trimText(
      "Roles: " .. table.concat(meta.role_candidates or {}, ", ") ..
      "  Intensity: " .. tostring(meta.intensity) ..
      "  Repeat: " .. tostring(meta.repetition_risk) ..
      "  AI: " .. formatNumber(meta.ai_confidence),
      width
    ))

    manualLine = "Manual: " .. (#manualTags > 0 and table.concat(manualTags, ", ") or "-")
    if soundNote ~= "" then
      manualLine = manualLine .. "  Note"
    end
    if roleNote ~= "" then
      manualLine = manualLine .. "  RoleNote"
    end

    term.setCursorPos(1, 7)
    term.setTextColor(colors.lime)
    term.write(trimText(manualLine, width))
  else
    term.setCursorPos(1, 5)
    term.setTextColor(colors.red)
    term.write(trimText("No sound selected.", width))
  end

  term.setCursorPos(1, listStartY)
  term.setTextColor(colors.gray)
  term.write(string.rep("-", width))

  for row = 1, rows do
    index = state.scroll + row
    rowSoundId = state.matches[index]

    if not rowSoundId then
      break
    end

    rowBucket = reviewStore.getBucket(state.review_data, rowSoundId)
    term.setCursorPos(1, listStartY + row)

    if index == state.selected then
      term.setBackgroundColor(colors.lightBlue)
      term.setTextColor(colors.black)
    else
      term.setBackgroundColor(colors.black)
      if rowBucket == "favorite" then
        term.setTextColor(colors.lime)
      elseif rowBucket == "reject" then
        term.setTextColor(colors.red)
      elseif rowBucket == "maybe" then
        term.setTextColor(colors.yellow)
      else
        term.setTextColor(colors.white)
      end
    end

    term.clearLine()
    term.write(trimText(
      (index == state.selected and ">" or " ") ..
      (rowBucket == "favorite" and "F" or (rowBucket == "reject" and "X" or (rowBucket == "maybe" and "M" or " "))) ..
      " " .. rowSoundId,
      width
    ))
  end

  term.setBackgroundColor(colors.black)
  term.setCursorPos(1, footerY)
  term.setTextColor(colors.lightGray)
  term.clearLine()
  term.write(trimText("Enter play  / filter  F/X/M buckets  </> role  B/G/V/C verdict  T tags  N role note  O sound note  S save  Q quit", width))

  term.setCursorPos(1, height)
  term.setTextColor(soundId and colors.white or colors.orange)
  term.clearLine()
  term.write(trimText(state.status or "", width))
end

runBrowser = function(...)
  local args = { ... }
  local event = nil
  local p1 = nil
  local running = true

  loadLegacyFavorites()
  refreshSpeaker(args[1])
  recalcMatches()
  setStatus("Loaded " .. tostring(catalog.SOUND_COUNT or #(catalog.SOUNDS or {})) .. " sounds with auto metadata. Save file: " .. REVIEW_FILE)

  while running do
    drawScreen()
    event, p1 = os.pullEvent()

    if event == "char" then
      if p1 == "/" then
        promptFilter()
      elseif p1 == "f" or p1 == "F" then
        toggleBucket("favorite")
      elseif p1 == "x" or p1 == "X" then
        toggleBucket("reject")
      elseif p1 == "m" or p1 == "M" then
        toggleBucket("maybe")
      elseif p1 == "s" or p1 == "S" then
        saveReviews()
      elseif p1 == "r" or p1 == "R" then
        clearFilter()
      elseif p1 == "q" or p1 == "Q" then
        running = false
      elseif p1 == "-" then
        adjustVolume(-0.1)
      elseif p1 == "=" or p1 == "+" then
        adjustVolume(0.1)
      elseif p1 == "[" or p1 == "{" then
        adjustPitch(-0.1)
      elseif p1 == "]" or p1 == "}" then
        adjustPitch(0.1)
      elseif p1 == "," or p1 == "<" then
        cycleRole(-1)
      elseif p1 == "." or p1 == ">" then
        cycleRole(1)
      elseif p1 == "b" or p1 == "B" then
        setRoleVerdict("best")
      elseif p1 == "g" or p1 == "G" then
        setRoleVerdict("good")
      elseif p1 == "v" or p1 == "V" then
        setRoleVerdict("avoid")
      elseif p1 == "c" or p1 == "C" then
        setRoleVerdict("")
      elseif p1 == "t" or p1 == "T" then
        promptManualTags()
      elseif p1 == "n" or p1 == "N" then
        promptRoleNote()
      elseif p1 == "o" or p1 == "O" then
        promptSoundNote()
      end
    elseif event == "key" then
      if p1 == keys.up then
        moveSelection(-1)
      elseif p1 == keys.down then
        moveSelection(1)
      elseif p1 == keys.pageUp then
        pageSelection(-1)
      elseif p1 == keys.pageDown then
        pageSelection(1)
      elseif p1 == keys.home then
        state.selected = 1
        ensureScroll()
      elseif p1 == keys["end"] then
        state.selected = #state.matches
        ensureScroll()
      elseif p1 == keys.enter or p1 == keys.numPadEnter or p1 == keys.space then
        playSelected()
      end
    elseif event == "peripheral" or event == "peripheral_detach" then
      if refreshSpeaker(state.speakerSide) then
        setStatus("Speaker detected.")
      else
        setStatus("Speaker not available.")
      end
    elseif event == "term_resize" then
      ensureScroll()
    elseif event == "terminate" then
      running = false
    end
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("Exited " .. PROGRAM_NAME .. ".")
  print("Review file: " .. REVIEW_FILE)
end

local ok, err = pcall(function(...)
  runBrowser(...)
end, ...)

if not ok then
  appendLog("Fatal error: " .. tostring(err))
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1, 1)
  print(PROGRAM_NAME .. " crashed.")
  print("")
  term.setTextColor(colors.white)
  print(tostring(err))
  print("")
  print("See " .. LOG_FILE .. " for details.")
end
