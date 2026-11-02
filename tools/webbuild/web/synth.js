// A small synth standing in for the Minecraft sounds. host.lua sends the name from sound_picks (coin, step, mon_rat_hurt)
// where it can, and the raw sound id where it can't, so each is sorted into a kind by the words in it.
"use strict";

window.BlightSynth = (() => {
  const MUTE_KEY = "blightmare.web.muted";
  const LOUDNESS = 0.16;
  let ctx = null, master = null, noiseBuffer = null;
  let muted = false;
  try { muted = localStorage.getItem(MUTE_KEY) === "1"; } catch {}

  function wake() {
    if (!ctx) {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (!AudioContextClass) return;
      ctx = new AudioContextClass();
      master = ctx.createGain();
      master.gain.value = muted ? 0 : LOUDNESS;
      master.connect(ctx.destination);
      noiseBuffer = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
      const data = noiseBuffer.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
      // iOS only opens the audio once something has played inside a touch
      const silence = ctx.createBufferSource();
      silence.buffer = ctx.createBuffer(1, 1, ctx.sampleRate);
      silence.connect(ctx.destination);
      silence.start(0);
    }
    if (ctx.state !== "running") ctx.resume();
  }

  function tone(type, from, to, at, length, volume) {
    const osc = ctx.createOscillator(), gain = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(from, at);
    osc.frequency.exponentialRampToValueAtTime(Math.max(20, to), at + length);
    gain.gain.setValueAtTime(volume, at);
    gain.gain.exponentialRampToValueAtTime(0.001, at + length);
    osc.connect(gain).connect(master);
    osc.start(at);
    osc.stop(at + length + 0.01);
  }

  function noise(at, length, volume, cutoff) {
    const source = ctx.createBufferSource(), filter = ctx.createBiquadFilter(), gain = ctx.createGain();
    source.buffer = noiseBuffer;
    source.loop = true;
    filter.type = "lowpass";
    filter.frequency.value = cutoff;
    gain.gain.setValueAtTime(volume, at);
    gain.gain.exponentialRampToValueAtTime(0.001, at + length);
    source.connect(filter).connect(gain).connect(master);
    source.start(at, Math.random() * 0.8);
    source.stop(at + length + 0.01);
  }

  function notes(type, list, gap, length, volume, p, at) {
    list.forEach((f, i) => tone(type, f * p, f * p, at + i * gap, length, volume));
  }

  const KINDS = {
    tap: (p, v, t) => tone("square", 660 * p, 520 * p, t, 0.04, 0.3 * v),
    page: (p, v, t) => noise(t, 0.07, 0.35 * v, 2600),
    step: (p, v, t) => noise(t, 0.09, 0.5 * v, 420 * p),
    wall: (p, v, t) => { noise(t, 0.08, 0.6 * v, 300); tone("sine", 110, 70, t, 0.08, 0.4 * v); },
    hit: (p, v, t) => { noise(t, 0.12, 0.8 * v, 1800 * p); tone("square", 180 * p, 70 * p, t, 0.1, 0.35 * v); },
    hurt: (p, v, t) => { tone("sawtooth", 300 * p, 90 * p, t, 0.2, 0.4 * v); noise(t, 0.1, 0.4 * v, 1000); },
    miss: (p, v, t) => noise(t, 0.14, 0.3 * v, 4200),
    block: (p, v, t) => { tone("square", 220 * p, 200 * p, t, 0.07, 0.35 * v); noise(t, 0.05, 0.4 * v, 2400); },
    boom: (p, v, t) => { noise(t, 0.5, 1 * v, 500); tone("sine", 90, 35, t, 0.45, 0.7 * v); },
    die: (p, v, t) => { tone("sawtooth", 240 * p, 40 * p, t, 0.45, 0.45 * v); noise(t, 0.3, 0.3 * v, 700); },
    heal: (p, v, t) => notes("sine", [523, 659, 784, 1047], 0.07, 0.2, 0.4 * v, p, t),
    coin: (p, v, t) => notes("square", [988, 1319], 0.07, 0.12, 0.25 * v, p, t),
    pickup: (p, v, t) => notes("triangle", [587, 880], 0.06, 0.1, 0.45 * v, p, t),
    level: (p, v, t) => notes("square", [523, 659, 784, 1047, 1319], 0.09, 0.2, 0.25 * v, p, t),
    win: (p, v, t) => notes("triangle", [392, 523, 659, 784], 0.12, 0.3, 0.5 * v, p, t),
    lose: (p, v, t) => notes("triangle", [392, 330, 262, 196], 0.16, 0.35, 0.5 * v, p, t),
    spell: (p, v, t) => { tone("sine", 300 * p, 1400 * p, t, 0.25, 0.35 * v); tone("triangle", 450 * p, 2000 * p, t + 0.03, 0.22, 0.2 * v); },
    door: (p, v, t) => { noise(t, 0.16, 0.5 * v, 700); tone("sine", 140, 90, t + 0.03, 0.14, 0.4 * v); },
    chest: (p, v, t) => { noise(t, 0.12, 0.4 * v, 1200); notes("triangle", [440, 554], 0.06, 0.12, 0.3 * v, p, t + 0.05); },
    alarm: (p, v, t) => notes("sawtooth", [220, 233], 0.16, 0.16, 0.25 * v, p, t),
    error: (p, v, t) => notes("square", [160, 130], 0.08, 0.09, 0.25 * v, p, t),
    note: (p, v, t) => tone("triangle", 440 * p, 440 * p, t, 0.2, 0.4 * v),
    // the opening's own
    chain: (p, v, t) => { noise(t, 0.5, 0.35 * v, 900); notes("square", [196, 185, 175], 0.12, 0.1, 0.12 * v, p, t); },
    chime: (p, v, t) => { tone("sine", 880 * p, 880 * p, t, 1.2, 0.3 * v); tone("sine", 1320 * p, 1320 * p, t, 0.8, 0.12 * v); },
    wings: (p, v, t) => { for (let i = 0; i < 4; i++) noise(t + i * 0.18, 0.14, 0.45 * v, 600); },
    glow: (p, v, t) => notes("sine", [523, 784, 1047, 1568], 0.1, 0.6, 0.25 * v, p, t),
    eerie: (p, v, t) => { tone("sine", 220 * p, 180 * p, t, 1.4, 0.3 * v); tone("sine", 233 * p, 190 * p, t, 1.4, 0.2 * v); noise(t, 1.2, 0.15 * v, 500); },
    snuff: (p, v, t) => noise(t, 0.3, 0.3 * v, 3000),
    sting: (p, v, t) => { tone("sawtooth", 110, 55, t, 1.8, 0.35 * v); tone("sine", 82, 41, t, 2.2, 0.6 * v); noise(t, 1.5, 0.3 * v, 300); },
    flame: (p, v, t) => { noise(t, 0.25, 0.4 * v, 1600); tone("sine", 300 * p, 500 * p, t, 0.15, 0.15 * v); },
    whistle: (p, v, t) => tone("sine", 196 * p, 196 * p, t, 2.5, 0.35 * v),
    bell: (p, v, t) => { tone("sine", 523 * p, 523 * p, t, 2.2, 0.4 * v); tone("sine", 1046 * p, 1046 * p, t, 1.4, 0.15 * v); tone("sine", 1567 * p, 1567 * p, t, 0.8, 0.08 * v); },
    quiet: (p, v, t) => noise(t, 1.5, 0.08 * v, 1500),
  };

  // Music under the opening: a slow chord or figure on a loop, until the next piece or a stop.
  const BEDS = {
    intro_music_legend: { every: 5, type: "sine", parts: [[110, 165, 220, 262], [98, 147, 196, 247], [87, 131, 175, 220], [98, 147, 196, 233]] },
    intro_music_map: { every: 2.4, type: "triangle", parts: [[262, 330, 392, 523], [294, 349, 440, 587], [247, 330, 392, 494], [262, 330, 392, 523]], arpeggio: 0.3 },
    intro_music_dread: { every: 4, type: "sawtooth", parts: [[55, 58], [52, 55], [55, 62], [49, 52]], noise: true },
    intro_music_town: { every: 2.4, type: "triangle", parts: [[659, 523, 392, 523], [587, 494, 392, 494], [523, 440, 330, 440], [587, 494, 392, 330]], arpeggio: 0.6 },
  };
  let bed = null;

  function stopMusic() {
    if (!bed) return;
    clearInterval(bed.timer);
    bed.gain.gain.setTargetAtTime(0.0001, ctx.currentTime, 0.5);
    bed = null;
  }

  function startMusic(name, v) {
    stopMusic();
    const def = BEDS[name];
    if (!def) return;
    const gain = ctx.createGain();
    gain.gain.value = 0.5 * v;
    gain.connect(master);
    let i = 0;
    const play = () => {
      const at = ctx.currentTime + 0.05, chord = def.parts[i++ % def.parts.length];
      chord.forEach((f, n) => {
        const start = at + (def.arpeggio ? n * def.arpeggio : 0), length = def.arpeggio ? def.arpeggio * 2.5 : def.every * 1.2;
        const osc = ctx.createOscillator(), g = ctx.createGain();
        osc.type = def.type;
        osc.frequency.value = f;
        g.gain.setValueAtTime(0.0001, start);
        g.gain.exponentialRampToValueAtTime(def.arpeggio ? 0.3 : 0.18, start + (def.arpeggio ? 0.02 : 1));
        g.gain.exponentialRampToValueAtTime(0.0001, start + length);
        osc.connect(g).connect(gain);
        osc.start(start);
        osc.stop(start + length + 0.05);
      });
      if (def.noise) {
        const source = ctx.createBufferSource(), filter = ctx.createBiquadFilter(), g = ctx.createGain();
        source.buffer = noiseBuffer;
        source.loop = true;
        filter.type = "lowpass";
        filter.frequency.value = 260;
        g.gain.setValueAtTime(0.0001, at);
        g.gain.exponentialRampToValueAtTime(0.25, at + 1.5);
        g.gain.exponentialRampToValueAtTime(0.0001, at + def.every * 1.2);
        source.connect(filter).connect(g).connect(gain);
        source.start(at);
        source.stop(at + def.every * 1.2 + 0.05);
      }
    };
    play();
    bed = { gain, timer: setInterval(play, def.every * 1000) };
  }

  const RULES = [
    [/^intro_chain/, "chain"],
    [/^intro_god_fade/, "chime"],
    [/^intro_raven/, "wings"],
    [/^intro_(empire_glow|dream_rise)/, "glow"],
    [/^intro_(nightmare|grey)/, "eerie"],
    [/^intro_candle_out/, "snuff"],
    [/^intro_(sting_blightmare|title|wall_done)/, "sting"],
    [/^intro_wall_course/, "wall"],
    [/^intro_refugees/, "step"],
    [/^intro_lamp/, "flame"],
    [/^intro_(map_open|book)/, "page"],
    [/^intro_label/, "tap"],
    [/^intro_(window|knock|door)/, "door"],
    [/^intro_sting_one/, "whistle"],
    [/^intro_bell/, "bell"],
    [/^intro_dusk/, "quiet"],
    [/^mon_.*_die$|monster_die|death|^resign|robot_death/, "die"],
    [/^mon_.*_hurt$|monster_hurt|player_hurt|hurt|damage/, "hurt"],
    [/^mon_.*_attack$|^sword|^hit|attack|^smash|^thrust|^clang/, "hit"],
    [/level_up|levelup|powerup|achievement|^ui_rank|level_clear/, "level"],
    [/^win|success|completion_major/, "win"],
    [/^lose|fail/, "lose"],
    [/coin|payout|chip|gold|orb/, "coin"],
    [/heal|potion|drink|regen/, "heal"],
    [/^step|^wagon|^march|footstep/, "step"],
    [/^wall|bump/, "wall"],
    [/^miss|^swish|^flee/, "miss"],
    [/^block|shield/, "block"],
    [/cave_in|^crush|^boom|^bomb|^cannon|explo/, "boom"],
    [/spell|curse|zap|laser|teleport|sting|beacon/, "spell"],
    [/door|^knock/, "door"],
    [/chest|unlock|^lock/, "chest"],
    [/pickup|^save/, "pickup"],
    [/telegraph|battle|^horn/, "alarm"],
    [/ui_error|error/, "error"],
    [/page|flip/, "page"],
    [/^note$/, "note"],
  ];

  const kindCache = new Map();
  function kindOf(name) {
    let kind = kindCache.get(name);
    if (!kind) {
      const rule = RULES.find(([pattern]) => pattern.test(name));
      kind = rule ? rule[1] : "tap";
      kindCache.set(name, kind);
    }
    return kind;
  }

  return {
    wake,
    kindOf,
    play(name, volume, pitch) {
      if (!ctx || ctx.state !== "running") return;
      if (name === "__stop") return stopMusic();
      if (BEDS[name]) return startMusic(name, Math.min(1, volume || 0.7));
      if (muted) return;
      KINDS[kindOf(name)](pitch || 1, Math.min(1, volume || 0.7), ctx.currentTime + 0.001);
    },
    isMuted: () => muted,
    setMuted(on) {
      muted = on;
      try { localStorage.setItem(MUTE_KEY, on ? "1" : "0"); } catch {}
      if (master) master.gain.value = on ? 0 : LOUDNESS;
    },
  };
})();
