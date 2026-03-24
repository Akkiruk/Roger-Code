# Vault Gear Sorter

## Research Findings

- `Roger-Code` is the canonical ComputerCraft source repo. Existing patterns worth reusing were the flat `Games/<Program>/` installer layout, `Games/lib/` shared modules, `inventory.list()` before `getItemDetail()`, and file-backed error logging.
- As of `vhcctweaks` `2.2.4` on `2026-03-24`, Vault Hunters item data is exposed by enriching CC:Tweaked `getItemDetail()` with a `vaultData` table. I did **not** find a separate custom `getItemInfo()` API in source or runtime artifacts.
- The current detail provider lives in `com.vhcctweaks.detail.VaultItemDetailProvider` and covers `Gear`, `Tool`, `Jewel`, `Trinket`, `Charm`, `Inscription`, `Catalyst`, `VaultCrystal`, `VaultDoll`, `Card`, `Augment`, `Etching`, and a generic `VaultItem` fallback.
- Reliable top-level gear-sorter fields today:
  - Common gear fields: `itemType`, `name`, `level`, `rarity`, `state`, `identified`
  - Gear-only: `gearType`, `equipmentSlot`, `repairSlots`, `durability`, `craftingPotential`, `prefixSlots`, `suffixSlots`, `isLegendary`, `isSoulbound`, `uniqueKey`, `gearName`, `model`, `implicits`, `prefixes`, `suffixes`
  - Tool: `level`, `rarity`, `repairSlots`, `durability`, modifier lists
  - Jewel: `level`, `rarity`, modifier lists
  - Trinket/Charm: `uses`, `slot`/`effect`, `god`, `godReputation`
- Reliable modifier fields today:
  - `name`
  - `group` when Vault provides one
  - `identifier` when Vault provides one
  - `tier`, `min`, `max` for many rolled numeric modifiers
  - category flags such as `legendary`, `crafted`, `frozen`, `greater`, `corrupted`, `imbued`
- Important limitations:
  - Unidentified gear returns only minimal data; modifier, durability, repair-slot, and crafting-potential rules cannot be trusted there.
  - Jewel size is not exposed as a top-level field by `vhcctweaks` `2.2.4`; the sorter derives it from modifiers when possible.
  - Tool capacity is not exposed as a top-level field either and is not a first-class rule in this first pass.
  - Some modifier values are complex tables, so the UI currently treats modifier rules as presence/absence matches instead of arbitrary value expressions.
  - Fallback matching on modifier `name` is less stable than `group` or `identifier`, so canonical matching uses `group -> identifier -> normalized name`.

## Design Decisions

- The sorter is a keep-profile system, not a hardcoded ruleset. Each supported item type has its own profile that says what to keep and what to do on a miss.
- Safety defaults favor retention:
  - runtime starts disabled
  - non-vault items default to keep
  - unsupported vault items default to keep
  - detail-read failures default to keep
  - miss action defaults to keep until the player intentionally flips it to discard
- The monitor UI is split into four pages:
  - `Run`: start/stop, stats, health, preview, and selected-item summary
  - `Routing`: input/keep/trash selection plus scan cadence controls
  - `Profiles`: per-type keep criteria
  - `Modifiers`: discovered modifier catalog plus keep/block lists
- Config persistence is split:
  - `vaultgear_config.lua` for user intent
  - `vaultgear_state_settings.lua` for UI state and discovered modifier catalog
- The installer manifest tooling was upgraded to support recursive files under both program folders and `Games/lib/`, which makes namespaced subsystem libraries possible.

## Rule Model

- Supported sortable types in this first pass:
  - `Gear`
  - `Tool`
  - `Jewel`
  - `Trinket`
  - `Charm`
  - `Etching`
- Profile fields exposed in the UI:
  - `enabled`
  - `miss_action`
  - `unidentified_mode`
  - `min_rarity`
  - `min_level`
  - `max_level`
  - `min_crafting_potential` for gear
  - `min_free_repair_slots` for gear/tools
  - `min_durability_percent` for gear/tools
  - `max_jewel_size` for jewels
  - `min_uses` for trinkets/charms
  - `keep_legendary`, `keep_soulbound`, `keep_unique` where applicable
  - wanted/blocked modifier lists with `any/all` wanted matching

## Future Extensions

- Extend `vhcctweaks` to expose jewel size and tool capacity as explicit top-level fields.
- Add value-aware modifier rules for numeric modifiers.
- Add dedicated pages for non-gear Vault items such as crystals, catalysts, and inscriptions.
- Add a quarantine/overflow destination for blocked moves instead of simple retry-on-next-cycle behavior.
- Add monitor selection and multi-monitor dashboards if this grows into a fuller Vault Gear workstation.
