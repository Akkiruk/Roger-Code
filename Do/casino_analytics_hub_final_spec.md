# Casino Analytics Hub Final Spec

## Goal

Replace the old per-machine statistics model with a dedicated ComputerCraft analytics computer that receives gameplay events from every casino machine, stores the canonical casino-wide history, and exposes a polished operator-facing statistics menu.

This system is the single source of truth for analytics. Game terminals become event producers only.

## Product Summary

The final system consists of five parts:

1. `Games/lib/casino_event_client.lua`
   Shared client library used by every game terminal.
2. `Games/CasinoAnalyticsHub/analytics_hub.lua`
   Long-running service that receives, validates, persists, and indexes events.
3. `Games/CasinoAnalyticsHub/analytics_ui.lua`
   Operator UI for casino-wide stats, leaderboards, machine health, and drill-down views.
4. `Games/CasinoAnalyticsHub/analytics_store.lua`
   Storage and aggregation engine.
5. `Games/CasinoAnalyticsHub/analytics_protocol.lua`
   Shared message schema, versioning, and validation helpers.

## High-Level Architecture

```text
Game Computers
  Blackjack / Baccarat / HiLo / Roulette / Slots / VideoPoker / PokerTable / TaskMaster
    -> emit structured gameplay events over rednet

Analytics Hub Computer
  rednet receiver
    -> protocol validation
    -> append-only event log
    -> aggregate projections
    -> cached query views
    -> operator UI

Optional Future Consumers
  PhoneOS dashboard
  admin alert computer
  backup/export computer
```

## Design Principles

- The hub owns analytics state.
- Game computers never write long-term statistics files.
- Events are append-only and immutable.
- Aggregates are rebuildable from the raw event log.
- All network messages are versioned.
- UI queries read cached aggregates, not the raw log, unless running rebuild or audit tools.
- The system must tolerate offline periods, duplicate deliveries, and late arrivals.

## Network Model

### Transport

- Use `rednet` with structured tables serialized through `textutils.serializeJSON` only for wire payloads.
- Reserve a dedicated protocol name, for example: `casino.analytics.v1`.
- Each game computer opens its modem on startup and sends events asynchronously.

### Delivery Mode

- Primary mode: fire-and-acknowledge.
- Each event has a stable `event_id`.
- The hub responds with an ACK containing `event_id`, `received_at`, and `hub_seq`.
- Each producer keeps a small outbound retry queue on disk until ACKed.

### Reliability Requirements

- At-least-once delivery.
- Hub deduplicates by `event_id`.
- Producers retry with exponential backoff.
- Producers cap local queue size and log overflow errors.

## Producer Responsibilities

Each game terminal should emit events, not summaries. That keeps the analytics model flexible.

### Required Producer Metadata

Every event includes:

- `schema_version`
- `event_id`
- `event_type`
- `occurred_at`
- `sent_at`
- `source_game`
- `source_machine_id`
- `source_computer_label`
- `session_id`
- `round_id`
- `player_name`
- `host_name`

### Minimum Event Types

- `machine_started`
- `machine_stopped`
- `player_authenticated`
- `player_deauthenticated`
- `bet_placed`
- `round_started`
- `round_resolved`
- `payout_applied`
- `player_charged`
- `round_error`
- `machine_warning`
- `heartbeat`

### Recommended Per-Game Domain Events

- Blackjack:
  `blackjack_action_taken`, `blackjack_split_created`, `blackjack_insurance_offered`, `blackjack_insurance_taken`
- Baccarat:
  `baccarat_bet_selected`, `baccarat_natural_resolved`
- HiLo:
  `hilo_choice_made`, `hilo_cashout`
- Video Poker:
  `videopoker_discards_selected`, `videopoker_hand_evaluated`
- Slots:
  `slots_spin_started`, `slots_spin_resolved`, `slots_gamble_started`, `slots_gamble_resolved`
- Roulette:
  `roulette_bets_locked`, `roulette_spin_resolved`

## Canonical Event Shapes

### Common Envelope

```json
{
  "schema_version": 1,
  "event_id": "vp-12-1743893020123-00044",
  "event_type": "round_resolved",
  "occurred_at": 1743893020123,
  "sent_at": 1743893020201,
  "source_game": "VideoPoker",
  "source_machine_id": 12,
  "source_computer_label": "vp-east-01",
  "session_id": "vp-12-1743892900000",
  "round_id": "vp-12-1743893020123-r18",
  "player_name": "Roger",
  "host_name": "CasinoHost",
  "payload": {}
}
```

### Round Resolved Payload

```json
{
  "bet_amount": 250,
  "net_change": -250,
  "gross_payout": 0,
  "result": "loss",
  "duration_ms": 18342,
  "auto_play": false,
  "details": {
    "hand_name": "No Win",
    "cards_drawn": 5
  }
}
```

