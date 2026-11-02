-- regions/empire.lua: the Empire. Home gone, a land of books and owl beasts, the scholar's past, and bed nine.
-- Plain data and local helpers only. Draft for the author to edit: story.lua's header says how a script is put together.
-- The way round: the crack's east end, up the sally stair to empty Scythebreak for circlets, back down, under the wall, out into
-- Owlundia, Agoshull and the Stacks and the Ultimatum, then Evrastin, the Light, and the ward. Nobody here says what the hero is.

local say = require("games.blightmare.say")
local t, ask, topic, person, line = say.t, say.ask, say.topic, say.person, say.line

local R = {
  id = "empire", prefix = "em_",
  -- only what's needed: left_town and the mine's flags keep the search out of the slice, and no other region's site opens
  entry = {
    flags = { "wm_done", "left_town", "foreman_down", "arrived", "mine_pass" },
    join = { "deserter", "cleric", "owlin" }, lvl = 21, site = "crack_east", map = "em_crack_1", x = 28, y = 9,
  },
  exit = "em_done",
  -- what this region reads from the slice, so the people the hero knew answer for what was said to them
  exports = {
    "joked_nan", "snapped_nan", "lied_to_nan", "said_goodbye", "kid_kind", "kid_snub", "fed_watch", "heard_tobin", "kind_wick", "promised_wick",
    "threat_wick", "sass_clerk", "heard_evrastin", "wanted_back", "wm_got_dish", "em_counted",
  },
  sites = {
    crack_east = { mx = 28, my = 9, dir = 4 },
    crack_west = { mx = 3, my = 9, dir = 2 },
    agoshull = { mx = 28, my = 10, dir = 4 },
    evrastin = { mx = 28, my = 10, dir = 4 },
  },
  maps = {}, scripts = {}, shops = {}, goals = {},
  foes = {}, abilities = {}, encounters = {}, field = {},
  looks = {}, names = {}, art = {}, items = {},
}

local S, M = R.scripts, R.maps

-- ---------------------------------------------------------------- who says what

local hero, doc, sis, owl = line("hero"), line("deserter"), line("cleric"), line("owlin")
local mask = line("doctor")
local satchel = person("em_satchel", "CLINIC CLERK")
local tawn = person("em_tawn", "WARDEN TAWN")
local hob = person("em_hob", "HOB")
local perigee = person("em_perigee", "LORD PERIGEE")
local pellet = person("em_pellet", "MISTRESS PELLET")
local oswin = person("em_oswin", "BINDER EDRIC")
local tuppence = person("em_tuppence", "THIMBLE")
local marl = person("em_marl", "MARL")
local hesper = person("em_hesper", "DOCTOR LINDE")
local dagny = person("em_dagny", "DAGNY, SECOND HISS")
local provost = person("em_provost", "THE PROVOST")
local dole = person("em_dole", "PROCTOR DOLE")
local gannet = person("em_gannet", "PILOT GANNET")
local sorrel = person("em_sorrel", "BURDOCK")
local kess = person("em_kess", "MAGISTER KESS")
local tyto = person("em_tyto", "MATRON TYTO")
local warder = person("em_w_orderly", "ORDERLY")

--- A thing on a draped table, drawn with what a person would carry.
local function thing(carry)
  return { kind = "human", pose = "lying", bed = true, empty = true, carry = carry, carryX = 0.5 }
end

--- An npc on a map.
local function who(id, x, y, script, when, unless, sprite)
  return { id = id, x = x, y = y, sprite = sprite or "villager", script = script, when = when, unless = unless }
end

-- ---------------------------------------------------------------- the foot of the wall

S.em_arrive = {
  t("The wall goes up and up. It takes a while to find the top. You stopped noticing it years ago, and you notice it now."),
  t("This is the crack you walked past every day of your life, followed south along the foot of the wall to where a cart would fit. The dark in it is moving very slightly. In, and in, and in."),
  owl("I came out this way, on my stomach, with my eyes shut. It was narrower then, and so was I. This circlet is the reason I can tell you about it, and it's the only one we have."),
  owl("The three from the drawer don't count. I said they'd see you through, and I've smelled it now, and I take that back. They were made in a hurry, by frightened people."),
  doc("Then three of us walk in with our heads open. I've a bad idea, friend. Everyone who ever crawled out of that crack had a circlet taken off them at the wall. They went into a crate, in the store at Scythebreak."),
  doc("I know, because I signed for some of them."),
  doc("There's an old sally stair up this north gallery. It comes out at the end of Back Lane."),
  ask(doc("Nobody's had a word out of that town in months. You needn't come up, friend. I can carry a crate."), {
    topic("What do you think we'll find?", {
      doc("Doors, mostly. I've seen a town after the count is finished. They're very tidy."),
    }),
    { "It's my home. I'm coming.", {
      sis("Yes. I thought you might say that. I'll walk behind you. It's where I'm most use."),
    } },
    { "You go in first.", {
      doc("Naturally. I've been going in first for years. It's the coming out I want practice at."),
    } },
  }),
  { set = "em_wall_seen" },
  { save = true },
}

S.em_t_front = {
  t("Grey stuff stands in the passage, thick as wool. It leans towards the doctor as the doctor comes near."),
  doc("That's far enough, I think. My nose is bleeding, and I've only been looking at it."),
  sis("It doesn't lean towards you, {hero}. Had you noticed? It's gone round you like water round a post."),
}

S.em_t_wall_log = {
  t("The wall-watch's log, open on the table, with a mug standing on it. The last entries are in a sergeant's square hand."),
  t("'Town closed. Transfers begun. Pie allowance withdrawn, no reason given. Transfers complete. Post to stand down.'"),
  t("'The breathing has not stopped. Nobody has asked me to note that. I am noting it.'"),
}

-- ---------------------------------------------------------------- Scythebreak, empty

S.em_home = {
  t("The stair comes up in Back Lane. It's a fine, still morning. It takes you a moment to work out what's wrong with the sound of it, and then you have it. There isn't any."),
  t("Every door has its chalk tally. Nobody has been round with a cloth. The grass has started on the high street, very politely, at the edges."),
  sis("Empty. Hardly a thread in the whole town. I've stood in graveyards with more going on."),
  doc("It's the store we want, in the Clinic house. Top of the square, past the ward. There's no hurry, friend. Whatever you need to look at, look at it."),
}

S.em_s_nan = {
  t("Nan's door still sticks. Inside it smells of nothing, which is the worst thing it has ever smelled of."),
  t("The porridge pot is on the hob, scrubbed clean. She got the last of it off, then, before they came. The fence still wants mending."),
  { when = "joked_nan", steps = {
    t("A slate hangs by the door, where she kept the shopping. 'Salt. Lard. Find out what that child means about the horse.'"),
  }, other = {
    { when = "snapped_nan", steps = {
      t("A slate hangs by the door, where she kept the shopping. 'Salt. Lard. Stop fussing.' That last has been rubbed out, and written in again."),
    }, other = {
      t("A slate hangs by the door, where she kept the shopping. 'Salt. Lard. Something nice for {hero}.'"),
    } },
  } },
  { choice = {
    { "Wipe the slate clean.", {
      t("You lift your sleeve, and you find you can't do it. You straighten it on its nail instead."),
    } },
    { "Take the wooden spoon.", {
      t("It's worn away on one side, the side she stirred with. It weighs nothing at all. It goes in your coat."),
    } },
    { "Stand there for a bit.", {
      t("Nobody tells you to stop standing about. That's how you know."),
    } },
  } },
  { when = "lied_to_nan", steps = {
    sis("The doctor heard you lie to her, at the end. You said you'd had a dream. A small one, and a nice one."),
    sis("I've heard a great many last things. I'd have let that one stand."),
  } },
}

S.em_t_book = {
  t("The Dream Book is still on its stand in the square, under a square of oilcloth that somebody has tied down carefully. Twenty-two years of it, ruled in one neat hand."),
  t("You find your own page, and the page above it. Nothing, nothing, nothing, back and back."),
  { when = "sass_clerk", steps = {
    t("The last entry against your name has been struck through with a ruler. Beside it, very small and very neat: 'One dragon. A big one.'"),
    t("And under that, in the margin, the same hand. 'Apologies for the note about the attitude.'"),
  }, other = {
    t("The last line is the clerk's own, dated the day of the queue. 'Nothing further to declare.' He has signed it, and blotted it."),
  } },
  { choice = {
    { "Close the Book, and tie the cloth.", {
      t("It's a good knot. You've seen him do it often enough."),
    } },
    { "Write something on the next line.", {
      t("There's a pen on a string. It takes a moment to think of what. 'Came back. {hero}.' It is, you notice, the first thing you've ever declared."),
    } },
  } },
}

S.em_s_wick = {
  t("Wick's lamp-pole is lying where it rolled. Nobody has moved it. It seems nobody wanted to."),
  { when = "kind_wick", steps = {
    t("You asked him once if he was all right. You think about how few people had."),
  }, other = {
    { when = "promised_wick", steps = {
      t("You told him you wouldn't tell the Book. You never did. It didn't turn out to matter, and you're glad of it anyway."),
    }, other = {
      { when = "threat_wick", steps = {
        t("You told him the clerk should hear about him, once, for a joke. You'd take it back. There's nobody to take it back to."),
      } },
    } },
  } },
  { choice = {
    { "Light the lamp at the end of the street.", {
      t("It takes you three tries, and he would have been ashamed of you. Then the little flame stands up on its wick, in broad daylight, in an empty town."),
      sis("That's the most foolish thing I've seen all year. Leave it burning."),
    } },
    { "Lean the pole against the wall.", {
      t("You stand it by a door, where it would be handy for someone."),
    } },
  } },
}

S.em_s_watch = {
  t("The foot of the wall, at the end of the high street. The crack here has been stopped with grey mortar, and you can hear it working at the mortar from the other side."),
  { when = "fed_watch", steps = {
    t("A spear is propped by the watch-post, carefully, by someone who meant to come back for it."),
    t("He did say he'd bring Nan's cloth back, washed. It'll have gone on a cart with him."),
  }, other = {
    t("A spear is lying by the watch-post. He seems to have dropped it again."),
  } },
}

S.em_s_kid = {
  t("The yard wall is covered in chalk, as high as a small arm can reach. Doctors with beaks. Beds. A very large goose."),
  { when = "kid_kind", steps = {
    t("Low down, in a wobbling hand: 'ITS QUIET. {hero} SAYD.'"),
  }, other = {
    { when = "kid_snub", steps = {
      t("Low down, in a wobbling hand: a tall person, with a face scribbled out, being given the bad medicine."),
    }, other = {
      t("Low down, in a wobbling hand: a tall thin man, in the corner of a room. Somebody has drawn him a hat, to be polite."),
    } },
  } },
}

S.em_s_widow = {
  t("A pair of man's boots stands just inside the door, polished. On the mat under the letter-flap lies an envelope with a Clinic seal, this year's."),
  { when = "heard_tobin", steps = {
    t("It's the spring letter about Tobin. 'We are delighted to report that he continues to do well.' The widow went on a cart in the winter. It came all the same."),
    doc("There's a whole office for that. They'll send one next spring, too. I don't suppose anybody's told them to stop."),
  }, other = {
    t("'We are delighted to report that he continues to do well.' It's dated in the spring. There hasn't been anyone here to read it since the winter."),
  } },
  { when = "wm_got_dish", steps = {
    t("On the shelf there's a clean ring in the dust, with a scrap of paper in it. 'Nan's. Give back.' You've got it in your pack. It's on its way."),
  }, other = {
    t("On the shelf, there's a pie dish, washed, with a scrap of paper in it. 'Nan's. Give back.'"),
  } },
}

S.em_s_lioth = {
  t("Mistress Lioth's bench, with a boot still on the last and the tacks set out in a row. Above it, pinned where she could see it, is a yellow lecture bill."),
  t("'THE ULTIMATUM, AGOSHULL. On Lenses, and What They Are For. A guest lecture by the Keeper of the Evrastin Light.' Somebody has sketched the speaker in the margin, in a few quick lines."),
  { when = "heard_evrastin", steps = {
    t("It's mostly a chin. 'You've a look of,' she said to you, and then she said it was nothing."),
  } },
  owl("She gave that lecture series a very bad review, you know. She gave everything a bad review. I was terrified of her. Was she well, here?"),
  { choice = {
    { "She mended boots, and hated it.", {
      owl("Then she was well. Thank you."),
    } },
    { "She said she'd lived, and was sorry.", {
      owl("Yes. We all say that. I've never found the right person to say it to."),
    } },
  } },
}

S.em_s_ward = {
  t("The ward. The beds are all still here, and every one is made. Hospital corners, drawn tight enough to bounce a coin."),
  doc("They'd have stripped them and made them up again, after. It's in the regulations. A bed is to be left as though nothing has occurred."),
  t("There's a card at the foot of each bed. Each one has a name, a tick, and a cart number."),
}

S.em_t_bed_nan = {
  t("The card reads NAN, and then a surname you never once heard her use. Tick. Cart nineteen."),
  { when = "said_goodbye", steps = {
    t("They've made the bed, and the hollow is still in the pillow. You told yourself you wouldn't look."),
  }, other = {
    t("You never came by to say goodbye. They've made the bed, and there's a hollow in the pillow all the same. You told yourself you wouldn't look."),
  } },
}

