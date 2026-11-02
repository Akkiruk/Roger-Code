-- regions/plexios.lua
-- Plexios, the land of Shaid: Blackpool, Killerth, Murkwell and Adaphis, draft for the author to edit. Plain data and local helpers.
-- The chain of the region is paperwork, because Plexios is: the road to the capital needs a Well Paper, the one physician who'd
-- sign it is in the garrison at Murkwell, and nothing enters Murkwell but the hunters' meat. Inside Adaphis the body runs upward:
-- Pelvic, the Gutter under it, Ribbed and the Works, then the Cranial, the King, and last of all Colette.
-- It may run before or after Sindal: sn_done is read where it matters.

local say = require("games.blightmare.say")
local C = require("lib.arcade.ui").C

local t, ask, topic, person, line = say.t, say.ask, say.topic, say.person, say.line

local R = {
  id = "plexios", prefix = "px_",
  entry = { flags = { "finished", "hr_done" }, join = { "deserter", "cleric", "owlin" }, lvl = 12, site = "blackpool", map = "px_blackpool", x = 13, y = 17 },
  exit = "px_done",
  -- flags read here from the slice, and flags left for later regions and the author
  exports = {
    "heard_tobin", "spared_handlers", "held_handlers", "sn_crossed",
    "px_gave_blood", "px_refused_blood", "px_matron_lamp",
  },
  sites = {
    blackpool = { mx = 13, my = 17, dir = 1 },
    killerth = { mx = 12, my = 16, dir = 1 },
    murkwell = { mx = 13, my = 16, dir = 1 },
    adaphis = { mx = 14, my = 18, dir = 1 },
  },
  maps = {}, scripts = {}, shops = {}, goals = {},
  foes = {}, abilities = {}, encounters = {}, field = {},
  looks = {}, names = {}, art = {},
}

local S = R.scripts

local WORLD = { blackpool = { 97, 39 }, killerth = { 86, 26 }, murkwell = { 72, 30 }, adaphis = { 104, 28 } }

-- The party. The hero mostly speaks through choices.
local D, K, O = line("deserter"), line("cleric"), line("owlin")

--- Someone new: a look of their own, the name over their talk box, and a voice to write them in. The id is also their npc id.
local function who(id, name, look)
  R.looks[id] = look
  R.names[name] = id
  return person(id, name)
end

-- Colette and Fabian have core portrait ids. If the artist has not drawn those, these names carry the looks below.
local colette = person("colette", "DOCTOR COLETTE")
local fabian = person("fabian", "KING FABIAN")
R.looks.px_colette = { kind = "half-elf", tall = 0.95, build = "thin", cut = "robe", coat = C.line, trim = C.text, hair = "bun", hairInk = C.bg, eyes = "tired", mouth = "line", skin = C.text, carry = "book", back = C.redTint }
R.looks.px_fabian = { kind = "old", tall = 0.62, build = "hunched", lean = 0.16, cut = "robe", coat = C.accent, trim = C.hi, hat = "pointy", hatInk = C.hi, hatTrim = C.accent, hatSmall = 0.8, hair = "tufts", hairInk = C.text, beard = "long", beardInk = C.text, skin = C.line, wear = { "cape" }, capeInk = C.red, eyes = "wide", mouth = "open", back = C.bg }
R.names["DOCTOR COLETTE"] = "px_colette"
R.names["KING FABIAN"] = "px_fabian"

-- ---------------------------------------------------------------- Blackpool

local quill = who("px_quill", "INSPECTOR QUILL", { kind = "clinic", tall = 0.86, build = "thin", cut = "coat", coat = C.tie, trim = C.line, hat = "visor", hatInk = C.bg, hatTrim = C.text, beak = 0.06, carry = "clipboard", wear = { "badge" } })
local hobb = who("px_hobb", "MISTRESS SCALD", { kind = "human", tall = 0.92, build = "broad", cut = "dress", coat = C.blueTint, trim = C.text, hair = "bun", hairInk = C.line, wear = { "apron" }, carry = "laundry", mouth = "line", eyes = "narrow", back = C.blueTint })
local nell = who("px_nell", "CRAB NELL", { kind = "old", tall = 0.8, build = "stout", cut = "dress", coat = C.red, trim = C.redTint, hat = "scarf", hatInk = C.info, hatTrim = C.text, carry = "bucket", mouth = "smile", wear = { "apron" }, apronInk = C.tie, back = C.blueTint })
local holt = who("px_holt", "HOLT", { kind = "human", tall = 0.9, build = "thin", cut = "tunic", coat = C.blueTint, trim = C.text, legs = C.tie, hat = "cap", hatInk = C.blue, hatTrim = C.bg, beard = "whiskers", beardInk = C.line, eyes = "tired", mouth = "open", skin = C.line, carry = "pole", back = C.blueTint })
local tuppence = who("px_tuppence", "TUPPENCE", { kind = "child", tall = 0.46, build = "thin", cut = "tunic", coat = C.tie, trim = C.panel, wear = { "patches", "strap" }, hair = "wild", hairInk = C.redTint, carry = "tray", eyes = "shifty", mouth = "smile", back = C.tie })
local teasel = who("px_teasel", "MR TEASEL", { kind = "old", tall = 0.78, build = "hunched", lean = 0.1, cut = "coat", coat = C.panel, trim = C.tie, hat = "bowler", hatInk = C.tie, hatTrim = C.bg, hair = "short", hairInk = C.text, carry = "cane", eyes = "tired", mouth = "smile", skin = C.line, back = C.hiTint })
local tiller = who("px_tiller", "TILLER THE CHANDLER", { kind = "human", tall = 0.88, build = "stout", cut = "tunic", coat = C.hiTint, trim = C.tie, hat = "feather", hatInk = C.ok, hatTrim = C.hi, beard = "goatee", beardInk = C.redTint, wear = { "apron" }, carry = "ledger", eyes = "narrow", back = C.hiTint })
local bess = who("px_bess", "BESS GANT", { kind = "human", tall = 0.84, build = "normal", cut = "dress", coat = C.hiTint, trim = C.redTint, hat = "scarf", hatInk = C.line, hatTrim = C.tie, carry = "kettle", eyes = "tired", mouth = "frown", back = C.hiTint })
local handler = person("villager", "CASK HANDLER")

R.maps.px_blackpool = {
  name = "BLACKPOOL", theme = "town", savepoint = true,
  rows = {
    "############>############",
    "#hhhhhhhhhh...hhhhhh~~~~#",
    "#h...h....h...h....h~~~~#",
    "#h...h....h...h....h~~~~#",
    "#hh+hhhh+hh...hh+hhh~~~~#",
    "#.......................#",
    "#.......................#",
    "#.hhh+hh.......hh+hhh...#",
    "#.h....h.......h....h.~~#",
    "#.h....h.......h....h.~~#",
    "#.hhhhhh.......hhhhhh.~~#",
    "#.....................~~#",
    "#.......hhhh.hhhh......~#",
    "#WWWWWWWWWWW.WWWWWWWWWWW#",
    "#WWWWWWWWWWW.WWWWWWWWWWW#",
    "#WWWWWWWWWWW.WWWWWWWWWWW#",
    "#WWWWWWWWWWW.WWWWWWWWWWW#",
    "############>############",
  },
  npcs = {
    { id = "px_quill", x = 12, y = 12, sprite = "orderly", script = "px_talk_quill" },
    { id = "px_hobb", x = 8, y = 3, sprite = "villager", script = "px_talk_hobb" },
    { id = "px_nell", x = 23, y = 7, sprite = "villager", script = "px_talk_nell" },
    { id = "px_holt", x = 22, y = 12, sprite = "villager", script = "px_talk_holt" },
    { id = "px_tuppence", x = 10, y = 7, sprite = "child", script = "px_talk_tuppence" },
    { id = "px_teasel", x = 19, y = 10, sprite = "villager", script = "px_talk_teasel" },
    { id = "px_tiller", x = 17, y = 3, sprite = "villager", script = "px_talk_tiller" },
    { id = "px_bess", x = 5, y = 9, sprite = "villager", script = "px_talk_bess" },
    { id = "px_bp_board", x = 3, y = 12, sprite = "px_board", script = "px_read_bp_board" },
  },
  steps = {
    { x = 13, y = 15, script = "px_bp_arrive", unless = "px_arrived" },
  },
  chests = {
    { id = "c1", x = 3, y = 3, give = "tonic", n = 1 },
    { id = "c2", x = 17, y = 10, gold = 120 },
  },
  exits = {
    { x = 13, y = 1, world = WORLD.blackpool },
    { x = 13, y = 18, world = WORLD.blackpool },
  },
}

R.shops.px_bp_tiller = { tier = 3 }

S.px_bp_arrive = {
  t("The Nevermore Portal is black iron, ninety feet to the lintel, and it stands open by the width of one thin person. Everyone goes through sideways. That's the point of it."),
  t("Across the inner face, in letters as tall as a house: THE WELL PASS. THE SICK WAIT."),
  quill("Next. Stand on the mark, tongue out, say 'Plexios'. Thank you. Papers."),
  ask(quill("'Two barley factors of Hayford, and a patient in their care.' I count four and no barley. The sick wait, so which of you is the patient?"), {
    { "The sister. She got better. It was a miracle.", {
      K("A very small one, Inspector. Nothing anyone could hang me for."),
      quill("Recovered. I'll note that down. We get so few."),
    } },
    { "The owl. It always looks like that.", {
      O("I shall remember that, {hero}, in a footnote."),
      quill("It's upright and it's not coughing. There's no regulation against a bad colour."),
    } },
  }),
  quill("Blackpool only, mind. The road north to Adaphis is for the Well, and for that you want a Well Paper, signed by a Clinic physician. I'm not a physician. I'm a man with a stamp."),
  K("Something from the throne of Plexios, the Vulture said. She didn't say how one gets within a day's walk of it."),
  D("I know one physician who'd sign and not ask. Doctor Nye, at Murkwell. She's in the mud there because she once asked a question in front of people."),
  O("All that's let in at Murkwell's gate is meat, from the hunters of Killerth. I read it on a crate."),
  D("Then we go west, and ask how a person gets to be meat."),
  { when = "sn_done", steps = {
    K("They cough here. Did you notice? After all those smiles, I find it almost friendly."),
  } },
  { set = "px_arrived" },
}

S.px_read_bp_board = {
  t("A board of notices. WELL PAPERS ARE FREE TO THE WELL. COUGHING IS A COURTESY OWED TO OTHERS: PLEASE DO IT INDOORS."),
  t("Under that, freshly pasted: WANTED FOR QUESTIONS. A TALL PERSON OF NO DREAMS. The drawing could be anyone. It's rather a good likeness of the doctor."),
  D("That's very unfair. I've a much better chin."),
}

S.px_talk_quill = {
  ask(quill("Tongue's fine. Have you a query? Queries are free. It's the answers that go on your record."), {
    topic("What happens to the ones you stop?", {
      quill("They wait. There's a room, off the square. I don't know what for, and I don't believe they do either. Nobody's complained, which I take as a good sign."),
    }),
    { "Back to your stamp, Inspector.", {
      quill("It's a good stamp. It has never once looked me in the eye."),
    } },
  }),
}

S.px_talk_hobb = {
  ask(hobb("The Last Clean Bed. It's a true sign, I boil them myself. Thirty gold, paid before you lie down, and if you cough in the night you'll cough into the pillow, like a citizen."), {
    { "A bed, please.", {
      { inn = 30 },
    } },
    { "Not tonight.", {
      hobb("Suit yourself. There's only worse beds from here to the sea."),
    } },
  }),
}

S.px_talk_nell = {
  ask(nell("Crab or calamari? The crab's fresh, I get them under the pier. Lovely and fat this year. It's where the capital's water comes out, you see."), {
    topic("What does the capital's water have in it?", {
      nell("Whatever they've finished with. My husband used to ask questions like that. Very thin man. Eat your crab."),
    }),
    { "No crab for me, thank you.", {
      nell("Suit yourself, dear. They're not fussy what they eat, either."),
    } },
  }),
}

S.px_talk_holt = {
  t("A long thin man is mending a net and singing, very loudly. Whenever a long note comes up, he turns his head and coughs into it."),
  ask(holt("Haul away the, hrrrk, silver, boys! Don't look at me like that. There's an inspector forty paces off, and this song's got a verse for every day till spring."), {
    { "Your secret's safe with me.", {
      K("Steam, with the head covered, morning and night. It won't save you. It'll give you the top notes back."),
      holt("Whoever taught you that wants hanging, miss. Thank you."),
    } },
    { "Sing up, then. He's looking.", {
      holt("HAUL away the, hrrrk..."),
    } },
  }),
}

S.px_talk_tuppence = {
  ask(tuppence("Clean spit! Five gold the bottle, passed by a real inspector! Tip it under your tongue before the mark and you'll go through like a duke. It's my own, so I know where it's been."), {
    topic("Does that work?", {
      tuppence("Nobody who bought one's ever come back to complain. Mind, nobody who bought one's ever come back."),
    }),
    { "That's disgusting. Five gold, you say?", {
      { paid = 5, steps = {
        t("It's a very small bottle, and it's warm."),
        tuppence("Keep it out of the sun. It goes off."),
        { set = "px_bought_spit" },
      }, other = {
        tuppence("You're as poor as you look."),
      } },
    } },
    { "Keep your spit.", {
      tuppence("I will. It's appreciating."),
    } },
  }),
}

S.px_talk_teasel = {
  t("A bare room with a bench around three walls. The people on the bench don't look up. An old man at the end of it raises his hat."),
  teasel("Do sit. I'm number three. I've been number three for six years, and they've been very good about it. I started at ninety."),
  ask(teasel("I'd a touch of something in the chest, and the gentleman said to wait. So I'm waiting. It's coming along nicely."), {
    topic("Who are numbers one and two?", {
      teasel("Mrs Abney and Mr Coyle. They've not said much lately. The orderly comes on Fridays and tidies them, and I expect I'll move up."),
    }),
    { "I hope it comes soon, Mr Teasel.", {
      teasel("That's kind. Mind the bench. It's been sat on by some very patient people."),
    } },
  }),
}

S.px_talk_tiller = {
  ask(tiller("Rope, tar, potions, and anything that's fallen off the Adaphis boat. Gold only. I don't take passes or promises."), {
    { "Show me what you've got.", {
      { shop = "px_bp_tiller" },
    } },
    { "Nothing today.", {} },
  }),
}

S.px_talk_bess = {
  { when = "spared_handlers", steps = {
    { when = "px_handler_paid", steps = {
      bess("He does the school run now. He's terrible at it. There's always tea."),
    }, other = {
      t("A big man in a clean shirt sits with two small girls climbing on him. He sees you, and the colour goes out of him, and slowly comes back."),
      handler("It's you, from the second level. Bess, this is them. Go home, they said, and I went."),
      bess("I don't know what he did down there, and he wakes up saying it. But you sent him home to me. Take this. It's the Clinic's, so I don't feel a thing."),
      { give = "ether", n = 2 },
      { set = "px_handler_paid" },
    } },
  }, other = {
    { when = "held_handlers", steps = {
      bess("My husband's held in some gnome town, for a thing with casks. He says they gave him a chair, and it's the first time in years he's slept. I don't know what to tell the girls."),
    }, other = {
      bess("Is there word from the Heart? My husband took a job for a polite gentleman, hooking up casks in a mine. He said three weeks. That was a while ago."),
    } },
  } },
}

-- ---------------------------------------------------------------- Killerth

local kest = who("px_kest", "WARDEN KEST", { kind = "human", tall = 0.94, build = "broad", cut = "coat", coat = C.tie, trim = C.panel, hat = "wide", hatInk = C.panel, hatTrim = C.red, hair = "plaits", hairInk = C.text, wear = { "strap", "belt" }, carry = "spear", eyes = "narrow", mouth = "line", mark = "scar", back = C.panel })
local tallow = who("px_tallow", "MARGE SUET", { kind = "human", tall = 0.86, build = "stout", cut = "dress", coat = C.redTint, trim = C.tie, hair = "curls", hairInk = C.red, wear = { "apron" }, apronInk = C.line, carry = "ladle", mouth = "smile", back = C.redTint })
local orla = who("px_orla", "ORLA THE FLETCHER", { kind = "human", tall = 0.88, build = "thin", cut = "tunic", coat = C.ok, trim = C.tie, legs = C.tie, hat = "feather", hatInk = C.ok, hatTrim = C.warn, hair = "long", hairInk = C.bg, carry = "feather", eyes = "narrow", back = C.hiTint })
local mount = who("px_mount", "MASTER MOUNT", { kind = "human", tall = 0.8, build = "stout", cut = "coat", coat = C.hiTint, trim = C.hi, hair = "tufts", hairInk = C.warn, beard = "chops", beardInk = C.warn, eyes = "specs", wear = { "apron", "waistcoat" }, carry = "pen", mouth = "open", back = C.tie })
local brack = who("px_brack", "BRACK", { kind = "human", tall = 0.97, build = "broad", cut = "tunic", coat = C.tie, trim = C.bg, legs = C.bg, hat = "cap", hatInk = C.bg, hatTrim = C.tie, beard = "stubble", beardInk = C.bg, carry = "spear", mouth = "frown", back = C.panel })

