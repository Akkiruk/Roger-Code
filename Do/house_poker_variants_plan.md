# House Poker Variants Plan

Last updated: 2026-04-13

This document covers the next two house-vs-dealer poker cabinets:

- 3 Card Poker
- Ultimate Texas Hold'em

These are not multiplayer poker features and do not belong on `PokerTable`.

## Build Order

1. Build 3 Card Poker first.
2. Build Ultimate Texas Hold'em second.

Reason:

- 3 Card Poker has a smaller state machine.
- It needs fewer betting branches.
- It is the cleaner place to harden house-poker UI, payout settlement, and replay flow before taking on UTH.

## Shared Requirements

- Both games are single-seat house games.
- Both should follow the existing casino cabinet structure used by Blackjack, Baccarat, VideoPoker, and Roulette.
- Both should use transfer-at-end settlement through the existing settlement helpers.
- Both should expose in-game payout and rules screens from day one.
- Both should enforce bankroll-based host coverage limits before a round starts.
- Both should reject stale player sessions if the authenticated player changes.
- Both should log failures through the existing alert and safe-runner patterns.

## 3 Card Poker

### Core Rules

- Player places an Ante bet.
- Optional Pair Plus bet can be added.
- Dealer and player each receive three cards.
- Player chooses `PLAY` or `FOLD` after seeing their hand.
- `PLAY` adds a Play bet equal to the Ante.
- Dealer qualifies with `Q high` or better.

### Base Settlement Model

- If player folds:
  - lose Ante
  - Pair Plus still resolves on player hand strength
- If player plays and dealer does not qualify:
  - Ante pushes
  - Play pays `1:1` if player beats dealer
  - Play loses if player loses to dealer
- If player plays and dealer qualifies:
  - compare hands normally
  - winning Ante pays `1:1`
  - winning Play pays `1:1`
  - losing Ante and Play are both charged
  - ties push

### Pair Plus Payout Table

Recommended starting table:

- Straight Flush: `40:1`
- Three of a Kind: `30:1`
- Straight: `6:1`
- Flush: `3:1`
- Pair: `1:1`

### Ante Bonus

Recommended starting bonus table, independent of dealer qualification:

- Straight Flush: `5:1`
- Three of a Kind: `4:1`
- Straight: `1:1`

### Hand Ranking

Use 3-card poker ranking, not 5-card ranking:

1. Straight Flush
2. Three of a Kind
3. Straight
4. Flush
5. Pair
6. High Card

Notes:

- In 3 Card Poker, a straight ranks above a flush.
- `A-2-3` should count as a straight.

### Cabinet Flow

1. Pre-round menu: `PLAY`, `PAYOUTS`, `HOW TO PLAY`.
2. Bet screen with separate Ante and optional Pair Plus controls.
3. Deal three player cards and three dealer cards with dealer hidden.
4. Player decision screen: `PLAY` or `FOLD`.
5. Reveal dealer, resolve qualification, then settle all active wagers.
6. Replay prompt preserving the previous bet layout if still valid.

### First Implementation Scope

- Fixed Ante denomination selection through the shared bet screen.
- Pair Plus toggle or secondary bet amount using a simple stepped control.
- No side features beyond Ante Bonus and Pair Plus.
- No progressive jackpot path.

### Acceptance Criteria

- Dealer qualification works correctly.
- Fold path resolves Pair Plus independently.
- Ante Bonus pays correctly even if dealer does not qualify.
- Pair Plus and base game settlement never double-charge or double-pay.
- Rules and payout screens match the code.

## Ultimate Texas Hold'em

### Core Rules

- Player starts with Ante and Blind bets of equal size.
- Optional Trips side bet can be added.
- Player receives two hole cards.
- Dealer receives two hole cards hidden until showdown.
- Five community cards are revealed across flop, turn, and river.
- Player may raise once during the hand:
  - `4x` preflop
  - `2x` on the flop
  - `1x` on the turn or river
- If player never raises, they may fold at the river and lose Ante and Blind.

### Base Settlement Model

- Dealer qualifies with a pair or better.
- If dealer qualifies:
  - Ante pays `1:1` on player win
  - Blind pays according to the blind table on straights or better, otherwise pushes on a player win
  - Raise pays `1:1` on player win
  - all three lose on a player loss
  - ties push
- If dealer does not qualify:
  - Ante pushes
  - Raise pays `1:1` on player win
  - Blind still resolves by the blind table if the player wins with a qualifying hand, otherwise pushes

### Blind Payout Table

Recommended starting table:

- Royal Flush: `500:1`
- Straight Flush: `50:1`
- Four of a Kind: `10:1`
- Full House: `3:1`
- Flush: `3:2`
- Straight: `1:1`
- Lower hands: push on player win

### Trips Side Bet

Recommended starting table:

- Royal Flush: `50:1`
- Straight Flush: `40:1`
- Four of a Kind: `30:1`
- Full House: `8:1`
- Flush: `7:1`
- Straight: `4:1`
- Three of a Kind: `3:1`

### Cabinet Flow

1. Pre-round menu: `PLAY`, `PAYOUTS`, `HOW TO PLAY`.
2. Bet screen for Ante/Blind base stake plus optional Trips side bet.
3. Preflop reveal of player hole cards with actions `CHECK` or `RAISE 4X`.
4. Flop reveal with actions `CHECK` or `RAISE 2X` if no raise yet.
5. Turn and river reveal with actions `FOLD` or `RAISE 1X` if still unchecked.
6. Showdown, dealer qualification, settlement, replay prompt.

### First Implementation Scope

- Single fixed raise path enforcement so only one raise can ever exist.
- No progressive jackpot path.
- No dealer animation beyond existing card reveal patterns.
- Use shared 5-card evaluation logic against the best 5 of 7 cards.

### Acceptance Criteria

- Raise windows enforce the correct multiplier at the correct street.
- Dealer qualification and blind payouts match the selected rules.
- Trips resolves independently from the base game.
- Player cannot raise more than once.
- Fold path never settles Raise or Trips incorrectly.

## Shared Code Opportunities

- Add a shared helper for house-poker side-bet settlement.
- Add a shared helper for rules/payout page rendering where practical.
- Extend `card_rules.lua` only if the extracted evaluator logic remains reusable.
- Keep cabinet-specific decision flow in game-local files rather than over-generalizing too early.

## Recommended Repo Layout

- `Games/ThreeCardPoker/`
- `Games/UltimateTexasHoldem/`

Each folder should include:

- `startup.lua`
- main game file
- config file
- any local art assets

## Do Not Mix With PokerTable

- `PokerTable` remains reserved for player-vs-player poker.
- Do not reuse its dealer/seat network model for these house games.
- Shared card-ranking helpers are fine.
- Shared cabinet UX patterns are fine.