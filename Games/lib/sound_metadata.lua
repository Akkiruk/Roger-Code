local catalog = require("lib.sound_catalog")
local roles = require("lib.sound_roles")

local M = {}

local metadata_by_id = nil

local intensity_rank = {
  low = 1,
  medium = 2,
  medium_high = 3,
  high = 4,
}

local repetition_rank = {
  low = 1,
  medium = 2,
  high = 3,
}

local namespace_rules = {
  the_vault = { tags = { "vault", "high_stakes", "fantasy" }, notes = { "Vault namespace suggests dramatic or high-stakes styling." } },
  lightmanscurrency = { tags = { "currency", "casino" }, notes = { "Currency namespace suggests betting or reward utility." } },
  buildinggadgets = { tags = { "mechanical", "industrial", "ui_candidate" }, notes = { "Gadget namespace suggests machine-like utility sounds." } },
  create = { tags = { "mechanical", "industrial" }, notes = { "Create sounds often read as mechanical or clockwork." } },
  mekanism = { tags = { "mechanical", "industrial" }, notes = { "Mekanism sounds tend to be machine-oriented." } },
  mekanismgenerators = { tags = { "mechanical", "industrial" }, notes = { "Generator namespace suggests heavy machine cues." } },
  thermal = { tags = { "mechanical", "industrial" }, notes = { "Thermal sounds often fit machine interactions." } },
  modularrouters = { tags = { "mechanical", "industrial" }, notes = { "Router namespace suggests automation or utility cues." } },
  mininggadgets = { tags = { "mechanical", "industrial" }, notes = { "Mining gadget sounds often feel tool-like." } },
  computercraft = { tags = { "computer", "ui_candidate" }, notes = { "ComputerCraft sounds are likely suitable for utility roles." } },
  quark = { tags = { "utility" }, notes = { "Quark often supplies concise utility sounds." } },
  botania = { tags = { "magical", "fantasy" }, notes = { "Botania sounds often lean magical or mystical." } },
  patchouli = { tags = { "magical", "fantasy" }, notes = { "Patchouli sounds usually read as magical UI or book cues." } },
  alexsmobs = { tags = { "creature" }, notes = { "Alex's Mobs sounds are creature-oriented and often poor UI fits." } },
  ecologics = { tags = { "creature", "ambient" }, notes = { "Ecologics sounds tend toward environment or creature ambience." } },
  waddles = { tags = { "creature" }, notes = { "Waddles sounds are creature-oriented." } },
}

local keyword_rules = {
  { keywords = { "coin", "coins", "cash", "currency", "token", "chip" }, tags = { "casino", "currency", "percussive", "short", "repetition_safe" }, notes = { "Currency words suggest betting or chip-style interactions." }, intensity = "low", repetition = "low" },
  { keywords = { "click", "tick", "clock", "beep", "ping", "place", "switch", "button", "lever", "toggle" }, tags = { "ui_candidate", "percussive", "short", "repetition_safe", "mechanical" }, notes = { "Click or tick words suggest tight repeatable UI timing." }, intensity = "low", repetition = "low" },
  { keywords = { "open", "close", "start", "begin", "launch", "ignite", "activate", "boot" }, tags = { "transition", "start_cue" }, notes = { "Open or start words suggest transitions or program starts." }, intensity = "medium", repetition = "medium" },
  { keywords = { "success", "complete", "completion", "major", "reward", "unlock", "levelup", "win", "clear" }, tags = { "success", "reward", "celebration", "dramatic" }, notes = { "Success words suggest payout or reward cues." }, intensity = "high", repetition = "medium" },
  { keywords = { "fail", "error", "hurt", "death", "die", "trap", "loss", "robot_death" }, tags = { "failure", "danger", "hostile", "alert" }, notes = { "Failure words suggest negative or warning feedback." }, intensity = "medium_high", repetition = "medium" },
  { keywords = { "idle", "ambient", "hum", "loop", "walk", "flap" }, tags = { "ambient", "long_form" }, notes = { "Ambient words suggest background or creature loops." }, intensity = "low", repetition = "high" },
  { keywords = { "music", "song", "record", "box" }, tags = { "music", "long_form" }, notes = { "Music-like sounds are usually poor fits for repeated UI cues." }, intensity = "medium", repetition = "high" },
  { keywords = { "attack", "explode", "blast", "roar", "scream", "trumpet", "boom" }, tags = { "aggressive", "impact", "high_stakes", "rare_event" }, notes = { "Aggressive words suggest rare dramatic moments instead of spammed inputs." }, intensity = "high", repetition = "high" },
  { keywords = { "gate", "portal", "vault", "raid", "artifact", "puzzle" }, tags = { "vault", "dramatic", "high_stakes", "transition" }, notes = { "Vault or gate words suggest dramatic start or alert moments." }, intensity = "medium_high", repetition = "medium" },
  { keywords = { "card", "deal", "shuffle" }, tags = { "casino", "card", "percussive", "short" }, notes = { "Card words suggest direct casino table interaction." }, intensity = "low", repetition = "low" },
  { keywords = { "toast", "ui", "menu" }, tags = { "ui_candidate", "notification", "short" }, notes = { "UI naming suggests interface or toast usage." }, intensity = "low", repetition = "low" },
  { keywords = { "alarm", "warning", "alert", "notify" }, tags = { "alert", "danger" }, notes = { "Alert words suggest warning or timeout roles." }, intensity = "medium_high", repetition = "medium" },
}