S.em_s_spoon = {
  t("The little room at the end of the corridor. A bed, a bucket, and a very clean floor. In the corner, where it was dropped, there's a spoon."),
  doc("Oh, there it is. I've been looking for that."),
  sis("You opened a Clinic cell with a teaspoon, and you've been pining for it?"),
  doc("It's a delicate instrument. It's signed out to me. I'd hate there to be a form."),
}

S.em_t_crate = {
  { when = "em_circlets", steps = {
    t("Hundreds of them, still, each with a name on a tag. They'll keep. It's what they were made to do."),
  }, other = {
    t("A Clinic crate, stencilled and sealed. The doctor gets the lid up with a bone saw. Plain grey bands, packed in straw, each one tagged with the name of whoever had it taken away."),
    owl("Well, I'll be plucked. That's Agoshull work. These aren't confiscated goods, doctor, they're the last good thing anyone made there."),
    doc("Item, one circlet, surrender of. I've got a very clear signature. I was proud of the loop on the D."),
    sis("This one says 'Lioth'. Every one of these got out."),
    { give = "circlet", n = 3 },
    sis("Three, for the doctor and me, and a spare for the scholar in case that old thing cracks. There's a fourth here for you, {hero}."),
    { choice = {
      { "Leave it. I don't think I need one.", {
        sis("No. I don't think you do. I can't say why I'm so sure, and I'd rather you didn't ask me yet."),
      } },
      { "Give it here.", {
        t("It sits on your head like a hat on a post, doing nothing. You put it back in the straw, and nobody says anything."),
      } },
    } },
    { set = "em_circlets" },
    doc("That's the crate, friend. Back down the sally stair, or out by the gate and round to the crack. There's nothing else here that wants carrying."),
    { save = true },
  } },
}

S.em_t_satchel = {
  { when = "em_clerk_met", steps = {
    satchel("Four hundred and twelve out, and one over. It balances, if I don't look at it. Good day. Mind the grass. I've got it down as an irregularity."),
  }, other = {
    t("A small man with a satchel is standing in the middle of the empty square, counting the doors. His coat has been mended, badly, by himself. He looks up, and goes quite pale."),
    satchel("Four hundred and twelve out. You'll excuse me, I make that four hundred and twelve out, and you. You're on my list as absent. I've had you as absent for a year. I've been very happy with it."),
    doc("Good grief. Have they left you here?"),
    ask(satchel("Nobody's told me to stop, doctor. The instruction says quarterly. Pages to agree with people. And they do agree, now. It's the first time they ever have. None and none."), {
      topic("Where did everyone go?", {
        satchel("Adaphis, on transfer. Forty-one carts. I have the receipt for each of them, and I've never yet seen one come back with anything in it but a very clean floor."),
      }),
      topic("Where's Nan?", {
        satchel("Name? Yes. Second column, the narrow one. Cart nineteen, lying very straight, and complaining of the driver in her sleep. I'm not supposed to have that. It isn't a figure. I wrote it down anyway, and I couldn't tell you why."),
      }),
      topic("Why are you still counting?", {
        satchel("I've been thinking about that. If I stop, then the last thing that ever happened here was a sum. I'm not an imaginative man. It just doesn't seem as though it ought to come out so neatly."),
      }),
      { "Go home. It's over.", {
        satchel("Home. Yes. I've got a room over the Records Office. I don't believe anyone has counted it. Perhaps at the end of the quarter."),
      } },
      { "Count me. I came back.", {
        t("He looks at you for a moment. Then he licks his pencil, and very carefully writes something in the narrow column."),
        satchel("Four hundred and thirteen. I'm afraid that's fraud. Thank you."),
        { set = "em_counted" }, -- ruin_south's ledger quotes this line
      } },
    }),
    { set = "em_clerk_met" },
  } },
}

-- ---------------------------------------------------------------- under the wall

local function lamp(flag, seen)
  return {
    { when = flag, steps = {
      t("The lamp burns steadily behind its hood. The grey stuff has drawn away from it, as far as the wall."),
    }, other = {
      t(seen),
      { choice = {
        { "Trim the wick, and light it.", {
          t("Up, and a quarter turn, and don't breathe on it. You watched a man do this every evening of your life. It catches first time."),
          { set = flag },
          { count = { "em_lamp_a", "em_lamp_b", "em_lamp_c" }, at = 3, steps = {
            t("Far down the gallery, something that has been breathing in misses a beat. The wool in the passage comes apart like wet paper."),
            { set = "em_lamps" },
          }, other = {
            owl("The wool's thinning. It doesn't like it. I make that one more than there were, and I have a feeling they were all meant to be lit."),
          } },
        } },
        { "Leave it for now.", {} },
      } },
    } },
  }
end

S.em_t_lamp_a = lamp("em_lamp_a", "A hooded Clinic lamp on a bracket, dead. Someone left a tin of oil beside it, and wrote the date on the tin.")
S.em_t_lamp_b = lamp("em_lamp_b", "A lamp of the wall-watch, burned dry. There are scratches round the bracket. Someone was counting days and then stopped.")
S.em_t_lamp_c = lamp("em_lamp_c", "The last lamp in the gallery, with a very old Empire shade under the Clinic hood. Whoever stood here last tried to keep it going with lamp-black and spit.")

S.em_t_fog = {
  t("The grey wool fills the gallery from floor to roof. It presses on the bands like a hand on a horse."),
  owl("The Clinic kept this gallery lit for a reason. Those old lamps along the side passages. Light keeps it thin, or it did before the oil ran out."),
}

S.em_scene_breath = {
  t("The gallery opens onto a drop with no bottom. Across it, grown into the wall from one side to the other, is something very large and pale, drawing in, all at once, like a chest. Things are stuck to it that used to be other things."),
  doc("That's what the horn was for. All this time I thought the crawlers were getting through. They weren't. They were falling out of it."),
  owl("A nightmare, grown where the wards are thin. There's no mind in it to reason with. It has one idea, and the idea is 'more'."),
  { choice = {
    { "Then it stops here.", {
      sis("She has a list. I've never yet seen this on it. I'd like to write it in."),
    } },
    { "How long can a thing breathe in?", {
      owl("I would very much prefer that we did not find out."),
    } },
  } },
  { battle = "em_boss_breath" },
  t("It lets go. It takes a long while. The air goes past you, warm and stale, down the whole length of the gallery, and it smells of lavender and boiled linen."),
  t("Then there's nothing in the crack but stones and a draught. You'd forgotten that the wall could be quiet."),
  { when = "wanted_back", steps = {
    doc("You told me once you should go back for them, and I talked you out of it. Well, we've come back. I don't know that this counts, friend. It's a start."),
  } },
  { set = "em_breath_down" },
  { save = true },
}

S.em_out = {
  t("The stair climbs into daylight on the far side of the wall. You have lived your whole life looking at the other side of this."),
  { big = "OWLUNDIA" },
  t("Low hills, and rain coming. Every hill has a tower on it, stopped halfway through falling down. Paper blows across the road and catches in the hedges like snow."),
  owl("Ah. Yes. Well. It's smaller. No, it isn't. I expect that I am."),
  owl("West, then. Agoshull is the cluster of towers on the skyline, and Evrastin's the light on the coast. We don't go near that. And please don't let the owl beasts hear you make a weak argument."),
  { set = "em_through" },
}

-- ---------------------------------------------------------------- Agoshull

S.em_ag_arrive = {
  t("Agoshull is one city from end to end, mage tower against mage tower, with their tops lost in rain. Nearly all the windows are dark."),
  t("At the foot of the nearest tower, behind a barricade of very large books, something raises a spear."),
  hob("Halt! Friend or foe? And mind, I've got to write down which, so please say it clearly."),
  { choice = {
    { "Friend.", {
      hob("Friend. Oh, that's a relief. I've been doing this for eleven years, and you're my first."),
    } },
    { "Depends who's asking.", {
      hob("Hob's asking! Oh, I'm not allowed to say that. I'll put 'friend'. I haven't got anything to compare you with."),
    } },
  } },
  t("He sees the scholar then, and the spear comes down a long way. His round eyes go, slowly, to the circlet."),
  hob("I'll fetch the Warden. No. I think I'll just point. She's in the Quiet Rooms, north of the Orrery. She's going to want to see you. I don't think she's going to enjoy it."),
  { set = "em_ag_seen" },
}

S.em_t_hob = {
  hob("Barricade's all sound! It's the collected Proceedings of the Constellation. Nothing has ever got through them, including me."),
}

S.em_t_tawn = {
  { when = "em_proof", steps = {
    tawn("A hundred and forty souls and a week of barley. If you've something to do at Evrastin, go and do it, and try to come back owing me nothing."),
  }, other = {
    { has = "em_book", steps = {
      t("The Warden takes the Last Proof in both claws and reads the final page. It takes a long time, though it's very short."),
      tawn("Bed nine. So she knew there was something, and she went up on that stage regardless. She had a night, and she took the night. That was always her trouble."),
      { when = "em_honest", steps = {
        owl("Warden. I've told them. I told the chamber, too. I found the error, and I kept quiet."),
      }, other = {
        owl("Warden. I've told them. I found the error, and I kept quiet."),
      } },
      tawn("Do you think we hadn't worked that out? My Corvin was in the east hills that morning, tending the bees. He's up there yet. I've seen him. He comes down for the rain."),
      tawn("I don't forgive you. I want that understood. I've moved you off the list of people I won't feed. It's a long way from being forgiven."),
      { choice = {
        { "That's more than they asked for.", {
          owl("Thank you, Warden. I shall eat a very small amount."),
        } },
        { "They brought the book back.", {
          tawn("They did. Don't push your luck, child. It runs out on this floor."),
        } },
      } },
      owl("The Proof holds the corrected ninth line. It's only a small ward, but it should hold the fog off us for as long as we need. Evrastin, then. South-east, on the coast."),
      { set = "em_proof" },
      { save = true },
    }, other = {
      { when = "em_warden_told", steps = {
        { when = "em_ticket_got", steps = {
          tawn("You've got your ticket. The Ultimatum's under the Stacks. Go and use it, and let me get on with the barley."),
        }, other = {
          tawn("The Ultimatum's under the Stacks, and you'll want a reader's ticket from Lord Perigee. South of the Orrery. Mistress Pellet won't let the Queen of Heaven downstairs without one."),
        } },
      }, other = {
        t("A broad old owlin stands at a table of ration sheets. When she looks up she doesn't look at you. She looks at the circlet."),
        tawn("I know that band. I knew the head that it was made for. You've got a nerve, coming home."),
        owl("Warden Tawn. You look well."),
        ask(tawn("I look like a hundred and forty people's dinner. Who are these? Oh, I can see they don't know. Twenty-two years, and they haven't heard about the sums."), {
          topic("What sums?", {
            owl("I'll tell you, {hero}. I will. Not here, if you don't mind. There's a place for it, down in the Stacks."),
          }),
          topic("What happened to this city?", {
            tawn("The sickness came up from Evrastin in the night. In a week every third bed was breathing together. Then our Provost made a great working to drive it out, on that stage, and every owl in Owlundia woke up hungry."),
          }),
          { "We came for the cure.", {
            tawn("Everyone does. There's one thing in this city worth having, and that's the Last Proof, the Provost's own papers. It's in the Ultimatum, past the Reserve. Nobody has come back up with so much as a bookmark."),
          } },
        }),
        tawn("You'll need a reader's ticket. Lord Perigee signs them, the last of the Constellation, south of the Orrery. Beds are at Marl's. Don't take more barley than you need."),
        { set = "em_warden_told" },
      } },
    } },
  } },
}

S.em_t_perigee = {
  { when = "em_ticket_got", steps = {
    perigee("Order! The Chair notes with pleasure that the motion has been carried. I've had it framed. The Chair now moves to adjourn for a short sleep. Does anybody... no? No. Order, then."),
  }, other = {
    t("A very old man in the sash of a Lord of the Constellation sits at the head of a table laid for forty. He raps it with a small bell, as he hasn't got a gavel."),
    perigee("Order! This is the nine thousand, one hundred and sixth sitting of the Constellation of Lords. I am present. I make that a quorum, following the resignations. Does the floor wish to address the Chair?"),
    ask(perigee("Speak up. There's a draught, and my colleague on the left has been dead some time."), {
      topic("Resignations?", {
        perigee("Thirty-nine of my colleagues. Some took the road in the first week. Some are still attending, in a manner of speaking, with feathers. I'm told the standard of debate has come up."),
      }),
      topic("Why do you keep sitting?", {
        perigee("A council that stops meeting is just some old people in a burned house. And there is a motion on the table, young person. I've never left a motion on the table in my life. I don't recall what it was."),
      }),
      { "I need a reader's ticket.", {
        perigee("A motion! From the floor! Oh, my word. It wants a seconder, it wants a seconder. Is there a seconder?"),
        owl("Seconded, my lord."),
        perigee("Moved and seconded! All those in favour?"),
        t("There's a long silence. A drop of rain falls through the roof, into a soup plate. You raise your hand. So does the sister. The doctor, after thinking about it, raises a scalpel."),
        perigee("Carried! Carried, by acclamation! The first since the fall! Give me that pen. I'd like it in the minutes that I wept."),
        { give = "em_ticket", n = 1 },
        t("He signs it with enormous care. You now hold a Reader's Ticket of the Ultimatum, valid for all departments, in the name of 'The Floor'."),
        { set = "em_ticket_got" },
      } },
      { "Not now, my lord.", {
        perigee("The Chair recognises that the floor is shy. Order!"),
      } },
    }),
  } },
}

