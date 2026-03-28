local basalt = require("lib.basalt")
local catalog = require("lib.vaultgear.catalog")
local constants = require("lib.vaultgear.constants")
local evaluator = require("lib.vaultgear.evaluator")
local peripherals = require("lib.vaultgear.peripherals")
local routing = require("lib.vaultgear.routing")
local util = require("lib.vaultgear.util")

local M = {}

local palette = {
  bg = colors.black,
  surface = colors.gray,
  surface_alt = colors.lightGray,
  text = colors.white,
  text_dark = colors.black,
  muted = colors.lightGray,
  accent = colors.lightBlue,
  accent_dark = colors.blue,
  keep = colors.green,
  trash = colors.red,
  warning = colors.orange,
  gold = colors.yellow,
}

local theme = {
  default = {
    background = palette.bg,
    foreground = palette.text,
  },
  BaseFrame = {
    background = palette.bg,
    foreground = palette.text,
    Frame = {
      background = palette.bg,
      foreground = palette.text,
    },
    Label = {
      foreground = palette.text,
    },
    Button = {
      background = palette.accent_dark,
      foreground = palette.text,
      states = {
        clicked = {
          background = palette.accent,
          foreground = palette.text_dark,
        },
      },
    },
    List = {
      background = palette.bg,
      foreground = palette.text,
      selectedBackground = palette.accent,
      selectedForeground = palette.text_dark,
      scrollBarColor = palette.text,
      scrollBarBackgroundColor = palette.surface_alt,
    },
    DropDown = {
      background = palette.surface,
      foreground = palette.text,
      selectedBackground = palette.accent,
      selectedForeground = palette.text_dark,
      scrollBarColor = palette.text,
      scrollBarBackgroundColor = palette.surface_alt,
      states = {
        opened = {
          background = palette.surface_alt,
          foreground = palette.text_dark,
        },
      },
    },
    ScrollFrame = {
      background = palette.bg,
      foreground = palette.text,
      scrollBarColor = palette.text,
      scrollBarBackgroundColor = palette.surface_alt,
      scrollBarBackgroundColor2 = palette.bg,
    },
    TabControl = {
      background = palette.bg,
      foreground = palette.muted,
      headerBackground = palette.bg,
      activeTabBackground = palette.accent,
      activeTabTextColor = palette.text_dark,
    },
    SideNav = {
      background = palette.bg,
      foreground = palette.muted,
      sidebarBackground = palette.bg,
      activeTabBackground = palette.accent,
      activeTabTextColor = palette.text_dark,
    },
    ProgressBar = {
      background = palette.surface,
      foreground = palette.text,
      progressColor = palette.accent,
    },
    Switch = {
      background = palette.text,
      foreground = palette.text_dark,
      onBackground = palette.keep,
      offBackground = palette.trash,
    },
    Toast = {
      background = palette.bg,
      foreground = palette.text,
    },
  },
}

local choice_options = {
  miss_action = {
    { label = "Keep", value = "keep" },
    { label = "Trash", value = "discard" },
  },
  unidentified_mode = {
    { label = "Keep", value = "keep" },
    { label = "Trash", value = "discard" },
    { label = "Basic", value = "evaluate_basic" },
  },
  wanted_modifier_mode = {
    { label = "Any", value = "any" },
    { label = "All", value = "all" },
  },
  route_action = {
    { label = "Keep", value = "keep" },
    { label = "Trash", value = "discard" },
    { label = "Any", value = "any" },
  },
  route_type_mode = {
    { label = "All Types", value = "all" },
    { label = "Selected Types", value = "selected" },
  },
  min_rarity = {
    { label = "Off", value = "ANY" },
    { label = "Scrappy+", value = "SCRAPPY" },
    { label = "Common+", value = "COMMON" },
    { label = "Rare+", value = "RARE" },
    { label = "Epic+", value = "EPIC" },
    { label = "Omega+", value = "OMEGA" },
    { label = "Unique+", value = "UNIQUE" },
    { label = "Special+", value = "SPECIAL" },
    { label = "Chaotic+", value = "CHAOTIC" },
  },
}

local numeric_labels = {
  min_level = "Min Level",
  max_level = "Max Level",
  min_crafting_potential = "Min CP",
  min_free_repair_slots = "Free Repairs",
  min_durability_percent = "Durability %",
  max_jewel_size = "Max Jewel Size",
  min_uses = "Min Uses",
}

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

local function firstConfiguredRouteText(app)
  if not app.config.routing.input or app.config.routing.input == "" then
    return "Setup: choose the input inventory."
  end

  local destinations = app.config.routing.destinations or {}
  if #destinations == 0 then
    return "Setup: add at least one destination."
  end

  local configured = false
  for _, destination in ipairs(destinations) do
    if destination.enabled ~= false and destination.inventory and destination.inventory ~= "" then
      configured = true
      break
    end
  end
  if not configured then
    return "Setup: give at least one destination an inventory."
  end

  return nil
end

local function nextStep(app)
  if #app.health.errors > 0 then
    return app.health.errors[1]
  end

  local routingStep = firstConfiguredRouteText(app)
  if routingStep then
    return routingStep
  end

  local gearProfile = app.config.type_profiles.Gear
  if gearProfile and evaluator.profileHasActiveFilters(gearProfile) and gearProfile.miss_action == "keep" then
    return "Gear misses still go to Keep. Flip Misses Go To if you want misses trashed."
  end

  if gearProfile and evaluator.profileHasActiveFilters(gearProfile) and gearProfile.unidentified_mode == "keep" then
    return "Unidentified gear is bypassing your rules. Use Basic or Trash when you are ready."
  end

  if not app.config.runtime.enabled then
    return "Review the flow, then hit Start Sorting when everything feels right."
  end

  if #(app.preview.items or {}) == 0 then
    return "Drop Vault gear into the input inventory to generate a live preview."
  end

  return "Tap any preview item to inspect the exact keep or trash decision."
end

