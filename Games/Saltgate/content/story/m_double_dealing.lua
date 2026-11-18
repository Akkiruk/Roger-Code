-- Act 2, job 8: Rusty is taken from his yard on the Commissioner's orders. Chase Harrow's van, talk to Harrow, then face
-- Juno with what you know. The choice at the end is who Juno is to Wren from here on.
return function(api)
  api.step("news", function()
    api.say("Pip", "Wren! Wren! They took Rusty! Wardens and a van, they smashed the gate! Admiral is on the roof screaming!")
    api.say("Wren", "Pip. Breathe. Where did they take him?")
    api.say("Pip", "I do not know! The van went down the coast road! Nana says come to the stall, but there is no time, is there?")
    api.say("Wren", "No. There is not. Stay with Juno. I am on it.")
  end)

  api.step("wheels", function()
    api.anyCar("Get a fast car.")
  end, { at = "juno" })

  api.step("yard", function()
    api.hint("Rusty's yard is in Cinder Flats. The van went along the coast road toward the Patrol pier.")
    api.drive("scrapyard_gate", { text = "Go to Rusty's yard. See what is left.", radius = 6 })
    api.say("Wren", "The gate is flat. The Sovereign is gone. Wait, no, it is behind the crane. They missed it.")
    api.say("Tam", "Pit Wall to Wren. I tracked the van. Harrow's van, not the wardens. It is on the coast road. Go, go, go.")
  end, { at = "juno", give = { name = "car", kind = "marlin" } })

  api.step("chase", function()
    api.actor("runner", "scrapyard_gate", { name = "van", vehicle = "tidewater", route = { "patrol_pier" }, flees = true, label = "Harrow's van" })
    api.hint("The van is slow. Ram it to a stop. Don't wreck it. Rusty is inside.")
    api.chase("van", { text = "Run down Harrow's van. Rusty is inside.", failText = "the van reached the Patrol pier" })
  end, { at = "scrapyard_gate", give = { name = "car", kind = "marlin" } })

  api.step("harrow", function()
    api.say("Harrow", "Stop! Stop, stop. I will stop. I have stopped. Please do not ram the van again. The back door is already rattling.")
    api.say("Wren", "Open it, Harrow. Now.")
    api.say("Harrow", "I cannot. I have an order. A 'Tide Order'. It says: 'clear Old Saltgate'. It says a great many things. I do not like any of them.")
    api.say("Rusty", "(from inside the van) Harrow, tell her I am fine. Tell her I miss the gull.")
    local pick = api.choose("Harrow is shaking. The sandwich is on the dashboard, half eaten.", {
      "Let him out, Dov. You know this is wrong.",
      "Then drive. I'll follow you to the pier.",
      "Fine. Tell me what the order says.",
    })
    if pick == 1 then
      api.say("Harrow", "It is wrong. It is so wrong. I think about the order, and then I think about my mother, who lives on Cooper Street. Which is in Old Saltgate.")
      api.say("Harrow", "I cannot open it. But I can drive slowly. That is a thing I can do. Take that as a promise.")
      api.tally("law", 2)
      api.remember("harrow_doubts", true)
    elseif pick == 2 then
      api.say("Harrow", "You will follow me? Into the pier station? That is the stupidest thing anyone has said to me this month. And I once worked with a man who ate soap.")
      api.tally("greed", 1)
    else
      api.say("Harrow", "It says the Commissioner may close the sea gate at her discretion. It says the old town is 'surplus to the plan'. It says...")
      api.say("Harrow", "It says nothing about people. I read it twice. Nothing about people.")
      api.tally("law", 1)
      api.remember("harrow_doubts", true)
    end
    api.say("Harrow", "Go to your safehouse, Calloway. I will keep Rusty fed. If you come for him, do it properly. I will not be looking.")
    api.say("Rusty", "(muffled) Wren. Ask Juno about the tip. She will know what I mean.")
  end, { at = "scrapyard_gate", give = { name = "car", kind = "marlin" } })

  api.step("home", function()
    api.hint("The safehouse is in Old Saltgate. Juno is waiting. This one is not a job. It is a conversation.")
    api.drive("safehouse", { text = "Go to the safehouse. Talk to Juno.", radius = 4 })
  end, { at = "scrapyard_gate", give = { name = "car", kind = "marlin" } })

  api.step("juno", function()
    api.say("Mama Juno", "You look like a woman with a question. Sit. The soup is hot. The soup will not answer it, but it is hot.")
    api.say("Wren", "Rusty said to ask you about the tip.")
    api.say("Mama Juno", "...Ah.")
    api.say("Wren", "Three years ago. The docks. The Patrol were waiting. Somebody told them. I have thought it was Sable for three years.")
    api.say("Mama Juno", "It was not Sable. It was me, Wren.")
    api.say("Mama Juno", "The Commissioner, back when she was a captain, came to my stall. She said: give me one job, one route, one night, and the old town gets left alone.")
    api.say("Mama Juno", "I thought: one night, one small crew. You would get a month. Maybe two. Vane made it three years. I did not know until the sentence was read.")
    api.say("Wren", "And you did not think to tell me.")
    api.say("Mama Juno", "I thought of nothing else. For three years. I put money in a jar every week. Look. It is all in the jar. It is yours.")
    if api.recall("sable_suspects_juno") then
      api.say("Sable", "(arriving) I told her I had a picture. I did not want to be right.")
    end
    local pick = api.choose("Juno puts a very full jar on the table. Her hands are steady. Her eyes are not.", {
      "I forgive you. I do. Help me fix it.",
      "I don't forgive you. But I'll finish this.",
      "You tell the street. All of it. Out loud.",
      "Keep the jar. I need to think.",
    })
    if pick == 1 then
      api.say("Mama Juno", "Oh, little crab. I do not deserve that. Thank you. I will take it and never put it down.")
      api.remember("juno_fate", "forgiven")
      api.tally("juno", 3)
      api.tally("heart", 2)
    elseif pick == 2 then
      api.say("Mama Juno", "That is more than fair. It is more than I would offer. I will take it.")
      api.remember("juno_fate", "cold")
      api.tally("juno", 1)
    elseif pick == 3 then
      api.say("Mama Juno", "Out loud. In front of everybody. Yes. Yes, I will. Ferris will have to lend me his microphone.")
      api.remember("juno_fate", "public")
      api.tally("law", 2)
      api.tally("heart", 1)
    else
      api.say("Mama Juno", "Of course. Take all the time you need. The jar will keep. So will I.")
      api.remember("juno_fate", "waiting")
    end
    api.say("Mama Juno", "There is one more thing. The sea gate. The old town is outside the wall, and I knew it a year ago.")
    api.say("Mama Juno", "I did not know she would close it. I told myself she would not. I told myself a lot of things.")
    api.text("juno", "Stay with us tonight. Pip made a bed. It is mostly pillows. It is a very good bed.")
  end, { at = "safehouse" })
end