R.maps.px_killerth = {
  name = "KILLERTH", theme = "town", savepoint = true,
  rows = {
    "###########>###########",
    "#hhhhhhhhhh.hhhhhhhhhh#",
    "#h.....h.......h.....h#",
    "#h.....h.......h.....h#",
    "#hhh+hhh.......hhh+hhh#",
    "#.....................#",
    "#.....................#",
    "#hhhh+hh.......hh+hhhh#",
    "#h.....h.......h.....h#",
    "#h.....h.......h.....h#",
    "#hhhhhhh.......hhhhhhh#",
    "#.....................#",
    "#.....................#",
    "#hhhhhhhhhh...hhhhhhhh#",
    "#hhhhhhhhhh...hhhhhhhh#",
    "#hhhhhhhhhh...hhhhhhhh#",
    "###########>###########",
  },
  npcs = {
    { id = "px_kest", x = 5, y = 3, sprite = "villager", script = "px_talk_kest" },
    { id = "px_tallow", x = 19, y = 3, sprite = "villager", script = "px_talk_tallow" },
    { id = "px_orla", x = 5, y = 9, sprite = "villager", script = "px_talk_orla" },
    { id = "px_mount", x = 19, y = 9, sprite = "villager", script = "px_talk_mount" },
    { id = "px_brack", x = 12, y = 2, sprite = "soldier", script = "px_talk_brack", unless = "px_ki_job" },
  },
  steps = {
    { x = 12, y = 16, script = "px_ki_arrive", unless = "px_ki_in" },
  },
  chests = {
    { id = "c1", x = 3, y = 3, give = "potion", n = 3 },
    { id = "c2", x = 21, y = 10, gold = 90 },
  },
  exits = {
    { x = 12, y = 17, world = WORLD.killerth },
    { x = 12, y = 1, map = "px_sending_1", mx = 13, my = 17, dir = 1 },
  },
}

R.shops.px_ki_orla = { tier = 3 }

S.px_ki_arrive = {
  t("Killerth smells of smoke and wet dog. There's a hide nailed to every wall, and over the gate a board with the season's count in chalk. Some of the things on it have legs. Some have boots."),
  D("Shaid's where the old kingdoms sent their sick, friend, for a thousand years, and nobody came to fetch them back. These people are paid by the head for what became of them."),
  K("The Warden's hall is top left, under the antlers."),
  { set = "px_ki_in" },
}

S.px_talk_kest = {
  { when = "px_tally", steps = {
    ask(kest("Your tally's good at any gate that eats. My four sleep with the lamp on and won't say why. Is there something else?"), {
      topic("What do they say here about the purge?", {
        kest("Hollodin Adaphis came with fire and saved us all, and there's a statue. I've heard about that cellar now. I'll keep hunting. I'll stop looking at the statue."),
      }),
      { "That's all, Warden.", {} },
    }),
  }, other = {
    { when = "px_matron_down", steps = {
      t("Warden Kest looks at the four hunters behind you, pink and rested and blinking. She looks for some time."),
      kest("I sent a dozen after them, and they came back with a limp. You come back with the lost ones, and they've had their hair combed. I'm not going to ask."),
      kest("Here's a tally, burned with my mark. Murkwell's gate takes that and doesn't look at who's holding it. You'd be a side of venison, as far as the Clinic's concerned. And this, for the hunters."),
      { gold = 400 },
      { give = "hunters_eye" },
      { set = "px_tally" },
    }, other = {
      { when = "px_ki_job", steps = {
        kest("The Sending House, up the trail. Brack's opened it. Bring me the four, or what they had on them."),
      }, other = {
        ask(kest("Warden Kest. Murkwell's gate takes nothing but my wagon, and my wagon stays home until the Sending House is quiet. Something up there's taking hunters alive. Four since harvest."), {
          topic("What is the Sending House?", {
            kest("The old hospice in the hills, where three kingdoms sent their sick and left them. Founder Adaphis cleaned it out with fire. Now something's put the lamps back on."),
          }),
          topic("Taken alive?", {
            kest("No blood, no drag marks. Their boots left by the door, side by side. A hunter doesn't take his boots off for anything."),
          }),
          { "We'll go up and see.", {
            kest("Then Brack will open the trail. Bring back my people and I'll put you on the wagon myself. If it gets you, leave your boots where I can find them."),
            { set = "px_ki_job" },
          } },
        }),
      } },
    } },
  } },
}

S.px_talk_tallow = {
  ask(tallow("The Stuck Pig! Stew's on, and I'd not ask what's in it, but it was running at noon. Twenty-five a head for a bed that's mostly dog."), {
    { "A bed, please.", {
      { inn = 25 },
    } },
    { "Just looking, thank you.", {
      tallow("The dog's name is Warden. Don't tell her."),
    } },
  }),
}

S.px_talk_orla = {
  ask(orla("Arrows I make, potions I buy off the boat, and the rest I took from people who didn't finish the season. No returns."), {
    { "Show me.", {
      { shop = "px_ki_orla" },
    } },
    { "No, thank you.", {} },
  }),
}

S.px_talk_mount = {
  t("The room is full of stuffed animals. Every one of them looks as if it has just been told something very surprising."),
  ask(mount("Master Mount, Taxidermist. That's a stag. I've never seen a live one, I work from descriptions. I'm told the eyes are close together. That one has four. It came in with four."), {
    { "It's very lifelike.", {
      mount("You're the first who's said so! The last gentleman was sick in that bucket."),
    } },
    { "Why does that bear have a waistcoat?", {
      mount("That's not a bear. Well, it's mostly a bear. Don't look at the hands, I've had complaints."),
    } },
  }),
}

S.px_talk_brack = {
  brack("Trail's shut. Warden's orders, and she's got the antlers, so it's her say. Top left. Don't touch the antlers."),
}

-- ---------------------------------------------------------------- the Sending House

local matron = who("px_matron", "THE HOUSE MATRON", { kind = "human", tall = 1, build = "thin", lean = 0.08, cut = "dress", coat = C.bg, trim = C.text, skin = C.line, hat = "scarf", hatInk = C.text, hatTrim = C.line, wear = { "apron" }, apronInk = C.text, carry = "lantern", eyes = "red", mouth = "teeth", ears = "long", back = C.bg })

R.looks.px_bed_a = { kind = "human", pose = "lying", bed = true, coat = C.text, trim = C.line, hair = "short", hairInk = C.bg, beard = "stubble", beardInk = C.bg }
R.looks.px_bed_b = { kind = "human", pose = "lying", bed = true, coat = C.text, trim = C.line, hair = "long", hairInk = C.redTint, flip = true }
R.looks.px_bed_c = { kind = "old", pose = "lying", bed = true, coat = C.text, trim = C.line, hair = "tufts", hairInk = C.text, beard = "whiskers", beardInk = C.text }
R.looks.px_bed_d = { kind = "human", pose = "lying", bed = true, coat = C.text, trim = C.line, hair = "plaits", hairInk = C.tie, flip = true }

R.maps.px_sending_1 = {
  name = "THE SENDING HOUSE", theme = "ruin",
  rows = {
    "#########################",
    "#.....h.....h.....h.....#",
    "#.....h.....h.....h.....#",
    "#.....h.....h.....h.....#",
    "#hh+hhhhh+hhhhh+hhhhh+hh#",
    "#.......................#",
    "#.hhhhhhhhhhhhhhhhhhhhh.#",
    "#.h.......h...h.......h.#",
    "#.h.......h.>.h.......h.#",
    "#.+.......h...h.......+.#",
    "#.h.......h...h.......h.#",
    "#.h.......h...h.......h.#",
    "#.hhhhhhhhhh.hhhhhhhhhh.#",
    "#.......................#",
    "#hhhhhhh.~~~.~~~hhhhhhhh#",
    "#########~~~.~~~#########",
    "#########~~~.~~~#########",
    "############>############",
  },
  npcs = {
    { id = "px_lamp_1", x = 3, y = 2, sprite = "px_lamp", script = "px_lamp_north", unless = "px_lamp_a" },
    { id = "px_lamp_2", x = 5, y = 11, sprite = "px_lamp", script = "px_lamp_west", unless = "px_lamp_b" },
    { id = "px_lamp_3", x = 21, y = 8, sprite = "px_lamp", script = "px_lamp_east", unless = "px_lamp_c" },
    { id = "px_lit_1", x = 3, y = 2, sprite = "px_lamp_lit", script = "px_lamp_lit", when = "px_lamp_a" },
    { id = "px_lit_2", x = 5, y = 11, sprite = "px_lamp_lit", script = "px_lamp_lit", when = "px_lamp_b" },
    { id = "px_lit_3", x = 21, y = 8, sprite = "px_lamp_lit", script = "px_lamp_lit", when = "px_lamp_c" },
    { id = "px_register", x = 10, y = 2, sprite = "px_ledger", script = "px_read_register" },
    { id = "px_bell", x = 9, y = 15, sprite = "px_bell", script = "px_read_bell" },
    { id = "px_court_door", x = 13, y = 13, sprite = "px_grate", script = "px_try_court", unless = "px_lamps" },
  },
  steps = {
    { x = 13, y = 15, script = "px_sending_in", once = true },
  },
  chests = {
    { id = "c1", x = 18, y = 2, give = "hide_coat" },
    { id = "c2", x = 24, y = 3, give = "potion", n = 3 },
    { id = "c3", x = 9, y = 8, gold = 150 },
    { id = "c4", x = 17, y = 11, give = "linen_alb" },
  },
  foes = {
    { id = "f1", x = 6, y = 14, enc = "px_house_bats", sprite = "px_bat" },
    { id = "f2", x = 20, y = 14, enc = "px_house_beds", sprite = "blighted" },
    { id = "f3", x = 2, y = 9, enc = "px_house_bats", sprite = "px_bat" },
    { id = "f4", x = 7, y = 9, enc = "px_house_beds", sprite = "blighted" },
    { id = "f5", x = 13, y = 6, enc = "px_house_were", sprite = "px_werebat" },
    { id = "f6", x = 19, y = 10, enc = "px_house_were", sprite = "px_werebat" },
    { id = "f7", x = 22, y = 2, enc = "px_house_beds", sprite = "blighted" },
  },
  exits = {
    { x = 13, y = 18, map = "px_killerth", mx = 12, my = 2, dir = 3 },
    { x = 13, y = 9, map = "px_sending_2", mx = 3, my = 2, dir = 2 },
  },
}

R.maps.px_sending_2 = {
  name = "THE SENDING HOUSE: BELOW", theme = "ruin",
  rows = {
    "#####################",
    "#>......#...........#",
    "###.###.#.#########.#",
    "###.###.#.#.......#.#",
    "#.....#...#.......#.#",
    "#.....#####.......#.#",
    "#.....#.#.+.......#.#",
    "###.###.#.#.......#.#",
    "###.....#.#########.#",
    "#######.#...........#",
    "#.....#.#########.###",
    "#.....+...........###",
    "#.....###############",
    "#####################",
    "#####################",
  },
  npcs = {
    { id = "px_order", x = 4, y = 6, sprite = "px_board", script = "px_read_order" },
    { id = "px_burnt", x = 3, y = 12, sprite = "shroud", script = "px_read_burnt" },
    { id = "px_matron", x = 15, y = 6, sprite = "px_matron", script = "px_boss_matron", unless = "px_matron_down" },
    { id = "px_bed_a", x = 13, y = 4, sprite = "shroud", script = "px_talk_beds", unless = "px_matron_down" },
    { id = "px_bed_b", x = 17, y = 4, sprite = "shroud", script = "px_talk_beds", unless = "px_matron_down" },
    { id = "px_bed_c", x = 13, y = 8, sprite = "shroud", script = "px_talk_beds", unless = "px_matron_down" },
    { id = "px_bed_d", x = 17, y = 8, sprite = "shroud", script = "px_talk_beds", unless = "px_matron_down" },
  },
  steps = {
    { x = 12, y = 7, script = "px_boss_matron", unless = "px_matron_down" },
  },
  chests = {
    { id = "c1", x = 8, y = 7, give = "tonic", n = 2 },
    { id = "c2", x = 5, y = 13, gold = 180 },
    { id = "c3", x = 15, y = 8, give = "falchion" },
  },
  foes = {
    { id = "f1", x = 6, y = 2, enc = "px_house_bats", sprite = "px_bat" },
    { id = "f2", x = 3, y = 5, enc = "px_house_beds", sprite = "blighted" },
    { id = "f3", x = 12, y = 12, enc = "px_house_were", sprite = "px_werebat" },
    { id = "f4", x = 20, y = 5, enc = "px_house_were", sprite = "px_werebat" },
    { id = "f5", x = 15, y = 10, enc = "px_house_bats", sprite = "px_bat" },
  },
  exits = {
    { x = 2, y = 2, map = "px_sending_1", mx = 12, my = 9, dir = 3 },
    { x = 18, y = 8, map = "px_killerth", mx = 12, my = 3, dir = 3, when = "px_matron_down" },
  },
}

S.px_sending_in = {
  t("A long, low house on a bare hill. The causeway to its door crosses ground burned so hard that nothing has grown back. The roof has gone in places, but the floors are swept."),
  O("A house for a thousand years of the unwanted, and by the door a bell with felt on the clapper, so as not to trouble the family."),
  K("I'd like to say something for them. I'm told that's illegal. Remind me to do it anyway."),
}

S.px_read_bell = {
  t("The felt has worn through to the wood where hands have rung it. Beside it, cut into the stone: NOBODY IS SENT. THEY ARE ONLY SEEN OFF."),
}

S.px_read_register = {
  t("The register of the House, in one round hand. The last lines read: MATRON DOES NOT FEEL THE COLD NOW. MATRON DOES NOT EAT. NO MATTER. FORTY-ONE IN THE WARDS AND THE DOCTOR HAS NOT COME."),
  D("There's always one who stays when the money's gone. I've just never had to wonder what happens if you let them go on staying."),
}

local function lamp(text, flag)
  return {
    t(text),
    { set = flag },
    { all = { "px_lamp_a", "px_lamp_b", "px_lamp_c" }, steps = {
      t("The third lamp takes. Somewhere in the middle of the House, a bolt slides back on its own, slowly, like someone getting out of a chair."),
      { set = "px_lamps" },
    } },
  }
end

S.px_lamp_north = lamp("A ward lamp on a stone shelf, filled, trimmed and ready. You'd have expected dust. You light it, and twelve empty beds come up out of the dark, every blanket squared.", "px_lamp_a")
S.px_lamp_west = lamp("The lamp of the west ward. There's fresh oil in it. Each bed has a small pair of felt shoes under it, set side by side. You light it, and try not to count.", "px_lamp_b")
S.px_lamp_east = lamp("The lamp of the east ward, the children's, by the size of the beds. You light it. There are scratches on the wall at about the height of your knee: someone was keeping a tally of days.", "px_lamp_c")
S.px_lamp_lit = { t("The lamp burns very steadily. You have the feeling that it's pleased with you.") }

S.px_try_court = {
  t("An iron grate across the way to the inner court, and a brass plate: NO PATIENT LEFT IN THE DARK. WHEN THE THREE WARDS ARE LIT THE DOOR WILL BE OPENED."),
  { count = { "px_lamp_a", "px_lamp_b", "px_lamp_c" }, at = 1, steps = {
    O("It's counting. I find I don't care for a building that counts."),
  } },
}

S.px_read_order = {
  t("Cut into the wall with a chisel and all the time in the world: BY HOLLODIN ADAPHIS. THE SICK OF THIS HOUSE ARE TO BE DELIVERED OF THEIR SICKNESS. LET NONE GO OUT."),
  O("Every child in Embia learns that he cleansed Shaid. It's on the coins. It takes a particular sort of mind to write 'delivered'."),
}

