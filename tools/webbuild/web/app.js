// BLIGHTMARE in a browser: real Lua 5.1 in wasm runs the real program under host.lua, and this page is the monitor.
// Each frame, if a timer is due or a tap is waiting, __web.step runs the game until it waits again and hands back what
// it did. See `step` in host.lua for the records.
"use strict";

/** An error as words: the message, then the stack. Safari's stack leaves the message out, so the stack alone hides what happened. */
function describeError(e) {
  if (!e || typeof e !== "object") return String(e);
  const message = e.message || String(e);
  const stack = e.stack || "";
  return stack.includes(message) ? stack : (message + "\n" + stack).trim();
}

const DAMAGED = "The game files are damaged. Tap Restart to fetch them again. Your saved game is safe.";

(async () => {
  const COLS = 121, ROWS = 81;
  const FS_PREFIX = "blightmare.web.fs/";
  const LUA_GLOBALSINDEX = -10002;
  const MULTRET = -1;

  const wall = document.getElementById("wall");
  const note = document.getElementById("note");
  const crashBox = document.getElementById("crash");
  const crashText = document.getElementById("crashText");
  const muteButton = document.getElementById("mute");
  const cursorEl = document.getElementById("cursor");
  const hintEl = document.getElementById("keys");
  const panelEl = document.getElementById("panel");
  const panelBody = document.getElementById("panelBody");
  const installEl = document.getElementById("install");
  const insetProbe = document.getElementById("insets");
  const coarsePointer = window.matchMedia("(pointer: coarse)");
  const PANEL_FREE_PX = 160, PANEL_CELL_PX = 7, PANEL_GAP = 4;
  let cursorBox = [0, 0, 0, 0];
  let panelWanted = false, luaRunning = false;
  const synth = window.BlightSynth;
  const startedAt = performance.now();
  const decoder = new TextDecoder("utf-8");

  const stats = { loadMs: 0, ticks: 0, stepMs: 0, stepMax: 0, stepSamples: [], drawMs: 0, drawMax: 0, draws: 0, rowsDrawn: 0, sounds: 0, crash: null };

  function showCrash(text) {
    if (stats.crash) return;
    stats.crash = text;
    crashText.textContent = text;
    crashBox.style.display = "block";
    note.style.display = "none";
  }
  document.getElementById("crashReload").addEventListener("click", () => location.reload());
  window.addEventListener("error", (e) => showCrash(e.error ? describeError(e.error) : String(e.message)));
  window.addEventListener("unhandledrejection", (e) => showCrash(describeError(e.reason)));

  // ------------------------------------------------------------------ the picture

  const chars = new Uint8Array(COLS * ROWS).fill(32);
  const fgs = new Uint8Array(COLS * ROWS);
  const bgs = new Uint8Array(COLS * ROWS).fill(15);
  const palette = new Array(16).fill("#000");
  const dirtyLo = new Int16Array(ROWS).fill(COLS);
  const dirtyHi = new Int16Array(ROWS).fill(-1);
  let anyDirty = false;

  const ctx = wall.getContext("2d", { alpha: false });
  let cw = 2, ch = 3;
  const atlas = document.createElement("canvas");
  const atlasCtx = atlas.getContext("2d");
  let glyphReady = new Uint8Array(16 * 256);

  function markAll() {
    dirtyLo.fill(0);
    dirtyHi.fill(COLS - 1);
    anyDirty = true;
  }

  function resetAtlas() {
    atlas.width = cw * 256;
    atlas.height = ch * 16;
    glyphReady.fill(0);
  }

  function hexColour(rgb) {
    return "#" + rgb.toString(16).padStart(6, "0");
  }

  function setPalette(slot, rgb) {
    palette[slot] = hexColour(rgb);
    for (let i = 0; i < 256; i++) glyphReady[slot * 256 + i] = 0;
    atlasCtx.clearRect(0, slot * ch, atlas.width, ch);
    markAll();
  }

  function glyph(code, slot) {
    const key = slot * 256 + code;
    const sx = code * cw, sy = slot * ch;
    if (!glyphReady[key]) {
      glyphReady[key] = 1;
      atlasCtx.fillStyle = palette[slot];
      if (code >= 128 && code < 160) {
        // the teletext blocks: bits run across, then down, and bit 32 swaps ink and paper
        const bits = code & 31;
        const xs = [0, cw >> 1, cw], ys = [0, Math.round(ch / 3), Math.round(ch * 2 / 3), ch];
        for (let i = 0; i < 6; i++) {
          if (bits >> i & 1) {
            const c = i % 2, r = i >> 1;
            atlasCtx.fillRect(sx + xs[c], sy + ys[r], xs[c + 1] - xs[c], ys[r + 1] - ys[r]);
          }
        }
      } else {
        atlasCtx.font = "600 " + Math.min(ch * 1.02, cw / 0.56).toFixed(1) + "px ui-monospace, 'DejaVu Sans Mono', Menlo, Consolas, 'Liberation Mono', monospace";
        atlasCtx.textAlign = "center";
        atlasCtx.textBaseline = "middle";
        atlasCtx.save();
        atlasCtx.beginPath();
        atlasCtx.rect(sx, sy, cw, ch);
        atlasCtx.clip();
        atlasCtx.fillText(String.fromCharCode(code), sx + cw / 2, sy + ch * 0.54);
        atlasCtx.restore();
      }
    }
    return sx;
  }

  // The keyboard cursor and the key hint sit over and beside the canvas, so the game's picture never has to be repainted for them.
  function placeCursor() {
    const [x, y, w, h] = cursorBox;
    if (!w) {
      cursorEl.style.display = "none";
      return;
    }
    const box = wall.getBoundingClientRect();
    const cellW = box.width / COLS, cellH = box.height / ROWS;
    const thick = Math.max(2, Math.round(cellW));
    cursorEl.style.display = "block";
    cursorEl.style.left = box.left + x * cellW - thick + "px";
    cursorEl.style.top = box.top + y * cellH - thick + "px";
    cursorEl.style.width = w * cellW + "px";
    cursorEl.style.height = h * cellH + "px";
    cursorEl.style.borderWidth = thick + "px";
  }

  function placeHint() {
    const box = wall.getBoundingClientRect();
    const side = box.left, below = window.innerHeight - box.bottom;
    hintEl.className = panelWanted ? "" : side >= 170 ? "side" : below >= 26 ? "under" : "";
  }

  function setPanel(on) {
    if (on === panelWanted) return;
    panelWanted = on;
    panelEl.style.display = on ? "flex" : "none";
    if (luaRunning) inputs.push("panel " + (on ? 1 : 0));
  }

  function setCells(newW, newH) {
    if (newW === cw && newH === ch && wall.width === newW * COLS) return;
    cw = newW;
    ch = newH;
    wall.width = newW * COLS;
    wall.height = newH * ROWS;
    resetAtlas();
    markAll();
  }

  /** On a phone the wall keeps a true 2:3 cell and clears the notch, and the room left over goes to the panel. */
  function fitPhone(dpr, inset, across, down, panel) {
    const cell = Math.min(across / COLS, down * 2 / 3 / ROWS);
    const w = cell * COLS, h = cell * 1.5 * ROWS;
    const stacked = down - h >= across - w;
    wall.style.width = w + "px";
    wall.style.height = h + "px";
    let left = inset.left + (across - w) / 2, top = inset.top + (down - h) / 2;
    if (panel && stacked) {
      top = inset.top;
      panelEl.style.left = inset.left + "px";
      panelEl.style.top = top + h + PANEL_GAP + "px";
      panelEl.style.width = across + "px";
      panelEl.style.height = down - h - PANEL_GAP + "px";
    } else if (panel) {
      left = inset.left;
      panelEl.style.left = left + w + PANEL_GAP + "px";
      panelEl.style.top = inset.top + "px";
      panelEl.style.width = across - w - PANEL_GAP + "px";
      panelEl.style.height = down + "px";
    }
    wall.style.left = left + "px";
    wall.style.top = top + "px";
    if (panel) {
      const box = panelEl.getBoundingClientRect();
      muteButton.style.left = box.right - 40 + "px";
      muteButton.style.top = box.top + 2 + "px";
      muteButton.style.right = "auto";
    }
    // whole pixels can't always make 2:3, so the canvas holds the nearest even cell and the browser scales it the last little way
    const wanted = cell * dpr;
    const low = Math.max(2, Math.floor(wanted / 2) * 2);
    const newW = wanted - low <= low + 2 - wanted ? low : low + 2;
    setCells(newW, newW * 1.5);
  }

  function fit() {
    const dpr = window.devicePixelRatio || 1;
    const across = Math.floor(window.innerWidth * dpr), down = Math.floor(window.innerHeight * dpr);
    let newW = Math.max(2, Math.floor(Math.min(across / COLS, down * 2 / 3 / ROWS)));
    let newH = Math.round(newW * 1.5);
    if (newH * ROWS > down) newH = Math.max(3, Math.floor(down / ROWS));

    const view = window.visualViewport;
    const box = getComputedStyle(insetProbe);
    const inset = {
      top: parseFloat(box.paddingTop) || 0, right: parseFloat(box.paddingRight) || 0,
      bottom: parseFloat(box.paddingBottom) || 0, left: parseFloat(box.paddingLeft) || 0,
    };
    const roomW = (view ? view.width : window.innerWidth) - inset.left - inset.right;
    const roomH = (view ? view.height : window.innerHeight) - inset.top - inset.bottom;
    const coarse = coarsePointer.matches;
    const exact = Math.min(roomW / COLS, roomH * 2 / 3 / ROWS);
    const free = Math.max(roomH - exact * 1.5 * ROWS, roomW - exact * COLS);
    const panel = (coarse || newH / dpr < PANEL_CELL_PX) && free >= PANEL_FREE_PX;
    const phone = coarse || panel;
    document.documentElement.classList.toggle("phone", phone);
    setPanel(panel);
    if (phone) {
      fitPhone(dpr, inset, roomW, roomH, panel);
    } else {
      wall.style.left = wall.style.top = "";
      wall.style.width = newW * COLS / dpr + "px";
      wall.style.height = newH * ROWS / dpr + "px";
      setCells(newW, newH);
    }
    if (!panel) muteButton.style.left = muteButton.style.top = muteButton.style.right = "";
    placeCursor();
    placeHint();
  }

  function draw() {
    if (!anyDirty) return;
    anyDirty = false;
    const t0 = performance.now();
    let rows = 0;
    for (let y = 0; y < ROWS; y++) {
      const hi = dirtyHi[y];
      if (hi < 0) continue;
      const lo = dirtyLo[y];
      dirtyHi[y] = -1;
      dirtyLo[y] = COLS;
      rows++;
      const base = y * COLS, py = y * ch;
      // paper in runs of one colour, then ink
      let x = lo;
      while (x <= hi) {
        const colour = bgs[base + x];
        let end = x + 1;
        while (end <= hi && bgs[base + end] === colour) end++;
        ctx.fillStyle = palette[colour];
        ctx.fillRect(x * cw, py, (end - x) * cw, ch);
        x = end;
      }
      for (x = lo; x <= hi; x++) {
        const code = chars[base + x];
        if (code === 32 || code === 0 || code === 128) continue;
        const slot = fgs[base + x];
        const sx = glyph(code, slot);
        ctx.drawImage(atlas, sx, slot * ch, cw, ch, x * cw, py, cw, ch);
      }
    }
    const ms = performance.now() - t0;
    stats.drawMs += ms;
    stats.draws++;
    stats.rowsDrawn += rows;
    if (ms > stats.drawMax) stats.drawMax = ms;
  }

  function hexDigit(b) {
    return b >= 97 ? b - 87 : b >= 65 ? b - 55 : b - 48;
  }

  function blit(heap, at, x, y, n) {
    const row = y - 1;
    if (row < 0 || row >= ROWS) return;
    const base = row * COLS;
    let lo = COLS, hi = -1;
    for (let i = 0; i < n; i++) {
      const col = x - 1 + i;
      if (col < 0 || col >= COLS) continue;
      const cell = base + col;
      const code = heap[at + i], fg = hexDigit(heap[at + n + i]), bg = hexDigit(heap[at + n * 2 + i]);
      if (chars[cell] !== code || fgs[cell] !== fg || bgs[cell] !== bg) {
        chars[cell] = code; fgs[cell] = fg; bgs[cell] = bg;
        if (col < lo) lo = col;
        if (col > hi) hi = col;
      }
    }
    if (hi >= 0) {
      if (lo < dirtyLo[row]) dirtyLo[row] = lo;
      if (hi > dirtyHi[row]) dirtyHi[row] = hi;
      anyDirty = true;
    }
  }

  function clearWall(bg) {
    chars.fill(32);
    fgs.fill(0);
    bgs.fill(bg);
    markAll();
  }

  function scrollWall(n, bg) {
    const shift = n * COLS;
    if (n > 0) {
      chars.copyWithin(0, shift); fgs.copyWithin(0, shift); bgs.copyWithin(0, shift);
      chars.fill(32, chars.length - shift); fgs.fill(0, chars.length - shift); bgs.fill(bg, chars.length - shift);
    } else if (n < 0) {
      chars.copyWithin(-shift, 0, chars.length + shift); fgs.copyWithin(-shift, 0, chars.length + shift); bgs.copyWithin(-shift, 0, chars.length + shift);
      chars.fill(32, 0, -shift); fgs.fill(0, 0, -shift); bgs.fill(bg, 0, -shift);
    }
    markAll();
  }

  fit();
  window.addEventListener("resize", fit);
  window.addEventListener("orientationchange", () => {
    fit();
    // iOS reports the new size a little after the turn
    setTimeout(fit, 120);
    setTimeout(fit, 400);
  });
  if (window.visualViewport) window.visualViewport.addEventListener("resize", fit);
  coarsePointer.addEventListener("change", fit);
  window.addEventListener("pageshow", fit);

  // ------------------------------------------------------------------ Lua

  const fetched = (name) => fetch(name).then((r) => {
    if (!r.ok) throw new Error(name + ": " + r.status);
    return r.arrayBuffer();
  });
  const [bundleBytes, compiled] = await Promise.all([
    fetched("bundle.txt").then((b) => new Uint8Array(b)),
    fetched("lua-5.1.5.wasm").then((b) => WebAssembly.compile(b)),
  ]);

  // The glue wants its exports back from this call, so it's compiled ahead and only instantiated here.
  const module = await new Promise((resolve, reject) => {
    const m = {
      print: (t) => console.log(t),
      printErr: (t) => console.error(t),
      locateFile: (name) => name,
      instantiateWasm(imports, done) {
        const instance = new WebAssembly.Instance(compiled, imports);
        done(instance, compiled);
        return instance.exports;
      },
      onRuntimeInitialized: () => resolve(m),
      onAbort: (what) => reject(new Error("Lua aborted: " + what)),
    };
    window.glue(m);
  });

  const api = {
    newstate: module._luaL_newstate, openlibs: module._luaL_openlibs, loadbuffer: module._luaL_loadbuffer,
    pcall: module._lua_pcall, getfield: module._lua_getfield, settop: module._lua_settop,
    pushstring: module._lua_pushstring, tolstring: module._lua_tolstring,
  };
  const heap = () => module.HEAPU8;
  const L = api.newstate();
  api.openlibs(L);

  // A scratch buffer in wasm memory for anything crossing over. Bytes, not text: nothing goes through UTF-8.
  let scratch = 0, scratchSize = 0;
  function bytesIn(bytes) {
    if (bytes.length + 1 > scratchSize) {
      scratchSize = Math.max(1 << 16, (bytes.length + 1) * 2);
      scratch = module._malloc(scratchSize);
    }
    heap().set(bytes, scratch);
    heap()[scratch + bytes.length] = 0;
    return scratch;
  }

  function latin1(text) {
    const bytes = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i);
    return bytes;
  }

  function latin1Of(view) {
    let text = "";
    for (let i = 0; i < view.length; i += 8192) text += String.fromCharCode.apply(null, view.subarray(i, i + 8192));
    return text;
  }

  function pushBytes(bytes) { api.pushstring(L, bytesIn(bytes)); }

  // A short name kept in its own malloc, for the calls that take a C string.
  const names = new Map();
  function cname(text) {
    let at = names.get(text);
    if (!at) {
      at = module._malloc(text.length + 1);
      heap().set(latin1(text), at);
      heap()[at + text.length] = 0;
      names.set(text, at);
    }
    return at;
  }

  function luaText(index) {
    const at = api.tolstring(L, index, 0);
    if (!at) return "(no message)";
    const h = heap();
    let end = at;
    while (h[end]) end++;
    return decoder.decode(h.subarray(at, end));
  }

  function runChunk(bytes, name) {
    const at = bytesIn(bytes);
    let status = api.loadbuffer(L, at, bytes.length, cname(name));
    if (status === 0) status = api.pcall(L, 0, 0, 0);
    if (status !== 0) {
      const message = luaText(-1);
      api.settop(L, 0);
      throw new Error(message);
    }
  }

  /** Call __web.<fn>; leaves one result on the stack if results is 1. */
  function webCall(fn, args, results) {
    api.getfield(L, LUA_GLOBALSINDEX, cname("__web"));
    api.getfield(L, -1, cname(fn));
    for (const arg of args) pushBytes(typeof arg === "string" ? latin1(arg) : arg);
    const status = api.pcall(L, args.length, results, 0);
    if (status !== 0) {
      const message = luaText(-1);
      api.settop(L, 0);
      throw new Error(message);
    }
  }

  // ------------------------------------------------------------------ files

  // Everything is checked here, before Lua sees a byte: a damaged file must say so, and not look like a bug in the game.
  async function readIndex() {
    const named = "bundle.txt".match(/\.([0-9a-f]{10})\.txt$/);
    if (named && window.crypto && crypto.subtle) { // no crypto.subtle on plain http, where the length still counts
      const sum = new Uint8Array(await crypto.subtle.digest("SHA-256", bundleBytes));
      const hex = Array.from(sum.subarray(0, 5), (b) => b.toString(16).padStart(2, "0")).join("");
      if (hex !== named[1]) throw new Error("the bundle's hash is " + hex + ", not " + named[1]);
    }
    const end = bundleBytes.indexOf(10);
    const list = JSON.parse(decoder.decode(bundleBytes.subarray(0, end)));
    const length = list.reduce((sum, [, n]) => sum + n, end + 1);
    if (length !== bundleBytes.length) throw new Error("the bundle is " + bundleBytes.length + " bytes, not " + length);
    return [list, end];
  }

  let index, headerEnd;
  try {
    [index, headerEnd] = await readIndex();
  } catch (e) {
    console.error("damaged bundle: " + e.message);
    // Its hashed name would bring the same bad copy back from the offline cache for ever, so that goes first.
    try {
      for (const name of await caches.keys()) if (name.startsWith("blightmare-")) await caches.delete(name);
    } catch {}
    throw Object.assign(new Error(DAMAGED), { damaged: true });
  }
  let offset = headerEnd + 1;
  const bundle = new Map();
  for (const [path, length] of index) {
    bundle.set(path, bundleBytes.subarray(offset, offset + length));
    offset += length;
  }

  runChunk(bundle.get("__host.lua"), "@host.lua");
  for (const [path, bytes] of bundle) {
    if (path !== "__host.lua") webCall("addFile", [path, bytes], 0);
    api.settop(L, 0);
  }

  function restoreFiles() {
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key.startsWith(FS_PREFIX)) {
          webCall("restoreFile", [key.slice(FS_PREFIX.length), localStorage.getItem(key)], 0);
          api.settop(L, 0);
        }
      }
    } catch (e) {
      console.warn("no saved games: " + e);
    }
  }

  // How far this browser's game has got, for the players page. Only from the real site, at most once a minute, and a
  // failure is no matter: the next save tries again.
  const DEVICE_KEY = "blightmare.web.device", REPORT_MS = 60000;
  let lastReport = 0;
  function reportProgress(text) {
    if (!/(^|\.)elawondra\.com$/.test(location.hostname)) return;
    const t = Date.now();
    if (t - lastReport < REPORT_MS) return;
    lastReport = t;
    let device = null;
    try {
      device = localStorage.getItem(DEVICE_KEY);
      if (!device) {
        device = Array.from(crypto.getRandomValues(new Uint8Array(12)), (b) => b.toString(16).padStart(2, "0")).join("");
        localStorage.setItem(DEVICE_KEY, device);
      }
    } catch { return; }
    let p;
    try { p = JSON.parse(text); } catch { return; }
    const app = navigator.standalone === true || window.matchMedia("(display-mode: standalone)").matches;
    fetch("/api/blightmare/progress", {
      method: "POST", headers: { "content-type": "application/json" }, keepalive: true,
      body: JSON.stringify({ ...p, device, app }),
    }).catch(() => {});
  }

  function saveFile(path, text) {
    try {
      localStorage.setItem(FS_PREFIX + path, text);
    } catch (e) {
      console.warn("could not keep " + path + ": " + e);
      stats.saveError = String(e);
    }
  }

  function dropFile(path) {
    try { localStorage.removeItem(FS_PREFIX + path); } catch {}
  }

  // ------------------------------------------------------------------ the loop

  let inputs = [];
  let nextDue = 0;
  let stopped = false;
  let shownUp = false;

  function readNumber(h, at, stop) {
    let value = 0, sign = 1;
    if (h[at] === 45) { sign = -1; at++; }
    for (; at < stop; at++) value = value * 10 + h[at] - 48;
    return value * sign;
  }

  function apply(at, length) {
    const h = heap();
    const end = at + length;
    while (at < end) {
      const type = h[at];
      let lineEnd = at + 1;
      while (h[lineEnd] !== 10) lineEnd++;
      const fields = [];
      let start = at + 1;
      for (let i = at + 1; i <= lineEnd; i++) {
        if (i === lineEnd || (h[i] === 44 && !(type === 83 && fields.length >= 2))) {
          fields.push([start, i]);
          start = i + 1;
        }
      }
      const num = (i) => readNumber(h, fields[i][0], fields[i][1]);
      at = lineEnd + 1;
      switch (type) {
        case 66: { // B
          const n = num(2);
          blit(h, at, num(0), num(1), n);
          at += n * 3;
          break;
        }
        case 67: clearWall(num(0)); break; // C
        case 82: scrollWall(num(0), num(1)); break; // R
        case 80: setPalette(num(0), num(1)); break; // P
        case 83: { // S
          const text = (i) => latin1Of(h.subarray(fields[i][0], fields[i][1]));
          stats.sounds++;
          synth.play(text(2), parseFloat(text(0)), parseFloat(text(1)));
          break;
        }
        case 76: { // L
          const n = num(0);
          console.log("[lua] " + latin1Of(h.subarray(at, at + n)));
          at += n;
          break;
        }
        case 87: { // W
          const pn = num(0), n = num(1);
          saveFile(latin1Of(h.subarray(at, at + pn)), latin1Of(h.subarray(at + pn, at + pn + n)));
          at += pn + n;
          break;
        }
        case 68: { // D
          const pn = num(0);
          dropFile(latin1Of(h.subarray(at, at + pn)));
          at += pn;
          break;
        }
        case 69: { // E
          const n = num(0);
          showCrash(latin1Of(h.subarray(at, at + n)));
          stopped = true;
          at += n;
          break;
        }
        case 81: stopped = true; showCrash("The game has shut down."); break; // Q
        case 74: { // J
          const n = num(0);
          showPanel(JSON.parse(latin1Of(h.subarray(at, at + n))));
          at += n;
          break;
        }
        case 71: { // G
          const n = num(0);
          reportProgress(latin1Of(h.subarray(at, at + n)));
          at += n;
          break;
        }
        case 75: cursorBox = [num(0), num(1), num(2), num(3)]; placeCursor(); break; // K
        case 78: nextDue = num(0); break; // N
        default:
          throw new Error("bad record from Lua: " + type);
      }
    }
  }

  function step() {
    const t0 = performance.now();
    const input = inputs.join("\n");
    inputs = [];
    webCall("step", [String(Date.now()), input], 1);
    const at = api.tolstring(L, -1, 0);
    // the result begins with its own length, so it may hold any byte
    const h = heap();
    let start = at, length = 0;
    while (h[start] !== 10) length = length * 10 + h[start++] - 48;
    start++;
    apply(start, length);
    api.settop(L, 0);
    const ms = performance.now() - t0;
    stats.ticks++;
    stats.stepMs += ms;
    if (ms > stats.stepMax) stats.stepMax = ms;
    if (stats.stepSamples.length < 20000) stats.stepSamples.push(ms);
  }

  function safeStep() {
    if (stopped) return;
    try {
      step();
    } catch (e) {
      stopped = true;
      showCrash(describeError(e));
    }
    if (!shownUp && anyDirty) {
      shownUp = true;
      note.style.display = "none";
      stats.loadMs = performance.now(); // from navigation
      stats.bootMs = performance.now() - startedAt;
    }
  }

  function frame() {
    if (!stopped && (inputs.length > 0 || Date.now() >= nextDue)) safeStep();
    draw();
    requestAnimationFrame(frame);
  }

  function tap(x, y) {
    inputs.push("touch " + x + " " + y);
    safeStep();
    draw();
  }

  wall.addEventListener("pointerdown", (e) => {
    e.preventDefault();
    synth.wake();
    if (e.button > 0) return;
    const box = wall.getBoundingClientRect();
    const x = Math.floor((e.clientX - box.left) / box.width * COLS) + 1;
    const y = Math.floor((e.clientY - box.top) / box.height * ROWS) + 1;
    if (x >= 1 && x <= COLS && y >= 1 && y <= ROWS) tap(x, y);
  });
  wall.addEventListener("contextmenu", (e) => e.preventDefault());

  // Pinching, double taps and the rubber band all belong to the page, and the page doesn't want them. The panel may still scroll.
  for (const name of ["gesturestart", "gesturechange", "gestureend", "dblclick"]) {
    document.addEventListener(name, (e) => e.preventDefault(), { passive: false });
  }
  document.addEventListener("touchmove", (e) => {
    if (!(e.target.closest && e.target.closest("#panelBody")) || e.touches.length > 1) e.preventDefault();
  }, { passive: false });
  // iOS opens its audio only inside a gesture it counts, and a call can shut it again, so every touch has another go
  for (const name of ["touchend", "click"]) window.addEventListener(name, () => synth.wake(), { capture: true, passive: true });

  // ------------------------------------------------------------------ the phone panel

  const esc = (text) => String(text ?? "").replace(/[&<>"]/g, (c) => "&#" + c.charCodeAt(0) + ";");
  const button = (id, label, kind = "", right = null) =>
    `<button type="button" class="pb ${kind}" data-id="${esc(id)}"><span>${esc(label)}</span>${right == null ? "" : `<b>${esc(right)}</b>`}</button>`;
  const bar = (now, top, kind) => {
    const share = top > 0 ? Math.max(0, Math.min(1, now / top)) : 0;
    const shade = kind || (share > 0.5 ? "" : share > 0.25 ? "low" : "bad");
    return `<div class="bar ${shade}"><i style="width:${Math.round(share * 100)}%"></i></div>`;
  };
  const member = (m) => `<div class="who${m.active ? " on" : ""}"><div><span>${esc(m.name)}${m.lvl ? " LV " + m.lvl : ""}</span>`
    + `<span>HP ${m.hp}/${m.maxHp}${m.maxMp ? ` MP ${m.mp}/${m.maxMp}` : ""}</span></div>${bar(m.hp, m.maxHp)}${m.maxMp ? bar(m.mp, m.maxMp, "mp") : ""}</div>`;
  const rows = (list) => (list || []).map((r) => button(r.id, r.label, r.dim ? "dim" : "", r.right)).join("");

  const PANEL_VIEWS = {
    none: () => "",
    talk: (d) => (d.name ? `<h2>${esc(d.name)}</h2>` : "") + (d.big ? `<p class="big">${esc(d.big)}</p>` : "") + (d.text ? `<p>${esc(d.text)}</p>` : "")
      + rows(d.choices) + (d.tap ? `<p class="more">${d.more ? "Tap for more" : "Tap to continue"}</p>` : "")
      + (d.skip ? button(d.skip, "SKIP", "dim") : ""),
    menu: (d) => `<h2>${esc(d.title)}</h2>` + (d.line ? `<p class="msg">${esc(d.line)}</p>` : "") + (d.note ? `<p>${esc(d.note)}</p>` : "") + rows(d.rows)
      + `<div class="row2">${button("back", "BACK", "go")}${button("button:actQuit", d.quit, d.quit === "SURE?" ? "warn" : "")}</div>`
      + `<p class="gold" style="margin-top:10px">GOLD ${d.gold}</p>`
      + (d.facts ? `<div class="facts">${d.facts.map(([k, v]) => `<span>${esc(k)}</span><b>${esc(v)}</b>`).join("")}</div>` : "")
      + (d.party || []).map(member).join("") + (d.bag && d.bag.length ? `<p>${esc(d.bag.join(", "))}</p>` : ""),
    battle: (d) => `<p class="msg">${esc(d.msg)}</p>`
      + (d.spoils ? `<p>${d.spoils.xp ?? 0} XP, <span class="gold">${d.spoils.gold ?? 0} gold</span></p>${d.spoils.ups.map((u) => `<p>${esc(u)}</p>`).join("")}<p class="more">Tap to continue</p>` : "")
      + (d.cmds ? `<div class="grid">${d.cmds.map((c) => button(c.id, c.label, c.warn ? "warn" : c.dim ? "dim" : "")).join("")}</div>` : "")
      + rows(d.rows) + (d.back ? button("back", "BACK", "go") : "")
      + `<div style="margin-top:10px">${d.allies.map(member).join("")}</div>`,
    ground: (d) => (d.place ? `<h2>${esc(d.place)}</h2>` : "") + (d.goal ? `<p class="goal">${esc(d.goal)}</p>` : "") + (d.msg ? `<p class="msg">${esc(d.msg)}</p>` : "")
      + button("menu", "MENU", "go") + `<p class="gold">GOLD ${d.gold}</p>` + d.party.map(member).join(""),
    help: (d) => `<h2>How to play</h2>` + d.lines.filter(Boolean).map((l) => `<p>${esc(l)}</p>`).join("") + button("button:rulesDone", d.done, "go"),
    ready: (d) => (d.line ? `<p>${esc(d.line)}</p>` : "") + `<div class="row2">`
      + (d.line ? `<button type="button" class="pb" data-local="export"><span>COPY SAVE CODE</span></button>` : "")
      + `<button type="button" class="pb" data-local="import"><span>PASTE SAVE CODE</span></button></div>`
      + `<p><a class="players-link" href="players.html">Who else is playing?</a></p>`,
  };

  let shownPanel = { kind: "none" }, panelPlace = "";

  function showPanel(data) {
    shownPanel = data;
    panelBody.innerHTML = (PANEL_VIEWS[data.kind] || PANEL_VIEWS.none)(data);
    const place = [data.kind, data.title, data.phase, data.text].join("|");
    if (place !== panelPlace) panelBody.scrollTop = 0;
    panelPlace = place;
  }

  function pressPanel(id) {
    inputs.push("press " + id);
    safeStep();
    draw();
  }

  // Save codes carry a game between Safari and the home screen app, whose storage iOS keeps apart.
  const SAVE_KEY = /^blightmare\.web\.fs\/arcade_save_[^/]*\.dat$/;
  async function exportSave() {
    const saves = {};
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (SAVE_KEY.test(key)) saves[key] = localStorage.getItem(key);
    }
    const code = btoa(JSON.stringify(saves));
    try {
      await navigator.clipboard.writeText(code);
      window.alert("Save code copied. Paste it into the other copy of the game.");
    } catch {
      window.prompt("Copy this save code", code);
    }
  }
  function importSave() {
    const code = window.prompt("Paste a save code");
    if (!code) return;
    try {
      const saves = JSON.parse(atob(code.trim()));
      const keys = Object.keys(saves);
      if (!keys.length || !keys.every((k) => SAVE_KEY.test(k) && typeof saves[k] === "string")) throw new Error("not a save");
      if (!window.confirm("Replace the saved game here with this one?")) return;
      for (const key of keys) localStorage.setItem(key, saves[key]);
      location.reload();
    } catch {
      window.alert("That code isn't a saved game.");
    }
  }

  panelBody.addEventListener("click", (e) => {
    const local = e.target.closest("[data-local]");
    if (local) {
      if (local.dataset.local === "export") exportSave(); else importSave();
      return;
    }
    const pressed = e.target.closest("[data-id]");
    if (pressed) pressPanel(pressed.dataset.id);
    else if (shownPanel.tap) pressPanel("tap");
  });

  const INSTALL_KEY = "blightmare.web.installHint";
  (function installHint() {
    const ios = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
    const safari = /Safari/.test(navigator.userAgent) && !/CriOS|FxiOS|EdgiOS|OPiOS/.test(navigator.userAgent);
    const installed = navigator.standalone === true || window.matchMedia("(display-mode: standalone)").matches;
    let dismissed = false;
    try { dismissed = localStorage.getItem(INSTALL_KEY) === "1"; } catch {}
    if (!ios || !safari || installed || dismissed) return;
    installEl.style.display = "flex";
    document.getElementById("installClose").addEventListener("click", () => {
      installEl.style.display = "none";
      try { localStorage.setItem(INSTALL_KEY, "1"); } catch {}
    });
  })();

  // Keys go to Lua by name. Only the ways repeat, and only from here, so every browser and keyboard repeats alike.
  const REPEAT_WAIT_MS = 230, REPEAT_MS = 150;
  const KEY_NAMES = {
    ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
    Enter: "enter", " ": "space", Tab: "tab", Escape: "escape", Backspace: "backspace",
  };
  const REPEATS = new Set(["up", "down", "left", "right", "w", "a", "s", "d"]);
  const SWALLOW = new Set(["up", "down", "left", "right", "space", "tab", "backspace"]);
  const down = new Set();
  let repeatKey = null, repeatTimer = 0;

  function keyName(e) {
    if (KEY_NAMES[e.key]) return KEY_NAMES[e.key];
    return e.key.length === 1 && /[a-zA-Z0-9]/.test(e.key) ? e.key.toLowerCase() : null;
  }

  function sendKey(kind, name) {
    inputs.push("key " + kind + " " + name);
    safeStep();
    draw();
  }

  function stopRepeat() {
    clearTimeout(repeatTimer);
    repeatKey = null;
  }

  function startRepeat(name) {
    stopRepeat();
    repeatKey = name;
    const again = () => {
      if (repeatKey !== name || stopped) return;
      sendKey("repeat", name);
      repeatTimer = setTimeout(again, REPEAT_MS);
    };
    repeatTimer = setTimeout(again, REPEAT_WAIT_MS);
  }

  window.addEventListener("keydown", (e) => {
    if (stopped || e.ctrlKey || e.altKey || e.metaKey) return;
    const name = keyName(e);
    if (!name) return;
    if (SWALLOW.has(name) || name === "enter") e.preventDefault();
    if (e.repeat || down.has(name)) return;
    down.add(name);
    synth.wake();
    sendKey("down", name);
    if (REPEATS.has(name)) startRepeat(name);
  });

  window.addEventListener("keyup", (e) => {
    const name = keyName(e);
    if (!name || !down.delete(name)) return;
    if (repeatKey === name) stopRepeat();
    if (!stopped) sendKey("up", name);
  });

  // a key let go in another window never comes up here, and the party would walk on
  window.addEventListener("blur", () => {
    stopRepeat();
    for (const name of down) if (!stopped) sendKey("up", name);
    down.clear();
  });

  // The shell saves the run on the installer's key without ending anything, so this is the same save the cabinet makes.
  function saveNow() {
    if (stopped) return;
    inputs.push("char i");
    safeStep();
  }
  window.addEventListener("pagehide", saveNow);
  document.addEventListener("freeze", saveNow);
  // nothing ticks while the page is hidden, and iOS may end it there without another word, so this is the last chance
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") saveNow();
    else fit();
  });

  function showMute() {
    const muted = synth.isMuted();
    muteButton.setAttribute("aria-pressed", String(muted));
    muteButton.setAttribute("aria-label", muted ? "Sound off, tap for sound" : "Sound on, tap to mute");
  }
  muteButton.addEventListener("click", () => {
    synth.wake();
    synth.setMuted(!synth.isMuted());
    showMute();
    muteButton.blur(); // or the next Space would press it again
  });
  showMute();

  // For test scripts: look at the wall, and ask the game things.
  window.__blightmare = {
    stats,
    tap,
    rowText: (y) => latin1Of(chars.subarray((y - 1) * COLS, y * COLS)),
    cell: (x, y) => ({ ch: chars[(y - 1) * COLS + x - 1], fg: fgs[(y - 1) * COLS + x - 1], bg: bgs[(y - 1) * COLS + x - 1] }),
    palette: () => palette.slice(),
    cellSize: () => [cw, ch],
    cursor: () => cursorBox.slice(),
    panel: () => shownPanel,
    eval(code) {
      webCall("eval", [code], 1);
      const text = luaText(-1);
      api.settop(L, 0);
      return text;
    },
  };

  restoreFiles();
  webCall("start", [String(new Date().getTimezoneOffset() * -1)], 0);
  luaRunning = true;
  if (panelWanted) inputs.push("panel 1");
  api.settop(L, 0);
  safeStep();
  draw();
  requestAnimationFrame(frame);
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("sw.js").then((worker) => {
      // a home screen app is mostly resumed, not launched, so coming back counts as a launch for updates
      document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible") worker.update().catch(() => {});
      });
    }).catch((e) => console.warn("no offline copy: " + e));
  }
})().catch((e) => {
  const box = document.getElementById("crash");
  document.getElementById("crashText").textContent = e && e.damaged ? e.message : describeError(e);
  document.getElementById("note").style.display = "none";
  box.style.display = "block";
});
