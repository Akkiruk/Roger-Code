# Multiplayer Poker Plan

## Audit Fixes

The original brainstorm was directionally right, but it missed several operational risks that matter with the current CCVault model.

1. Same-host enforcement is mandatory.
Every seat computer must report the same `ccvault.getHostName()`. If seats are owned by different hosts, eventual settlement lands in different wallets and the table cannot resolve net winners coherently.

2. Stack declarations and hand settlements must be idempotent.
`rednet.send()` does not guarantee delivery, and duplicate retries are realistic. Dealer-side stack declarations now key on declaration IDs, and real token movement must key on end-of-hand settlement IDs.

3. The dealer cannot move player wallets directly.
Only the authenticated seat terminal can touch that player's wallet. The dealer is authoritative for poker state, not for CCVault transfers.

4. Pre-hand escrow creates avoidable UX and recovery risk.
Charging on join or rebuy means a network or persistence failure can separate real money movement from chip credit. The safer model is to keep chips virtual during the hand and move only the final net result after the hand is resolved.

5. Reconnects need state, not trust.
Dealer state and seat-bank state are both persisted to disk. Rejoins rebind a disconnected seat by player name and requested seat ID instead of creating a duplicate seat.

6. Multi-seat abuse must be blocked.
The dealer now rejects duplicate active seats for the same player name.

7. Leaving the table must not imply a payout.
If the user requirement is "no transfers until a hand is done", then leaving or disconnecting can only close the seat session. Any real token change belongs to explicit hand settlement logic.

## Plan

Phase 1 is implemented in this change.

1. Shared poker protocol and rednet transport.
2. Dealer/seat lobby with discovery over rednet.
3. CCVault-authenticated seat identity with virtual stack declaration only.
4. Dealer persistence for seats, stack declarations, and future settlements.
5. Seat persistence for reconnects and duplicate-settlement prevention.

Phase 2 is not implemented yet.

1. Actual betting rounds.
2. Pot and side-pot engine.
3. Private cards and showdown flow.
4. End-of-hand net settlement using CCVault only after winners and losers are known.
5. Five-card draw or hold'em rules on top of the new transport.

## What Ships Now

The new `PokerTable` program is a working foundation for multiplayer poker tables:

- Dealer mode hosts a discoverable table.
- Seat mode authenticates a player, joins a table, declares a virtual stack, marks ready, tops up that virtual stack, and leaves without moving tokens.
- Real token movement is intentionally deferred.
- All in-table value is tracked as virtual chips in dealer state until a future hand-settlement phase is implemented.

That aligns the foundation with the current requirement: no transfers on join, rebuy, or leave. The remaining money work belongs to the hand engine, where the program can settle only the final net outcome after each completed hand.