S.px_read_burnt = {
  t("The doors down here are barred on the outside. In this last cell there are forty-one soft dark shapes on the stone, left by the fire. Each has been covered with a folded blanket. The blankets are new."),
  { when = "px_matron_down", steps = {
    K("She came down and tucked them in. Every night."),
  }, other = {
    K("Someone comes down and tucks them in."),
  } },
  { fade = true },
  t("The sister stays a while. Nobody mentions what is and isn't legal."),
}

S.px_talk_beds = {
  t("A hunter lies in a clean bed with their hair combed, breathing slowly, a neat dressing on the inside of one arm. A pair of felt shoes stands under the bed, side by side."),
}

S.px_boss_matron = {
  t("Four beds, four sleeping hunters and one lamp. Something very tall and thin in a white apron is bent over the nearest bed, doing something gentle to the blanket."),
  matron("Visitors are the second Sunday. You've let the cold in, and you've tracked Shaid all over my floor."),
  t("She turns. The cap is starched. The face under it is a bat's, or was a woman's."),
  ask(matron("You're not well. Look at you, worn to the bone. Into bed, all of you. A little something from the arm, for the doctor, and you'll sleep. He's coming. He's only been delayed."), {
    { "Nobody's coming. Let them go.", {} },
    { "The doctor isn't coming, Matron. It's over.", {
      D("I'm a doctor. You've done very well, Matron. You can go off shift now."),
      matron("Oh, you're not him. You're much too thin."),
    } },
  }),
  matron("No patient leaves before Doctor's round."),
  { battle = "px_boss_matron" },
  t("She folds onto the floor all at once, as a sheet does. Her hand goes out, feeling for the lamp, and doesn't quite reach it."),
  ask(K("Someone ought to leave that lit."), {
    { "Set the lamp by her hand.", {
      t("Her fingers close on the handle and stay there. The sister ties a thread around them, and says the words out loud, in the Clinic's own country."),
      { set = "px_matron_lamp" },
    } },
    { "Leave it. Wake the hunters.", {
      K("Very well. I'll say the words anyway."),
    } },
  }),
  t("The hunters wake one by one, looking better than they have in years. There's a way out by the orderlies' stair, in the corner."),
  { set = "px_matron_down" },
}

R.abilities.px_bedrest = { name = "BED REST", mp = 4, power = 35, magic = true, status = "sleep", chance = 60 }
R.abilities.px_draw = { name = "FROM THE ARM", power = 105 }
R.abilities.px_round = { name = "THE NIGHT ROUND", power = 170, magic = true, target = "all", windup = 34, warn = "SHE TAKES UP THE LAMP" }

R.foes.px_gaunt_bat = { name = "GAUNT BAT", tier = 12, shape = "small", sprite = "px_bat", family = "harpy", abilities = { { "bite", 3 }, { "shriek", 1 } }, weak = { "fire" } }
R.foes.px_bedridden = { name = "BEDRIDDEN", tier = 13, shape = "tank", sprite = "blighted", family = "blighted", abilities = { { "claw", 3 }, { "retch", 2 }, { "touch", 1 } } }
R.foes.px_werebat = { name = "WEREBAT", tier = 14, shape = "quick", sprite = "px_werebat", family = "harpy", abilities = { { "claw", 3 }, { "lunge", 1 }, { "bite", 2 } }, weak = { "fire" } }
R.foes.px_matron = {
  name = "THE HOUSE MATRON", tier = 14, shape = "caster", sprite = "px_matron", family = "boss", immune = { sleep = true },
  abilities = { { "px_draw", 1 } },
  boss = { hpx = 1, phases = {
    { at = 100, moves = { { "px_draw", 3 }, { "px_bedrest", 1 } }, every = 5, big = "px_round" },
    { at = 50, moves = { { "px_draw", 2 }, { "px_bedrest", 2 }, { "shriek", 1 } }, every = 4, big = "px_round", say = "NO PATIENT LEAVES", speedUp = 1 },
  } },
}

R.encounters.px_house_bats = { foes = { "px_gaunt_bat", "px_gaunt_bat", "px_gaunt_bat" }, flee = true, bg = "ruin" }
R.encounters.px_house_beds = { foes = { "px_bedridden", "px_gaunt_bat" }, flee = true, bg = "ruin" }
R.encounters.px_house_were = { foes = { "px_werebat", "px_bedridden" }, flee = true, bg = "ruin" }
R.encounters.px_boss_matron = { foes = { "px_matron" }, flee = false, bg = "ruin", boss = true }

R.art.px_bat = "A starved, leathery bat the size of a cat, all ribs and ears, hanging its head."
R.art.px_werebat = "A man-tall thing, half bat and half what it used to be, in the rags of a patient's gown."
R.art.px_matron = "A very tall, thin woman with a bat's face in a starched cap and white apron, holding a lamp out in front of her."
R.art.px_lamp = "An unlit ward lamp on a stone shelf."
R.art.px_lamp_lit = "The same lamp, burning very steadily."
R.art.px_board = "A notice board or inscribed slab on a post, for reading."
R.art.px_ledger = "A thick open book on a stand."
R.art.px_bell = "A small bell hung in a stone niche, with a felt clapper."
R.art.px_grate = "An iron grate or sluice gate filling a corridor."

-- ---------------------------------------------------------------- Murkwell

local pell = who("px_pell", "DOCTOR NYE", { kind = "human", tall = 0.88, build = "stout", cut = "coat", coat = C.text, trim = C.tie, legs = C.tie, hair = "short", hairInk = C.text, eyes = "specs", mouth = "line", wear = { "apron" }, apronInk = C.redTint, carry = "bowl", oneShoe = true, back = C.redTint })
local ormond = who("px_ormond", "CAPTAIN ORMOND", { kind = "clinic", tall = 0.96, build = "normal", coat = C.tie, trim = C.hi, hat = "peaked", hatInk = C.bg, hatTrim = C.hi, beak = 0.05, wear = { "epaulettes", "badge" }, carry = "scroll", back = C.panel })
local loam = who("px_loam", "QUARTERMASTER DUNN", { kind = "human", tall = 0.82, build = "stout", cut = "tunic", coat = C.panel, trim = C.tie, hat = "cap", hatInk = C.tie, hatTrim = C.bg, hair = "short", hairInk = C.tie, carry = "list", eyes = "shifty", wear = { "belt" }, back = C.panel })
local dampier = who("px_dampier", "CORPORAL DAMPIER", { kind = "human", tall = 0.88, build = "thin", cut = "tunic", coat = C.blueTint, trim = C.tie, hat = "nightcap", hatInk = C.blueTint, hatTrim = C.text, beard = "stubble", carry = "pillow", eyes = "tired", mouth = "frown", back = C.blueTint })
local mire = who("px_mire", "PRIVATE MIRE", { kind = "human", tall = 0.56, build = "normal", cut = "tunic", coat = C.tie, trim = C.panel, hat = "sallet", hatInk = C.line, hatTrim = C.tie, carry = "spear", eyes = "wide", mouth = "line", back = C.tie })
local sallow = who("px_sallow", "PRIVATE SALLOW", { kind = "old", tall = 0.84, build = "hunched", cut = "coat", coat = C.tie, trim = C.bg, hat = "sallet", hatInk = C.tie, hatTrim = C.bg, hair = "long", hairInk = C.text, beard = "long", beardInk = C.text, carry = "spear", eyes = "wide", skin = C.line, back = C.bg })
local sentry = who("px_mu_sentry", "PUMPHOUSE SENTRY", { kind = "clinic", tall = 0.9, build = "normal", cut = "tunic", coat = C.tie, trim = C.panel, hat = "sallet", hatInk = C.line, hatTrim = C.red, beak = 0.05, carry = "spear", back = C.panel })

R.looks.px_fever_a = { kind = "human", pose = "lying", bed = true, coat = C.tie, trim = C.panel, hair = "short", hairInk = C.redTint, skin = C.line, thread = true }
R.looks.px_fever_b = { kind = "human", pose = "lying", bed = true, coat = C.tie, trim = C.panel, hair = "short", hairInk = C.bg, beard = "moustache", beardInk = C.bg, skin = C.line, flip = true }

R.maps.px_murkwell = {
  name = "MURKWELL", theme = "town", savepoint = true,
  rows = {
    "#########################",
    "#WWWWWWWWWWWWWWWWWWWWWWW#",
    "#~~~~~~~~~~~.~~~~~~~~~~~#",
    "#~hhhhh~~~~~.~~~~~hhhhh~#",
    "#~h...h~~~...~~~~~h...h~#",
    "#~h...+...........+...h~#",
    "#~h...h~~~~~.~~~~~h...h~#",
    "#~hhhhh~~~~~.~~~~~hhhhh~#",
    "#~~~~~~~~~.....~~~~~~~~~#",
    "#~hhhhhhh~~~.~~~hhhhhhh~#",
    "#~h.....h~~~.~~~h.....h~#",
    "#~h.....+.......+....>h~#",
    "#~h.....h~~~.~~~h.....h~#",
    "#~hhhhhhh~~~.~~~hhhhhhh~#",
    "#~~~~~~~~~~~.~~~~~~~~~~~#",
    "#~~~~~~~~~~~.~~~~~~~~~~~#",
    "############>############",
  },
  npcs = {
    { id = "px_ormond", x = 13, y = 3, sprite = "captain", script = "px_talk_ormond" },
    { id = "px_mire", x = 11, y = 9, sprite = "soldier", script = "px_talk_mire" },
    { id = "px_loam", x = 5, y = 6, sprite = "villager", script = "px_talk_loam" },
    { id = "px_dampier", x = 21, y = 6, sprite = "villager", script = "px_talk_dampier" },
    { id = "px_pell", x = 6, y = 11, sprite = "villager", script = "px_talk_pell" },
    { id = "px_fever_a", x = 4, y = 13, sprite = "shroud", script = "px_talk_fever" },
    { id = "px_fever_b", x = 8, y = 13, sprite = "shroud", script = "px_talk_fever" },
    { id = "px_mu_sentry", x = 18, y = 12, sprite = "soldier", script = "px_talk_mu_sentry", unless = "px_pell_job" },
  },
  steps = {
    { x = 13, y = 16, script = "px_mu_turned", unless = "px_tally" },
    { x = 13, y = 16, script = "px_mu_arrive", when = "px_tally", unless = "px_mu_in" },
  },
  chests = {
    { id = "c1", x = 4, y = 5, give = "antidote", n = 3 },
    { id = "c2", x = 22, y = 5, give = "potion", n = 2 },
    { id = "c3", x = 22, y = 13, gold = 140 },
  },
  exits = {
    { x = 13, y = 17, world = WORLD.murkwell },
    { x = 22, y = 12, map = "px_sump", mx = 3, my = 8, dir = 2 },
  },
}

R.shops.px_mu_loam = { tier = 3 }

S.px_mu_turned = {
  t("The road ends in a gate of tarred logs. The sentries look at your hands, to see if you're holding meat."),
  D("Nothing goes in but the hunters' wagon, friend. We'll want the Warden's tally from Killerth."),
  { world = WORLD.murkwell },
}

S.px_mu_arrive = {
  t("The sentry sniffs the Warden's tally and waves you in behind a cart of smoked tusker. You are now, for official purposes, venison."),
  t("Murkwell stands in mud the way a tooth stands in a gum. The streets are planks. Past the last houses a wall crosses the only gap in the mountains wide enough for an army, and beyond its shut gate is Sindal."),
  D("Nye runs the fever ward, bottom left. Stay on the boards. There's a helmet out there that's been sinking since I was a student."),
  { set = "px_mu_in" },
}

S.px_talk_ormond = {
  t("Beyond him, the Sindal gate. Forty guns stand under tarpaulins along the wall, all new."),
  { when = "sn_done", steps = {
    ormond("You've the look of someone who's been over that wall. Everyone comes back looking so well. It's the most frightening thing I know."),
  }, other = {
    ormond("That's Sindal. Clean roads, full bellies, and not a complaint in eight hundred years. I'd give a good deal to see one person over there lose their temper."),
  } },
  ask(ormond("We're under a ceasefire, and I'm told I should be pleased."), {
    topic("Why so many new guns, then?", {
      ormond("I asked once, in writing. The answer was forty more. King Fabian doesn't want a war, and they keep arriving with Doctor Colette's seal on the crate."),
    }),
    { "Just stretching my legs, Captain.", {
      ormond("Stretch them on the boards."),
    } },
  }),
}

S.px_talk_mire = {
  t("A young soldier stands in the mud beside the boards, sunk to the waist, at attention."),
  ask(mire("Sir! Private Mire, sir! Corporal Dampier told me to hold this position till relieved, sir! That was Tuesday! Sergeant says I'm not getting shorter, it's the angle!"), {
    { "You're relieved, Private. Get out of there.", {
      { when = "px_mire_out", steps = {
        mire("Thank you, sir! I've thought it over, sir, and I'd rather stay. It's the only post I've got."),
      }, other = {
        t("It takes the whole party, and the mud gives him up with a noise like a very rude old man. He looks at where his boots went, and goes back in to his knees, on principle."),
        mire("Permission to resume the position, sir? I've already started. I don't know what else I'd do."),
        { set = "px_mire_out" },
      } },
    } },
    { "As you were, Private.", {
      mire("Sir! That's the nicest thing anyone's said all week!"),
    } },
  }),
}

S.px_talk_loam = {
  ask(loam("Stores. You want something, you sign for it. The medicine crates are empty, before you ask. They stop off in the Cranial, where the need is greater."), {
    { "Let's see the stores.", {
      { shop = "px_mu_loam" },
    } },
    { "Never mind.", {} },
  }),
}

S.px_talk_dampier = {
  ask(dampier("The Dry Bunk. It's not. Twenty gold for a hammock, and I'll wake you when the floor goes under."), {
    { "A hammock, then.", {
      { inn = 20 },
    } },
    { "Have you left a man standing in the mud?", {
      dampier("Have I? Oh, lord. Is that Tuesday's? Don't tell him. It's the first order he's ever understood."),
    } },
  }),
}

S.px_talk_mu_sentry = {
  sentry("Pumphouse is closed. That's the way down to the Sump, and the order is nobody goes down without a physician's say. Go and ask Doctor Nye. She's got no other friends."),
}

S.px_talk_fever = {
  t("A soldier on a cot, soaked through and shaking. The hour is written on the wall above each bed, in charcoal, all in the same hand."),
  { when = "px_paper", steps = {
    K("The fever's broken in this one. Sit a moment, would you? They come back better for a voice."),
  } },
}

S.px_talk_pell = {
  { when = "px_paper", steps = {
    pell("The ward's cooling. Six since this morning. I'm writing it all down, in triplicate, with the seal on the front. Go on. Go and be somebody's problem."),
  }, other = {
    { when = "px_found_cask", steps = {
      t("The doctor sets the stencilled bung on the table and says nothing. Nye turns it over, and takes off her spectacles."),
      pell("That's our lot number. My own lads, in a trial, and I've been keeping their notes for them."),
      t("She sits for a moment with both hands flat on the table. Then she takes a sheet of the good paper, and writes very fast and very hard."),
      pell("One Well Paper, four bearers, sound in wind and limb. I've never told a lie on a form in my life. It's easier than I'd been led to believe. It'll take you through Pelvic gate and no further. Don't come back. I mean that as a friend."),
      { set = "px_paper" },
    }, other = {
      { when = "px_pell_job", steps = {
        pell("The Sump's through the pumphouse, bottom right. Three old sluices and a lot of leeches. Go on. I've got nine more to turn."),
      }, other = {
        t("A long tin ward, very hot. A stout woman with one boot on, and no time to find the other, is turning a soldier on his cot with one practised heave."),
        pell("If that's bad news, put it on the pile. Oh. It's you. I heard you'd gone off with a spoon."),
        D("It was a very good spoon. Nye, I need a Well Paper. Four names, and I can't tell you why."),
        ask(pell("Of course you do. I've fifty-one men with a fever, and it started at the pump. Find what's fouled my water, and I'll sign anything you like."), {
          topic("How did you end up here?", {
            pell("I asked the Surgeon-General, at a dinner, what happens to a transfer. There's a lovely silence you get in Adaphis. The next morning I got a promotion and a pair of boots."),
            D("She asked, friend. The rest of us just walked beside the carts."),
            pell("Don't make me out to be anything. I asked once. Then I took the boots."),
          }),
          { "We'll go down to the Sump.", {
            pell("Good. Tell the sentry I said so. If you meet anyone down there called Sallow, be kind. He's on the pay book, and I've no idea if he's real."),
            { set = "px_pell_job" },
          } },
        }),
      } },
    } },
  } },
}

-- ---------------------------------------------------------------- the Sump

