-- Act 1, job 6: Tam's transmitter, Big Mouth, has to reach the relay mast at the top of Gilt Heights. A race up the
-- hairpins under a clock, then a hold at the mast while it uploads, then a way back down.
return function(api)
  api.step("garage", function()
    api.say("Tam", "Welcome to Pit Wall! Mind the cat. Mind the other cat. Mind the thing that is not a cat but looks like one.")
    api.say("Wren", "What is that?")
    api.say("Tam", "Big Mouth. A transmitter. It turns one tiny radio voice into every radio in Saltgate. Ferris, our friend on Radio Lantern, will do the talking.")
    api.say("Tam", "It has to sit at the top of the Heights relay mast. Anywhere else, it just whispers. Eighty seconds, give or take.")
    local pick = api.choose("The hairpins on Gilt Heights are steep and tight.", {
      "Eighty seconds. I can do sixty.",
      "Who is going to be waiting at the top?",
      "What does Ferris plan to say?",
    })
    if pick == 1 then
      api.say("Tam", "That is the spirit. Also the engine. If it starts smoking, that is also the spirit.")
      api.tally("greed", 1)
    elseif pick == 2 then
      api.say("Tam", "Nobody. That is the problem. Nobody means nobody is watching the mast. Which means someone will be, soon.")
    else
      api.say("Tam", "The truth. All of it. He says he has a list. He also has a hat.")
      api.tally("heart", 1)
    end
  end)

  api.step("pickup", function()
    api.hint("Tam's pickup is the blue one parked in the lane. It handles like a sofa on wheels.")
    api.car("tidewater", "tam_garage", { name = "car", label = "pickup" })
    api.getIn("car", "Take Tam's pickup with Big Mouth in the back.")
  end, { at = "tam_garage" })

  api.step("climb", function()
    api.say("Tam", "Pit Wall to Wren! Hairpins are on the right. Wait, left. Both, actually. I never said it was easy.")
    api.ensureCar("car", "tidewater", "tam_garage", { label = "pickup" })
    api.hint("Brake before the hairpin, not in it. The pickup leans, so take it wide.")
    api.heat(2)
    api.toast("Gilt guards at the foot of the hill! Go!", "alarm")
    api.drive("hairpin_top", {
      name = "car", text = "Race up the hairpins to the relay mast.",
      timer = 80, timerText = "UPLINK", timerReason = "the uplink window closed",
    })
  end, { at = "tam_garage", give = { name = "car", kind = "tidewater" } })

  api.step("mast", function()
    api.say("Tam", "That's the mast! Park up next to it and hold still. Big Mouth is warming up.")
    api.ensureCar("car", "tidewater", "hairpin_top", { label = "pickup" })
    api.hold("radio_mast", 8, { text = "Hold at the mast while Big Mouth connects.", away = "Get back beside the mast!", radius = 3 })
    api.say("Ferris", "Good evening, Saltgate! You are listening to Radio Lantern, and I have the finest scandal of the evening.")
    api.say("Ferris", "Do you know what the Gilts pay the Harbor Patrol to look the other way? Do you know what they pay in hats?")
    local pick = api.choose("Ferris asks you, off air, how hard to hit them.", {
      "Everything. Names, numbers, the lot.",
      "Make them sweat. Spare Juno.",
      "Only what the Patrol will believe.",
    })
    if pick == 1 then
      api.say("Ferris", "Music to my ears. And to their lawyers'. Ahem. Dear listeners, a ledger of crimes follows.")
      api.remember("ferris_truth", true)
      api.tally("heart", 1)
      api.tally("law", 1)
    elseif pick == 2 then
      api.say("Ferris", "Delicate. I do delicate. It is my least favourite thing, but I do it.")
      api.remember("ferris_careful", true)
      api.tally("juno", 1)
    else
      api.say("Ferris", "The Patrol believes nothing that costs them a lunch. Careful, careful... all right, a little.")
      api.tally("law", 1)
    end
  end, { at = "hairpin_top", give = { name = "car", kind = "tidewater" } })

  api.step("down", function()
    api.say("Tam", "Signal's out. Everybody heard it. Everybody. Even the seagulls turned their heads.")
    api.say("Tam", "Aaaand the Gilts heard it too. You have company. Sorry! Go go go!")
    api.ensureCar("car", "tidewater", "hairpin_top", { label = "pickup" })
    api.heat(3)
    api.hint("Downhill is faster than it looks. Use the brake early on the hairpins.")
    api.loseHeat("Lose the Gilts' cars on the way down.")
  end, { at = "hairpin_top", give = { name = "car", kind = "tidewater" } })

  api.step("home", function()
    api.say("Tam", "That was the best thing I have ever done. And I once soldered a toaster to a bicycle.")
    api.say("Ferris", "Wren Calloway, I have not met you, but I am in love with your hands on a steering wheel. Come to the studio in Lantern Row.")
    api.unlock("ferris")
    api.text("ferris", "Radio Lantern, the second floor. Bring a tie. It is for the cat.")
    api.text("tam", "Also the pickup needs a respray. Also a new wing mirror. Also a lot of love.")
  end, { at = "tam_garage" })
end
