-- group_baccarat_test.lua
-- Shared-coup baccarat: the same coup as Games/Baccarat, played against baccarat_rules itself, then every seat's money, what a view may
-- hold, the whole contract at random, and the exact return of each bet through the group rules.

local deck = require("lib.casino.deck")
local solo = require("baccarat_rules")
local kit = require("group_kit")
local t = require("testing")

local plugin = kit.plugin("BigTable", "baccarat")
local rules = plugin.rules
local base = require("games.baccarat.coup")
local played = require("games.baccarat.played")

local BANKER_WINS, PLAYER_WINS, TIES = 2292252566437888, 2230518282592256, 475627426473216

--- A table of entries from { player, banker, tie } triples.
local function table_(list)
  local entries = {}
  for index, spots in ipairs(list) do
    entries[index] = { seat = spots.seat or index, name = "P" .. index,
      bet = (spots[1] or 0) + (spots[2] or 0) + (spots[3] or 0),
      bets = { player = spots[1], banker = spots[2], tie = spots[3] } }
  end
  return entries
end

--- A round from these cards in deal order: P, B, P, B, then draws.
local function rigged(names, entries, keep)
  keep = keep or {}
  keep.shoe = deck.stack(deck.fresh(8), names)
  local rng = t.fastRng(9)
  return rules.new(entries, 1, rng, keep), rng, keep
end

--- A dealt round.
local function coup(names, entries)
  local state, rng, keep = rigged(names, entries)
  rules.act(state, nil, "deal", nil, rng)
  return state, keep
end