R.maps.px_sump = {
  name = "THE MURKWELL SUMP", theme = "swamp",
  rows = {
    "######################",
    "#.....+............###",
    "#.....############.###",
    "#.....##########.....#",
    "####.###########.....#",
    "####.###########.....#",
    "####.#################",
    "#>..................##",
    "####.##############.##",
    "####.##############.##",
    "#.....########.......#",
    "#.....########.......#",
    "#.....########.......#",
    "######################",
    "######################",
  },
  npcs = {
    { id = "px_wheel_1", x = 2, y = 2, sprite = "px_wheel", script = "px_sluice_one", unless = "px_sluice_a" },
    { id = "px_wheel_2", x = 2, y = 12, sprite = "px_wheel", script = "px_sluice_two", unless = "px_sluice_b" },
    { id = "px_wheel_3", x = 21, y = 5, sprite = "px_wheel", script = "px_sluice_three", unless = "px_sluice_c" },
    { id = "px_sallow", x = 4, y = 12, sprite = "villager", script = "px_talk_sallow" },
    { id = "px_flood", x = 13, y = 8, sprite = "px_grate", script = "px_try_flood", unless = "px_drained" },
    { id = "px_cask", x = 21, y = 12, sprite = "px_cask", script = "px_read_cask", unless = "px_found_cask" },
  },
  steps = {
    { x = 4, y = 8, script = "px_sump_in", once = true },
  },
  chests = {
    { id = "c1", x = 6, y = 4, give = "potion", n = 3 },
    { id = "c2", x = 6, y = 12, give = "chainmail" },
    { id = "c3", x = 17, y = 4, gold = 160 },
    { id = "c4", x = 15, y = 12, give = "ash_rod" },
  },
  foes = {
    { id = "f1", x = 8, y = 8, enc = "px_sump_leech", sprite = "px_leech" },
    { id = "f2", x = 5, y = 6, enc = "px_sump_leech", sprite = "px_leech" },
    { id = "f3", x = 12, y = 2, enc = "px_sump_mixed", sprite = "px_hulk" },
    { id = "f4", x = 19, y = 5, enc = "px_sump_leech", sprite = "px_leech" },
    { id = "f5", x = 17, y = 8, enc = "px_sump_mixed", sprite = "px_hulk" },
    { id = "f6", x = 18, y = 12, enc = "px_sump_guard", sprite = "px_hulk" },
  },
  exits = {
    { x = 2, y = 8, map = "px_murkwell", mx = 21, my = 12, dir = 4 },
  },
}

S.px_sump_in = {
  t("The culvert under Murkwell is older than the wall. Black water fills the main run ahead, and the air tastes of pennies."),
  O("Three sluice wheels, if the pumphouse drawing is honest. The flood won't drop until all three are turned."),
  D("There's something sweet under the iron. Friend, tell me you can smell that."),
}

local function sluice(text, flag)
  return {
    t(text),
    { set = flag },
    { all = { "px_sluice_a", "px_sluice_b", "px_sluice_c" }, steps = {
      t("Far off, something gives. The whole culvert groans, the water in the main run shudders, and it starts going down with a long, long swallow."),
      { set = "px_drained" },
    } },
  }
end

S.px_sluice_one = sluice("A great rusted wheel. It takes two of you, and it goes round with a scream that goes on down the pipes for some time.", "px_sluice_a")
S.px_sluice_two = sluice("The second wheel has been kept greased, by someone, with something. It turns almost at a touch.", "px_sluice_b")
S.px_sluice_three = sluice("The far wheel is furred with leech eggs. It takes your whole weight to shift. Behind the wall, a long way down, something heavy starts to drain.", "px_sluice_c")

S.px_try_flood = {
  t("The main run is drowned to the roof here, black and quite still. A stencilled board floats against the iron. You can't get through."),
  { count = { "px_sluice_a", "px_sluice_b", "px_sluice_c" }, at = 1, steps = {
    t("The waterline has dropped a hand's width. There are more wheels to turn."),
  } },
}

S.px_talk_sallow = {
  t("A very old man in a very old helmet sits bolt upright on a crate. He leaps to his feet when he sees you, and most of him arrives."),
  ask(sallow("Halt! Friend or Sindal! Oh, thank goodness. Is this the relief? Private Sallow, sir. Forty-one years on this post. I've kept the wheel greased, as ordered. Is the war going well?"), {
    topic("Has anyone come through?", {
      sallow("Three weeks back, sir. Beaks, with a cask on a sledge, up the far run. I challenged them. They said, 'Thank you, carry on.' Nobody's said that since Lieutenant Barrow."),
    }),
    { "The war's over, Private. You can go up.", {
      sallow("Is it? Who won? No, don't tell me, I'd hate to be disappointed. I'll just finish the watch, sir."),
    } },
    { "Good work, Private. Carry on.", {
      sallow("Sir! Thank you, carry on! It's very civil."),
    } },
  }),
}

S.px_read_cask = {
  t("A cask on a sledge, roped over the place where the Sump feeds the pumps. It's the same make as the ones in Orrenshire, and a slip is pasted under the bung."),
  D("'Murkwell, garrison water. Trial four. Must reach the sleeping. Record onset. Record spread across the gate.' 'Do not treat.' She underlined it again."),
  O("Across the gate, toward Sindal, with the mud and the wind. This is not a test of the disease. It's a test of the road."),
  K("Those are her own soldiers up there."),
  D("Yes, sister. They're very well placed. Help me with this. I'd like to take the bung back to a friend."),
  t("You stave in the cask and let it run away down the drain. The doctor stands looking at the wet stones rather longer than the job requires."),
  { set = "px_found_cask" },
}

R.foes.px_mud_leech = { name = "SUMP LEECH", tier = 14, shape = "small", sprite = "px_leech", family = "bug", abilities = { { "bite", 3 }, { "spit", 1 } }, weak = { "fire" } }
R.foes.px_hulk = { name = "SILT HULK", tier = 15, shape = "tank", sprite = "px_hulk", family = "frog", abilities = { { "swing", 3 }, { "tongue", 1 } }, weak = { "ice" } }

R.encounters.px_sump_leech = { foes = { "px_mud_leech", "px_mud_leech", "px_mud_leech" }, flee = true, bg = "swamp" }
R.encounters.px_sump_mixed = { foes = { "px_hulk", "px_mud_leech" }, flee = true, bg = "swamp" }
R.encounters.px_sump_guard = { foes = { "px_hulk", "px_hulk" }, flee = true, bg = "swamp" }

R.art.px_leech = "A fat, grey leech as long as a bolster, rearing up on its tail, ringed mouth open."
R.art.px_hulk = "A heaped man-shape of black silt and old helmets, with a leech for one arm."
R.art.px_wheel = "A rusted iron sluice wheel on a post."
R.art.px_cask = "A Clinic cask on a sledge, roped upright, with a neat stencil, dripping."

-- ---------------------------------------------------------------- Adaphis: the Pelvic District

local stopes = who("px_stopes", "WARDEN STOPES", { kind = "clinic", tall = 0.94, build = "stout", cut = "coat", coat = C.tie, trim = C.panel, hat = "bowler", hatInk = C.bg, hatTrim = C.line, beak = 0.09, carry = "cane", wear = { "badge" } })
local fenn = who("px_fenn", "GOODMAN FENN", { kind = "human", tall = 0.98, build = "thin", cut = "coat", coat = C.bg, trim = C.panel, hat = "stovepipe", hatInk = C.bg, hatTrim = C.line, hair = "short", hairInk = C.text, carry = "shovel", eyes = "tired", mouth = "line", skin = C.line, back = C.tie })
local socket = who("px_socket", "MA SOCKET", { kind = "old", tall = 0.8, build = "broad", cut = "dress", coat = C.tie, trim = C.hi, hair = "bun", hairInk = C.text, wear = { "apron", "shawl" }, carry = "mug", mouth = "teeth", eyes = "wide", back = C.redTint })
local nance = who("px_nance", "RAG NANCE", { kind = "old", tall = 0.76, build = "hunched", cut = "dress", coat = C.panel, trim = C.tie, hat = "scarf", hatInk = C.redTint, hatTrim = C.tie, wear = { "patches", "shawl" }, carry = "laundry", eyes = "shifty", back = C.panel })
local lark = who("px_lark", "JOAN LARK", { kind = "human", tall = 0.88, build = "thin", cut = "dress", coat = C.hiTint, trim = C.tie, hair = "long", hairInk = C.tie, carry = "bowl", eyes = "tired", mouth = "frown", back = C.hiTint })
local tansy = who("px_tansy", "MISS TANSY", { kind = "human", tall = 0.9, build = "thin", cut = "dress", coat = C.line, trim = C.bg, hair = "bun", hairInk = C.bg, eyes = "specs", mouth = "line", carry = "chalk", wear = { "collar" }, back = C.blueTint })
local linnet = who("px_linnet", "LINNET", { kind = "child", tall = 0.5, build = "thin", cut = "tunic", coat = C.redTint, trim = C.tie, hair = "plaits", hairInk = C.redTint, carry = "crutch", eyes = "wide", mouth = "smile", back = C.tie })

R.maps.px_pelvic = {
  name = "ADAPHIS: PELVIC DISTRICT", theme = "city", savepoint = true,
  rows = {
    "##############>##############",
    "#hhhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#h....h.....h...h.....h....h#",
    "#h....h.....h...h.....h....h#",
    "#hh+hhhhh+hhh...hhh+hhhh+hhh#",
    "#...........................#",
    "#.............~.............#",
    "#.hhh+hhhhh...~...hhhhh+hhh.#",
    "#.h.......h...~...h.......h.#",
    "#.h.......h...~...h.......h.#",
    "#.hhhhhhhhh...~...hhhhhhhhh.#",
    "#.............~.............#",
    "#...........................#",
    "#.............~.............#",
    "#hhhhhhh+hhhh.~.hhhh+hhhhhhh#",
    "#h..........h.~.h..........h#",
    "#h..........h.~.h..........h#",
    "#hhhhhhhhhhhh.>.hhhhhhhhhhhh#",
    "#############>###############",
  },
  npcs = {
    { id = "px_stopes", x = 15, y = 2, sprite = "orderly", script = "px_talk_stopes", unless = "px_done" },
    { id = "px_socket", x = 10, y = 3, sprite = "villager", script = "px_talk_socket" },
    { id = "px_nance", x = 25, y = 3, sprite = "villager", script = "px_talk_nance" },
    { id = "px_fenn", x = 7, y = 9, sprite = "villager", script = "px_talk_fenn" },
    { id = "px_lark", x = 22, y = 9, sprite = "villager", script = "px_talk_lark" },
    { id = "px_tansy", x = 20, y = 17, sprite = "villager", script = "px_talk_tansy" },
    { id = "px_linnet", x = 18, y = 12, sprite = "child", script = "px_talk_linnet" },
  },
  steps = {
    { x = 14, y = 18, script = "px_pe_turned", unless = "px_paper" },
    { x = 14, y = 18, script = "px_pe_arrive", when = "px_paper", unless = "px_pe_in" },
  },
  chests = {
    { id = "c1", x = 3, y = 17, give = "potion", n = 3 },
    { id = "c2", x = 26, y = 17, gold = 200 },
  },
  exits = {
    { x = 14, y = 19, world = WORLD.adaphis },
    { x = 15, y = 1, map = "px_ribbed", mx = 15, my = 14, dir = 1 },
    { x = 15, y = 18, script = "px_drain_shut", unless = "px_gutter_ok" },
    { x = 15, y = 18, map = "px_gutter_1", mx = 13, my = 15, dir = 1, when = "px_gutter_ok" },
  },
}

R.shops.px_pe_nance = { tier = 3 }

S.px_pe_turned = {
  t("The South Gate of Adaphis is manned by masks, and nobody gets in without a Well Paper."),
  { when = "px_tally", steps = {
    D("Nye's our only chance of that paper, friend. We've got the Warden's tally. Murkwell, for Nye."),
  }, other = {
    D("Nye's our only chance of that paper, friend. Murkwell, for Nye. Killerth, for the wagon."),
  } },
  { world = WORLD.adaphis },
}

S.px_pe_arrive = {
  t("The mask at the South Gate looks at Doctor Nye's signature for a long time, then stamps it."),
  t("Adaphis lies along the coast with its spires up, like the ribs of something that crawled to the sea to die and was built on anyway. This is the hip of it, the lowest streets, where everything ends up. A trench runs down the middle of the road."),
  t("There are ten thousand people in earshot, all of them thin, and not one is coughing. It's like someone holding their breath in a cupboard."),
  K("Where are the sick? There ought to be sick on every step."),
  D("That's a very good question, sister. Up the hill is the Ribbed gate, and they won't pass us there. We'd better learn how people here get around things."),
  { set = "px_pe_in" },
}

S.px_talk_stopes = {
  ask(stopes("Ribbed Gate. A Pelvic paper won't do past this line. Breathe out. Thank you. You've a very clean chest. It's suspicious."), {
    topic("Is it true nobody's sick here?", {
      stopes("Adaphis is the healthiest city in Embia. There's been no reported illness in this district for eleven years. People have been very good about not reporting it."),
    }),
    topic("How else does a person get up there?", {
      stopes("Nobody comes through this gate on a whim. Though a great deal goes in and out of this city that doesn't trouble the gate. Pity about the smell."),
    }),
    { "Thank you, Warden.", {} },
  }),
}

S.px_drain_shut = {
  t("The trench drops into a brick mouth with a bar across it and a Clinic lock. The lock has been oiled lately."),
  O("Nobody oils a lock that isn't used. I wonder who in this district may carry things that no one will look at."),
}

S.px_talk_fenn = {
  { when = "px_gutter_ok", steps = {
    fenn("Mind how you go. Tell Mother Cray that Mr Harbottle is resting comfortably."),
  }, other = {
    t("A long room with four trestles and four shrouded shapes. A very thin undertaker is tying off a shroud with neat, sad little knots."),
    fenn("Goodman Fenn. Funerals, removals, condolences. I'm sorry for your loss. Whichever one it is. It saves time."),
    t("One of the shrouded shapes sneezes."),
    t("Nobody moves. The undertaker finishes his knot, and looks at the ceiling for a while."),
    fenn("Gas. The dead do a great deal of that sort of thing."),
    t('"Bless you," says the sister, without thinking. "Thank you," says the corpse, and then, after a moment, "Oh, bother."'),
    ask(fenn("I wonder if you'd care to tell me what it is you're going to do."), {
      { "We'd like to go where he's going.", {
        fenn("Would you, now. Yes, I saw that thread, sister. It's my trade to look at wrists."),
      } },
      { "Nothing. I didn't hear a thing.", {
        fenn("No. I don't believe you did. You might consider going the same way."),
      } },
    }),
    fenn("A dead man needs no paper, and the wardens don't care to lift the sheet. Here's the key to the drain, at the foot of the trench. The Gutter runs under the whole city, and Mother Cray takes them on from there. If you see anyone, you're dead, and I'm very sorry."),
    { set = "px_gutter_ok" },
  } },
}

S.px_talk_socket = {
  ask(socket("The Hip and Socket, and you can spare me the joke, love. Twenty-five a head. I've only had the one complaint, from a man who's since moved on."), {
    { "A bed, please.", {
      { inn = 25 },
    } },
    { "Not tonight, Ma.", {
      socket("Mind the step. We've had three go down it, and only one was drunk."),
    } },
  }),
}

S.px_talk_nance = {
  ask(nance("Everything here belonged to someone who's stopped needing it. Goodman Fenn always tells me when there's a pair of boots coming. Buying?"), {
    { "Show me.", {
      { shop = "px_pe_nance" },
    } },
    { "No, thank you.", {} },
  }),
}

S.px_talk_lark = {
  { when = "px_lark_met", steps = {
    lark("The mice are eating well, thank you. I'd be obliged if you'd go on not noticing."),
  }, other = {
    t("A bare room. A woman is spooning soup into a hole in the plaster, down near the floor. She stands up very fast, and gets in front of it."),
    ask(lark("Mice. We've mice. I feed them. Nobody here's been sick. Are you from the Register? Are you going to tell?"), {
      { "Who's behind the wall?", {
        lark("My dad. Four years. He built it himself, the week he started coughing, and I bricked up the last of it. One knock for yes. He only coughs when the carts go by."),
        lark("If they take him up the hill, they send a letter every spring to say he's doing well. I don't want a letter."),
      } },
      { "I saw mice. Lots of mice.", {
        t("She looks at you a long moment, and lets out a breath. From inside the wall, very softly, there comes one knock."),
      } },
    }),
    { set = "px_lark_met" },
  } },
}

