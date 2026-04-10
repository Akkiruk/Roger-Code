# Vault Storage Manager

## Product Goal

Keep a network of connected Vault Hunters storages organized automatically.

The system should feel like a calm storage manager, not a noisy rules engine.

## Core Model

- `Inbox`: a managed inventory where new items appear.
- `Home`: a managed inventory with a purpose and matching rules.
- `Priority`: lower values win when multiple homes match the same item.
- `Idle repair`: when inbox work is done, the manager rescans homes and fixes drift.

## User Experience Goals

- Setup should start from a connected storage, not from a giant config screen.
- Most storages should be configured with a preset plus a strictness level.
- Advanced tuning should stay available, but hidden by default.
- Every move should be explainable from the UI.
- The main screen should show system health, live activity, and what needs attention.

## Screen Model

- `Overview`: health, current mode, next step, managed storages, recent activity.
- `Storages`: pick an inventory, assign a role, apply a preset, then open advanced rules only if needed.
- `Live`: recent moves, current repair/routing state, sampled item decisions.

## Routing Rules

1. New items are scanned from connected inboxes first.
2. Supported vault items are matched against enabled homes.
3. The best home is the matching home with the highest priority.
4. If an item is already in an equally ranked matching home, it stays put.
5. If no home matches, the item remains unresolved until a better home exists.

## Repair Rules

1. When inbox routing is idle, the manager picks the next rescan-enabled home.
2. Sampled items in that home are re-evaluated.
3. Misplaced items are moved into a better home when one exists.
4. Repair should be steady and low-noise rather than aggressive and thrashy.

## Preset Strategy

Presets should represent real storage jobs, not implementation details.

Examples:

- General Gear
- High-Value Gear
- Unidentified Gear
- Jewel Storage
- Small Jewels
- Trinkets
- Charms
- Etchings
- Overflow

## Safety Principles

- No built-in trash lane in the core model.
- Missing or disconnected storages should degrade gracefully.
- Unsupported items should be ignored, not force-moved.
- Moves should be sparse, explainable, and loop-resistant.
