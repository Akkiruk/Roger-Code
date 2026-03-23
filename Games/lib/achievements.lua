-- achievements.lua
-- Achievement definitions and checking engine for Blackjack.
-- Extracted from statistics.lua for modularity.
-- All 102 achievements organized by category with check functions.

local playerStats = require("lib.player_stats")

-----------------------------------------------------
-- Achievement Categories
-----------------------------------------------------
local CATEGORIES = {
  BEGINNER = {
    id = "beginner",
    name = "Beginner's Journey",
    color = colors.lime,
    description = "Your first steps into the world of blackjack",
  },
  EXPERT = {
    id = "expert",
    name = "Expert Play",
    color = colors.cyan,
    description = "Achievements for skilled blackjack players",
  },
  RISK = {
    id = "risk",
    name = "Risk Taker",
    color = colors.orange,
    description = "For those who like to live dangerously",
  },
  STRATEGY = {
    id = "strategy",
    name = "Strategic Mind",
    color = colors.blue,
    description = "Achievements for strategic play and decision making",
  },
  FORTUNE = {
    id = "fortune",
    name = "Fortune & Fate",
    color = colors.yellow,
    description = "Lucky streaks and rare occurrences",
  },
  MILESTONES = {
    id = "milestones",
    name = "Milestones",
    color = colors.purple,
    description = "Major accomplishments in your blackjack career",
  },
  DEDICATION = {
    id = "dedication",
    name = "Dedication",
    color = colors.white,
    description = "Achievements for dedicated players",
  },
  MATHEMATICAL = {
    id = "mathematical",
    name = "Mathematical Feats",
    color = colors.lightBlue,
    description = "Achievements based on numbers and patterns",
  },
  SEASONAL = {
    id = "seasonal",
    name = "Seasonal",
    color = colors.pink,
    description = "Special achievements related to time periods",
  },
  SPECIAL = {
    id = "special",
    name = "Special & Rare",
    color = colors.red,
    description = "Unique and highly challenging achievements",
  },
  HUMOROUS = {
    id = "humorous",
    name = "Humorous",
    color = colors.green,
    description = "Fun and quirky achievements",
  },
  DEALER = {
    id = "dealer",
    name = "Dealer Dynamics",
    color = colors.gray,
    description = "Achievements related to dealer interactions",
  },
  SUPERSTITION = {
    id = "superstition",
    name = "Superstitions",
    color = colors.magenta,
    description = "Cards, numbers, and patterns considered lucky or unlucky",
  },
}

-----------------------------------------------------
-- Math helpers for achievement checks
-----------------------------------------------------
local function isFibonacci(n)
  local a, b = 0, 1
  while b <= n do
    if b == n then return true end
    a, b = b, a + b
  end
  return false
end

local function isPrime(n)
  if n <= 1 then return false end
  if n <= 3 then return true end
  if n % 2 == 0 or n % 3 == 0 then return false end
  local i = 5
  while i * i <= n do
    if n % i == 0 or n % (i + 2) == 0 then return false end
    i = i + 6
  end
  return true
end