S.px_talk_tansy = {
  t("Children and old people sit on benches. On the board: THE SWALLOW. THE TURN OF THE HEAD. THE FALSE LAUGH."),
  tansy("And again. Tickle comes up, we swallow, we smile, we look out of the window at something interesting. Very good, Mr Ames. Your shoulders told me, but your face was excellent."),
  { when = "px_bought_spit", steps = {
    tansy("You've a bottle in your pocket from Blackpool. I can smell it. That's soup, dear. It's always been soup."),
  } },
  ask(tansy("Miss Tansy's School of Deportment. This room buys five hundred people another year past the inspectors. Don't look at me like that. What do you teach?"), {
    topic("How long can someone hide it?", {
      tansy("Six years, my best, a laundress. She fell down dead at the Warden's own inspection, with a lovely smile on her face. I think of her very often."),
    }),
    { "Nothing as useful as this.", {
      tansy("No. Well, sit or leave. We've got the Sneeze at four."),
    } },
  }),
}

S.px_talk_linnet = {
  t("A small girl tucks her crutch behind her back and walks, perfectly straight, for eleven steps, smiling, with sweat on her lip. Then she stops and props herself on a wall."),
  ask(linnet("That's my record. It's only got to be till the Warden's past. Is it true there's a place where you can limp?"), {
    { "Yes. There are places you can limp.", {
      linnet("Huh. I'd be so good at it."),
    } },
    { "That was very well done.", {
      linnet("I know. I'm going to do twelve."),
    } },
  }),
}

-- ---------------------------------------------------------------- the Gutter

local cray = who("px_cray", "MOTHER CRAY", { kind = "old", tall = 0.84, build = "stout", cut = "robe", coat = C.tie, trim = C.panel, hat = "hood", hatInk = C.tie, hatTrim = C.panel, hair = "short", hairInk = C.text, carry = "lantern", eyes = "narrow", mouth = "line", wear = { "apron" }, apronInk = C.redTint, back = C.bg })
local harbottle = who("px_harbottle", "MR HARBOTTLE", { kind = "old", tall = 0.8, build = "stout", cut = "robe", coat = C.text, trim = C.line, hair = "tufts", hairInk = C.text, beard = "whiskers", beardInk = C.text, wear = { "gown" }, carry = "pillow", mouth = "smile", skin = C.line, back = C.bg })
local ivo = who("px_ivo", "IVO", { kind = "human", pose = "lying", coat = C.tie, trim = C.panel, hair = "short", hairInk = C.redTint, skin = C.line, sackInk = C.line, thread = true })

R.looks.px_gutter_sick = { kind = "old", pose = "lying", coat = C.panel, trim = C.tie, hair = "long", hairInk = C.text, sackInk = C.line, skin = C.line, thread = true, flip = true }

R.maps.px_gutter_1 = {
  name = "THE GUTTER", theme = "swamp",
  rows = {
    "#########################",
    "#...h.......>.......h...#",
    "#...h#####.~~~.#####h...#",
    "#...h#####.~~~.#####h...#",
    "#...h#####.~~~.#####h...#",
    "#...+......~~~......+...#",
    "#...h#####.~~~.#####h...#",
    "#...h#####.~~~.#####h...#",
    "#hhhh#####.....#####hhhh#",
    "#...h#####.~~~.#####h...#",
    "#...h##.##.~~~.#####h...#",
    "#...+......~~~......+...#",
    "#...h#####.~~~.#####h...#",
    "#...h#####.~~~.#####h...#",
    "#hhhh#####.....#####hhhh#",
    "##########..>..##########",
    "#########################",
  },
  npcs = {
    { id = "px_grate_w", x = 11, y = 3, sprite = "px_grate", script = "px_try_grate", unless = "px_gutter_grate" },
    { id = "px_grate_e", x = 15, y = 3, sprite = "px_grate", script = "px_try_grate", unless = "px_gutter_grate" },
    { id = "px_lever", x = 23, y = 12, sprite = "px_wheel", script = "px_gutter_lever", unless = "px_gutter_grate" },
    { id = "px_raven", x = 8, y = 11, sprite = "px_board", script = "px_read_raven" },
    { id = "px_bodycart", x = 3, y = 12, sprite = "shroud", script = "px_read_bodycart" },
  },
  steps = {
    { x = 13, y = 15, script = "px_gutter_in", once = true },
  },
  chests = {
    { id = "c1", x = 2, y = 2, give = "tonic", n = 2 },
    { id = "c2", x = 24, y = 2, gold = 220 },
    { id = "c3", x = 2, y = 14, give = "potion", n = 3 },
    { id = "c4", x = 24, y = 14, give = "bone_saw" },
  },
  foes = {
    { id = "f1", x = 11, y = 12, enc = "px_gut_rats", sprite = "rat" },
    { id = "f2", x = 15, y = 13, enc = "px_gut_leech", sprite = "px_leech" },
    { id = "f3", x = 8, y = 12, enc = "px_gut_bats", sprite = "px_bat" },
    { id = "f4", x = 18, y = 12, enc = "px_gut_fat", sprite = "px_fatleech" },
    { id = "f5", x = 11, y = 7, enc = "px_gut_fat", sprite = "px_fatleech" },
    { id = "f6", x = 18, y = 6, enc = "px_gut_bats", sprite = "px_bat" },
    { id = "f7", x = 3, y = 4, enc = "px_gut_leech", sprite = "px_leech" },
  },
  exits = {
    { x = 13, y = 16, map = "px_pelvic", mx = 14, my = 18, dir = 1 },
    { x = 13, y = 2, map = "px_gutter_2", mx = 9, my = 14, dir = 1 },
  },
}

R.maps.px_gutter_2 = {
  name = "THE GUTTER: THE SPINE DRAIN", theme = "swamp",
  rows = {
    "###########################",
    "####################>######",
    "####################.######",
    "#hhhhhhhhhh####...........#",
    "#h........h####.~~~~~~~~~.#",
    "#h........h####.~~~~~~~~~.#",
    "#h........+...+.~~~~~~~~~.#",
    "#h........h####.~~~~~~~~~.#",
    "#h........h####.~~~~~~~~~.#",
    "#h........h####...........#",
    "#hhhhhhh+hh################",
    "########.##################",
    "########.##################",
    "########.##################",
    "########>##################",
    "###########################",
  },
  npcs = {
    { id = "px_cray", x = 6, y = 6, sprite = "villager", script = "px_talk_cray" },
    { id = "px_harbottle", x = 3, y = 5, sprite = "villager", script = "px_talk_harbottle" },
    { id = "px_ivo", x = 9, y = 8, sprite = "shroud", script = "px_talk_ivo" },
    { id = "px_gutter_sick", x = 3, y = 9, sprite = "shroud", script = "px_talk_gutter_sick" },
    { id = "px_candle", x = 10, y = 9, sprite = "px_lamp_lit", script = "px_gutter_save" },
    { id = "px_alderman", x = 21, y = 3, sprite = "px_alderman", script = "px_boss_alderman", unless = "px_alderman_down" },
    { id = "px_shaft", x = 26, y = 7, sprite = "px_grate", script = "px_read_shaft" },
  },
  steps = {
    { x = 9, y = 10, script = "px_ward_in", unless = "px_ward_seen" },
    { x = 21, y = 4, script = "px_boss_alderman", unless = "px_alderman_down" },
  },
  chests = {
    { id = "c1", x = 26, y = 10, give = "saints_bone" },
    { id = "c2", x = 16, y = 4, give = "stiletto" },
  },
  foes = {
    { id = "f1", x = 13, y = 7, enc = "px_gut_rats", sprite = "rat" },
    { id = "f2", x = 16, y = 8, enc = "px_gut_fat", sprite = "px_fatleech" },
    { id = "f3", x = 22, y = 10, enc = "px_gut_leech", sprite = "px_leech" },
    { id = "f4", x = 24, y = 4, enc = "px_gut_fat", sprite = "px_fatleech" },
  },
  exits = {
    { x = 9, y = 15, map = "px_gutter_1", mx = 12, my = 2, dir = 3 },
    { x = 21, y = 2, map = "px_ribbed", mx = 14, my = 14, dir = 1 },
  },
}

S.px_gutter_in = {
  t("Below the street the trench opens into the true Gutter, a brick nave with all of Adaphis draining down a black channel in the middle. Through the gratings overhead, you can hear people not coughing."),
  O("There is a theory that a city can be read from its sewers. I withdraw my support for that theory."),
  D("The way on is the far end of the channel. Try not to breathe with your mouth."),
}

S.px_read_raven = {
  t("Scratched into the bricks, over and over, in a hundred different hands: a small bird with one wing."),
  K("That's not the Crown's raven. That's hers. Someone down here has been praying in the dark."),
}

S.px_read_bodycart = {
  t("A hand cart lies on its side, the shafts worn pale. In it, a pair of very small felt shoes, side by side, and a note in pencil: SHE WANTS TO COME BACK FOR THESE. PLEASE LEAVE."),
  t("You leave them."),
}

S.px_try_grate = {
  t("An iron grate, dropped across the walkway and rusted into place. The chain runs away along the wall and through the bricks, heading south and east. There's a lever at the other end of it, wherever that is."),
}

S.px_gutter_lever = {
  t("A chain-lever in a side cell, thick with grease and hung with old rags. The rags, when you look closely, are hospital gowns."),
  t("It takes three of you. Far up the channel there's a long iron shriek, and then the sound of a great many small things leaving in a hurry."),
  { set = "px_gutter_grate" },
}

S.px_ward_in = {
  t("A smell comes through the door and stops you dead. Soup. Boiled linen. Lamp oil."),
  t("Behind a brick bulkhead is a vault as long as a street, lit by candles in old bottles. On doors, on sacks, on heaps of rag, row after row, lie all the people who weren't coughing in Pelvic. Each has a cup beside them, and someone has been round to turn them."),
  cray("Fenn's sent more dead, has he? They're looking well on it. Shut that door, you're letting the Gutter in."),
  t("The sister has stopped in the doorway. Slowly she pulls back her sleeve, and for the first time since the Portal she takes out her thread in front of strangers."),
  K("Raven Queen, who notices. I'm late. I'm sorry. Here are some more."),
  t("Heads turn all the way down the vault. An old man starts, very quietly, to cry. By the time she's finished, there are hands out on every side."),
  { set = "px_ward_seen" },
}

S.px_gutter_save = {
  ask(K("Sit down, all of you, before you fall down. There's nothing here that's going to come for us tonight."), {
    { "Rest here.", {
      { heal = true },
      { save = true },
      t("Someone brings you soup. It's mostly water. It's the best thing you've ever eaten."),
    } },
    { "Not yet.", {} },
  }),
}

S.px_talk_cray = {
  { when = "px_alderman_down", steps = {
    { when = "px_rb_asked", steps = {
      { when = "px_drains_open", steps = {
        cray("The drains are ready. My people aren't strong, but there are a lot of them, and they know how to keep quiet."),
      }, other = {
        ask(cray("So Harrow wants my Gutter, for the rising. I've kept four hundred people out of the carts. What will she do for them, if it goes well?"), {
          { "They'll have the hospitals. That's the point.", {
            cray("That'll do. Tell her the drains are hers. Tell her I'm counting."),
            { set = "px_drains_open" },
          } },
          { "I can't promise anything, Mother.", {
            cray("That's the first honest thing anyone from up there's said to me. Tell her the drains are hers."),
            { set = "px_drains_open" },
          } },
        }),
      } },
    }, other = {
      cray("So the Alderman's dead. I've buried worse, with fewer people there. The way's clear to the Ribs. Off you go, before you start to look useful."),
    } },
  }, other = {
    { when = "px_cray_met", steps = {}, other = {
      cray("Mother Cray. I was head nurse at the Open Door, in the Cranial, before it shut. Now I'm the Crown's largest hospital, and nobody's told it."),
      { set = "px_cray_met" },
    } },
    ask(cray("The way up to the Ribs is east of here, and it's blocked."), {
      topic("Who are all these people?", {
        cray("Anyone who got to Fenn before the Register got to them. There's no medicine. There's turning them, and water, and someone knowing their name. You'd be surprised how far that goes. Then you'd be surprised how far it doesn't."),
      }),
      { "We'll clear the way. What's blocking it?", {
        cray("We call it the Alderman, because it takes a cut of everything that goes by. A leech, or it was, getting fat in the Spine Drain on what comes down from the hospitals. It took my last two runners."),
      } },
    }),
  } },
}

S.px_talk_harbottle = {
  ask(harbottle("You're the people who said 'bless you'. Thirty years a clerk at the Ministry, never once late, and I sneeze at my own funeral. Fenn did the eulogy. I'd no idea I was so well thought of."), {
    topic("Are you very ill?", {
      harbottle("I've until about the spring. It's quite all right. I'm already dead, so there's no paperwork."),
    }),
    { "Rest well, Mr Harbottle.", {
      harbottle("That's what it says on the stone."),
    } },
  }),
}

S.px_talk_ivo = {
  { when = "px_ivo_asked", steps = {
    t("The young shoemaker's eyes are shut. He looks a little less cross than he'd planned."),
  }, other = {
    t("A young shoemaker on a door laid over two crates. He hasn't long, and he's watching the sister."),
    ask(ivo("My gran said there was a lady who'd keep count of you. Does she? Honest, now. I'd like to know while there's time to be cross about it."), {
      { "Ask the sister.", {
        K("Yes. Every one. I don't know what she does with the count, and I won't lie to you. But you won't be left off it, Ivo. There's your thread. I've got the other end."),
        ivo("Huh. That's better than I thought."),
      } },
      { "I think she must. Someone should.", {
        ivo("You're no better at this than I am, are you? Stay a minute, though."),
      } },
    }),
    { set = "px_ivo_asked" },
  } },
}

S.px_talk_gutter_sick = {
  t("A very old woman with a cup beside her. She's holding the hand of the empty air next to her, and talking to it. When you lean close, she's giving it directions to a house in Blackpool."),
}

S.px_read_shaft = {
  t("A shaft comes down through the roof, far too clean. The air in it smells of lavender. On the grating, in beautiful lettering: CRANIAL DISTRICT. NOTHING GOES UP."),
}

S.px_boss_alderman = {
  t("The drain widens to a pool of something that isn't water. A great ringed bulk rises out of it, as big as a cart. Sunk deep in the folds of its neck is a tarnished chain of civic office."),
  D("Now that's a reasonable likeness of the Adaphis Board of Health."),
  { battle = "px_boss_alderman" },
  t("The Alderman comes apart with a long sigh, and everything it had been keeping goes down the drain at once. The chain lands at your feet. On the links: FOR THE GOOD OF THE CITY."),
  { gold = 500 },
  { set = "px_alderman_down" },
}

R.abilities.px_attach = { name = "ATTACH", power = 112 }
R.abilities.px_slime = { name = "GUTTER SLIME", power = 50, target = "all", status = "poison", chance = 60 }
R.abilities.px_cut = { name = "THE ALDERMAN'S CUT", power = 190, target = "all", windup = 34, warn = "IT RISES FROM THE MUCK" }

R.foes.px_gut_rat = { name = "GUTTER RAT", tier = 15, shape = "small", sprite = "rat", family = "rat", abilities = { { "gnaw", 3 }, { "spit", 1 } } }
R.foes.px_gut_bat = { name = "BLOOD BAT", tier = 15, shape = "quick", sprite = "px_bat", family = "harpy", abilities = { { "bite", 3 }, { "shriek", 1 } }, weak = { "fire" } }
R.foes.px_gut_leech = { name = "GUTTER LEECH", tier = 15, shape = "quick", sprite = "px_leech", family = "bug", abilities = { { "px_attach", 3 }, { "retch", 1 } }, weak = { "fire" } }
R.foes.px_fat_leech = { name = "BLOATED LEECH", short = "BLOATED", tier = 16, shape = "tank", sprite = "px_fatleech", family = "bug", abilities = { { "px_attach", 2 }, { "px_slime", 1 } }, weak = { "fire" } }
R.foes.px_alderman = {
  name = "THE ALDERMAN", tier = 16, shape = "tank", sprite = "px_alderman", family = "boss", immune = { sleep = true }, weak = { "fire" },
  abilities = { { "px_attach", 1 } },
  boss = { hpx = 1, phases = {
    { at = 100, moves = { { "px_attach", 3 }, { "px_slime", 1 } }, every = 5, big = "px_cut" },
    { at = 50, moves = { { "px_attach", 2 }, { "px_slime", 2 } }, every = 4, big = "px_cut", say = "IT CALLS ITS CREDITORS", summon = "px_gut_leech" },
  } },
}