local function summaryLinesForProfile(app, itemType)
  local profile = app.config.type_profiles[itemType]
  if not profile then
    return {
      "No profile loaded.",
      "Misses -> Keep | Unidentified -> Keep",
      "Apply a preset to start shaping the profile.",
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
      line3 = "Safety keeps: " .. table.concat(alwaysKeep, ", ")
    else
      line3 = string.format("Modifiers: Keep %d | Block %d", #(profile.wanted_modifiers or {}), #(profile.blocked_modifiers or {}))
    end
  end

  return { line1, line2, line3 }
end

local function previewBadge(entry)
  if entry and entry.decision and entry.decision.action == "discard" then
    return "TRASH", palette.trash
  end
  return "KEEP", palette.keep
end

local function findInventoryLabel(app, inventoryName)
  if not inventoryName or inventoryName == "" then
    return "Not set"
  end

  local entry = peripherals.findInventory(app.discovery, inventoryName)
  if entry then
    return entry.label
  end

  return inventoryName .. " (missing)"
end

local function selectedDestination(app)
  return routing.findDestination(app.config.routing.destinations, app.ui.selected_destination_id)
end

local function destinationTitle(app, destination, index)
  local prefix = tostring(index or "?") .. ". "
  local inventory = findInventoryLabel(app, destination and destination.inventory)
  if destination and destination.enabled == false then
    return prefix .. "Paused -> " .. inventory
  end
  return prefix .. routing.actionSummary(destination) .. " -> " .. inventory
end

local function routeFlowSummary(app)
  local parts = {}
  for index, destination in ipairs(app.config.routing.destinations or {}) do
    if destination.enabled ~= false then
      local inventory = findInventoryLabel(app, destination.inventory)
      parts[#parts + 1] = string.format("%d:%s->%s", index, routing.actionSummary(destination), inventory)
      if #parts >= 3 then
        break
      end
    end
  end

  if #parts == 0 then
    return "Routes: none configured"
  end

  return "Routes: " .. table.concat(parts, " | ")
end

local function formatRecentEntry(entry)
  if not entry then
    return ""
  end

  local stamp = util.formatTime(entry.at)
  local prefix = "[" .. stamp .. "] "
  return prefix .. tostring(entry.message or "")
end

local function flattenLines(sourceLines, width, limit)
  local lines = {}
  for _, source in ipairs(sourceLines or {}) do
    local wrapped = util.wrapText(source, width, limit - #lines)
    for _, wrappedLine in ipairs(wrapped) do
      lines[#lines + 1] = wrappedLine
      if #lines >= limit then
        return lines
      end
    end
  end
  return lines
end

local function selectedDecisionLines(app, entry)
  if not entry then
    return {
      "No preview item selected yet.",
      "Scan the input inventory to populate the preview list.",
    }
  end

  local item = entry.item or {}
  local decision = entry.decision or {}
  local destination = entry.destination or nil
  local reasons = decision.reasons or {}
  local lines = {}

  lines[#lines + 1] = tostring(item.display_name or item.registry_name or "Item")
  lines[#lines + 1] = string.upper(actionText(decision.action)) .. ": " .. tostring(reasons[1] or "No decision details")
  if destination then
    lines[#lines + 1] = "Route: " .. routing.actionSummary(destination) .. " -> " .. findInventoryLabel(app, destination.inventory)
  else
    lines[#lines + 1] = "Route: no matching destination"
  end

  local stats = {
    item.item_type or "Item",
    item.rarity or "-",
    "Lv" .. tostring(item.level or "-"),
  }
  if item.identified == false then
    stats[#stats + 1] = "Unidentified"
  end
  lines[#lines + 1] = table.concat(stats, " | ")

  if type(item.crafting_potential_current) == "number" and type(item.crafting_potential_max) == "number" then
    lines[#lines + 1] = "Crafting potential: " .. item.crafting_potential_current .. "/" .. item.crafting_potential_max
  end
  if type(item.repair_free) == "number" and type(item.repair_total) == "number" then
    lines[#lines + 1] = "Repair slots: " .. item.repair_free .. " free of " .. item.repair_total
  end
  if type(item.durability_percent) == "number" then
    lines[#lines + 1] = "Durability: " .. util.formatPercent(item.durability_percent)
  end
  if type(item.jewel_size) == "number" then
    lines[#lines + 1] = "Jewel size: " .. tostring(item.jewel_size)
  end
  if type(item.uses) == "number" then
    lines[#lines + 1] = "Uses: " .. tostring(item.uses)
  end

  local tags = {}
  if item.is_soulbound then
    tags[#tags + 1] = "Soulbound"
  end
  if item.is_unique then
    tags[#tags + 1] = "Unique"
  end
  if item.is_legendary then
    tags[#tags + 1] = "Legendary"
  end
  if #tags > 0 then
    lines[#lines + 1] = "Tags: " .. table.concat(tags, ", ")
  end

  for index = 2, math.min(#reasons, 5) do
    lines[#lines + 1] = "Reason: " .. reasons[index]
  end

  local modifiers = {}
  for _, modifier in ipairs(item.modifiers and item.modifiers.all or {}) do
    modifiers[#modifiers + 1] = modifier.label
    if #modifiers >= 3 then
      break
    end
  end
  if #modifiers > 0 then
    lines[#lines + 1] = "Seen mods: " .. table.concat(modifiers, ", ")
  end

  return lines
end

local function setLabelLines(labels, lines)
  for index, label in ipairs(labels or {}) do
    label:setText(lines[index] or "")
  end
end

local function setWrappedLabelLines(labels, sourceLines, width)
  local lines = flattenLines(sourceLines, width, #labels)
  setLabelLines(labels, lines)
end

local function chooseColor(level)
  if level == "error" then
    return palette.trash
  end
  if level == "warning" then
    return palette.warning
  end
  return palette.text
end

local function setDropdownItems(dropdown, options, selectedValue)
  dropdown:clear()
  for _, option in ipairs(options or {}) do
    dropdown:addItem({
      text = option.label,
      value = option.value,
      selected = option.value == selectedValue,
    })
  end

  if selectedValue ~= nil then
    for index, option in ipairs(options or {}) do
      if option.value == selectedValue then
        dropdown:selectItem(index)
        break
      end
    end
  end
end

local function addCard(parent, props, title, accent)
  local card = parent:addFrame(props)
  card:setBackground(palette.surface)
  card:addBorder(palette.surface_alt, {
    left = true,
    right = true,
    bottom = true,
  })
  card:addLabel({
    x = 1,
    y = 1,
    width = "{parent.width}",
    text = " " .. tostring(title or ""),
    background = accent or palette.accent,
    foreground = palette.text_dark,
  })
  return card
end

local function addDropdownRow(controller, parent, y, labelText, onSelect)
  local label = parent:addLabel({
    x = 2,
    y = y,
    width = "{parent.width - 22}",
    text = labelText,
    foreground = palette.muted,
  })

  local dropdown = parent:addDropDown({
    x = "{parent.width - 18}",
    y = y,
    width = 17,
    dropdownHeight = 6,
    selectedText = "Select",
    background = palette.surface,
  })

  dropdown:onSelect(function(_, _, item)
    if controller.suppress_events then
      return
    end
    if item and item.value ~= nil then
      onSelect(item.value)
    end
  end)

  return {
    label = label,
    dropdown = dropdown,
  }
end

local function addStepperRow(controller, parent, y, labelText, onMinus, onPlus)
  local label = parent:addLabel({
    x = 2,
    y = y,
    width = "{parent.width - 16}",
    text = labelText,
    foreground = palette.muted,
  })

  local minus = parent:addButton({
    x = "{parent.width - 13}",
    y = y,
    width = 3,
    height = 1,
    text = "-",
    background = palette.surface,
  })
  minus:onClick(function()
    if controller.suppress_events then
      return
    end
    onMinus()
  end)

  local value = parent:addLabel({
    x = "{parent.width - 9}",
    y = y,
    width = 6,
    text = "Off",
    foreground = palette.text,
    background = palette.bg,
  })

  local plus = parent:addButton({
    x = "{parent.width - 2}",
    y = y,
    width = 3,
    height = 1,
    text = "+",
    background = palette.surface,
  })
  plus:onClick(function()
    if controller.suppress_events then
      return
    end
    onPlus()
  end)

  return {
    label = label,
    value = value,
    minus = minus,
    plus = plus,
  }
end

local function addSwitchRow(controller, parent, y, labelText, onChange)
  local switch = parent:addSwitch({
    x = 2,
    y = y,
    width = 5,
    height = 1,
    text = labelText,
  })

  switch:onChange("checked", function(_, checked)
    if controller.suppress_events then
      return
    end
    onChange(checked)
  end)

  return switch
end

local function pageIndex(pageId)
  for index, tab in ipairs(constants.TABS) do
    if tab.id == pageId then
      return index
    end
  end
  return 1
end

local function typeIndex(itemType)
  for index, value in ipairs(constants.SUPPORTED_TYPES) do
    if value == itemType then
      return index
    end
  end
  return 1
end

local function inventoryOptions(app, requireInputCapabilities, allowUnset)
  local items = {}
  if allowUnset then
    items[#items + 1] = {
      label = "Not set",
      value = "",
    }
  end

  for _, entry in ipairs(app.discovery.inventories or {}) do
    local valid = not requireInputCapabilities or (entry.can_detail and entry.can_push)
    if valid then
      items[#items + 1] = {
        label = entry.label,
        value = entry.name,
      }
    end
  end

  if #items == 0 then
    items[1] = {
      label = "No inventory found",
      value = nil,
    }
  end

  return items
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
  if field == "min_rarity" and (value == nil or value == "ANY") then
    return "Off"
  end
  if type(value) == "boolean" then
    return value and "Yes" or "No"
  end
  if value == nil then
    return "Off"
  end
  return tostring(value)
end

local function buildHeader(controller)
  local refs = controller.refs
  local frame = controller.frame

  refs.header = frame:addFrame({
    x = 1,
    y = 1,
    width = "{parent.width}",
    height = 3,
    background = palette.bg,
  })

  refs.header:addLabel({
    x = 1,
    y = 1,
    width = "{parent.width}",
    text = string.rep(" ", 1),
    background = palette.accent,
  })

  refs.title = refs.header:addLabel({
    x = 2,
    y = 1,
    width = "{parent.width - 16}",
    text = constants.APP_NAME,
    foreground = palette.text_dark,
    background = palette.accent,
  })

  refs.runtime_pill = refs.header:addLabel({
    x = "{parent.width - 11}",
    y = 1,
    width = 10,
    text = " STOPPED ",
    foreground = palette.text,
    background = palette.trash,
  })

  refs.subtitle = refs.header:addLabel({
    x = 2,
    y = 2,
    width = "{parent.width - 25}",
    text = "Preparing the sorter UI...",
    foreground = palette.muted,
  })

  refs.run_button = refs.header:addButton({
    x = "{parent.width - 21}",
    y = 2,
    width = 10,
    height = 1,
    text = "Start",
    background = palette.keep,
    foreground = palette.text_dark,
  })
  refs.run_button:onClick(function()
    controller.actions.toggleRuntime()
  end)

  refs.scan_button = refs.header:addButton({
    x = "{parent.width - 10}",
    y = 2,
    width = 10,
    height = 1,
    text = "Scan Now",
  })
  refs.scan_button:onClick(function()
    controller.actions.scanNow()
  end)

  refs.toast = frame:addToast({
    x = "{parent.width - self.width}",
    y = 1,
    width = 28,
    height = 3,
  })
end

local function buildNotice(controller)
  local refs = controller.refs
  refs.notice = controller.frame:addFrame({
    x = 1,
    y = 4,
    width = "{parent.width}",
    height = "{parent.height - 3}",
    background = palette.bg,
  })

  local notice_card = addCard(refs.notice, {
    x = 1,
    y = 1,
    width = "{parent.width}",
    height = "{parent.height}",
  }, "Monitor Needed", palette.warning)

  refs.notice_lines = {}
  for index = 1, 6 do
    refs.notice_lines[index] = notice_card:addLabel({
      x = 2,
      y = index + 1,
      width = "{parent.width - 3}",
      text = "",
      foreground = index == 1 and palette.warning or palette.text,
    })
  end
end

local function buildDashboard(controller, dashboard)
  local refs = controller.refs

  refs.dashboard = {}
  refs.dashboard.hero = addCard(dashboard, {
    x = 1,
    y = 1,
    width = "{parent.width}",
    height = 5,
  }, "Live Status", palette.accent)

  refs.dashboard.status_lines = {}
  for index = 1, 3 do
    refs.dashboard.status_lines[index] = refs.dashboard.hero:addLabel({
      x = 2,
      y = index + 1,
      width = "{parent.width - 3}",
      text = "",
      foreground = index == 1 and palette.text or palette.muted,
    })
  end

  refs.dashboard.progress = refs.dashboard.hero:addProgressBar({
    x = 2,
    y = 5,
    width = "{parent.width - 3}",
    height = 1,
    background = palette.surface,
    progressColor = palette.keep,
  })

  refs.dashboard.preview_card = addCard(dashboard, {
    name = "dashboardPreviewCard",
    x = 1,
    y = 7,
    width = "{math.max(24, math.floor(parent.width * 0.56))}",
    height = "{parent.height - 6}",
  }, "Input Preview", palette.accent_dark)

  refs.dashboard.preview_list = refs.dashboard.preview_card:addList({
    x = 1,
    y = 2,
    width = "{parent.width}",
    height = "{parent.height - 1}",
    emptyText = "No preview yet",
    showScrollBar = true,
  })
  refs.dashboard.preview_list:onSelect(function(_, index)
    if controller.suppress_events then
      return
    end
    controller.actions.selectPreview(index)
  end)

  refs.dashboard.detail_card = addCard(dashboard, {
    name = "dashboardDetailCard",
    x = "{dashboardPreviewCard.x + dashboardPreviewCard.width + 1}",
    y = 7,
    width = "{parent.width - dashboardPreviewCard.width - 1}",
    height = "{math.max(6, math.floor((parent.height - 6) * 0.62))}",
  }, "Decision Breakdown", palette.keep)

  refs.dashboard.detail_list = refs.dashboard.detail_card:addList({
    x = 1,
    y = 2,
    width = "{parent.width}",
    height = "{parent.height - 1}",
    emptyText = "Select a preview item",
    showScrollBar = true,
    selectable = false,
  })

  refs.dashboard.recent_card = addCard(dashboard, {
    name = "dashboardRecentCard",
    x = "{dashboardPreviewCard.x + dashboardPreviewCard.width + 1}",
    y = "{dashboardDetailCard.y + dashboardDetailCard.height + 1}",
    width = "{parent.width - dashboardPreviewCard.width - 1}",
    height = "{parent.height - dashboardDetailCard.height - 7}",
  }, "Recent Activity", palette.warning)

  refs.dashboard.recent_list = refs.dashboard.recent_card:addList({
    x = 1,
    y = 2,
    width = "{parent.width}",
    height = "{parent.height - 1}",
    emptyText = "No activity yet",
    showScrollBar = true,
    selectable = false,
  })
end

local function buildRulesPage(controller, rules_tab)
  local refs = controller.refs
  refs.rules = {}

  refs.rules.types = rules_tab:addSideNav({
    x = 1,
    y = 1,
    width = "{parent.width}",
    height = "{parent.height}",
    sidebarBackground = palette.bg,
    activeTabBackground = palette.accent,
    activeTabTextColor = palette.text_dark,
    foreground = palette.muted,
    sidebarWidth = 10,
  })

  refs.rules.types:registerCallback("tabChanged", function(_, new_tab)
    if controller.suppress_events then
      return
    end
    controller.actions.selectType(constants.SUPPORTED_TYPES[new_tab])
  end)

  for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
    local type_tab = refs.rules.types:newTab(itemType)
    local page = {
      summary = {},
      presets = {},
      choices = {},
      switches = {},
      numbers = {},
    }

    local scroll = type_tab:addScrollFrame({
      x = 1,
      y = 1,
      width = "{parent.width}",
      height = "{parent.height}",
      background = palette.bg,
      showScrollBar = true,
    })

    local y = 1
    page.summary_card = addCard(scroll, {
      x = 1,
      y = y,
      width = "{parent.width - 1}",
      height = 5,
    }, "Live Summary", palette.accent)
    for index = 1, 3 do
      page.summary[index] = page.summary_card:addLabel({
        x = 2,
        y = index + 1,
        width = "{parent.width - 3}",
        text = "",
      })
    end
    y = y + 6

    page.preset_card = addCard(scroll, {
      x = 1,
      y = y,
      width = "{parent.width - 1}",
      height = 3,
    }, "Starter Presets", palette.gold)
    do
      local presets = constants.PROFILE_PRESETS[itemType] or {}
      local count = math.max(1, #presets)
      local button_formula = string.format("math.max(8, math.floor((parent.width - %d) / %d))", count + 2, count)
      for index, preset in ipairs(presets) do
        local x_formula = "2"
        if index > 1 then
          x_formula = string.format("2 + (%d * ((%s) + 1))", index - 1, button_formula)
        end
        local button = page.preset_card:addButton({
          x = "{" .. x_formula .. "}",
          y = 2,
          width = "{" .. button_formula .. "}",
          height = 1,
          text = preset.label,
          background = index == 1 and palette.keep or palette.surface,
          foreground = index == 1 and palette.text_dark or palette.text,
        })
        button:onClick(function()
          controller.actions.applyPreset(itemType, preset.id)
        end)
        page.presets[preset.id] = button
      end
    end
    y = y + 4

    page.policy_card = addCard(scroll, {
      x = 1,
      y = y,
      width = "{parent.width - 1}",
      height = 5,
    }, "Core Policy", palette.accent_dark)

    page.switches.enabled = addSwitchRow(controller, page.policy_card, 2, "Profile Enabled", function(checked)
      controller.actions.setProfileFlag(itemType, "enabled", checked)
    end)

    page.choices.miss_action = addDropdownRow(controller, page.policy_card, 3, "Misses Go To", function(value)
      controller.actions.setProfileChoice(itemType, "miss_action", value)
    end)

    page.choices.unidentified_mode = addDropdownRow(controller, page.policy_card, 4, "Unidentified", function(value)
      controller.actions.setProfileChoice(itemType, "unidentified_mode", value)
    end)

    y = y + 6

    local numeric_fields = {}
    if itemType == "Gear" or itemType == "Tool" or itemType == "Jewel" or itemType == "Charm" or itemType == "Etching" then
      numeric_fields[#numeric_fields + 1] = "min_rarity"
    end
    if itemType == "Gear" or itemType == "Tool" or itemType == "Jewel" or itemType == "Etching" then
      numeric_fields[#numeric_fields + 1] = "min_level"
      numeric_fields[#numeric_fields + 1] = "max_level"
    end
    if itemType == "Gear" then
      numeric_fields[#numeric_fields + 1] = "min_crafting_potential"
    end
    if itemType == "Gear" or itemType == "Tool" then
      numeric_fields[#numeric_fields + 1] = "min_free_repair_slots"
      numeric_fields[#numeric_fields + 1] = "min_durability_percent"
    end
    if itemType == "Jewel" then
      numeric_fields[#numeric_fields + 1] = "max_jewel_size"
    end
    if itemType == "Trinket" or itemType == "Charm" then
      numeric_fields[#numeric_fields + 1] = "min_uses"
    end

    local threshold_height = 2 + #numeric_fields
    page.threshold_card = addCard(scroll, {
      x = 1,
      y = y,
      width = "{parent.width - 1}",
      height = threshold_height,
    }, "Thresholds", palette.warning)

    local row_y = 2
    for _, field in ipairs(numeric_fields) do
      if field == "min_rarity" then
        page.choices.min_rarity = addDropdownRow(controller, page.threshold_card, row_y, "Min Rarity", function(value)
          controller.actions.setProfileChoice(itemType, "min_rarity", value)
        end)
      else
        page.numbers[field] = addStepperRow(controller, page.threshold_card, row_y, numeric_labels[field], function()
          controller.actions.adjustProfileNumber(itemType, field, -1)
        end, function()
          controller.actions.adjustProfileNumber(itemType, field, 1)
        end)
      end
      row_y = row_y + 1
    end

    y = y + threshold_height + 1

    local safety_fields = {}
    if itemType == "Gear" or itemType == "Etching" then
      safety_fields[#safety_fields + 1] = {
        field = "keep_legendary",
        label = "Always Keep Legendary",
      }
    end
    if itemType == "Gear" then
      safety_fields[#safety_fields + 1] = {
        field = "keep_soulbound",
        label = "Always Keep Soulbound",
      }
      safety_fields[#safety_fields + 1] = {
        field = "keep_unique",
        label = "Always Keep Unique",
      }
    end

    page.safety_card = addCard(scroll, {
      x = 1,
      y = y,
      width = "{parent.width - 1}",
      height = math.max(3, 2 + #safety_fields),
    }, "Safety Overrides", palette.keep)

    if #safety_fields == 0 then
      page.safety_empty = page.safety_card:addLabel({
        x = 2,
        y = 2,
        width = "{parent.width - 3}",
        text = "No extra safety toggles for this type.",
        foreground = palette.muted,
      })
    else
      for index, field_info in ipairs(safety_fields) do
        page.switches[field_info.field] = addSwitchRow(controller, page.safety_card, index + 1, field_info.label, function(checked)
          controller.actions.setProfileFlag(itemType, field_info.field, checked)
        end)
      end
    end

    refs.rules[itemType] = page
  end
end

local function buildModifiersPage(controller, modifiers_tab)
  local refs = controller.refs
  refs.modifiers = {}

  refs.modifiers.types = modifiers_tab:addSideNav({
    x = 1,
    y = 1,
    width = "{parent.width}",
    height = "{parent.height}",
    sidebarBackground = palette.bg,
    activeTabBackground = palette.accent,
    activeTabTextColor = palette.text_dark,
    foreground = palette.muted,
    sidebarWidth = 10,
  })

  refs.modifiers.types:registerCallback("tabChanged", function(_, new_tab)
    if controller.suppress_events then
      return
    end
    controller.actions.selectType(constants.SUPPORTED_TYPES[new_tab])
  end)

  for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
    local type_tab = refs.modifiers.types:newTab(itemType)
    local page = {}

    page.catalog_card = addCard(type_tab, {
      name = itemType .. "ModifierCatalog",
      x = 1,
      y = 1,
      width = "{math.max(22, math.floor(parent.width * 0.52))}",
      height = "{parent.height}",
    }, "Discovered Modifiers", palette.accent)

    page.catalog_list = page.catalog_card:addList({
      x = 1,
      y = 2,
      width = "{parent.width}",
      height = "{parent.height - 1}",
      emptyText = "No modifiers discovered yet",
      showScrollBar = true,
    })
    page.catalog_list:onSelect(function(_, _, item)
      if controller.suppress_events then
        return
      end
      if item and item.key then
        controller.actions.selectCatalogModifier(item.key)
      end
    end)

    page.actions_card = addCard(type_tab, {
      name = itemType .. "ModifierActions",
      x = "{" .. itemType .. "ModifierCatalog.x + " .. itemType .. "ModifierCatalog.width + 1}",
      y = 1,
      width = "{parent.width - " .. itemType .. "ModifierCatalog.width - 1}",
      height = 4,
    }, "Rule Actions", palette.gold)

    page.mode_row = addDropdownRow(controller, page.actions_card, 2, "Wanted Match", function(value)
      controller.actions.setProfileChoice(itemType, "wanted_modifier_mode", value)
    end)

    page.keep_button = page.actions_card:addButton({
      x = 2,
      y = 3,
      width = "{math.max(10, math.floor((parent.width - 4) / 2))}",
      height = 1,
      text = "+ Keep",
      background = palette.keep,
      foreground = palette.text_dark,
    })
    page.keep_button:onClick(function()
      controller.actions.addRule("wanted_modifiers")
    end)

    page.block_button = page.actions_card:addButton({
      x = "{parent.width - math.max(10, math.floor((parent.width - 4) / 2))}",
      y = 3,
      width = "{math.max(10, math.floor((parent.width - 4) / 2))}",
      height = 1,
      text = "+ Block",
      background = palette.trash,
    })
    page.block_button:onClick(function()
      controller.actions.addRule("blocked_modifiers")
    end)

    page.keep_card = addCard(type_tab, {
      name = itemType .. "KeepRules",
      x = "{" .. itemType .. "ModifierCatalog.x + " .. itemType .. "ModifierCatalog.width + 1}",
      y = 6,
      width = "{parent.width - " .. itemType .. "ModifierCatalog.width - 1}",
      height = "{math.max(4, math.floor((parent.height - 5) / 2))}",
    }, "Keep Rules", palette.keep)

    page.keep_list = page.keep_card:addList({
      x = 1,
      y = 2,
      width = "{parent.width}",
      height = "{parent.height - 1}",
      emptyText = "No keep rules",
      showScrollBar = true,
    })
    page.keep_list:onSelect(function(_, _, item)
      if controller.suppress_events then
        return
      end
      if item and item.key then
        controller.actions.selectKeepRule(item.key)
      end
    end)

    page.keep_remove = page.keep_card:addButton({
      x = "{parent.width - 11}",
      y = 1,
      width = 11,
      height = 1,
      text = "Remove",
      background = palette.surface,
    })
    page.keep_remove:onClick(function()
      controller.actions.removeRule("wanted_modifiers")
    end)

    page.block_card = addCard(type_tab, {
      name = itemType .. "BlockRules",
      x = "{" .. itemType .. "ModifierCatalog.x + " .. itemType .. "ModifierCatalog.width + 1}",
      y = "{" .. itemType .. "KeepRules.y + " .. itemType .. "KeepRules.height + 1}",
      width = "{parent.width - " .. itemType .. "ModifierCatalog.width - 1}",
      height = "{math.max(4, parent.height - " .. itemType .. "KeepRules.height - 6)}",
    }, "Block Rules", palette.trash)

    page.block_list = page.block_card:addList({
      x = 1,
      y = 2,
      width = "{parent.width}",
      height = "{parent.height - 1}",
      emptyText = "No block rules",
      showScrollBar = true,
    })
    page.block_list:onSelect(function(_, _, item)
      if controller.suppress_events then
        return
      end
      if item and item.key then
        controller.actions.selectBlockRule(item.key)
      end
    end)

    page.block_remove = page.block_card:addButton({
      x = "{parent.width - 11}",
      y = 1,
      width = 11,
      height = 1,
      text = "Remove",
      background = palette.surface,
    })
    page.block_remove:onClick(function()
      controller.actions.removeRule("blocked_modifiers")
    end)

    page.clear_button = page.block_card:addButton({
      x = 2,
      y = 1,
      width = 10,
      height = 1,
      text = "Clear All",
      background = palette.warning,
      foreground = palette.text_dark,
    })
    page.clear_button:onClick(function()
      controller.actions.clearRules()
    end)

    refs.modifiers[itemType] = page
  end
end

local function buildSetupPage(controller, setup)
  local refs = controller.refs
  refs.setup = {}

  refs.setup.scroll = setup:addScrollFrame({
    x = 1,
    y = 1,
    width = "{parent.width}",
    height = "{parent.height}",
    background = palette.bg,
    showScrollBar = true,
  })

  refs.setup.flow_card = addCard(refs.setup.scroll, {
    x = 1,
    y = 1,
    width = "{parent.width - 1}",
    height = 7,
  }, "Input & Speed", palette.accent)

  refs.setup.input_row = addDropdownRow(controller, refs.setup.flow_card, 2, "Input Inventory", function(value)
    if value then
      controller.actions.setInputInventory(value)
    end
  end)

  refs.setup.scan_stepper = addStepperRow(controller, refs.setup.flow_card, 3, "Scan Interval (s)", function()
    controller.actions.adjustRuntime("scan_interval", -1)
  end, function()
    controller.actions.adjustRuntime("scan_interval", 1)
  end)

  refs.setup.batch_stepper = addStepperRow(controller, refs.setup.flow_card, 4, "Batch Size", function()
    controller.actions.adjustRuntime("batch_size", -1)
  end, function()
    controller.actions.adjustRuntime("batch_size", 1)
  end)

  refs.setup.refresh_button = refs.setup.flow_card:addButton({
    x = 2,
    y = 6,
    width = 18,
    height = 1,
    text = "Refresh Peripherals",
    background = palette.surface,
  })
  refs.setup.refresh_button:onClick(function()
    controller.actions.refreshPeripherals(true)
  end)

  refs.setup.route_card = addCard(refs.setup.scroll, {
    name = "setupRouteCard",
    x = 1,
    y = 9,
    width = "{parent.width - 1}",
    height = 8,
  }, "Destinations", palette.warning)

  refs.setup.route_add = refs.setup.route_card:addButton({
    x = 2,
    y = 1,
    width = 5,
    height = 1,
    text = "+",
    background = palette.keep,
    foreground = palette.text_dark,
  })
  refs.setup.route_add:onClick(function()
    controller.actions.addDestination()
  end)

  refs.setup.route_remove = refs.setup.route_card:addButton({
    x = 8,
    y = 1,
    width = 5,
    height = 1,
    text = "-",
    background = palette.trash,
  })
  refs.setup.route_remove:onClick(function()
    controller.actions.removeDestination()
  end)

  refs.setup.route_up = refs.setup.route_card:addButton({
    x = "{parent.width - 10}",
    y = 1,
    width = 4,
    height = 1,
    text = "Up",
    background = palette.surface,
  })
  refs.setup.route_up:onClick(function()
    controller.actions.moveDestination(-1)
  end)

  refs.setup.route_down = refs.setup.route_card:addButton({
    x = "{parent.width - 5}",
    y = 1,
    width = 5,
    height = 1,
    text = "Down",
    background = palette.surface,
  })
  refs.setup.route_down:onClick(function()
    controller.actions.moveDestination(1)
  end)

  refs.setup.route_list = refs.setup.route_card:addList({
    x = 1,
    y = 2,
    width = "{parent.width}",
    height = "{parent.height - 1}",
    emptyText = "No destinations yet",
    showScrollBar = true,
  })
  refs.setup.route_list:onSelect(function(_, _, item)
    if controller.suppress_events then
      return
    end
    if item and item.key then
      controller.actions.selectDestination(item.key)
    end
  end)

  refs.setup.editor_card = addCard(refs.setup.scroll, {
    x = 1,
    y = 18,
    width = "{parent.width - 1}",
    height = 17,
    name = "setupEditorCard",
  }, "Selected Route", palette.accent_dark)

  refs.setup.route_enabled = addSwitchRow(controller, refs.setup.editor_card, 2, "Route Enabled", function(checked)
    controller.actions.setDestinationEnabled(checked)
  end)

  refs.setup.route_inventory = addDropdownRow(controller, refs.setup.editor_card, 3, "Destination Inventory", function(value)
    if value ~= nil then
      controller.actions.setDestinationChoice("inventory", value)
    end
  end)

  refs.setup.route_action = addDropdownRow(controller, refs.setup.editor_card, 4, "Decision Match", function(value)
    controller.actions.setDestinationChoice("match_action", value)
  end)

  refs.setup.route_type_mode = addDropdownRow(controller, refs.setup.editor_card, 5, "Type Scope", function(value)
    controller.actions.setDestinationChoice("type_mode", value)
  end)

  refs.setup.type_title = refs.setup.editor_card:addLabel({
    x = 2,
    y = 6,
    width = "{parent.width - 3}",
    text = "Type Filters",
    foreground = palette.muted,
  })

  refs.setup.type_switches = {}
  local type_positions = {
    Gear = { x = 2, y = 7 },
    Tool = { x = 2, y = 8 },
    Jewel = { x = 2, y = 9 },
    Trinket = { x = "{math.max(16, math.floor(parent.width / 2))}", y = 7 },
    Charm = { x = "{math.max(16, math.floor(parent.width / 2))}", y = 8 },
    Etching = { x = "{math.max(16, math.floor(parent.width / 2))}", y = 9 },
  }

  for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
    local position = type_positions[itemType]
    refs.setup.type_switches[itemType] = refs.setup.editor_card:addSwitch({
      x = position.x,
      y = position.y,
      width = 12,
      height = 1,
      text = itemType,
    })
    refs.setup.type_switches[itemType]:onChange("checked", function(_, checked)
      if controller.suppress_events then
        return
      end
      controller.actions.setDestinationType(itemType, checked)
    end)
  end

  refs.setup.type_reset = refs.setup.editor_card:addButton({
    x = 2,
    y = 11,
    width = 14,
    height = 1,
    text = "All Types",
    background = palette.keep,
    foreground = palette.text_dark,
  })
  refs.setup.type_reset:onClick(function()
    controller.actions.clearDestinationTypes()
  end)

  refs.setup.route_lines = {}
  for index = 1, 5 do
    refs.setup.route_lines[index] = refs.setup.editor_card:addLabel({
      x = 2,
      y = index + 11,
      width = "{parent.width - 3}",
      text = "",
      foreground = index == 1 and palette.text or palette.muted,
    })
  end
end

local function buildPages(controller)
  local refs = controller.refs

  refs.pages = controller.frame:addTabControl({
    x = 1,
    y = 4,
    width = "{parent.width}",
    height = "{parent.height - 3}",
    headerBackground = palette.bg,
    activeTabBackground = palette.accent,
    activeTabTextColor = palette.text_dark,
    foreground = palette.muted,
  })

  refs.pages:registerCallback("tabChanged", function(_, new_tab)
    if controller.suppress_events then
      return
    end
    controller.actions.setPage(constants.TABS[new_tab].id)
  end)

  local dashboard = refs.pages:newTab("Dashboard")
  local rules = refs.pages:newTab("Rules")
  local modifiers = refs.pages:newTab("Modifiers")
  local setup = refs.pages:newTab("Setup")

  buildDashboard(controller, dashboard)
  buildRulesPage(controller, rules)
  buildModifiersPage(controller, modifiers)
  buildSetupPage(controller, setup)
end

local function buildTimers(controller)
  local refs = controller.refs

  refs.preview_timer = controller.frame:addTimer({
    interval = 2,
    running = true,
    action = function()
      controller.actions.onPreviewTimer()
    end,
  })
  refs.preview_timer:start()

  refs.sort_timer = controller.frame:addTimer({
    interval = controller.app.config.runtime.scan_interval,
    running = true,
    action = function()
      controller.actions.onSortTimer()
    end,
  })
  refs.sort_timer:start()

  refs.save_timer = controller.frame:addTimer({
    interval = 10,
    running = true,
    action = function()
      controller.actions.onSaveTimer()
    end,
  })
  refs.save_timer:start()
end

local function buildGlobalHandlers(controller)
  basalt.onEvent("peripheral", function()
    controller.actions.onPeripheralEvent("peripheral")
  end)

  basalt.onEvent("peripheral_detach", function()
    controller.actions.onPeripheralEvent("peripheral_detach")
  end)

  basalt.onEvent("terminate", function()
    controller.actions.onTerminate()
  end)
end

local function refreshHeader(controller)
  local app = controller.app
  local refs = controller.refs
  local running = app.config.runtime.enabled
  local status_text = running and " RUNNING " or " STOPPED "
  local status_bg = running and palette.keep or palette.trash
  local subtitle = nextStep(app)
  local subtitle_color = palette.muted
  local subtitle_width = math.max(10, controller.frame.get("width") - 27)

  if #app.health.errors > 0 then
    subtitle_color = palette.trash
  elseif #app.health.warnings > 0 then
    subtitle_color = palette.warning
  end

  refs.runtime_pill:setText(status_text)
  refs.runtime_pill:setBackground(status_bg)

  refs.run_button:setText(running and "Pause" or "Start")
  refs.run_button:setBackground(running and palette.trash or palette.keep)
  refs.run_button:setForeground(palette.text_dark)

  refs.subtitle:setForeground(subtitle_color)
  if controller.last_subtitle ~= subtitle or controller.last_subtitle_width ~= subtitle_width then
    refs.subtitle:stopAnimation()
    if #subtitle > subtitle_width then
      refs.subtitle:setText(util.trimText(subtitle, subtitle_width))
      refs.subtitle:animate():scrollText("text", subtitle, 0.25, "easeOutQuad"):start()
    else
      refs.subtitle:setText(subtitle)
    end
    controller.last_subtitle = subtitle
    controller.last_subtitle_width = subtitle_width
  end

  refs.notice:setVisible(not app.health.monitor_ok)
  refs.pages:setVisible(app.health.monitor_ok)

  if not app.health.monitor_ok then
    setWrappedLabelLines(refs.notice_lines, {
      app.health.monitor_error or "Monitor unavailable.",
      "This UI is designed for a monitor and will reattach automatically when one becomes available.",
      "Attach or resize a monitor, then tap Refresh Peripherals if needed.",
      "Minimum size: " .. constants.MIN_MONITOR_WIDTH .. "x" .. constants.MIN_MONITOR_HEIGHT .. " characters.",
    }, math.max(16, controller.frame.get("width") - 6))
  end
end

local function refreshDashboard(controller)
  local app = controller.app
  local refs = controller.refs.dashboard
  local preview = app.preview.items or {}
  local selected_index = util.clamp(app.ui.preview_selected or 1, 1, math.max(1, #preview))
  local selected_entry = preview[selected_index]
  local total_moves = app.session.kept + app.session.discarded
  local keep_ratio = total_moves > 0 and math.floor((app.session.kept / total_moves) * 100 + 0.5) or 0
  local show_recent = controller.refs.dashboard.recent_card.get("height") >= 4
  local flow_text = "Input: " .. findInventoryLabel(app, app.config.routing.input) .. " | " .. routeFlowSummary(app)
  local cycle_text = app.last_cycle_at
    and ("Last sort: " .. util.formatTime(app.last_cycle_at) .. " | Preview: " .. tostring(#preview))
    or ("Preview: " .. tostring(#preview) .. " | Waiting for first live sort")

  if #app.health.errors > 0 then
    refs.status_lines[1]:setText(app.health.errors[1])
    refs.status_lines[1]:setForeground(palette.trash)
  elseif #app.health.warnings > 0 then
    refs.status_lines[1]:setText(app.health.warnings[1])
    refs.status_lines[1]:setForeground(palette.warning)
  else
    refs.status_lines[1]:setText(string.format("Scanned %d | Keep %d | Trash %d | Errors %d", app.session.scanned, app.session.kept, app.session.discarded, app.session.errors))
    refs.status_lines[1]:setForeground(palette.text)
  end

  refs.status_lines[2]:setText(util.trimText(flow_text, math.max(12, refs.hero.get("width") - 3)))
  refs.status_lines[3]:setText(util.trimText(cycle_text, math.max(12, refs.hero.get("width") - 3)))
  refs.progress:setProgress(keep_ratio)
  refs.progress:setProgressColor(total_moves > 0 and palette.keep or palette.surface)

  refs.preview_list:clear()
  for index, entry in ipairs(preview) do
    local badge, badge_color = previewBadge(entry)
    refs.preview_list:addItem({
      text = string.format("[%s] %s", badge, tostring(entry.item.display_name or "?")),
      key = tostring(index),
      fg = badge_color,
      selected = index == selected_index,
      selectedBg = palette.accent,
      selectedFg = palette.text_dark,
    })
  end
  if #preview > 0 then
    refs.preview_list:scrollToItem(selected_index)
  end

  local detail_lines = selectedDecisionLines(app, selected_entry)
  refs.detail_list:clear()
  for index, line in ipairs(detail_lines) do
    local color = palette.text
    if index == 2 then
      color = (selected_entry and selected_entry.decision and selected_entry.decision.action == "discard") and palette.trash or palette.keep
    elseif index == 3 then
      color = palette.warning
    elseif index == 4 then
      color = palette.muted
    end

    refs.detail_list:addItem({
      text = line,
      fg = color,
    })
  end
  refs.detail_list:scrollToTop()
  refs.recent_card:setVisible(show_recent)

  refs.recent_list:clear()
  for _, entry in ipairs(app.recent or {}) do
    refs.recent_list:addItem({
      text = formatRecentEntry(entry),
      fg = chooseColor(entry.level),
    })
  end
  refs.recent_list:scrollToBottom()
end

local function refreshRules(controller)
  local app = controller.app
  controller.suppress_events = true
  controller.refs.rules.types:setActiveTab(typeIndex(app.ui.selected_type))
  controller.suppress_events = false

  for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
    local page = controller.refs.rules[itemType]
    local profile = app.config.type_profiles[itemType]
    local summary = summaryLinesForProfile(app, itemType)

    setLabelLines(page.summary, summary)
    page.summary[3]:setForeground(selectedTypeWarning(app, itemType) and palette.warning or palette.muted)

    page.switches.enabled:setChecked(profile.enabled == true)
    setDropdownItems(page.choices.miss_action.dropdown, choice_options.miss_action, profile.miss_action)
    setDropdownItems(page.choices.unidentified_mode.dropdown, choice_options.unidentified_mode, profile.unidentified_mode)

    if page.choices.min_rarity then
      setDropdownItems(page.choices.min_rarity.dropdown, choice_options.min_rarity, profile.min_rarity)
    end

    for field, row in pairs(page.numbers) do
      row.value:setText(friendlyProfileValue(profile, field))
    end

    if page.switches.keep_legendary then
      page.switches.keep_legendary:setChecked(profile.keep_legendary == true)
    end
    if page.switches.keep_soulbound then
      page.switches.keep_soulbound:setChecked(profile.keep_soulbound == true)
    end
    if page.switches.keep_unique then
      page.switches.keep_unique:setChecked(profile.keep_unique == true)
    end
  end
end

local function refreshModifiers(controller)
  local app = controller.app
  local itemType = app.ui.selected_type

  controller.suppress_events = true
  controller.refs.modifiers.types:setActiveTab(typeIndex(itemType))
  controller.suppress_events = false

  for _, supportedType in ipairs(constants.SUPPORTED_TYPES) do
    local page = controller.refs.modifiers[supportedType]
    local profile = app.config.type_profiles[supportedType]
    local catalog_entries = catalog.listForType(app.state.catalog, supportedType)

    setDropdownItems(page.mode_row.dropdown, choice_options.wanted_modifier_mode, profile.wanted_modifier_mode)

    page.catalog_list:clear()
    for _, entry in ipairs(catalog_entries) do
      page.catalog_list:addItem({
        text = entry.label,
        key = entry.key,
        selected = supportedType == itemType and app.ui.selected_modifier_key == entry.key,
      })
    end

    page.keep_list:clear()
    for _, entry in ipairs(profile.wanted_modifiers or {}) do
      page.keep_list:addItem({
        text = entry.label or entry.key,
        key = entry.key,
        selected = supportedType == itemType and app.ui.selected_keep_key == entry.key,
        fg = palette.keep,
      })
    end

    page.block_list:clear()
    for _, entry in ipairs(profile.blocked_modifiers or {}) do
      page.block_list:addItem({
        text = entry.label or entry.key,
        key = entry.key,
        selected = supportedType == itemType and app.ui.selected_block_key == entry.key,
        fg = palette.trash,
      })
    end
  end
end

local function refreshSetup(controller)
  local app = controller.app
  local refs = controller.refs.setup
  local destination, selected_index = selectedDestination(app)

  controller.suppress_events = true

  setDropdownItems(refs.input_row.dropdown, inventoryOptions(app, true), app.config.routing.input)

  refs.scan_stepper.value:setText(tostring(app.config.runtime.scan_interval) .. "s")
  refs.batch_stepper.value:setText(tostring(app.config.runtime.batch_size))

  refs.route_list:clear()
  for index, entry in ipairs(app.config.routing.destinations or {}) do
    local color = palette.keep
    if entry.enabled == false then
      color = palette.muted
    elseif entry.match_action == "discard" then
      color = palette.trash
    elseif entry.match_action == "any" then
      color = palette.warning
    end

    refs.route_list:addItem({
      text = util.trimText(destinationTitle(app, entry, index) .. " | " .. routing.typeSummary(entry), math.max(14, refs.route_card.get("width") - 2)),
      key = entry.id,
      fg = color,
      selected = app.ui.selected_destination_id == entry.id,
      selectedBg = palette.accent,
      selectedFg = palette.text_dark,
    })
  end
  if selected_index then
    refs.route_list:scrollToItem(selected_index)
  end

  if destination then
    refs.route_enabled:setChecked(destination.enabled ~= false)
    setDropdownItems(refs.route_inventory.dropdown, inventoryOptions(app, false, true), destination.inventory or "")
    setDropdownItems(refs.route_action.dropdown, choice_options.route_action, destination.match_action)
    setDropdownItems(refs.route_type_mode.dropdown, choice_options.route_type_mode, destination.type_mode)

    local type_lookup = {}
    for _, itemType in ipairs(destination.match_types or {}) do
      type_lookup[itemType] = true
    end
    for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
      refs.type_switches[itemType]:setChecked(type_lookup[itemType] == true)
    end

    local route_lines = {
      destinationTitle(app, destination, selected_index),
      "Priority: first matching route wins.",
      "Decision: " .. routing.actionSummary(destination) .. " | Types: " .. routing.typeSummary(destination),
      app.monitor and string.format("Monitor: %s | %dx%d @ %s", app.monitor.name, app.monitor.width, app.monitor.height, tostring(app.monitor.text_scale or "?")) or "Monitor: not available",
      (#app.health.errors > 0 and app.health.errors[1]) or (#app.health.warnings > 0 and app.health.warnings[1]) or "Route looks healthy.",
    }
    setWrappedLabelLines(refs.route_lines, route_lines, math.max(16, refs.editor_card.get("width") - 3))
    refs.route_lines[5]:setForeground(#app.health.errors > 0 and palette.trash or (#app.health.warnings > 0 and palette.warning or palette.muted))
  else
    refs.route_enabled:setChecked(false)
    setDropdownItems(refs.route_inventory.dropdown, inventoryOptions(app, false, true), "")
    setDropdownItems(refs.route_action.dropdown, choice_options.route_action, nil)
    setDropdownItems(refs.route_type_mode.dropdown, choice_options.route_type_mode, nil)
    for _, itemType in ipairs(constants.SUPPORTED_TYPES) do
      refs.type_switches[itemType]:setChecked(false)
    end
    setLabelLines(refs.route_lines, {
      "No destination selected.",
      "Add a destination or pick one from the list.",
      "Routes are checked top to bottom.",
      "",
      "",
    })
    refs.route_lines[5]:setForeground(palette.muted)
  end

  controller.suppress_events = false
end

local function refreshAll(controller)
  refreshHeader(controller)
  if controller.app.health.monitor_ok then
    controller.suppress_events = true
    controller.refs.pages:setActiveTab(pageIndex(controller.app.ui.page))
    controller.suppress_events = false
    refreshDashboard(controller)
    refreshRules(controller)
    refreshModifiers(controller)
    refreshSetup(controller)
  end
end

local function refreshLive(controller)
  refreshHeader(controller)
  if controller.app.health.monitor_ok then
    refreshDashboard(controller)
    refreshModifiers(controller)
    refreshSetup(controller)
  end
end

local function rebindTerm(controller)
  local target_term = term.current()
  if controller.app.monitor and controller.app.monitor.peripheral then
    target_term = controller.app.monitor.peripheral
  end

  controller.frame:setTerm(target_term)
  if controller.refs.sort_timer then
    controller.refs.sort_timer:setInterval(controller.app.config.runtime.scan_interval)
  end
end

local function notify(controller, level, title, message)
  if not controller.refs.toast then
    return
  end

  if level == "success" then
    controller.refs.toast:success(title, message, 2.5)
  elseif level == "warning" then
    controller.refs.toast:warning(title, message, 3)
  elseif level == "error" then
    controller.refs.toast:error(title, message, 4)
  else
    controller.refs.toast:info(title, message, 2.5)
  end
end

function M.create(app, actions)
  local theme_api = basalt.getAPI("theme")
  if theme_api and theme_api.setTheme then
    theme_api.setTheme(theme)
  end

  local controller = {
    app = app,
    actions = actions,
    refs = {},
    suppress_events = false,
    last_subtitle = nil,
    last_subtitle_width = nil,
  }

  controller.frame = basalt.createFrame()

  controller.rebindTerm = function(self)
    rebindTerm(self)
  end

  controller.refreshHeader = function(self)
    refreshHeader(self)
  end

  controller.refreshDashboard = function(self)
    refreshDashboard(self)
  end

  controller.refreshModifiers = function(self)
    refreshModifiers(self)
  end

  controller.refreshSetup = function(self)
    refreshSetup(self)
  end

  controller.refreshLive = function(self)
    refreshLive(self)
  end

  controller.refreshAll = function(self)
    refreshAll(self)
  end

  controller.notify = function(self, level, title, message)
    notify(self, level, title, message)
  end

  controller.run = function()
    basalt.run()
  end

  controller:rebindTerm()
  buildHeader(controller)
  buildNotice(controller)
  buildPages(controller)
  buildTimers(controller)
  buildGlobalHandlers(controller)
  controller:refreshAll()

  return controller
end

return M
