-- group_blackjack_test.lua
-- Blackjack on Big Table: scripted rounds against a stacked shoe, the contract, the secrets, a hand-for-hand match against the single
-- table's rules with one seat, and the return at one, three and eight seats.

local deck = require("lib.casino.deck")
local kit = require("group_kit")
local single = require("blackjack_rules")
local t = require("testing")

local plugin = kit.plugin("BigTable", "blackjack")
local rules = plugin.rules

--- A round dealt from these cards: each seat, the up card, each seat, the hole card, then the draws.
local function rigged(names, seats, bet)
  local keep = { shoe = deck.stack(deck.fresh(rules.DECKS), names) }
  local entries = {}
  for index, seat in ipairs(seats or { 1 }) do entries[index] = { seat = seat, name = "P" .. seat, bet = bet or 100 } end
  local state, events = rules.new(entries, 1, t.fastRng(9), keep)
  return state, events, keep
end

local function player(state, seat)
  for _, each in ipairs(state.players) do
    if each.seat == seat then return each end
  end
end

local function has(state, seat, id)
  for _, action in ipairs(rules.actions(state, seat)) do
    if action.id == id then return action end
  end
  return nil
end

local function dealerPlays(state)
  local events = rules.act(state, nil, rules.auto(state, nil))
  t.truthy(events and #events > 0, "the dealer's move did something")
  return events
end

t.test("seats act in seat order, and only the one whose turn it is", function()
  local state = rigged({ "10H", "10D", "9S", "7C", "8H", "9D", "8S", "10C" }, { 2, 3, 7 })
  t.eq(rules.waitingOn(state)[1], 2)
  t.eq(#rules.waitingOn(state), 1)
  t.eq(#rules.actions(state, 3), 0, "seat 3 has nothing yet")
  t.eq(#rules.act(state, 3, "stand"), 0, "seat 3 cannot play out of turn")
  t.eq(#rules.act(state, 2, "stand"), 2, "the stand and the turn moving on")
  t.eq(rules.waitingOn(state)[1], 3)
  rules.act(state, 3, "stand")
  t.eq(rules.waitingOn(state)[1], 7)
  rules.act(state, 7, "stand")
  t.eq(#rules.waitingOn(state), 0, "the computer's move")
  t.truthy(not rules.done(state), "and the round is not over until it makes it")
  dealerPlays(state)
  t.truthy(rules.done(state))
  local nets = rules.nets(state)
  t.eq(nets[2], 100, "18 beats 17")
  t.eq(nets[3], 100, "19 beats 17")
  t.eq(nets[7], 0, "17 pushes")
end)

t.test("a natural pays 3:2 and is skipped in the turn order", function()
  local state = rigged({ "AH", "10D", "6C", "KD", "9S", "10C", "4C" }, { 1, 2 })
  t.eq(rules.waitingOn(state)[1], 2, "seat 1 has nothing to decide")
  rules.act(state, 2, "stand")
  dealerPlays(state)
  local nets = rules.nets(state)
  t.eq(nets[1], 150)
  t.eq(rules.result(state, 1).title, "BLACKJACK")
  t.eq(nets[2], -100, "19 loses to 20")
  t.eq(rules.result(state, 2).title, "DEALER WINS")
end)

t.test("a natural floors to whole tokens", function()
  local state = rigged({ "AH", "6C", "KD", "9S" }, { 1 }, 15)
  dealerPlays(state)
  t.eq(rules.nets(state)[1], 22)
end)

t.test("everyone holding a natural leaves the dealer nothing to draw", function()
  local state = rigged({ "AH", "AD", "6C", "KD", "QD", "5S", "9C" }, { 1, 2 })
  t.eq(#rules.waitingOn(state), 0)
  dealerPlays(state)
  t.eq(#state.dealer, 2)
  t.eq(rules.nets(state)[1], 150)
end)

t.test("a dealer natural ends it on the peek: nobody acts, a player natural pushes, a pair loses one bet", function()
  local state = rigged({ "AH", "8D", "AC", "KD", "8S", "QS" }, { 1, 2 })
  t.eq(#rules.waitingOn(state), 0, "no one gets a button")
  t.eq(#rules.actions(state, 2), 0)
  t.eq(#rules.act(state, 2, "hit"), 0)
  dealerPlays(state)
  t.eq(rules.nets(state)[1], 0)
  t.eq(rules.result(state, 1).kind, "push")
  t.eq(rules.nets(state)[2], -100)
  t.eq(rules.result(state, 2).title, "DEALER BLACKJACK")
  t.eq(rules.result(state, nil).title, "DEALER BLACKJACK")
end)

t.test("a peek that finds nothing plays on, and the peek shows on the table whichever it found", function()
  local state, events = rigged({ "9H", "KC", "7D", "5S" })
  t.truthy(has(state, 1, "hit"))
  local peeked = false
  for _, ev in ipairs(events) do peeked = peeked or ev.type == "peek" end
  t.truthy(peeked)
end)

t.test("the dealer draws for a live hand, not when all have bust", function()
  local state = rigged({ "10H", "10C", "6D", "8S", "KD", "3C" })
  rules.act(state, 1, "hit")
  t.eq(#rules.waitingOn(state), 0, "a bust moves on by itself")
  dealerPlays(state)
  t.eq(#state.dealer, 2, "nothing to draw against")
  t.eq(rules.nets(state)[1], -100)

  state = rigged({ "10H", "10D", "6C", "6S", "KD", "2C", "9C", "3H" }, { 1, 2 })
  rules.act(state, 1, "hit")
  t.eq(player(state, 1).hands[1].cards[3] ~= nil, true, "seat 1 bust on the 9")
  rules.act(state, 2, "stand")
  dealerPlays(state)
  t.truthy(#state.dealer > 2, "seat 2 stood, so the dealer plays it out")
end)

t.test("soft 17 hits, hard 17 stands", function()
  local state = rigged({ "10H", "AC", "8D", "6S", "4C", "10D" })
  rules.act(state, 1, "stand")
  dealerPlays(state)
  t.eq(#state.dealer, 3)
  t.eq(rules.total(state.dealer), 21)
  state = rigged({ "10H", "10C", "8D", "7S", "4C" })
  rules.act(state, 1, "stand")
  dealerPlays(state)
  t.eq(#state.dealer, 2)
end)

t.test("double on a hard 11 only, for one card and twice the bet", function()
  t.truthy(has(rigged({ "6H", "5C", "5D", "10S" }), 1, "double"), "6,5")
  t.truthy(not has(rigged({ "6H", "5C", "4D", "10S" }), 1, "double"), "hard 10")
  t.truthy(not has(rigged({ "AH", "5C", "AD", "10S" }), 1, "double"), "soft 12")
  local state = rigged({ "6H", "10C", "5D", "7S", "9C" })
  t.eq(#rules.act(state, 1, "split"), 0, "not a pair")
  t.eq(has(state, 1, "double").cost, 100)
  rules.act(state, 1, "double")
  t.eq(#rules.waitingOn(state), 0, "one card and the hand stands")
  dealerPlays(state)
  t.eq(rules.risk(state, 1), 200)
  t.eq(rules.nets(state)[1], 200)
  state = rigged({ "2H", "5C", "4D", "10S", "5H" })
  t.eq(#rules.act(state, 1, "double"), 0, "6 is no 11")
  rules.act(state, 1, "hit")
  t.truthy(not has(state, 1, "double"), "only on the first two cards")
end)

t.test("a split plays two hands for two bets, then the turn moves on", function()
  local state = rigged({ "8H", "10S", "10C", "8D", "9H", "7S", "3C", "10D", "10H", "9C" }, { 1, 2 })
  t.eq(has(state, 1, "split").cost, 100)
  rules.act(state, 1, "split")
  local one = player(state, 1)
  t.eq(#one.hands, 2)
  t.eq(rules.total(one.hands[1].cards), 11, "8 and 3")
  t.eq(rules.total(one.hands[2].cards), 18, "8 and 10")
  t.truthy(not has(state, 1, "double"), "no double after a split")
  t.eq(#rules.act(state, 1, "split"), 0, "only once")
  rules.act(state, 1, "hit")
  t.eq(one.active, 2, "21 stood by itself")
  t.eq(rules.waitingOn(state)[1], 1, "still this seat")
  rules.act(state, 1, "stand")
  t.eq(rules.waitingOn(state)[1], 2, "now the next seat")
  rules.act(state, 2, "stand")
  dealerPlays(state)
  t.eq(rules.risk(state, 1), 200)
  t.eq(rules.nets(state)[1], 200, "both beat 17")
  t.eq(rules.result(state, 1).title, "SPLIT WON")
end)

t.test("split aces get one card each, and 21 on one is no natural", function()
  local state = rigged({ "AH", "10C", "AD", "9S", "KC", "5D" })
  rules.act(state, 1, "split")
  t.eq(#rules.waitingOn(state), 0, "both stand at once")
  dealerPlays(state)
  local hands = player(state, 1).hands
  t.eq(hands[1].result, "win")
  t.eq(hands[1].net, 100, "1 to 1, not 3 to 2")
  t.eq(hands[2].result, "lose", "16 loses to 19")
end)

t.test("max win covers the best case, split or double", function()
  t.eq(rules.maxWin({ bet = 100 }), 200)
  local state = rigged({ "8H", "10C", "8D", "7S", "3C", "10D", "10H", "9C" })
  rules.act(state, 1, "split")
  rules.act(state, 1, "hit")
  rules.act(state, 1, "stand")
  dealerPlays(state)
  t.truthy(rules.nets(state)[1] <= rules.maxWin({ bet = 100 }))
end)

t.test("junk does nothing at any point in a round", function()
  local state = rigged({ "8H", "10C", "8D", "7S", "3C", "10D", "10H", "9C" }, { 4 })
  local junk = {
    { 4, "no" }, { 4, nil }, { 4, 12 }, { 4, {} }, { 4, "dealer" }, { 4, "double" }, { 1, "hit" }, { 99, "stand" },
    { "4", "stand" }, { {}, "hit" }, { nil, "hit" }, { nil, "dealer" }, { nil, nil },
  }
  for pass = 1, 3 do
    local before = kit.plain(state)
    for _, press in ipairs(junk) do
      local events = rules.act(state, press[1], press[2], nil)
      t.truthy(not events or #events == 0, "junk returned events")
      t.truthy(kit.same(before, state), "junk changed the state")
    end
    if pass == 1 then rules.act(state, 4, "split") elseif pass == 2 then rules.act(state, 4, "hit") end
  end
  rules.act(state, 4, "stand")
  dealerPlays(state)
  local final = kit.plain(state)
  t.eq(#rules.act(state, 4, "hit"), 0, "after the round")
  t.eq(#rules.act(state, nil, "dealer"), 0, "the dealer plays once")
  t.truthy(kit.same(final, state))
end)

t.test("the contract, with people walking off", function()
  kit.fuzz(plugin, { rounds = 1500, seats = { 1, 2, 5, 8 }, bet = 100, absent = 15 })
  kit.fuzz(plugin, { rounds = 1000, seats = { 1, 8 }, bet = 25, absent = 0, seed = 77 })
end)

--- Two copies of a state that only differ in what nobody may know: another hole card and another shoe.
local function withOtherSecrets(state)
  local other = kit.plain(state)
  other.dealer[2] = (other.dealer[2] + 17) % 52
  for index = 1, #other.cards do other.cards[index] = (other.cards[index] + 5) % 52 end
  return other
end

t.test("no view holds the hole card or the shoe before the round is over, over 2000 rounds", function()
  local checked = 0
  local function check(state, entries)
    if state.phase == "over" then return end
    local other = withOtherSecrets(state)
    other.cards[#other.cards + 1] = 51
    t.truthy(kit.same(rules.viewFor(state, nil), (function()
      local view = rules.viewFor(other, nil)
      view.left = view.left - 1
      return view
    end)()), "the public view moved with the secrets")
    for _, entry in ipairs(entries) do
      local mine = rules.viewFor(state, entry.seat)
      t.eq(mine.dealer[2], nil, "only the up card")
      t.eq(mine.cards, nil, "no shoe")
      t.eq(mine.me, entry.seat)
      local also = rules.viewFor(other, entry.seat)
      also.left = also.left - 1
      t.truthy(kit.same(mine, also), "seat " .. entry.seat .. "'s view moved with the secrets")
      checked = checked + 1
    end
    -- What a view has is a copy, so nothing a seat is sent can reach back
    local public = rules.viewFor(state, nil)
    t.truthy(public.seats[1].hands[1].cards ~= state.players[1].hands[1].cards, "a copy, not the state's own list")
  end
  kit.fuzz(plugin, { rounds = 2000, seats = { 1, 3, 8 }, bet = 100, check = check, seed = 321 })
  t.truthy(checked > 2000, "the check ran")
end)

local EVENT_KEYS = { type = true, seat = true, hand = true, step = true, fresh = true, shown = true }

--- A random legal round, handing every event to see. Returns the state.
local function playRandom(entries, keep, rng, see)
  local state, events = rules.new(entries, 1, rng, keep)
  see(events, state)
  while not rules.done(state) do
    local waiting = rules.waitingOn(state)
    local moved
    if #waiting == 0 then
      moved = rules.act(state, nil, rules.auto(state, nil))
    else
      local list = rules.actions(state, waiting[1])
      moved = rules.act(state, waiting[1], list[rng:below(#list) + 1].id)
    end
    t.truthy(#moved > 0, "a legal move did something")
    see(moved, state)
  end
  return state
end

t.test("over 2000 random rounds an event never names a card, and every net is what its hands earned", function()
  local rng = t.fastRng(404)
  local keep, hands = {}, 0
  for round = 1, 2500 do
    local entries = {}
    for seat = 1, 1 + round % 8 do entries[seat] = { seat = seat, name = "P" .. seat, bet = 10 + rng:below(91) } end
    local state = playRandom(entries, keep, rng, function(events)
      for _, ev in ipairs(events) do
        for key in pairs(ev) do t.truthy(EVENT_KEYS[key], "an event carries " .. key) end
      end
    end)
    local nets = rules.nets(state)
    for _, entry in ipairs(entries) do
      local net, each = nets[entry.seat], player(state, entry.seat)
      hands = hands + 1
      local sum = 0
      for _, hand in ipairs(each.hands) do
        t.truthy(hand.result, "every hand is judged")
        sum = sum + hand.net
      end
      t.eq(net, sum)
      t.truthy(net >= -rules.risk(state, entry.seat), "no one loses more than they staked")
      t.truthy(net <= rules.maxWin(entry), "and no one wins past maxWin")
    end
    rules.finish(state, keep)
    if round % 100 == 0 then t.breathe() end
  end
  t.truthy(hands >= 2000)
end)

t.test("every state and view survives textutils, and carries on the same", function()
  if not textutils then return end
  local rng = t.fastRng(55)
  local state = rules.new({ { seat = 2, name = "A", bet = 50 }, { seat = 5, name = "B", bet = 75 } }, 1, rng, {})
  while not rules.done(state) do
    local copied = textutils.unserialize(textutils.serialize(state))
    t.truthy(kit.same(state, copied), "the state came back whole")
    t.truthy(type(textutils.serialize(rules.viewFor(state, 2))) == "string")
    t.truthy(type(textutils.serialize(rules.viewFor(state, nil))) == "string")
    state = copied
    local waiting = rules.waitingOn(state)
    if #waiting == 0 then rules.act(state, nil, "dealer") else rules.act(state, waiting[1], "stand") end
  end
  t.truthy(type(textutils.serialize(rules.viewFor(state, 2))) == "string")
end)

t.test("the shoe lasts between rounds, stays in keep between them, and reshuffles only below the cut", function()
  local keep = {}
  local rng = t.fastRng(5)
  local entries = { { seat = 1, name = "A", bet = 10 }, { seat = 2, name = "B", bet = 10 } }
  local state, events = rules.new(entries, 1, rng, keep)
  t.truthy(events[1].fresh, "the first round shuffles")
  t.truthy(keep.shuffled, "and tells the engine")
  t.eq(keep.shoe, nil, "the shoe is in the state while it plays")
  t.eq(#state.cards, 6 * 52 - 6)
  local function play()
    while not rules.done(state) do
      local waiting = rules.waitingOn(state)
      if #waiting == 0 then rules.act(state, nil, "dealer") else rules.act(state, waiting[1], "stand") end
    end
  end
  play()
  local left = #state.cards
  rules.finish(state, keep)
  t.eq(#state.cards, 0, "and leaves with finish")
  t.eq(#keep.shoe, left)
  t.eq(rules.viewFor(state, nil).left, left, "a finished round still says what was left")
  keep.shuffled = nil
  state, events = rules.new(entries, 1, rng, keep)
  t.truthy(not events[1].fresh)
  t.eq(keep.shuffled, nil)
  t.eq(#state.cards, left - 6, "the same shoe")
  play()
  rules.finish(state, keep)
  while #keep.shoe > 156 do table.remove(keep.shoe) end
  state, events = rules.new(entries, 1, rng, keep)
  t.truthy(not events[1].fresh, "156 left still plays")
  play()
  rules.finish(state, keep)
  t.truthy(#keep.shoe < 156)
  state, events = rules.new(entries, 1, rng, keep)
  t.truthy(events[1].fresh, "below it, a fresh shoe")
  t.truthy(plugin.shoe, "and the engine knows it is a shoe game")
end)

--- single's own shape for one seat, so its basic strategy can read this table.
local function shim(state, each)
  return { hands = each.hands, active = each.active, dealer = state.dealer }
end

local function offeredOf(state, seat)
  local offered = {}
  for _, action in ipairs(rules.actions(state, seat)) do offered[action.id] = true end
  return offered
end

t.test("with one seat it is the single table, hand for hand", function()
  local rngA, rngB, choice = t.fastRng(808), t.fastRng(808), t.fastRng(809)
  local keepA, keepB = {}, {}
  for round = 1, 6000 do
    local a = single.new(100, rngA, keepA, {})
    local b = rules.new({ { seat = 1, name = "A", bet = 100 } }, 1, rngB, keepB)
    t.truthy(kit.same(a.dealer, b.dealer), "same deal")
    while not single.done(a) do
      if a.hold then
        t.eq(#rules.waitingOn(b), 0, "a natural either side waits on nobody here")
        single.act(a, "stand", rngA)
      else
        local listA, listB = single.actions(a), rules.actions(b, 1)
        t.eq(#listA, #listB, "the same buttons")
        for index, action in ipairs(listA) do
          t.eq(action.id, listB[index].id)
          t.eq(action.cost, listB[index].cost)
        end
        local id = listA[choice:below(#listA) + 1].id
        single.act(a, id, rngA)
        rules.act(b, 1, id)
      end
    end
    t.eq(#rules.waitingOn(b), 0)
    rules.act(b, nil, "dealer")
    t.truthy(rules.done(b))
    t.eq(single.net(a), rules.nets(b)[1], "the same net")
    t.eq(single.risk(a), rules.risk(b, 1), "the same stake")
    t.truthy(kit.same(a.dealer, b.dealer), "the same dealer cards")
    local one, two = single.result(a), rules.result(b, 1)
    t.eq(one.kind, two.kind)
    t.eq(one.title, two.title)
    t.eq(one.detail, two.detail)
    single.finish(a, keepA)
    rules.finish(b, keepB)
    t.eq(#keepA.shoe, #keepB.shoe, "the same cards used")
    if round % 200 == 0 then t.breathe() end
  end
  t.eq(rules.DECKS, single.DECKS)
  t.eq(rules.RESHUFFLE_BELOW, single.RESHUFFLE_BELOW)
  t.eq(rules.maxWin({ bet = 7 }), single.maxWin(7))
end)

local function simulate(seats, rounds, seed)
  local rng = t.fastRng(seed)
  local keep, net, staked, wagered = {}, 0, 0, 0
  local entries = {}
  for seat = 1, seats do entries[seat] = { seat = seat, name = "P" .. seat, bet = 100 } end
  for round = 1, rounds do
    local state = rules.new(entries, 1, rng, keep)
    while not rules.done(state) do
      local waiting = rules.waitingOn(state)
      if #waiting == 0 then
        rules.act(state, nil, "dealer")
      else
        local seat = waiting[1]
        local each = player(state, seat)
        rules.act(state, seat, single.basic(shim(state, each), offeredOf(state, seat)))
      end
    end
    for seat, amount in pairs(rules.nets(state)) do
      net = net + amount
      staked = staked + 100
      wagered = wagered + rules.risk(state, seat)
    end
    rules.finish(state, keep)
    if round % 500 == 0 then t.breathe() end
  end
  return (staked + net) / staked, (wagered + net) / wagered
end

t.test("basic strategy returns the single table's 98.5%, within 97.5 to 99.5, however many sit", function()
  local totalReturn = 0
  for _, setup in ipairs({ { 1, 90000, 11 }, { 3, 30000, 12 }, { 8, 11250, 13 } }) do
    local value, onWagered = simulate(setup[1], setup[2], setup[3])
    print(("     %d seats: return %.4f on the bet, %.4f on all wagered"):format(setup[1], value, onWagered))
    t.truthy(value >= 0.975 and value <= 0.995, setup[1] .. " seats return " .. value)
    totalReturn = totalReturn + value
  end
  local value = totalReturn / 3
  print(("     blackjack on Big Table return %.4f"):format(value))
  t.truthy(value >= 0.98 and value <= 0.992, "return " .. value)
end)

t.test("the help comes from the rules and names no secret", function()
  local parts = {}
  for _, line in ipairs(plugin.help()) do parts[#parts + 1] = type(line) == "table" and line[1] or line end
  local text = table.concat(parts, " ")
  t.truthy(text:find("3 to 2", 1, true), "the payout")
  t.truthy(text:find("soft 17", 1, true), "the dealer's rule")
  t.truthy(text:find("hard 11", 1, true), "the double")
end)

t.test("every event has a time, and the deal is short even at a full table", function()
  local keep = {}
  local _, events = rules.new((function()
    local entries = {}
    for seat = 1, 8 do entries[seat] = { seat = seat, name = "P" .. seat, bet = 10 } end
    return entries
  end)(), 1, t.fastRng(3), keep)
  local seconds = 0
  for _, ev in ipairs(events) do seconds = seconds + plugin.event(ev) end
  t.truthy(seconds < 4, "a full deal takes " .. seconds)
end)
