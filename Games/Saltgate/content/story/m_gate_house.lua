-- Act 3, job 6: Harrow asks to meet in a car park, and what he does depends on whether you earned him. Then the Sea Gate's
-- control house, on foot: the gate guards, the Hiccup, and a crowd at the fence.
return function(api)
  api.step("lot", function()
    api.say("Harrow", "Calloway. Do not look at the cruiser. I am not in it. I am merely near it. This is a private conversation between a man and some tarmac.")
    api.say("Wren", "Dov. What's going on?")
    if api.score("law") >= 5 then
      api.say("Harrow", "I read the order twice more. Then I read the ledgers on the radio. Then I phoned my mother.")
      api.say("Harrow", "I am coming with you. Not as a Patrol officer. As someone who ate a sandwich in front of a gate and decided it was the last one.")
      api.remember("harrow_joins", true)
    elseif api.score("law") >= 3 then
      api.say("Harrow", "I cannot join you. But I can leave a side door unlocked. And I can be very slow at the gate. I am a very slow man.")
      api.remember("harrow_slow", true)
    else
      api.say("Harrow", "I am here to ask you to stop. The Commissioner has a plan, and plans survive. People do not necessarily. I would like to keep as many as I can.")
      api.say("Harrow", "I will not help you. I will not stop you either. I have run out of good ideas, and I have a sandwich.")
    end
    if api.recall("harrow_helped") then
      api.say("Harrow", "I left a cell unlocked for you once. I am still not sure that was legal. It felt like a good rule to break.")
    end
    local pick = api.choose("Harrow looks up at the sea wall, then down at his shoes.", {
      "Dov, the old town is your mother's town.",
      "Say you'll look away. That is enough.",
      "We'll knock them down gently.",
    })
    if pick == 1 then
      api.say("Harrow", "It is. It is. I have said that to myself every night this week. It has not helped. But it has not hurt.")
      api.tally("law", 1)
    elseif pick == 2 then
      api.say("Harrow", "I will look at the sky. It is a very nice sky. It has a gull in it.")
    else
      api.say("Harrow", "They are wardens. They sign up for a pension and a hat. A knock on the head is within their terms.")
    end
  end)

  api.step("wheels", function()
    api.anyCar("Get a car for the Sea Gate.")
  end, { at = "harrow_lot" })

  api.step("approach", function()
    api.say("Tam", "Pit Wall! I have the Hiccup in my lap and I am not allowed to touch it. Gate house is on the sea wall road. Park outside. Go in on foot.")
    api.hint("The Sea Gate is at the east end of the wall. Park by the fence, not on the road.")
    api.drive("seawall", { text = "Drive to the Sea Gate.", radius = 6 })
  end, { at = "harrow_lot", give = { name = "car", kind = "marlin" } })

  api.step("guards", function()
    if api.recall("crowd_at_gate") then
      api.say("Crowd", "(from the fence) Saltgate! Saltgate! Saltgate! Open the gate! Let the sea in!")
    elseif api.recall("crowd_with_lamps") then
      api.say("Crowd", "(from the fence) Lamps up! Lamps up! Let them see us!")
    end
    local count = api.recall("harrow_joins") and 3 or 6
    api.say("Warden", "Halt! This is a restricted area! This is a sea gate! It is very important and it is not for you!")
    api.actor("crew", "gate_house", { group = "gate", count = count, look = "warden" })
    api.hint("On foot, lock on with F and fire, or tackle with G. They are not tough. They are numerous.")
    api.defeat("gate", { text = "Knock down the gate house guards (" .. count .. ")." })
    if api.recall("harrow_joins") then
      api.say("Harrow", "That is the last one. I have never so enjoyed paperwork I intend to never file.")
    end
  end, { at = "seawall", give = { name = "car", kind = "marlin" } })

  api.step("hack", function()
    api.say("Tam", "Okay. Control house. Put the fleet key in. Then the gate key. Then the Hiccup. Then press the doorbell. That is my best advice.")
    api.hold("gate_house", 8, { text = "Hold at the control panel while the Hiccup works.", away = "Get back to the control panel!", radius = 3 })
    api.toast("The gate is unlocked. For now.", "toast")
    api.say("Tam", "It worked! It worked and it did not explode! I am going to sit down and cry a bit. Not now. Later.")
    api.say("Wren", "The gate won't close on its own now?")
    api.say("Tam", "Not unless someone puts a bigger key in. And there is only one thing in Saltgate bigger than my Hiccup. It is Vane's temper.")
  end, { at = "gate_house", give = { name = "car", kind = "marlin" } })

  api.step("fence", function()
    api.heat(3)
    api.toast("Sirens! The Commissioner knows!", "alarm")
    api.say("Harrow", "Go. Go. I will say you went to the left. You went to the right. I am a terrible liar. It is my best quality.")
    api.hint("Get off the sea wall and lose the Patrol. Saturday is tomorrow.")
    api.loseHeat("Lose the Patrol and get away from the Sea Gate.")
  end, { at = "gate_house", give = { name = "car", kind = "marlin" } })
end
