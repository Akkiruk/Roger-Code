-- Act 1, job 4: Rusty finds a phone in Juno's crate, and a voice in the phone. A Gilt courier van runs the same road
-- every night. Follow it without being seen. (Tailing: stay near enough to see, far enough not to be noticed.)
return function(api)
  api.step("crate", function()
    api.say("Rusty", "Juno's crate had a phone in it. It rang. I do not like things that ring.")
    api.say("Wren", "Answer it.")
    api.say("Rusty", "Already did. It talked. Fast. Here.")
    api.say("Tam", "Pit Wall to Wren! Hi, hello, I am Tam, I am nineteen, I fix things, I am in your headset now. Do not panic.")
    api.say("Wren", "I wasn't wearing a headset.")
    api.say("Tam", "You are now. It is in the phone. It is a very small headset. Juno sent me. I know a courier van's nightly route.")
    local pick = api.choose("How do you take the voice in the phone?", {
      "Fine. Where is the van?",
      "Nineteen? Does Juno know?",
      "Rusty, is this person safe?",
    })
    if pick == 2 then
      api.say("Tam", "Juno found me at fifteen. She said I was a fire hazard with a gift. I took that as a compliment.")
      api.tally("heart", 1)
    elseif pick == 3 then
      api.say("Rusty", "She fixed my carburettor over the phone. Safe enough.")
      api.say("Tam", "He cried a bit. I did not mention it. I am mentioning it now.")
      api.tally("rusty", 1)
    else
      api.say("Tam", "Counting house in Lantern Row. It leaves at the quarter hour. I will tell you when to breathe.")
    end
    api.say("Tam", "Rules. Stay back, but do not lose it. If you can see the driver's eyes in his mirror, you are too close.")
    api.unlock("tam")
    api.text("tam", "Pit Wall online. Say 'Tam' for hints. Say nothing for jokes.")
  end)

  api.step("wheels", function()
    api.hint("Any car works, but nothing flashy. A bright car is a loud car.")
    api.anyCar("Get a car. Something plain, if you can.")
  end, { at = "rusty_door" })

  -- (on the real city the counting house is 220 units from Rusty's: the van must not leave before you are there)
  api.step("stakeout", function()
    api.hint("Park across from the counting house. Not outside it: he knows every car on that street.")
    api.drive("courier_watch", { text = "Park across from the counting house." })
  end, { at = "rusty_door", give = { name = "car", kind = "pipit" } })

  api.step("follow", function()
    api.say("Tam", "There. Dark grey van, Gilt crest on the door. It is pulling out now. Go, go, go. Gently.")
    api.hint("Keep the van between 7 and 70 metres away. Too close and he spots you, too far and you lose him.")
    api.actor("runner", "counting_house", { name = "courier", vehicle = "tidewater", route = { "gilt_door" }, label = "courier van" })
    api.tail("courier", { text = "Follow the courier van. Stay back, stay in sight." })
  end, { at = "courier_watch", give = { name = "car", kind = "pipit" } })

  api.step("at_the_door", function()
    api.say("Courier", "Evening, Mr. Cass! Satchel for the tower, as ever. Two stops tonight, one of them is a surprise.")
    api.say("Tam", "Ooh, I like surprises. Wren? Closer. Not that close. Just so I can hear what he says.")
    api.say("Cass", "Leave it on the table. And tell the cook the soup was cold again. Cold soup means cold nerves.")
    local pick = api.choose("The satchel is sitting in the van, unattended.", {
      "Photograph the door. Leave quietly.",
      "Grab the satchel. Gilts can spare it.",
      "Just leave. Not worth the heat.",
    })
    if pick == 1 then
      api.say("Tam", "Photo taken. That is a nice crest. I will frame it. Out you go.")
      api.tally("law", 1)
      api.remember("pitwall_photo", true)
    elseif pick == 2 then
      api.say("Wren", "It's heavy. Feels like paper and coins.")
      api.say("Tam", "That's, what, six hundred? That is a lot of lunch. Okay. You are a good thief and a bad listener. I like you.")
      api.tally("greed", 1)
      api.remember("pitwall_satchel", true)
      api.reward(300)
    else
      api.say("Tam", "Safe. Sensible. Slightly dull. I am writing that down as growth.")
      api.tally("heart", 1)
    end
  end, { at = "gilt_door", give = { name = "car", kind = "pipit" } })

  api.step("report", function()
    api.say("Rusty", "Quiet job. Good. Quiet jobs are the best jobs.")
    api.say("Rusty", "There is a car on the Gilt Tower plaza I have wanted for years. Come by when you want it.")
  end, { at = "rusty_door" })
end
