-- Act 1 finale: the Gilt Tower. Drive Juno to the doors, hold the car while she works, then run down the Heights to the
-- last ferry. The ferry will not leave (that is the next act).
return function(api)
  api.step("plan", function()
    api.say("Mama Juno", "The Gilts own the docks, the Patrol and half of Lantern Row.")
    api.say("Mama Juno", "Tonight they pay what they owe the city. Then you and I take the last ferry out.")
    api.say("Wren", "I'll drive. You do the talking.")
    api.say("Tam", "Pit Wall is live! I have eyes on the tower. Eight cameras. I have blinded six. Two are shy.")
    local pick = api.choose("Juno asks you quietly: what do we take?", {
      "What the ledger says they owe.",
      "Every last coin in that vault.",
      "Nothing. Just the ledger on air.",
    })
    if pick == 1 then
      api.say("Mama Juno", "To the penny. Good. I did not raise you to be greedy. Only exact.")
      api.tally("juno", 1)
      api.remember("tower_exact", true)
    elseif pick == 2 then
      api.say("Mama Juno", "Hm. Every coin. The Gilts would call that vulgar. I call it thorough.")
      api.tally("greed", 2)
      api.remember("tower_all", true)
    else
      api.say("Mama Juno", "Noble. Pointless. But noble. We will see how the evening goes.")
      api.tally("heart", 1)
      api.tally("law", 1)
      api.remember("tower_air", true)
    end
    api.say("Mama Juno", "Get a fast car. Quick. The kind with a back seat for a woman of my stature.")
  end)

  api.step("car", function()
    api.hint("The Sovereign is Rusty's now, but any quick car will do. Juno rides in the back.")
    api.anyCar("Get a fast car.")
  end, { at = "juno" })

  api.step("doors", function()
    api.hint("Gilt Heights is up the hill. The hairpins are fastest if you do not cut the corners.")
    api.drive("gilt_door", { text = "Drive Juno to the Gilt Tower doors." })
  end, { at = "juno", give = { name = "car", kind = "marlin" } })

  api.step("hold", function()
    api.cutscene({
      { at = "gilt_door", look = "gilt_lot", height = 3, seconds = 3, fade = "in", caption = "THE GILT TOWER" },
      { at = "gilt_door", look = "gilt_door", height = 2, drift = { 0, 3, 1 }, seconds = 3,
        say = { "Aurelian", "Mama Juno. How unexpected. And you brought your little driver. How quaint." } },
      { at = "gilt_lot", look = "gilt_door", height = 4, seconds = 3,
        say = { "Mama Juno", "I brought a ledger, Aurelian. And a debt. Hold your breath. This will not take long." } },
    })
    api.say("Tam", "Juno is inside! Vault door opening... now! Wren, hold the car at the doors. Do not wander off.")
    api.hold("gilt_door", 6, { text = "Hold the car at the doors while Juno works.", away = "Get back to the tower doors!", radius = 2 })
    api.toast("The tower's lit up like a lighthouse. GO!", "alarm")
    api.heat(4)
    api.say("Mama Juno", "Done! Drive, Wren! And do not dawdle, I am wearing the nice shoes!")
  end, { at = "gilt_door", give = { name = "car", kind = "marlin" } })

  api.step("ferry", function()
    api.hint("Down the hairpins, along the coast road, straight to the ferry pier.")
    api.timer(120, "FERRY", "the ferry sailed without you")
    api.drive("ferry", { text = "Make the last ferry!" })
    api.stopTimer()
  end, { at = "gilt_door", give = { name = "car", kind = "marlin" } })

  api.step("dawn", function()
    api.cutscene({
      { at = "ferry", look = "open_water", height = 6, seconds = 3, fade = "in", caption = "THE FERRY PIER, 4 A.M." },
      { at = "ferry", look = "ferry", height = 3, drift = { 4, 0, 0 }, seconds = 3,
        say = { "Mama Juno", "Look at it, Wren. All those lights, and not one of them belongs to a Gilt any more." } },
    })
    api.say("Wren", "Next ferry's at dawn. Plenty of time to see the town.")
    api.say("Mama Juno", "Mmm. About that. Do you hear it?")
    api.say("Radio", "...by order of the Harbor Authority, all ferry services are suspended until further notice. Residents are asked to remain indoors.")
    api.say("Wren", "Harbor Authority. That is a new name.")
    api.say("Mama Juno", "It is a new name on an old kind of trouble. Come on. Soup first. Worry after.")
    api.say("Sable", "Evening, Calloway. Nice driving. I watched you come down the Heights. Rattled a few windows.")
    api.say("Wren", "Sable Quinn. Three years, and you pick tonight to say hello.")
    api.say("Sable", "Tonight is when it gets interesting.")
    api.unlock("sable")
    api.text("juno", "Safe house in Old Saltgate. Come by tomorrow. Bring the car and an appetite.")
  end, { at = "ferry" })
end