### Blackjack Action Payload

```json
{
  "action": "double",
  "hand_index": 1,
  "hand_total_before": 11,
  "dealer_up_card": "6",
  "decision_ms": 742
}
```

## Storage Layout On The Hub

Suggested directory layout:

```text
CasinoAnalyticsHub/
  analytics_hub.lua
  analytics_ui.lua
  analytics_store.lua
  analytics_protocol.lua
  analytics_config.lua
  analytics_error.log
  analytics_runtime.log
  data/
    events/
      2026-04-06.log
      2026-04-07.log
    indexes/
      dedupe_ids.dat
      machine_registry.dat
      player_registry.dat
    projections/
      casino_overview.dat
      games.dat
      players.dat
      machines.dat
      hourly.dat
      daily.dat
      alerts.dat
    snapshots/
      snapshot-2026-04-06T23-59-59.dat
    outbound/
      admin_alert_queue.dat
```

## Persistence Strategy

### Raw Event Log

- Append newline-delimited serialized events to `data/events/YYYY-MM-DD.log`.
- Never mutate prior rows.
- Include hub sequence number when persisted.

### Projections

Maintain rebuildable aggregate tables:

- `casino_overview`
- `games`
- `players`
- `machines`
- `hourly`
- `daily`
- `alerts`

### Snapshots

- Save periodic snapshots of all projections every `N` events or every `M` minutes.
- On boot, load latest snapshot then replay later log files.
- Provide a full rebuild mode for audits and schema migrations.

## Core Aggregates

### Casino Overview

- Total rounds played
- Total wagered
- Total paid out
- Net house profit
- Active machines
- Active players
- Error count
- Last event timestamp

### By Game

- Rounds played
- Total wagered
- Gross payout
- Net house profit
- Average bet
- Biggest single payout
- Average round duration
- Win rate / loss rate / push rate where applicable
- RTP estimate by game

### By Player

- Lifetime wagers
- Lifetime net result
- Favorite game
- Sessions played
- Last seen timestamp
- Biggest win
- Longest session
- Per-game split
- Volatility score

### By Machine

- Computer ID and label
- Assigned game
- Online/offline state
- Last heartbeat
- Error count
- Last player
- Last payout
- Total rounds hosted
- Local queue health if reported by producer

### Time-Series Views

- Hourly wagers
- Hourly profit
- Daily wagers
- Daily profit
- Peak usage windows
- Concurrent players over time

## Operator UI

The analytics hub should feel like a dedicated control console, not a debug page.

### Main Menu

- Overview
- Live Floor
- Game Performance
- Player Leaderboards
- Player Lookup
- Machine Health
- Alerts
- Trends
- Audit Tools
- Export
- Settings

### Overview Screen

Shows:

- House bankroll movement today
- Current online machines
- Active players right now
- Today’s wagers and net
- Biggest win today
- Most active game today
- Recent warnings/errors ticker

### Live Floor Screen

One row per machine:

- machine label
- game name
- online/offline
- active player
- current state such as idle, betting, in_round, settling, fault
- last event age
- current session length

### Game Performance Screen

Tabs or pages by game with:

- rounds
- wagered
- profit
- RTP estimate
- average round duration
- top players for that game
- unusual behavior flags

### Player Leaderboards

Views:

- most wagered
- biggest winners
- biggest losers
- biggest single win
- longest sessions
- most active this week

### Player Lookup

Search by exact name, then show:

- current status
- lifetime totals
- per-game totals
- recent sessions
- recent big wins/losses
- anomaly flags

### Machine Health

- heartbeat age
- restart count
- recent errors
- outbound queue depth reported by client
- current config hash if provided

### Alerts Screen

Show and acknowledge:

- machine offline too long
- repeated settlement failures
- payout spike above threshold
- suspicious player burst behavior
- event queue backlog
- hub storage nearing cap

### Trends Screen

- last hour
- today
- rolling 7 days
- rolling 30 days

This screen can use compact text charts made from block characters or color bars.

## Analytics Features

### Must-Have Metrics

- House profit by game and total
- RTP estimate by game
- Session counts by player
- Bet distribution bands
- Peak play windows
- Win/loss streak observations by player and by machine

### Nice-to-Have Metrics

- Average decision speed by game
- Split/double frequency for Blackjack
- Cash-out depth for HiLo
- Hold/discard tendencies for Video Poker
- Slot outcome frequency tables
- Roulette bet mix heatmap

### Suspicion and Anomaly Flags

Flag, do not auto-act on:

- repeated identical bet timing patterns
- impossible volume from a machine in a short window
- unusual payout burst on a single machine
- missing heartbeat while rounds still claim to resolve
- player hopping rapidly between machines
- duplicate settlement events beyond normal retry behavior

## Client Library API

