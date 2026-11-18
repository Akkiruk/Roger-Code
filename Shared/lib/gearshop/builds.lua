-- gearshop/builds.lua
-- The build presets IMPROVEMENTS judges gear by (IMPROVEMENTS-SEARCH-DESIGN.md in the lobby build folder, section 4).
-- Weights run 0 to 3 (0: the stat does not count). The owner can change any weight on the shop computer (page 4, B):
-- those are kept in the limits as `buildWeights`, { build = { attribute = weight } }, over these.
-- Attributes are vhcctweaks' ids without "the_vault:". Nothing here touches a peripheral: Tests/gearshop_test.lua runs it.

local M = {}

M.ORDER = { "caster", "melee", "lucky", "tank", "thorns", "summoner", "healer", "hybrid", "looter", "balanced" }

M.LABELS = {
  caster = "Caster (Ability Power)", melee = "Melee (Attack Damage)", lucky = "Lucky Hit", tank = "Tank (Resistance, Health)",
  thorns = "Thorns (Shield)", summoner = "Summoner", healer = "Healer", hybrid = "Hybrid (Battlestaff)",
  looter = "Looter (Quantity, Rarity)", balanced = "Balanced (every stat)",
}

--- The largest natural level-100 roll of each attribute anywhere: one line of it is worth 1 (section 2.6).
M.REF = {
  ability_power = 50, ability_power_percent = 0.2, area_of_effect = 0.2, armor = 30, attack_damage = 132, attack_range = 0.5,
  attack_speed_percent = 0.25, block = 0.3, cooldown_reduction = 0.28, copiously = 0.25, critical_hit_mitigation = 0.4,
  damage_increase = 0.35, damage_champion = 0.3, damage_dungeon = 0.3, damage_assassin = 0.3, damage_horde = 0.3,
  damage_tank = 0.3, damage_dweller = 0.3, damage_illagers = 1.0, damage_spiders = 1.0, damage_undead = 1.0,
  damage_nether = 1.0, double_hit_chance = 0.81, durability_wear_reduction = 0.5, echoing_chance = 0.24,
  echoing_damage = 0.08, effect_duration = 0.2, healing_effectiveness = 0.42, health = 6, hit_hearts = 0.24,
  item_quantity = 0.6, item_rarity = 0.7, knockback_resistance = 0.5, leech = 0.01, lucky_hit_chance = 0.1,
  mana_additive = 100, mana_additive_percentile = 0.5, mana_cost_reduction = 0.08, mana_regen = 1, mining_speed = 20,
  movement_speed = 0.2, on_hit_chain = 8, on_hit_stun = 0.3, piercing = 5, range = 30, reach = 1.5, resistance = 0.2,
  returning_damage = 0.65, shocking_hit_chance = 0.6, soul_chance = 1.0, summon_damage = 0.25, sweeping_hit_damage = 0.8,
  thorns_damage_flat = 50, trap_disarming = 1.0, velocity = 0.25, summon_damage_percent = 0.25, sweeping = 0.8,
  effect_list_avoidance = 0.5, on_kill_heal = 1, durability = 1,
}

--- Every build that sets no value of its own gets these: a floor of survival.
M.UNIVERSAL = { resistance = 0.6, health = 0.4, armor = 0.3 }
--- Weight 0 unless a build names them.
M.IGNORE = { durability = true, soul_chance = true }
--- A piece is worth suggesting when it is this much better in fit points (100 is one best-roll line at weight 1), and
-- at least this share of what the worn piece scores.
M.WORTH = { minPoints = 15, minRel = 0.08 }

