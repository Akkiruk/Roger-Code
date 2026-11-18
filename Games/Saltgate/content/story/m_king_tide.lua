-- The finale. The surge reaches the Sea Gate. Race the wall road and jump the gap the opening gate leaves, hold the control house,
-- face the Commissioner, then choose how Saltgate ends: leave on the last ferry, open the gate and stay, or keep the keys.
-- What the epilogue says depends on every choice that came before.
return function(api)
  api.step("wall", function()
    api.cutscene({
      { at = "seawall", look = "open_water", height = 10, seconds = 3, fade = "in", caption = "SATURDAY. THE KING TIDE." },
      { at = "seawall", look = "gate_house", height = 6, orbit = -50, seconds = 4,
        say = { "Captain Rook", "She's coming up, lass. The big one. The sea is not asking permission this time." } },
    })
    api.say("Tam", "Pit Wall to everybody. Gate sensors say the surge is forty minutes out. Old Saltgate is three minutes from the waterline.")
    api.say("Ferris", "Radio Lantern, live from a very damp mast. Saltgate, if you can hear me, the gate is open and the crowd is on the wall. Thank you. Thank you.")
    api.say("Sable", "Wren. The Authority has the gate house. They are going to close it by hand. Go. I will drive you to the wall.")
    local pick = api.choose("The whole crew is behind you. The rain is horizontal.", {
      "Everyone know their part? Go.",
      "I'll do it. You stay with the crowd.",
      "Sable, drive. I'll talk on the way.",
    })
    if pick == 1 then
      api.say("Rusty", "Crane ready. Admiral says he's ready. He is not. He is asleep. But he is ready in spirit.")
      api.tally("heart", 1)
    elseif pick == 2 then
      api.say("Mama Juno", "No, little crab. Not alone. Not tonight. We all go together or not at all.")
      api.tally("juno", 1)
    else
      api.say("Sable", "Talking is my second favourite thing to do in a car. Behind driving and slightly above not being arrested.")
      api.tally("sable", 1)
    end
  end)

  api.step("wheels", function()
    api.anyCar("Get the fastest car you can.")
  end, { at = "seawall" })

  api.step("run", function()
    api.say("Tam", "Wall road is clear but wet. It is a long straight with a gate at the end. The gate is opening. It will leave a gap.")
    api.hint("Floor it along the wall. The gate is opening. Keep it straight.")
    api.heat(2)
    api.drive("gate_house", { text = "Race along the sea wall road to the gate.", radius = 20, timer = 90, timerText = "SURGE",
      timerReason = "the surge reached the gate first" })
  end, { at = "seawall", give = { name = "car", kind = "sovereign" } })

  api.step("gap", function()
    api.say("Tam", "That is a gap. That is a very big gap. That is a gap with a sea in it. Wren, you have to jump.")
    api.say("Sable", "You can do this. You did the canal. You did the hairpins. You are Wren Calloway. Go, go, go!")
    api.hint("Full throttle, no steering, no braking. Land it on the far side of the wall.")
    api.jump({ text = "Jump the gap the opening gate leaves!", min = 16, place = "gate_house", failText = "you didn't clear the gap" })
    api.toast("AIR!", "toast")
  end, { at = "seawall", give = { name = "car", kind = "sovereign" } })

  api.step("control", function()
    api.say("Tam", "She flew. She actually flew. I will never doubt a woman in a car again. Control house is in front of you. The Hiccup is ready.")
    api.hold("gate_house", 8, { text = "Hold the panel while the Hiccup works.", away = "Get back to the control panel!",
      radius = 3 })
    api.toast("The gate is holding open!", "toast")
  end, { at = "gate_house", give = { name = "car", kind = "sovereign" } })

  api.step("vane", function()
    api.cutscene({
      { at = "gate_house", look = "seawall", height = 4, seconds = 3, fade = "in", caption = "THE CONTROL HOUSE" },
      { at = "seawall", look = "gate_house", height = 3, drift = { 0, 2, 0 }, seconds = 4,
        say = { "Vane", "You cannot hold it, Miss Calloway. The sea does not take sides. It simply is." } },
    })
    api.say("Vane", "I will make you an offer. I have been in this city longer than the Gilts. I do not like to waste a good driver.")
    api.say("Vane", "Be my Harbor Warden. The keys, the boats, the wall. You would be queen of the tide.")
    local pick = api.choose("Vane peels off both gloves. The rain washes her hands clean.", {
      "No. The gate stays open.",
      "Tell me about the deal you made with Juno.",
      "I'll think about it. Out loud.",
    })
    if pick == 1 then
      api.say("Vane", "Then you are a fool. A very brave, very wet fool. I will make a note.")
      api.remember("vane_refused", true)
      api.tally("heart", 1)
      api.tally("law", 1)
    elseif pick == 2 then
      api.say("Vane", "She gave me a girl and I gave her a street. It was a fair price. It is, as ever, a question of who paid.")
      api.say("Wren", "She paid three years of it. I paid the rest.")
      api.remember("vane_confronted", true)
      api.tally("juno", 1)
    else
      api.say("Vane", "Thinking aloud is how all tyrants begin. Go on. Say what you think. I am listening.")
      api.say("Wren", "I think I like a gate. I think a gate is a very powerful thing to hold.")
      api.say("Vane", "Yes. It is.")
      api.tally("greed", 2)
    end
    api.say("Harrow", "(arriving, wet, with a very large umbrella) Commissioner. I have a warrant. It is for you. I am so sorry. I wrote it myself.")
    if api.recall("harrow_joins") then
      api.say("Harrow", "I have six men behind me and a sandwich. They are all on your side. I counted twice.")
    end
  end, { at = "gate_house", give = { name = "car", kind = "sovereign" } })

  api.step("choice", function()
    api.say("Mama Juno", "(on the radio, from the crowd) Wren. We are all at the wall. We are all behind you. Whatever you pick, we will understand.")
    api.say("Tam", "The Hiccup is in your hand. The surge is two minutes out. The gate will do what you tell it to.")
    local options = {
      "Take the last ferry out.",
      "Open the gate. Stay. Rebuild.",
      "Keep the keys. Saltgate answers to me.",
    }
    local pick = api.choose("The whole of Saltgate waits. What does Wren do?", options)
    local ending = ({ "leave", "stay", "crown" })[pick]
    api.var("ending", ending)
    api.remember("ending", ending)
  end, { at = "gate_house", give = { name = "car", kind = "sovereign" } })

  api.step("epilogue", function()
    local ending = api.var("ending") or "stay"
    local juno = api.recall("juno_fate")
    local sable = api.score("sable") >= 4
    local crowd = api.recall("crowd_at_gate") or api.recall("crowd_with_lamps")
    api.music("finale")
    if ending == "leave" then
      api.cutscene({
        { black = true, title = "THE LAST FERRY", seconds = 3, fade = "both" },
        { at = "ferry", look = "open_water", height = 7, seconds = 4, fade = "in",
          caption = "The Tern pulls out of Saltgate at dawn." },
        { at = "ferry", look = "ferry", height = 4, drift = { 6, 0, 0 }, seconds = 4,
          say = { "Captain Rook", "That is the lot, lass. Everybody who wanted to come. You sure you want to stay aboard?" } },
        { at = "lighthouse", look = "ferry", height = 6, orbit = 60, seconds = 4,
          caption = "Wren Calloway drove off the pier, and kept going." },
        { black = true, seconds = 4, fade = "both",
          title = (juno == "forgiven") and "Juno opened a stall on the far shore. The first bowl was Wren's."
            or "Juno opened a stall on the far shore. Wren came by on Sundays. She always paid." },
        { black = true, seconds = 4, fade = "both",
          title = sable and "Sable took the next ferry. She said she was just visiting. She never left."
            or "Sable stayed behind with the gnome, and drove the harbor road at dawn." },
        { black = true, seconds = 4, fade = "both",
          title = "The Sea Gate closed behind them. Saltgate went on, one tide at a time." },
      })
      api.say("Wren", "Next ferry's at dawn. Plenty of time to see the town. Any town.")
    elseif ending == "stay" then
      api.cutscene({
        { black = true, title = "HIGH TIDE, HARBOR LIGHT", seconds = 3, fade = "both" },
        { at = "seawall", look = "gate_house", height = 8, seconds = 4, fade = "in",
          caption = "The gate stayed open. The sea went to the harbor basin, not the town." },
        { at = "seawall", look = "gate_house", height = 4, drift = { 0, 4, 0 }, seconds = 4,
          say = { "Harrow", "Commissioner Vane, by the power of this very wet warrant, you are under arrest. May I finish my sandwich first?" } },
        { at = "juno", look = "juno", height = 3, orbit = 30, seconds = 4,
          caption = crowd and "The street came out in lamps and held the wall until the water went down."
            or "The old town woke to dry cellars and a very loud radio." },
        { black = true, seconds = 4, fade = "both",
          title = (juno == "public") and "Juno stood at the stall and told the street the whole truth. They gave her a standing bowl."
            or "Juno reopened the stall. The first bowl went to the girl who drove the old town to safety." },
        { black = true, seconds = 4, fade = "both",
          title = "Rusty hung a sign over the yard: THE ADMIRAL'S. Tam wrote the wiring. Ferris read it aloud." },
        { black = true, seconds = 4, fade = "both",
          title = "Sable and Wren opened Calloway and Quinn, Drivers. They quarrel about the name every Tuesday." },
      })
      api.say("Wren", "The tide went out. The city stayed. So did I.")
    else
      api.cutscene({
        { black = true, title = "KING OF THE TIDE", seconds = 3, fade = "both" },
        { at = "seawall", look = "gate_house", height = 8, seconds = 4, fade = "in",
          caption = "The gate answered to Wren. Everyone else got a very good view." },
        { at = "gate_house", look = "seawall", height = 4, drift = { 0, 3, 0 }, seconds = 4,
          say = { "Vane", "Harbor Warden Calloway. I was right about you, you know. You are very good at holding doors." } },
        { at = "juno", look = "juno", height = 3, orbit = 30, seconds = 4,
          caption = "The old town stayed dry. It also stayed in debt." },
        { black = true, seconds = 4, fade = "both",
          title = sable and "Sable drove for the Warden. She said it was for the cars. It was for the cars." or "Sable left on the next boat." },
        { black = true, seconds = 4, fade = "both",
          title = (juno == "forgiven") and "Juno brought broth to the Warden's office every night. She never said a word."
            or "Juno cooked on the wall each evening. She stopped asking for forgiveness." },
        { black = true, seconds = 4, fade = "both",
          title = "The sea does not take sides. Wren held the gate. The rest of the city learned what that meant." },
      })
      api.say("Wren", "Every gate has a key. Every key has a flaw. Mine is that I like holding it.")
    end
    api.ending(ending)
    api.title("SALTGATE", "THE END")
    api.text("juno", "Whatever you chose, the stall will keep a bowl warm. Come home when you can.")
  end, { at = "gate_house", give = { name = "car", kind = "sovereign" } })
end
