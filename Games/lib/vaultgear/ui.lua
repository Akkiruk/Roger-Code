local constants = require("lib.vaultgear.constants")
local util = require("lib.vaultgear.util")

local M = {}

local function addZone(frame, id, x1, y1, x2, y2, data)
  frame.zones[#frame.zones + 1] = {
    id = id,
    x1 = x1,
    y1 = y1,
    x2 = x2,
    y2 = y2,
    data = data,
  }
end

local function fill(x, y, width, bg)
  term.setCursorPos(x, y)
  term.setBackgroundColor(bg)
  term.write(string.rep(" ", width))
end

local function writeAt(x, y, text, width, fg, bg)
  local value = tostring(text or "")
  if width and width > 0 then
    value = util.trimText(value, width)
    value = value .. string.rep(" ", math.max(0, width - #value))
  end

  if bg then
    term.setBackgroundColor(bg)
  end
  if fg then
    term.setTextColor(fg)
  end
  term.setCursorPos(x, y)
  term.write(value)
end

local function button(frame, id, x, y, width, label, fg, bg, data)
  local text = util.trimText(label, width)
  local pad = math.max(0, width - #text)
  local leftPad = math.floor(pad / 2)
  local rendered = string.rep(" ", leftPad) .. text .. string.rep(" ", width - #text - leftPad)
  writeAt(x, y, rendered, nil, fg or colors.white, bg or colors.blue)
  addZone(frame, id, x, y, x + width - 1, y, data)
end

local function firstReasonWithPrefix(reasons, prefix)
  for _, reason in ipairs(reasons or {}) do
    if type(reason) == "string" and reason:find(prefix, 1, true) == 1 then
      return reason
    end
  end
  return nil
end

local function decisionHint(entry)
  local decision = entry and entry.decision or {}
  local reasons = decision.reasons or {}

  if firstReasonWithPrefix(reasons, "Unidentified -> keep") then
    return "Profiles: set Unidentified to discard/basic"
  end
  if firstReasonWithPrefix(reasons, "Miss -> keep") then
    return "Profiles: set Miss Action to discard"
  end
  if firstReasonWithPrefix(reasons, "Wanted modifiers missing") then
    return "Modifiers: add/remove keep rules"
  end
  if firstReasonWithPrefix(reasons, "Blocked mod: ") then
    return "Modifiers: remove block rule if unwanted"
  end
  if firstReasonWithPrefix(reasons, "Below rarity floor") then
    return "Profiles: lower Min Rarity to keep more"
  end
  return nil
end

local function selectedDetailLines(entry)
  local item = entry and entry.item or {}
  local decision = entry and entry.decision or {}
  local reasons = decision.reasons or {}
  local lines = {}

  lines[#lines + 1] = string.format("%s | %s | Lv%s", item.item_type or "Item", item.rarity or "-", tostring(item.level or "-"))

  local actionLabel = string.upper(tostring(decision.action or "keep"))
  local primaryReason = reasons[1] or "No decision details"
  lines[#lines + 1] = actionLabel .. ": " .. primaryReason

  local hint = decisionHint(entry)
  if hint then
    lines[#lines + 1] = hint
    return lines
  end

  if #reasons > 1 then
    local tailReason = reasons[#reasons]
    if tailReason ~= primaryReason then
      lines[#lines + 1] = tailReason
      return lines
    end
  end

  lines[#lines + 1] = item.display_name or "-"
  return lines
end

local function header(frame, app, width)
  local runLabel = app.config.runtime.enabled and "RUNNING" or "STOPPED"
  local bg = app.config.runtime.enabled and colors.green or colors.red
  writeAt(1, 1, constants.APP_NAME, math.max(1, width - 12), colors.white, colors.gray)
  writeAt(width - 11, 1, " " .. runLabel .. " ", 11, colors.white, bg)

  local x = 1
  for _, tab in ipairs(constants.TABS) do
    local selected = app.ui.page == tab.id
    local tabWidth = math.max(8, #tab.label + 4)
    button(frame, "tab", x, 2, tabWidth, tab.label, selected and colors.black or colors.white, selected and colors.lightGray or colors.blue, {
      tab = tab.id,
    })
    x = x + tabWidth + 1
  end

  fill(1, 3, width, colors.gray)
end

local function renderRun(frame, app, width, height)
  local preview = app.preview.items or {}
  local selectedIndex = util.clamp(app.ui.preview_selected or 1, 1, math.max(1, #preview))
  local previewStart = 9
  local detailStart = math.max(previewStart + 4, height - 4)
  if detailStart <= previewStart then
    detailStart = height
  end
  local listHeight = math.max(1, detailStart - previewStart)

  button(frame, "run_toggle", 1, 4, 12, app.config.runtime.enabled and "Stop" or "Start", colors.white, app.config.runtime.enabled and colors.red or colors.green)
  button(frame, "run_scan_now", 14, 4, 12, "Scan Now", colors.white, colors.blue)
  button(frame, "run_reset_stats", 27, 4, 14, "Reset Stats", colors.white, colors.gray)

  writeAt(1, 6, "Input: " .. tostring(app.config.routing.input or "-"), width, colors.white, colors.black)
  writeAt(1, 7, string.format("Scanned %d | Keep %d | Trash %d | Errors %d", app.session.scanned, app.session.kept, app.session.discarded, app.session.errors), width, colors.white, colors.black)

  local statusLine = "Healthy"
  local statusColor = colors.lime
  if #app.health.errors > 0 then
    statusLine = app.health.errors[1]
    statusColor = colors.red
  elseif #app.health.warnings > 0 then
    statusLine = app.health.warnings[1]
    statusColor = colors.yellow
  elseif app.last_cycle_at then
    statusLine = "Last cycle " .. util.formatTime(app.last_cycle_at)
  end
  writeAt(1, 8, statusLine, width, statusColor, colors.black)

  for row = 0, listHeight - 1 do
    local index = row + 1
    local y = previewStart + row
    fill(1, y, width, colors.black)

    local entry = preview[index]
    if entry then
      local selected = index == selectedIndex
      local bg = selected and colors.lightGray or colors.black
      local fg = selected and colors.black or colors.white
      local badgeBg = entry.decision.action == "discard" and colors.red or colors.green
      writeAt(1, y, " " .. tostring(entry.slot) .. " ", 5, colors.white, badgeBg)
      local label = string.format("%s | %s", entry.item.item_type or "Item", entry.item.display_name or "?")
      writeAt(7, y, label, width - 6, fg, bg)
      addZone(frame, "run_select_preview", 1, y, width, y, { index = index })
    end
  end

  if #preview == 0 then
    writeAt(1, previewStart, "No preview items yet. Configure routing, then scan.", width, colors.lightGray, colors.black)
  end

  if #preview > 0 then
    local selected = preview[selectedIndex]
    local detailY = detailStart
    fill(1, detailY, width, colors.gray)
    writeAt(1, detailY, "Selected Decision", width, colors.white, colors.gray)
    local lines = selectedDetailLines(selected)
    for i = 1, math.min(3, #lines) do
      local fg = colors.white
      if i == 2 then
        if selected.decision.action == "discard" then
          fg = colors.red
        else
          fg = colors.lime
        end
      elseif i == 3 then
        fg = colors.lightGray
      end
      writeAt(1, detailY + i, lines[i], width, fg, colors.black)
    end
  end
end

local function renderRouting(frame, app, width, height)
  local roleX = 1
  for _, role in ipairs(constants.ROUTING_ROLES) do
    local selected = app.ui.routing_role == role.id
    button(frame, "routing_role", roleX, 4, 10, role.label, selected and colors.black or colors.white, selected and colors.lightGray or colors.blue, {
      role = role.id,
    })
    roleX = roleX + 11
  end
  button(frame, "routing_refresh", roleX, 4, 10, "Refresh", colors.white, colors.gray)

  writeAt(1, 6, "Input: " .. tostring(app.config.routing.input or "-"), width, colors.white, colors.black)
  writeAt(1, 7, "Keep:  " .. tostring(app.config.routing.keep or "-"), width, colors.white, colors.black)
  writeAt(1, 8, "Trash: " .. tostring(app.config.routing.trash or "-"), width, colors.white, colors.black)

  button(frame, "runtime_interval_down", 1, 10, 3, "-", colors.white, colors.blue)
  writeAt(5, 10, "Interval " .. tostring(app.config.runtime.scan_interval) .. "s", 17, colors.white, colors.black)
  button(frame, "runtime_interval_up", 23, 10, 3, "+", colors.white, colors.blue)
  button(frame, "runtime_batch_down", 30, 10, 3, "-", colors.white, colors.blue)
  writeAt(34, 10, "Batch " .. tostring(app.config.runtime.batch_size), 13, colors.white, colors.black)
  button(frame, "runtime_batch_up", 48, 10, 3, "+", colors.white, colors.blue)

  local listStart = 12
  local visibleRows = math.max(1, height - listStart - 1)
  local scroll = app.ui.inventory_scroll or 0
  local inventories = app.discovery.inventories or {}

  button(frame, "routing_inventory_up", width - 8, listStart - 1, 4, "Up", colors.white, colors.gray)
  button(frame, "routing_inventory_down", width - 4, listStart - 1, 4, "Dn", colors.white, colors.gray)

  for row = 0, visibleRows - 1 do
    local index = scroll + row + 1
    local y = listStart + row
    fill(1, y, width, colors.black)
    local entry = inventories[index]
    if entry then
      local mark = " "
      if app.config.routing[app.ui.routing_role] == entry.name then
        mark = "*"
      end
      writeAt(1, y, mark .. " " .. entry.label, width, colors.white, colors.black)
      addZone(frame, "routing_assign", 1, y, width, y, { name = entry.name })
    end
  end
end

local function renderTypeButtons(frame, app, y, width, zonePrefix)
  local x = 1
  for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
    local selected = app.ui.selected_type == itemType
    local buttonWidth = math.max(8, #itemType + 2)
    if x + buttonWidth - 1 > width then
      y = y + 1
      x = 1
    end
    button(frame, zonePrefix, x, y, buttonWidth, itemType, selected and colors.black or colors.white, selected and colors.lightGray or colors.blue, {
      item_type = itemType,
    })
    x = x + buttonWidth + 1
  end
  return y
end

local function profileValue(profile, field)
  local value = profile[field]
  if value == nil then
    return "-"
  end
  return tostring(value)
end

local function renderProfiles(frame, app, width, height)
  local lastTypeRow = renderTypeButtons(frame, app, 4, width, "profiles_type")
  local selectedType = app.ui.selected_type
  local profile = app.config.type_profiles[selectedType]
  local fields = constants.PROFILE_FIELDS[selectedType] or {}
  local startY = lastTypeRow + 2
  local visibleRows = math.max(1, height - startY - 1)
  local scroll = app.ui.profile_scroll or 0

  button(frame, "profiles_scroll_up", width - 8, startY - 1, 4, "Up", colors.white, colors.gray)
  button(frame, "profiles_scroll_down", width - 4, startY - 1, 4, "Dn", colors.white, colors.gray)

  for row = 0, visibleRows - 1 do
    local index = scroll + row + 1
    local field = fields[index]
    local y = startY + row
    fill(1, y, width, colors.black)
    if field then
      local label = constants.PROFILE_LABELS[field] or field
      writeAt(1, y, label, math.floor(width * 0.45), colors.white, colors.black)
      button(frame, "profiles_cycle", math.floor(width * 0.45) + 2, y, 3, "<", colors.white, colors.blue, {
        field = field,
        delta = -1,
      })
      writeAt(math.floor(width * 0.45) + 6, y, profileValue(profile, field), math.max(1, width - math.floor(width * 0.45) - 12), colors.yellow, colors.black)
      button(frame, "profiles_cycle", width - 2, y, 3, ">", colors.white, colors.blue, {
        field = field,
        delta = 1,
      })
    end
  end
end

local function ruleListText(list)
  if not list or #list == 0 then
    return "-"
  end

  local names = {}
  for _, entry in ipairs(list) do
    names[#names + 1] = entry.label or entry.key
  end
  return table.concat(names, ", ")
end

local function renderModifiers(frame, app, width, height)
  local lastTypeRow = renderTypeButtons(frame, app, 4, width, "modifiers_type")
  local selectedType = app.ui.selected_type
  local profile = app.config.type_profiles[selectedType]
  local catalogEntries = app.catalog_entries or {}
  local startY = lastTypeRow + 2
  local catalogWidth = math.max(18, math.floor(width * 0.55))
  local scroll = app.ui.catalog_scroll or 0
  local visibleRows = math.max(3, height - startY - 6)

  local controlX = 1
  button(frame, "modifiers_mode_cycle", controlX, startY, 16, "Mode: " .. tostring(profile.wanted_modifier_mode), colors.white, colors.blue)
  controlX = controlX + 17
  button(frame, "modifiers_add_keep", controlX, startY, 10, "+ Keep", colors.white, colors.green)
  controlX = controlX + 11
  button(frame, "modifiers_add_block", controlX, startY, 10, "+ Block", colors.white, colors.red)

  controlX = 1
  button(frame, "modifiers_remove_keep", controlX, startY + 1, 10, "- Keep", colors.white, colors.gray)
  controlX = controlX + 11
  button(frame, "modifiers_remove_block", controlX, startY + 1, 10, "- Block", colors.white, colors.gray)

  button(frame, "modifiers_catalog_up", catalogWidth - 6, startY + 2, 4, "Up", colors.white, colors.gray)
  button(frame, "modifiers_catalog_down", catalogWidth - 2, startY + 2, 4, "Dn", colors.white, colors.gray)

  for row = 0, visibleRows - 1 do
    local index = scroll + row + 1
    local y = startY + 3 + row
    fill(1, y, catalogWidth, colors.black)
    local entry = catalogEntries[index]
    if entry then
      local selected = app.ui.selected_modifier_key == entry.key
      writeAt(1, y, (selected and ">" or " ") .. " " .. entry.label, catalogWidth, selected and colors.black or colors.white, selected and colors.lightGray or colors.black)
      addZone(frame, "modifiers_select_catalog", 1, y, catalogWidth, y, {
        key = entry.key,
      })
    end
  end

  fill(catalogWidth + 2, startY + 2, width - catalogWidth - 1, colors.gray)
  writeAt(catalogWidth + 2, startY + 2, "Rules", width - catalogWidth - 1, colors.white, colors.gray)
  writeAt(catalogWidth + 2, startY + 3, "Selected: " .. tostring(app.ui.selected_modifier_key or "-"), width - catalogWidth - 1, colors.white, colors.black)
  writeAt(catalogWidth + 2, startY + 4, "Keep: " .. ruleListText(profile.wanted_modifiers), width - catalogWidth - 1, colors.green, colors.black)
  writeAt(catalogWidth + 2, startY + 6, "Block: " .. ruleListText(profile.blocked_modifiers), width - catalogWidth - 1, colors.red, colors.black)
end

function M.render(app)
  local frame = {
    zones = {},
  }

  if not app.monitor or not app.monitor.peripheral then
    return frame
  end

  local oldTerm = term.current()
  term.redirect(app.monitor.peripheral)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  local width, height = term.getSize()
  frame.width = width
  frame.height = height

  header(frame, app, width)

  if not app.health.monitor_ok then
    writeAt(1, 5, app.health.monitor_error or "Monitor missing or too small", width, colors.red, colors.black)
  else
    if app.ui.page == "run" then
      renderRun(frame, app, width, height)
    elseif app.ui.page == "routing" then
      renderRouting(frame, app, width, height)
    elseif app.ui.page == "profiles" then
      renderProfiles(frame, app, width, height)
    elseif app.ui.page == "modifiers" then
      renderModifiers(frame, app, width, height)
    end
  end

  term.redirect(oldTerm)
  return frame
end

function M.hit(frame, x, y)
  for _, zone in ipairs(frame.zones or {}) do
    if x >= zone.x1 and x <= zone.x2 and y >= zone.y1 and y <= zone.y2 then
      return zone
    end
  end
  return nil
end

return M