S.em_t_pellet = {
  { when = "em_ticket_got", steps = {
    t("Mistress Pellet examines the ticket by a candle, and then through a glass, and then smells it. She has a hunched back and a date-stamp on a chain."),
    pellet("In order. Valid for all departments. Lift's at the far south-west of the gallery. And I'll say this, since I've got you. There's a matter of a book."),
    t("Her head goes round, a long way further than you were expecting, and stops at the scholar."),
    pellet("'Notes Towards a Theory of Sleep', second edition. Borrowed for two weeks. I make it twenty-two years, four months and a day. At a penny a day that's three hundred and twelve gold, and I'd have it in writing."),
    owl("I can explain. There was a catastrophe."),
    { choice = {
      { "Pay the fine. (312 gold)", {
        { paid = 312, steps = {
          pellet("Paid in full. Do you know, in sixty years, nobody ever has? I don't know how to feel about it. Here. You've a clean record. It's the only one in the city."),
          { give = "scribe_rod", n = 1 },
          t("She sniffs, and takes a very fine reading-rod out from under the desk. 'Unclaimed,' she says, 'for some time.'"),
        }, other = {
          pellet("You haven't got it. No, don't turn out your pockets. I've seen pockets. It goes on the account, with interest, and I shall know where you are."),
        } },
      } },
      { "It's a catastrophe. Waive it.", {
        pellet("The catastrophe is noted. So is the fine. It goes on the account, scholar, and I'll live for ever if I have to."),
      } },
    } },
    { set = "em_past_desk" },
  }, other = {
    pellet("Hush. Stacks are closed to the public. Are you a reader? No. I can tell by your hands. No ticket, no stairs, and it isn't me that's being difficult. It's the owl beasts downstairs. They're the ones who don't like being disturbed."),
    { choice = {
      { "Who signs a ticket?", {
        pellet("Lord Perigee. South side of the Orrery. Speak up, and don't let him adjourn you."),
      } },
      { "We'll come back.", {
        pellet("Quietly."),
      } },
    } },
  } },
}

S.em_t_pellet_aside = {
  { when = "em_stamped", steps = {
    pellet("Hush. That's stamped out to you, and it's due back. I shall know where you are."),
  }, other = {
    { when = "em_provost_down", steps = {
      pellet("You're back. With the Proof. That's Reference Only, you know. I'm stamping it out to you anyway, and it's the first time I've done such a thing. Don't tell anyone that I can be moved."),
      { set = "em_stamped" },
    }, other = {
      pellet("Hush. The stair's open. Mind you keep to the catalogue, and don't run. They can smell running."),
    } },
  } },
}

S.em_t_oswin = {
  oswin("Edric, binder, last of the guild. I've got a glue pot and the Empire's entire stock of everything, bought off the dead at fair prices. I keep the receipts."),
  ask(oswin("I've a very nice line in a dead man's armour. He hardly used it."), {
    topic("A million books. What's the use of them?", {
      oswin("There's a shelf downstairs that says how to cure every sickness known, and another that proves the first one's wrong. We burned a good many for heat, the second winter. I started with the poetry."),
    }),
    { "Show me what you've got.", {
      { shop = "em_oswin" },
    } },
    { "Later.", {} },
  }),
}

S.em_t_tuppence = {
  ask(tuppence("Are you from Outside? I was born in the Quiet Rooms. I've read all of Natural History, up to the letter M. Is it true about ducks?"), {
    topic("What about ducks?", {
      tuppence("That you can just have one, and nobody's written anything about it. Warden says there's no such thing as a casual duck. I think she's just tired."),
    }),
    { "Ducks are real. I've met one.", {
      tuppence("I KNEW it. Did it have a purpose? No, don't tell me. I want to think about it. Oh, this is the best day of the year."),
    } },
    { "Go back to your book.", {
      tuppence("All right. But I'm going to be a person who's seen a duck. It's only a matter of the wall."),
    } },
  }),
}

S.em_t_marl = {
  ask(marl("Sit down, you're letting the warm out. Barley and something. Don't ask what the something is. Sixty gold a bed, and that's for the barley, not for me."), {
    { "A bed, please. (60 gold)", {
      { inn = 60 },
      { save = true },
    } },
    { "Not now.", {
      marl("It'll keep. It always does. That's what's wrong with it."),
    } },
  }),
}

S.em_t_hesper = {
  ask(hesper("You're that clean case from the wall, aren't you? We hear things, even here. I've charted every sleeper in this city since the fall. Do you dream?"), {
    topic("Why does everyone ask me that?", {
      hesper("Because I've never found the exception. Every one of them dreams. There's no such thing as a person who doesn't. I've met one or two who claimed it. Go and see Dole at Evrastin. It's her sort of problem."),
    }),
    { "No. I don't dream.", {
      hesper("So you say. I'll put a question mark. I've got a lot of those."),
    } },
    { "I'd rather not say.", {
      hesper("That's the most sensible thing anyone has told me this year."),
    } },
  }),
}

S.em_t_dagny = {
  { when = "em_provost_down", steps = {
    dagny("So you took the stage, and they've all gone home. Thirty years in the chamber, and I've never seen a house clear in good order. I don't suppose I'll need the eyebrow."),
  }, other = {
    dagny("Dagny Fairlie, Second Hiss to the Constellation of Lords, thirty years in the chamber. They kept twelve of us on salary, to give a debate some tone. I once ended a career with one eyebrow."),
    ask(dagny("It's the Ultimatum you're after? You'll be on that stage, then. It's the only way to the back rooms. Do you want some advice from a professional?"), {
      topic("What's up there now?", {
        dagny("The audience. They still come. Every owl in the hills that has anything left to remember with. They sit in the seats, love. Thousands. In rows."),
      }),
      { "What's the advice?", {
        dagny("Don't flatter them, and don't argue. Stand up and say the true thing that's costing you the most. They could always tell. They still can. It'll go easier."),
      } },
      { "I'll manage.", {
        dagny("That's what the Minister for Fisheries said. Mind the third row."),
      } },
    }),
  } },
}

-- ---------------------------------------------------------------- the Stacks

S.em_stacks_in = {
  t("The stairs go down a long way, and stop on a gallery with no far side. Shelves go up into the dark and down into the dark."),
  owl("Two million, eight hundred thousand volumes. I used to think that if I read them all, I'd know what to do. I got to about nine thousand. It's mostly people disagreeing."),
  owl("The way down is by the book lift, in the far south-west bay. You'll want a shelf mark for it."),
}

S.em_card_a = {
  t("A drawer of the great catalogue hangs open on the reading desk. One card has been pulled up, and held with a pin."),
  t("'PROOF, THE LAST. Reserved to the Provost. See the Provost's own shelf mark. Do not ask at the desk. She will not tell you. She thinks it's funny.'"),
}

S.em_card_b = {
  t("A slip of paper in a big, round, impatient hand has been left in a book on the lectern. 'Dear colleague: stop asking. A proof that works is mathematics. A proof that fails is only a story. Shelve accordingly.'"),
}

S.em_t_lift = {
  { when = "em_lift_open", steps = {
    { choice = {
      { "Down to the Closed Reserve.", {
        { warp = { "em_stacks_2", 3, 2, 2 } },
      } },
      { "Stay up here.", {} },
    } },
  }, other = {
    t("A brass book lift, big enough for four people who like each other. It won't move without a shelf mark."),
    ask({ text = "One dial, set by department. What's the Last Proof shelved under?" }, {
      topic("Ask the scholar.", {
        owl("She reorganised it all the week before the end, without telling anyone. There are notes of hers around the gallery. I'd read those, if I were someone who could stand to."),
      }),
      { "Set the dial to FICTION.", {
        t("Somewhere below you, something heavy goes clunk with deep satisfaction."),
        owl("Oh, you dreadful old woman. Fiction. Top marks, {hero}. She'd have given you a look that could peel a pear."),
        { set = "em_lift_open" },
        { warp = { "em_stacks_2", 3, 2, 2 } },
      } },
      { "Set the dial to MEDICINE.", {
        t("The lift delivers a large and very dull work on the care of the feet, and sinks back."),
      } },
      { "Set the dial to ARCANA.", {
        t("The lift spits out a small card. It says, 'Obviously not.'"),
      } },
    }),
  } },
}

S.em_reserve_in = {
  t("The Closed Reserve is low and close and smells of mice and old wax. The shelves here have grilles on them. Something has been eating through the grilles."),
}

S.em_t_grille = {
  t("An iron grille closes the passage, with a lock in the shape of a closed eye."),
  owl("That's the Reserve gate. It opens to a staff key. I, ah. I've got one, or I did. It's in my carrel. Top of the middle block. Yes, I had a carrel. Don't look at me like that."),
}

S.em_t_carrel = {
  { when = "em_carrel", steps = {
    t("A small desk, and a cup with a ring of something at the bottom that has given up."),
  }, other = {
    t("A small desk in a small room. There's a cup, a very old sandwich that has become a kind of mineral, and a stack of papers squared to the corner."),
    t("The scholar sits down. The chair fits. The top sheet is covered in a small neat hand, and in the ninth line there's a figure with a ring round it, in red."),
    owl("This is what I was going to tell you. Tawn was right."),
    owl("The Provost was my teacher, the greatest mind in the Empire, and the rudest. The great working was hers, and I checked the sums. It drove the sickness out of the sleepers, all at once, by force."),
    owl("On the night before she cast it I found this. A sign error. Line nine. The sickness goes out, and the proof doesn't say where to."),
    ask(sis("You saw this. The night before."), {
      topic("Why didn't you tell her?", {
        owl("I told myself that it was small. I was twenty, it was the most beautiful thing I'd ever seen, and I wanted to see it work. There isn't a better reason. I've looked."),
      }),
      topic("What happened?", {
        owl("It went out of them, and it had to go somewhere. It went into the ground, and the owls live on the ground. By noon they were coming down from the hills. By nightfall the sickness was back in the sleepers. So it was all for nothing, in case you'd hoped for better."),
      }),
      { "You were twenty.", {
        owl("Yes. People have said that. I still found it."),
      } },
      { "You should have said.", {
        owl("Yes. Thank you. Nobody has ever just told me so. It's oddly restful."),
      } },
    }),
    t("Nobody says anything for a while. Then the scholar opens the drawer, takes out a key, and leaves the papers where they are."),
    { set = "em_carrel" },
  } },
}

-- ---------------------------------------------------------------- the Ultimatum

S.em_ult_in = {
  t("You come up out of the Reserve into white stone, and light. A hall runs the length of the college, with the rain coming through the roof. Doors stand open. Bells have stopped at the hour for the second lecture."),
  owl("Well. Here we are. Do wipe your feet. She always knew."),
}

S.em_t_chair = {
  t("A lecture room, with four hundred seats going up in rows. A brass plate on the lectern reads 'M. LIOTH, Chair of Moral Philosophy'. Someone has left half a sentence on the board."),
  t("'And so we may conclude that the survivor owes'"),
  owl("She'd have finished that. She'd have marked you down for asking."),
}

S.em_t_study = {
  t("The Provost's study. Books are piled on every surface, and a perch stands by the window, polished by years of use. An appointment book lies open at the last day."),
  t("'Morning: cast. Noon: lunch, if there is a world.' And above that, the night before: 'Give the child my band. Will argue. Do not allow it.'"),
  owl("I did argue. She took it off her own head and put it on mine, the morning of, and told me that I was slouching. I thought she'd made a spare. I found out afterwards."),
  owl("There was never a spare, {hero}."),
}

S.em_scene_arena = {
  t("The hall gives out onto the top of a great bowl of white stone. Seats go round and down in thousands to a circular stage far below."),
  t("They aren't empty. Row on row, in the rain, the owl beasts of Owlundia are sitting with their claws on their knees. Thousands of round eyes come slowly round to you. There's a low, dry hiss from the third row."),
  sis("Oh, the poor things. There's hardly a thread in any of them. And every one of them has come here to listen."),
  t("On the stage there's a chair, and something has outgrown it. It has wings like a barn roof, and the Provost's chain is sunk deep in the feathers of its neck. It looks at the scholar."),
  owl("Provost. It's your student. I've come for the Proof. I'm, ah. Sorry about the time."),
  ask({ text = "All of those eyes. It has been twenty-two years. Someone is going to have to address the chamber." }, {
    { "Scholar. Tell them the truth.", {
      owl("Yes. All right. Yes."),
      owl("Lords, Ladies, members of the public. I found the error on the night before. Line nine. It was my job to say so, and I didn't, because I wanted to see it work. All of you are sitting there because of me. I don't have a second page."),
      t("For a long moment there's only the rain. Then, up in the top rows, a pair of great claws come together, slowly. Then another. It isn't approval. It's a very old habit, and it goes round the bowl like a tide coming in."),
      { set = "em_honest" },
    } },
    { "We've come to end this.", {
      t("Your voice comes back to you from every side, sounding very thin. The hiss starts in the third row and goes round the bowl like a tide coming in."),
      owl("Oh dear. That was a weak opening, {hero}. I'm afraid they've marked it."),
    } },
  }),
  t("The Provost gets up out of the chair. There's rather a lot of her. She looks down at the band on the scholar's head, and something moves in the huge yellow eyes, and then it's gone."),
  provost("HOO."),
  { when = "em_honest", steps = {
    { battle = "em_boss_provost_kind" },
  }, other = {
    { battle = "em_boss_provost" },
  } },
  t("She comes down slowly, wing first, across the stage. Not one head in the chamber is turning."),
  t("The scholar walks across to her, very small, reaches up, takes off the old circlet, and sets it on that enormous head."),
  t("The eye clears, only for a moment. It goes over the scholar from head to foot, in a way that has surely reduced a lot of people to tears, and the great beak opens."),
  provost("Show... your working."),
  owl("Yes, Provost."),
  { fade = true },
  t("All round the bowl, row on row, they get up, and go out by the aisles in no hurry. The third row goes last."),
  owl("I've got the one from the crate. It has someone else's name in it, which seems about right. Excuse me. There's something in my eye. In both of them. They're large eyes."),
  { set = "em_provost_down" },
  { save = true },
}