R.encounters.px_gut_rats = { foes = { "px_gut_rat", "px_gut_rat", "px_gut_rat" }, flee = true, bg = "swamp" }
R.encounters.px_gut_bats = { foes = { "px_gut_bat", "px_gut_bat" }, flee = true, bg = "swamp" }
R.encounters.px_gut_leech = { foes = { "px_gut_leech", "px_gut_rat" }, flee = true, bg = "swamp" }
R.encounters.px_gut_fat = { foes = { "px_fat_leech", "px_gut_leech" }, flee = true, bg = "swamp" }
R.encounters.px_boss_alderman = { foes = { "px_alderman" }, flee = false, bg = "swamp", boss = true }

R.art.px_fatleech = "A swollen, purple-grey leech the size of a sofa, dragging itself along, shiny and tight."
R.art.px_alderman = "An enormous ringed leech as big as a cart, rearing out of black water, with a tarnished chain of civic office sunk into its neck."

-- ---------------------------------------------------------------- Adaphis: the Ribbed District

local harrow = who("px_harrow", "FOREWOMAN HARROW", { kind = "human", tall = 0.93, build = "broad", cut = "tunic", coat = C.redTint, trim = C.bg, legs = C.tie, hat = "scarf", hatInk = C.red, hatTrim = C.bg, hair = "short", hairInk = C.bg, wear = { "apron" }, apronInk = C.tie, carry = "hammer", eyes = "narrow", mouth = "line", mark = "scar", back = C.redTint })
local tom = who("px_tom", "OLD TOM", { kind = "old", tall = 0.8, build = "stout", cut = "tunic", coat = C.tie, trim = C.hi, hair = "tufts", hairInk = C.text, beard = "chops", beardInk = C.text, wear = { "apron" }, carry = "mug", eyes = "narrow", mouth = "smile", back = C.redTint })
local canteen = who("px_canteen", "CANTEEN MAUD", { kind = "human", tall = 0.86, build = "stout", cut = "dress", coat = C.line, trim = C.tie, hat = "scarf", hatInk = C.tie, hatTrim = C.line, wear = { "apron" }, apronInk = C.text, carry = "ladle", mouth = "frown", back = C.tie })
local osric = who("px_osric", "OSRIC", { kind = "human", tall = 0.88, build = "thin", cut = "coat", coat = C.panel, trim = C.bg, hair = "short", hairInk = C.line, carry = "letter", eyes = "tired", mouth = "line", back = C.hiTint })
local gateman = who("px_rb_gate", "GATE ORDERLY", { kind = "clinic", tall = 0.9, build = "normal", cut = "tunic", coat = C.line, trim = C.text, legs = C.tie, hat = "cap", hatInk = C.text, hatTrim = C.line, beak = 0.05, carry = "keys" })
local whistle = who("px_rb_sentry", "WORKS SENTRY", { kind = "clinic", tall = 0.98, build = "broad", cut = "tunic", coat = C.tie, trim = C.panel, legs = C.bg, hat = "sallet", hatInk = C.line, hatTrim = C.red, beak = 0.08, carry = "spear" })

R.maps.px_ribbed = {
  name = "ADAPHIS: RIBBED DISTRICT", theme = "city", savepoint = true,
  rows = {
    "##############>##############",
    "#hhhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#...........................#",
    "#hhhhh+hhhhhhh.hhhhhhh+hhhhh#",
    "#h...........h.h...........h#",
    "#h...........h.h...........h#",
    "#hhhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#...........................#",
    "#hhhhh+hhhhhhh.hhhhhhh+hhhhh#",
    "#h...........h.h...........h#",
    "#h...........h.h...........h#",
    "#hhhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#...........................#",
    "#hhhhhhhhhhhh...hhhhhhhhhhhh#",
    "#hhhhhhhhhhhh>..hhhhhhhhhhhh#",
    "##############>##############",
  },
  npcs = {
    { id = "px_harrow", x = 4, y = 10, sprite = "villager", script = "px_talk_harrow" },
    { id = "px_tom", x = 5, y = 5, sprite = "villager", script = "px_talk_tom" },
    { id = "px_canteen", x = 25, y = 5, sprite = "villager", script = "px_talk_canteen" },
    { id = "px_osric", x = 25, y = 10, sprite = "villager", script = "px_talk_osric" },
    { id = "px_rb_gate", x = 15, y = 15, sprite = "orderly", script = "px_talk_rb_gate", unless = "px_done" },
    { id = "px_rb_sentry", x = 15, y = 2, sprite = "soldier", script = "px_talk_rb_sentry", unless = "px_rb_job" },
  },
  steps = {
    { x = 14, y = 14, script = "px_rb_arrive", unless = "px_rb_in" },
  },
  chests = {
    { id = "c1", x = 12, y = 5, give = "potion", n = 3 },
    { id = "c2", x = 18, y = 11, gold = 250 },
  },
  exits = {
    { x = 15, y = 1, map = "px_works_1", mx = 13, my = 15, dir = 1 },
    { x = 14, y = 15, map = "px_gutter_2", mx = 21, my = 3, dir = 3 },
    { x = 15, y = 16, map = "px_pelvic", mx = 15, my = 3, dir = 3 },
  },
}

R.shops.px_rb_canteen = { tier = 3 }

S.px_rb_arrive = {
  t("You climb out of a manhole into noise. After Pelvic it's like being struck. Foundry sheds curve away like the bones of a chest, and at the top of it all, on the spine, stands the Works. The Clinic's war comes out of that gate. So, at dawn, do the empty carts."),
  D("I've wanted to know where they go for years, friend. I've also very much wanted not to."),
  O("There's a lift inside the Works, up the spine to the Cranial. That's our way to the King."),
  K("Someone's chalked a hammer on that wall, and someone's scrubbed it off, and someone's chalked it again. Let's find out who."),
  { set = "px_rb_in" },
}

S.px_talk_rb_gate = {
  gateman("South gate of the Ribs. It's for people going down, and nobody's going down today. Your face isn't on my board, so I can't say I've seen it."),
}

S.px_talk_rb_sentry = {
  whistle("Works gate. Shift's on, shift's off, and you're neither. No chit, no entry. Try the Foremen, if you've got a mind to work. They've a very wide definition of volunteer."),
}

S.px_talk_harrow = {
  { when = "px_revolt_started", steps = {
    ask(harrow("It's begun. Nobody's thrown anything yet. We've just stopped saying sir. You'd be amazed how loud that is."), {
      topic("Will you win?", {
        harrow("No idea. I know what a rib's for. It's so what's inside doesn't get crushed. That's all we've got for a plan."),
      }),
      { "Good luck, Forewoman.", {
        harrow("Luck's for the Cranial. We've got numbers."),
      } },
    }),
  }, other = {
    { when = "px_ledger", steps = {
      { when = "px_drains_open", steps = {
        t("Harrow slides the ledger out from under the mangle and lays it on the press-bed. She turns the pages with one blackened finger, and stops at a name for some time."),
        harrow("My brother's on page ninety. Set it, lads. Every name, every cart. Every street in the Ribs by morning. People can stand a great deal. What they can't stand is a number with their own name in it."),
        t("The press starts to thump, slowly, like something waking up. Somewhere along the rib, one hammer stops, and then another."),
        { gold = 800 },
        { give = "tonic", n = 3 },
        { set = "px_revolt_started" },
      }, other = {
        { when = "px_rb_asked", steps = {
          harrow("Not without the drains. Ask Mother Cray. The book's safe under the mangle."),
        }, other = {
          { set = "px_rb_asked" },
          harrow("That's the book? Put it under the mangle. It'll get us killed if we print it with no way to move people when the Clinic comes down the ribs. We need the drains, and they're Mother Cray's. Ask her for me. She'll listen to someone who's turned a patient."),
        } },
      } },
    }, other = {
      { when = "px_rb_job", steps = {
        harrow("The way up is at the far end of the Works, past the Tally Door. If you find their ledger, where the carts are written down, I want it."),
      }, other = {
        t("A back room that smells of hot ink, with washing hung across it to hide the press. A woman with forearms like ship's cable looks you over."),
        ask(harrow("This is a laundry. Fenn's runner said you'd come. Forewoman Harrow, Rib Nine. What do you want?"), {
          topic("What are you doing here?", {
            harrow("Asking a question. Where do the carts go? We build the guns, and we've got a right to know what for. They took my brother for a cough, and they've written every spring since."),
          }),
          { "We need to get into the Works.", {
            harrow("So do we. Here's a shift chit, it was a good man's. Past the yards there's the Tally Door, and they'll want a form I've never seen. Bring me their cart ledger, and you've a friend in the Ribs."),
            { set = "px_rb_job" },
          } },
        }),
      } },
    } },
  } },
}

S.px_talk_tom = {
  ask(tom("The Ninth Rib. There's beer, and a bed for twenty-five, and I'll wake you for the shift whistle whether you've a shift or not."), {
    { "A bed, please.", {
      { inn = 25 },
    } },
    { "No, thanks.", {} },
  }),
}

S.px_talk_canteen = {
  ask(canteen("I've four hundred mouths and a fifth of what I'm signed for. I've seen Cranial crates go by marked MEDICAL with a tin of peaches rolling about in them. What d'you want?"), {
    { "Show me the supplies.", {
      { shop = "px_rb_canteen" },
    } },
    { "Never mind.", {} },
  }),
}

S.px_talk_osric = {
  t("A cold, tidy room. Nine letters are laid out on the table in a row, on the same good paper, and a man is reading the ninth."),
  ask(osric("Nine years. 'She continues to make good progress, and she speaks of you warmly.' Warmly. She had a stammer, you know. I'd give a great deal to know who writes these."), {
    { "I'm sorry for your trouble.", {
      osric("There's no trouble. That's what it says here."),
    } },
    { "I'll find out, if I can.", {
      osric("I don't suppose it matters. Yes, it does. Thank you."),
    } },
  }),
}

-- ---------------------------------------------------------------- the Works

local tally = who("px_tally_o", "TALLY ORDERLY", { kind = "clinic", tall = 0.86, build = "thin", cut = "tunic", coat = C.line, trim = C.text, legs = C.tie, hat = "visor", hatInk = C.tie, hatTrim = C.text, beak = 0.06, carry = "clipboard" })
local loveday = who("px_loveday", "MR LOVEDAY", { kind = "old", tall = 0.76, build = "hunched", lean = 0.1, cut = "coat", coat = C.hiTint, trim = C.tie, hair = "tufts", hairInk = C.text, eyes = "specs", carry = "pen", mouth = "smile", wear = { "waistcoat" }, mark = "ink", back = C.hiTint })
local swabb = who("px_swabb", "MR SWABB", { kind = "human", tall = 0.9, build = "broad", cut = "tunic", coat = C.line, trim = C.tie, legs = C.bg, hat = "scarf", hatInk = C.text, hatTrim = C.line, wear = { "apron" }, apronInk = C.panel, carry = "bucket", eyes = "tired", mouth = "line", back = C.tie })
local crake = who("px_crake", "SURGEON-GENERAL CRAKE", { kind = "clinic", tall = 1, build = "thin", cut = "robe", coat = C.text, trim = C.red, hat = "beakhat", hatInk = C.bg, hatTrim = C.hi, beak = 0.26, maskInk = C.text, beakInk = C.hi, wear = { "epaulettes", "badge" }, back = C.redTint })

R.looks.px_sleeper_a = { kind = "human", pose = "lying", bed = true, coat = C.text, trim = C.line, hair = "long", hairInk = C.tie, thread = false }
R.looks.px_sleeper_b = { kind = "old", pose = "lying", bed = true, coat = C.text, trim = C.line, hair = "short", hairInk = C.text, flip = true }
R.looks.px_sleeper_c = { kind = "child", pose = "lying", bed = true, coat = C.text, trim = C.line, hair = "plaits", hairInk = C.redTint, size = 0.75 }
R.looks.px_sleeper_d = { kind = "human", pose = "lying", bed = true, coat = C.text, trim = C.line, hair = "short", hairInk = C.bg, beard = "stubble", flip = true }

R.maps.px_works_1 = {
  name = "THE WORKS: THE YARDS", theme = "mine",
  rows = {
    "#########################",
    "#hhhhhhhhhhh>hhhhhhhhhhh#",
    "#hhhhhhhhhhh.hhhhhhhhhhh#",
    "#h.........h.h.........h#",
    "#h.........h.h.........h#",
    "#h.........+.+.........h#",
    "#h.........h.h.........h#",
    "#hhhhhhhhhhh.hhhhhhhhhhh#",
    "#.......................#",
    "#.~~~~.hhhhh.hhhhh.~~~~.#",
    "#.~~~~.h...h.h...h.~~~~.#",
    "#.~~~~.h...+.+...h.~~~~.#",
    "#.~~~~.hhhhh.hhhhh.~~~~.#",
    "#.......................#",
    "#hhhhhhhhhhh.hhhhhhhhhhh#",
    "############>############",
  },
  npcs = {
    { id = "px_tally_o", x = 13, y = 3, sprite = "orderly", script = "px_talk_tally", unless = "px_form_shown" },
    { id = "px_loveday", x = 19, y = 5, sprite = "villager", script = "px_talk_loveday" },
    { id = "px_swabb", x = 9, y = 11, sprite = "villager", script = "px_talk_swabb" },
    { id = "px_filling", x = 4, y = 4, sprite = "px_cask", script = "px_read_filling" },
    { id = "px_cartyard", x = 2, y = 12, sprite = "px_cart", script = "px_read_cartyard" },
  },
  steps = {
    { x = 13, y = 14, script = "px_works_in", once = true },
  },
  chests = {
    { id = "c1", x = 10, y = 7, give = "broadsword" },
    { id = "c2", x = 17, y = 12, give = "tonic", n = 2 },
    { id = "c3", x = 23, y = 7, gold = 280 },
    { id = "c4", x = 24, y = 12, give = "potion", n = 4 },
  },
  foes = {
    { id = "f1", x = 6, y = 14, enc = "px_wk_orderlies", sprite = "orderly" },
    { id = "f2", x = 20, y = 14, enc = "px_wk_orderlies", sprite = "orderly" },
    { id = "f3", x = 6, y = 9, enc = "px_wk_cart", sprite = "px_cart" },
    { id = "f4", x = 20, y = 9, enc = "px_wk_staff", sprite = "doctor" },
    { id = "f5", x = 6, y = 5, enc = "px_wk_staff", sprite = "doctor" },
    { id = "f6", x = 16, y = 11, enc = "px_wk_orderlies", sprite = "orderly" },
  },
  exits = {
    { x = 13, y = 16, map = "px_ribbed", mx = 15, my = 2, dir = 3 },
    { x = 13, y = 2, map = "px_works_2", mx = 14, my = 15, dir = 1 },
  },
}

R.maps.px_works_2 = {
  name = "THE WORKS: THE LONG WARD", theme = "marble",
  rows = {
    "###########################",
    "#hhhhhhhhhhhhhhhhhhhhhhhhh#",
    "#h.....h.........h.......h#",
    "#h.....h.........h.......h#",
    "#h.....+.........+.......h#",
    "#h.....h.........h.......h#",
    "#hhhhhhhhhhhh+hhhhhhhhhhhh#",
    "#.........................#",
    "#.hhhhhhhhhhh.hhhhhhhhhhh.#",
    "#.........................#",
    "#.hhhhhhhhhhh.hhhhhhhhhhh.#",
    "#.........................#",
    "#.hhhhhhhhhhh.hhhhhhhhhhh.#",
    "#.........................#",
    "#hhhhhhhhhhhh.hhhhhhhhhhhh#",
    "#############>#############",
  },
  npcs = {
    { id = "tobin", x = 4, y = 10, sprite = "shroud", script = "px_talk_tobin" },
    { id = "px_sleeper_a", x = 8, y = 12, sprite = "shroud", script = "px_talk_sleeper" },
    { id = "px_sleeper_b", x = 20, y = 10, sprite = "shroud", script = "px_talk_sleeper" },
    { id = "px_sleeper_c", x = 22, y = 14, sprite = "shroud", script = "px_talk_sleeper_child" },
    { id = "px_sleeper_d", x = 6, y = 14, sprite = "shroud", script = "px_talk_sleeper" },
    { id = "px_crake", x = 13, y = 3, sprite = "doctor", script = "px_boss_crake", unless = "px_crake_down" },
    { id = "px_ledgerbook", x = 4, y = 4, sprite = "px_ledger", script = "px_read_ledger", unless = "px_ledger" },
    { id = "px_lift", x = 24, y = 4, sprite = "px_lift", script = "px_ride_up" },
  },
  steps = {
    { x = 14, y = 14, script = "px_ward_long", once = true },
    { x = 14, y = 6, script = "px_boss_crake", unless = "px_crake_down" },
  },
  chests = {
    { id = "c1", x = 3, y = 6, give = "padded_coat" },
    { id = "c2", x = 25, y = 8, gold = 320 },
    { id = "c3", x = 2, y = 14, give = "wool_habit" },
  },
  foes = {
    { id = "f1", x = 10, y = 14, enc = "px_wk_walkers", sprite = "blighted" },
    { id = "f2", x = 18, y = 14, enc = "px_wk_walkers", sprite = "blighted" },
    { id = "f3", x = 14, y = 11, enc = "px_wk_walkers", sprite = "blighted" },
    { id = "f4", x = 2, y = 9, enc = "px_wk_staff", sprite = "doctor" },
    { id = "f5", x = 26, y = 11, enc = "px_wk_cart", sprite = "px_cart" },
    { id = "f6", x = 10, y = 8, enc = "px_wk_orderlies", sprite = "orderly" },
  },
  exits = {
    { x = 14, y = 16, map = "px_works_1", mx = 13, my = 3, dir = 3 },
  },
}

