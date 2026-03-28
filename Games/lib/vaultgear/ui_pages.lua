local constants = require("lib.vaultgear.constants")
local quickSetup = require("lib.vaultgear.quick_setup")
local shared = require("lib.vaultgear.ui_shared")
local util = require("lib.vaultgear.util")

local M = {}

local layout = shared.layout
local widgets = shared.widgets

local function flattenLines(lines, width, maxLines)
  local flattened = {}
  local limit = maxLines or 999

  for _, line in ipairs(lines or {}) do
    local bits = util.wrapText(line, math.max(8, width), limit - #flattened)
    for _, bit in ipairs(bits) do
      flattened[#flattened + 1] = bit
      if #flattened >= limit then
        return flattened
      end
    end
  end

  return flattened
end

local function drawWrappedLines(ctx, rect, lines, primaryTone)
  local wrapped = flattenLines(lines, rect.w, rect.h)
  for index = 1, math.min(#wrapped, rect.h) do
    local tone = index == 1 and (primaryTone or "text") or "text"
    ctx:drawText(rect.x, rect.y + index - 1, ctx:trimText(wrapped[index], rect.w), tone, nil)
  end
end

local function addRow(rows, height, render)
  rows[#rows + 1] = {
    height = height or 1,
    render = render,
  }
end

local function addSpacer(rows, height)
  addRow(rows, height or 1, function() end)
end

local function addSection(rows, text)
  addRow(rows, 1, function(ctx, rect)
    shared.renderSectionLabel(ctx, rect, text)
  end)
end

local function changeDraftType(view, itemType)
  local current = quickSetup.normalizeConfig(view.draft_home or quickSetup.defaultConfig("Gear", 10))
  view.draft_home = quickSetup.defaultConfig(itemType, current.priority)
end

local function appendQuickHomeRows(rows, config, handlers)
  local rarityOptions = shared.rarityOptions()
  local identifiedOptions = shared.identifiedOptions()
  local itemTypeOptions = shared.quickTypeOptions()
  local normalized = quickSetup.normalizeConfig(config)

  addRow(rows, 1, function(ctx, rect)
    widgets.stepper(ctx, rect, "Priority", tostring(normalized.priority or 1), {
      onMinus = function()
        handlers.adjustPriority(-1)
      end,
      onPlus = function()
        handlers.adjustPriority(1)
      end,
    })
  end)

  addRow(rows, 1, function(ctx, rect)
    widgets.selector(ctx, rect, "Item Type", shared.optionLabel(itemTypeOptions, normalized.item_type, "Gear"), {
      onPrev = function()
        handlers.setType(shared.cycleItemType(normalized.item_type, -1))
      end,
      onNext = function()
        handlers.setType(shared.cycleItemType(normalized.item_type, 1))
      end,
    })
  end)

  for _, field in ipairs(shared.quickFieldsForType(normalized.item_type)) do
    local currentField = field
    if currentField.kind == "choice" and currentField.id == "min_rarity" then
      addRow(rows, 1, function(ctx, rect)
        widgets.selector(ctx, rect, currentField.label, shared.optionLabel(rarityOptions, normalized.min_rarity, "Any"), {
          onPrev = function()
            handlers.setChoice(currentField.id, shared.cycleOption(rarityOptions, normalized.min_rarity, -1))
          end,
          onNext = function()
            handlers.setChoice(currentField.id, shared.cycleOption(rarityOptions, normalized.min_rarity, 1))
          end,
        })
      end)
    elseif currentField.kind == "choice" and currentField.id == "identified_mode" then
      addRow(rows, 1, function(ctx, rect)
        widgets.selector(ctx, rect, currentField.label, shared.optionLabel(identifiedOptions, normalized.identified_mode, "Any"), {
          onPrev = function()
            handlers.setChoice(currentField.id, shared.cycleOption(identifiedOptions, normalized.identified_mode, -1))
          end,
          onNext = function()
            handlers.setChoice(currentField.id, shared.cycleOption(identifiedOptions, normalized.identified_mode, 1))
          end,
        })
      end)
    elseif currentField.kind == "stepper" and currentField.id == "min_uses" then
      addRow(rows, 1, function(ctx, rect)
        widgets.stepper(ctx, rect, currentField.label, tostring(normalized.min_uses or "Off"), {
          onMinus = function()
            handlers.adjustNumber(currentField.id, -1)
          end,
          onPlus = function()
            handlers.adjustNumber(currentField.id, 1)
          end,
        })
      end)
    elseif currentField.kind == "toggle" then
      addRow(rows, 1, function(ctx, rect)
        widgets.toggle(ctx, rect, currentField.label, normalized[currentField.id] == true, {
          onClick = function()
            handlers.setToggle(currentField.id, normalized[currentField.id] ~= true)
          end,
        })
      end)
    end
  end
end

local function buildDraftRows(app, actions, view)
  local rows = {}
  local role = view.draft_role or "home"
  local draftHome = quickSetup.normalizeConfig(view.draft_home or quickSetup.defaultConfig("Gear", 10))

  addSection(rows, "Quick Setup")
  addRow(rows, 1, function(ctx, rect)
    shared.renderSegmentRow(ctx, rect, "Role", shared.roleOptions(), role, function(value)
      view.draft_role = value
    end)
  end)

  if role == "home" then
    appendQuickHomeRows(rows, draftHome, {
      adjustPriority = function(delta)
        draftHome.priority = math.max(1, draftHome.priority + delta)
        view.draft_home = quickSetup.normalizeConfig(draftHome)
      end,
      setType = function(itemType)
        changeDraftType(view, itemType)
      end,
      setChoice = function(field, value)
        draftHome[field] = value
        view.draft_home = quickSetup.normalizeConfig(draftHome)
      end,
      adjustNumber = function(field, delta)
        local current = draftHome[field]
        if current == nil then
          if delta > 0 then
            draftHome[field] = 1
          end
        else
          local nextValue = current + delta
          if nextValue < 1 then
            draftHome[field] = nil
          else
            draftHome[field] = nextValue
          end
        end
        view.draft_home = quickSetup.normalizeConfig(draftHome)
      end,
      setToggle = function(field, value)
        draftHome[field] = value == true
        view.draft_home = quickSetup.normalizeConfig(draftHome)
      end,
    })

    addRow(rows, 2, function(ctx, rect)
      local lines = {
        "Lower number wins when multiple homes match.",
      }
      for _, line in ipairs(shared.quickSummaryLines(draftHome)) do
        lines[#lines + 1] = line
      end
      if app.suggestion then
        lines[#lines + 1] = "Suggestion: " .. tostring(app.suggestion.reason or "")
      end
      drawWrappedLines(ctx, rect, lines, "muted")
    end)

    addRow(rows, 1, function(ctx, rect)
      shared.renderButtonRow(ctx, rect, {
        {
          label = "Save Home",
          background = "success",
          foreground = "text_dark",
          onClick = function()
            actions.configureSelectedHomeQuick(view.draft_home)
          end,
        },
        app.suggestion and {
          label = "Use Suggest",
          background = "surface_alt",
          foreground = "text",
          onClick = function()
            local current = quickSetup.normalizeConfig(view.draft_home or draftHome)
            view.draft_home = shared.quickDraftFromSuggestion(app, current.priority)
          end,
        } or nil,
      })
    end)
  else
    addRow(rows, 2, function(ctx, rect)
      drawWrappedLines(ctx, rect, {
        "Inboxes are watch points for new items.",
        "Anything that lands here gets routed into the best matching home.",
      }, "muted")
    end)

    addRow(rows, 1, function(ctx, rect)
      shared.renderButtonRow(ctx, rect, {
        {
          label = "Save Inbox",
          background = "accent",
          foreground = "text_dark",
          onClick = actions.manageSelectedAsInbox,
        },
      })
    end)
  end

  return rows
end

local function buildInboxRows(app, actions)
  local rows = {}

  addSection(rows, "Basic")
  addRow(rows, 1, function(ctx, rect)
    shared.renderSegmentRow(ctx, rect, "Role", shared.roleOptions(), "inbox", actions.setSelectedRole)
  end)
  addRow(rows, 1, function(ctx, rect)
    local storage = shared.selectedStorage(app)
    widgets.toggle(ctx, rect, "Active", storage and storage.enabled ~= false, {
      onClick = function()
        local current = shared.selectedStorage(app)
        actions.setSelectedEnabled(current and current.enabled == false)
      end,
    })
  end)
  addRow(rows, 2, function(ctx, rect)
    drawWrappedLines(ctx, rect, {
      "This storage is watched for new work.",
      "It does not act as a long-term home during idle repair.",
    }, "muted")
  end)
  addRow(rows, 1, function(ctx, rect)
    shared.renderButtonRow(ctx, rect, {
      {
        label = "Run Cycle",
        background = "surface_alt",
        foreground = "text",
        onClick = actions.scanNow,
      },
      {
        label = "Stop Managing",
        background = "warning",
        foreground = "text_dark",
        onClick = actions.stopManagingSelected,
      },
    })
  end)

  return rows
end

local function buildHomeRows(app, actions)
  local rows = {}
  local storage = shared.selectedStorage(app)
  local rule = storage and storage.rule or nil
  local quickConfig = quickSetup.fromStorage(storage)

  addSection(rows, "Quick Setup")
  addRow(rows, 1, function(ctx, rect)
    shared.renderSegmentRow(ctx, rect, "Role", shared.roleOptions(), "home", actions.setSelectedRole)
  end)

  appendQuickHomeRows(rows, quickConfig, {
    adjustPriority = actions.adjustSelectedPriority,
    setType = actions.setSelectedQuickType,
    setChoice = actions.setSelectedRuleChoice,
    adjustNumber = actions.adjustSelectedRuleNumber,
    setToggle = actions.setSelectedFlag,
  })

  addRow(rows, 2, function(ctx, rect)
    local lines = {
      "Lower number wins when multiple homes match.",
    }
    for _, line in ipairs(shared.quickSummaryLines(quickConfig)) do
      lines[#lines + 1] = line
    end
    drawWrappedLines(ctx, rect, lines, "muted")
  end)

  addSpacer(rows, 1)
  addSection(rows, "Controls")
  addRow(rows, 1, function(ctx, rect)
    widgets.toggle(ctx, rect, "Active", storage.enabled ~= false, {
      onClick = function()
        actions.setSelectedEnabled(storage.enabled == false)
      end,
    })
  end)
  addRow(rows, 1, function(ctx, rect)
    widgets.toggle(ctx, rect, "Idle Repair", storage.rescan ~= false, {
      onClick = function()
        actions.setSelectedRescan(storage.rescan == false)
      end,
    })
  end)
  addRow(rows, 1, function(ctx, rect)
    shared.renderButtonRow(ctx, rect, {
      {
        label = app.ui.advanced and "Basic View" or "Advanced",
        background = "surface_alt",
        foreground = "text",
        onClick = actions.toggleAdvanced,
      },
      {
        label = "Run Cycle",
        background = "surface_alt",
        foreground = "text",
        onClick = actions.scanNow,
      },
      {
        label = "Stop",
        background = "warning",
        foreground = "text_dark",
        onClick = actions.stopManagingSelected,
      },
    })
  end)

  if not app.ui.advanced then
    addRow(rows, 2, function(ctx, rect)
      drawWrappedLines(ctx, rect, {
        "Advanced view is for deeper filters like durability, free repairs, or extra thresholds.",
        "Quick setup stays focused on the highest-signal decisions only.",
      }, "muted")
    end)
    return rows
  end

  addSpacer(rows, 1)
  addSection(rows, "Match Types")
  addRow(rows, 3, function(ctx, rect)
    shared.renderItemTypeMatrix(ctx, rect, rule.item_types, actions.toggleSelectedType)
  end)

  addSpacer(rows, 1)
  addSection(rows, "Match Rules")
  addRow(rows, 1, function(ctx, rect)
    shared.renderSegmentRow(ctx, rect, "Identified", identifiedOptions, rule.identified_mode, function(value)
      actions.setSelectedRuleChoice("identified_mode", value)
    end)
  end)

  if shared.ruleSupportsField(rule, "min_rarity") then
    addRow(rows, 1, function(ctx, rect)
      widgets.selector(ctx, rect, "Min Rarity", shared.optionLabel(rarityOptions, rule.min_rarity, "Any"), {
        onPrev = function()
          actions.setSelectedRuleChoice("min_rarity", shared.cycleOption(rarityOptions, rule.min_rarity, -1))
        end,
        onNext = function()
          actions.setSelectedRuleChoice("min_rarity", shared.cycleOption(rarityOptions, rule.min_rarity, 1))
        end,
      })
    end)
  end

  for _, field in ipairs(constants.NUMERIC_FIELD_ORDER) do
    local currentField = field
    if shared.ruleSupportsField(rule, currentField) then
      addRow(rows, 1, function(ctx, rect)
        widgets.stepper(ctx, rect, constants.NUMERIC_FIELDS[currentField].label, shared.formatRuleValue(rule, currentField), {
          onMinus = function()
            actions.adjustSelectedRuleNumber(currentField, -1)
          end,
          onPlus = function()
            actions.adjustSelectedRuleNumber(currentField, 1)
          end,
        })
      end)
    end
  end

  addSpacer(rows, 1)
  addSection(rows, "Special Cases")
  addRow(rows, 1, function(ctx, rect)
    widgets.toggle(ctx, rect, "Legendary Override", rule.allow_legendary == true, {
      onClick = function()
        actions.setSelectedFlag("allow_legendary", rule.allow_legendary ~= true)
      end,
    })
  end)
  addRow(rows, 1, function(ctx, rect)
    widgets.toggle(ctx, rect, "Soulbound Override", rule.allow_soulbound == true, {
      onClick = function()
        actions.setSelectedFlag("allow_soulbound", rule.allow_soulbound ~= true)
      end,
    })
  end)
  addRow(rows, 1, function(ctx, rect)
    widgets.toggle(ctx, rect, "Unique Override", rule.allow_unique == true, {
      onClick = function()
        actions.setSelectedFlag("allow_unique", rule.allow_unique ~= true)
      end,
    })
  end)

  return rows
end

local function buildStorageRows(app, actions, view)
  local storage = shared.selectedStorage(app)
  if not storage then
    return buildDraftRows(app, actions, view)
  end
  if storage.role == "inbox" then
    return buildInboxRows(app, actions)
  end
  return buildHomeRows(app, actions)
end

local function renderHeader(ctx, rect, app, actions)
  local accent = shared.accentForApp(app)
  local counts = shared.storageCounts(app)
  local inner = widgets.card(ctx, rect, {
    title = constants.APP_NAME,
    accent = accent,
    actions = {
      {
        label = "Refresh",
        background = "surface_alt",
        foreground = "text",
        onClick = actions.refreshPeripherals,
      },
      {
        label = "Scan",
        background = "surface_alt",
        foreground = "text",
        onClick = actions.scanNow,
      },
      {
        label = app.config.runtime.enabled and "Pause" or "Start",
        background = app.config.runtime.enabled and "warning" or "success",
        foreground = "text_dark",
        onClick = actions.toggleRuntime,
      },
    },
  })

  if inner.w <= 0 or inner.h <= 0 then
    return
  end

  local row1, rest = layout.sliceTop(inner, 1, 0)
  local row2, row3 = layout.sliceTop(rest, 1, 0)
  local runtimeRect, remainder = layout.sliceLeft(row1, 10, 1)
  local healthRect, infoRect = layout.sliceLeft(remainder, 12, 1)

  widgets.pill(ctx, runtimeRect, app.config.runtime.enabled and "LIVE" or "PAUSED", {
    background = app.config.runtime.enabled and "success" or "warning",
    foreground = "text_dark",
  })
  widgets.pill(ctx, healthRect, shared.healthLabel(app), {
    background = accent,
    foreground = "text_dark",
  })
  ctx:drawText(infoRect.x, infoRect.y, ctx:trimText(tostring(app.state.runtime.last_summary or "Idle"), infoRect.w), "text", nil)

  if row2.h > 0 then
    local metricRects = layout.columns(row2, { 0.25, 0.25, 0.25, 0.25 }, 1)
    widgets.pill(ctx, metricRects[1], "Connected " .. tostring(counts.connected), {
      background = "surface_alt",
      foreground = "text",
    })
    widgets.pill(ctx, metricRects[2], "Managed " .. tostring(counts.managed), {
      background = "surface_alt",
      foreground = "text",
    })
    widgets.pill(ctx, metricRects[3], "Inboxes " .. tostring(counts.inboxes), {
      background = "accent",
      foreground = "text_dark",
    })
    widgets.pill(ctx, metricRects[4], "Homes " .. tostring(counts.homes), {
      background = "gold",
      foreground = "text_dark",
    })
  end

  if row3.h > 0 then
    ctx:drawText(row3.x, row3.y, ctx:trimText(shared.nextStep(app), row3.w), accent == "danger" and "danger" or "muted", nil)
  end
end

local function renderOverview(ctx, rect, app, actions, view)
  local storageItems = shared.managedStorageItems(app)
  if rect.w >= 92 and rect.h >= 10 then
    local columns = layout.columns(rect, { 0.31, 0.34, 0.35 }, 1)
    local leftTop, leftBottom = layout.sliceTop(columns[1], 5, 1)
    local rightTop, rightBottom = layout.sliceTop(columns[3], math.max(4, math.floor(columns[3].h * 0.4)), 1)

    shared.renderWrappedTextCard(ctx, leftTop, "System", shared.liveSummaryLines(app), 0, nil, {
      accent = shared.accentForApp(app),
      actions = {
        {
          label = "Storages",
          background = "surface_alt",
          foreground = "text",
          onClick = function()
            actions.setPage("storages")
          end,
        },
      },
    })

    shared.renderWrappedTextCard(ctx, leftBottom, "Selected Storage", shared.selectionSummaryLines(app), 0, nil, {
      accent = "accent_alt",
      actions = {
        {
          label = "Open",
          background = "surface_alt",
          foreground = "text",
          onClick = function()
            actions.setPage("storages")
          end,
        },
      },
    })

    local _, storageScroll = shared.renderListCard(ctx, columns[2], {
      title = "Managed Storages",
      accent = "gold",
      items = storageItems,
      selected_id = shared.selectedStorage(app) and shared.selectedStorage(app).id or nil,
      scroll = view.storage_scroll,
      onScrollChange = function(value)
        view.storage_scroll = value
      end,
      onSelect = function(id)
        for _, storage in ipairs(app.config.storages or {}) do
          if storage.id == id then
            actions.selectInventory(storage.inventory)
            actions.setPage("storages")
            break
          end
        end
      end,
      empty_text = "No managed storages yet",
    })
    view.storage_scroll = storageScroll

    local _, healthScroll = shared.renderListCard(ctx, rightTop, {
      title = "Health",
      accent = shared.accentForApp(app),
      items = shared.healthItems(app),
      scroll = view.health_scroll,
      onScrollChange = function(value)
        view.health_scroll = value
      end,
      empty_text = "All checks passed",
    })
    view.health_scroll = healthScroll

    local _, recentScroll = shared.renderListCard(ctx, rightBottom, {
      title = "Recent Activity",
      accent = "accent_alt",
      items = shared.recentItems(app),
      scroll = view.recent_scroll,
      onScrollChange = function(value)
        view.recent_scroll = value
      end,
      empty_text = "Waiting for activity",
    })
    view.recent_scroll = recentScroll
    return
  end

  local topRect, remainder = layout.sliceTop(rect, 5, 1)
  local midRect, bottomRect = layout.sliceTop(remainder, math.max(4, math.floor(remainder.h * 0.45)), 1)

  shared.renderWrappedTextCard(ctx, topRect, "System", shared.liveSummaryLines(app), 0, nil, {
    accent = shared.accentForApp(app),
  })

  local _, storageScroll = shared.renderListCard(ctx, midRect, {
    title = "Managed Storages",
    accent = "gold",
    items = storageItems,
    selected_id = shared.selectedStorage(app) and shared.selectedStorage(app).id or nil,
    scroll = view.storage_scroll,
    onScrollChange = function(value)
      view.storage_scroll = value
    end,
    onSelect = function(id)
      for _, storage in ipairs(app.config.storages or {}) do
        if storage.id == id then
          actions.selectInventory(storage.inventory)
          actions.setPage("storages")
          break
        end
      end
    end,
    empty_text = "No managed storages yet",
  })
  view.storage_scroll = storageScroll

  local _, recentScroll = shared.renderListCard(ctx, bottomRect, {
    title = "Recent Activity",
    accent = "accent_alt",
    items = shared.recentItems(app),
    scroll = view.recent_scroll,
    onScrollChange = function(value)
      view.recent_scroll = value
    end,
    empty_text = "Waiting for activity",
  })
  view.recent_scroll = recentScroll
end

local function renderStorages(ctx, rect, app, actions, view)
  local inventoryItems = shared.inventoryItems(app)
  local sampleItems = shared.sampleItems(app)
  local selectedStorage = shared.selectedStorage(app)
  local summaryLines = shared.selectionSummaryLines(app)
  local rows = buildStorageRows(app, actions, view)
  local selectedEntry = shared.selectedSample(app, view)

  view.sample_scroll = shared.ensureVisible(view.sample_scroll, view.sample_selected, math.max(1, rect.h - 4), #sampleItems)

  if rect.w >= 92 and rect.h >= 11 then
    local listRect, rightRect = layout.sliceLeft(rect, math.max(22, math.floor(rect.w * 0.31)), 1)
    local summaryRect, lowerRect = layout.sliceTop(rightRect, 5, 1)
    local sampleRect, formRect = layout.sliceLeft(lowerRect, math.max(20, math.floor(lowerRect.w * 0.38)), 1)

    local _, inventoryScroll = shared.renderListCard(ctx, listRect, {
      title = "Connected Inventories",
      accent = "accent",
      items = inventoryItems,
      selected_id = app.ui.selected_inventory,
      scroll = view.inventory_scroll,
      onScrollChange = function(value)
        view.inventory_scroll = value
      end,
      onSelect = actions.selectInventory,
      empty_text = "No inventories detected",
    })
    view.inventory_scroll = inventoryScroll

    shared.renderWrappedTextCard(ctx, summaryRect, shared.selectedInventoryLabel(app), summaryLines, 0, nil, {
      accent = selectedStorage and (selectedStorage.role == "home" and "gold" or "accent") or "accent_alt",
      actions = {
        {
          label = "Live",
          background = "surface_alt",
          foreground = "text",
          onClick = function()
            actions.setPage("live")
          end,
        },
      },
    })

    local _, sampleScroll = shared.renderListCard(ctx, sampleRect, {
      title = "Sample",
      accent = "accent_alt",
      items = sampleItems,
      selected_id = view.sample_selected,
      scroll = view.sample_scroll,
      onScrollChange = function(value)
        view.sample_scroll = value
      end,
      onSelect = function(id)
        view.sample_selected = id
        view.detail_scroll = 0
      end,
      empty_text = "This storage is empty or unreadable",
    })
    view.sample_scroll = sampleScroll

    local cardInner = widgets.card(ctx, formRect, {
      title = selectedStorage and (shared.roleLabel(selectedStorage.role) .. " Settings") or "Setup",
      accent = selectedStorage and (selectedStorage.role == "home" and "gold" or "accent") or "accent",
    })
    if cardInner.w > 0 and cardInner.h > 0 then
      local maxScroll, currentScroll = shared.renderFormRows(ctx, cardInner, rows, view.form_scroll, function(value)
        view.form_scroll = value
      end)
      view.form_scroll = util.clamp(currentScroll, 0, maxScroll)
    end
    return
  end

  local listRect, remainder = layout.sliceTop(rect, math.max(5, math.floor(rect.h * 0.32)), 1)
  local summaryRect, formRect = layout.sliceTop(remainder, 5, 1)

  local _, inventoryScroll = shared.renderListCard(ctx, listRect, {
    title = "Connected Inventories",
    accent = "accent",
    items = inventoryItems,
    selected_id = app.ui.selected_inventory,
    scroll = view.inventory_scroll,
    onScrollChange = function(value)
      view.inventory_scroll = value
    end,
    onSelect = actions.selectInventory,
    empty_text = "No inventories detected",
  })
  view.inventory_scroll = inventoryScroll

  shared.renderWrappedTextCard(ctx, summaryRect, shared.selectedInventoryLabel(app), summaryLines, 0, nil, {
    accent = selectedStorage and (selectedStorage.role == "home" and "gold" or "accent") or "accent_alt",
  })

  local cardInner = widgets.card(ctx, formRect, {
    title = selectedStorage and (shared.roleLabel(selectedStorage.role) .. " Settings") or "Setup",
    accent = selectedStorage and (selectedStorage.role == "home" and "gold" or "accent") or "accent",
  })
  if cardInner.w > 0 and cardInner.h > 0 then
    local maxScroll, currentScroll = shared.renderFormRows(ctx, cardInner, rows, view.form_scroll, function(value)
      view.form_scroll = value
    end)
    view.form_scroll = util.clamp(currentScroll, 0, maxScroll)
  end
end

local function renderLive(ctx, rect, app, actions, view)
  local sampleItems = shared.sampleItems(app)
  local selectedEntry = shared.selectedSample(app, view)
  local detailLines = shared.sampleDecisionLines(app, selectedEntry)

  view.sample_scroll = shared.ensureVisible(view.sample_scroll, view.sample_selected, math.max(1, rect.h - 4), #sampleItems)

  if rect.w >= 88 and rect.h >= 10 then
    local leftRect, rightRect = layout.sliceLeft(rect, math.max(24, math.floor(rect.w * 0.36)), 1)
    local leftTop, leftBottom = layout.sliceTop(leftRect, 5, 1)
    local rightTop, rightBottom = layout.sliceTop(rightRect, math.max(4, math.floor(rightRect.h * 0.48)), 1)

    shared.renderWrappedTextCard(ctx, leftTop, "Live Summary", shared.liveSummaryLines(app), 0, nil, {
      accent = shared.accentForApp(app),
      actions = {
        {
          label = "Scan",
          background = "surface_alt",
          foreground = "text",
          onClick = actions.scanNow,
        },
      },
    })

    local _, sampleScroll = shared.renderListCard(ctx, leftBottom, {
      title = "Selected Storage Sample",
      accent = "accent_alt",
      items = sampleItems,
      selected_id = view.sample_selected,
      scroll = view.sample_scroll,
      onScrollChange = function(value)
        view.sample_scroll = value
      end,
      onSelect = function(id)
        view.sample_selected = id
        view.detail_scroll = 0
      end,
      empty_text = "No sampled items available",
    })
    view.sample_scroll = sampleScroll

    local _, recentScroll = shared.renderListCard(ctx, rightTop, {
      title = "Recent Activity",
      accent = "accent",
      items = shared.recentItems(app),
      scroll = view.recent_scroll,
      onScrollChange = function(value)
        view.recent_scroll = value
      end,
      empty_text = "Waiting for activity",
    })
    view.recent_scroll = recentScroll

    local _, detailScroll = shared.renderWrappedTextCard(ctx, rightBottom, "Selected Item", detailLines, view.detail_scroll, function(value)
      view.detail_scroll = value
    end, {
      accent = "gold",
      actions = {
        {
          label = "Storages",
          background = "surface_alt",
          foreground = "text",
          onClick = function()
            actions.setPage("storages")
          end,
        },
      },
    })
    view.detail_scroll = detailScroll
    return
  end

  local topRect, remainder = layout.sliceTop(rect, 5, 1)
  local midRect, bottomRect = layout.sliceTop(remainder, math.max(4, math.floor(remainder.h * 0.42)), 1)

  shared.renderWrappedTextCard(ctx, topRect, "Live Summary", shared.liveSummaryLines(app), 0, nil, {
    accent = shared.accentForApp(app),
  })

  local _, recentScroll = shared.renderListCard(ctx, midRect, {
    title = "Recent Activity",
    accent = "accent",
    items = shared.recentItems(app),
    scroll = view.recent_scroll,
    onScrollChange = function(value)
      view.recent_scroll = value
    end,
    empty_text = "Waiting for activity",
  })
  view.recent_scroll = recentScroll

  local _, detailScroll = shared.renderWrappedTextCard(ctx, bottomRect, "Selected Item", detailLines, view.detail_scroll, function(value)
    view.detail_scroll = value
  end, {
    accent = "gold",
  })
  view.detail_scroll = detailScroll
end

function M.renderApp(ctx, app, actions, view)
  shared.syncDraft(view, app)

  local root = layout.rect(1, 1, ctx.width, ctx.height)
  ctx:fillRect(root, "bg", "text", " ")

  local headerRect, remainder = layout.sliceTop(root, 5, 1)
  local tabsRect, bodyRect = layout.sliceTop(remainder, 1, 1)

  renderHeader(ctx, headerRect, app, actions)
  widgets.nav(ctx, tabsRect, constants.TABS, app.ui.page, {
    onSelect = actions.setPage,
  })

  if bodyRect.w <= 0 or bodyRect.h <= 0 then
    return
  end

  if app.ui.page == "storages" then
    renderStorages(ctx, bodyRect, app, actions, view)
  elseif app.ui.page == "live" then
    renderLive(ctx, bodyRect, app, actions, view)
  else
    renderOverview(ctx, bodyRect, app, actions, view)
  end
end

return M