S.em_t_desk = {
  { has = "em_book", steps = {
    t("An empty desk, with a clean square in the dust."),
  }, other = {
    t("Behind the stage there's a desk, and one thick book in a hand-sewn cover. On the spine, in a big round hand: 'FICTION'. The last sheet is a note, dashed off in a hurry."),
    t("'From the ward at Evrastin: an infant in bed nine, taken ill, and all signs ceased by the eleventh night. One case is not a proof. If I had a month, I would go myself. I have a night.'"),
    doc("An infant. Taken ill, and stopped. In all my years with them I never saw a case stop. Friend? Are you with us?"),
    { choice = {
      { "Take it to the Warden.", {
        doc("Quite right. Back up by the book lift, then."),
      } },
      { "Evrastin's a long way off.", {
        doc("It's nearer than it was. Let's show the Warden first."),
      } },
    } },
    { give = "em_book", n = 1 },
  } },
}

-- ---------------------------------------------------------------- Evrastin

S.em_evr_fog = {
  t("Evrastin stands on the coast with a white light turning over it. Everything between you and the first house is fog, and every time the light goes round, the fog leans."),
  t("The doctor and the sister stop. Their bands have started to sing, a thin high note you can feel in your teeth."),
  owl("No. A circlet only keeps things out, and that is a thing that wants to be let in. We aren't ready. Somebody at Agoshull must know how it can be borne. Back, please."),
  { world = { 47, 62 } },
}

S.em_evr_arrive = {
  t("The fog comes up against the scholar's little ward, and stops, and stands round you like a crowd at a fire."),
  owl("Line nine, corrected. Twenty-two years late. It's holding."),
  t("Evrastin. Crystal has grown through it the way ivy grows through a garden wall, and it rings a little whenever the light goes over."),
  t("Everybody's told you that you came from here. You've never been anywhere that you felt so little."),
  { save = true },
  { set = "em_evr_seen" },
}

S.em_t_dole = {
  { when = "em_read", steps = {
    dole("Go on. Kess's road. I'll keep working. Try to be alive when I've finished, I've rather built it round you."),
  }, other = { { when = "em_light_out", steps = {
    dole("It's dark. I'd forgotten what that was for. If you want the Ward, the Clinic's sitting on it, and I want my records out from under them."),
  }, other = { { when = "em_dole_met", steps = {
    dole("The stair's on the point, past the sluice. Follow the order in the keeper's log. And please don't touch anything up there that's humming."),
  }, other = {
    t("A long thin woman in a stained coat is bent over a bench of glass and copper. Crystal has started on the fingers of her left hand, and she's holding her pen with the right."),
    dole("If that's the Clinic again, the answer is no. If that's the fish, leave it on the step."),
    owl("Proctor Dole? I'm from the Ultimatum. I sent you a stiff note on your fourth paper."),
    dole("That was you? It was a very good note. I've been on the verge of a breakthrough for twenty-two years, you know. It's a wonderful place to live. The views are excellent."),
    ask(dole("You got through the fog. Nobody's done that but the Clinic, and they came with a wagon of lead shutters. So what do you want?"), {
      topic("Is there really a cure?", {
        dole("There's a working. It's the finest thing I'll ever make. Agoshull's arithmetic and our medicine. And it has a blank in the middle of it, like a missing tooth, that says to see the ward record."),
      }),
      topic("What's that light doing?", {
        dole("That's where it began. Magister Kess came back from the Underdark with his whole party screaming in their sleep. So he put them under, took the Keeper's key, and turned the Great Lens on them, to read it out."),
        dole("In the morning everyone who had looked at that beam was dreaming the same thing. He's still up there. It holds this whole quarter under, the Clinic's ward and my records with it."),
      }),
      { "We'll put out the Light.", {
        dole("Will you? You're the first who has offered. Most people just want something. Here's the key to the sea-sluice, on the causeway. The stair goes up from the point."),
      } },
    }),
    dole("The Keeper's log will be in the tower. Follow the order she wrote down. She was very firm about it."),
    { set = "em_dole_met" },
  } } } } } },
}

S.em_t_gannet = {
  gannet("Vessel ahoy! Oh. Sorry, love. It's the fog. Pilot of this harbour for fifty-one years, and I'm still keeping a berth for the Synder packet. They're only a bit late."),
  ask(gannet("You'll have come in by the Light. It guided the fleets of Sindal round the reef for three hundred years."), {
    topic("Did you know the Keeper?", {
      gannet("Ansa Thole? I should say I did. She'd bawl you out from the gallery for a lazy tack, and sit up with you if your boat was late. Could've called the fish in. Why d'you ask?"),
    }),
    { "Keep the berth open.", {
      gannet("Aye. They'll want it. They're only a bit late."),
    } },
    { "They're not coming, Pilot.", {
      gannet("No. I know that, love. I've known it since before you could walk. Don't tell the harbour."),
    } },
  }),
}

--- Burdock's stall; the crystals stop singing when the Light goes out.
local function burdock(pitch)
  return ask(sorrel(pitch), {
    { "Show me what you've got.", {
      { shop = "em_sorrel" },
    } },
    { "Not today.", {
      sorrel("I'll be here. I've looked into going elsewhere."),
    } },
  })
end

S.em_t_sorrel = {
  { when = "em_light_out", steps = {
    burdock("Crystals, fresh off the wall! They've stopped singing, and it hasn't helped trade. I've also got armour and tonics, because it turns out nobody can eat a crystal. I've tried."),
  }, other = {
    burdock("Crystals, fresh off the wall! Don't mind the singing. I've also got armour and tonics, because it turns out nobody can eat a crystal. I've tried."),
  } },
}

S.em_t_sluice = {
  t("An iron gate stands across the causeway to the point, with the sea coming through under it. It's locked, and the lock is the size of a loaf."),
  owl("A sea-sluice. Somebody in this city will have the key. The last researcher, Dole, if Agoshull's gossip is sound. West side of the street."),
}

S.em_t_warder = {
  { when = "em_light_out", steps = {
    warder("I'm afraid the Ward is closed for inventory. Oh, it's you. I was told you might come. I was told to be especially polite."),
    doc("That's a Scythebreak badge. Friend, that one's from your ward."),
    { battle = "em_e_guards" },
    t("The door behind them stands open. It smells of lavender and boiled linen. You knew that it would."),
    { set = "em_guard_down" },
    { save = true },
  }, other = {
    warder("I'm afraid the Ward is closed for inventory. It's quite impossible for you to come in while that light's on. I do hope you'll come back another day."),
  } },
}

-- ---------------------------------------------------------------- the Light

S.em_light_in = {
  t("The sea-sluice opens with a groan, and the stair winds up inside the great white tower. Each time the Light goes round overhead, every stone in the place hums."),
  t("Moths the size of your hand are lying in drifts on the steps, and some of them are still moving."),
}

S.em_t_log = {
  t("The Keeper's day-log, open on a sloping desk. It's a strong black hand, with no time for anyone's nonsense."),
  t("'Order for lighting, written here because the boy forgets. RED for the reef. GREEN for the harbour. WHITE for home. In that order, every night of your life. Always finish on home.'"),
  t("Further down the page: 'Magister K. has had my key off me on the Constellation's warrant. He wants the Lens for his sleepers. I told him what I thought of that from the gallery. They heard me in the harbour.'"),
  t("'Six weeks old tomorrow, and not a wink of sleep in this tower. If it's a tooth I shall be surprised.'"),
}

S.em_t_cradle = {
  t("Under the window there's a wooden cradle, with a lamp-black thumbprint on its rail. Someone has painted a small red boat on the headboard, and it wasn't anyone who could paint."),
  { choice = {
    { "Put a hand on the cradle.", {
      t("It rocks a little and stops. You don't feel anything. You stand there for a moment, in case you do."),
    } },
    { "Walk on.", {} },
  } },
}

local function shutter(lit, wanted, drop, line1, line2)
  return {
    { when = lit, steps = {
      t(line2),
    }, other = {
      t(line1),
      { choice = {
        { "Throw the shutter.", {
          { when = wanted, steps = {
            { set = lit },
            t("The shutter drops with a clean, heavy sound, and the colour goes up the shaft. Something far overhead shifts on its bearings."),
          }, other = {
            { unset = drop },
            t("The beam lurches, and dies back. Whatever order this wants, that wasn't it. All through the tower, the shutters clack back to where they began."),
          } },
        } },
        { "Leave it.", {} },
      } },
    } },
  }
end

S.em_lens_r = {
  { when = "em_l1", steps = {
    t("The red shutter is down. Up the shaft, the colour of a bad tooth."),
  }, other = {
    t("A shutter of red glass, on a counterweight."),
    { choice = {
      { "Throw the shutter.", {
        { set = "em_l1" },
        t("The shutter drops with a clean, heavy sound, and red goes up the shaft. For the reef."),
      } },
      { "Leave it.", {} },
    } },
  } },
}

S.em_lens_g = shutter("em_l2", "em_l1", "em_l1", "A shutter of green glass, on a counterweight.", "The green shutter is down. For the harbour.")

S.em_lens_w = {
  { when = "em_lens_lit", steps = {
    t("The white shutter is down. For home."),
  }, other = {
    t("A shutter of plain white glass, on a counterweight, a good deal more worn than the others."),
    { choice = {
      { "Throw the shutter.", {
        { when = "em_l2", steps = {
          t("White goes up the shaft, and the whole tower lets out one long note, and settles. Somewhere above, a heavy door slides back. You've done what she told you to. It feels very much like being told."),
          { set = "em_lens_lit" },
        }, other = {
          { unset = "em_l1" },
          { unset = "em_l2" },
          t("The beam lurches, and dies back. Whatever order this wants, that wasn't it. All through the tower, the shutters clack back to where they began."),
        } },
      } },
      { "Leave it.", {} },
    } },
  } },
}

S.em_t_lightdoor = {
  t("The way up to the Lens is a bronze door with no handle, ringed with three coloured panes. They're all dark."),
  owl("It's the lighting order. It won't open until the tower's been lit as it should be. There'll be something in the keeper's rooms."),
}

S.em_scene_sleeper = {
  t("The top of the world. The Great Lens fills the room, taller than a house, and turning. The white beam goes out across the fog, slowly, like a hand feeling for something."),
  t("Five chairs stand round it. Four are full of crystal. In the fifth a man in a Magister's robes sits bolt upright, with his eyes wide open and his mouth moving."),
  kess("...and the lower caverns, and the bridges on the chains, and I'll have it out of them by morning. Is that the morning? Keeper, I said no visitors."),
  owl("Magister Kess. It's over. You've been sitting here for twenty-two years."),
  kess("Nearly read. It's so very large, you see, and they brought it home in such a little space. I've only to turn it a bit more, and everyone will be able to..."),
  t("His eyes come round, and stop on you. The whole Lens stops, for the first time in your life."),
  kess("...oh. There you are. It's been looking for you everywhere. Bed nine, bed nine. Keeper, come and see! It's stopped!"),
  { choice = {
    { "Put out the Light.", {
      sis("She'll have him. Go on."),
    } },
    { "What's looking for me?", {
      t("He laughs. It comes out of all five chairs."),
    } },
  } },
  { battle = "em_boss_sleeper" },
  t("Kess slumps with crystal running up his throat. A line runs across the Great Lens from side to side, as fine as a hair, and you feel it in the roots of your teeth."),
  { sfx = "door" },
  { big = "THE LIGHT GOES OUT" },
  t("It's the first dark Evrastin has had in twenty-two years. It comes down over the city very gently, like a blanket. One by one, far below, the crystals stop ringing."),
  t("At the end of the quay someone has lit a small lamp, and is shouting something rude about the state of the fairway."),
  { set = "em_light_out" },
  { save = true },
}

S.em_t_kess_log = {
  { has = "em_route", steps = {
    t("Kess sits in his chair, finished. His mouth has stopped moving at last."),
  }, other = {
    t("In Kess's lap there's a field book, swollen with damp. It's the expedition's. Every page is a sketch-map, in a shaky hand, of a road going down."),
    owl("The Violet Abyss, the east stair. Touarch. The salt. And there, you see, the last page: 'the library at the bottom'. This is the way they went, {hero}. This is the way it came back up."),
    doc("Then that's the way the eye's pointing, and that's the way to the man it's pointing at. I'd rather hoped for somewhere nearer."),
    { give = "em_route", n = 1 },
  } },
}

-- ---------------------------------------------------------------- the ward

