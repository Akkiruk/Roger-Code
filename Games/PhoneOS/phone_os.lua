local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" and shell.dir then
  ROOT = shell.dir()
end

local PARENT = ROOT ~= "" and fs.combine(ROOT, "..") or ""

local function addPackagePath(pattern)
  if pattern and pattern ~= "" and not string.find(package.path, pattern, 1, true) then
    package.path = package.path .. ";" .. pattern
  end
end

addPackagePath(fs.combine(ROOT, "?.lua"))
addPackagePath(fs.combine(ROOT, "?/init.lua"))
if PARENT ~= "" then
  addPackagePath(fs.combine(PARENT, "?.lua"))
  addPackagePath(fs.combine(PARENT, "?/init.lua"))
end

local ui       = require("phoneos.ui")
local storage  = require("phoneos.storage")
local currency = require("lib.currency")
local sound    = require("lib.sound")
local alert    = require("lib.alert")
local updater  = require("lib.updater")

local theme = ui.theme or {}

local blackjackApp = require("phoneos.blackjack")
local slotsApp     = require("phoneos.slots")

local function loadConfig(label, candidates, fallbackModule)
  local checked = {}
  local seen = {}

  local function tryPath(path)
    if not path or path == "" or seen[path] then
      return nil
    end

    seen[path] = true
    checked[#checked + 1] = path

    if not fs.exists(path) then
      return nil
    end

    local ok, value = pcall(dofile, path)
    if not ok then
      error("Failed to load " .. label .. " config from " .. path .. ": " .. tostring(value))
    end
    if type(value) == "table" then
      return value
    end
    error("Invalid " .. label .. " config at " .. path)
  end

  for _, path in ipairs(candidates) do
    local value = tryPath(path)
    if type(value) == "table" then
      return value
    end

    if path and path ~= "" and shell and type(shell.resolve) == "function" then
      local ok, resolved = pcall(shell.resolve, path)
      if ok then
        value = tryPath(resolved)
        if type(value) == "table" then
          return value
        end
      end
    end
  end

  if fallbackModule and fallbackModule ~= "" then
    local ok, value = pcall(require, fallbackModule)
    if ok and type(value) == "table" then
      return value
    end
    error("Missing " .. label .. " config. Fallback " .. fallbackModule .. " failed: " .. tostring(value))
  end

  error("Missing " .. label .. " config. Checked: " .. table.concat(checked, ", "))
end

local blackjackConfig = loadConfig("blackjack", {
  PARENT ~= "" and fs.combine(PARENT, "Blackjack/blackjack_config.lua") or nil,
  ROOT ~= "" and fs.combine(ROOT, "Blackjack/blackjack_config.lua") or nil,
  "Blackjack/blackjack_config.lua",
  ROOT ~= "" and fs.combine(ROOT, "blackjack_config.lua") or "blackjack_config.lua",
}, "phoneos.blackjack_defaults")

local slotsConfig = loadConfig("slots", {
  PARENT ~= "" and fs.combine(PARENT, "Slots/slots_config.lua") or nil,
  ROOT ~= "" and fs.combine(ROOT, "Slots/slots_config.lua") or nil,
  "Slots/slots_config.lua",
  ROOT ~= "" and fs.combine(ROOT, "slots_config.lua") or "slots_config.lua",
}, "phoneos.slots_defaults")

local DATA_DIR       = fs.combine(ROOT, "phone_data")
local SETTINGS_FILE  = fs.combine(DATA_DIR, "settings.dat")
local NOTES_FILE     = fs.combine(DATA_DIR, "notes.dat")
local MESSAGES_FILE  = fs.combine(DATA_DIR, "messages.dat")
local PAIRING_FILE   = fs.combine(DATA_DIR, "pairing.dat")

if not fs.exists(DATA_DIR) then
  fs.makeDir(DATA_DIR)
end

sound.init()

alert.configure({
  adminName = "Akkiruk",
  gameName  = "Pocket Casino",
  logFile   = fs.combine(DATA_DIR, "phone_os_error.log"),
})
alert.addPlannedExits({ "home", "back", "cancel" })

local DEFAULT_SETTINGS = {
  sound = true,
  animations = true,
  autoAuth = false,
  confirmWagers = true,
}

local DEFAULT_PAIRING = {
  lastPlayerName = nil,
  lastHostName = nil,
  lastComputerId = nil,
  lastLinkedAt = nil,
  everAuthenticated = false,
}

local function nowStamp()
  return os.date("%Y-%m-%d %H:%M")
end

local function defaultMessages()
  return {
    {
      title = "Welcome",
      body = "Pocket Casino OS is ready. Use Wallet or Pairing to link the phone, then open Blackjack or Slots.",
      level = "info",
      time = nowStamp(),
    },
    {
      title = "Provisioning",
      body = "House-owned phones run live wagers. Owner testing uses CCVault self-pay.",
      level = "warn",
      time = nowStamp(),
    },
  }
end

local state = {
  settings = storage.load(SETTINGS_FILE, DEFAULT_SETTINGS),
  notes = storage.load(NOTES_FILE, {}),
  messages = storage.load(MESSAGES_FILE, nil),
  pairing = storage.load(PAIRING_FILE, DEFAULT_PAIRING),
}

if type(state.settings) ~= "table" then
  state.settings = {}
end
if type(state.notes) ~= "table" then
  state.notes = {}
end
if type(state.messages) ~= "table" then
  state.messages = nil
end
if type(state.pairing) ~= "table" then
  state.pairing = {}
end

for key, value in pairs(DEFAULT_SETTINGS) do
  if state.settings[key] == nil then
    state.settings[key] = value
  end
end
for key, value in pairs(DEFAULT_PAIRING) do
  if state.pairing[key] == nil then
    state.pairing[key] = value
  end
end

if not state.messages or #state.messages == 0 then
  state.messages = defaultMessages()
  storage.save(MESSAGES_FILE, state.messages)
end

local function saveSettings()
  storage.save(SETTINGS_FILE, state.settings)
end

local function saveNotes()
  storage.save(NOTES_FILE, state.notes)
end

local function saveMessages()
  storage.save(MESSAGES_FILE, state.messages)
end

local function savePairing()
  storage.save(PAIRING_FILE, state.pairing)
end

local function shorten(text, maxLen)
  text = tostring(text or "")
  maxLen = math.max(1, maxLen or #text)
  if #text <= maxLen then
    return text
  end
  if maxLen <= 3 then
    return text:sub(1, maxLen)
  end
  return text:sub(1, maxLen - 3) .. "..."
end

local function sanitizeTerminalText(text)
  text = tostring(text or "")
  text = text:gsub("[\r\n]+", " ")
  text = text:gsub("[^\32-\126]", "-")
  text = text:gsub("%-+", "-")
  text = text:gsub("%s+", " ")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function addMessage(title, body, level)
  table.insert(state.messages, 1, {
    title = title,
    body = body,
    level = level or "info",
    time = nowStamp(),
  })

  while #state.messages > 40 do
    table.remove(state.messages)
  end

  saveMessages()
end

local function playSound(soundId, volume)
  if state.settings.sound then
    sound.play(soundId, volume)
  end
end

local function rememberPairing(session)
  if type(session) ~= "table" then
    return
  end

  local changed = false

  if session.playerName and state.pairing.lastPlayerName ~= session.playerName then
    state.pairing.lastPlayerName = session.playerName
    changed = true
  end

  if session.hostName and state.pairing.lastHostName ~= session.hostName then
    state.pairing.lastHostName = session.hostName
    changed = true
  end

  local computerId = session.computerId or os.getComputerID()
  if state.pairing.lastComputerId ~= computerId then
    state.pairing.lastComputerId = computerId
    changed = true
  end

  if session.authenticated then
    if not state.pairing.everAuthenticated then
      state.pairing.everAuthenticated = true
      changed = true
    end
    if changed then
      state.pairing.lastLinkedAt = nowStamp()
      changed = true
    end
  end

  if changed then
    savePairing()
  end
end

local function ccvaultCall(method, ...)
  if not ccvault or type(ccvault[method]) ~= "function" then
    return nil, "ccvault unavailable"
  end

  local results = { pcall(ccvault[method], ...) }
  if not results[1] then
    return nil, tostring(results[2])
  end

  return results[2], results[3], results[4], results[5]
end

local function refreshSession()
  local session = {
    available = ccvault and ccvault.isAvailable and ccvault.isAvailable() or false,
    authenticated = ccvault and ccvault.isAuthenticated and ccvault.isAuthenticated() or false,
    computerId = ccvault and ccvault.getComputerId and ccvault.getComputerId() or os.getComputerID(),
    playerName = ccvault and ccvault.getPlayerName and ccvault.getPlayerName() or nil,
    hostName = nil,
    playerBalance = nil,
    hostBalance = nil,
    selfPlay = false,
    transfersRemaining = nil,
  }

  local info = ccvault and ccvault.getSessionInfo and ccvault.getSessionInfo() or nil
  if type(info) == "table" then
    session.info = info
    session.playerName = info.playerName or session.playerName
    session.hostName = info.hostName or session.hostName
    session.selfPlay = info.isSelfPlay or false
    session.transfersRemaining = info.transfersRemaining
    session.authenticated = info.authenticated or session.authenticated
  elseif ccvault and ccvault.getHostName then
    session.hostName = ccvault.getHostName()
  end

  if session.authenticated and session.available then
    local playerBalance = ccvaultCall("getBalance", "player")
    local hostBalance = ccvaultCall("getBalance", "host")
    if type(playerBalance) == "number" then
      session.playerBalance = playerBalance
    end
    if type(hostBalance) == "number" then
      session.hostBalance = hostBalance
    end
  end

  session.modeTag = session.selfPlay and "self-pay" or "live"
  session.modeLabel = session.selfPlay and "Self-Pay" or "Live"

  if not session.available then
    session.status = "OFFLINE"
  elseif not session.playerName then
    session.status = "NO USER"
  elseif not session.authenticated then
    session.status = "LOCKED"
  elseif session.selfPlay then
    session.status = "SELF PAY"
  else
    session.status = "READY"
  end

  if session.playerName or session.hostName or session.authenticated then
    rememberPairing(session)
  end

  return session
end

local function isLiveSession(session)
  session = session or refreshSession()
  return session.available and session.authenticated
end

local function ensureAuthenticated(reason)
  local session = refreshSession()

  if not session.available then
    ui.showMessage("Economy Offline", {
      "CCVault is not available on this computer right now.",
    })
    return false
  end

  if session.authenticated then
    return true
  end

  if not session.playerName then
    ui.showMessage("No Active User", {
      "Wait for the pocket session to register, then try again.",
    })
    return false
  end

  local ok, err = ccvaultCall("requestAuth")
  local errText = sanitizeTerminalText(err)
  local pending = errText ~= "" and errText:lower():find("already pending", 1, true) ~= nil

  if not ok and not pending then
    ui.showMessage("Auth Error", {
      errText ~= "" and errText or "Unable to send the approval prompt.",
    })
    return false
  end

  if pending then
    addMessage("Approval Pending", "Wallet approval is already pending for computer #" .. tostring(session.computerId) .. ".", "info")
  else
    addMessage("Approval Sent", "Wallet approval requested for computer #" .. tostring(session.computerId) .. ".", "info")
  end

  local started = os.epoch("local")
  local spinner = { "|", "/", "-", "\\" }
  local frame = 1

  while true do
    session = refreshSession()
    if session.authenticated then
      addMessage("Wallet Linked", "Session approved for " .. tostring(session.playerName or "player") .. ".", "info")
      rememberPairing(session)
      playSound(sound.SOUNDS.SUCCESS, 0.6)
      return true
    end

    ui.clear(colors.black)
    ui.header("Waiting For Approval", shorten(reason or "Approve this phone in chat.", 26), session.status)
    ui.writeAt(2, 5, "Player: " .. tostring(session.playerName or "Unknown"), colors.white)
    ui.writeAt(2, 7, "Computer #" .. tostring(session.computerId), colors.white)
    ui.writeAt(2, 9, "Check chat and click", theme.subtitle or colors.lightGray)
    ui.writeAt(2, 10, "[APPROVE].", theme.accent or colors.magenta)
    ui.writeAt(2, 12, "Status: " .. spinner[frame], theme.rule or colors.lightBlue)
    ui.footer("Backspace cancel")
    frame = frame % #spinner + 1

    if os.epoch("local") - started > 60000 then
      ui.showMessage("Auth Timeout", {
        "Approval timed out. Try again from Wallet.",
      })
      return false
    end

    local timer = os.startTimer(0.25)
    local event, p1 = os.pullEvent()
    if event == "key" and p1 == keys.backspace then
      return false
    elseif event == "timer" and p1 == timer then
      -- redraw
    end
  end
end

local function promptBet(opts)
  opts = opts or {}

  local session = refreshSession()
  local maxBet = math.max(0, math.floor(opts.maxBet or 0))
  local liveMode = opts.liveMode ~= false
  local bet = math.max(0, math.floor(opts.initial or 0))
  local increments = opts.increments or { 1, 5, 25, 100 }

  if maxBet <= 0 then
    ui.showMessage(opts.title or "No Bets", {
      "This device cannot cover a wager right now.",
    })
    return nil
  end

  if not liveMode then
    ui.showMessage(opts.title or "Wagers Locked", {
      "This wager requires an approved live or self-pay wallet session.",
    }, { status = session.status })
    return nil
  end

  while true do
    session = refreshSession()
    local balance = session.playerBalance or 0
    local cap = maxBet
    cap = math.min(cap, balance)

    if cap <= 0 then
      ui.showMessage(opts.title or "No Bets", {
        "There is not enough balance available for this wager right now.",
      }, { status = session.status })
      return nil
    end

    ui.clear(colors.black)
    ui.header(opts.title or "Place Bet", opts.subtitle or "", session.status)
    ui.writeAt(2, 5, "Balance: " .. (session.playerBalance and currency.formatTokens(session.playerBalance) or "Locked"), colors.white)
    ui.writeAt(2, 6, "Max Bet: " .. currency.formatTokens(cap), colors.white)
    ui.writeAt(2, 8, "Current: " .. currency.formatTokens(bet), theme.accent or colors.magenta)
    ui.writeAt(2, 10, "1 +" .. increments[1], colors.white)
    ui.writeAt(14, 10, "2 +" .. increments[2], colors.white)
    ui.writeAt(2, 11, "3 +" .. increments[3], colors.white)
    ui.writeAt(14, 11, "4 +" .. increments[4], colors.white)

    ui.writeAt(2, 13, "5 All In", colors.white)
    ui.writeAt(14, 13, "6 Clear", colors.white)
    ui.writeAt(2, 15, "Enter Start", colors.lime)
    ui.writeAt(14, 15, "-1 / +1", colors.lightGray)
    ui.footer("Backspace cancel")

    local _, key = os.pullEvent("key")

    if key == keys.backspace or key == keys.h then
      return nil
    elseif key == keys.one and cap >= bet + increments[1] then
      bet = bet + increments[1]
      playSound(sound.SOUNDS.CLEAR, 0.3)
    elseif key == keys.two and cap >= bet + increments[2] then
      bet = bet + increments[2]
      playSound(sound.SOUNDS.CLEAR, 0.3)
    elseif key == keys.three and cap >= bet + increments[3] then
      bet = bet + increments[3]
      playSound(sound.SOUNDS.CLEAR, 0.3)
    elseif key == keys.four and cap >= bet + increments[4] then
      bet = bet + increments[4]
      playSound(sound.SOUNDS.CLEAR, 0.3)
    elseif key == keys.five then
      bet = cap
      playSound(sound.SOUNDS.ALL_IN, 0.4)
    elseif key == keys.six or key == keys.c then
      bet = 0
      playSound(sound.SOUNDS.CLEAR, 0.3)
    elseif key == keys.minus then
      bet = math.max(0, bet - 1)
    elseif key == keys.equals or key == keys.plus then
      bet = math.min(cap, bet + 1)
    elseif key == keys.enter and bet > 0 then
      if not state.settings.confirmWagers or ui.confirm("Confirm Wager", {
        "Start with a bet of " .. currency.formatTokens(bet) .. "?",
      }, { status = session.status }) then
        return bet
      end
    end
  end
end

local function bootSplash()
  if not state.settings.animations then
    return
  end

  ui.clear(colors.black)
  ui.header("Pocket Casino", "Vault Link OS", refreshSession().status)
  ui.center(8, "ADVANCED POCKET", theme.subtitle or colors.lightGray)
  ui.center(10, "BLACKJACK", theme.rule or colors.lightBlue)
  ui.center(11, "SLOTS", theme.accent or colors.magenta)
  ui.footer("Booting...")
  playSound(sound.SOUNDS.BOOT, 0.4)
  os.sleep(0.6)
end

local function showWallet()
  while true do
    local session = refreshSession()

    ui.clear(colors.black)
    ui.header("Wallet", "Computer #" .. tostring(session.computerId), session.status)
    ui.writeAt(2, 5, "Player: " .. tostring(session.playerName or "Unknown"), colors.white)
    ui.writeAt(2, 6, "Host:   " .. tostring(session.hostName or "Unregistered"), colors.white)
    ui.writeAt(2, 7, "Mode:   " .. session.modeLabel, session.selfPlay and (theme.accent or colors.magenta) or colors.lime)
    ui.writeAt(2, 8, "Auth:   " .. (session.authenticated and "Approved" or "Required"), session.authenticated and colors.lime or colors.orange)

    local playerBal = session.playerBalance and currency.formatTokens(session.playerBalance) or "Locked"
    local hostBal = session.hostBalance and currency.formatTokens(session.hostBalance) or "Locked"
    ui.writeAt(2, 10, "You:    " .. playerBal, colors.white)
    ui.writeAt(2, 11, "House:  " .. hostBal, colors.white)
    ui.writeAt(2, 12, "Moves:  " .. tostring(session.transfersRemaining or "?"), colors.white)

    ui.writeAt(2, 15, "A Authenticate", colors.white)
    ui.writeAt(2, 16, "R Refresh", colors.white)
    ui.writeAt(14, 15, "T History", colors.white)
    ui.footer("Back/H home")

    local _, key = os.pullEvent("key")
    if key == keys.backspace or key == keys.h then
      return "home"
    elseif key == keys.a then
      ensureAuthenticated("Wallet access requires approval.")
    elseif key == keys.t then
      return "history"
    elseif key == keys.r then
      -- redraw
    end
  end
end

local function showPairing()
  while true do
    local session = refreshSession()

    ui.clear(colors.black)
    ui.header("Pairing", "Phone Wallet Link", session.status)
    ui.writeAt(2, 5, "Player: " .. tostring(session.playerName or "Unknown"), colors.white)
    ui.writeAt(2, 6, "Host:   " .. tostring(session.hostName or "Pending"), colors.white)
    ui.writeAt(2, 7, "Device: #" .. tostring(session.computerId), colors.white)
    ui.writeAt(2, 9, "House phones run", theme.subtitle or colors.lightGray)
    ui.writeAt(2, 10, "live. Owners self-pay.", theme.subtitle or colors.lightGray)
    ui.writeAt(2, 12, "Current mode: " .. string.upper(session.modeLabel), session.selfPlay and (theme.accent or colors.magenta) or colors.lime)
    ui.writeAt(2, 13, "Last host: " .. tostring(state.pairing.lastHostName or "Unknown"), colors.white)
    ui.writeAt(2, 14, "Last link: " .. tostring(state.pairing.lastLinkedAt or "Never"), colors.white)

    ui.writeAt(2, 15, "A Approve Wallet", colors.white)
    ui.writeAt(2, 16, "R Refresh", colors.white)
    ui.writeAt(14, 15, "W Wallet", colors.white)
    ui.footer("Back/H home")

    local _, key = os.pullEvent("key")
    if key == keys.backspace or key == keys.h then
      return "home"
    elseif key == keys.a then
      ensureAuthenticated("Pair this phone with the wallet session.")
    elseif key == keys.w then
      return "wallet"
    elseif key == keys.r then
      -- redraw
    end
  end
end

local function toArray(tbl, opts)
  opts = opts or {}

  if type(tbl) ~= "table" then
    return {}
  end

  local out = {}
  for k, v in pairs(tbl) do
    if type(k) == "number" then
      out[#out + 1] = { index = k, value = v }
    end
  end
  table.sort(out, function(a, b)
    local aTime = a.value and a.value.timestamp
    local bTime = b.value and b.value.timestamp

    if aTime and bTime and aTime ~= bTime then
      if opts.newestFirst then
        return tostring(aTime) > tostring(bTime)
      end
      return tostring(aTime) < tostring(bTime)
    end

    if opts.newestFirst then
      return a.index > b.index
    end
    return a.index < b.index
  end)

  local final = {}
  for _, item in ipairs(out) do
    final[#final + 1] = item.value
  end
  return final
end

local function showHistory()
  if not ensureAuthenticated("History requires wallet approval.") then
    return "home"
  end

  local selected = 1
  while true do
    local entries = toArray(currency.getTransactionHistory(12) or {}, { newestFirst = true })
    local session = refreshSession()
    local items = {}

    for i, tx in ipairs(entries) do
      local sign = ""
      if tx.playerUuid and tx.to == tx.playerUuid then
        sign = "+"
      elseif tx.playerUuid and tx.from == tx.playerUuid then
        sign = "-"
      end
      items[i] = {
        label = shorten(sign .. tostring(tx.amount or "?") .. " " .. tostring(tx.reason or "transaction"), 22),
      }
    end

    if #items == 0 then
      ui.showMessage("History", {
        "No transaction history is available yet.",
      }, { status = session.status })
      return "home"
    end

    local index, action = ui.chooseMenu("History", items, {
      selected = selected,
      subtitle = "Most recent wallet activity",
      status = session.status,
      footer = "Enter view  R refresh  Back home",
    })

    selected = index
    if action == "back" or action == "home" then
      return "home"
    elseif action == "refresh" then
      -- redraw
    elseif action == "select" and entries[index] then
      local tx = entries[index]
      ui.showMessage("Transaction", {
        "Amount: " .. tostring(tx.amount or "?"),
        "Reason: " .. tostring(tx.reason or "Unknown"),
        "Time: " .. tostring(tx.timestamp or "Unknown"),
        "TX: " .. tostring(tx.txId or "Unknown"),
      }, { status = session.status })
    end
  end
end

local function showMessages()
  local selected = 1
  while true do
    local items = {}
    for i, message in ipairs(state.messages) do
      items[i] = {
        label = shorten(message.time .. " " .. message.title, 22),
      }
    end

    local index, action = ui.chooseMenu("Messages", items, {
      selected = selected,
      subtitle = "System and game notices",
      status = refreshSession().status,
      footer = "Enter view  D clear all  Back home",
      extraKeys = {
        [keys.d] = "clear",
      },
    })

    selected = index
    if action == "back" or action == "home" then
      return "home"
    elseif action == "clear" then
      if ui.confirm("Clear Messages", {
        "Remove all saved system messages?",
      }, { status = refreshSession().status }) then
        state.messages = defaultMessages()
        saveMessages()
      end
    elseif action == "select" and state.messages[index] then
      local message = state.messages[index]
      ui.showMessage(message.title, {
        message.time,
        "",
        message.body,
      }, { status = refreshSession().status })
    end
  end
end

local function showContacts()
  while true do
    local session = refreshSession()
    ui.clear(colors.black)
    ui.header("Contacts", "Casino Directory", session.status)
    ui.writeAt(2, 5, "Host:     " .. tostring(session.hostName or "Unknown"), colors.white)
    ui.writeAt(2, 7, "Cashier:  Vault Desk", colors.white)
    ui.writeAt(2, 8, "Security: House Security", colors.white)
    ui.writeAt(2, 9, "Support:  Akkiruk", colors.white)
    ui.writeAt(2, 12, "Use Messages to keep", colors.lightGray)
    ui.writeAt(2, 13, "track of payouts and", colors.lightGray)
    ui.writeAt(2, 14, "wallet prompts.", colors.lightGray)
    ui.footer("Back/H home")

    local _, key = os.pullEvent("key")
    if key == keys.backspace or key == keys.h then
      return "home"
    end
  end
end

local function viewNote(note)
  while true do
    ui.showMessage(note.title, {
      note.body,
      "",
      "Updated: " .. tostring(note.updatedAt or "Unknown"),
    }, {
      status = refreshSession().status,
      footer = "Enter/Backspace continue",
    })
    return
  end
end

local function editNote(existing)
  local title = ui.promptLine("Note Title", "Enter a short title.", existing and existing.title or "")
  if not title or title == "" then
    return nil
  end

  local body = ui.promptLine("Note Body", "Enter a short note.", existing and existing.body or "")
  if not body then
    return nil
  end

  return {
    title = shorten(title, 24),
    body = body,
    updatedAt = nowStamp(),
  }
end

local function showNotes()
  local selected = 1
  while true do
    local items = {}
    for i, note in ipairs(state.notes) do
      items[i] = {
        label = shorten(note.title, 22),
      }
    end

    if #items == 0 then
      items[1] = { label = "(no notes yet)" }
    end

    local index, action = ui.chooseMenu("Notes", items, {
      selected = math.max(1, selected),
      subtitle = "N new  Enter view/edit",
      status = refreshSession().status,
      footer = "N new  D delete  Back home",
      extraKeys = {
        [keys.n] = "new",
        [keys.d] = "delete",
      },
    })

    selected = index
    if action == "back" or action == "home" then
      return "home"
    elseif action == "new" then
      local note = editNote(nil)
      if note then
        table.insert(state.notes, 1, note)
        saveNotes()
        addMessage("Note Saved", "Saved note '" .. note.title .. "'.", "info")
        selected = 1
      end
    elseif action == "delete" and state.notes[index] then
      if ui.confirm("Delete Note", {
        "Delete '" .. state.notes[index].title .. "'?",
      }, { status = refreshSession().status }) then
        table.remove(state.notes, index)
        saveNotes()
        selected = math.max(1, math.min(selected, #state.notes))
      end
    elseif action == "select" and state.notes[index] then
      viewNote(state.notes[index])
      if ui.confirm("Edit Note", {
        "Update this note now?",
      }, { status = refreshSession().status }) then
        local updated = editNote(state.notes[index])
        if updated then
          state.notes[index] = updated
          saveNotes()
        end
      end
    end
  end
end

local function showSettings()
  local selected = 1
  local labels = {
    {
      kind = "toggle",
      key = "sound",
      name = "Sound",
    },
    {
      kind = "toggle",
      key = "animations",
      name = "Animations",
    },
    {
      kind = "toggle",
      key = "autoAuth",
      name = "Auto Auth On Boot",
    },
    {
      kind = "toggle",
      key = "confirmWagers",
      name = "Confirm Wagers",
    },
    {
      kind = "action",
      action = "update",
      name = "Check For Updates",
    },
  }

  local function checkForUpdatesNow()
    local callbackStatus = "checking"
    local callbackMessage = "Contacting update server..."

    local function renderProgress()
      ui.showMessage("Update Check", {
        string.upper(tostring(callbackStatus or "checking")),
        tostring(callbackMessage or ""),
      }, {
        subtitle = "Pocket Casino OS",
        status = refreshSession().status,
        footer = "Working...",
        wait = false,
      })
    end

    renderProgress()

    local result = updater.checkForUpdates({
      callback = function(status, msg)
        callbackStatus = status
        callbackMessage = msg
        renderProgress()
      end,
    })

    local install = updater.getInstallInfo() or {}
    local version = tostring(install.version or "?")

    if result == "updated" then
      addMessage("Phone Updated", "Pocket Casino OS updated to v" .. version .. ".", "info")
      if ui.confirm("Update Applied", {
        "Pocket Casino OS updated to v" .. version .. ".",
        "Reboot now to load the new files?",
      }, { status = refreshSession().status }) then
        os.reboot()
      end
      ui.showMessage("Update Applied", {
        "Update is installed.",
        "Reboot the phone when you are ready.",
      }, { status = refreshSession().status })
    elseif result == "up-to-date" then
      ui.showMessage("Up To Date", {
        "Pocket Casino OS is current.",
        "Installed version: v" .. version,
      }, { status = refreshSession().status })
    elseif result == "skipped" then
      ui.showMessage("Update Skipped", {
        tostring(callbackMessage or "Another update is already running."),
      }, { status = refreshSession().status })
    else
      ui.showMessage("Update Error", {
        tostring(callbackMessage or "Update check failed."),
      }, { status = refreshSession().status })
    end
  end

  while true do
    local items = {}
    for i, item in ipairs(labels) do
      if item.kind == "toggle" then
        local enabled = state.settings[item.key]
        items[i] = {
          label = item.name .. ": " .. (enabled and "ON" or "OFF"),
        }
      else
        items[i] = {
          label = item.name,
        }
      end
    end

    local index, action = ui.chooseMenu("Settings", items, {
      selected = selected,
      subtitle = "Enter toggle or open",
      status = refreshSession().status,
      footer = "Enter open  Back home",
    })

    selected = index
    if action == "back" or action == "home" then
      return "home"
    elseif action == "select" and labels[index] then
      local item = labels[index]
      if item.kind == "toggle" then
        local key = item.key
        state.settings[key] = not state.settings[key]
        saveSettings()
      elseif item.action == "update" then
        checkForUpdatesNow()
      end
    end
  end
end

local function showPlaceholder(gameName)
  ui.showMessage(gameName, {
    gameName .. " is still monitor-first.",
    "Use the cabinet or table build for the full layout.",
    "Blackjack and Slots are pocket-ready now.",
  }, { status = refreshSession().status })
  return "home"
end

local function buildAppEnv()
  return {
    ui = ui,
    rootDir = ROOT,
    dataDir = DATA_DIR,
    settings = state.settings,
    refreshSession = refreshSession,
    ensureAuthenticated = ensureAuthenticated,
    promptBet = promptBet,
    addMessage = addMessage,
    playSound = playSound,
    isLiveSession = isLiveSession,
    showMessage = function(title, lines, opts)
      return ui.showMessage(title, lines, opts)
    end,
    confirm = function(title, lines, opts)
      return ui.confirm(title, lines, opts)
    end,
    blackjackConfig = blackjackConfig,
    slotsConfig = slotsConfig,
  }
end

local function runGame(appModule)
  local env = buildAppEnv()
  local ok, result = pcall(appModule.run, env)
  if not ok then
    alert.log("Pocket game error: " .. tostring(result))
    addMessage("Game Error", tostring(result), "error")
    ui.showMessage("Game Error", {
      tostring(result),
    }, { status = refreshSession().status })
  end
  return "home"
end

local function recoverPendingGames()
  local env = buildAppEnv()
  local ok, result = pcall(blackjackApp.recoverPending, env)
  if not ok then
    alert.log("Pocket recovery error: " .. tostring(result))
    addMessage("Recovery Error", tostring(result), "error")
    ui.showMessage("Recovery Error", {
      tostring(result),
    }, { status = refreshSession().status })
    return false
  end

  return result ~= false
end

local function showHome()
  local selected = 1

  while true do
    local session = refreshSession()
    local items = {
      { key = "wallet",    label = "Wallet" },
      { key = "blackjack", label = "Blackjack" },
      { key = "slots",     label = "Slots" },
      { key = "history",   label = "History" },
      { key = "notes",     label = "Notes (" .. tostring(#state.notes) .. ")" },
      { key = "settings",  label = "Settings" },
      { key = "roulette",  label = "Roulette" },
      { key = "baccarat",  label = "Baccarat" },
    }

    local subtitle = shorten((session.playerName or "Unknown") .. "  " ..
      (session.playerBalance and currency.formatTokens(session.playerBalance) or "wallet locked"), 26)

    local index, action = ui.chooseMenu("Pocket Casino", items, {
      selected = selected,
      subtitle = subtitle,
      status = session.status,
      footer = "Enter open  R refresh  Back exit",
    })

    selected = index
    if action == "back" then
      if ui.confirm("Exit Pocket Casino", {
        "Close the phone operating system now?",
      }, { status = session.status }) then
        return nil
      end
    elseif action == "refresh" then
      -- redraw
    elseif action == "select" then
      return items[index].key
    end
  end
end

bootSplash()

if state.settings.autoAuth then
  pcall(ensureAuthenticated, "Auto-auth enabled in settings.")
end

local current = "home"

while current do
  if current == "home" then
    if recoverPendingGames() then
      current = showHome()
    else
      current = nil
    end
  elseif current == "wallet" then
    current = showWallet()
  elseif current == "history" then
    current = showHistory()
  elseif current == "messages" then
    current = showMessages()
  elseif current == "notes" then
    current = showNotes()
  elseif current == "settings" then
    current = showSettings()
  elseif current == "blackjack" then
    current = runGame(blackjackApp)
  elseif current == "slots" then
    current = runGame(slotsApp)
  elseif current == "roulette" then
    current = showPlaceholder("Roulette")
  elseif current == "baccarat" then
    current = showPlaceholder("Baccarat")
  else
    current = "home"
  end
end

ui.clear(colors.black)
ui.header("Pocket Casino", "Session closed", refreshSession().status)
ui.center(10, "Goodbye.", colors.white)
ui.footer("Run startup.lua to reopen")
