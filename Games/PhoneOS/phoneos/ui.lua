local ui = {}

local THEME = {
  background = colors.black,
  chromeBg = colors.gray,
  chromeText = colors.white,
  statusBg = colors.purple,
  statusText = colors.white,
  rule = colors.lightBlue,
  subtitle = colors.lightGray,
  accent = colors.magenta,
  selectionBg = colors.purple,
  selectionText = colors.white,
}

local PALETTE = {
  [colors.gray] = 0x1B1028,
  [colors.lightGray] = 0xD7CBEA,
  [colors.purple] = 0x5B2A86,
  [colors.magenta] = 0x9D4EDD,
  [colors.lightBlue] = 0xC6A0FF,
}

local paletteApplied = false

local function applyTheme()
  if paletteApplied or type(term.setPaletteColor) ~= "function" then
    return
  end

  for colorId, hex in pairs(PALETTE) do
    term.setPaletteColor(colorId, hex)
  end

  paletteApplied = true
end

local function termSize()
  return term.getSize()
end

local function clear(bg)
  applyTheme()
  term.setBackgroundColor(bg or THEME.background)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

local function writeAt(x, y, text, fg, bg)
  if bg then term.setBackgroundColor(bg) end
  if fg then term.setTextColor(fg) end
  term.setCursorPos(x, y)
  term.write(text)
end

local function center(y, text, fg, bg)
  local w = termSize()
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  writeAt(x, y, text, fg, bg)
  return x
end

local function rule(y, color)
  local w = termSize()
  writeAt(1, y, string.rep("-", w), color or THEME.rule)
end

local function wrap(text, width)
  local lines = {}
  text = tostring(text or "")
  width = math.max(1, width or select(1, termSize()))

  for rawLine in text:gmatch("[^\n]+") do
    local current = ""
    for word in rawLine:gmatch("%S+") do
      if current == "" then
        current = word
      elseif #current + 1 + #word <= width then
        current = current .. " " .. word
      else
        table.insert(lines, current)
        current = word
      end
    end
    if current ~= "" then
      table.insert(lines, current)
    elseif rawLine == "" then
      table.insert(lines, "")
    end
  end

  if #lines == 0 then
    table.insert(lines, "")
  end

  return lines
end