-- the weights table of the design, a row an attribute (or a few that share one), a column a build
local COLUMNS = { "caster", "melee", "lucky", "tank", "thorns", "summoner", "healer", "hybrid", "looter", "balanced" }
local ROWS = {
  { { "ability_power" }, { 3, nil, nil, nil, nil, 2.5, 1, 2.5, nil, 1 } },
  { { "ability_power_percent" }, { 3, nil, nil, nil, nil, 2.5, 1, 2, nil, 1 } },
  { { "summon_damage" }, { 0.5, nil, nil, nil, nil, 3, nil, nil, nil, 1 } },
  { { "cooldown_reduction" }, { 2.5, 0.5, 0.5, 0.5, 0.5, 2, 2.5, 1.5, 0.5, 1 } },
  { { "mana_regen" }, { 1.5, nil, nil, nil, nil, 1, 2, 0.8, nil, 1 } },
  { { "mana_additive", "mana_additive_percentile" }, { 1, nil, nil, 0.3, nil, 1, 1, 0.5, nil, 1 } },
  { { "mana_cost_reduction" }, { 1, nil, nil, nil, nil, 0.8, 1, 0.5, nil, 1 } },
  { { "area_of_effect" }, { 1.2, 0.5, 0.5, nil, 1, 1.5, 0.8, 1, nil, 1 } },
  { { "effect_duration" }, { 0.6, nil, nil, nil, nil, 2, 1.5, nil, nil, 1 } },
  { { "healing_effectiveness" }, { 0.3, nil, nil, 0.5, 0.5, nil, 3, nil, nil, 1 } },
  { { "added_ability_level" }, { 2, 1.5, 1.5, 1.5, 1.5, 2, 2, 1.5, 1, 1 } },
  { { "attack_damage" }, { nil, 3, 2, nil, nil, nil, nil, 2.5, nil, 1 } },
  { { "damage_increase" }, { 0.3, 3, 2, nil, nil, 0.5, nil, 2, nil, 1 } },
  { { "attack_speed_percent" }, { nil, 2, 1.5, nil, nil, nil, nil, 1, nil, 1 } },
  { { "double_hit_chance", "sweeping_hit_damage" }, { nil, 1.5, 1, nil, nil, nil, nil, 0.8, nil, 1 } },
  { { "on_hit_chain" }, { nil, 1.5, 2, nil, nil, nil, nil, 1.5, nil, 1 } },
  { { "lucky_hit_chance" }, { 0.3, 1, 3, nil, nil, nil, nil, 0.8, nil, 1 } },
  { { "echoing_damage", "echoing_chance" }, { nil, 1, 1, nil, nil, nil, nil, 0.8, nil, 1 } },
  { { "damage_champion", "damage_dungeon", "damage_assassin", "damage_horde", "damage_tank", "damage_dweller" },
    { nil, 0.4, 0.4, nil, nil, nil, nil, 0.3, nil, 0.3 } },
  { { "damage_illagers", "damage_spiders", "damage_undead", "damage_nether" }, { nil, 0.2, 0.2, nil, nil, nil, nil, 0.2, nil, 0.2 } },
  { { "attack_range" }, { nil, 0.6, 0.6, nil, nil, nil, nil, 0.4, nil, 1 } },
  { { "leech", "hit_hearts", "on_kill_heal" }, { nil, 1, 1.2, 0.5, nil, nil, nil, 0.6, nil, 1 } },
  { { "on_hit_stun", "shocking_hit_chance" }, { nil, 0.6, 0.6, 0.5, nil, nil, nil, 0.5, nil, 1 } },
  { { "resistance" }, { 1, 1, 1, 3, 2, 1, 1, 1, 0.6, 1 } },
  { { "health" }, { 0.6, 0.8, 0.8, 3, 2, 0.6, 0.8, 0.8, 0.4, 1 } },
  { { "armor" }, { 0.4, 0.6, 0.6, 2, 1.5, 0.4, 0.5, 0.6, 0.3, 1 } },
  { { "block" }, { nil, nil, nil, 2, 2.5, nil, nil, nil, nil, 1 } },
  { { "thorns_damage_flat" }, { nil, nil, nil, 0.5, 3, nil, nil, nil, nil, 1 } },
  { { "critical_hit_mitigation" }, { 0.3, 0.3, 0.3, 1, 1, 0.3, 0.3, 0.3, nil, 1 } },
  { { "knockback_resistance", "effect_list_avoidance" }, { 0.3, 0.3, 0.3, 1, 0.8, 0.3, 0.5, 0.3, nil, 1 } },
  { { "movement_speed" }, { 0.8, 0.8, 0.8, 0.5, 0.5, 0.8, 0.8, 0.8, 1.5, 1 } },
  { { "item_quantity", "item_rarity" }, { nil, nil, nil, nil, nil, nil, nil, nil, 3, 1 } },
  { { "copiously" }, { nil, nil, nil, nil, nil, nil, nil, nil, 2.5, 1 } },
  { { "soul_chance" }, { nil, nil, nil, nil, nil, nil, nil, nil, 2, 0 } },
  { { "trap_disarming" }, { nil, nil, nil, nil, nil, nil, nil, nil, 1, 1 } },
  { { "mining_speed", "reach" }, { nil, nil, nil, nil, nil, nil, nil, nil, 1, 1 } },
  { { "durability" }, { 0, 0, 0, 0.1, 0.1, 0, 0, 0, 0, 0.3 } },
}

local WEAPONS = { "the_vault:sword", "the_vault:axe", "the_vault:battlestaff", "the_vault:trident", "the_vault:rang" }
local CASTER_OFF = { "the_vault:wand", "the_vault:focus" }

