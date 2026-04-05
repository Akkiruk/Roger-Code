# Multiplayer Poker Plan

## Audit Fixes

The original brainstorm was directionally right, but it missed several operational risks that matter with the current CCVault model.

1. Same-host enforcement is mandatory.
Every seat computer must report the same `ccvault.getHostName()`. If seats are owned by different hosts, buy-ins land in different wallets and the table cannot cash out coherently.

2. Buy-ins and cash-outs must be idempotent.
`rednet.send()` does not guarantee delivery, and duplicate retries are realistic. Dealer-side buy-in processing now keys on transaction IDs, and seat-side cash-outs key on settlement IDs.

3. The dealer cannot move player wallets directly.
Only the authenticated seat terminal can touch that player's wallet. The dealer is authoritative for poker state, not for CCVault transfers.

4. The host bankroll can drift while a table is live.
Players buy in to the host, but the host can still spend tokens outside the table. Cash-out code therefore checks the live host balance before paying and leaves the session open if the bank is short.

5. Reconnects need state, not trust.
Dealer state and seat-bank state are both persisted to disk. Rejoins rebind a disconnected seat by player name and requested seat ID instead of creating a duplicate seat.

6. Multi-seat abuse must be blocked.
The dealer now rejects duplicate active seats for the same player name.

## Plan

Phase 1 is implemented in this change.

1. Shared poker protocol and rednet transport.
2. Dealer/seat lobby with discovery over rednet.
3. CCVault-authenticated buy-in and cash-out with host escrow.
4. Dealer persistence for seats, buy-ins, and pending settlements.
5. Seat persistence for duplicate-payout prevention.

Phase 2 is not implemented yet.

1. Actual betting rounds.
2. Pot and side-pot engine.
3. Private cards and showdown flow.
4. Five-card draw or hold'em rules on top of the new transport.

## What Ships Now

The new `PokerTable` program is a working foundation for multiplayer poker tables:

- Dealer mode hosts a discoverable table.
- Seat mode authenticates a player, joins a table, buys in, marks ready, rebuys, and cashes out.
- Real token movement is only:
  - buy-in: player -> host
  - cash-out: host -> player
- All in-table value is tracked as chips in dealer state.

That resolves the money-transfer problem correctly with the current CCVault API and gives the repo a real multiplayer substrate to build the actual poker game on.