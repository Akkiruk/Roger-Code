-- Act 2, job 1 (Riptide opens): the harbor is sealed and Harrow wants Juno. A boat chase out of the pier.
return function(api)
  api.step("dawn", function()
    api.title("ACT TWO", "RIPTIDE")
    api.say("Captain Rook", "Morning, lass. Morning, Juno. I would say it is a fine one, but the Authority has tied my Tern to the dock with a chain.")
    api.say("Mama Juno", "Bart Rook, you have outlived three harbormasters. A chain will not stop you.")
    api.say("Captain Rook", "It is not the chain. It is the paperwork. They filed it in triplicate. Nobody argues with triplicate.")
    api.say("Harrow", "Mama Juno. Wren Calloway. Good morning. I have been looking for you both since the Gilt Tower, and I am so tired.")
    api.say("Wren", "Lieutenant Harrow. You look like you slept in your cruiser.")
    api.say("Harrow", "I did. Twice. Placing you under arrest, Miss Calloway. I will do it properly in a moment. I am finishing a sandwich.")
    local pick = api.choose("Harrow is mid-bite. The patrol boats are creeping in.", {
      "Take your time. Lunch is important.",
      "You are going to have to catch me.",
      "Juno, get in the boat. I'll handle him.",
    })
    if pick == 1 then
      api.say("Harrow", "Thank you. Do you know how hard it is to eat while chasing people? It is very hard.")
      api.tally("law", 1)
    elseif pick == 2 then
      api.say("Harrow", "I know. I have been chasing you since you were nineteen. I have had a lot of time to think of ways.")
    else
      api.say("Harrow", "Handle me? I am stood right here. I am a very handleable man. It is why I get overlooked.")
      api.tally("juno", 1)
    end
    api.say("Captain Rook", "Right then. The Tern is chained. My skiff is not. Mind her paint, lass. She has feelings.")
  end)

  api.step("skiff", function()
    api.hint("The skiff is at the end of the pier. Jump in and open her up. Patrol boats cut across the harbor mouth.")
    api.car("skiff", "ferry", { name = "boat", label = "skiff" })
    api.getIn("boat", "Get into Captain Rook's skiff.")
    api.heat(3)
    api.toast("Patrol boats are closing the harbor mouth!", "alarm")
  end, { at = "ferry" })

  api.step("run", function()
    api.say("Tam", "Pit Wall to Wren! Three cruisers on the quay, two boats at the mouth. There is a gap. It is a very small gap.")
    api.ensureCar("boat", "skiff", "ferry", { label = "skiff" })
    -- (the lighthouse stands on Gull Rock's headland; a boat makes for the bay under it, round the west shore: about
    -- 950 units, so the net closes in 150 s, not the 80 the step 0 harbor needed)
    api.hint("Round the west shore to the bay under the lighthouse. The patrol boats are slow to turn, so cut inside them.")
    api.drive("lighthouse_landing", { name = "boat", text = "Slip the patrol boats. Make for the lighthouse.", timer = 150, timerText = "NET",
      timerReason = "the patrol boats closed the net" })
  end, { at = "ferry", give = { name = "boat", kind = "skiff" } })

  api.step("ashore", function()
    api.say("Mama Juno", "Well. That is the most exercise I have had since the Tidewater Ball. Wren, you are an artist.")
    api.say("Wren", "I'm a driver. The artist was the skiff.")
    api.say("Mama Juno", "Listen. The Gilts are finished, but someone has filled the hole they left. The Harbor Authority. Commissioner Vane.")
    api.say("Wren", "Who is she?")
    api.say("Mama Juno", "Someone who wears gloves in July and calls a flood a 'managed event'. I have known her for a long time.")
    local pick = api.choose("Juno looks out over the water. What now?", {
      "Hide out in Old Saltgate for now.",
      "We should leave. Rook's boat, tonight.",
      "We take the fight to her. Whoever she is.",
    })
    if pick == 1 then
      api.say("Mama Juno", "The safehouse. Good. A stove, a mattress and Pip's terrible jokes. Done.")
      api.tally("juno", 1)
      api.remember("plan_hide", true)
    elseif pick == 2 then
      api.say("Mama Juno", "Leave? After last night? Mm. I would, once. I am too old and my stall is too good.")
      api.tally("greed", 1)
      api.remember("plan_leave", true)
    else
      api.say("Mama Juno", "That is the Calloway I remember. Stubborn as a barnacle. Come, I will tell you what I know.")
      api.tally("heart", 1)
      api.remember("plan_fight", true)
    end
    api.say("Harrow", "(far off, through a loudhailer) Calloway! I am still going to arrest you! Just not right now! I am eating!")
    api.unlock("bart")
    api.unlock("harrow")
    api.text("bart", "Skiff's got a scratch. You owe me a coat of paint and a story. Fair trade.")
  end, { at = "lighthouse" })
end