-- caps (fractions), require (allowed types per slot), keep (a stat the build must not lose more than keepLoss of),
-- abilities (name patterns an added_ability_level line, or a learned ability, counts for)
M.RULES = {
  caster = { caps = { cooldown_reduction = 0.8, area_of_effect = 0.8 }, require = { offhand = CASTER_OFF }, keep = { "ability_power" },
    abilities = { "^Fireball", "^Nova", "^Smite", "^Chain_Lightning", "^Arcane", "^Ice_Bolt", "^Stonefall_Snow", "^Toxic" } },
  melee = { caps = { area_of_effect = 0.8, lucky_hit_chance = 0.562 }, require = { weapon = WEAPONS }, keep = { "attack_damage" },
    abilities = { "^Rampage", "^Battle_Cry", "^Javelin", "^Dash_Damage", "^Stonefall" } },
  lucky = { caps = { lucky_hit_chance = 0.562 }, require = { weapon = WEAPONS }, keep = { "lucky_hit_chance" },
    abilities = { "^Battle_Cry_Lucky_Strike", "^Rampage_Leech", "^Javelin_Scatter" } },
  tank = { caps = { resistance = 0.5, block = 0.6 }, keep = { "resistance" },
    abilities = { "^Mana_Shield", "^Mana_Barrier", "^Shell", "^Taunt", "^Empower_Ice_Armor" } },
  thorns = { caps = { resistance = 0.5, block = 0.6 }, require = { offhand = { "the_vault:shield" } }, keep = { "thorns_damage_flat" },
    keepSlots = { offhand = true }, abilities = { "^Shell_Porcupine", "^Shell_Quill", "^Mana_Shield_Retribution", "^Shield_Bash" } },
  summoner = { caps = { cooldown_reduction = 0.8, area_of_effect = 0.8 }, require = { offhand = CASTER_OFF },
    keepAny = { "summon_damage", "ability_power" }, abilities = { "^Totem", "^Taunt_Charm" } },
  healer = { caps = { cooldown_reduction = 0.8 }, keep = { "healing_effectiveness" }, abilities = { "^Heal", "^Totem_Mana_Regen" } },
  hybrid = { caps = { cooldown_reduction = 0.8, area_of_effect = 0.8 },
    require = { weapon = { "the_vault:battlestaff", "the_vault:sword", "the_vault:axe" } },
    abilities = { "^Battle_Cry_Spectral_Strike", "^Arcane_Rail", "^Fireball_Fireshot" } },
  looter = { abilities = { "^Vein_Miner", "^Hunter", "^Ghost_Walk", "^Mega_Jump", "^Dash" } },
  balanced = { abilities = { "." } },
}

--- Trinkets (Curios) that point at a build.
M.TRINKETS = { spellbook = "caster", cufflinks = "caster", crystal_ball = "caster", phylactery = "caster",
  stone_of_jordan = "caster", clover = "lucky", giants_heart = "tank", carapace = "tank", healing_salve = "healer",
  velaras_petal = "healer", tenos_charm = "looter", lucky_goose = "looter" }

--- The default weights of every build: { build = { attribute = weight } }.
function M.defaults()
  local out = {}
  for _, id in ipairs(COLUMNS) do out[id] = {} end
  for _, row in ipairs(ROWS) do
    for col, id in ipairs(COLUMNS) do
      local v = row[2][col]
      if v ~= nil then
        for _, a in ipairs(row[1]) do out[id][a] = v end
      end
    end
  end
  return out
end

--- The builds with the owner's weights over the defaults: { id = { id, label, weights, caps, require, keep, ... } }.
-- owner: cfg.buildWeights, { build = { attribute = weight } }.
function M.all(owner)
  local weights = M.defaults()
  for id, mine in pairs(type(owner) == "table" and owner or {}) do
    if weights[id] and type(mine) == "table" then
      for a, v in pairs(mine) do
        if type(v) == "number" then weights[id][a] = v end
      end
    end
  end
  local out = {}
  for _, id in ipairs(M.ORDER) do
    local r = M.RULES[id] or {}
    out[id] = { id = id, label = M.LABELS[id], weights = weights[id], caps = r.caps or {}, require = r.require,
      keep = r.keep, keepAny = r.keepAny, keepSlots = r.keepSlots, keepLoss = r.keepLoss or 0.10, abilities = r.abilities or {} }
  end
  return out
end

--- What a stat weighs in a build: its own weight, else the survival floor (unless ignored), else 0.
function M.weight(build, a)
  local w = build.weights[a]
  if w ~= nil then return w end
  if M.IGNORE[a] then return 0 end
  return M.UNIVERSAL[a] or 0
end

--- The attributes a build lists, for the owner's editor: { a, ... } sorted.
function M.attributes()
  local seen, list = {}, {}
  for _, row in ipairs(ROWS) do
    for _, a in ipairs(row[1]) do
      if not seen[a] then
        seen[a] = true
        list[#list + 1] = a
      end
    end
  end
  table.sort(list)
  return list
end

return M
