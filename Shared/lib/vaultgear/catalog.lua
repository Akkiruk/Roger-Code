local util = require("lib.vaultgear.util")

local M = {}

local function ensureTypeCatalog(catalog, itemType)
  if not catalog[itemType] then
    catalog[itemType] = {}
  end
  return catalog[itemType]
end

function M.observe(catalog, item)
  if not item or not item.supported_type then
    return false
  end

  local typeCatalog = ensureTypeCatalog(catalog, item.item_type)
  local changed = false

  for _, modifier in ipairs(item.modifiers.all) do
    local existing = typeCatalog[modifier.key]
    if not existing then
      existing = {
        key = modifier.key,
        label = modifier.label,
        item_type = item.item_type,
        affix_types = {},
        seen = 0,
        last_seen = 0,
      }
      typeCatalog[modifier.key] = existing
      changed = true
    end

    existing.label = modifier.label
    existing.affix_types[modifier.affix_type] = true
    existing.seen = (existing.seen or 0) + 1
    existing.last_seen = os.epoch("local")
  end

  return changed
end

function M.listForType(catalog, itemType)
  local entries = {}
  for _, key in ipairs(util.sortedKeys(catalog[itemType] or {})) do
    entries[#entries + 1] = catalog[itemType][key]
  end

  table.sort(entries, function(a, b)
    if a.label == b.label then
      return a.key < b.key
    end
    return a.label < b.label
  end)

  return entries
end

return M