Suggested API for `casino_event_client.lua`:

```lua
local analytics = require("lib.casino_event_client")

analytics.init({
  modemSide = "top",
  protocol = "casino.analytics.v1",
  machineId = os.getComputerID(),
  machineLabel = os.getComputerLabel(),
  gameName = "Blackjack",
  queueFile = "analytics_queue.dat",
})

analytics.emit("round_started", {
  round_id = roundId,
  player_name = playerName,
  bet_amount = betAmount,
})

analytics.flushPending()
analytics.heartbeat(stateTable)
analytics.shutdown("planned_exit")
```

### Client Requirements

- Validate payload before enqueue.
- Persist unsent queue with `textutils.serialize()`.
- Never crash the game if analytics send fails.
- Log analytics transport failures to a local error log.
- Yield during retry loops.

## Hub Service Lifecycle

### Startup

1. Load config.
2. Open modem.
3. Load latest snapshot.
4. Replay logs newer than snapshot.
5. Rebuild in-memory indexes.
6. Start receiver, heartbeat monitor, snapshot timer, and UI loop with `parallel.waitForAny`.

### Runtime Loops

- receiver loop
- machine timeout loop
- snapshot loop
- admin alert loop
- UI loop

### Shutdown

- flush projections
- write clean shutdown marker
- close modem if desired

## Validation Rules

Reject and log any event that is missing:

- `schema_version`
- `event_id`
- `event_type`
- `source_game`
- `source_machine_id`
- `occurred_at`

Also reject:

- unknown event types
- non-numeric token values
- malformed timestamps
- empty player name where event type requires one
- impossible negative wagers or payouts

## File Formats

Use `textutils.serialize()` for persisted ComputerCraft tables.

Recommended persisted projection structure:

```lua
{
  version = 1,
  generatedAt = 1743894000000,
  casino = {
    totalRounds = 0,
    totalWagered = 0,
    totalPaidOut = 0,
    netProfit = 0,
  },
  games = {},
  players = {},
  machines = {},
  alerts = {},
}
```

## Performance Targets

- Event ingest should remain responsive with 10 to 20 active casino machines.
- UI should render from projections within one tick.
- Snapshot writes should be amortized and not block ingest for long periods.
- Rebuild from log should handle at least several hundred thousand events acceptably on a dedicated advanced computer.

## UI Interaction Model

- Touch-friendly buttons for monitor use.
- Keyboard shortcuts for emulator/operator testing.
- Page-based navigation with clear back/home actions.
- Color-coded state badges.
- A footer showing hub status, pending alerts, and last ingest time.

## Recommended Hardware Layout

### Hub Computer

- Advanced Computer
- Large monitor on the analytics computer
- Wired modem or reliable wireless modem
- Optional speaker for critical alerts

### Producers

- Each game machine must have a modem.
- A monitor is optional for some future utility-only machines.

## Security and Trust Model

- Treat all producer payloads as untrusted.
- Validate every numeric field server-side on the hub.
- Do not allow remote requests to mutate historical data.
- UI actions such as rebuild, purge, export, and reset must require local operator interaction.

## Migration Plan

### Phase 1

- Build protocol library.
- Build minimal hub receiver.
- Emit `machine_started`, `heartbeat`, `bet_placed`, and `round_resolved` from one game.

### Phase 2

- Add append-only log.
- Add projections and overview UI.
- Roll out client library to all games.

### Phase 3

- Add machine health and leaderboards.
- Add snapshots and rebuild tooling.
- Add alerting.

### Phase 4

- Add deep per-game analytics.
- Add anomaly detection.
- Add export/import and historical retention tools.

## Recommended Initial Implementation Order

1. `Games/lib/casino_event_client.lua`
2. `Games/CasinoAnalyticsHub/analytics_protocol.lua`
3. `Games/CasinoAnalyticsHub/analytics_store.lua`
4. `Games/CasinoAnalyticsHub/analytics_hub.lua`
5. `Games/CasinoAnalyticsHub/analytics_ui.lua`
6. Integrate event emission into Blackjack first.
7. Roll event emission into the other games.

## Concrete Success Criteria

- A game machine can go offline and replay queued events later without double-counting.
- The hub shows live machine status for every casino computer.
- The hub can answer “how much has the house made today?” instantly.
- The hub can answer “what has Roger done across all machines this week?” from one screen.
- The hub can rebuild all projections from raw logs without external data.
- No gameplay computer stores canonical analytics state anymore.

## Final Recommendation

Do not rebuild the old per-game statistics menus. Use the archive only as reference material.

The new target should be a proper event-driven analytics platform with:

- dumb producers
- one authoritative hub
- append-only history
- rebuildable aggregates
- an operator UI designed around the whole casino rather than a single machine

That structure scales better, is easier to reason about, and matches the way you want the casino to run.