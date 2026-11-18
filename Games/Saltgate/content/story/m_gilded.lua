-- Act 1, job 5: the Gilt brothers' gold Sovereign. Steal it off the tower plaza and bring it to Rusty in one piece.
return function(api)
  api.step("offer", function()
    api.say("Rusty", "The Gilt brothers park their Sovereign on the tower plaza like a trophy.")
    api.say("Rusty", "Bring it here with most of the paint still on and I will make it worth your while.")
    api.say("Wren", "And the brothers?")
    api.say("Rusty", "Will call the Patrol. They always do.")
    local pick = api.choose("Rusty waits for your answer.", {
      "Worth my while how?",
      "I like a challenge. Gold, you said?",
      "Tam, are you hearing this?",
    })
    if pick == 1 then
      api.say("Rusty", "Twelve hundred. And a story to tell. Admiral likes stories.")
    elseif pick == 2 then
      api.say("Rusty", "Gold. Low. Fast. It hates corners, so go straight when you can.")
      api.tally("greed", 1)
    else
      api.say("Tam", "Loud and clear! It has a four-litre engine and a cupholder for a champagne flute. I looked it up for fun.")
      api.say("Rusty", "The kid is right. Cupholder's the first thing I'll cut out.")
    end
  end)

  api.step("steal", function()
    api.hint("It is parked at the plaza, up on Gilt Heights. Walk up, press E, and do not look like you belong.")
    api.car("sovereign", "gilt_lot", { name = "car", heading = 3.14, label = "Sovereign" })
    api.getIn("car", "Steal the gold Sovereign at the Gilt Tower plaza.")
    api.toast("The Gilts called it in. Lose them!", "alarm")
    api.heat(3)
    api.say("Cass", "Oi! That is MY Sovereign! Do you know how long I waited for the paint to cure?")
    api.say("Wren", "Not as long as it will take you to catch me.")
  end, { at = "gilt_lot" })

  api.step("shake", function()
    api.hint("Downhill the Sovereign gets away from them fast. Mind the hairpins.")
    api.ensureCar("car", "sovereign", "gilt_lot", { label = "Sovereign" })
    api.loseHeat("Lose the Gilts' friends in the Patrol.")
  end, { at = "gilt_lot", give = { name = "car", kind = "sovereign" } })

  api.step("deliver", function()
    api.hint("Rusty will not open the gate with a cruiser behind you, and he will not pay for scrap.")
    api.ensureCar("car", "sovereign", "gilt_lot", { label = "Sovereign" })
    api.drive("rusty", {
      name = "car", text = "Bring the Sovereign to Rusty's, in one piece.",
      noHeat = true, minHealth = 0.35, failText = "Rusty won't take scrap",
      hotText = "Lose the Patrol first. Nobody opens up with cops on your tail.",
    })
  end, { at = "gilt_lot", give = { name = "car", kind = "sovereign" } })

  api.step("outro", function()
    api.say("Rusty", "Look at that shine. The brothers are going to cry into their caviar.")
    api.say("Rusty", "I am not cutting it up. Not yet. Look, you can see the Heights in the door.")
    local pick = api.choose("Rusty strokes the bonnet.", {
      "Keep it. It suits the yard.",
      "Sell it. We need the cash.",
      "Park it where the Gilts can see it.",
    })
    if pick == 1 then
      api.say("Rusty", "I might. Do not tell Juno. She will want to put noodles on it.")
      api.tally("rusty", 1)
    elseif pick == 2 then
      api.say("Rusty", "Practical. I respect it. I hate it, but I respect it.")
      api.tally("greed", 1)
    else
      api.say("Rusty", "That is the kind of rude I can get behind. Admiral! Come see!")
      api.tally("heart", 1)
    end
    api.text("tam", "That Sovereign is a work of art and also a clue. Come by Pit Wall. Big Mouth needs a driver.")
  end, { at = "rusty_door" })
end