S.em_scene_doc = {
  t("The Evrastin Ward is a long, high room with tall windows. The Clinic's lamps are set out in a tidy row, and all the record chests stand open, with their lids at the same angle."),
  t("At the far end a tall figure with a long white beak is sitting at the Matron's desk, writing. He finishes the line, blots it, and looks up."),
  mask("Good morning, {hero}. How did you sleep? There's fresh water by your hand."),
  doc("Get away from that desk."),
  mask("And my colleague. Your transfer's still open, you know. I've missed your handwriting."),
  mask("But I've come a long way, and I do like to keep a promise. I told you that if there was nothing in you, you'd have lost a night's rest, and I should apologise to you in person. It's in the notes."),
  mask("So. I'm sorry for the lost night."),
  ask(mask("Would you like to ask me anything? I always encourage questions."), {
    topic("Where's Nan?", {
      mask("She's being looked after by people who are trained to do it. I'm sorry. I do try to keep my material fresh."),
    }),
    topic("What are you doing here?", {
      mask("Reading. Doctor Colette asked me to find out where a clean result comes from, and it comes from here. I've sent a copy of the page by bird. I've never seen her so interested."),
    }),
    { "Step away from the desk.", {
      mask("Of course. You may refuse. It's on the form. The form says that you will then be held down."),
    } },
    { "I accept your apology.", {
      mask("Do you? How gracious. Nobody ever has. I shall put that in your notes. It won't help, but it's true."),
    } },
  }),
  { battle = "em_boss_doctor" },
  t("He sits down, with care, on the end of the nearest bed, and looks with interest at the red on his coat. Then he undoes two buckles and takes off the mask."),
  t("It's a smaller face than you'd expected. He looks like somebody's uncle."),
  mask("There. It does get warm. I wonder, is there any water?"),
  { choice = {
    { "Give him some water.", {
      t("You hold the cup for him, because his hands have stopped doing what he tells them."),
      mask("Thank you. You've been a great help."),
    } },
    { "Say nothing.", {
      t("He nods, as if you had done something quite correct, and makes a small movement with one hand, as though writing it down."),
    } },
  } },
  { fade = true },
  t("The sister ties a black thread at his wrist. She doesn't say anything about it, and nobody asks her to."),
  doc("It's done, friend. I've wanted that for eleven years. I don't know what I thought I'd do afterwards."),
  t("Behind the far door, someone drags a laundry basket away. The door opens a hand's width, and a very old owlin looks out."),
  tyto("Have they gone? Three days I've been in with the sheets. I'd like it noted that I bit one."),
  t("She comes out with her wings folded and her apron straight. She looks at the doctor, and the sister, and the scholar. She gets to you, and she stops. She stays stopped for some time."),
  tyto("Oh, you've got thin. Look at you. They told me you'd never get past a month. Come to the end of the row. I've kept it made."),
  { set = "em_doc_down" },
  { save = true },
}

S.em_t_bed = {
  t("An iron bed with its sheets folded down, and a Clinic tag tied to the rail. The name on the tag has been written over an older name."),
}

S.em_t_tyto = {
  { when = "em_read", steps = {
    tyto("Go on. You've got a long road, and I've got sheets. I'll keep it made. It's what I do. Mind you eat."),
  }, other = {
    tyto("Bed nine. End of the row, under the window. I've turned it down every night for twenty-two years, and it's been a great trial to my back. Go on, then. I'll come with you."),
  } },
}

S.em_bed_nine = {
  { when = "em_read", steps = {
    t("A very small bed under a window, with the sheet turned down. The moon is out over Evrastin. You didn't know it did that."),
  }, other = {
    t("It's a very small bed. Someone has kept it made, with the sheet turned down, for twenty-two years. A brass 9 is screwed to the rail."),
    tyto("Eleven days, you cried. Your mother had taken ill, and you took it from her, the same as anyone. Six weeks old. Your eyes went back and forth with all the rest. I've never heard a sound like that from something so small."),
    tyto("And on the eleventh night you stopped, all at once, like a clock. I held a feather to your mouth. You were breathing as sweet as you please. I've nursed for sixty years, and I've never been so frightened of a baby."),
    t("She takes down a thick ward book and opens it on the blanket. Her claw goes to a place that has been opened very often."),
    { big = "BED NINE" },
    t("'Infant, six weeks. Taken ill on the ninth. Fever, crying, eyes moving with the ward. Eleventh night: all signs cease. Feeds well. Does not appear to dream.'"),
    t("'Name: {hero}. Mother: Ansa Thole, Keeper of the Evrastin Light.'"),
    t("You've written that name a great many times, beside the word nothing. You've never seen it in anybody else's hand."),
    t("Below that the writing changes. It's a strong black hand, gone rather large, running downhill, and you've read it before."),
    t("'They say I shan't see the week out. Put the child on the last cart, and tell nobody which bed. Don't let them make a study of it. Red for the reef, green for the harbour. Always finish on home.'"),
    hero("She wrote that."),
    tyto("With me holding the book. She went on the twelfth night. She'd seen you stop, you know. She laughed. It's the only time I ever heard anyone laugh on this ward."),
    ask(tyto("You've got her chin, you know. Ask me what you like. I've been saving it."), {
      topic("What was she like?", {
        tyto("Loud. She'd bawl out a Magister from the top of her tower, and then come down and do the night shift. She sang to you, very badly. She only knew shanties."),
      }),
      topic("Why did I stop?", {
        tyto("I don't know. I wrote down what I saw, and that's all a nurse can do. Ask the ones who know about such things. And when they tell you, ask them how they know."),
      }),
      { "How did I get out?", {
        tyto("In a crate, on the last cart. I wrote on the lid myself, so the soldiers wouldn't look in. It said NO TROUBLE."),
        hero("An old woman opened it. She took one look, and said, that one's going to be no trouble."),
        tyto("Did she, now? And was she good to you?"),
        { choice = {
          { "She asked what I dreamed, every morning.", {
            tyto("Every morning? Well, then. Then you were well kept. That's all I've wanted to know, for twenty-two years."),
          } },
          { "She said I'd be the lucky one.", {
            tyto("Then you were loved by somebody with sense. I'll take that, and go on with my sheets."),
          } },
        } },
      } },
    }),
    { give = "em_record", n = 1 },
    { set = "em_read" },
    t("Someone comes in at the far end of the ward, walking fast, in a stained coat, with a roll of paper under one arm."),
    dole("It went out! The whole quarter's awake. Matron, I need the record for bed nine. It's the blank, I've been staring at that blank for twenty-two years. Where's..."),
    t("She looks down at the book, at the name, and then at you. It doesn't take her long, and she has to sit down."),
    dole("Well. There's my missing tooth. Hello. I've been on the verge of you for some time."),
    t("She spreads the roll across the blanket: a whole wall's worth of tiny neat lines, and in the very middle a gap with three words in it. 'See bed nine.'"),
    dole("This is the cure. I don't say that lightly. It'll work, and it needs you, {hero}. Not your blood or your good wishes. You. It asks for you the way a lock asks for a key."),
    ask(dole("I'm sorry. I don't know how else to put it."), {
      topic("Why me? What does it want with me?", {
        dole("I don't know. The medicine says what, it doesn't say why. There was a page. Look. There's a page gone from the back of the record."),
        t("It's been cut out close to the spine with something very sharp, a long time ago. Matron Tyto looks at it, and folds her wings."),
        tyto("That was gone before the cart left. The Keeper's knife, I thought. She never told me, and by then she'd stopped being able to."),
      }),
      topic("Can it cure Nan? All of them?", {
        dole("Every sleeper in every town, if it does what it says. I'll tell you honestly, I've no idea what else it does. I've only ever seen the outside of it."),
      }),
      { "What do you need me to do?", {
        dole("Nothing, yet. Stay alive, and stay out of that woman's hands. There's something at the bottom of Kess's road that I'd want to read before I touched this. Go and find it, and I'll keep working."),
      } },
      { "Then what happens to me?", {
        dole("I don't know that either. I'd like to hear from anyone who can tell me. Go down Kess's road, and find out. I'll keep working."),
      } },
    }),
    t("Outside it's getting light. A real, plain, ordinary morning is coming up over the harbour."),
    owl("I've got a thought, and I don't care for it. I'm going to keep it until I've tried to prove it wrong. I've learned something about keeping quiet, {hero}, and I promise you this isn't that. I'll show my working."),
    sis("I've had hold of your thread since Orrenshire. I'm not going to say any more than that. I've been wrong before. Once."),
    doc("Like a clock. I told you that, the first night, and said to forget it. I'm going to stay right here beside you, friend. You can consider that a clinical opinion."),
    { choice = {
      { "Let's go. Kess's road goes down.", {
        doc("It does. The Abyss, then. It's a long walk, and I've got a spoon."),
      } },
      { "I've lived with not knowing.", {
        doc("So you have. Better than any of us. I'd still like to know. The Abyss, then."),
      } },
    } },
    { dark = true },
    t("Far to the north-east, in Adaphis. The high room in the Cranial District, and one lamp."),
    t("On the desk lies a page from a ward at Evrastin, copied in a very neat hand. A woman in a physician's grey reads one line of it again. 'Mother: Ansa Thole.'"),
    t('"Somebody\'s child," says Doctor Colette, to no one. She moves the lamp a little closer, and doesn\'t turn the page.'),
    { dark = false },
    { fade = true },
    { big = "THE ROAD GOES DOWN" },
    { set = "em_done" },
    { save = true },
  } },
}

S.em_back_through = {
  t("You know the way under the wall by now. It takes the best part of an hour, and nothing down there wants to stop you."),
  { warp = { "em_crack_1", 28, 9, 2 } },
}

-- ---------------------------------------------------------------- maps

M.em_crack_1 = {
  name = "THE CRACK", theme = "cave",
  rows = {
    "#############WWWW#############",
    "#############WWWW#####>.######",
    "#..........##WWWW######.######",
    "#..........##WWWW######.######",
    "#..........##WWWW######.######",
    "########.####WWWW######.######",
    "########.####WWWW######.######",
    "########.####WWWW######.######",
    "#...........>WWWW>...........#",
    "#####.#######WWWW#####.#######",
    "###......####WWWW###hh+hhhh###",
    "###......####WWWW###h.....h###",
    "###......####WWWW###h.....h###",
    "#############WWWW###hhhhhhh###",
    "#############WWWW#############",
  },
  npcs = {
    who("em_front", 20, 9, "em_t_front", nil, "em_circlets", "em_wool"),
    who("em_wall_log", 25, 13, "em_t_wall_log"),
  },
  steps = {
    { x = 27, y = 9, script = "em_arrive", once = true },
    { x = 11, y = 9, script = "em_out", when = "em_breath_down", once = true },
    { x = 3, y = 9, script = "em_back_through", when = "em_done" },
  },
  chests = {
    { id = "c1", x = 22, y = 13, give = "hipotion", n = 2 },
    { id = "c2", x = 2, y = 3, give = "ether", n = 2 },
    { id = "c3", x = 8, y = 13, gold = 400 },
    { id = "c4", x = 11, y = 5, give = "scale_vest" },
  },
  foes = {
    { id = "f1", x = 24, y = 12, enc = "em_e_wall1", sprite = "crawler" },
    { id = "f2", x = 5, y = 4, enc = "em_e_wall2", sprite = "em_wool" },
    { id = "f3", x = 5, y = 12, enc = "em_e_wall3", sprite = "blighted" },
  },
  exits = {
    { x = 29, y = 9, world = { 62, 67 } },
    { x = 2, y = 9, world = { 57, 67 } },
    { x = 23, y = 2, map = "em_scythebreak", mx = 22, my = 15, dir = 4 },
    { x = 18, y = 9, map = "em_crack_2", mx = 30, my = 7, dir = 4 },
    { x = 13, y = 9, map = "em_crack_2", mx = 3, my = 7, dir = 2 },
  },
}

M.em_crack_2 = {
  name = "UNDER THE WALL", theme = "cave",
  rows = {
    "################################",
    "##################....###....###",
    "##################....###....###",
    "####~~~~~~~~~######.######.#####",
    "####~~.....~~######.######.#####",
    "####~.......~######.######.#####",
    "#>............................>#",
    "####~.......~#############.#####",
    "####~~.....~~#############.#####",
    "####~~~~~~~~~#############.#####",
    "#########################....###",
    "#########################....###",
    "################################",
    "################################",
    "################################",
  },
  npcs = {
    who("em_lamp_a", 21, 2, "em_t_lamp_a", nil, nil, "em_lamp"),
    who("em_lamp_b", 28, 2, "em_t_lamp_b", nil, nil, "em_lamp"),
    who("em_lamp_c", 28, 12, "em_t_lamp_c", nil, nil, "em_lamp"),
    who("em_fog", 15, 7, "em_t_fog", nil, "em_lamps", "em_wool"),
    who("em_mass", 9, 7, "em_scene_breath", nil, "em_breath_down", "em_breath"),
  },
  steps = {
    { x = 13, y = 7, script = "em_scene_breath", unless = "em_breath_down" },
  },
  chests = {
    { id = "c1", x = 19, y = 3, give = "hipotion", n = 2 },
    { id = "c2", x = 29, y = 11, give = "lancet" },
    { id = "c3", x = 26, y = 2, give = "tonic", n = 3 },
    { id = "c4", x = 9, y = 9, give = "swift_band" },
  },
  foes = {
    { id = "f1", x = 24, y = 7, enc = "em_e_wall1", sprite = "crawler" },
    { id = "f2", x = 20, y = 5, enc = "em_e_wall2", sprite = "em_wool" },
    { id = "f3", x = 27, y = 5, enc = "em_e_wall3", sprite = "blighted" },
    { id = "f4", x = 27, y = 9, enc = "em_e_wall2", sprite = "em_wool" },
    { id = "f5", x = 19, y = 7, enc = "em_e_wall3", sprite = "blighted" },
  },
  exits = {
    { x = 31, y = 7, map = "em_crack_1", mx = 19, my = 9, dir = 2 },
    { x = 2, y = 7, map = "em_crack_1", mx = 12, my = 9, dir = 4 },
  },
}

