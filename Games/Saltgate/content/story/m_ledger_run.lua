-- Act 1, job 7: Hobb Marsh, the Gilts' accountant, is leaving town with the books. A chase through Lantern Row and
-- the Cinder rail yard; ram him to a stop, then decide what to do with him.
return function(api)
  api.step("studio", function()
    api.say("Ferris", "Wren! Come in, come in, mind the cat, she is a critic. You heard the broadcast?")
    api.say("Wren", "I made the broadcast. I was on the hill.")
    api.say("Ferris", "And now the Gilts are scrambling. Hobb Marsh, their accountant, keeps the only copy of the real ledger. He is fleeing tonight.")
    api.say("Ferris", "Black Kestrel cab, out of the Row, through the Cinder yard to the crossing. If he gets out of the city, the ledger goes with him.")
    local pick = api.choose("How hard do you stop him?", {
      "Nudge him. Politely.",
      "However it takes.",
      "Why not just ask him nicely?",
    })
    if pick == 1 then
      api.say("Ferris", "Polite is good. Polite is under-rated. Polite is also slower. Hurry.")
      api.tally("heart", 1)
    elseif pick == 2 then
      api.say("Ferris", "That's the voice of someone who has seen the price of paper. Go.")
      api.tally("greed", 1)
    else
      api.say("Ferris", "Ask him nicely? He is a man who charged an orphanage for a window. Go.")
    end
  end)

  api.step("wheels", function()
    api.hint("Pick something quick. A cab is not going to out-run a Sovereign, but it will out-turn you.")
    api.anyCar("Get a fast car.")
  end, { at = "studio" })

  api.step("chase", function()
    api.say("Tam", "Pit Wall to Wren! He is out of the garage! He is turning left, which is a mistake, because left is the rail yard!")
    api.actor("runner", "counting_house", { name = "hobb", vehicle = "kestrel", route = { "rail_yard", "crossing" }, flees = true, label = "cab" })
    api.hint("Close in and bump him from behind. A couple of firm nudges will stop the cab. Don't wreck it.")
    api.chase("hobb", { text = "Run Hobb's cab down. Ram him to a stop.", failText = "Hobb got away with the books" })
  end, { at = "studio", give = { name = "car", kind = "pipit" } })

  api.step("books", function()
    api.say("Hobb", "All right! All right! My car! My beautiful, awful car! You owe me a bumper!")
    api.say("Wren", "Hand over the ledger and I will think about the bumper.")
    api.say("Hobb", "You do not know what you are carrying. Those books will end Aurelian Gilt. And me. I have a daughter, you know.")
    local pick = api.choose("Hobb clutches the ledger. He is shaking.", {
      "Give me the ledger. You can go.",
      "Come with me. Ferris will keep you safe.",
      "Patrol can have him. He cooked the books.",
    })
    if pick == 1 then
      api.say("Hobb", "Thank you. I will be on the first train. I will send a postcard. No, I will not. Goodbye.")
      api.tally("heart", 1)
      api.remember("hobb_free", true)
    elseif pick == 2 then
      api.say("Hobb", "Radio Lantern? On the air? My mother listens. Oh, she will be so cross.")
      api.tally("juno", 1)
      api.remember("hobb_ferris", true)
    else
      api.say("Hobb", "You would not! Oh, you would. You are exactly the sort.")
      api.say("Wren", "I am a very organised sort.")
      api.tally("law", 1)
      api.remember("hobb_patrol", true)
    end
    api.say("Tam", "Ledger acquired. I will scan it tonight. Page one is already a crime.")
  end, { at = "crossing", give = { name = "car", kind = "pipit" } })

  api.step("handoff", function()
    api.hint("Juno is waiting at the back lot. The ledger is in your glove box.")
    api.drive("juno_lot", { text = "Take the ledger to Juno's back lot.", onFoot = false })
  end, { at = "crossing", give = { name = "car", kind = "pipit" } })

  api.step("juno", function()
    api.say("Mama Juno", "So that is what a villain's homework looks like. Tidy handwriting. They always have tidy handwriting.")
    api.say("Mama Juno", "Tomorrow night the Gilts pay what they owe the city. You are going to drive me to their tower.")
    api.say("Wren", "Their tower. Where all the guards are.")
    api.say("Mama Juno", "And a very comfortable lobby. Get some sleep, little crab.")
  end, { at = "juno_lot" })
end