local function trimToken(token)
  local value = tostring(token or ""):lower()
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  return value
end

local function addUnique(list, set, value)
  local normalized = trimToken(value)
  if normalized == "" or set[normalized] then
    return
  end

  set[normalized] = true
  list[#list + 1] = normalized
end

local function splitTokens(soundId)
  local namespace, name = string.match(soundId, "^([^:]+):(.+)$")
  local tokens = {}
  local seen = {}
  local part = nil

  for piece in string.gmatch((namespace or "") .. "_" .. (name or ""), "[%w]+") do
    local lower = trimToken(piece)
    if lower ~= "" then
      addUnique(tokens, seen, lower)
      for part in string.gmatch(lower, "[^%._%-]+") do
        addUnique(tokens, seen, part)
      end
      for part in string.gmatch(lower, "[^_]+") do
        addUnique(tokens, seen, part)
      end
    end
  end

  return namespace or "", name or soundId, tokens, seen
end

local function setMaxIntensity(meta, value)
  if intensity_rank[value] and intensity_rank[value] > intensity_rank[meta.intensity] then
    meta.intensity = value
  end
end

local function setMaxRepetition(meta, value)
  if repetition_rank[value] and repetition_rank[value] > repetition_rank[meta.repetition_risk] then
    meta.repetition_risk = value
  end
end

local function addTag(meta, value)
  addUnique(meta.auto_tags, meta.auto_tag_set, value)
end

local function addNote(meta, value)
  addUnique(meta.ai_notes, meta.ai_note_set, value)
end

local function hasAnyToken(tokenSet, keywords)
  for _, keyword in ipairs(keywords or {}) do
    if tokenSet[trimToken(keyword)] then
      return true
    end
  end
  return false
end

local function inferMetadata(soundId)
  local namespace = nil
  local name = nil
  local tokens = nil
  local tokenSet = nil
  local meta = nil
  local nsRule = nil
  local matchedRules = 0

  namespace, name, tokens, tokenSet = splitTokens(soundId)
  meta = {
    sound_id = soundId,
    namespace = namespace,
    name = name,
    tokens = tokens,
    auto_tags = {},
    auto_tag_set = {},
    ai_notes = {},
    ai_note_set = {},
    role_candidates = {},
    role_scores = {},
    intensity = "medium",
    repetition_risk = "medium",
    ai_confidence = 0.25,
  }

  nsRule = namespace_rules[namespace]
  if nsRule then
    for _, tag in ipairs(nsRule.tags or {}) do
      addTag(meta, tag)
    end
    for _, note in ipairs(nsRule.notes or {}) do
      addNote(meta, note)
    end
    matchedRules = matchedRules + 1
  end

  for _, rule in ipairs(keyword_rules) do
    if hasAnyToken(tokenSet, rule.keywords) then
      matchedRules = matchedRules + 1
      for _, tag in ipairs(rule.tags or {}) do
        addTag(meta, tag)
      end
      for _, note in ipairs(rule.notes or {}) do
        addNote(meta, note)
      end
      if rule.intensity then
        setMaxIntensity(meta, rule.intensity)
      end
      if rule.repetition then
        setMaxRepetition(meta, rule.repetition)
      end
    end
  end

  if meta.intensity == "low" then
    addTag(meta, "low_intensity")
  elseif meta.intensity == "medium" then
    addTag(meta, "medium_intensity")
  elseif meta.intensity == "medium_high" then
    addTag(meta, "medium_high_intensity")
    addTag(meta, "high_intensity")
  elseif meta.intensity == "high" then
    addTag(meta, "high_intensity")
  end

  if meta.repetition_risk == "low" then
    addTag(meta, "repetition_safe")
  elseif meta.repetition_risk == "high" then
    addTag(meta, "repetition_risky")
  end

  if meta.auto_tag_set.ui_candidate == nil and meta.auto_tag_set.short and meta.auto_tag_set.percussive then
    addTag(meta, "ui_candidate")
  end

  if meta.auto_tag_set.percussive == nil and (meta.auto_tag_set.currency or meta.auto_tag_set.tick) then
    addTag(meta, "percussive")
  end

  if tokenSet.click or tokenSet.tick or tokenSet.clock or tokenSet.ping or tokenSet.beep then
    addTag(meta, "precise")
    addTag(meta, "tick")
  end

  if meta.auto_tag_set.failure == nil and meta.auto_tag_set.alert then
    addTag(meta, "warning")
  end

  meta.ai_confidence = math.min(0.95, 0.25 + matchedRules * 0.11)

  return meta
end

local function scoreRole(meta, role)
  local score = 0
  local desiredHit = 0

  for _, tag in ipairs(role.desired_tags or {}) do
    if meta.auto_tag_set[tag] then
      desiredHit = desiredHit + 1
      score = score + 3
    end
  end

  for _, tag in ipairs(role.avoid_tags or {}) do
    if meta.auto_tag_set[tag] then
      score = score - 4
    end
  end

  if meta.auto_tag_set.creature then
    score = score - 2
  end

  if desiredHit >= 2 then
    score = score + 1
  end

  return score
end

local function ensureBuilt()
  local bestRole = nil
  local bestScore = nil

  if metadata_by_id then
    return
  end

  metadata_by_id = {}

  for _, soundId in ipairs(catalog.SOUNDS or {}) do
    local meta = inferMetadata(soundId)

    bestRole = nil
    bestScore = nil

    for _, role in ipairs(roles.LIST) do
      local score = scoreRole(meta, role)
      meta.role_scores[role.id] = score

      if score >= 4 then
        meta.role_candidates[#meta.role_candidates + 1] = role.id
      end

      if bestScore == nil or score > bestScore then
        bestScore = score
        bestRole = role.id
      end
    end

    if #meta.role_candidates == 0 and bestRole ~= nil and bestScore ~= nil and bestScore > 0 then
      meta.role_candidates[1] = bestRole
    end

    metadata_by_id[soundId] = meta
  end
end

function M.get(soundId)
  ensureBuilt()
  return metadata_by_id[soundId]
end

function M.all()
  ensureBuilt()
  return metadata_by_id
end

function M.scoreForRole(soundId, roleId)
  local meta = M.get(soundId)
  return meta and meta.role_scores[roleId] or 0
end

function M.topCandidates(roleId, limit)
  local items = {}

  ensureBuilt()

  for _, soundId in ipairs(catalog.SOUNDS or {}) do
    items[#items + 1] = {
      sound_id = soundId,
      score = M.scoreForRole(soundId, roleId),
    }
  end

  table.sort(items, function(a, b)
    if a.score == b.score then
      return a.sound_id < b.sound_id
    end
    return a.score > b.score
  end)

  if limit and #items > limit then
    while #items > limit do
      table.remove(items)
    end
  end

  return items
end

return M
