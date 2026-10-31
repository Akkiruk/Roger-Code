-- crazyeights_test.lua

local deck = require("lib.casino.deck")
local rules = require("crazyeights_rules")
local view = require("crazyeights_view")
local t = require("testing")

local function cards(names)
  local list = {}
  for i, name in ipairs(names) do list[i] = deck.parse(name) end
  return list
end

--- A hand set up by name. Every card not named goes in the stock, shuffled by the fixed generator.
local function rigged(spec)
  local rng = t.fastRng(spec.seed or 4)
  local state = rules.new(spec.bet or 100, rng, {}, {})
  state.player = cards(spec.player)
  state.dealer = cards(spec.dealer)
  state.pile = cards(spec.pile or { "5D" })
  state.suit = spec.suit or deck.suit(state.pile[#state.pile])
  state.pending = spec.pending or 0
  local used = {}
  for _, list in ipairs({ state.player, state.dealer, state.pile }) do
    for _, card in ipairs(list) do used[card] = true end
  end
  state.stock = {}
  for card = 0, 51 do
    if not used[card] then state.stock[#state.stock + 1] = card end
  end
  deck.shuffle(state.stock, rng)
  if spec.stock then
    for i, name in ipairs(spec.stock) do
      local wanted = deck.parse(name)
      for j, card in ipairs(state.stock) do
        if card == wanted then table.remove(state.stock, j) end
      end
      state.stock[#state.stock + 1] = wanted
      local _ = i
    end
  end
  return state, rng
end

local function has(list, card)
  for _, value in ipairs(list) do
    if value == card then return true end
  end
  return false
end

local function play(name)
  return "p" .. deck.parse(name)
end

--- Every card in the game, once.
local function checkDeck(state, what)
  local seen = {}
  local total = 0
  for _, name in ipairs({ "stock", "pile", "player", "dealer" }) do
    for _, card in ipairs(state[name]) do
      t.truthy(not seen[card], (what or "") .. " card twice " .. deck.name(card))
      seen[card] = true
      total = total + 1
    end
  end
  t.eq(total, 52, what)
end

-- ------------------------------------------------------------------ rules

t.test("a deal is seven each, one on the pile, and never starts on a wild or a 2", function()
  local rng = t.fastRng(1)
  for _ = 1, 3000 do
    local state = rules.new(10, rng, {}, {})
    t.eq(#state.player, 7)
    t.eq(#state.dealer, 7)
    local rank = deck.rank(rules.top(state))
    t.truthy(rank ~= 8 and rank ~= 2, "first card")
    t.eq(state.suit, deck.suit(rules.top(state)))
    checkDeck(state, "deal")
  end
end)

t.test("a card plays on its suit or rank, and an 8 on anything", function()
  local state = rigged({ player = { "5S", "9D", "8C", "KH" }, dealer = { "3C" }, pile = { "5D" } })
  t.truthy(rules.canPlay(state, deck.parse("5S")), "rank")
  t.truthy(rules.canPlay(state, deck.parse("9D")), "suit")
  t.truthy(rules.canPlay(state, deck.parse("8C")), "wild")
  t.truthy(not rules.canPlay(state, deck.parse("KH")), "neither")
end)

t.test("after a wild only the named suit follows, or another 8", function()
  local state = rigged({ player = { "5H", "9D", "8C", "KS" }, dealer = { "3C", "4C", "5C" }, pile = { "8D" }, suit = 2 })
  t.truthy(rules.canPlay(state, deck.parse("5H")), "named suit")
  t.truthy(not rules.canPlay(state, deck.parse("9D")), "the card's own suit is not in force")
  t.truthy(not rules.canPlay(state, deck.parse("KS")))
  t.truthy(rules.canPlay(state, deck.parse("8C")), "8 on 8")
end)

t.test("a wild asks for a suit, and BACK changes your mind", function()
  local state, rng = rigged({ player = { "8C", "KS", "4H" }, dealer = { "3C", "4C", "5C" }, pile = { "5D" } })
  rules.act(state, play("8C"), rng)
  t.eq(state.choosing, deck.parse("8C"))
  t.eq(#state.player, 3, "not played yet")
  t.eq(rules.actions(state)[1].id, "back")
  rules.act(state, "back", rng)
  t.eq(state.choosing, nil)
  rules.act(state, play("8C"), rng)
  rules.act(state, "suit2", rng)
  t.eq(#state.player, 2, "played")
  t.truthy(rules.top(state) ~= nil)
end)

t.test("a last-card 8 wins at once with no suit prompt", function()
  local state, rng = rigged({ player = { "8C" }, dealer = { "3C", "4C", "5C" }, pile = { "5D" } })
  local events = rules.act(state, play("8C"), rng)
  t.eq(state.choosing, nil, "no prompt")
  t.truthy(rules.done(state))
  t.eq(state.winner, "player")
  t.eq(rules.net(state), rules.maxWin(100))
  t.eq(events[#events].type, "reveal", "the dealer's cards are turned over")
  t.eq(#events[#events].cards, 3)
end)

t.test("a last-card 2 wins at once and the dealer draws nothing", function()
  local state, rng = rigged({ player = { "2D" }, dealer = { "3C", "4C" }, pile = { "5D" } })
  rules.act(state, play("2D"), rng)
  t.truthy(rules.done(state))
  t.eq(state.winner, "player")
  t.eq(#state.dealer, 2)
end)

t.test("a 2 makes the dealer draw two, and the turn comes back", function()
  local state, rng = rigged({ player = { "2D", "KS", "QS" }, dealer = { "3C", "4C", "6H" }, pile = { "5D" } })
  rules.act(state, play("2D"), rng)
  t.eq(#state.dealer, 5, "dealer took two")
  t.eq(state.pending, 0)
  t.truthy(not rules.done(state))
end)

t.test("a 2 answers a 2, and the stack grows", function()
  local state, rng = rigged({ player = { "2D", "KS", "QS" }, dealer = { "2C", "4C", "6H" }, pile = { "5D" } })
  rules.act(state, play("2D"), rng)
  t.eq(#state.dealer, 2, "dealer answered with its 2")
  t.eq(state.pending, 4, "stack at 4")
  t.eq(rules.actions(state)[1].label, "TAKE 4")
end)

t.test("an 8 does not answer a draw stack", function()
  local state = rigged({ player = { "8C", "KS" }, dealer = { "3C" }, pile = { "2D" }, pending = 2 })
  t.truthy(not rules.canPlay(state, deck.parse("8C")))
  t.eq(#rules.legal(state, "player"), 0)
end)

t.test("the stack stops at the cap: no fourth 2 can be played", function()
  local state = rigged({ player = { "2S", "KS" }, dealer = { "3C" }, pile = { "2D", "2C", "2H" }, pending = rules.CAP })
  t.eq(rules.CAP, 6)
  t.truthy(not rules.canPlay(state, deck.parse("2S")), "capped")
  local below = rigged({ player = { "2S", "KS" }, dealer = { "3C" }, pile = { "2D", "2C" }, pending = 4 })
  t.truthy(rules.canPlay(below, deck.parse("2S")), "room for one more")
end)

t.test("taking a stack draws all of it, ends the turn, and clears it", function()
  local state, rng = rigged({ player = { "KS" }, dealer = { "3C", "9H", "JH" }, pile = { "2D", "2C", "2H" }, pending = 6 })
  rules.act(state, "draw", rng)
  t.eq(#state.player, 7)
  t.eq(state.pending, 0)
  t.truthy(not rules.done(state))
end)

t.test("DRAW is always there, whatever the hand holds", function()
  local cases = {
    rigged({ player = { "5H" }, dealer = { "3C" }, pile = { "5D" } }),               -- something to play
    rigged({ player = { "KH" }, dealer = { "3C" }, pile = { "5D" } }),               -- nothing to play
    rigged({ player = { "8H" }, dealer = { "3C" }, pile = { "5D" } }),               -- only a wild
    rigged({ player = { "KH" }, dealer = { "3C" }, pile = { "2D" }, pending = 2 }),  -- a stack
    (rigged({ player = { "2H" }, dealer = { "3C" }, pile = { "2D" }, pending = 2 })), -- a stack and an answer
  }
  for i, state in ipairs(cases) do
    t.eq(rules.actions(state)[1].id, "draw", "case " .. i)
  end
end)

t.test("drawing takes one card and ends the turn even if it could be played", function()
  local state, rng = rigged({ player = { "5H" }, dealer = { "KC", "QC", "JC" }, pile = { "5D" }, stock = { "9D" } })
  rules.act(state, "draw", rng)
  t.truthy(has(state.player, deck.parse("9D")), "drew the 9")
  t.eq(#state.player, 2)
end)

t.test("an empty stock takes the pile back, keeping the top card", function()
  local state, rng = rigged({ player = { "KH" }, dealer = { "3C", "9C", "JC" }, pile = { "5D" } })
  state.pile = {}
  for _, card in ipairs(state.stock) do state.pile[#state.pile + 1] = card end
  state.pile[#state.pile + 1] = deck.parse("5D")
  state.stock = {}
  local events = rules.act(state, "draw", rng)
  t.eq(rules.top(state), deck.parse("5D"), "top card stays")
  checkDeck(state, "after a reshuffle")
  t.eq(events[1].type, "reshuffle")
end)

t.test("nothing to draw and nothing to play: the hand ends and the fewer cards wins", function()
  local state, rng = rigged({ player = { "KH" }, dealer = { "3C", "9C" }, pile = { "5D" } })
  state.stock = {}
  t.eq(rules.actions(state)[1].label, "PASS")
  rules.act(state, "draw", rng)
  t.truthy(rules.done(state), "two passes end it")
  t.eq(state.winner, "player")
  t.eq(state.ended, "blocked")
  t.eq(rules.result(state).kind, "win")
end)

t.test("equal hands at a block push, and the bet comes back", function()
  local state, rng = rigged({ player = { "KH" }, dealer = { "3C" }, pile = { "5D" } })
  state.stock = {}
  rules.act(state, "draw", rng)
  t.eq(state.winner, "push")
  t.eq(rules.net(state), 0)
  t.eq(rules.result(state).kind, "push")
end)

t.test("a hand that runs too long is called on the cards held", function()
  local state, rng = rigged({ player = { "KH", "QH" }, dealer = { "3C" }, pile = { "5D" } })
  state.turns = rules.MAX_TURNS - 1
  rules.act(state, "draw", rng)
  t.truthy(rules.done(state))
  t.eq(state.ended, "long")
  t.eq(state.winner, "dealer")
end)

t.test("a win pays floor(bet * (pay - 1)) at every size, with nothing special for small bets", function()
  for _, bet in ipairs({ 1, 2, 3, 5, 7, 10, 25, 99, 100, 1000, 12345 }) do
    local state, rng = rigged({ player = { "5H" }, dealer = { "3C" }, pile = { "5D" }, bet = bet })
    rules.act(state, play("5H"), rng)
    local cents = math.floor(rules.PAY * 100 + 0.5) - 100
    t.eq(rules.net(state), math.floor(bet * cents / 100), "bet " .. bet)
    t.truthy(rules.net(state) < bet, "never even money or better")
    t.eq(rules.maxWin(bet), rules.net(state))
  end
end)

t.test("a loss costs the bet", function()
  local state, rng = rigged({ player = { "KH", "QH" }, dealer = { "5C" }, pile = { "5D" } })
  rules.act(state, "draw", rng)
  t.eq(state.winner, "dealer")
  t.eq(rules.net(state), -100)
end)

t.test("a card that cannot be played, or is not held, does nothing", function()
  local state, rng = rigged({ player = { "KH", "5H" }, dealer = { "3C", "4C" }, pile = { "5D" } })
  t.eq(#rules.act(state, play("KH"), rng), 0, "illegal")
  t.eq(#rules.act(state, play("AS"), rng), 0, "not held")
  t.eq(#rules.act(state, "nonsense", rng), 0, "not an action")
  t.eq(#state.player, 2)
end)

t.test("state serializes to plain data with no shared tables", function()
  local rng = t.fastRng(8)
  local state, events = rules.new(50, rng, {}, {})
  local seen = {}
  local function walk(value, path)
    t.truthy(type(value) ~= "function", path)
    if type(value) == "table" then
      t.truthy(not seen[value], "shared table at " .. path)
      seen[value] = true
      for k, v in pairs(value) do walk(v, path .. "." .. tostring(k)) end
    end
  end
  walk(state, "state")
  t.truthy(events[1].player ~= state.player, "events copy the hand")
end)

-- ------------------------------------------------------------------ the dealer

t.test("the dealer keeps its 8 while anything else can go", function()
  local state = rigged({ player = { "KH", "QH", "JH" }, dealer = { "8C", "5S", "KC", "QC" }, pile = { "5D" } })
  t.eq(rules.think(state, "dealer"), deck.parse("5S"))
end)

t.test("the dealer goes out when it can", function()
  local state = rigged({ player = { "KH", "QH", "JH" }, dealer = { "8C" }, pile = { "5D" } })
  t.eq(rules.think(state, "dealer"), deck.parse("8C"))
end)

t.test("the dealer names the suit it holds most of", function()
  local state = rigged({ player = { "KH", "QH", "JH", "9H" }, dealer = { "8C", "KS", "QS", "JS", "3H" }, pile = { "5D" } })
  local card, suit = rules.think(state, "dealer")
  t.eq(card, deck.parse("8C"), "only the 8 can go")
  t.eq(suit, deck.SPADES)
end)

t.test("the dealer hands a stack back with a 2", function()
  local state = rigged({ player = { "KH" }, dealer = { "2S", "KS" }, pile = { "2D" }, pending = 2 })
  t.eq(rules.think(state, "dealer"), deck.parse("2S"))
end)

t.test("the dealer chains its long suit", function()
  -- 7S changes to spades, where it holds four more. 7D would stay on a suit it then has none of.
  local state = rigged({ player = { "KH", "QH", "JH", "9H", "4C" }, dealer = { "7D", "7S", "KS", "QS", "JS", "10S" }, pile = { "7H" } })
  t.eq(rules.think(state, "dealer"), deck.parse("7S"))
end)

t.test("the dealer never reads your hand or the stock", function()
  -- Same counts, different hidden cards: the same choice, whatever is hidden
  local rng = t.fastRng(77)
  for _ = 1, 500 do
    local state = rules.new(10, rng, {}, {})
    for _ = 1, rng:below(10) do
      if rules.done(state) then break end
      rules.act(state, rules.auto(state), rng)
    end
    if not rules.done(state) and not state.choosing then
      local card, suit = rules.think(state, "dealer")
      local hidden = {}
      for _, value in ipairs(state.player) do hidden[#hidden + 1] = value end
      for _, value in ipairs(state.stock) do hidden[#hidden + 1] = value end
      deck.shuffle(hidden, rng)
      local n = #state.player
      for i = 1, n do state.player[i] = hidden[i] end
      for i = 1, #state.stock do state.stock[i] = hidden[n + i] end
      local again, againSuit = rules.think(state, "dealer")
      t.eq(again, card, "same card")
      t.eq(againSuit, suit, "same suit")
    end
  end
end)

-- ------------------------------------------------------------------ whole hands

--- Plays any legal move at random, so the odd corners get visited.
local function randomPlay(rng)
  return function(state)
    if state.choosing then return "suit" .. rng:below(4) end
    local moves = rules.legal(state, "player")
    if #moves == 0 or rng:below(5) == 0 then return "draw" end
    return "p" .. moves[rng:below(#moves) + 1]
  end
end

--- A good human's plan: spend the long suit, keep 8s for last, hit a nearly empty hand with 2s.
local function heuristic(state)
  if state.choosing then return "suit" .. rules.bestSuit(state, "player", state.choosing) end
  local moves = rules.legal(state, "player")
  if #moves == 0 then return "draw" end
  local counts = { 0, 0, 0, 0 }
  for _, card in ipairs(state.player) do counts[deck.suit(card) + 1] = counts[deck.suit(card) + 1] + 1 end
  local best, bestValue = nil, -math.huge
  for _, card in ipairs(moves) do
    local value = counts[deck.suit(card) + 1]
    if deck.rank(card) == 8 then value = value - 50 end
    if deck.rank(card) == 2 then value = value + (#state.dealer <= 3 and 20 or 2) end
    if value > bestValue then best, bestValue = card, value end
  end
  return "p" .. best
end

local HANDS = 20000

t.test("20000 hands end by themselves, with the deck whole and no hand stuck", function()
  local rng = t.fastRng(2024)
  local chooser = randomPlay(rng)
  local most = 0
  for i = 1, HANDS do
    local state = rules.new(100, rng, {}, {})
    local steps = 0
    while not rules.done(state) do
      -- Every moment of every hand offers the player a way on
      if not state.choosing then
        t.truthy(#rules.actions(state) > 0, "no action offered")
      end
      local id = i % 2 == 0 and rules.auto(state) or chooser(state)
      local card = tonumber((id:match("^p(%d+)$")))
      if card then t.truthy(rules.canPlay(state, card), "a legal move") end
      rules.act(state, id, rng)
      steps = steps + 1
      t.truthy(steps < 2 * rules.MAX_TURNS + 10, "a hand that will not end")
    end
    most = math.max(most, state.turns)
    t.truthy(state.winner ~= nil, "no winner")
    if i % 250 == 0 then
      checkDeck(state, "after hand " .. i)
      t.breathe()
    end
  end
  t.truthy(most <= rules.MAX_TURNS, "turn limit")
end)

local function record(name, value)
  print(("     %s: %.4f"):format(name, value))
end

t.test("the dealer outplays simple strategies", function()
  local rng = t.fastRng(31)
  local chooser = randomPlay(rng)
  local returns = t.simulate(rules, 8000, 100, chooser, 41)
  record("random player return", returns)
  t.truthy(returns < 0.7, "random play is punished")
  local plain = t.simulate(rules, 8000, 100, heuristic, 42)
  record("simple heuristic return", plain)
  t.truthy(plain < 0.95, "a sensible heuristic stays well below even")
end)

t.test("the dealer's own plan, played first, stays under the target return", function()
  local returns = t.simulate(rules, HANDS, 100, function(state) return rules.auto(state) end, 43)
  record("dealer's plan played first, return", returns)
  t.truthy(returns < 0.98, "strong play returns under 98%")
  t.truthy(returns > 0.9, "and it is still a game worth playing")
end)

t.test("the strongest plan found against this dealer still loses", function()
  -- Found by searching the dealer's own weights for what beats it, then confirmed on 100000 fresh hands: 51.8% wins
  local strong = {}
  for name, weight in pairs(rules.AI) do strong[name] = weight end
  strong.pressure, strong.holdWild = 12.74, 5
  local real = rules.AI
  local function plan(state)
    rules.AI = strong
    local id = rules.auto(state)
    rules.AI = real
    return id
  end
  local returns = t.simulate(rules, HANDS, 100, plan, 44)
  record("strongest plan return", returns)
  t.truthy(returns < 1, "under 100%")
  t.truthy(returns < 0.985, "about 97-98% at most")
end)

-- ------------------------------------------------------------------ the view

local function fakeModel(state)
  local model = view.new({ c = { w = 121, h = 81 } })
  view.sync(model, state)
  return model
end

t.test("every card keeps a wide target at any hand size, on the wall and above the banner", function()
  for n = 1, 40 do
    local hand = {}
    for card = 0, 51 do
      if #hand < n and deck.rank(card) ~= 8 then hand[#hand + 1] = card end
    end
    -- Every card made legal: a stack is the one state that says yes to 2s only, so use a pile-wide wild test instead
    local state = rigged({ player = { "KH" }, dealer = { "3C" }, pile = { "5D" } })
    state.player = hand
    local pages = math.ceil(n / rules.PAGE)
    for page = 0, pages - 1 do
      state.page = page
      state.suit = 0
      for _, region in ipairs(view.regions(fakeModel(state), state)) do
        if region.id:sub(1, 1) == "p" and tonumber(region.id:sub(2)) then
          t.truthy(region.w >= view.MIN_STRIP, n .. " cards: strip " .. region.w)
          t.truthy(region.x >= 1 and region.x + region.w - 1 <= 121, "on the wall")
          t.truthy(region.y + region.h - 1 <= 55, "above the banner")
        end
      end
    end
  end
end)

t.test("the page arrows reach every card", function()
  local hand = {}
  for card = 0, 28 do hand[#hand + 1] = card end
  local state, rng = rigged({ player = { "KH" }, dealer = { "3C" }, pile = { "5D" } })
  state.player = hand
  local ids = {}
  local function pageIds()
    local out = {}
    for _, region in ipairs(view.regions(fakeModel(state), state)) do out[region.id] = true end
    return out
  end
  ids = pageIds()
  t.truthy(ids.pageNext and not ids.pagePrev, "first page")
  rules.act(state, "pageNext", rng)
  t.eq(state.page, 1)
  ids = pageIds()
  t.truthy(ids.pageNext and ids.pagePrev, "middle page")
  rules.act(state, "pageNext", rng)
  ids = pageIds()
  t.truthy(ids.pagePrev and not ids.pageNext, "last page")
  rules.act(state, "pageNext", rng)
  t.eq(state.page, 2, "cannot run off the end")
end)

t.test("the dealer's reveal lasts, and stays on the table for the result", function()
  local state, rng = rigged({ player = { "5H" }, dealer = { "3C", "KC" }, pile = { "5D" } })
  local events = rules.act(state, play("5H"), rng)
  local model = fakeModel(state)
  model.shown = nil
  local last = events[#events]
  t.eq(last.type, "reveal")
  t.truthy(view.event(model, last) >= 1, "a second at least")
  view.commit(model, last)
  t.eq(#model.shown, 2, "both cards stay face up")
end)

t.test("a wild offers all four suits", function()
  local state, rng = rigged({ player = { "8C", "KS" }, dealer = { "3C" }, pile = { "5D" } })
  rules.act(state, play("8C"), rng)
  local suits = 0
  for _, region in ipairs(view.regions(fakeModel(state), state)) do
    if region.id:match("^suit%d$") then
      suits = suits + 1
      t.truthy(region.w >= 20 and region.h >= 10, "big enough")
    end
  end
  t.eq(suits, 4)
end)
