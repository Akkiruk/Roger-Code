# Legacy Casino Statistics Archive

This directory preserves the retired per-machine statistics code that used to ship with the live casino games.

Why it was removed:
- Local gameplay terminals should focus on running games, not storing long-term analytics state.
- The next iteration is a dedicated casino analytics computer that receives events from every game computer and renders a casino-wide statistics UI.

What is archived here:
- `Games/Blackjack/statistics.lua`
- `Games/Blackjack/stats_ui.lua`
- `Games/lib/player_stats.lua`
- `Games/lib/achievements.lua`
- `Games/lib/session_stats.lua`

Notes:
- These files are intentionally kept outside `Games/` so they are not deployed by the installer or deploy-index builder.
- The archive preserves the old implementation for reference, migration work, and selective code reuse.
- If parts of this are revived later, prefer extracting reusable ideas into a new shared event-driven analytics library instead of restoring the old per-terminal storage model wholesale.