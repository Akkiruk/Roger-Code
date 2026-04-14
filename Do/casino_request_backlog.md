# Casino Request Backlog

Last updated: 2026-04-14

| Priority | Request | Category | Status | Notes |
| --- | --- | --- | --- | --- |
| P1 | Recheck VideoPoker payouts and Jacks-or-Better logic | QA | Needs runtime QA | Code review says the current table and evaluator match the intended rules. |
| P1 | Review Blackjack balance and overall feel | Balance | Needs decision | Current table is intentionally harsh; tune rules only if the product goal changes. |
| P1 | QA new max bet cap behavior | QA | Needs runtime QA | Coverage caps already exist across all shipped house games. |
| P1 | Add visible rules and payout tables where missing | UX | Complete | HiLo now exposes the payout ladder too; shipped house games now surface rules or payout info in-game. |
| P2 | 3 Card Poker vs house | New game | Not started | House game, separate from PokerTable. |
| P2 | Ultimate Texas Hold'em vs dealer | New game | Not started | House game, separate from PokerTable. |
| P2 | Horse betting / digital horse race | New game | Not started | Needs payout model and race presentation spec. |
| P2 | PokerTable Phase 2 betting and settlement | Multiplayer | Not started | Phase 1 lobby and virtual stack flow already exists. |
| P3 | Multiplayer tic-tac-toe | Multiplayer framework | Not started | Useful as a framework proof, but not a casino priority. |
| P3 | Texas Hold'em on PokerTable | Multiplayer poker | Deferred | Build after five-card draw proves the engine. |
| P3 | Investigate 100,413-cost trinket issue | Economy | Needs reproduction | Likely belongs to VaultGear or vhcctweaks, not the casino code. |