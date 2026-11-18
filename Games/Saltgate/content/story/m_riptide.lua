-- Act 2 finale: break Rusty out of the Patrol pier station. Everyone in the crew has a part. The way out is up the hairpins
-- and down the funicular's steep slope. Ends with the Commissioner on every radio in the city.
return function(api)
  api.step("council", function()
    api.say("Tam", "Right. Everybody here? Good. Pit Wall is a very small room with very many people in it. Lovely.")
    api.say("Tam", "The Patrol pier station. One front gate, two guard posts and a back cell block that faces the water. Rusty is in the third cell.")
    api.say("Sable", "I take the gate, you take the road. Ferris keeps the Patrol band busy. Tam keeps the cameras blind. Easy.")
    api.say("Ferris", "I will be reading aloud from Aurelian's ledgers. Page nine is a recipe for lobster bisque. It will bore them to tears.")
    local pick = api.choose("Everyone looks at Wren.", {
      "Quiet. In and out. No heroics.",
      "Loud. Break the gate. Rusty will love it.",
      "Let Harrow help. He said he wouldn't look.",
    })
    if pick == 1 then
      api.say("Sable", "No heroics. I will hold you to that. I will also quietly be disappointed.")
      api.tally("law", 1)
    elseif pick == 2 then
      api.say("Sable", "Loud! Finally! I have had a battering ram in my boot for a week.")
      api.tally("greed", 1)
      api.tally("sable", 1)
    else
      api.say("Tam", "Dov Harrow? The sandwich man? He picked up on the first ring. He says he will leave the third cell unlocked and go for a long lunch.")
      api.say("Wren", "That's the most dangerous thing a Patrol officer has ever done.")
      api.remember("harrow_helped", true)
      api.tally("law", 2)
    end
  end)

  api.step("wheels", function()
    api.anyCar("Get the getaway car.")
  end, { at = "tam_garage" })

  api.step("pier", function()
    api.say("Tam", "Pit Wall to Wren. Pier ahead. Cameras are blind. Guards are... mostly awake.")
    api.hint("Park at the pier station gate. Don't come in hot or they will lock the cells.")
    api.drive("patrol_pier", { text = "Drive up to the Patrol pier station.", noHeat = true, hotText = "Too hot. Shake them off first." })
  end, { at = "tam_garage", give = { name = "car", kind = "marlin" } })

  api.step("breakout", function()
    api.actor("crew", "patrol_pier", { group = "guards", count = 3, look = "warden" })
    api.say("Warden", "Hey! Stop that car! This is a restricted... oh no. Oh no, it is her.")
    api.hint("Three guards on the pier. Knock them down. Quickly. Then Tam opens the cell.")
    api.defeat("guards", { text = "Knock down the pier guards." })
    api.say("Tam", "Cell open! Rusty! Move! He is coming! He has a bag! Why does he have a bag?")
    api.hold("patrol_pier", 5, { text = "Hold at the gate while Rusty gets out.", away = "Get back to the pier gate!", radius = 4 })
    api.say("Rusty", "Admiral's gull friends brought me a sandwich through the bars. I could not leave it.")
    api.toast("The whole station is awake! Go!", "alarm")
    api.heat(4)
  end, { at = "patrol_pier", give = { name = "car", kind = "marlin" } })

  api.step("climb", function()
    api.say("Sable", "Heat is four! I have the cruisers on the quay! Wren, up the Heights! Up, up, up!")
    api.hint("Hairpins first, then the funicular line at the top. It is the only way they cannot follow.")
    api.drive("funicular_top", { text = "Up the hairpins to the funicular top station.", timer = 100, timerText = "CHASE",
      timerReason = "the Patrol boxed you in" })
  end, { at = "patrol_pier", give = { name = "car", kind = "marlin" } })

  api.step("funicular", function()
    api.say("Tam", "Okay, so the funicular is a track. A very steep track. It runs straight down the cliff from the top station to the bottom station.")
    api.say("Rusty", "That is not a road.")
    api.say("Tam", "It is a road that happens to have rails on it.")
    api.hint("Steer straight down the slope. Hold the brake lightly. The Patrol cannot follow on the rails.")
    api.drive("funicular_bottom", { text = "Ride the funicular slope to the bottom.", timer = 40, timerText = "SLOPE",
      timerReason = "the Patrol caught you at the bottom" })
  end, { at = "funicular_top", give = { name = "car", kind = "marlin" } })

  api.step("clear", function()
    api.loseHeat("Lose the Patrol at the foot of the funicular.")
  end, { at = "funicular_bottom", give = { name = "car", kind = "marlin" } })

  api.step("broadcast", function()
    api.cutscene({
      { at = "safehouse", look = "juno", height = 3, seconds = 3, fade = "in", caption = "THE SAFEHOUSE, THAT NIGHT" },
      { at = "safehouse", look = "safehouse", height = 2, drift = { 2, 0, 0 }, seconds = 4,
        say = { "Vane", "Citizens of Saltgate. This is Commissioner Vane. At the next king tide, the Harbor Authority will close the sea gate." } },
      { at = "safehouse", look = "safehouse", height = 2, drift = { 0, 2, 0 }, seconds = 4,
        say = { "Vane", "Properties beyond the wall are subject to managed retreat. You have three days. Thank you for your cooperation." } },
    })
    api.say("Pip", "Three days. That is Saturday. That is my birthday.")
    api.say("Mama Juno", "Then we will make it a good one. We have three days, a safehouse, a ferry captain and a radio host.")
    api.say("Rusty", "And a gull. Do not forget the gull. He has a part.")
    local pick = api.choose("The whole crew is in the cellar. The water pipes are creaking.", {
      "Three days is enough. Let's stop her.",
      "We need more people. A lot more.",
      "We run. Take everyone out of the city.",
    })
    if pick == 1 then
      api.say("Sable", "Confident. I like that in a driver and fear it in a person.")
      api.tally("heart", 1)
    elseif pick == 2 then
      api.say("Ferris", "I will put it on the air. Everybody, listen. If you can drive, if you can shout, if you can bake, we need you.")
      api.tally("juno", 1)
      api.remember("called_the_street", true)
    else
      api.say("Mama Juno", "Run? With three hundred families? On one ferry? Wren. Tell me you have a better idea.")
      api.tally("greed", 1)
    end
    api.say("Tam", "Pit Wall is yours. Everything I have is yours. Act three starts tomorrow. I have named the plan. It is called 'Plan'. I will add to it later.")
    api.text("tam", "Every gate in this city has a key, and every key has a boring little flaw. Find me the flaw.")
  end, { at = "safehouse" })
end