-----------------------------------------------------
-- Achievement Definitions (102 achievements)
-----------------------------------------------------
local ACHIEVEMENTS = {
  -- ===== BEGINNER =====
  {
    id = "first_win",
    name = "Beginner's Luck",
    description = "Win your first hand of blackjack",
    category = CATEGORIES.BEGINNER,
    checkFunction = function(s) return (s.wins or 0) >= 1 end,
  },
  {
    id = "first_blackjack",
    name = "Natural Talent",
    description = "Get your first blackjack",
    category = CATEGORIES.BEGINNER,
    checkFunction = function(s) return (s.blackjacks or 0) >= 1 end,
  },
  {
    id = "first_double_down",
    name = "Double Trouble",
    description = "Double down for the first time",
    category = CATEGORIES.BEGINNER,
    checkFunction = function(s)
      return s.actions and s.actions.double and (s.actions.double.total or 0) >= 1
    end,
  },
  {
    id = "first_push",
    name = "Standoff",
    description = "Push (tie) with the dealer",
    category = CATEGORIES.BEGINNER,
    checkFunction = function(s) return (s.pushes or 0) >= 1 end,
  },
  {
    id = "first_bust",
    name = "Learning the Hard Way",
    description = "Bust for the first time",
    category = CATEGORIES.BEGINNER,
    checkFunction = function(s) return (s.busts or 0) >= 1 end,
  },

  -- ===== FORTUNE =====
  {
    id = "winning_streak",
    name = "Hot Streak",
    description = "Win 3 hands in a row",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.winStreak or 0) >= 3 end,
  },
  {
    id = "lucky_seven",
    name = "Lucky Seven",
    description = "Win 7 hands in a row",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.winStreak or 0) >= 7 end,
  },
  {
    id = "blackjack_master",
    name = "Blackjack Master",
    description = "Get 5 blackjacks total",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.blackjacks or 0) >= 5 end,
  },
  {
    id = "blackjack_legend",
    name = "Blackjack Legend",
    description = "Get 20 blackjacks total",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.blackjacks or 0) >= 20 end,
  },
  {
    id = "suspicious_luck",
    name = "Suspicious Luck",
    description = "Get 3 blackjacks in a row (the dealer is watching you...)",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.consecutiveBlackjacks or 0) >= 3 end,
  },
  {
    id = "statistical_anomaly",
    name = "Statistical Anomaly",
    description = "Get 5 blackjacks in 10 consecutive hands",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s)
      return (s.gamesPlayed or 0) >= 10
             and ((s.blackjacks or 0) / (s.gamesPlayed or 1)) >= 0.5
    end,
  },
  {
    id = "royal_showdown",
    name = "Royal Showdown",
    description = "You and the dealer both get blackjack in the same hand",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.doubleBlackjacks or 0) >= 1 end,
  },
  {
    id = "twenty_one_club",
    name = "21 Club",
    description = "Get exactly 21 with 5 or more cards",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.fiveCard21s or 0) >= 1 end,
  },
  {
    id = "seven_card_charlie",
    name = "Seven-Card Charlie",
    description = "Win with 7 cards or more without busting",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.sevenCardCharlies or 0) >= 1 end,
  },
  {
    id = "rainbow_road",
    name = "Rainbow Road",
    description = "Win with every suit represented in your hand",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.rainbowWins or 0) >= 1 end,
  },
  {
    id = "soft_landing",
    name = "Soft Landing",
    description = "Win with a soft 21",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.soft21Wins or 0) >= 1 end,
  },
  {
    id = "nail_biter",
    name = "Nail-Biter",
    description = "Edge-out the dealer by exactly 1 point",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.edgeOutWins or 0) >= 1 end,
  },
  {
    id = "lucky_club",
    name = "Lucky Club",
    description = "Win holding 5 or more clubs",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.fiveClubWins or 0) >= 1 end,
  },
  {
    id = "houdini",
    name = "Houdini",
    description = "Start at 12 or below, take 3+ hits, land exactly 21 & win",
    category = CATEGORIES.FORTUNE,
    checkFunction = function(s) return (s.houdiniWins or 0) >= 1 end,
  },

  -- ===== MILESTONES =====
  {
    id = "high_roller",
    name = "High Roller",
    description = "Place a bet of at least 90 gold",
    category = CATEGORIES.MILESTONES,
    checkFunction = function(s) return (s.biggestBet or 0) >= 810 end,
  },
  {
    id = "whale_status",
    name = "Whale Status",
    description = "Place a bet of at least 500 gold",
    category = CATEGORIES.MILESTONES,
    checkFunction = function(s) return (s.biggestBet or 0) >= 4500 end,
  },
  {
    id = "silver_milestone",
    name = "Silver Milestone",
    description = "Win a total of 200 gold",
    category = CATEGORIES.MILESTONES,
    checkFunction = function(s) return (s.totalWinnings or 0) >= 1800 end,
  },
  {
    id = "gold_milestone",
    name = "Gold Milestone",
    description = "Win a total of 500 gold",
    category = CATEGORIES.MILESTONES,
    checkFunction = function(s) return (s.totalWinnings or 0) >= 4500 end,
  },
  {
    id = "platinum_milestone",
    name = "Platinum Milestone",
    description = "Win a total of 1000 gold",
    category = CATEGORIES.MILESTONES,
    checkFunction = function(s) return (s.totalWinnings or 0) >= 9000 end,
  },
  {
    id = "palladium_milestone",
    name = "Palladium Milestone",
    description = "Win a total of 5000 gold",
    category = CATEGORIES.MILESTONES,
    checkFunction = function(s) return (s.totalWinnings or 0) >= 45000 end,
  },
  {
    id = "vault_hunter",
    name = "Vault Hunter",
    description = "Win a total of 10000 gold",
    category = CATEGORIES.MILESTONES,
    checkFunction = function(s) return (s.totalWinnings or 0) >= 90000 end,
  },
  {
    id = "gold_digger",
    name = "Gold Digger",
    description = "Lifetime winnings reach 100 gold",
    category = CATEGORIES.MILESTONES,
    checkFunction = function(s) return (s.totalWinnings or 0) >= 900 end,
  },
  {
    id = "break_even",
    name = "Break-Even",
    description = "After 100+ hands your net profit is exactly 0 (within half a gold)",
    category = CATEGORIES.MILESTONES,
    checkFunction = function(s)
      return (s.gamesPlayed or 0) >= 100 and math.abs(s.netProfit or 0) < 5
    end,
  },

  -- ===== DEDICATION =====
  {
    id = "dedicated_player",
    name = "Dedicated Player",
    description = "Play 50 hands of blackjack",
    category = CATEGORIES.DEDICATION,
    checkFunction = function(s) return (s.gamesPlayed or 0) >= 50 end,
  },
  {
    id = "professional_gambler",
    name = "Professional Gambler",
    description = "Play 200 hands of blackjack",
    category = CATEGORIES.DEDICATION,
    checkFunction = function(s) return (s.gamesPlayed or 0) >= 200 end,
  },
  {
    id = "veteran_player",
    name = "Veteran Player",
    description = "Play 500 hands of blackjack",
    category = CATEGORIES.DEDICATION,
    checkFunction = function(s) return (s.gamesPlayed or 0) >= 500 end,
  },
  {
    id = "blackjack_legend_games",
    name = "Blackjack Legend",
    description = "Play 1000 hands of blackjack",
    category = CATEGORIES.DEDICATION,
    checkFunction = function(s) return (s.gamesPlayed or 0) >= 1000 end,
  },
  {
    id = "the_grinder",
    name = "The Grinder",
    description = "Maintain the same bet amount for 30 consecutive hands",
    category = CATEGORIES.DEDICATION,
    checkFunction = function(s) return (s.sameBetStreak or 0) >= 30 end,
  },
  {
    id = "the_marathon",
    name = "The Marathon",
    description = "Play 100 hands in a single session",
    category = CATEGORIES.DEDICATION,
    checkFunction = function(s) return (s.sessionHandsPlayed or 0) >= 100 end,
  },
  {
    id = "loyal_customer",
    name = "Loyal Customer",
    description = "Play blackjack on 7 different days",
    category = CATEGORIES.DEDICATION,
    checkFunction = function(s) return (s.uniqueDaysPlayed or 0) >= 7 end,
  },
  {
    id = "iron_resolve",
    name = "Iron Resolve",
    description = "Play 50 consecutive hands in one sitting",
    category = CATEGORIES.DEDICATION,
    checkFunction = function(s) return (s.sessionHandsPlayed or 0) >= 50 end,
  },
  {
    id = "penny_pincher",
    name = "Penny Pincher",
    description = "Win 10 straight hands betting 1 silver or less",
    category = CATEGORIES.DEDICATION,
    checkFunction = function(s) return (s.lowBetWinStreak or 0) >= 10 end,
  },
  {
    id = "devoted_gambler",
    name = "Devoted Gambler",
    description = "Stay at the table for 1 hour without exiting",
    category = CATEGORIES.DEDICATION,
    checkFunction = function(s) return (s.sessionTime or 0) >= 3600 end,
  },

  -- ===== RISK =====
  {
    id = "walking_the_edge",
    name = "Walking the Edge",
    description = "Win a hand after hitting on 16 or higher",
    category = CATEGORIES.RISK,
    checkFunction = function(s)
      if not s.actions or not s.actions.hit or not s.actions.hit.outcomes then return false end
      for handValue, outcomes in pairs(s.actions.hit.outcomes) do
        local val = tonumber(handValue)
        if val and val >= 16 and (outcomes.win or 0) > 0 then return true end
      end
      return false
    end,
  },
  {
    id = "fortune_favors_bold",
    name = "Fortune Favors the Bold",
    description = "Double down on a hand total of 6-8 and win",
    category = CATEGORIES.RISK,
    checkFunction = function(s)
      if not s.actions or not s.actions.double or not s.actions.double.outcomes then return false end
      for handValue, outcomes in pairs(s.actions.double.outcomes) do
        local val = tonumber(handValue)
        if val and val >= 6 and val <= 8 and (outcomes.win or 0) > 0 then return true end
      end
      return false
    end,
  },
  {
    id = "daredevil",
    name = "Daredevil",
    description = "Hit on 17 and win the hand",
    category = CATEGORIES.RISK,
    checkFunction = function(s)
      if not s.actions or not s.actions.hit or not s.actions.hit.outcomes
         or not s.actions.hit.outcomes[17] then
        return false
      end
      return (s.actions.hit.outcomes[17].win or 0) > 0
    end,
  },
  {
    id = "living_dangerously",
    name = "Living Dangerously",
    description = "Hit three times in a single hand without busting",
    category = CATEGORIES.RISK,
    checkFunction = function(s) return (s.tripleHitSuccess or 0) >= 1 end,
  },
  {
    id = "betting_it_all",
    name = "Betting It All",
    description = "Place the maximum allowed bet and win",
    category = CATEGORIES.RISK,
    checkFunction = function(s) return (s.maxBetWins or 0) >= 1 end,
  },
  {
    id = "against_all_odds",
    name = "Against All Odds",
    description = "Win after hitting on 19 or 20",
    category = CATEGORIES.RISK,
    checkFunction = function(s)
      if not s.actions or not s.actions.hit or not s.actions.hit.outcomes then return false end
      for handValue, outcomes in pairs(s.actions.hit.outcomes) do
        local val = tonumber(handValue)
        if val and val >= 19 and (outcomes.win or 0) > 0 then return true end
      end
      return false
    end,
  },
  {
    id = "calculated_risk",
    name = "Calculated Risk",
    description = "Win after losing 5 hands in a row without reducing your bet",
    category = CATEGORIES.RISK,
    checkFunction = function(s)
      return (s.loseStreak or 0) >= 5
             and (s.sameBetStreak or 0) >= 6
             and (s.wins or 0) > 0
    end,
  },
  {
    id = "shutout",
    name = "Shut-Out",
    description = "Dealer busts while you sit on 12 or less",
    category = CATEGORIES.RISK,
    checkFunction = function(s) return (s.shutoutWins or 0) >= 1 end,
  },
  {
    id = "risky_double",
    name = "Risky Double",
    description = "Double-down on exactly 9 and win",
    category = CATEGORIES.RISK,
    checkFunction = function(s) return (s.riskyDoubleWins or 0) >= 1 end,
  },
  {
    id = "overkill",
    name = "Overkill",
    description = "Hit on 20, draw an Ace, make 21 & win",
    category = CATEGORIES.RISK,
    checkFunction = function(s) return (s.overkillWins or 0) >= 1 end,
  },

  -- ===== STRATEGY =====
  {
    id = "consistent_better",
    name = "Consistent Better",
    description = "Maintain an average bet of at least 20 gold",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s)
      return (s.gamesPlayed or 0) >= 10 and (s.averageBet or 0) >= 180
    end,
  },
  {
    id = "comeback_king",
    name = "Comeback King",
    description = "Win after being down 100 gold",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s)
      return (s.lowestNetProfit or 0) <= -900 and (s.netProfit or 0) >= 0
    end,
  },
  {
    id = "phoenix_gambler",
    name = "Phoenix Gambler",
    description = "Recover from a net loss of 300+ gold to a net profit",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s)
      return (s.lowestNetProfit or 0) <= -2700 and (s.netProfit or 0) > 0
    end,
  },
  {
    id = "risk_reward_specialist",
    name = "Risk/Reward Specialist",
    description = "Win 10 hands with a bet at least 2x your average bet",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s)
      return (s.biggestBet or 0) >= ((s.averageBet or 0) * 2) and (s.wins or 0) >= 10
    end,
  },
  {
    id = "efficient_gambler",
    name = "Efficient Gambler",
    description = "Maintain an ROI of 30%+ over 25+ hands",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s)
      if not s.totalBet or s.totalBet == 0 or (s.gamesPlayed or 0) < 25 then return false end
      local roi = ((s.totalWinnings or 0) - s.totalBet) / s.totalBet * 100
      return roi >= 30
    end,
  },
  {
    id = "soft_hand_master",
    name = "Soft Hand Master",
    description = "Win 5 times with a soft hand (containing an Ace counted as 11)",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s) return (s.softHandWins or 0) >= 5 end,
  },
  {
    id = "martingale_master",
    name = "Martingale Master",
    description = "Double your bet after a loss and win the next hand - 3 times",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s) return (s.betDoublingWins or 0) >= 3 end,
  },
  {
    id = "disciplined_player",
    name = "Disciplined Player",
    description = "Maintain the same bet for 10 consecutive hands regardless of outcome",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s) return (s.sameBetStreak or 0) >= 10 end,
  },
  {
    id = "probability_master",
    name = "Probability Master",
    description = "Maintain a win rate of at least 60% over 10+ hands",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s)
      return (s.gamesPlayed or 0) >= 10
             and ((s.wins or 0) / (s.gamesPlayed or 1)) >= 0.6
    end,
  },
  {
    id = "snap_decision",
    name = "Snap Decision",
    description = "All decisions in a hand took < 0.5 s and you won",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s) return (s.snapDecisionWins or 0) >= 1 end,
  },
  {
    id = "slow_burn",
    name = "Slow Burn",
    description = "Every decision took > 15 s yet you still won",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s) return (s.slowBurnWins or 0) >= 1 end,
  },
  {
    id = "stonewall",
    name = "Stonewall",
    description = "Stand on 12 or less and finish in a push",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s) return (s.stonewallPushes or 0) >= 1 end,
  },
  {
    id = "no_time_to_think",
    name = "No-Time-to-Think",
    description = "Entire winning hand resolved in < 6 s",
    category = CATEGORIES.STRATEGY,
    checkFunction = function(s) return (s.quickHandWins or 0) >= 1 end,
  },

  -- ===== MATHEMATICAL =====
  {
    id = "mathematical_precision",
    name = "Mathematical Precision",
    description = "End with a net profit that's a perfect square number of gold",
    category = CATEGORIES.MATHEMATICAL,
    checkFunction = function(s)
      if not s.netProfit or s.netProfit <= 0 or (s.gamesPlayed or 0) < 10 then return false end
      local netGold = math.floor(s.netProfit / 9)
      local sqrt = math.sqrt(netGold)
      return netGold > 0 and math.floor(sqrt) == sqrt
    end,
  },
  {
    id = "golden_ratio",
    name = "Golden Ratio",
    description = "Achieve exactly 1.618x your total bets in winnings",
    category = CATEGORIES.MATHEMATICAL,
    checkFunction = function(s)
      if not s.totalWinnings or not s.totalBet or s.totalBet == 0
         or (s.gamesPlayed or 0) < 30 then
        return false
      end
      local ratio = s.totalWinnings / s.totalBet
      return ratio >= 1.61 and ratio <= 1.63
    end,
  },
  {
    id = "fibonacci_fortune",
    name = "Fibonacci Fortune",
    description = "Win exactly a Fibonacci number in gold (8, 13, 21, 34, 55...)",
    category = CATEGORIES.MATHEMATICAL,
    checkFunction = function(s)
      if not s.totalWinnings or (s.wins or 0) < 5 then return false end
      local winGold = math.floor(s.totalWinnings / 9)
      return winGold > 5 and isFibonacci(winGold)
    end,
  },
  {
    id = "perfect_symmetry",
    name = "Perfect Symmetry",
    description = "Achieve equal numbers of wins and losses (10+ each)",
    category = CATEGORIES.MATHEMATICAL,
    checkFunction = function(s)
      return (s.wins or 0) >= 10 and (s.wins or 0) == (s.losses or 0)
    end,
  },
  {
    id = "prime_player",
    name = "Prime Player",
    description = "Win a prime number amount of gold (23, 29, 31, 37, 41...)",
    category = CATEGORIES.MATHEMATICAL,
    checkFunction = function(s)
      if not s.netProfit or s.netProfit <= 0 then return false end
      local netGold = math.floor(s.netProfit / 9)
      return netGold > 19 and isPrime(netGold)
    end,
  },
  {
    id = "perfect_21",
    name = "Perfect 21",
    description = "Get exactly 21 points from exactly 3 cards",
    category = CATEGORIES.MATHEMATICAL,
    checkFunction = function(s)
      return s.cards and s.cards.twentyOneWith
             and (s.cards.twentyOneWith["3cards"] or 0) > 0
    end,
  },

  -- ===== HUMOROUS =====
  {
    id = "perfectly_balanced",
    name = "Perfectly Balanced",
    description = "End a session of 20+ hands with exactly 0 net profit",
    category = CATEGORIES.HUMOROUS,
    checkFunction = function(s)
      return (s.gamesPlayed or 0) >= 20 and (s.netProfit or 0) == 0
    end,
  },
  {
    id = "casino_employee",
    name = "Casino Employee",
    description = "Play blackjack for at least 8 hours total",
    category = CATEGORIES.HUMOROUS,
    checkFunction = function(s) return (s.totalPlayTime or 0) >= 28800 end,
  },
  {
    id = "suspicious_timing",
    name = "Suspicious Timing",
    description = "Play blackjack at exactly midnight",
    category = CATEGORIES.HUMOROUS,
    checkFunction = function(s)
      return s.timing and s.timing.startTimes
             and (s.timing.startTimes[0] or 0) > 0
    end,
  },
  {
    id = "cant_decide",
    name = "Can't Decide",
    description = "Take more than 30 seconds to make a decision",
    category = CATEGORIES.HUMOROUS,
    checkFunction = function(s)
      if not s.timing or not s.timing.decisionTimes then return false end
      for _, t in ipairs(s.timing.decisionTimes) do
        if t > 30 then return true end
      end
      return false
    end,
  },
  {
    id = "number_of_the_beast",
    name = "Number of the Beast",
    description = "Lose exactly 666 silver in a single hand",
    category = CATEGORIES.HUMOROUS,
    checkFunction = function(s) return (s.lost666 or 0) >= 1 end,
  },
  {
    id = "cold_snap",
    name = "Cold Snap",
    description = "Lose 5 in a row",
    category = CATEGORIES.HUMOROUS,
    checkFunction = function(s) return (s.loseStreak or 0) >= 5 end,
  },
  {
    id = "crimson_cascade",
    name = "Crimson Cascade",
    description = "Lose a hand that contained only red cards",
    category = CATEGORIES.HUMOROUS,
    checkFunction = function(s) return (s.redCardsLoss or 0) >= 1 end,
  },

  -- ===== DEALER =====
  {
    id = "dealer_buster",
    name = "Dealer Buster",
    description = "Win 5 hands where the dealer busts",
    category = CATEGORIES.DEALER,
    checkFunction = function(s) return (s.dealerBustWins or 0) >= 5 end,
  },
  {
    id = "even_stevens",
    name = "Even Stevens",
    description = "Push with the dealer 5 times",
    category = CATEGORIES.DEALER,
    checkFunction = function(s) return (s.pushes or 0) >= 5 end,
  },
  {
    id = "ace_hunter",
    name = "Ace Hunter",
    description = "Win 3 hands against a dealer showing an Ace",
    category = CATEGORIES.DEALER,
    checkFunction = function(s)
      if not s.dealer or not s.dealer.upCardOutcomes
         or not s.dealer.upCardOutcomes["A"] then
        return false
      end
      return (s.dealer.upCardOutcomes["A"].win or 0) >= 3
    end,
  },
  {
    id = "face_off",
    name = "Face Off",
    description = "Win 5 hands against a dealer showing a face card (J, Q, K)",
    category = CATEGORIES.DEALER,
    checkFunction = function(s)
      if not s.dealer or not s.dealer.upCardOutcomes then return false end
      local jw = (s.dealer.upCardOutcomes["J"] or {}).win or 0
      local qw = (s.dealer.upCardOutcomes["Q"] or {}).win or 0
      local kw = (s.dealer.upCardOutcomes["K"] or {}).win or 0
      return jw + qw + kw >= 5
    end,
  },
  {
    id = "ten_hunter",
    name = "Ten Hunter",
    description = "Win 5 hands against a dealer showing a 10",
    category = CATEGORIES.DEALER,
    checkFunction = function(s)
      if not s.dealer or not s.dealer.upCardOutcomes
         or not s.dealer.upCardOutcomes["T"] then
        return false
      end
      return (s.dealer.upCardOutcomes["T"].win or 0) >= 5
    end,
  },
  {
    id = "mirror_match",
    name = "Mirror Match",
    description = "Push where score and card-count match the dealer exactly",
    category = CATEGORIES.DEALER,
    checkFunction = function(s) return (s.mirrorMatches or 0) >= 1 end,
  },
  {
    id = "streak_breaker",
    name = "Streak Breaker",
    description = "Push that ends a 4-hand win or loss streak",
    category = CATEGORIES.DEALER,
    checkFunction = function(s) return (s.streakBreakers or 0) >= 1 end,
  },

  -- ===== SUPERSTITION =====
  {
    id = "lucky_number_seven",
    name = "Lucky Number Seven",
    description = "Win a hand with a 7 in it",
    category = CATEGORIES.SUPERSTITION,
    checkFunction = function(s) return (s.wonWithSeven or 0) >= 1 end,
  },
  {
    id = "unlucky_thirteen",
    name = "Unlucky Thirteen",
    description = "Lose a hand with a total of 13",
    category = CATEGORIES.SUPERSTITION,
    checkFunction = function(s)
      if not s.actions or not s.actions.stand or not s.actions.stand.outcomes
         or not s.actions.stand.outcomes[13] then
        return false
      end
      return (s.actions.stand.outcomes[13].loss or 0) > 0
    end,
  },
  {
    id = "black_cat",
    name = "Black Cat",
    description = "Win a hand with only black cards (clubs and spades)",
    category = CATEGORIES.SUPERSTITION,
    checkFunction = function(s) return (s.blackCardWins or 0) >= 1 end,
  },
  {
    id = "red_inferno",
    name = "Red Inferno",
    description = "Win a hand with only red cards (hearts and diamonds)",
    category = CATEGORIES.SUPERSTITION,
    checkFunction = function(s) return (s.redCardWins or 0) >= 1 end,
  },
  {
    id = "four_leaf_clover",
    name = "Four-Leaf Clover",
    description = "Win a hand with exactly 4 clubs",
    category = CATEGORIES.SUPERSTITION,
    checkFunction = function(s) return (s.fourClubWins or 0) >= 1 end,
  },

  -- ===== SEASONAL =====
  {
    id = "midnight_gambler",
    name = "Midnight Gambler",
    description = "Play blackjack between 11 PM and 1 AM",
    category = CATEGORIES.SEASONAL,
    checkFunction = function(s)
      if not s.timing or not s.timing.startTimes then return false end
      return (s.timing.startTimes[23] or 0) > 0
             or (s.timing.startTimes[0] or 0) > 0
             or (s.timing.startTimes[1] or 0) > 0
    end,
  },
  {
    id = "early_bird",
    name = "Early Bird",
    description = "Play blackjack between 5 AM and 7 AM",
    category = CATEGORIES.SEASONAL,
    checkFunction = function(s)
      if not s.timing or not s.timing.startTimes then return false end
      return (s.timing.startTimes[5] or 0) > 0
             or (s.timing.startTimes[6] or 0) > 0
    end,
  },
  {
    id = "weekend_warrior",
    name = "Weekend Warrior",
    description = "Play blackjack on Friday night or Saturday",
    category = CATEGORIES.SEASONAL,
    checkFunction = function(s) return (s.playedOnWeekend or 0) >= 1 end,
  },

  -- ===== SPECIAL =====
  {
    id = "against_the_house",
    name = "Against the House",
    description = "Win 100,000 gold total from the casino",
    category = CATEGORIES.SPECIAL,
    checkFunction = function(s) return (s.totalWinnings or 0) >= 900000 end,
  },
  {
    id = "blackjack_billionaire",
    name = "Blackjack Billionaire",
    description = "Achieve a net profit of 50,000 gold",
    category = CATEGORIES.SPECIAL,
    checkFunction = function(s) return (s.netProfit or 0) >= 450000 end,
  },
  {
    id = "legendary_luck",
    name = "Legendary Luck",
    description = "Get 7 blackjacks in a single session",
    category = CATEGORIES.SPECIAL,
    checkFunction = function(s) return (s.sessionBlackjacks or 0) >= 7 end,
  },
  {
    id = "oracle",
    name = "The Oracle",
    description = "Win 15 hands in a row",
    category = CATEGORIES.SPECIAL,
    checkFunction = function(s) return (s.winStreak or 0) >= 15 end,
  },
  {
    id = "perfect_pair",
    name = "Perfect Pair",
    description = "Split once & both split hands beat the dealer",
    category = CATEGORIES.SPECIAL,
    checkFunction = function(s) return (s.perfectPairs or 0) >= 1 end,
  },
  {
    id = "twin_blackjacks",
    name = "Twin Blackjacks",
    description = "Split A-A, both hands are blackjack",
    category = CATEGORIES.SPECIAL,
    checkFunction = function(s) return (s.twinBlackjacks or 0) >= 1 end,
  },
  {
    id = "bankbuster",
    name = "Bank-Buster",
    description = "Payout drains the house below 10% of its opening silver",
    category = CATEGORIES.SPECIAL,
    checkFunction = function(s) return (s.bankBuster or 0) >= 1 end,
  },
  {
    id = "comeback_kid",
    name = "Comeback Kid",
    description = "Win immediately after 3 straight losses",
    category = CATEGORIES.SPECIAL,
    checkFunction = function(s) return (s.comebackKidWins or 0) >= 1 end,
  },
  {
    id = "quad_aces",
    name = "Ace Quartet",
    description = "Four Aces, still standing",
    category = CATEGORIES.SPECIAL,
    checkFunction = function(s) return (s.quadAceWins or 0) >= 1 end,
  },
  {
    id = "precision_split",
    name = "Precision Split",
    description = "Split 8-8, both hands finish on 21 & win",
    category = CATEGORIES.SPECIAL,
    checkFunction = function(s) return (s.precisionSplits or 0) >= 1 end,
  },
}

-----------------------------------------------------
-- Achievement Check Engine
-----------------------------------------------------

--- Check all achievements for a player and unlock any newly earned ones.
-- @param stats table  The player stats table (must include .achievements)
-- @return table  Array of newly unlocked achievement entries
local function checkAchievements(stats)
  if not stats or not stats.achievements then return {} end

  local newlyUnlocked = {}

  for _, achievement in ipairs(ACHIEVEMENTS) do
    if not stats.achievements[achievement.id] then
      local ok, earned = pcall(achievement.checkFunction, stats)
      if not ok then
        playerStats.writeLog("Error checking achievement " .. achievement.id .. ": " .. tostring(earned))
      elseif earned then
        stats.achievements[achievement.id] = os.day()
        table.insert(newlyUnlocked, achievement)
        playerStats.writeLog((stats.playerName or "?") .. " earned: " .. achievement.name)
      end
    end
  end

  if #newlyUnlocked > 0 then
    playerStats.savePlayerStats(stats.playerName, stats)
  end

  return newlyUnlocked
end

return {
  CATEGORIES        = CATEGORIES,
  ACHIEVEMENTS      = ACHIEVEMENTS,
  checkAchievements = checkAchievements,
}
