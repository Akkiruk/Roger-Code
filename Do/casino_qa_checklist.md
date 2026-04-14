# Casino QA Checklist

Last updated: 2026-04-13

Use this for live cabinet verification in CraftOS-PC or on real computers.

## VideoPoker

- Confirm these hands score exactly once and in the right tier:
  - Royal Flush
  - Straight Flush
  - Four of a Kind
  - Full House
  - Flush
  - Straight
  - Three of a Kind
  - Two Pair
  - Jacks or Better
- Confirm `A-2-3-4-5` scores as a straight.
- Confirm `10-J-Q-K-A` only scores as a royal when all suits match.
- Confirm a pair of tens does not pay.
- Confirm payout math returns original bet plus the configured net multiplier.
- Confirm the payout table screen matches the code values.
- Confirm the displayed max bet updates when host balance changes.

## Blackjack

- Confirm the pre-round help menu matches the actual config:
  - blackjack pays even money
  - dealer hits soft 17
  - double only on hard 11
  - split allowed once
  - split aces receive one card
  - insurance off
  - surrender off
- Confirm a natural blackjack resolves immediately unless the dealer also has blackjack.
- Confirm double-blackjack pushes.
- Confirm split and double are unavailable outside the configured rule window.
- Confirm replay flow downgrades gracefully if the host limit shrinks.
- Confirm max bet never exceeds the absolute cap or bankroll coverage cap.

## Roulette

- Confirm straight-up bets pay `35x` net and even-money bets pay `1x` net.
- Confirm mixed inside and outside bets settle correctly on a single spin.
- Confirm per-bet stake caps reject oversized wagers with the correct message.
- Confirm overall house coverage rejects impossible exposure sets.
- Confirm replay restores the last chip layout correctly.
- Confirm result history keeps only the configured number of recent spins.

## Slots

- Confirm the new help menu opens before bet selection.
- Confirm triple payouts match `slots_config.lua`.
- Confirm configured paying pairs either push or pay the expected net amount.
- Confirm non-paying pairs do not silently award anything.
- Confirm a losing spin charges exactly one bet.
- Confirm a winning spin only pays net profit and does not over-credit the player.
- Confirm gamble mode only appears when enabled and after a real win.

## CrazyEights

- Confirm the rules and payout pages match the live config.
- Confirm best-of-three match payout labels match the actual settlement math.
- Confirm draw-chain cap behavior stops at the configured value.
- Confirm timeout auto-play picks legal actions and does not deadlock the round.

## Baccarat

- Confirm Player pays `1:1`.
- Confirm Banker pays `1:1` minus the configured commission.
- Confirm Tie pays the configured tie multiplier.
- Confirm natural 8/9 hands skip draw logic.
- Confirm tutorial screens match live rules.

## HiLo

- Confirm streak multipliers match the config.
- Confirm ties resolve according to the implemented rule.
- Confirm cash-out math uses rounded payout behavior consistently.
- Confirm the displayed help text matches the live payout ladder.

## Cross-Game Limits

- Verify every game rejects bets above player balance.
- Verify every game rejects bets above the current host coverage limit.
- Verify games with an absolute token cap still respect that cap after host balance grows.
- Verify replay or repeat-bet flows revalidate limits instead of trusting the previous round.

## Session And Recovery

- Force-close each cabinet once during a live round and confirm recovery does not duplicate payouts or charges.
- Confirm inactivity timeout exits cleanly without leaving a stale paid state.
- Confirm switching authenticated players mid-session is rejected where relevant.