S.px_works_in = {
  t("Harrow's chit gets a grunt from the sentry. Inside are rail-lines, vats that steam, and, drawn up in perfect rows, the closed carts. Far up the yard is a single door, and a thin orderly at a very small desk."),
  D("Forty carts. I never thought about there being a place where they were parked."),
}

S.px_read_filling = {
  t("Row on row of stencilled casks. On a board: ORRENSHIRE, DONE. MURKWELL, DONE. OPLINAS, PENDING. VEINS OF SINDAL, TEN THOUSAND BY SPRING."),
  D("That's what the guns at Murkwell are for. They were never meant to hit anything. They're meant to carry."),
  { when = "sn_done", steps = {
    K("All those smiling people, asleep in their clean beds."),
  } },
}

S.px_read_cartyard = {
  t("A closed cart, just out of the wash. It's the cleanest object in the whole of Plexios. On the inside of the door, someone has gone over the wood with a plane."),
}

S.px_talk_swabb = {
  t("A wet stone bay. A big, quiet man is working at the inside of a cart door with a hand-plane."),
  ask(swabb("Swabb. They come back very clean. I've had a commendation. It's not the blood, that's only cold water. It's the marks on the inside of the doors. You need the plane for those."), {
    topic("Marks?", {
      swabb("They get their nails in. The big ones, and the little ones lower down. I take it all off, every time. Nobody's to see. I've seen every one."),
    }),
    { "How do you sleep, Mr Swabb?", {
      swabb("Very well. That's what I can't forgive."),
    } },
    { "I'll leave you to it.", {} },
  }),
}

S.px_talk_tally = {
  { when = "px_form", steps = {
    t("The orderly reads Mr Loveday's form, checks both sides and holds it to the light, and his shoulders lower with a happiness you can't help but envy."),
    tally("A P-Nine. In order. It's been so long. Pass, please. Mind the wet floor."),
    { set = "px_form_shown" },
  }, other = {
    ask(tally("Tally Door. Nobody goes through to the Long Ward without a Form P-Nine, countersigned. I don't make the rules. I've been told they don't either."), {
      topic("Where would I get one?", {
        tally("Correspondence, the door on the right, up the yard. There's an old gentleman. He's very, very glad to see people."),
      }),
      { "I'll find one.", {} },
    }),
  } },
}

S.px_talk_loveday = {
  t("A long office lined to the ceiling with pigeonholes, each with a name on a card. There must be thirty thousand. In the middle sits a small, pink, happy old man with a very good pen."),
  { when = "px_form", steps = {
    ask(loveday("Back so soon! I've just done a lovely one to a lady in Scythebreak. Was there anything else?"), {
      topic("Do you write them all yourself?", {
        loveday("Oh, they're all me! I've been doing 'warmly' this year. I thought it was rather a find."),
        D("Have you seen any of them, Mr Loveday?"),
        loveday("Oh, no. I've never been past the door. I don't think that would be at all good for the writing."),
      }),
      { "No. Thank you, Mr Loveday.", {
        loveday("Do come again. Hardly anybody ever does."),
      } },
    }),
  }, other = {
    ask(loveday("A visitor! Mr Loveday, Correspondence, forty-four years. Every spring, thirty thousand families, each by hand. 'Doing well', 'much improved'. I'm very proud of the variety."), {
      topic("And when one of them dies?", {
        loveday("Then I use the good paper. 'Resting comfortably.' And I keep on sending it. There's no form for stopping. It's all a very great comfort."),
      }),
      { "We need a Form P-Nine.", {
        loveday("A P-Nine! Nobody's wanted one since the Scab! There. Oh, it's such a pleasure to be asked for something."),
        D("I've spent years telling people there was a whole office for that. I don't know what I thought it would look like. I don't even know how to hate him."),
        { set = "px_form" },
      } },
    }),
  } },
}

S.px_ward_long = {
  t("The noise of the yards stops behind you as if a lid has come down. It is cool in here, and clean, and it smells of lavender."),
  t("The room goes on further than the lamps do. Racks, four cots high, in rows, running back into the dark. On every cot a person in a white gown, breathing, in time with all the others. Thin tubes run down from a pipe, with the small sweet hiss of sopor."),
  K("They're alive. Oh, you poor loves."),
  O("Dreaming is how it breeds. So one keeps a great many dreaming, in a cool room, at a steady temperature. It's an excellent piece of work. I wish to be sick."),
  D("Transfers. Nobody counts a transfer. I walked beside the carts, friend. This is what I was walking to."),
}

S.px_talk_sleeper = {
  t("A man or a woman, somewhere between thirty and sixty. Clean, fed and well turned. The eyes are moving very fast under the lids. A card at the foot of the cot gives a number, and the words DOING WELL."),
}

S.px_talk_sleeper_child = {
  t("A very small shape on a very clean cot. The card reads DOING WELL. Somebody, some orderly, against all regulations, has tucked a rag doll in under the arm."),
  K("There's a thread for this one. Give me a moment."),
}

S.px_talk_tobin = {
  t("A thin, greying man on a bottom cot. The card says TOBIN. SCYTHEBREAK. ONE NIGHT'S OBSERVATION. It's dated nine years ago."),
  t("Everyone else in the ward lies rigid, faces working. He lies perfectly loose, and his mouth opens and closes, softly. One hand is moving at his side, very slowly, the way a fin moves."),
  { when = "heard_tobin", steps = {
    ask(K("You know this one, don't you?"), {
      { "His boots are by a door in Scythebreak.", {
        K("Then someone's still waiting for him. I've tied the thread. I couldn't wake him, and I doubt I should."),
        t("The hand moves. He smiles a little. He is, as far as anyone will ever know, a fish."),
      } },
      { "He said it was the happiest he'd ever been.", {
        K("I believe it. I've tied the thread. I wouldn't wake him if I could."),
      } },
    }),
  }, other = {
    K("I can't wake him, and I'm not sure I should. It's a strange thing to say in a room like this, but I believe that man is having a lovely time."),
  } },
}

S.px_boss_crake = {
  t("A surgical theatre, tiered and spotless. At a basin a very tall old man in a long white coat is washing his hands, and he has been washing them for some time."),
  crake("Mind the floor, it's just been done. Is that my best walking officer? Eleven carts and not one query. Do you know how rare that is?"),
  D("Surgeon-General."),
  crake("You made soup. I did laugh. Your commission was never cancelled, you know. I've kept it in a drawer. Say the word, and that badge can be back on by morning."),
  ask(crake("And this will be the clean one. How do you do? Do tell the doctor what you think. People so rarely ask the transfers."), {
    { "It's your choice, doctor. I'll stand by it.", {
      D("Thank you, friend. It's been a long time since that was true."),
    } },
    { "We need you. Don't you dare go back.", {
      D("That's the kindest thing anyone's ever shouted at me."),
    } },
    { "Tell him about the spoon.", {
      D("It was a very good spoon, sir."),
    } },
  }),
  D("I wrote 'clean' on a great many forms, and you read every one, and you were pleased. No, sir. I've taken myself off it."),
  crake("Pity. Hold them for me, would you? I've just finished scrubbing in."),
  { battle = "px_boss_crake" },
  t("He sits down on the steps of his own theatre, all at once, and looks at the blood on his hands with a mild and terrible disappointment."),
  crake("The ledger's in my office. You always did read to the end. Do mind the floor."),
  t("He doesn't get up again. The doctor doesn't watch. Then the doctor looks to the door on the west side."),
  { set = "px_crake_down" },
}

S.px_read_ledger = {
  t("On the desk lies the cart ledger, thick as a loaf. A name, a town, a date, a cart, and at the foot of each page the signature of the walking officer."),
  t("The doctor finds the first page without having to look for it. Then the second. It takes a long time."),
  D("Two hundred and seven. I told you I'd tried not knowing, and it didn't take. It's a very nice signature."),
  K("Read them out."),
  D("Sister, I can't."),
  K("I know you can't. Read them out. I need the names."),
  t("So the doctor reads two hundred and seven names aloud, in an even voice, and the sister ties a knot for each. The scholar holds the lamp."),
  ask(D("That's all of them. Friend, I don't know what one does now. What does one do?"), {
    { "We take the ledger to Harrow. All of it.", {
      D("Yes. My page as well. Let them see the hand."),
    } },
    { "You keep walking. I'll walk with you.", {
      D("That's what I did before. It's rather better with company. We'll bring the book."),
    } },
    { "Tear your page out, if you want to.", {
      D("I thought of it. I find I'd rather be on it. We'll bring the book. Someone in the Ribs has been waiting for it."),
    } },
  }),
  { set = "px_ledger" },
}

S.px_ride_up = {
  { when = "px_ledger", steps = {
    ask(t("A brass cage on a cable as thick as your arm. The dial has two marks: WORKS and CRANIAL. It's the only thing in this building with a cushion."), {
      { "Take it up.", {
        t("The cage shudders and rises. The smell of lavender comes down to meet you."),
        { warp = { "px_cranial", 3, 14, 2 } },
      } },
      { "Not yet.", {} },
    }),
  }, other = {
    { when = "px_crake_down", steps = {
      D("Not yet, friend. There's something in his office I've got to look at. West door. I'd sooner do it now, while I'm still angry."),
    }, other = {
      t("A brass cage, locked off. The controls run to the Surgeon-General's theatre."),
    } },
  } },
}

R.abilities.px_incision = { name = "INCISION", power = 125 }
R.abilities.px_sopor = { name = "SOPOR MIST", mp = 6, power = 30, magic = true, target = "all", status = "sleep", chance = 55 }
R.abilities.px_amputate = { name = "AMPUTATION", power = 260, windup = 34, warn = "HE SCRUBS IN" }
R.abilities.px_call = { name = "ORDERLIES, PLEASE", target = "summon", summon = "px_senior" }

R.foes.px_senior = { name = "SENIOR ORDERLY", short = "SENIOR", tier = 17, shape = "brute", sprite = "orderly", family = "staff", abilities = { { "baton", 4 }, { "needle", 1 } } }
R.foes.px_physician = { name = "WARD PHYSICIAN", short = "PHYSICIAN", tier = 17, shape = "healer", sprite = "doctor", family = "staff", abilities = { { "baton", 2 }, { "draught", 1 }, { "suture", 2 } } }
R.foes.px_cart_engine = { name = "CLOSED CART", tier = 17, shape = "tank", sprite = "px_cart", family = "staff", abilities = { { "lunge", 2 }, { "swing", 3 } }, resist = { "bolt" } }
R.foes.px_walker = { name = "SLEEPWALKER", tier = 17, shape = "quick", sprite = "blighted", family = "blighted", abilities = { { "claw", 3 }, { "touch", 2 }, { "stare", 1 } } }
R.foes.px_crake = {
  name = "SURGEON-GENERAL CRAKE", short = "CRAKE", tier = 18, shape = "caster", sprite = "doctor", family = "boss", immune = { sleep = true, nightmare = true },
  abilities = { { "px_incision", 1 } },
  boss = { hpx = 1.2, phases = {
    { at = 100, moves = { { "px_incision", 3 }, { "draught", 1 } }, every = 5, big = "px_amputate" },
    { at = 66, moves = { { "px_incision", 2 }, { "px_sopor", 2 } }, every = 5, big = "px_amputate", say = "HE ASKS FOR A SECOND PAIR OF HANDS", summon = "px_senior", call = "px_call" },
    { at = 33, moves = { { "px_incision", 3 }, { "px_sopor", 1 } }, every = 4, big = "px_amputate", say = "HE STOPS BEING GENTLE", speedUp = 1, summon = "px_senior", call = "px_call" },
  } },
}

R.encounters.px_wk_orderlies = { foes = { "px_senior", "px_senior" }, flee = true, bg = "town" }
R.encounters.px_wk_staff = { foes = { "px_physician", "px_senior" }, flee = true, bg = "marble" }
R.encounters.px_wk_cart = { foes = { "px_cart_engine", "px_senior" }, flee = true, bg = "town" }
R.encounters.px_wk_walkers = { foes = { "px_walker", "px_walker", "px_walker" }, flee = true, bg = "marble" }
R.encounters.px_boss_crake = { foes = { "px_crake" }, flee = false, bg = "marble", boss = true }

R.art.px_cart = "A closed black cart with no window, spotlessly clean, moving by itself on iron wheels."
R.art.px_lift = "A brass lift cage on a thick cable, with one cushioned seat."

-- ---------------------------------------------------------------- Adaphis: the Cranial District

local aspinall = who("px_aspinall", "LORD ASPINALL", { kind = "old", tall = 0.92, build = "thin", cut = "robe", coat = C.accent, trim = C.text, hair = "short", hairInk = C.text, wear = { "chain" }, carry = "scroll", eyes = "narrow", mouth = "line", back = C.hiTint })
local henman = who("px_henman", "THE HEN-BEARER", { kind = "human", tall = 0.92, build = "normal", coat = C.accent, trim = C.hi, hat = "cap", hatInk = C.accent, hatTrim = C.hi, carry = "hen", eyes = "tired", mouth = "line", wear = { "collar" }, back = C.hiTint })
local hale = who("px_hale", "PROFESSOR HALE", { kind = "old", tall = 0.8, build = "hunched", lean = 0.12, cut = "robe", coat = C.bg, trim = C.text, hat = "wide", hatInk = C.bg, hatTrim = C.text, hair = "tufts", hairInk = C.text, beard = "long", beardInk = C.text, carry = "book", eyes = "specs", back = C.blueTint })
local bram = who("px_bram", "BRAM THE SWEEPER", { kind = "old", tall = 0.8, build = "hunched", cut = "tunic", coat = C.line, trim = C.tie, hat = "cap", hatInk = C.tie, hatTrim = C.bg, hair = "short", hairInk = C.text, carry = "broom", eyes = "tired", mouth = "line", skin = C.line, back = C.hiTint })
local steward = who("px_steward", "THE STOREKEEPER", { kind = "human", tall = 0.88, build = "thin", cut = "coat", coat = C.line, trim = C.hi, hair = "short", hairInk = C.line, carry = "list", eyes = "narrow", mouth = "line", wear = { "waistcoat" }, back = C.hiTint })
local porter = who("px_porter", "HOSPITAL PORTER", { kind = "clinic", tall = 0.9, build = "normal", cut = "coat", coat = C.text, trim = C.line, hat = "cap", hatInk = C.line, hatTrim = C.text, beak = 0.05, carry = "keys", back = C.redTint })
local gatekeep = who("px_cr_gate", "CRANIAL GUARD", { kind = "clinic", tall = 0.98, build = "broad", coat = C.tie, trim = C.hi, hat = "peaked", hatInk = C.bg, hatTrim = C.hi, beak = 0.08, carry = "spear", back = C.panel })

R.looks.px_charwoman = { kind = "old", pose = "lying", bed = true, coat = C.text, trim = C.line, hair = "bun", hairInk = C.text, carry = "none" }