M.em_scythebreak = {
  name = "SCYTHEBREAK", theme = "town",
  rows = {
    "WW#######################",
    "WW.....h.....h.....h...h#",
    "WW.....h.....h.....h...h#",
    "WW.....h.....hhh+hhhh+hh#",
    "WWhh+hhh.....h.........h#",
    "WW...........h.........h#",
    "WW...........h.........h#",
    "WWhhhhhh.....hh+hhhhhhhh#",
    "WW....hh........hhhhhhhh#",
    "WW....hh........hhhhhhhh#",
    "WW......................#",
    "WW....hh........hhhhhhhh#",
    "WW....hh........hhhhhhhh#",
    "WWhhhhhhh...hhhhhhhhhhhh#",
    "WW....................>h#",
    "WWhh+hhhhh+hhhhh+hhhhhhh#",
    "WW.....h.....h.....hhhhh#",
    "WW.....h.....h.....hhhhh#",
    "#########################",
  },
  npcs = {
    who("em_satchel", 13, 12, "em_t_satchel", nil, nil, "guard"),
    who("em_dreambook", 12, 10, "em_t_book"),
    who("em_crate", 17, 2, "em_t_crate", nil, nil, "chest"),
    who("em_bed_nan", 19, 7, "em_t_bed_nan"),
  },
  steps = {
    { x = 21, y = 15, script = "em_home", once = true },
    { x = 5, y = 4, script = "em_s_nan", once = true },
    { x = 8, y = 11, script = "em_s_wick", once = true },
    { x = 4, y = 11, script = "em_s_watch", once = true },
    { x = 11, y = 3, script = "em_s_kid", once = true },
    { x = 5, y = 17, script = "em_s_widow", once = true },
    { x = 11, y = 17, script = "em_s_lioth", once = true },
    { x = 16, y = 7, script = "em_s_ward", once = true },
    { x = 22, y = 3, script = "em_s_spoon", once = true },
  },
  chests = {
    { id = "c1", x = 3, y = 2, give = "tonic", n = 2 },
    { id = "c2", x = 13, y = 18, give = "scholar_robe" },
    { id = "c3", x = 19, y = 18, gold = 300 },
    { id = "c4", x = 23, y = 7, give = "hipotion", n = 3 },
  },
  exits = {
    { x = 24, y = 11, world = { 62, 60 } },
    { x = 23, y = 15, map = "em_crack_1", mx = 24, my = 2, dir = 3 },
  },
}

M.em_agoshull = {
  name = "AGOSHULL", theme = "city", savepoint = true,
  rows = {
    "##############################",
    "#h...........h##h...........h#",
    "#h...........h##h...........h#",
    "#h...........h##h...........h#",
    "#h...........h##h...........h#",
    "#hhhhhh+hhhhhh##hhhhh+hhhhhhh#",
    "#............................#",
    "#............................#",
    "#.........~~~~~~~~...........#",
    ">.........~~~~~~~~...........#",
    "#.........~~~~~~~~...........#",
    "#.........~~~~~~~~...........#",
    "#............................#",
    "#............................#",
    "#hhhhhh+hhhhhh##hhhhh+hhhhhhh#",
    "#h...........h##h...........h#",
    "#h...........h##h...........h#",
    "#h...........h##h...........h#",
    "##############################",
  },
  npcs = {
    who("em_tawn", 5, 3, "em_t_tawn"),
    who("em_hob", 27, 9, "em_t_hob"),
    who("em_perigee", 8, 17, "em_t_perigee"),
    who("em_pellet", 2, 10, "em_t_pellet", nil, "em_past_desk"),
    who("em_pellet_aside", 3, 8, "em_t_pellet_aside", "em_past_desk"),
    who("em_oswin", 25, 3, "em_t_oswin"),
    who("em_hesper", 20, 3, "em_t_hesper"),
    who("em_tuppence", 20, 17, "em_t_tuppence"),
    who("em_marl", 25, 17, "em_t_marl"),
    who("em_dagny", 16, 13, "em_t_dagny"),
  },
  steps = {
    { x = 28, y = 10, script = "em_ag_arrive", once = true },
  },
  chests = {
    { id = "c1", x = 12, y = 2, give = "ether", n = 2 },
    { id = "c2", x = 12, y = 18, give = "hipotion", n = 2 },
  },
  exits = {
    { x = 29, y = 10, world = { 30, 57 } },
    { x = 1, y = 10, map = "em_stacks_1", mx = 25, my = 3, dir = 4 },
  },
}

M.em_stacks_1 = {
  name = "THE STACKS: OPEN GALLERY", theme = "library",
  rows = {
    "############################",
    "##....h....h....h....h....##",
    "##....h....h....h....h...>##",
    "##....h....h....h....h....##",
    "##h.hhhh.hhhh.hhhh.hhhh.hh##",
    "##........................##",
    "##........................##",
    "##..~~~~~~~~~~~~~~~~~~~~..##",
    "##..~~~~~~~~~~~~~~~~~~~~..##",
    "##..~~~~~~~~~~~~~~~~~~~~..##",
    "##..~~~~~~~~~~~~~~~~~~~~..##",
    "##..~~~~~~~~~~~~~~~~~~~~..##",
    "##........................##",
    "##........................##",
    "##h.hhhh.hhhh.hhhh.hhhh.hh##",
    "##....h....h....h....h....##",
    "##....h....h....h....h....##",
    "############################",
  },
  npcs = {
    who("em_catalogue", 9, 2, "em_card_a"),
    who("em_lectern", 19, 17, "em_card_b"),
    who("em_lift", 4, 17, "em_t_lift", nil, nil, "chest"),
  },
  steps = {
    { x = 24, y = 3, script = "em_stacks_in", once = true },
  },
  chests = {
    { id = "c1", x = 15, y = 3, give = "hipotion", n = 2 },
    { id = "c2", x = 20, y = 2, gold = 500 },
    { id = "c3", x = 24, y = 17, give = "splint_mail" },
    { id = "c4", x = 9, y = 17, give = "ether", n = 2 },
  },
  foes = {
    { id = "f1", x = 12, y = 6, enc = "em_e_stack1", sprite = "em_bookworm" },
    { id = "f2", x = 20, y = 7, enc = "em_e_stack2", sprite = "em_folio" },
    { id = "f3", x = 3, y = 10, enc = "em_e_stack3", sprite = "em_invigilator" },
    { id = "f4", x = 25, y = 11, enc = "em_e_stack4", sprite = "em_owlbeast" },
    { id = "f5", x = 15, y = 13, enc = "em_e_stack1", sprite = "em_bookworm" },
    { id = "f6", x = 9, y = 14, enc = "em_e_stack2", sprite = "em_folio" },
  },
  exits = {
    { x = 26, y = 3, map = "em_agoshull", mx = 3, my = 10, dir = 2 },
  },
}

M.em_stacks_2 = {
  name = "THE STACKS: CLOSED RESERVE", theme = "library",
  rows = {
    "############################",
    "#>.....h.........h.........#",
    "#hhhhh.h.hhhhhhh.h.hhhhhhh.#",
    "#......h.h.....h...h.....h.#",
    "#.hhhhhh.h.....hhhhh.....h.#",
    "#........+.....h...h.....h.#",
    "#.hhhhhh.h.....h.h.+.....h.#",
    "#......h.hhhhhhh.h.hhhhhhh.#",
    "#hhhhh.h.........h.........#",
    "#......hhhhhhhhhhhhhhhhhhhh#",
    "#.hhhhhhhhhhhhhhhhhhhhhhhh.#",
    "#..........................#",
    "#hhhhhhhhhhhhhhhhhhhhhhhhh.#",
    "#..........................#",
    "#>##########################",
    "############################",
  },
  npcs = {
    who("em_carrel_desk", 13, 5, "em_t_carrel"),
    who("em_grille", 2, 11, "em_t_grille", nil, "em_carrel", "em_grille"),
  },
  steps = {
    { x = 3, y = 2, script = "em_reserve_in", once = true },
  },
  chests = {
    { id = "c1", x = 23, y = 5, give = "scribe_rod" },
    { id = "c2", x = 14, y = 7, gold = 600 },
    { id = "c3", x = 22, y = 4, give = "cantor_ring" },
    { id = "c4", x = 24, y = 7, give = "hipotion", n = 3 },
  },
  foes = {
    { id = "f1", x = 12, y = 2, enc = "em_e_stack1", sprite = "em_bookworm" },
    { id = "f2", x = 24, y = 2, enc = "em_e_stack3", sprite = "em_invigilator" },
    { id = "f3", x = 27, y = 6, enc = "em_e_stack4", sprite = "em_owlbeast" },
    { id = "f4", x = 12, y = 9, enc = "em_e_stack2", sprite = "em_folio" },
    { id = "f5", x = 5, y = 6, enc = "em_e_stack4", sprite = "em_owlbeast" },
    { id = "f6", x = 15, y = 12, enc = "em_e_stack3", sprite = "em_invigilator" },
    { id = "f7", x = 10, y = 14, enc = "em_e_stack2", sprite = "em_folio" },
  },
  exits = {
    { x = 2, y = 2, map = "em_stacks_1", mx = 4, my = 16, dir = 3 },
    { x = 2, y = 15, map = "em_ultimatum", mx = 3, my = 5, dir = 2 },
  },
}

M.em_ultimatum = {
  name = "THE ULTIMATUM", theme = "marble",
  rows = {
    "###########################",
    "##h.......h#####h.......h##",
    "##h.......h#####h.......h##",
    "##hhhh+hhhh#####hhhh+hhhh##",
    "#>.......................##",
    "############...############",
    "#####~~~~~~~...~~~~~~~#####",
    "###~~~~~~~~~...~~~~~~~~~###",
    "##~~~~~~~~~~...~~~~~~~~~~##",
    "##~~~~~~~.........~~~~~~~##",
    "#~~~~~~~...........~~~~~~~#",
    "#~~~~~~.............~~~~~~#",
    "#~~~~~~.............~~~~~~#",
    "#~~~~~~.............~~~~~~#",
    "#~~~~~~~...........~~~~~~~#",
    "##~~~~~~~.........~~~~~~~##",
    "##~~~~~~~~~~...~~~~~~~~~~##",
    "###~~~~~~~~~...~~~~~~~~~###",
    "#####~~~~~~~...~~~~~~~#####",
    "###########h...h###########",
    "#########h.......h#########",
    "#########h.......h#########",
    "###########################",
  },
  npcs = {
    who("em_chair", 5, 2, "em_t_chair"),
    who("em_study", 19, 2, "em_t_study"),
    who("em_seat", 14, 12, "em_scene_arena", nil, "em_provost_down", "em_provost"),
    who("em_desk", 14, 21, "em_t_desk"),
  },
  steps = {
    { x = 3, y = 5, script = "em_ult_in", once = true },
    { x = 13, y = 9, script = "em_scene_arena", unless = "em_provost_down" },
    { x = 14, y = 9, script = "em_scene_arena", unless = "em_provost_down" },
    { x = 15, y = 9, script = "em_scene_arena", unless = "em_provost_down" },
  },
  chests = {
    { id = "c1", x = 9, y = 2, give = "clear_eye" },
    { id = "c2", x = 23, y = 2, give = "ether", n = 3 },
    { id = "c3", x = 11, y = 21, give = "warblade" },
    { id = "c4", x = 17, y = 22, gold = 800 },
  },
  foes = {
    { id = "f1", x = 10, y = 5, enc = "em_e_ult1", sprite = "em_invigilator" },
    { id = "f2", x = 18, y = 5, enc = "em_e_ult1", sprite = "em_invigilator" },
    { id = "f3", x = 24, y = 5, enc = "em_e_stack4", sprite = "em_owlbeast" },
  },
  exits = {
    { x = 2, y = 5, map = "em_stacks_2", mx = 2, my = 14, dir = 1 },
  },
}

M.em_evrastin = {
  name = "EVRASTIN", theme = "ruin",
  rows = {
    "##############################",
    "#~~~~~~~~~~~~#>#~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~#.#~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~#.#~~~~~~~~~~~~~#",
    "#~~~~~~~...........~~~~~~~~~~#",
    "#~~~~~~~...........~~~~~~~~~~#",
    "#............................#",
    "#hhhh+hhhhh...hhhhh+hhhh.....#",
    "#h........h...h........h.....#",
    "#h........h...h........h.....#",
    "#hhhhhhhhhh...hhhhhhhhhh.....#",
    "#............................#",
    "#............................#",
    "##############>###############",
    "##############################",
  },
  npcs = {
    who("em_dole", 6, 10, "em_t_dole"),
    who("em_gannet", 13, 6, "em_t_gannet"),
    who("em_sorrel", 20, 10, "em_t_sorrel"),
    who("em_sluice", 15, 4, "em_t_sluice", nil, "em_dole_met", "em_grille"),
    who("em_w_orderly", 15, 13, "em_t_warder", nil, "em_guard_down"),
  },
  steps = {
    { x = 28, y = 10, script = "em_evr_fog", unless = "em_proof" },
    { x = 28, y = 10, script = "em_evr_arrive", when = "em_proof", once = true },
  },
  chests = {
    { id = "c1", x = 9, y = 9, give = "ether", n = 2 },
    { id = "c2", x = 23, y = 9, gold = 700 },
    { id = "c3", x = 28, y = 12, give = "hipotion", n = 2 },
  },
  exits = {
    { x = 29, y = 10, world = { 47, 62 } },
    { x = 15, y = 2, map = "em_light_1", mx = 11, my = 14, dir = 1 },
    { x = 15, y = 14, map = "em_ward", mx = 3, my = 5, dir = 2 },
  },
}

