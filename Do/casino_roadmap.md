# Casino Roadmap

Last updated: 2026-04-13

## What Is Already Shipped

- Blackjack is live.
- Baccarat is live.
- VideoPoker is live.
- HiLo is live.
- Slots is live.
- Roulette is already shipped, not just planned.
- CrazyEights is already shipped, not just planned.
- PokerTable already exists as a multiplayer foundation, but it is only Phase 1.

## Stabilize Current Games First

### VideoPoker

- Keep the current game as Jacks or Better.
- Current payout table in code is `250 / 50 / 25 / 9 / 6 / 4 / 3 / 2 / 1`.
- Current hand evaluation already matches Jacks-or-Better rules, including ace-low straights and high-pair qualification.
- Remaining work is QA, not a rules rewrite.

### Blackjack

- The current table is intentionally tight, not player-friendly Vegas blackjack.
- Current rules are: blackjack pays even money, dealer hits soft 17, doubles are hard-11 only, no insurance, no surrender, one split, split aces get one card.
- That is a product decision more than a bug. If the game feels too punishing, tune the rules as a balance pass instead of treating it like a defect.

### Bet Caps

- Every shipped house game already has bankroll-based host coverage caps.
- Blackjack and Baccarat also already have absolute token caps.
- Roulette already has a per-wager liability cap tied to payout odds.
- Follow-up QA should verify the cap messaging and edge cases, not add another cap system from scratch.

## Actual Build Order

1. Finish stabilization and QA on Blackjack, VideoPoker, Roulette, and the newer CrazyEights cabinet.
2. Build the next house-vs-dealer games: 3 Card Poker and Ultimate Texas Hold'em.
3. Add horse racing only after the two poker house games have specs and payout math locked.
4. Move PokerTable from Phase 1 foundation into a real playable multiplayer poker variant.

## Multiplayer Scope

- 3 Card Poker is a house game, not multiplayer poker.
- Ultimate Texas Hold'em is a house game, not multiplayer poker.
- PokerTable should stay reserved for true player-vs-player poker.
- Multiplayer tic-tac-toe can exist as a framework test, but it is below the casino stabilization and house-game work.

## Poker Decision

- Treat PokerTable as the base for true multiplayer poker only.
- Build five-card draw before Texas Hold'em.
- Reason: it needs fewer betting rounds, less table-state rendering, and a simpler private-card flow across seat terminals.
- Hold'em should come after the betting, side-pot, reconnect, and settlement engine is proven.

## Out-Of-Band Economy Issue

- The weird `100,413` trinket cost issue does not look like a casino-game task.
- If it is real and reproducible, it likely belongs in VaultGear or vhcctweaks item-detail/economy code, not in the casino games.
- Do not block casino roadmap work on it without a concrete reproduction path.