R.maps.px_cranial = {
  name = "ADAPHIS: CRANIAL DISTRICT", theme = "marble", savepoint = true,
  rows = {
    "###########################",
    "#hhhhhhhhhhhhhhhhhhhhhhhhh#",
    "#h.....h.........h.......h#",
    "#h.....h.........h.......h#",
    "#h.....h.........h.......h#",
    "#h.....h.........h.......h#",
    "#hhh+hhhhhhhh+hhhhhhh+hhhh#",
    "#.........................#",
    "#.........................#",
    "#...hhhh...........hhhh...#",
    "#...h..h...........h..h...#",
    "#...h+hh...........hh+h...#",
    "#.........................#",
    "#.........................#",
    "#hhhhhhhhhh...hhhhhhhhhhhh#",
    "#hhhhhhhhhhh.hhhhhhhhhhhhh#",
    "############>##############",
  },
  npcs = {
    { id = "px_lift_top", x = 2, y = 14, sprite = "px_lift", script = "px_ride_down" },
    { id = "px_aspinall", x = 14, y = 8, sprite = "villager", script = "px_talk_aspinall", unless = "px_fab_ok" },
    { id = "px_fabian", x = 13, y = 3, sprite = "villager", script = "px_scene_fabian", unless = "ud_done" },
    { id = "px_henman", x = 15, y = 4, sprite = "villager", script = "px_talk_henman" },
    { id = "px_hale", x = 5, y = 4, sprite = "villager", script = "px_talk_hale" },
    { id = "px_bram", x = 24, y = 9, sprite = "villager", script = "px_talk_bram" },
    { id = "px_steward", x = 7, y = 11, sprite = "villager", script = "px_talk_steward" },
    { id = "px_porter", x = 22, y = 8, sprite = "orderly", script = "px_talk_porter", unless = "px_token" },
    { id = "px_cr_gate", x = 13, y = 16, sprite = "soldier", script = "px_talk_cr_gate", unless = "px_done" },
    { id = "px_colette", x = 23, y = 4, sprite = "doctor", script = "px_scene_colette", unless = "px_done" },
    { id = "px_charwoman", x = 24, y = 4, sprite = "shroud", script = "px_talk_charwoman" },
  },
  steps = {
    { x = 3, y = 14, script = "px_cr_arrive", unless = "px_cr_in" },
    { x = 22, y = 6, script = "px_scene_colette", when = "px_token", unless = "px_done" },
    { x = 13, y = 3, script = "px_read_empty_chair", when = "ud_done" },
  },
  chests = {
    { id = "c1", x = 3, y = 6, give = "oak_staff" },
    { id = "c2", x = 25, y = 13, gold = 400 },
  },
  exits = {
    { x = 13, y = 17, world = WORLD.adaphis },
  },
}

R.shops.px_cr_steward = { tier = 3 }

S.px_ride_down = {
  ask(t("The brass cage waits, ticking gently."), {
    { "Go down to the Works.", {
      { warp = { "px_works_2", 23, 4, 4 } },
    } },
    { "Stay.", {} },
  }),
}

S.px_cr_arrive = {
  t("The cage opens on a white street under a white sky. There's no noise up here, and no smell. The steeples go up on every side like a mouthful of very good teeth. Over the palace flies the raven of Plexios."),
  K("Of all the birds they might have chosen. I do wonder if anyone here remembers whose that is."),
  D("That's the Chamberlain, by the palace door. No, friend, I don't know why nobody's stopped us. I was rather hoping you did."),
  { set = "px_cr_in" },
}

S.px_talk_aspinall = {
  t("A very old, very thin nobleman looks up from a list at the mud, the blood and the owl, with no change of expression whatsoever."),
  ask(aspinall("You'll be the party from the drains. His Majesty has been asking since Thursday. One bows at the third tile, one says Sire, and one doesn't look at the hen."), {
    { "We'll see the King.", {
      aspinall("So you will. If he offers you any soup, you've eaten."),
      { set = "px_fab_ok" },
    } },
    { "Don't look at the what?", {
      aspinall("It's the sort of thing one picks up. Through the door, please."),
      { set = "px_fab_ok" },
    } },
  }),
}

S.px_read_empty_chair = {
  t("The chair is empty, and someone has changed the cushion. A card on the arm says: HIS MAJESTY DIED OF A LONG ILLNESS. THE HOUSEHOLD THANKS YOU FOR YOUR CONCERN. It's in a very neat hand."),
}

S.px_scene_fabian = {
  { when = "px_token", steps = {
    { when = "px_done", steps = {
      fabian("You saw her, and you're still walking about? Don't tell me what she said. Go on, go away. I'm trying to die of something else."),
    }, other = {
      fabian("Are you still here? Go on! The hospital, across the square. It's the only way out of the Cranial. It's all the only way out."),
    } },
  }, other = {
    t("The throne of Plexios was built for a giant, and the man in it has been getting smaller for ninety years. There's a great deal of purple, and near the top of it two bright, frightened eyes."),
    fabian("Is it them? Speak up! Has the hen had the soup?"),
    henman("Lady Margaret has had the soup, Sire. She is well."),
    fabian("Then bring it. So you came up through my drains and did for my Surgeon-General. Ha! I've not been so pleased since the Scab."),
    { when = "sn_done", steps = {
      fabian("And you've dined with Sindal. Lovely manners. He'll bury me."),
    } },
    ask(fabian("You've come for something. Everyone does. I've got an army I didn't want and a city dying very politely. Which is it?"), {
      topic("Why does the hen have the soup first?", {
        fabian("Because I have a doctor. I gave Colette the army because she asked nicely, and the police because she was right. Every morning she comes up to ask after my health. She doesn't look at my face. She listens to how I breathe."),
        henman("This is the eleventh Lady Margaret, Sire."),
        fabian("Is it? They do go on so bravely. Promote her."),
      }),
      topic("Do you know what's in the Long Ward?", {
        fabian("I know what I signed. If one stays very old for long enough, nobody expects one to read things. I'm a coward, and I'm still breathing. It's more than the others can say."),
      }),
      { "We need a token from the throne of Plexios.", {
        fabian("For the hag in the windmill? Oh, word gets up here. Ha! Oh, my chest."),
        t("The King stops laughing. He looks around the great room, very quickly. Then one spotted hand goes into the purple, and comes out holding something small on a chain."),
        fabian("The Knuckle of Hollodin Adaphis, last joint of the Founder's right hand. No one is King in Plexios who hasn't got that on him. It's the only law she hasn't rewritten."),
        fabian("She can't sit in this chair without it. So take it, to your hag, to the bottom of the sea. That's the bravest thing I've ever done, and I want you to go away before I think of it again."),
        t("It's very small and very old. It's warm, from him."),
        { set = "px_token" },
        fabian("There's no way out but past her people. The Open Door hospital, across the square. She's in there. She'll want to see you. Don't drink anything."),
      } },
    }),
  } },
}

S.px_talk_henman = {
  ask(henman("I carry Lady Margaret, Taster to the Crown. She outranks most of the Privy Council. You may address her as My Lady. She's very tired."), {
    { "Good day, my lady.", {
      t("The hen looks at you with one round orange eye. It's the steadiest gaze you've met in Plexios. It knows exactly what's in the soup."),
    } },
    { "I'll leave you both to it.", {} },
  }),
}

S.px_talk_hale = {
  t("A dim hall of empty benches. Over the door the letters have been chiselled off, but you can read the marks: ALL WHO ARE SICK MAY COME. ALL WHO WISH TO LEARN MAY COME."),
  ask(hale("Is it the two o'clock? Sit, sit. The doors stood open, you know, all day and all night. A fishwife could walk in with a sore foot and be seen by the Regius Professor."), {
    topic("Did you teach Doctor Colette?", {
      hale("Little half-elf girl, came in out of the rain with a book too big for her. Best I ever taught. I asked what she wanted to cure. She said, 'Everyone.' I've thought about the way she said that."),
    }),
    topic("What happened to the College?", {
      hale("Someone shut one door, on a Tuesday, for a good reason. There's always a good reason. You'd want to write that down."),
    }),
    { "Thank you, Professor.", {
      hale("Read the set texts. There is always a test."),
    } },
  }),
}

S.px_talk_bram = {
  t("An old man sweeping a spotless street. He turns his head and swallows, and smiles, and looks at something interesting. Someone taught him that."),
  bram("Fifty years on this street, and I've never seen a thing. If you know a Mother Cray, tell her Bram's still got the lavender going down the shaft. It's not much. It gets rid of the smell for them, a little."),
}

S.px_talk_steward = {
  ask(steward("The Palace Stores. Nobody in the Cranial ever comes. You've got gold? That's what we call a clean bill of health."), {
    { "Show me the stores.", {
      { shop = "px_cr_steward" },
    } },
    { "Not now.", {} },
  }),
}

S.px_talk_porter = {
  ask(porter("The Open Door Hospital. Closed, by order. The Doctor's within. She says you're to go and see the King first."), {
    topic("She knows we're here?", {
      porter("She's left a chair out. I've found it's best to do as she expects. You're happier, and she's less disappointed."),
    }),
    { "All right. The King first.", {} },
  }),
}

S.px_talk_cr_gate = {
  { when = "px_token", steps = {
    gatekeep("Nobody goes out by this gate without a physician's hand. Open Door, east of the square. No, I don't want to see the bone. I haven't seen the bone."),
  }, other = {
    gatekeep("Nobody goes out by this gate without a physician's hand. Open Door, east of the square."),
  } },
}

S.px_talk_charwoman = {
  { when = "px_done", steps = {
    t("A very old woman sleeps with one hand out on the blanket, as if someone had only just let go of it. There's a chair beside the bed. Someone will be back for it."),
  }, other = {
    t("A very old woman, breathing very lightly. Her hands are cracked from forty years of lye."),
  } },
}

-- The heart of the region. Short, and hers: the author will rewrite this.
S.px_scene_colette = {
  t("One lamp. One bed, with an old charwoman in it. A woman in physician's grey is holding a cup to the old woman's lips, and she doesn't look round."),
  colette("A moment. She takes it better if nobody hurries her."),
  t("She wipes the old woman's chin with her thumb, and only then looks up. It's the most tired face you've ever seen, and it looks at you as though you were the first good news in years."),
  colette("{hero}. You've had a dreadful walk. Sit. Your grandmother's comfortable. I had her moved to the window. Nobody asked me to."),
  D("Doctor."),
  colette("You always read to the end. Are you sleeping?"),
  D("'Do not treat.' Underlined."),
  colette("Yes. So that none of you would have to decide. You may hate me for that. It's what I'm for."),
  colette("He gave you the Knuckle. He was so brave. I shan't want it."),
  ask(colette("Everyone dreams, {hero}. I've asked them all. Everyone but you. I'd like a little of your blood. You may say no."), {
    topic("Why do you want it?", {
      colette("Because I have been awake for a very long time."),
    }),
    topic("Orrenshire. Murkwell. The Long Ward. Why?", {
      colette("Somebody has to know exactly what this does, before it can be stopped, or aimed. I sat with the first of them. Ask the doctor how many others do."),
    }),
    { "Take it.", {
      t("She does it herself, and it doesn't hurt. It's the gentlest anyone has been with you since Nan. That's what frightens you. She holds the little glass up to the lamp, like a letter from someone she'd given up on."),
      colette("Thank you."),
      { set = "px_gave_blood" },
    } },
    { "No.", {
      colette("No. Thank you for saying so. Nobody does."),
      t("She sets the needle back on its cloth and squares it to the edge. You'd feel a great deal better if she were angry."),
      colette("You'll bring it to me yourself, in the end. I'll keep the chair."),
      { set = "px_refused_blood" },
    } },
  }),
  t("She writes three lines, in a very neat hand, and holds them out without looking. A pass for four, under her own seal. Then her hand goes to the old book at her elbow, and she turns back to the bed."),
  colette("Mind the step."),
  { fade = true },
  K("She looked at my thread and looked away. Twenty years I've been hiding that."),
  D("She asked if I was sleeping. I know exactly what I'd once have given to hear that."),
  { when = "sn_done", steps = {
    D("That's both, then. Back to the Vulture, friend. I never thought I'd look forward to that."),
  }, other = {
    { when = "sn_crossed", steps = {
      D("That's one. The Vulture wants something from Sindal as well, and we left that half done. Back through the Cavity Crevice, friend. I can't say I've missed the melons."),
    }, other = {
      D("That's one. The Vulture wants something from Sindal as well. The Cavity Crevice, in the pass west of Murkwell. A country with no coughing. Let's go and see."),
    } },
  } },
  { set = "px_done" },
  { big = "THE WAY OUT IS OPEN" },
}

-- ---------------------------------------------------------------- the road, and the story guide

R.foes.px_tusker = { name = "SHAID TUSKER", tier = 12, shape = "brute", sprite = "px_tusker", family = "stalker", abilities = { { "lunge", 1 }, { "bite", 3 } } }
R.foes.px_sent_one = { name = "SENT ONE", tier = 13, shape = "quick", sprite = "stalker", family = "stalker", abilities = { { "claw", 4 }, { "lunge", 1 } } }
R.foes.px_cordon = { name = "CORDON ORDERLY", short = "ORDERLY", tier = 14, shape = "brute", sprite = "orderly", family = "staff", abilities = { { "baton", 4 }, { "needle", 1 } } }

R.encounters.px_field_1 = { foes = { "px_tusker" }, flee = true, bg = "grass" }
R.encounters.px_field_2 = { foes = { "px_gaunt_bat", "px_gaunt_bat", "px_gaunt_bat" }, flee = true, bg = "grass" }
R.encounters.px_field_3 = { foes = { "px_sent_one", "px_sent_one" }, flee = true, bg = "grass" }
R.encounters.px_field_4 = { foes = { "px_cordon", "px_cordon" }, flee = true, bg = "grass" }

R.field.shaid = { "px_field_1", "px_field_2", "px_field_3", "px_field_4" }

R.art.px_tusker = "A huge black boar of Shaid with too many tusks and a hide like old tar."

R.goals = {
  { done = "px_arrived", text = "Cross the Nevermore Portal", site = "blackpool", when = "hr_done" },
  { done = "px_ki_in", text = "Go west to Killerth", site = "killerth", when = "px_arrived" },
  { done = "px_ki_job", text = "Talk to Warden Kest", map = "px_killerth", x = 5, y = 3, when = "px_ki_in" },
  { done = "px_lamps", text = "Light the three ward lamps", map = "px_sending_1", x = 13, y = 14, when = "px_ki_job" },
  { done = "px_matron_down", text = "Find what took the hunters", map = "px_sending_2", x = 15, y = 6, when = "px_lamps" },
  { done = "px_tally", text = "Go back to Warden Kest", map = "px_killerth", x = 5, y = 3, when = "px_matron_down" },
  { done = "px_mu_in", text = "Take the tally to Murkwell", site = "murkwell", when = "px_tally" },
  { done = "px_pell_job", text = "Find Doctor Nye", map = "px_murkwell", x = 6, y = 11, when = "px_mu_in" },
  { done = "px_found_cask", text = "Clear the Sump", map = "px_sump", x = 21, y = 12, when = "px_pell_job" },
  { done = "px_paper", text = "Go back to Doctor Nye", map = "px_murkwell", x = 6, y = 11, when = "px_found_cask" },
  { done = "px_pe_in", text = "Enter Adaphis", site = "adaphis", when = "px_paper" },
  { done = "px_gutter_ok", text = "Find a way past the gates", map = "px_pelvic", x = 7, y = 9, when = "px_pe_in" },
  { done = "px_ward_seen", text = "Go down into the Gutter", map = "px_gutter_2", x = 9, y = 10, when = "px_gutter_ok" },
  { done = "px_alderman_down", text = "Clear the Spine Drain", map = "px_gutter_2", x = 21, y = 4, when = "px_ward_seen" },
  { done = "px_rb_job", text = "Find the laundry in the Ribs", map = "px_ribbed", x = 4, y = 10, when = "px_alderman_down" },
  { done = "px_form", text = "Get a form for the Tally Door", map = "px_works_1", x = 19, y = 5, when = "px_rb_job" },
  { done = "px_crake_down", text = "Find where the carts go", map = "px_works_2", x = 14, y = 6, when = "px_form" },
  { done = "px_ledger", text = "Read the cart ledger", map = "px_works_2", x = 4, y = 4, when = "px_crake_down" },
  { done = "px_cr_in", text = "Take the lift to the Cranial", map = "px_works_2", x = 24, y = 4, when = "px_ledger" },
  { done = "px_fab_ok", text = "Talk to the Chamberlain", map = "px_cranial", x = 14, y = 8, when = "px_cr_in" },
  { done = "px_token", text = "See King Fabian", map = "px_cranial", x = 13, y = 3, when = "px_fab_ok" },
  { done = "px_done", text = "Go to the Open Door Hospital", map = "px_cranial", x = 22, y = 6, when = "px_token" },
}

return R
