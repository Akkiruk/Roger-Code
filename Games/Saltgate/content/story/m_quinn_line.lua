-- Act 2, job 2: Sable Quinn, who drove away three years ago. Learn her line up the hairpins, then beat her down them.
return function(api)
  api.step("fountain", function()
    api.say("Sable", "Calloway. You look rested. Prison suits you. It is the cheekbones.")
    api.say("Wren", "Quinn. Three years. You could have written.")
    api.say("Sable", "Letters get read. By people who then come looking for you. I was being tactful.")
    api.say("Sable", "You think I tipped the Patrol. I did not. I want to show you something instead of arguing. Follow me up the Heights.")
    local pick = api.choose("Sable leans on a cherry-red coupe. Her smile is not quite sure.", {
      "Show me. I'll decide after.",
      "Why should I follow you anywhere?",
      "You left me at the docks, Sable.",
    })
    if pick == 1 then
      api.say("Sable", "Fair. That is more than I deserve. Keep up. I do not slow for anyone.")
      api.tally("sable", 1)
    elseif pick == 2 then
      api.say("Sable", "Because you are curious. Because you are bored of being a delivery girl. Because I have a better car.")
    else
      api.say("Sable", "I did. I know I did. I have spent three years learning what that cost. Come up the hill. Please.")
      api.tally("sable", 2)
      api.tally("heart", 1)
    end
  end)

  api.step("wheels", function()
    api.hint("Her car is quick and so is she. Any car you like. Pick one you trust on a corner.")
    api.anyCar("Get a car you trust on corners.")
  end, { at = "park_fountain" })

  api.step("follow", function()
    api.say("Tam", "Pit Wall to Wren. She is quick. Do not try to out-drive her, just learn the line. Where she brakes, where she cuts.")
    api.actor("runner", "park_fountain", { name = "sable", vehicle = "sovereign", route = { "hairpin_top" }, label = "coupe" })
    api.hint("Stay close enough to see her brake lights. Brake where she brakes.")
    api.tail("sable", { text = "Follow Sable up the hairpins. Learn her line.", min = 5, max = 50, spot = 12 })
  end, { at = "park_fountain", give = { name = "car", kind = "marlin" } })

  api.step("top", function()
    api.say("Sable", "That is the top of the Heights. See the mast? See the tower? Everything in this city runs downhill to the sea.")
    api.say("Sable", "Which includes the water. Which is why I brought you up here. Listen.")
    api.say("Sable", "The Authority has a plan for the sea wall. I saw the drawings at the motor pool. Not the whole thing. Enough.")
    api.say("Wren", "Enough for what?")
    api.say("Sable", "Enough that I want to race you down before I tell you. First one to the foot of the hill gets to ask the first question.")
  end, { at = "hairpin_top", give = { name = "car", kind = "marlin" } })

  api.step("race", function()
    api.say("Sable", "Fifty-five seconds. That was my best. Beat it. Three, two, one.")
    api.hint("Downhill the Marlin will want to run wide. Brake before the hairpin and use the whole road.")
    api.drive("hairpin_foot", { text = "Race Sable down the hairpins.", timer = 55, timerText = "RACE", timerReason = "Sable beat you down" })
  end, { at = "hairpin_top", give = { name = "car", kind = "marlin" } })

  api.step("deal", function()
    api.say("Sable", "Hm. That was good. Better than I expected. Slightly better than me, and I will deny it in public.")
    api.say("Sable", "First question, then. Ask.")
    local ask = api.choose("Your first question to Sable Quinn?", {
      "Who tipped the Patrol, three years ago?",
      "What did you see at the motor pool?",
      "Why come back now?",
    })
    if ask == 1 then
      api.say("Sable", "Someone in Juno's kitchen, or near it. I do not know who, but I have a picture. I am working on it.")
      api.say("Sable", "Do not tell her I said so. Not yet.")
      api.remember("sable_suspects_juno", true)
    elseif ask == 2 then
      api.say("Sable", "Tide tables. A schedule for the sea gate. And a line: 'Old Saltgate, outside the barrier'.")
      api.remember("sable_tide_tables", true)
    else
      api.say("Sable", "Because you were out. Because I owed you. Because I had a feeling that city was about to need a driver more than a thief.")
      api.tally("sable", 1)
    end
    api.say("Sable", "I want in, Calloway. One more crew. One more job. I drive, you drive, and we are even.")
    local pick = api.choose("Sable holds out a hand.", {
      "Even. Welcome back.",
      "Not yet. Earn it.",
      "You owe me three years, not a favour.",
    })
    if pick == 1 then
      api.say("Sable", "I will earn it. I will be so annoying about earning it.")
      api.tally("sable", 2)
      api.remember("sable_crew", true)
    elseif pick == 2 then
      api.say("Sable", "Earn it. Fair. I know where your garage is. I will start there.")
      api.tally("sable", 1)
      api.remember("sable_crew", true)
    else
      api.say("Sable", "Three years. Right. That is a lot of favours. I will put it on account.")
      api.tally("law", 1)
    end
    api.unlock("sable")
    api.text("sable", "Quinn's lock-up. Top of the Heights, first left after the gnome. Do not ask about the gnome.")
  end, { at = "hairpin_foot", give = { name = "car", kind = "marlin" } })
end
