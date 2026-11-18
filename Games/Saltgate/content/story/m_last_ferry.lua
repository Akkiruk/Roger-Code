-- Act 3, job 7: the night before the surge. The Tern takes the old town out to the lighthouse's high ground in a storm, with a
-- patrol boat in the channel. A boat chase to stop it, then an escort across the harbor.
return function(api)
  api.step("storm", function()
    api.cutscene({
      { at = "ferry", look = "open_water", height = 8, seconds = 3, fade = "in", caption = "THE FERRY PIER, THE NIGHT BEFORE" },
      { at = "ferry", look = "ferry", height = 4, drift = { 0, -3, 0 }, orbit = 40, seconds = 4,
        say = { "Captain Rook", "Tide's on the turn, lass. I can smell it in my teeth. She is going to be a big one." } },
    })
    api.say("Captain Rook", "The Tern is loaded. Two hundred on the first trip. Old folk first, then children, then the ones who can swim.")
    api.say("Mama Juno", "I will ride with them. Someone needs to count heads. Someone needs to keep Pip from steering.")
    api.say("Pip", "I would be a fine steerer! I have been steering Dumpling! Dumpling is a van! It is basically a boat!")
    local pick = api.choose("The first load is aboard. Juno holds a clipboard. The rain has started.", {
      "Juno, ride along. I'll clear the channel.",
      "Stay. I need you at the gate tomorrow.",
      "Pip, you're with me. I'll look after you.",
    })
    if pick == 1 then
      api.say("Mama Juno", "Counting heads. I can do that. I have counted noodles for forty years.")
      api.remember("juno_on_boat", true)
      api.tally("juno", 1)
    elseif pick == 2 then
      api.say("Mama Juno", "At the gate? Tomorrow? I will be there. In my good apron. With the big pot.")
      api.tally("heart", 1)
    else
      api.say("Pip", "With you? In the skiff? Wren, I am going to be the best first mate ever. I am going to wear a hat.")
      api.remember("pip_with_wren", true)
      api.tally("heart", 1)
    end
    api.say("Captain Rook", "Go on, lass. Get the skiff. Vane's boat is in the channel. She is called the Prudence. She is not.")
  end)

  api.step("skiff", function()
    api.car("skiff", "ferry", { name = "boat", label = "skiff" })
    api.getIn("boat", "Get into Captain Rook's skiff.")
  end, { at = "ferry" })

  api.step("block", function()
    api.say("Tam", "Pit Wall to Wren! Prudence is lying across the channel. If she stays there, the Tern cannot get out. You have to move her.")
    api.ensureCar("boat", "skiff", "ferry", { label = "skiff" })
    api.actor("runner", "patrol_pier", { name = "prudence", vehicle = "patrol_boat", route = { "open_water" }, flees = true, label = "Prudence" })
    api.heat(3)
    api.hint("Cut across her bow and ram her side. She is heavy and slow. Don't get under her stern.")
    api.chase("prudence", { text = "Ram the patrol boat Prudence out of the channel.",
      failText = "the Prudence blocked the channel" })
    api.say("Warden", "(on the Prudence) We give up! We give up! The sea is up my trousers!")
  end, { at = "ferry", give = { name = "boat", kind = "skiff" } })

  api.step("escort", function()
    api.say("Captain Rook", "Channel's clear. Casting off. Stay close, lass. She does not like the swell and the swell does not like her.")
    api.ensureCar("boat", "skiff", "ferry", { label = "skiff" })
    api.actor("runner", "ferry", { name = "tern", vehicle = "tidewater", route = { "lighthouse" }, label = "the Tern" })
    api.hint("Stay beside the Tern. If it falls behind, wait. If a wave comes, steer into it.")
    api.escort("tern", "lighthouse", { text = "Escort the Tern across the harbor.", max = 80,
      failText = "the Tern was lost in the storm" })
  end, { at = "ferry", give = { name = "boat", kind = "skiff" } })

  api.step("ashore", function()
    api.say("Captain Rook", "Landfall! Everybody off! Mind the step. There is no step. Mind the rock!")
    api.say("Pip", "We are on a lighthouse! I have always wanted to be on a lighthouse!")
    if api.recall("juno_on_boat") then
      api.say("Mama Juno", "All two hundred. I counted. Twice. One of them was a dog, but I counted him as well.")
    end
    local pick = api.choose("The first load is safe. The wind is howling. Rook looks back at the city.", {
      "Four trips. Can you do it?",
      "Stay on the lighthouse. Ride it out.",
      "Tomorrow, we open the gate. Everyone.",
    })
    if pick == 1 then
      api.say("Captain Rook", "Four trips if the sea is kind. Three if it is not. Two if I'm a fool. I have been a fool before. I will manage.")
      api.tally("heart", 1)
    elseif pick == 2 then
      api.say("Captain Rook", "Ride it out? I have ridden worse. But the city does not ride; it drowns. Somebody has to open the gate.")
      api.tally("greed", 1)
    else
      api.say("Captain Rook", "That is the plan. I like it. It is simple. The best ones are, mostly.")
      api.tally("law", 1)
    end
    api.text("bart", "Tern's safe. Four trips. Pip says the lighthouse smells of cheese. He is right.")
  end, { at = "lighthouse", give = { name = "boat", kind = "skiff" } })
end
