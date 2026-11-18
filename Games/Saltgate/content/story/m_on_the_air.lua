-- Act 3, job 2: Ferris's van has to reach the Heights mast so the whole city hears the truth, and then the signal has to be
-- kept alive while the Authority's wardens come up the hill. What gets said on the air depends on what you did before.
return function(api)
  api.step("studio", function()
    api.say("Ferris", "I have been rehearsing since four in the morning. I have two speeches. One is dignified. One has a joke about lobsters.")
    api.say("Ferris", "I would like a driver, a van, and the sense that history is watching. Not necessarily in that order.")
    api.say("Wren", "The van is outside?")
    api.say("Ferris", "The van is outside. It has a transmitter in the back and a cat in the front. She is called Ledger. She will take the middle seat.")
    local pick = api.choose("Ferris straightens his hat. His hands shake a little.", {
      "You'll be fine. Just say what's true.",
      "Don't say anything you can't stand behind.",
      "Give them the lobster joke. A laugh helps.",
    })
    if pick == 1 then
      api.say("Ferris", "That is all I have ever wanted to do. And all the lawyers ever wanted to stop me doing.")
      api.tally("law", 1)
    elseif pick == 2 then
      api.say("Ferris", "Everything I say, I can stand behind. It is just that my knees are a little behind the rest of me.")
    else
      api.say("Ferris", "A laugh before the storm! Yes! A joke about lobsters and then the truth. In that order.")
      api.tally("heart", 1)
    end
  end)

  api.step("van", function()
    api.car("tidewater", "studio", { name = "van", label = "Radio van" })
    api.getIn("van", "Get into Ferris's radio van.")
  end, { at = "studio" })

  api.step("climb", function()
    api.say("Tam", "Pit Wall to Wren. The mast is at the top of the Heights. Wardens have a roadblock at the second hairpin. Do not take the second hairpin.")
    api.ensureCar("van", "tidewater", "studio", { label = "Radio van" })
    api.hint("There is a short cut through the park. The van is heavy. Brake early on the hairpins.")
    api.heat(2)
    api.drive("hairpin_top", { name = "van", text = "Get Ferris's van to the mast.", timer = 100, timerText = "AIR",
      timerReason = "the broadcast window closed" })
  end, { at = "studio", give = { name = "van", kind = "tidewater" } })

  api.step("defend", function()
    api.say("Ferris", "Pit Wall, are we live? Are we live? Live in five. Four. Three... Wren, I will need forty-five seconds with no one stepping on the cable.")
    api.actor("crew", "radio_mast", { group = "wardens", count = 5, look = "warden" })
    api.hint("Five wardens are climbing the hill to the mast. Knock them down before they reach the cable.")
    api.defeat("wardens", { text = "Knock down the wardens before the mast." })
    api.survive(20, { text = "Hold the mast while Ferris reads." })
  end, { at = "hairpin_top", give = { name = "van", kind = "tidewater" } })

  api.step("broadcast", function()
    api.say("Ferris", "Good evening, Saltgate. This is Ferris Quill, Radio Lantern, speaking from a mast on a hill. I have three things to say.")
    api.say("Ferris", "One: in three days, the Harbor Authority will close the sea gate. Two: everything outside the wall is considered surplus. Three: that is your home.")
    if api.recall("hobb_patrol") then
      api.say("Ferris", "I have the ledgers. A certain accountant, in custody, has confirmed every page. I thank him, and I thank Lieutenant Harrow's very large filing cabinet.")
    elseif api.recall("hobb_free") then
      api.say("Ferris", "I have the ledgers. Their author is on a train, with a postcard he promised not to send. I am sending it for him.")
    end
    if api.recall("juno_fate") == "public" then
      api.say("Mama Juno", "(live, shaky) Saltgate. This is Junoria Bell. I sold a girl for the stall. I would like to tell you the rest.")
      api.say("Crowd", "(far off) We are listening, Juno. Say it all.")
    end
    local pick = api.choose("Ferris holds the microphone out. He has one more line.", {
      "Tell them to stand at the gate.",
      "Tell them to bring a pot and a lamp.",
      "Tell them about Vane's gloves.",
    })
    if pick == 1 then
      api.say("Ferris", "Saturday. The gate. Come together. They cannot close a gate on a crowd. That is in the manual. Probably.")
      api.remember("crowd_at_gate", true)
      api.tally("law", 1)
    elseif pick == 2 then
      api.say("Ferris", "Bring a pot and a lamp. If it floods, you will want tea. If it does not, you will want tea.")
      api.remember("crowd_with_lamps", true)
      api.tally("heart", 1)
    else
      api.say("Ferris", "Gloves. She wears gloves in July. I do not know what that means. I just think it is funny.")
      api.tally("law", 1)
    end
    api.say("Ferris", "That was Radio Lantern. This was Ferris Quill. Goodnight, and please look under your beds. For canoes.")
  end, { at = "hairpin_top", give = { name = "van", kind = "tidewater" } })

  api.step("down", function()
    api.say("Tam", "They heard it. Every kettle in Saltgate is whistling. Also, the wardens are furious. Come down! Quickly!")
    api.ensureCar("van", "tidewater", "hairpin_top", { label = "Radio van" })
    api.heat(3)
    api.loseHeat("Get Ferris down the hill and lose the wardens.")
    api.text("ferris", "I was magnificent. Do not argue. The cat agrees.")
  end, { at = "hairpin_top", give = { name = "van", kind = "tidewater" } })
end