M.em_light_1 = {
  name = "THE EVRASTIN LIGHT", theme = "ruin",
  rows = {
    "#####################",
    "#...................#",
    "#.hhhhhhhhhhhhhhhhh.#",
    "#.h.....h.h>h.h...h.#",
    "#.h.....h.....h...h.#",
    "#.h.....h.....h...h.#",
    "#.hhh+hhhhh+hhhh+hh.#",
    "#.h...............h.#",
    "#.h...............h.#",
    "#.hhhhhhhhh+hhhhhhh.#",
    "#.h...............h.#",
    "#.h...............+.#",
    "#.hhhhhhhhhhhhhhhhh.#",
    "#...................#",
    "##########>##########",
  },
  npcs = {
    who("em_keeper_log", 5, 4, "em_t_log"),
    who("em_cradle", 7, 5, "em_t_cradle"),
    who("em_shut_r", 10, 5, "em_lens_r", nil, nil, "em_lamp"),
    who("em_shut_g", 14, 5, "em_lens_g", nil, nil, "em_lamp"),
    who("em_shut_w", 14, 6, "em_lens_w", nil, nil, "em_lamp"),
    who("em_lightdoor", 12, 5, "em_t_lightdoor", nil, "em_lens_lit", "em_grille"),
  },
  steps = {
    { x = 11, y = 14, script = "em_light_in", once = true },
  },
  chests = {
    { id = "c1", x = 8, y = 6, give = "hipotion", n = 2 },
    { id = "c2", x = 18, y = 4, give = "storm_ward" },
    { id = "c3", x = 16, y = 6, give = "tonic", n = 3 },
    { id = "c4", x = 4, y = 11, gold = 900 },
  },
  foes = {
    { id = "f1", x = 2, y = 8, enc = "em_e_light1", sprite = "em_moth" },
    { id = "f2", x = 11, y = 2, enc = "em_e_light2", sprite = "em_shard" },
    { id = "f3", x = 20, y = 5, enc = "em_e_light3", sprite = "em_shard" },
    { id = "f4", x = 8, y = 11, enc = "em_e_light1", sprite = "em_moth" },
    { id = "f5", x = 15, y = 8, enc = "em_e_light3", sprite = "em_shard" },
  },
  exits = {
    { x = 11, y = 15, map = "em_evrastin", mx = 15, my = 3, dir = 3 },
    { x = 12, y = 4, map = "em_light_2", mx = 11, my = 12, dir = 1 },
  },
}

M.em_light_2 = {
  name = "THE GREAT LENS", theme = "dream",
  rows = {
    "#####################",
    "#~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~.......~~~~~~#",
    "#~~~~...........~~~~#",
    "#~~~.............~~~#",
    "#~~...............~~#",
    "#~~.......#.......~~#",
    "#~~...............~~#",
    "#~~~.............~~~#",
    "#~~~~...........~~~~#",
    "#~~~~~~.......~~~~~~#",
    "#~~~~~~~~~.~~~~~~~~~#",
    "##########>##########",
    "#####################",
    "#####################",
  },
  npcs = {
    who("em_kess_chair", 11, 8, "em_t_kess_log", "em_light_out"),
  },
  steps = {
    { x = 11, y = 11, script = "em_scene_sleeper", unless = "em_light_out" },
  },
  chests = {
    { id = "c1", x = 5, y = 7, give = "brigandine" },
    { id = "c2", x = 17, y = 7, give = "hiether", n = 1 },
  },
  exits = {
    { x = 11, y = 13, map = "em_light_1", mx = 12, my = 5, dir = 3 },
  },
}

M.em_ward = {
  name = "THE EVRASTIN WARD", theme = "town",
  rows = {
    "#########################",
    "#hhhhhhhhhhhhhhhhhhhhhhh#",
    "#h.....................h#",
    "#h.....................h#",
    "#>.....................h#",
    "#h.....................h#",
    "#h.....................h#",
    "#hhhhhhhhhhhhhhhhhhhh+hh#",
    "#hhhhhhhhhhhhhhhhh.....h#",
    "#hhhhhhhhhhhhhhhhh.....h#",
    "#hhhhhhhhhhhhhhhhhhhhhhh#",
    "#########################",
    "#########################",
    "#########################",
    "#########################",
  },
  npcs = {
    who("em_bed_1", 6, 3, "em_t_bed"),
    who("em_bed_2", 10, 3, "em_t_bed"),
    who("em_bed_3", 14, 3, "em_t_bed"),
    who("em_bed_4", 6, 7, "em_t_bed"),
    who("em_bed_5", 10, 7, "em_t_bed"),
    who("em_bed_6", 14, 7, "em_t_bed"),
    who("em_bed_nine", 23, 3, "em_bed_nine", "em_doc_down"),
    who("em_mask", 20, 5, "em_scene_doc", nil, "em_doc_down", "doctor"),
    who("em_tyto", 21, 6, "em_t_tyto", "em_doc_down"),
  },
  steps = {
    { x = 3, y = 5, script = "em_scene_doc", unless = "em_doc_down" },
  },
  chests = {
    { id = "c1", x = 23, y = 9, give = "tonic", n = 3 },
    { id = "c2", x = 19, y = 10, give = "wool_habit" },
  },
  exits = {
    { x = 2, y = 5, map = "em_evrastin", mx = 15, my = 13, dir = 1 },
  },
}

-- ---------------------------------------------------------------- shops and things carried

R.shops.em_oswin = { tier = 4 }
R.shops.em_sorrel = { tier = 4, extra = { { item = "tent", price = 280 } } }

R.items.em_ticket = { name = "READER'S TICKET", key = true }
R.items.em_book = { name = "THE LAST PROOF", key = true }
R.items.em_route = { name = "KESS'S FIELD BOOK", key = true }
R.items.em_record = { name = "WARD BOOK, BED NINE", key = true }

-- ---------------------------------------------------------------- what's in the way

local A = R.abilities
A.em_talon = { name = "TALON", power = 115 }
A.em_hoot = { name = "DEEP HOOT", mp = 3, power = 30, magic = true, target = "all", status = "sleep", chance = 30 }
A.em_peck = { name = "PECK", power = 90 }
A.em_smother = { name = "SMOTHER", mp = 3, power = 45, magic = true, status = "sleep", chance = 45 }
A.em_blot = { name = "INK BLOT", power = 50, status = "blind", chance = 60 }
A.em_papercut = { name = "PAPER CUT", power = 80, status = "poison", chance = 35 }
A.em_recite = { name = "RECITE", mp = 4, power = 70, magic = true, element = "mind" }
A.em_rap = { name = "THE RULER", power = 105 }
A.em_hush = { name = "SILENCE IN HALL", mp = 3, power = 20, magic = true, status = "silence", chance = 70 }
A.em_dust = { name = "LENS DUST", power = 40, target = "all", status = "blind", chance = 35 }
A.em_cut = { name = "SHARD", power = 115 }
A.em_stitch = { name = "FIELD SUTURE", mp = 4, target = "friend", power = 20, share = 12 }
A.em_gasp = { name = "GASP", power = 100 }
A.em_inhale = { name = "THE LONG BREATH", power = 190, magic = true, target = "all", windup = 34, warn = "THE AIR GOES OUT OF THE ROOM" }
A.em_cough = { name = "IT COUGHS THEM UP", target = "summon", summon = "em_wall_crawler" }
A.em_hiss = { name = "THE HISS", mp = 5, power = 70, magic = true, target = "all", element = "mind" }
A.em_qed = { name = "Q.E.D.", power = 200, magic = true, target = "all", windup = 34, warn = "SHE WRITES THE LAST LINE" }
A.em_class = { name = "SHE CALLS THE CLASS", target = "summon", summon = "em_owlet" }
A.em_beam = { name = "THE LIGHT", mp = 4, power = 90, magic = true, status = "blind", chance = 40 }
A.em_lull = { name = "LULLABY", mp = 5, power = 45, magic = true, target = "all", status = "sleep", chance = 40 }
A.em_sweep = { name = "THE BEAM COMES ROUND", power = 210, magic = true, target = "all", windup = 34, warn = "THE LIGHT TURNS TOWARD YOU" }
A.em_moths = { name = "THE MOTHS COME", target = "summon", summon = "em_moth" }
A.em_scalpel = { name = "SCALPEL", power = 110 }
A.em_kind = { name = "A KIND WORD", mp = 5, power = 60, magic = true, target = "all", status = "blind", chance = 30 }
A.em_dose = { name = "FULL DOSE", power = 190, magic = true, target = "all", windup = 34, warn = "HE DRAWS UP THE DOSE", status = "sleep", chance = 30 }

local F = R.foes
F.em_wall_crawler = { name = "WALL CRAWLER", tier = 21, shape = "small", sprite = "crawler", family = "bug", abilities = { { "bite", 3 }, { "spit", 1 } } }
F.em_wool = { name = "DREAM WOOL", tier = 21, shape = "caster", sprite = "em_wool", family = "ghost", abilities = { { "em_smother", 3 }, { "stare", 2 } }, weak = { "fire" } }
F.em_walled = { name = "WALLED MAN", tier = 22, shape = "brute", sprite = "blighted", family = "blighted", abilities = { { "claw", 4 }, { "retch", 2 }, { "touch", 1 } } }
F.em_owlet = { name = "OWLET", tier = 22, shape = "small", sprite = "em_owlet", family = "harpy", abilities = { { "em_peck", 3 }, { "shriek", 1 } } }
F.em_owlbeast = { name = "OWL BEAST", tier = 22, shape = "brute", sprite = "em_owlbeast", family = "stalker", abilities = { { "em_talon", 4 }, { "em_hoot", 1 } } }
F.em_bookworm = { name = "BOOKWORM", tier = 23, shape = "quick", sprite = "em_bookworm", family = "bug", abilities = { { "gnaw", 3 }, { "em_blot", 1 } } }
F.em_folio = { name = "LOOSE FOLIO", tier = 23, shape = "caster", sprite = "em_folio", family = "ghost", abilities = { { "em_papercut", 3 }, { "em_recite", 2 } }, weak = { "fire" } }
F.em_invigilator = { name = "INVIGILATOR", tier = 24, shape = "tank", sprite = "em_invigilator", family = "knight", abilities = { { "em_rap", 3 }, { "em_hush", 2 } }, weak = { "bolt" } }
F.em_moth = { name = "LENS MOTH", tier = 25, shape = "small", sprite = "em_moth", family = "bug", abilities = { { "bite", 3 }, { "em_dust", 2 } }, weak = { "fire" } }
F.em_shard = { name = "SHARD SLEEPER", short = "SHARD", tier = 25, shape = "tank", sprite = "em_shard", family = "blighted", abilities = { { "em_cut", 3 }, { "stare", 1 } }, weak = { "bolt" } }
F.em_field_orderly = { name = "FIELD ORDERLY", short = "ORDERLY", tier = 25, shape = "brute", sprite = "orderly", family = "staff", abilities = { { "baton", 3 }, { "needle", 2 } } }
F.em_field_doctor = { name = "FIELD DOCTOR", tier = 25, shape = "healer", sprite = "doctor", family = "staff", abilities = { { "baton", 2 }, { "em_stitch", 2 }, { "draught", 1 } } }

F.em_b_breath = {
  name = "THE LONG BREATH", short = "LONG BREATH", tier = 22, sprite = "em_breath", family = "boss", size = 3, weak = { "fire" },
  boss = { hpx = 1, phases = {
    { at = 100, moves = { { "em_gasp", 5 }, { "em_smother", 2 } }, every = 5, big = "em_inhale" },
    { at = 60, moves = { { "em_gasp", 5 }, { "em_smother", 3 } }, every = 4, big = "em_inhale", say = "IT WON'T STOP", speedUp = 1, call = "em_cough", summon = "em_wall_crawler" },
    { at = 30, moves = { { "em_gasp", 4 }, { "em_smother", 3 } }, every = 3, big = "em_inhale", say = "THE WALL SHAKES", speedUp = 1, call = "em_cough", summon = "em_wall_crawler" },
  } },
}

local function theProvost(share)
  return {
    name = "THE PROVOST", tier = 24, sprite = "em_provost", family = "boss", size = 2, resist = { "mind" }, weak = { "bolt" },
    boss = { hpx = share, phases = {
      { at = 100, moves = { { "em_talon", 5 }, { "em_hush", 2 } }, every = 5, big = "em_qed" },
      { at = 66, moves = { { "em_talon", 4 }, { "em_hiss", 3 } }, every = 4, big = "em_qed", say = "THE CHAMBER LEANS IN", speedUp = 1, call = "em_class", summon = "em_owlet" },
      { at = 33, moves = { { "em_talon", 3 }, { "em_hiss", 3 }, { "em_hush", 2 } }, every = 3, big = "em_qed", say = "SHE IS NEARLY DONE", speedUp = 1, call = "em_class", summon = "em_owlet" },
    } },
  }
end
F.em_b_provost = theProvost(1)
F.em_b_provost_kind = theProvost(0.8) -- the chamber is with you: an honest speech takes a fifth off her

