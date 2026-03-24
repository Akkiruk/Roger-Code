local constants = require("lib.vaultgear.constants")
local evaluator = require("lib.vaultgear.evaluator")
local util = require("lib.vaultgear.util")

local M = {}

local theme = {
  background = colors.black,
  panel = colors.black,
  header = colors.lightBlue,
  header_text = colors.black,
  title = colors.gray,
  tab = colors.gray,
  tab_text = colors.white,
  tab_selected = colors.lightGray,
  tab_selected_text = colors.black,
  accent = colors.blue,
  accent_text = colors.white,
  positive = colors.green,
  negative = colors.red,
  warning = colors.yellow,
  muted = colors.lightGray,
  preview_selected = colors.lightGray,
  preview_selected_text = colors.black,
}

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

local function fillLine(x, y, width, bg)
  if width <= 0 then
    return
  end
  term.setCursorPos(x, y)
  term.setBackgroundColor(bg)
  term.write(string.rep(" ", width))
end

local function fillRect(x, y, width, height, bg)
  for row = 0, math.max(0, height - 1) do
    fillLine(x, y + row, width, bg)
  end
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
  if width <= 0 then
    return
  end

  local text = util.trimText(label or "", math.max(1, width - 2))
  local leftPad = math.max(0, math.floor((width - #text) / 2))
  local rendered = string.rep(" ", leftPad) .. text
  rendered = rendered .. string.rep(" ", math.max(0, width - #rendered))

  writeAt(x, y, rendered, nil, fg or theme.accent_text, bg or theme.accent)
  addZone(frame, id, x, y, x + width - 1, y, data)
end

local function panel(x, y, width, height, title, headerColor)
  if width <= 0 or height <= 0 then
    return
  end

  fillRect(x, y, width, height, theme.panel)
  fillLine(x, y, width, headerColor or theme.header)
  writeAt(x + 1, y, tostring(title or ""), math.max(1, width - 2), theme.header_text, headerColor or theme.header)
end

local function header(frame, app, width)
  local runLabel = app.config.runtime.enabled and " RUNNING " or " STOPPED "
  local runColor = app.config.runtime.enabled and theme.positive or theme.negative

  fillLine(1, 1, width, theme.title)
  writeAt(2, 1, constants.APP_NAME, math.max(1, width - 14), colors.white, theme.title)
  writeAt(width - 10, 1, runLabel, 10, colors.white, runColor)

  local gap = 1
  local tabCount = #constants.TABS
  local tabWidth = math.max(8, math.floor((width - ((tabCount - 1) * gap)) / tabCount))
  local x = 1
  for index, tab in ipairs(constants.TABS) do
    if index == tabCount then
      tabWidth = width - x + 1
    end

    local selected = app.ui.page == tab.id
    button(
      frame,
      "tab",
      x,
      2,
      tabWidth,
      tab.label,
      selected and theme.tab_selected_text or theme.tab_text,
      selected and theme.tab_selected or theme.tab,
      { tab = tab.id }
    )
    x = x + tabWidth + gap
  end

  fillLine(1, 3, width, theme.background)
end

local function actionText(action)
  if action == "discard" then
    return "Trash"
  end
  return "Keep"
end

local function unidentifiedText(mode)
  if mode == "discard" then
    return "Trash"
  end
  if mode == "evaluate_basic" then
    return "Basic"
  end
  return "Keep"
end

local function currentFilterText(itemType, profile)
  if not profile then
    return "No profile"
  end

  if not evaluator.profileHasActiveFilters(profile) then
    return "No keep filters"
  end

  if profile.min_rarity and profile.min_rarity ~= "ANY" then
    return profile.min_rarity .. "+"
  end
  if profile.min_uses then
    return tostring(profile.min_uses) .. "+ uses"
  end
  if profile.max_jewel_size then
    return "size <= " .. tostring(profile.max_jewel_size)
  end
  if profile.min_level and profile.max_level then
    return "Lv " .. tostring(profile.min_level) .. "-" .. tostring(profile.max_level)
  end
  if profile.min_level then
    return "Lv " .. tostring(profile.min_level) .. "+"
  end
  if profile.max_level then
    return "Lv <= " .. tostring(profile.max_level)
  end
  if profile.min_crafting_potential then
    return "CP >= " .. tostring(profile.min_crafting_potential)
  end
  if profile.min_free_repair_slots then
    return "repairs >= " .. tostring(profile.min_free_repair_slots)
  end
  if profile.min_durability_percent then
    return "durability >= " .. tostring(profile.min_durability_percent) .. "%"
  end
  if profile.wanted_modifiers and #profile.wanted_modifiers > 0 then
    if profile.wanted_modifier_mode == "all" then
      return "all wanted mods"
    end
    return "any wanted mod"
  end
  if profile.blocked_modifiers and #profile.blocked_modifiers > 0 then
    return "blocked mod rules"
  end

  return itemType .. " filters"
end

local function selectedTypeWarning(app, itemType)
  for _, warning in ipairs(app.health.warnings or {}) do
    if warning:find(itemType, 1, true) == 1 then
      return warning
    end
  end
  return nil
end

local function firstConfiguredRoleText(app)
  if not app.config.routing.input or app.config.routing.input == "" then
    return "Setup: choose the input inventory"
  end
  if not app.config.routing.keep or app.config.routing.keep == "" then
    return "Setup: choose the keep inventory"
  end
  if not app.config.routing.trash or app.config.routing.trash == "" then
    return "Setup: choose the trash inventory"
  end
  return nil
end

local function nextStep(app)
  if #app.health.errors > 0 then
    return app.health.errors[1]
  end

  local routingStep = firstConfiguredRoleText(app)
  if routingStep then
    return routingStep
  end

  local gearProfile = app.config.type_profiles.Gear
  if gearProfile and evaluator.profileHasActiveFilters(gearProfile) and gearProfile.miss_action == "keep" then
    return "Rules: Gear misses still go to Keep. Tap Common+ to trash scrappy gear."
  end

  if gearProfile and evaluator.profileHasActiveFilters(gearProfile) and gearProfile.unidentified_mode == "keep" then
    return "Rules: unidentified gear still bypasses filters. Use Basic or Trash."
  end

  if not app.config.runtime.enabled then
    return "Press Start once setup and rules look right."
  end

  if #(app.preview.items or {}) == 0 then
    return "Put Vault gear in the input inventory, then tap Scan Now."
  end

  return "Tap a preview item to see exactly why it moves."
end

local function roleLabel(roleId)
  for _, role in ipairs(constants.ROUTING_ROLES) do
    if role.id == roleId then
      return role.label
    end
  end
  return tostring(roleId or "-")
end

local function selectedDecisionLines(entry)
  if not entry then
    return {
      "No preview item selected.",
      "Put gear in the input inventory.",
      "Then tap Scan Now.",
    }
  end

  local decision = entry.decision or {}
  local reasons = decision.reasons or {}
  local item = entry.item or {}
  local primaryReason = reasons[1] or "No decision details"
  local hint = reasons[#reasons] or ""

  if primaryReason == "Unidentified -> keep" then
    hint = "Rules: set Unidentified to Basic or Trash."
  elseif primaryReason == "Unidentified -> discard" then
    hint = "This item is being trashed before other checks."
  elseif hint == "Miss -> keep" then
    hint = "Rules: change Misses Go To if you want failed items trashed."
  elseif hint == "Miss -> discard" then
    hint = "This item failed the rule and is going to Trash."
  elseif hint == "Profile matched" then
    hint = "This item passed the active keep rule."
  end

  return {
    tostring(item.display_name or item.registry_name or "Item"),
    string.upper(actionText(decision.action)) .. ": " .. primaryReason,
    hint ~= "" and hint or ((item.item_type or "Item") .. " | " .. (item.rarity or "-") .. " | Lv" .. tostring(item.level or "-")),
  }
end

local function summaryLinesForProfile(app, itemType)
  local profile = app.config.type_profiles[itemType]
  if not profile then
    return {
      "No profile loaded.",
      "Misses -> Keep | Unidentified -> Keep",
      "Tap a preset to start.",
    }
  end

  local line1 = itemType .. ": " .. currentFilterText(itemType, profile)
  local line2 = "Misses -> " .. actionText(profile.miss_action) .. " | Unidentified -> " .. unidentifiedText(profile.unidentified_mode)

  local line3 = selectedTypeWarning(app, itemType)
  if not line3 then
    local alwaysKeep = {}
    if profile.keep_legendary then
      alwaysKeep[#alwaysKeep + 1] = "Legendary"
    end
    if profile.keep_soulbound then
      alwaysKeep[#alwaysKeep + 1] = "Soulbound"
    end
    if profile.keep_unique then
      alwaysKeep[#alwaysKeep + 1] = "Unique"
    end

    if #alwaysKeep > 0 then
      line3 = "Always keep: " .. table.concat(alwaysKeep, ", ")
    else
      line3 = string.format("Modifiers: Keep %d | Block %d", #(profile.wanted_modifiers or {}), #(profile.blocked_modifiers or {}))
    end
  end

  return { line1, line2, line3 }
end

local function previewBadge(entry)
  if entry and entry.decision and entry.decision.action == "discard" then
    return "TRASH", theme.negative
  end
  return "KEEP", theme.positive
end

local function renderPreviewList(frame, app, x, y, width, rows)
  local preview = app.preview.items or {}
  local selectedIndex = util.clamp(app.ui.preview_selected or 1, 1, math.max(1, #preview))

  for row = 0, rows - 1 do
    local index = row + 1
    local drawY = y + row
    fillLine(x, drawY, width, theme.panel)

    local entry = preview[index]
    if entry then
      local selected = index == selectedIndex
      local bg = selected and theme.preview_selected or theme.panel
      local fg = selected and theme.preview_selected_text or colors.white
      local badgeText, badgeColor = previewBadge(entry)

      fillLine(x, drawY, width, bg)
      writeAt(x, drawY, " " .. badgeText .. " ", 7, colors.white, badgeColor)
      writeAt(x + 8, drawY, tostring(entry.item.display_name or "?"), math.max(1, width - 8), fg, bg)
      addZone(frame, "run_select_preview", x, drawY, x + width - 1, drawY, { index = index })
    end
  end

  if #preview == 0 and rows > 0 then
    writeAt(x, y, "No preview yet. Finish setup, add gear, then tap Scan Now.", width, theme.muted, theme.panel)
  end
end

local function renderTypeButtons(frame, app, y, width, zoneId)
  local x = 1
  local maxRows = 2
  local row = 0

  for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
    local buttonWidth = math.max(8, #itemType + 3)
    if x + buttonWidth - 1 > width then
      row = row + 1
      if row >= maxRows then
        break
      end
      y = y + 1
      x = 1
    end

    local selected = app.ui.selected_type == itemType
    button(
      frame,
      zoneId,
      x,
      y,
      buttonWidth,
      itemType,
      selected and colors.black or colors.white,
      selected and colors.lightGray or theme.accent,
      { item_type = itemType }
    )
    x = x + buttonWidth + 1
  end

  return y
end

local function renderPresetButtons(frame, app, itemType, y, width)
  local presets = constants.PROFILE_PRESETS[itemType] or {}
  local count = #presets
  if count == 0 then
    return
  end

  local gap = 1
  local buttonWidth = math.max(8, math.floor((width - ((count - 1) * gap)) / count))
  local x = 1
  for index, preset in ipairs(presets) do
    if index == count then
      buttonWidth = width - x + 1
    end

    button(
      frame,
      "apply_preset",
      x,
      y,
      buttonWidth,
      preset.label,
      colors.white,
      index == 1 and colors.green or theme.accent,
      { item_type = itemType, preset_id = preset.id }
    )
    x = x + buttonWidth + gap
  end
end

local function friendlyProfileValue(profile, field)
  local value = profile[field]
  if field == "enabled" then
    return value and "On" or "Off"
  end
  if field == "miss_action" then
    return actionText(value)
  end
  if field == "unidentified_mode" then
    return unidentifiedText(value)
  end
  if field == "wanted_modifier_mode" then
    if value == "all" then
      return "All"
    end
    return "Any"
  end
  if type(value) == "boolean" then
    return value and "Yes" or "No"
  end
  if value == nil then
    return "Off"
  end
  return tostring(value)
end

local function ruleListText(list)
  if not list or #list == 0 then
    return "-"
  end

  local labels = {}
  for _, entry in ipairs(list) do
    labels[#labels + 1] = entry.label or entry.key
  end
  return util.trimText(table.concat(labels, ", "), 999)
end

local function selectedModifierLabel(app)
  local selectedKey = app.ui.selected_modifier_key
  if not selectedKey then
    return "None"
  end

  for _, entry in ipairs(app.catalog_entries or {}) do
    if entry.key == selectedKey then
      return entry.label
    end
  end

  return selectedKey
end

local function roleMarks(app, inventoryName)
  local marks = {}
  if app.config.routing.input == inventoryName then
    marks[#marks + 1] = "I"
  end
  if app.config.routing.keep == inventoryName then
    marks[#marks + 1] = "K"
  end
  if app.config.routing.trash == inventoryName then
    marks[#marks + 1] = "T"
  end

  if #marks == 0 then
    return "-"
  end

  return table.concat(marks, "")
end

local function renderHome(frame, app, width, height)
  local halfWidth = math.floor((width - 2) / 2)
  local rightX = width - halfWidth + 1
  local gearProfile = app.config.type_profiles.Gear or {}
  local preview = app.preview.items or {}
  local selectedIndex = util.clamp(app.ui.preview_selected or 1, 1, math.max(1, #preview))
  local selected = preview[selectedIndex]
  local selectedStart = math.max(15, height - 3)
  local previewRows = math.max(2, selectedStart - 11)
  local detailLines = selectedDecisionLines(selected)
  local flowText = "Gear: " .. currentFilterText("Gear", gearProfile)
    .. " | Miss " .. actionText(gearProfile.miss_action)
    .. " | Unid " .. unidentifiedText(gearProfile.unidentified_mode)

  button(frame, "run_toggle", 1, 4, halfWidth, app.config.runtime.enabled and "Stop Sorting" or "Start Sorting", colors.white, app.config.runtime.enabled and colors.red or colors.green)
  button(frame, "run_scan_now", rightX, 4, halfWidth, "Scan Now", colors.white, theme.accent)
  button(frame, "apply_preset", 1, 5, halfWidth, "Gear Common+", colors.white, colors.orange, { item_type = "Gear", preset_id = "common_plus" })
  button(frame, "apply_preset", rightX, 5, halfWidth, "Gear Keep All", colors.white, colors.brown, { item_type = "Gear", preset_id = "keep_all" })

  panel(1, 6, width, 4, "Status", theme.header)
  if #app.health.errors > 0 then
    writeAt(2, 7, app.health.errors[1], width - 2, theme.negative, theme.panel)
  elseif #app.health.warnings > 0 then
    writeAt(2, 7, app.health.warnings[1], width - 2, theme.warning, theme.panel)
  else
    writeAt(2, 7, string.format("Scanned %d | Keep %d | Trash %d | Errors %d", app.session.scanned, app.session.kept, app.session.discarded, app.session.errors), width - 2, colors.white, theme.panel)
  end
  writeAt(2, 8, flowText, width - 2, colors.white, theme.panel)
  writeAt(2, 9, nextStep(app), width - 2, theme.muted, theme.panel)

  panel(1, 10, width, math.max(2, selectedStart - 10), "Input Preview", theme.header)
  renderPreviewList(frame, app, 1, 11, width, previewRows)

  panel(1, selectedStart, width, math.max(2, height - selectedStart + 1), "Selected Decision", theme.header)
  for index = 1, math.min(height - selectedStart, #detailLines) do
    local fg = colors.white
    if index == 2 then
      fg = selected and selected.decision and selected.decision.action == "discard" and theme.negative or theme.positive
    elseif index == 3 then
      fg = theme.muted
    end
    writeAt(2, selectedStart + index, detailLines[index], width - 2, fg, theme.panel)
  end
end

local function renderSetup(frame, app, width, height)
  local gap = 1
  local roleWidth = math.floor((width - (2 * gap)) / 3)
  local currentX = 1

  for index, role in ipairs(constants.ROUTING_ROLES) do
    if index == #constants.ROUTING_ROLES then
      roleWidth = width - currentX + 1
    end

    local selected = app.ui.routing_role == role.id
    button(
      frame,
      "routing_role",
      currentX,
      4,
      roleWidth,
      role.label,
      selected and colors.black or colors.white,
      selected and colors.lightGray or theme.accent,
      { role = role.id }
    )
    currentX = currentX + roleWidth + gap
  end

  panel(1, 6, width, 5, "Current Setup", theme.header)
  writeAt(2, 7, "Input: " .. tostring(app.config.routing.input or "Not set"), width - 2, colors.white, theme.panel)
  writeAt(2, 8, "Keep:  " .. tostring(app.config.routing.keep or "Not set"), width - 2, colors.white, theme.panel)
  writeAt(2, 9, "Trash: " .. tostring(app.config.routing.trash or "Not set"), width - 2, colors.white, theme.panel)
  writeAt(2, 10, "Selected: " .. roleLabel(app.ui.routing_role) .. " | " .. tostring(app.config.runtime.scan_interval) .. "s | batch " .. tostring(app.config.runtime.batch_size), width - 2, theme.muted, theme.panel)

  button(frame, "routing_refresh", 1, 11, 10, "Refresh", colors.white, theme.accent)
  button(frame, "runtime_interval_down", 13, 11, 4, "S-", colors.white, colors.gray)
  button(frame, "runtime_interval_up", 18, 11, 4, "S+", colors.white, colors.gray)
  button(frame, "runtime_batch_down", 24, 11, 4, "B-", colors.white, colors.gray)
  button(frame, "runtime_batch_up", 29, 11, 4, "B+", colors.white, colors.gray)

  panel(1, 12, width, math.max(2, height - 11), "Available Inventories", theme.header)

  local startY = 13
  local visibleRows = math.max(1, height - startY + 1)
  local scroll = app.ui.inventory_scroll or 0
  local inventories = app.discovery.inventories or {}

  for row = 0, visibleRows - 1 do
    local index = scroll + row + 1
    local drawY = startY + row
    fillLine(1, drawY, width, theme.panel)

    local entry = inventories[index]
    if entry then
      local marks = roleMarks(app, entry.name)
      local validForRole = app.ui.routing_role ~= "input" or (entry.can_detail and entry.can_push)
      local fg = validForRole and colors.white or theme.warning
      local prefix = "[" .. marks .. "] "
      writeAt(2, drawY, prefix .. entry.label, width - 2, fg, theme.panel)
      addZone(frame, "routing_assign", 1, drawY, width, drawY, { name = entry.name })
    end
  end
end

local function renderRules(frame, app, width, height)
  local lastTypeRow = renderTypeButtons(frame, app, 4, width, "profiles_type")
  local selectedType = app.ui.selected_type
  local profile = app.config.type_profiles[selectedType]
  local summaryY = lastTypeRow + 1
  local summaryLines = summaryLinesForProfile(app, selectedType)
  local presetY = summaryY + 4
  local fieldsY = presetY + 2
  local fields = constants.PROFILE_FIELDS[selectedType] or {}
  local visibleRows = math.max(1, height - fieldsY)
  local scroll = app.ui.profile_scroll or 0
  local labelWidth = math.max(12, math.floor(width * 0.36))
  local leftButtonX = labelWidth + 3
  local rightButtonX = width - 2
  local valueX = leftButtonX + 4
  local valueWidth = math.max(1, rightButtonX - valueX - 1)

  panel(1, summaryY, width, 4, "Rule Summary", theme.header)
  writeAt(2, summaryY + 1, summaryLines[1], width - 2, colors.white, theme.panel)
  writeAt(2, summaryY + 2, summaryLines[2], width - 2, colors.white, theme.panel)
  writeAt(2, summaryY + 3, summaryLines[3], width - 2, selectedTypeWarning(app, selectedType) and theme.warning or theme.muted, theme.panel)

  panel(1, presetY, width, 2, "Starter Presets", theme.header)
  renderPresetButtons(frame, app, selectedType, presetY + 1, width)

  fillLine(1, fieldsY, width, theme.header)
  writeAt(2, fieldsY, "Fine Tune", width - 12, theme.header_text, theme.header)
  button(frame, "profiles_scroll_up", width - 8, fieldsY, 4, "Up", colors.white, colors.gray)
  button(frame, "profiles_scroll_down", width - 3, fieldsY, 3, "Dn", colors.white, colors.gray)

  for row = 0, visibleRows - 1 do
    local index = scroll + row + 1
    local field = fields[index]
    local drawY = fieldsY + row + 1
    fillLine(1, drawY, width, theme.panel)

    if field then
      local label = constants.PROFILE_LABELS[field] or field
      writeAt(2, drawY, label, labelWidth, colors.white, theme.panel)
      button(frame, "profiles_cycle", leftButtonX, drawY, 3, "<", colors.white, theme.accent, {
        field = field,
        delta = -1,
      })
      writeAt(valueX, drawY, friendlyProfileValue(profile, field), valueWidth, colors.yellow, theme.panel)
      button(frame, "profiles_cycle", rightButtonX, drawY, 3, ">", colors.white, theme.accent, {
        field = field,
        delta = 1,
      })
    end
  end
end

local function renderMods(frame, app, width, height)
  local lastTypeRow = renderTypeButtons(frame, app, 4, width, "modifiers_type")
  local selectedType = app.ui.selected_type
  local profile = app.config.type_profiles[selectedType]
  local controlsY = lastTypeRow + 1
  local listHeaderY = controlsY + 3
  local listStartY = listHeaderY + 1
  local rulesY = math.max(listStartY + 4, height - 4)
  local visibleRows = math.max(2, rulesY - listStartY)
  local catalogEntries = app.catalog_entries or {}
  local scroll = app.ui.catalog_scroll or 0
  local selectedLabel = selectedModifierLabel(app)

  panel(1, controlsY, width, 3, "Modifier Rules", theme.header)
  writeAt(2, controlsY + 1, "Wanted match: " .. friendlyProfileValue(profile, "wanted_modifier_mode") .. " | Selected: " .. selectedLabel, width - 2, colors.white, theme.panel)
  button(frame, "modifiers_mode_cycle", 1, controlsY + 2, 12, "Mode", colors.white, theme.accent)
  button(frame, "modifiers_add_keep", 14, controlsY + 2, 12, "+ Keep", colors.white, colors.green)
  button(frame, "modifiers_add_block", 27, controlsY + 2, 12, "+ Block", colors.white, colors.red)
  button(frame, "modifiers_clear_all", 40, controlsY + 2, width - 39, "Clear All", colors.white, colors.gray)

  fillLine(1, listHeaderY, width, theme.header)
  writeAt(2, listHeaderY, "Discovered Modifiers", width - 12, theme.header_text, theme.header)
  button(frame, "modifiers_catalog_up", width - 8, listHeaderY, 4, "Up", colors.white, colors.gray)
  button(frame, "modifiers_catalog_down", width - 3, listHeaderY, 3, "Dn", colors.white, colors.gray)

  for row = 0, visibleRows - 1 do
    local index = scroll + row + 1
    local drawY = listStartY + row
    fillLine(1, drawY, width, theme.panel)

    local entry = catalogEntries[index]
    if entry then
      local selected = app.ui.selected_modifier_key == entry.key
      local bg = selected and theme.preview_selected or theme.panel
      local fg = selected and theme.preview_selected_text or colors.white
      writeAt(2, drawY, entry.label, width - 2, fg, bg)
      addZone(frame, "modifiers_select_catalog", 1, drawY, width, drawY, { key = entry.key })
    end
  end

  panel(1, rulesY, width, math.max(2, height - rulesY + 1), "Current Rules", theme.header)
  writeAt(2, rulesY + 1, "Keep:  " .. ruleListText(profile.wanted_modifiers), width - 2, colors.green, theme.panel)
  writeAt(2, rulesY + 2, "Block: " .. ruleListText(profile.blocked_modifiers), width - 2, colors.red, theme.panel)
  button(frame, "modifiers_remove_keep", 1, height, math.floor((width - 1) / 2), "- Keep", colors.white, colors.gray)
  button(frame, "modifiers_remove_block", width - math.floor((width - 1) / 2) + 1, height, math.floor((width - 1) / 2), "- Block", colors.white, colors.gray)
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
  term.setBackgroundColor(theme.background)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  local width, height = term.getSize()
  frame.width = width
  frame.height = height

  header(frame, app, width)

  if not app.health.monitor_ok then
    writeAt(1, 5, app.health.monitor_error or "Monitor missing or too small", width, theme.negative, theme.background)
  else
    if app.ui.page == "run" then
      renderHome(frame, app, width, height)
    elseif app.ui.page == "routing" then
      renderSetup(frame, app, width, height)
    elseif app.ui.page == "profiles" then
      renderRules(frame, app, width, height)
    elseif app.ui.page == "modifiers" then
      renderMods(frame, app, width, height)
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