t.test("a coup deals nothing until the computer's move, and waits on nobody", function()
  local state, rng = rigged({ "9H", "2C", "KD", "3S" }, table_({ { 100 } }))
  t.eq(#rules.viewFor(state, nil).player, 0)
  t.truthy(not rules.done(state))
  t.eq(#rules.waitingOn(state), 0)
  t.eq(#rules.actions(state, 1), 0)
  t.eq(rules.auto(state, nil), "deal")
  local events = rules.act(state, nil, "deal", nil, rng)
  t.truthy(rules.done(state))
  t.eq(events[#events].type, "outcome")
  for _, ev in ipairs(events) do t.truthy(ev.type == "deal" or ev.type == "outcome", tostring(ev.type)) end
end)

t.test("illegal input does nothing", function()
  local state, rng = rigged({ "9H", "2C", "KD", "3S" }, table_({ { 100 } }))
  local before = kit.plain(state)
  for _, press in ipairs({ { 1, "deal" }, { 1, "player" }, { nil, "player" }, { nil, nil }, { 9, "deal" }, { nil, 7 } }) do
    local events = rules.act(state, press[1], press[2], nil, rng)
    t.eq(#events, 0, "refused")
    t.truthy(kit.same(before, state), "unchanged")
  end
  rules.act(state, nil, "deal", nil, rng)
  local after = kit.plain(state)
  t.eq(#rules.act(state, nil, "deal", nil, rng), 0, "a coup deals once")
  t.truthy(kit.same(after, state))
end)

t.test("each seat is paid on its own bets from one coup", function()
  local entries = table_({ { 100 }, { 0, 100 }, { 0, 0, 100 }, { seat = 7, 50, 50, 10 } })
  local playerWins = { "9H", "2C", "KD", "3S", "4D", "5H" } -- P 9 natural, B 5
  local nets = rules.nets((coup(playerWins, entries)))
  t.eq(nets[1], 100)
  t.eq(nets[2], -100)
  t.eq(nets[3], -100)
  t.eq(nets[7], 50 - 50 - 10)

  local bankerWins = { "2H", "9C", "KD", "KS" } -- B natural 9
  nets = rules.nets((coup(bankerWins, entries)))
  t.eq(nets[1], -100)
  t.eq(nets[2], 95)
  t.eq(nets[3], -100)
  t.eq(nets[7], 47 - 50 - 10)

  local tie = { "9H", "9C", "KD", "KS" }
  nets = rules.nets((coup(tie, entries)))
  t.eq(nets[1], 0, "Player pushes")
  t.eq(nets[2], 0, "Banker pushes")
  t.eq(nets[3], 800, "Tie pays 8:1")
  t.eq(nets[7], 80, "the rest pushes under a Tie")
end)

t.test("a Banker bet below the minimum stands down, in the money, the risk and the cover", function()
  local entries = table_({ { 10, 10 } })
  local playerWins = { "9H", "2C", "KD", "3S", "4D", "5H" }
  local state = coup(playerWins, entries)
  t.eq(rules.nets(state)[1], 10, "only the Player bet stood")
  t.eq(rules.risk(state, 1), 10)
  t.eq(rules.viewFor(state, 1).own.void, 10)
  t.eq(rules.maxWin(entries[1]), 10)

  local only = coup({ "2H", "9C", "KD", "KS" }, table_({ { 0, 19 } }))
  t.eq(rules.nets(only)[1], 0)
  t.eq(rules.result(only, 1).kind, "push")
  t.eq(rules.risk(only, 1), 0)
  t.eq(rules.nets(coup({ "2H", "9C", "KD", "KS" }, table_({ { 0, 20 } })))[1], 19, "20 is enough")
end)

t.test("maxWin is the best a set of bets can really do", function()
  t.eq(rules.maxWin(table_({ { 100 } })[1]), 100)
  t.eq(rules.maxWin(table_({ { 0, 100 } })[1]), 95)
  t.eq(rules.maxWin(table_({ { 0, 0, 100 } })[1]), 800)
  t.eq(rules.maxWin(table_({ { 100, 100 } })[1]), 0, "a hedge wins nothing but pushes")
  t.eq(rules.maxWin(table_({ { 100, 0, 10 } })[1]), 90)
  t.eq(rules.maxWin(table_({ { 100, 0, 100 } })[1]), 800)
end)

t.test("the rest of the shoe stays with the table, and the road waits for the coup", function()
  local keep = { road = "PB" }
  local state, _, kept = rigged({ "2H", "9C", "KD", "KS" }, table_({ { 100 } }), keep)
  rules.act(state, nil, "deal", nil, t.fastRng(2))
  local left = #state.coup.cards
  rules.finish(state, kept)
  t.eq(kept.road, "BPB")
  t.eq(#kept.shoe, left)
  t.eq(rules.viewFor(state, nil).road, "PB", "the round's own copy, so the result cannot show early")
  t.eq(rules.result(state, 1).kind, "lose", "a result still reads after finish")
end)

t.test("a shoe goes on, burns one, and reshuffles below the cut", function()
  local keep = {}
  local rng = t.fastRng(5)
  local state, events = rules.new(table_({ { 100 } }), 1, rng, keep)
  t.truthy(events[1].fresh)
  t.truthy(keep.shuffled, "the engine is told")
  keep.shuffled = nil
  t.eq(#state.coup.cards, 8 * 52 - 1)
  rules.act(state, nil, "deal", nil, rng)
  rules.finish(state, keep)
  state, events = rules.new(table_({ { 100 } }), 1, rng, keep)
  t.truthy(not events[1].fresh)
  t.eq(keep.shuffled, nil)
  rules.act(state, nil, "deal", nil, rng)
  rules.finish(state, keep)
  while #keep.shoe >= 30 do table.remove(keep.shoe) end
  state, events = rules.new(table_({ { 100 } }), 1, rng, keep)
  t.truthy(events[1].fresh)
  t.truthy(keep.shuffled)
end)

t.test("this coup is baccarat_rules' coup, card for card, on every kind of hand", function()
  local rng = t.fastRng(77)
  for round = 1, 3000 do
    local shoe = deck.shuffle(deck.fresh(8), rng)
    local a = { bet = 100, cards = {}, player = {}, banker = {} }
    for index, card in ipairs(shoe) do a.cards[index] = card end
    solo.act(a, "tie")
    local state = rules.new(table_({ { 100, 100, 100 } }), 1, rng, { shoe = shoe })
    rules.act(state, nil, "deal", nil, rng)
    t.truthy(kit.same(a.player, state.coup.player), "Player's cards")
    t.truthy(kit.same(a.banker, state.coup.banker), "Banker's cards")
    t.eq(state.coup.winner, a.winner)
    if round % 200 == 0 then t.breathe() end
  end
end)

t.test("the shared constants and tables are baccarat_rules'", function()
  for _, key in ipairs({ "DECKS", "BURN", "RESHUFFLE_BELOW", "COMMISSION", "MIN_BANKER", "NATURAL", "ROAD_KEPT" }) do
    t.eq(base[key], solo[key], key)
  end
  for side, pays in pairs(solo.PAYS) do t.eq(base.PAYS[side], pays, side) end
  for total = 0, 9 do
    t.eq(base.playerDraws(total), solo.playerDraws(total))
    t.eq(base.bankerDraws(total, nil), solo.bankerDraws(total, nil))
    for third = 0, 9 do t.eq(base.bankerDraws(total, third), solo.bankerDraws(total, third)) end
  end
  for bet = 1, 2000 do
    for side in pairs(solo.PAYS) do t.eq(base.winOn(side, bet), solo.winOn(side, bet)) end
  end
  for card = 0, 51 do t.eq(base.value(card), solo.value(card)) end
  t.eq(base.addToRoad("PB", "tie"), solo.addToRoad("PB", "tie"))
end)

--- A view with the parts a coup decides taken out.
local function bare(view)
  local copy = kit.plain(view)
  copy.player, copy.banker, copy.winner, copy.over = nil, nil, nil, nil
  for _, line in ipairs(copy.bets) do line.net = nil end
  if copy.own then copy.own.net = nil end
  return copy
end

t.test("a view holds nothing of the shoe, and a view before the deal does not depend on it", function()
  local entries = table_({ { 100, 25, 5 }, { seat = 5, 0, 60 } })
  local one = rules.new(entries, 1, t.fastRng(1), {})
  local two = rules.new(entries, 1, t.fastRng(2), {})
  t.truthy(not kit.same(one.coup.cards, two.coup.cards), "two different shoes")
  for _, seat in ipairs({ false, 1, 5, 3 }) do
    local who = seat or nil
    t.truthy(kit.same(rules.viewFor(one, who), rules.viewFor(two, who)), "the same view from either shoe")
    local view = rules.viewFor(one, who)
    t.eq(#view.player + #view.banker, 0)
    t.eq(view.winner, nil)
  end
  rules.act(one, nil, "deal", nil, t.fastRng(3))
  rules.act(two, nil, "deal", nil, t.fastRng(3))
  for _, seat in ipairs({ false, 1, 5, 3 }) do
    local who = seat or nil
    t.truthy(kit.same(bare(rules.viewFor(one, who)), bare(rules.viewFor(two, who))), "only what was dealt differs")
    t.truthy(#rules.viewFor(one, who).player <= 3)
  end
end)

t.test("a seat's view is the public view and its own bets, nothing of anyone else's", function()
  local entries = table_({ { 111 }, { seat = 2, 0, 222 }, { seat = 6, 0, 0, 333 } })
  local state, rng = rigged({ "2H", "9C", "KD", "KS" }, entries)
  local function check()
    local public = rules.viewFor(state, nil)
    t.eq(public.own, nil, "the wall has no own")
    for _, entry in ipairs(entries) do
      local view = rules.viewFor(state, entry.seat)
      local own = view.own
      view.own = nil
      t.truthy(kit.same(view, public), "the same but for own")
      for _, other in ipairs(entries) do
        if other.seat ~= entry.seat then t.truthy(not kit.shows(own, other.bet), "no other seat's bet in own") end
      end
    end
    t.eq(rules.viewFor(state, 3).own, nil, "an empty seat has none either")
  end
  check()
  rules.act(state, nil, "deal", nil, rng)
  check()
end)

t.test("nothing but the deal puts a card in an event, and that move is the last, for the engine to hold back", function()
  local state, events = rules.new(table_({ { 100 } }), 1, t.fastRng(4), {})
  t.eq(#events, 1)
  t.eq(events[1].card, nil)
  t.eq(rules.done(state), false)
  local last = rules.act(state, nil, "deal", nil, t.fastRng(4))
  t.truthy(rules.done(state), "the money settles before these play")
  t.truthy(#last >= 5)
end)

t.test("the screens hold back cards and the result until they have played", function()
  local state, rng = rigged({ "2H", "2C", "KD", "KS", "9C", "4D" }, table_({ { 100 } }))
  local events = rules.act(state, nil, "deal", nil, rng)
  local view = rules.viewFor(state, 1)
  local p, b = 0, 0
  for _, ev in ipairs(events) do
    local shown = played.of(view, { ev = ev, t = 0.5 })
    if ev.type == "deal" then
      t.eq(#shown.player, p, "Player's cards so far")
      t.eq(#shown.banker, b, "Banker's cards so far")
      t.eq(shown.winner, nil, "no winner in the deal")
      t.eq(shown.road, "", "the road waits")
      if ev.who == "player" then p = p + 1 else b = b + 1 end
    else
      t.eq(shown.winner, ev.winner)
      t.eq(#shown.road, 1)
    end
  end
  t.eq(p + b, 6)
end)

t.test("a state survives serialization", function()
  if not textutils then return end
  local state, rng = rigged({ "9H", "2C", "KD", "3S" }, table_({ { 100 }, { seat = 4, 0, 50, 5 } }))
  local back = textutils.unserialize(textutils.serialize(state, { compact = true }))
  t.truthy(kit.same(state, back))
  rules.act(back, nil, "deal", nil, rng)
  back = textutils.unserialize(textutils.serialize(back, { compact = true }))
  t.eq(rules.nets(back)[1], 100)
  t.truthy(textutils.serialize(rules.viewFor(back, 4), { compact = true }) ~= nil)
end)

t.test("the contract, at random, with every spread of bets and a shoe that lasts", function()
  local rng = t.fastRng(404)
  local chips = { 0, 0, 5, 19, 20, 25, 100, 400, 2000 }
  local keep = {}
  local hands = 0
  for round = 1, 2500 do
    local spots = {}
    local count = rng:below(8) + 1
    local taken = {}
    for index = 1, count do
      local seat = rng:below(8) + 1
      while taken[seat] do seat = seat % 8 + 1 end
      taken[seat] = true
      spots[index] = { seat = seat, chips[rng:below(#chips) + 1], chips[rng:below(#chips) + 1], chips[rng:below(#chips) + 1] }
    end
    table.sort(spots, function(a, b) return a.seat < b.seat end)
    local entries = table_(spots)
    local state = kit.playRound(plugin, { entries = entries, rng = rng, keep = keep, check = function(live, list)
      for _, entry in ipairs(list) do
        local view = rules.viewFor(live, entry.seat)
        t.eq(#view.player + #view.banker, 0, "no card before the deal")
      end
    end })
    local nets = kit.checkEnd(plugin, state, entries)

    -- The payouts again, from the rules on the felt and the solo table's own figures
    local winner = state.coup.winner
    local total = solo.total(state.coup.player) - solo.total(state.coup.banker)
    t.eq(winner, total > 0 and "player" or total < 0 and "banker" or "tie")
    for _, entry in ipairs(entries) do
      local bets, want = entry.bets, 0
      for side, amount in pairs(bets) do
        if amount > 0 and (side ~= "banker" or amount >= solo.MIN_BANKER) then
          if side == winner then
            want = want + solo.winOn(side, amount)
          elseif winner ~= "tie" then
            want = want - amount
          end
        end
      end
      t.eq(nets[entry.seat], want, "seat " .. entry.seat .. " on " .. winner)
      t.truthy(nets[entry.seat] <= rules.maxWin(entry), "within maxWin")
      t.truthy(-nets[entry.seat] <= entry.bet, "never past the bet")
      t.truthy(rules.risk(state, entry.seat) <= entry.bet)
    end
    rules.finish(state, keep)
    hands = hands + 1
    if round % 50 == 0 then t.breathe() end
  end
  t.eq(hands, 2500)
end)

t.test("the kit's own fuzz passes with one spread and with none", function()
  kit.fuzz(plugin, { rounds = 200, seats = { 1, 4, 8 }, bet = 120, bets = { player = 100, tie = 20 } })
  kit.fuzz(plugin, { rounds = 100, seats = { 1, 8 }, bet = 100 })
end)

--- Every value sequence of a fresh shoe through the group rules, weighted by how many ordered cards give it, one seat on each side.
local function enumerate()
  local names = { [0] = "KS", "AS", "2S", "3S", "4S", "5S", "6S", "7S", "8S", "9S" }
  local cardOf = {}
  for value = 0, 9 do cardOf[value] = deck.parse(names[value]) end
  local counts = { [0] = 16 * 8 }
  for value = 1, 9 do counts[value] = 4 * 8 end
  local total = 52 * 8
  local rng = t.fastRng(1)
  local entries = table_({ { 100 }, { 0, 100 }, { 0, 0, 100 } })
  local padding = 30
  local shoe = {}
  for index = 1, padding do shoe[index] = 0 end
  local tally = { weight = 0, nets = { 0, 0, 0 } }

  local function run(seq)
    for index = #shoe, padding + 1, -1 do shoe[index] = nil end
    for index = 6, 1, -1 do shoe[#shoe + 1] = cardOf[seq[index] or 0] end
    local state = rules.new(entries, 1, rng, { shoe = shoe })
    rules.act(state, nil, "deal", nil, rng)
    return state, #state.coup.player + #state.coup.banker
  end

  local seq = {}
  local steps = 0
  local function walk(depth, weight)
    local state, used = run(seq)
    if used <= depth then
      local nets = rules.nets(state)
      tally.weight = tally.weight + weight
      for seat = 1, 3 do tally.nets[seat] = tally.nets[seat] + weight * nets[seat] end
      tally[state.coup.winner] = (tally[state.coup.winner] or 0) + weight
      return
    end
    for value = 0, 9 do
      local ways = counts[value]
      seq[depth + 1] = value
      counts[value] = ways - 1
      walk(depth + 1, weight * ways / (total - depth))
      counts[value] = ways
    end
    seq[depth + 1] = nil
    steps = steps + 1
    if steps % 500 == 0 then t.breathe() end
  end

  for a = 0, 9 do
    for b = 0, 9 do
      for c = 0, 9 do
        for d = 0, 9 do
          seq[1], seq[2], seq[3], seq[4] = a, b, c, d
          local weight, n = 1, 0
          for i = 1, 4 do
            weight = weight * counts[seq[i]] / (total - n)
            counts[seq[i]] = counts[seq[i]] - 1
            n = n + 1
          end
          walk(4, weight)
          for i = 1, 4 do counts[seq[i]] = counts[seq[i]] + 1 end
        end
      end
      t.breathe()
    end
  end
  return tally
end

t.test("exact returns: Banker 98.94%, Player 98.77%, Tie 85.64%", function()
  local tally = enumerate()
  local sum = BANKER_WINS + PLAYER_WINS + TIES
  t.near(tally.weight, 1, 1e-9, "every coup counted")
  t.near(tally.banker, BANKER_WINS / sum, 1e-10, "Banker wins")
  t.near(tally.player, PLAYER_WINS / sum, 1e-10, "Player wins")
  t.near(tally.tie, TIES / sum, 1e-10, "ties")
  local player, banker, tie = 1 + tally.nets[1] / 100, 1 + tally.nets[2] / 100, 1 + tally.nets[3] / 100
  print(("     group baccarat banker %.5f player %.5f tie %.5f"):format(banker, player, tie))
  t.near(banker, 0.98942, 0.00002, "Banker return")
  t.near(player, 0.98765, 0.00002, "Player return")
  t.near(tie, 0.85640, 0.00002, "Tie return")
end)

t.test("a simulation through the real shoe agrees", function()
  local rng = t.fastRng(21)
  local keep = {}
  local entries = table_({ { 100 }, { 0, 100 }, { 0, 0, 100 } })
  local sums = { 0, 0, 0 }
  local rounds = 60000
  for round = 1, rounds do
    local state = rules.new(entries, 1, rng, keep)
    rules.act(state, nil, "deal", nil, rng)
    local nets = rules.nets(state)
    for seat = 1, 3 do sums[seat] = sums[seat] + nets[seat] end
    rules.finish(state, keep)
    if round % 2000 == 0 then t.breathe() end
  end
  t.near(1 + sums[1] / (100 * rounds), 0.9877, 0.012, "Player")
  t.near(1 + sums[2] / (100 * rounds), 0.9894, 0.012, "Banker")
  t.near(1 + sums[3] / (100 * rounds), 0.8564, 0.04, "Tie")
end)

--- A canvas that draws nothing and says if anything lands outside the box.
local function fakeCanvas(w, h, top, bottom)
  local function inside(x, y, width, height)
    if x < 1 or y < top or x + width - 1 > w or y + height - 1 > bottom then
      error(("drawn outside: x %d y %d, %d by %d"):format(x, y, width, height), 0)
    end
  end
  local canvas = { w = w, h = h }
  function canvas.rect(_, x, y, width, height) inside(x, y, width, height) end
  function canvas.frame(_, x, y, width, height) inside(x, y, width, height) end
  function canvas.panel(_, x, y, width, height) inside(x, y, width, height) end
  function canvas.text(_, x, y, text) inside(x, y, #tostring(text), 1) end
  function canvas.textCenter(_, cx, y, text) inside(cx - math.floor(#tostring(text) / 2), y, #tostring(text), 1) end
  function canvas.bigWidth(_, text, scale) return #tostring(text) * 6 * (scale or 1) end
  function canvas.big(self, x, y, text, _, scale) inside(x, y, self:bigWidth(text, scale), 6 * (scale or 1)) end
  function canvas.bigCenter(self, cx, y, text, color, scale) self:big(cx - math.floor(self:bigWidth(text, scale) / 2), y, text, color, scale) end
  return canvas
end

t.test("both screens draw every kind of view inside their own space", function()
  local eight = {}
  for seat = 1, 8 do eight[seat] = { seat = seat, 2000, 15, 2000 } end
  local state, rng = rigged({ "2H", "2C", "KD", "KS", "9C", "4D" }, table_(eight))
  local function all()
    for _, seat in ipairs({ false, 1, 3 }) do
      local view = rules.viewFor(state, seat or nil)
      plugin.seatView.draw(fakeCanvas(78, 52, 10, 39), view)
      plugin.tableView.draw(fakeCanvas(121, 81, 10, 72), view)
    end
  end
  all()
  rules.act(state, nil, "deal", nil, rng)
  all()
  for _, ev in ipairs({ { type = "deal", who = "player", slot = 3, card = 0 }, { type = "deal", who = "banker", slot = 3, card = 0 }, { type = "outcome" } }) do
    plugin.seatView.draw(fakeCanvas(78, 52, 10, 39), rules.viewFor(state, 1), { ev = ev, t = 0 })
  end
  plugin.seatView.draw(fakeCanvas(78, 52, 10, 39), {})
  plugin.tableView.draw(fakeCanvas(121, 81, 10, 72), {})
end)

t.test("the plugin is whole and its help is built from the rules", function()
  t.eq(plugin.id, "baccarat")
  t.eq(plugin.kind, "house")
  t.eq(plugin.minSeats, 1)
  t.eq(plugin.maxSeats, 8)
  t.eq(plugin.shoe, true)
  t.eq(#plugin.spots, 3)
  local text = table.concat(plugin.help(), " ")
  t.truthy(text:find("wins 95", 1, true), "worked example")
  t.truthy(text:find("pays 8 to 1", 1, true), "tie odds")
  t.truthy(text:find("push", 1, true))
end)
