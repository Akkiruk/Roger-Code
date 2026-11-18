-- Act 2, job 7: Cass Gilt has holed up in the old cannery on the Brine docks with the last of the family's money and a lot
-- of hired muscle. Ferris wants the story. A shootout with cartoon guns (people are knocked down, never hurt), then Cass.
return function(api)
  api.step("studio", function()
    api.say("Ferris", "Wren! Welcome. Sit. Or do not, I am pacing. Cass Gilt is broadcasting. Not literally. His hired men are, on a pirate band.")
    api.say("Ferris", "He has barricaded himself in the old cannery. He is threatening to burn the family ledgers if anyone comes near.")
    api.say("Wren", "We already have the ledger. Hobb's.")
    api.say("Ferris", "Then these are the other ledgers. The ones nobody has read. Aurelian's. If they burn, the story burns with them.")
    local pick = api.choose("Ferris wrings his hat. The cat watches.", {
      "I'll go in. Quietly, if I can.",
      "Let Cass burn them. We have enough.",
      "Why do you care so much about the story?",
    })
    if pick == 1 then
      api.say("Ferris", "That is what I like about you. A hero with a plan and a very small amount of ego.")
      api.tally("heart", 1)
    elseif pick == 2 then
      api.say("Ferris", "Enough? There is no such thing as enough. There is only too late. Please. Go.")
      api.tally("greed", 1)
    else
      api.say("Ferris", "Because the story is the only thing the Authority cannot outrun. Because someone should say the true thing out loud, and it keeps being me.")
      api.tally("law", 1)
    end
  end)

  api.step("wheels", function()
    api.anyCar("Get a car for the Brine docks.")
  end, { at = "studio" })

  api.step("approach", function()
    api.hint("The cannery is at the far end of the Brine docks. Park outside and go in on foot.")
    api.drive("cannery", { text = "Drive to the old cannery.", radius = 6 })
  end, { at = "studio", give = { name = "car", kind = "marlin" } })

  api.step("fight", function()
    api.say("Cass", "Who is that? Who is that on my dock? Boys! Boys, take care of this, I am busy being tragic!")
    api.say("Tam", "Pit Wall to Wren. Six hired hands. They have pop guns. Bright tracers, stars when they fall. Nobody gets hurt. That is a rule.")
    api.actor("crew", "cannery", { group = "cass_crew", count = 6, look = "thug" })
    api.hint("On foot, lock on with F and fire, or tackle with G. Ram them with the car if you must. They get up after a while.")
    api.defeat("cass_crew", { text = "Knock down Cass's crew." })
    api.say("Tam", "Six down, six stars, six sets of cartoon birds. Lovely. Cass is in the back with the ledgers.")
  end, { at = "cannery", give = { name = "car", kind = "marlin" } })

  api.step("cass", function()
    api.say("Cass", "Do you know what these books are worth? Do you know what I will do to you? I will call my brother!")
    api.say("Wren", "Aurelian is under a chandelier somewhere, hiding from the Authority. Nobody is coming, Cass.")
    api.say("Cass", "...Oh. Yes. He is hiding. He is very good at it. I am better at shouting.")
    local pick = api.choose("Cass is sitting on a crate of ledgers. He looks very small.", {
      "Hand the ledgers to Ferris. Go home.",
      "Take him to Harrow. Let the law have him.",
      "Take the ledgers. Leave him the dock.",
      "Join us. The Authority wants you too.",
    })
    if pick == 1 then
      api.say("Cass", "Home? I have no home. I have a tower and a lawyer. The lawyer left.")
      api.say("Wren", "Then buy a cat. Ferris has a good one.")
      api.remember("cass_fate", "free")
      api.tally("heart", 1)
    elseif pick == 2 then
      api.say("Cass", "Harrow? The man with the sandwiches? Fine. He will at least feed me.")
      api.remember("cass_fate", "law")
      api.tally("law", 2)
    elseif pick == 3 then
      api.say("Cass", "The dock? You are leaving me the dock? It is a very large dock and I am not at all good at being on it.")
      api.remember("cass_fate", "dock")
      api.tally("greed", 1)
    else
      api.say("Cass", "Join? Me? Cass Gilt, joining? Do I get a hat? I would like a hat.")
      api.say("Wren", "Ferris has hats.")
      api.remember("cass_fate", "join")
      api.tally("juno", 1)
      api.tally("heart", 1)
    end
    api.say("Tam", "Ledgers recovered. Quite a lot of crime in these. Some of it is poetry. I am reading the poetry first.")
  end, { at = "cannery", give = { name = "car", kind = "marlin" } })

  api.step("ferris", function()
    api.hint("Bring the ledgers back to Radio Lantern. Keep the Patrol off you.")
    api.drive("studio", { text = "Bring the ledgers back to Ferris.", noHeat = true, hotText = "Shake the Patrol first." })
    api.say("Ferris", "The ledgers! Oh, the ledgers! I am going to read them aloud for nine hours!")
    api.say("Ferris", "No. Not all of them. A selection. A tasteful selection, with my own commentary.")
    api.text("ferris", "Breaking: a radio host is brave and also terrified. More at eleven.")
  end, { at = "cannery", give = { name = "car", kind = "marlin" } })
end