local function header(title, subtitle, status)
  applyTheme()
  local w = termSize()
  writeAt(1, 1, string.rep(" ", w), THEME.chromeText, THEME.chromeBg)
  center(1, tostring(title or ""), THEME.chromeText, THEME.chromeBg)

  if status and status ~= "" then
    local statusText = "[" .. status .. "]"
    writeAt(math.max(1, w - #statusText + 1), 1, statusText, THEME.statusText, THEME.statusBg)
  end

  if subtitle and subtitle ~= "" then
    writeAt(1, 2, string.rep(" ", w), colors.white, colors.black)
    writeAt(1, 2, subtitle:sub(1, w), THEME.subtitle, THEME.background)
  end

  rule(3, THEME.rule)
end

local function footer(text)
  applyTheme()
  local w, h = termSize()
  local shown = tostring(text or ""):sub(1, w)
  writeAt(1, h, string.rep(" ", w), THEME.chromeText, THEME.chromeBg)
  writeAt(1, h, shown, THEME.chromeText, THEME.chromeBg)
end

local function showMessage(title, lines, opts)
  opts = opts or {}
  clear(opts.bg or colors.black)
  header(title or "Info", opts.subtitle or "", opts.status or "")

  local w, h = termSize()
  local y = 5
  local allLines = {}

  if type(lines) == "string" then
    lines = { lines }
  end

  for _, line in ipairs(lines or {}) do
    local wrapped = wrap(line, w - 2)
    for _, wrappedLine in ipairs(wrapped) do
      table.insert(allLines, wrappedLine)
    end
  end

  local maxLines = math.max(1, h - 6)
  for i = 1, math.min(#allLines, maxLines) do
    writeAt(2, y, allLines[i], opts.textColor or colors.white)
    y = y + 1
  end

  footer(opts.footer or "Enter/Backspace to continue")

  if opts.wait == false then
    return
  end

  while true do
    local event, key = os.pullEvent("key")
    if event == "key" and (key == keys.enter or key == keys.backspace or key == keys.space) then
      return
    end
  end
end

local function confirm(title, lines, opts)
  opts = opts or {}
  clear(opts.bg or colors.black)
  header(title or "Confirm", opts.subtitle or "", opts.status or "")

  local w, h = termSize()
  local y = 5
  local allLines = {}

  if type(lines) == "string" then
    lines = { lines }
  end

  for _, line in ipairs(lines or {}) do
    local wrapped = wrap(line, w - 2)
    for _, wrappedLine in ipairs(wrapped) do
      table.insert(allLines, wrappedLine)
    end
  end

  for i = 1, math.min(#allLines, h - 7) do
    writeAt(2, y, allLines[i], colors.white)
    y = y + 1
  end

  footer("Y/Enter yes  N/Backspace no")

  while true do
    local _, key = os.pullEvent("key")
    if key == keys.y or key == keys.enter then
      return true
    elseif key == keys.n or key == keys.backspace then
      return false
    end
  end
end

local function promptLine(title, prompt, defaultValue, opts)
  opts = opts or {}
  clear(opts.bg or colors.black)
  header(title or "Input", opts.subtitle or "", opts.status or "")

  local w = termSize()
  local lines = wrap(prompt or "", w - 2)
  local y = 5
  for _, line in ipairs(lines) do
    writeAt(2, y, line, colors.white)
    y = y + 1
  end

  if defaultValue and defaultValue ~= "" then
    y = y + 1
    writeAt(2, y, "Default: " .. defaultValue, colors.lightGray)
    y = y + 1
  end

  writeAt(2, y, "> ", THEME.accent)
  footer("Enter save  Ctrl+T abort")
  term.setCursorPos(4, y)

  local ok, value = pcall(read, nil, nil, nil, defaultValue or "")
  if ok then
    return value
  end

  return nil
end

local function keyToDigit(key)
  local mapping = {
    [keys.one] = 1, [keys.two] = 2, [keys.three] = 3,
    [keys.four] = 4, [keys.five] = 5, [keys.six] = 6,
    [keys.seven] = 7, [keys.eight] = 8, [keys.nine] = 9,
  }
  return mapping[key]
end

local function chooseMenu(title, items, opts)
  opts = opts or {}
  local selected = math.max(1, opts.selected or 1)
  local offset = math.max(1, opts.offset or 1)

  while true do
    clear(opts.bg or colors.black)
    header(title or "Menu", opts.subtitle or "", opts.status or "")

    local w, h = termSize()
    local visible = math.max(1, h - 6)

    if selected < offset then
      offset = selected
    elseif selected >= offset + visible then
      offset = selected - visible + 1
    end

    if #items == 0 then
      center(math.floor(h / 2), "(empty)", colors.lightGray)
    else
      for row = 1, visible do
        local index = offset + row - 1
        if index > #items then break end

        local item = items[index]
        local y = 3 + row
        local isSelected = index == selected
        local bg = isSelected and THEME.selectionBg or THEME.background
        local fg = isSelected and THEME.selectionText or (item.disabled and colors.gray or colors.white)
        local prefix = tostring(index) .. ". "
        local text = prefix .. tostring(item.label or item)
        writeAt(1, y, string.rep(" ", w), fg, bg)
        writeAt(2, y, text:sub(1, w - 2), fg, bg)
      end
    end

    footer(opts.footer or "Arrows move  Enter open  Back exit  H home")

    local _, key = os.pullEvent("key")
    local digit = keyToDigit(key)

    if key == keys.up then
      selected = math.max(1, selected - 1)
    elseif key == keys.down then
      selected = math.min(math.max(1, #items), selected + 1)
    elseif key == keys.pageUp then
      selected = math.max(1, selected - visible)
    elseif key == keys.pageDown then
      selected = math.min(math.max(1, #items), selected + visible)
    elseif key == keys.enter then
      return selected, "select"
    elseif key == keys.backspace then
      return selected, "back"
    elseif key == keys.h then
      return selected, "home"
    elseif key == keys.r then
      return selected, "refresh"
    elseif digit then
      local target = offset + digit - 1
      if items[target] then
        selected = target
        return selected, "select"
      end
    elseif opts.extraKeys and opts.extraKeys[key] then
      return selected, opts.extraKeys[key]
    end
  end
end

ui.clear = clear
ui.writeAt = writeAt
ui.center = center
ui.rule = rule
ui.wrap = wrap
ui.header = header
ui.footer = footer
ui.showMessage = showMessage
ui.confirm = confirm
ui.promptLine = promptLine
ui.chooseMenu = chooseMenu
ui.theme = THEME

return ui