F.em_b_sleeper = {
  name = "THE FIRST SLEEPER", short = "FIRST SLEEPER", tier = 25, sprite = "em_kess", family = "boss", size = 2, weak = { "bolt" },
  boss = { hpx = 0.84, phases = {
    { at = 100, moves = { { "em_beam", 5 }, { "em_lull", 2 } }, every = 5, big = "em_sweep" },
    { at = 60, moves = { { "em_beam", 4 }, { "em_lull", 3 } }, every = 4, big = "em_sweep", say = "THE LENS TURNS FASTER", speedUp = 1, call = "em_moths", summon = "em_moth" },
    { at = 30, moves = { { "em_beam", 5 }, { "em_lull", 3 } }, every = 3, big = "em_sweep", say = "ALL FIVE CHAIRS WAKE", speedUp = 1, call = "em_moths", summon = "em_moth" },
  } },
}

F.em_b_doctor = {
  name = "THE WARD DOCTOR", short = "THE DOCTOR", tier = 25, sprite = "doctor", family = "boss", size = 1,
  boss = { hpx = 0.64, phases = {
    { at = 100, moves = { { "em_scalpel", 4 }, { "draught", 2 }, { "em_stitch", 2 } }, every = 5, big = "em_dose" },
    { at = 50, moves = { { "em_scalpel", 4 }, { "em_kind", 3 }, { "em_stitch", 2 } }, every = 4, big = "em_dose", say = "THERE IS NO NEED TO BE AFRAID", speedUp = 1 },
  } },
}

local E = R.encounters
E.em_e_wall1 = { foes = { "em_wall_crawler", "em_wall_crawler", "em_wall_crawler" }, flee = true, bg = "cave" }
E.em_e_wall2 = { foes = { "em_wool", "em_wall_crawler" }, flee = true, bg = "cave" }
E.em_e_wall3 = { foes = { "em_walled", "em_wool" }, flee = true, bg = "cave" }
E.em_boss_breath = { foes = { "em_b_breath" }, flee = false, bg = "cave", boss = true }
E.em_f_1 = { foes = { "em_owlbeast" }, flee = true, bg = "grass" }
E.em_f_2 = { foes = { "em_owlet", "em_owlet", "em_owlet" }, flee = true, bg = "grass" }
E.em_f_3 = { foes = { "em_owlbeast", "em_owlet" }, flee = true, bg = "grass" }
E.em_e_stack1 = { foes = { "em_bookworm", "em_bookworm" }, flee = true, bg = "marble" }
E.em_e_stack2 = { foes = { "em_folio", "em_bookworm" }, flee = true, bg = "marble" }
E.em_e_stack3 = { foes = { "em_invigilator" }, flee = true, bg = "marble" }
E.em_e_stack4 = { foes = { "em_owlbeast", "em_folio" }, flee = true, bg = "marble" }
E.em_e_ult1 = { foes = { "em_invigilator", "em_folio" }, flee = true, bg = "marble" }
E.em_boss_provost = { foes = { "em_b_provost" }, flee = false, bg = "marble", boss = true }
E.em_boss_provost_kind = { foes = { "em_b_provost_kind" }, flee = false, bg = "marble", boss = true }
E.em_e_light1 = { foes = { "em_moth", "em_moth", "em_moth" }, flee = true, bg = "ruin" }
E.em_e_light2 = { foes = { "em_shard" }, flee = true, bg = "ruin" }
E.em_e_light3 = { foes = { "em_shard", "em_moth" }, flee = true, bg = "ruin" }
E.em_boss_sleeper = { foes = { "em_b_sleeper" }, flee = false, bg = "dream", boss = true }
E.em_e_guards = { foes = { "em_field_orderly", "em_field_orderly", "em_field_doctor" }, flee = false, bg = "ruin" }
E.em_boss_doctor = { foes = { "em_b_doctor", "em_field_orderly", "em_field_orderly" }, flee = false, bg = "town", boss = true }

R.field.owlundia = { "em_f_1", "em_f_2", "em_f_3" }

-- ---------------------------------------------------------------- the art

R.art = {
  em_wool = "A drift of grey dream-fog standing up like a sheep with no head, thick as wool, lime at the edges.",
  em_breath = "A huge pale chest grown into a wall of stone, ribs and folds of soft grey skin drawing in, old helmets and crawlers stuck in it.",
  em_owlet = "A knee-high fluffy owl chick with a beak too big for it and a very hungry look.",
  em_owlbeast = "A bear-sized owl on thick arms, feathers matted, round yellow eyes that seem to be marking you out of ten.",
  em_bookworm = "A long pale grub with a mouth full of paper teeth, bits of print along its sides.",
  em_folio = "A swirl of loose book pages holding the shape of a robed reader, with no one in it.",
  em_invigilator = "A white stone statue of an examiner in gown and square cap, holding a long ruler.",
  em_moth = "A hand-sized white moth with crystal dust on its wings.",
  em_shard = "A sleeper in a nightshirt, half grown over with pale crystal, walking with eyes shut.",
  em_provost = "A vast owl beast in the rags of an academic robe, wings like a barn roof, a gold chain of office sunk in the feathers of its neck.",
  em_kess = "A Magister in a tall chair bolt upright, eyes wide, crystal running up his throat, a great lens behind him with moths in the beam.",
  em_lamp = "Map sprite only: a hooded iron lamp, or a shutter of coloured glass, on a post.",
  em_grille = "Map sprite only: a low iron grille or gate, closing a passage.",
}

-- ---------------------------------------------------------------- the people

local L = R.looks
L.em_satchel = { like = "n_satchel" }
L.em_tawn = { kind = "owlin", tall = 0.84, build = "stout", cut = "robe", coat = "panel", trim = "hi", hat = "circlet", hatInk = "line", wear = { "chain" }, carry = "keys", back = "blueTint" }
L.em_hob = { kind = "owlin", tall = 0.7, build = "thin", cut = "tunic", coat = "hiTint", trim = "warn", hat = "pot", hatInk = "line", hatTrim = "text", carry = "spear", back = "tie" }
L.em_perigee = { kind = "old", tall = 0.8, build = "thin", cut = "robe", coat = "accent", trim = "hi", hat = "pointy", hatInk = "blueTint", hatTrim = "hi", beard = "belted", beardInk = "text", wear = { "sash" }, sashInk = "hi", carry = "bell", eyes = "tired", mouth = "open", back = "blueTint" }
L.em_pellet = { kind = "owlin", tall = 0.66, build = "hunched", cut = "robe", coat = "bg", trim = "line", skin = "line", eyes = "specs", wear = { "chain" }, carry = "ledger", back = "panel" }
L.em_pellet_aside = { like = "em_pellet" }
L.em_oswin = { kind = "human", tall = 0.8, build = "stout", cut = "coat", coat = "redTint", trim = "tie", hair = "tufts", hairInk = "line", wear = { "apron" }, apronInk = "warn", carry = "book", eyes = "narrow", mouth = "smile", mark = "ink", back = "hiTint" }
L.em_hesper = { kind = "human", tall = 0.9, build = "thin", cut = "coat", coat = "text", trim = "line", skin = "warn", hat = "circlet", hatInk = "line", hair = "bun", hairInk = "bg", carry = "clipboard", eyes = "tired", mouth = "line", back = "tie" }
L.em_tuppence = { kind = "owlin", tall = 0.42, build = "stout", cut = "tunic", coat = "warn", trim = "text", skin = "line", carry = "book", back = "blueTint" }
L.em_marl = { kind = "old", tall = 0.78, build = "broad", cut = "dress", coat = "tie", trim = "text", hat = "scarf", hatInk = "red", hatTrim = "text", wear = { "apron" }, carry = "ladle", mouth = "frown", back = "redTint" }
L.em_dagny = { kind = "human", tall = 0.92, build = "normal", cut = "dress", coat = "red", trim = "redTint", hat = "feather", hatInk = "accent", hatTrim = "text", hair = "curls", hairInk = "text", eyes = "narrow", mouth = "smile", wear = { "necklace" }, back = "accent" }
L.em_provost = { kind = "owlin", tall = 1, build = "broad", cut = "robe", coat = "accent", trim = "hi", skin = "line", blight = true, wear = { "chain" }, back = "redTint" }
L.em_dole = { kind = "human", tall = 0.96, build = "gaunt", cut = "coat", coat = "tie", trim = "line", skin = "text", hair = "short", hairInk = "line", hat = "circlet", hatInk = "line", carry = "pen", eyes = "tired", mouth = "line", back = "tie" }
L.em_gannet = { kind = "old", tall = 0.8, build = "stout", cut = "coat", coat = "blueTint", trim = "hi", hat = "tricorn", hatInk = "blue", hatTrim = "hi", beard = "chops", beardInk = "text", carry = "lantern", mouth = "open", back = "blueTint" }
L.em_sorrel = { kind = "gnome", tall = 0.52, build = "stout", cut = "tunic", coat = "accent", trim = "info", hat = "goggles", hatInk = "info", hatTrim = "bg", hair = "wild", hairInk = "soft", carry = "orb", eyes = "wide", mouth = "smile", back = "blueTint" }
L.em_kess = { kind = "human", tall = 0.95, build = "gaunt", cut = "robe", coat = "blueTint", trim = "info", skin = "line", blight = true, hair = "wild", hairInk = "text", eyes = "wide", mouth = "open", back = "bg" }
L.em_tyto = { kind = "owlin", tall = 0.68, build = "hunched", cut = "dress", coat = "text", trim = "line", skin = "line", hat = "scarf", hatInk = "text", hatTrim = "line", wear = { "apron" }, apronInk = "line", carry = "pillow", back = "hiTint" }
L.em_w_orderly = { like = "gateman" }
L.em_dreambook = thing("ledger")
L.em_wall_log = thing("ledger")
L.em_catalogue = thing("drawer")
L.em_lectern = thing("book")
L.em_carrel_desk = thing("book")
L.em_chair = thing("book")
L.em_study = thing("book")
L.em_desk = thing("tome")
L.em_keeper_log = thing("ledger")
L.em_cradle = thing("doll")
L.em_kess_chair = thing("book")
for _, id in ipairs({ "em_bed_nan", "em_bed_1", "em_bed_2", "em_bed_3", "em_bed_4", "em_bed_5", "em_bed_6", "em_bed_nine" }) do
  L[id] = { like = "w_bed" }
end

R.names = {
  ["WARDEN TAWN"] = "em_tawn", HOB = "em_hob", ["LORD PERIGEE"] = "em_perigee", ["MISTRESS PELLET"] = "em_pellet", ["BINDER EDRIC"] = "em_oswin",
  THIMBLE = "em_tuppence", MARL = "em_marl", ["DOCTOR LINDE"] = "em_hesper", ["DAGNY, SECOND HISS"] = "em_dagny",
  ["THE PROVOST"] = "em_provost", ["PROCTOR DOLE"] = "em_dole", ["PILOT GANNET"] = "em_gannet", BURDOCK = "em_sorrel",
  ["MAGISTER KESS"] = "em_kess", ["MATRON TYTO"] = "em_tyto",
}

-- ---------------------------------------------------------------- the story guide

R.goals = {
  { done = "em_wall_seen", text = "Go to the crack in the wall", site = "crack_east", when = "wm_done" },
  { done = "em_circlets", text = "Find circlets at Scythebreak", map = "em_scythebreak", x = 17, y = 3, when = "wm_done" },
  { done = "em_lamps", text = "Light the old lamps", map = "em_crack_2", x = 21, y = 3, when = "wm_done" },
  { done = "em_breath_down", text = "End what's in the crack", map = "em_crack_2", x = 13, y = 7, when = "wm_done" },
  { done = "em_through", text = "Climb out into Owlundia", map = "em_crack_1", x = 11, y = 9, when = "wm_done" },
  { done = "em_ag_seen", text = "Reach Agoshull", site = "agoshull", when = "wm_done" },
  { done = "em_warden_told", text = "Find Warden Tawn", map = "em_agoshull", x = 6, y = 3, when = "wm_done" },
  { done = "em_ticket_got", text = "See Lord Perigee", map = "em_agoshull", x = 8, y = 16, when = "wm_done" },
  { done = "em_past_desk", text = "Show Pellet the ticket", map = "em_agoshull", x = 3, y = 10, when = "wm_done" },
  { done = "em_lift_open", text = "Work the book lift", map = "em_stacks_1", x = 4, y = 16, when = "wm_done" },
  { done = "em_carrel", text = "Find the scholar's carrel", map = "em_stacks_2", x = 12, y = 5, when = "wm_done" },
  { done = "em_provost_down", text = "Take the stage", map = "em_ultimatum", x = 14, y = 8, when = "wm_done" },
  { done = "em_proof", text = "Take the Proof to the Warden", map = "em_agoshull", x = 6, y = 3, when = "wm_done" },
  { done = "em_evr_seen", text = "Go to Evrastin", site = "evrastin", when = "wm_done" },
  { done = "em_dole_met", text = "Find Proctor Dole", map = "em_evrastin", x = 7, y = 10, when = "wm_done" },
  { done = "em_lens_lit", text = "Light the tower in order", map = "em_light_1", x = 12, y = 6, when = "wm_done" },
  { done = "em_light_out", text = "Put out the Light", map = "em_light_2", x = 11, y = 11, when = "wm_done" },
  { done = "em_guard_down", text = "Go to the Ward", map = "em_evrastin", x = 15, y = 12, when = "wm_done" },
  { done = "em_doc_down", text = "Face the doctor", map = "em_ward", x = 3, y = 5, when = "wm_done" },
  { done = "em_read", text = "Go to bed nine", map = "em_ward", x = 22, y = 3, when = "wm_done" },
}

return R
