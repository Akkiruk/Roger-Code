// Builds the browser version of BLIGHTMARE: real Lua 5.1 in wasm, the game's real sources, a stand-in for CC:Tweaked.
//   npm install --prefix tools/webbuild      once, for lua-wasm-bindings
//   node tools/webbuild/build.mjs [--out dir]
// .github/workflows/publish-web.yml runs this on every push that touches the game, so elawondra.com keeps up by itself.
// Static files only, all named relative to the page, so it works under any folder. Roger-Code is only read.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { deflateSync } from "node:zlib";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  return i < 0 ? fallback : args[i + 1];
};
const roger = resolve(flag("--roger", join(here, "..", "..")));
const outDir = resolve(flag("--out", join(here, "out", "blightmare")));
const game = join(roger, "Games", "Blightmare");
const shared = join(roger, "Shared", "lib");

function fail(message) {
  console.error(message);
  process.exit(1);
}

const glueDir = join(here, "node_modules", "lua-wasm-bindings", "dist", "glue");
if (!existsSync(glueDir)) fail("lua-wasm-bindings is missing. Run: npm install --prefix tools/webbuild");
if (!existsSync(game)) fail("no game at " + game);

function walk(dir) {
  const found = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) found.push(...walk(full));
    else found.push(full);
  }
  return found;
}

// The layout of a real computer: the package's files, with lib/ beside the program.
const files = new Map();
const add = (path, full) => files.set(path, readFileSync(full));

for (const name of ["blightmare.lua", "font", "surface"]) add(name, join(game, name));
for (const full of walk(join(game, "games"))) add(relative(game, full).replaceAll("\\", "/"), full);
for (const full of walk(join(shared, "arcade"))) add("lib/arcade/" + relative(join(shared, "arcade"), full).replaceAll("\\", "/"), full);
for (const name of ["sound.lua", "sound_picks.lua", "peripherals.lua"]) add("lib/" + name, join(shared, name));

// Everything the sources ask for has to be here, or the fault would only show at the screen that needs it.
const missing = [];
for (const [path, bytes] of files) {
  if (!path.endsWith(".lua")) continue;
  for (const [, name] of bytes.toString("latin1").matchAll(/^[^-\n]*\brequire\s*\(?\s*"([\w.]+)"/gm)) {
    if (name.endsWith(".")) continue; // the start of a name built at run time
    const base = name.replaceAll(".", "/");
    if (!files.has(base + ".lua") && !files.has(base)) missing.push(`${path} needs ${name}`);
  }
}
if (missing.length) fail("missing modules:\n" + missing.join("\n"));
for (const [path, bytes] of files) {
  if (bytes.includes(0)) fail(path + " has a NUL byte, which the loader can't carry");
}

files.set("__host.lua", readFileSync(join(here, "host.lua")));

const index = [...files].map(([path, bytes]) => [path, bytes.length]);
const bundle = Buffer.concat([Buffer.from(JSON.stringify(index) + "\n"), ...files.values()]);

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

// The file names carry a hash of what's in them, so a new build can't be mixed with one a browser has cached.
function stamped(name, bytes) {
  const tag = createHash("sha256").update(bytes).digest("hex").slice(0, 10);
  const dot = name.lastIndexOf(".");
  return name.slice(0, dot) + "." + tag + name.slice(dot);
}

const wasm = readFileSync(join(glueDir, "glue-lua-5.1.5.wasm"));
const glue = readFileSync(join(glueDir, "glue-lua-5.1.5.js"));
const wasmName = stamped("lua-5.1.5.wasm", wasm);
const bundleName = stamped("bundle.txt", bundle);
const synth = readFileSync(join(here, "web", "synth.js"));
const app = Buffer.from(
  readFileSync(join(here, "web", "app.js"), "utf8").replaceAll("lua-5.1.5.wasm", wasmName).replaceAll("bundle.txt", bundleName),
);
const glueName = stamped("lua-5.1.5.js", glue);
const synthName = stamped("synth.js", synth);
const appName = stamped("app.js", app);
const html = readFileSync(join(here, "web", "index.html"), "utf8")
  .replace('src="lua-5.1.5.js"', `src="${glueName}"`)
  .replace('src="synth.js"', `src="${synthName}"`)
  .replace('src="app.js"', `src="${appName}"`);

// ------------------------------------------------------------------ the home screen app

// PNG by hand, so the build needs nothing but node. Every picture is opaque RGB, as iOS rounds the corners itself.
const crcTable = Array.from({ length: 256 }, (_, start) => {
  let n = start;
  for (let k = 0; k < 8; k++) n = n & 1 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
  return n >>> 0;
});
function crc32(bytes) {
  let c = 0xffffffff;
  for (const b of bytes) c = crcTable[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function pngChunk(type, data) {
  const typed = Buffer.concat([Buffer.from(type), data]);
  const out = Buffer.alloc(typed.length + 8);
  out.writeUInt32BE(data.length, 0);
  typed.copy(out, 4);
  out.writeUInt32BE(crc32(typed), typed.length + 4);
  return out;
}
function png(width, height, colourAt) {
  const raw = Buffer.alloc((width * 3 + 1) * height);
  let at = 0;
  for (let y = 0; y < height; y++) {
    raw[at++] = 0;
    for (let x = 0; x < width; x++) {
      const rgb = colourAt(x, y);
      raw[at++] = rgb >> 16;
      raw[at++] = (rgb >> 8) & 255;
      raw[at++] = rgb & 255;
    }
  }
  const head = Buffer.alloc(13);
  head.writeUInt32BE(width, 0);
  head.writeUInt32BE(height, 4);
  head[8] = 8; // bits
  head[9] = 2; // RGB
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), pngChunk("IHDR", head), pngChunk("IDAT", deflateSync(raw, { level: 9 })), pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

// The title screen's picture: the great wall at night with the crack in it, under a big red B. Drawn on a 64 square grid.
const ICON_B = ["XXXXXX.", "XX..XXX", "XX...XX", "XX..XX.", "XXXXX..", "XX..XX.", "XX...XX", "XX..XXX", "XXXXXX."];
const ICON_STARS = new Set(["6,8", "11,27", "4,34", "53,6", "58,20", "51,31", "57,38", "9,18"]);
const NIGHT = 0x14161c, STONE = 0x232733, LIT = 0x4a4f60, RED = 0xe5484d, DEEP = 0x4a2328;
function iconPixel(x, y) {
  const wallTop = 46;
  const crackX = 45 + (y % 7 < 3 ? 1 : -1);
  if (y >= wallTop - 2) {
    if (x === crackX || x === crackX + 1) return RED;
    if (x === crackX + 2 || x === crackX - 1) return DEEP;
  }
  if (y >= wallTop - 3 && y < wallTop && x % 8 < 5) return y === wallTop - 3 ? LIT : STONE;
  if (y >= wallTop) return (y - wallTop) % 5 === 4 ? NIGHT : y === wallTop ? LIT : STONE;
  const col = Math.floor((x - 18) / 4), row = Math.floor((y - 5) / 4);
  if (x >= 18 && row >= 0 && row < 9 && col < 7 && ICON_B[row][col] === "X") return RED;
  return ICON_STARS.has(x + "," + y) ? LIT : NIGHT;
}
const icon = (size) => png(size, size, (x, y) => iconPixel(Math.floor(x * 64 / size), Math.floor(y * 64 / size)));

// A launch screen in the page's own dark for each size of phone, or iOS opens the app on white.
const SPLASHES = [
  [320, 568, 2], [375, 667, 2], [414, 736, 3], [375, 812, 3], [414, 896, 2], [414, 896, 3], [360, 780, 3], [390, 844, 3],
  [393, 852, 3], [428, 926, 3], [430, 932, 3], [402, 874, 3], [440, 956, 3],
];
const splashTags = [];
const pictures = {};
for (const size of [152, 167, 180, 192, 512]) pictures[`icon-${size}.png`] = icon(size);
for (const [w, h, ratio] of SPLASHES) {
  const name = `splash-${w * ratio}x${h * ratio}.png`;
  pictures[name] ??= png(w * ratio, h * ratio, () => 0x0b0c10);
  splashTags.push(`<link rel="apple-touch-startup-image" href="${name}" media="(device-width: ${w}px) and (device-height: ${h}px) and (-webkit-device-pixel-ratio: ${ratio}) and (orientation: portrait)">`);
}

const manifest = JSON.stringify({
  id: "./", name: "BLIGHTMARE", short_name: "BLIGHTMARE", description: "A dark RPG: a wall, a plague, and a hero who has never dreamed.",
  start_url: "./", scope: "./", display: "standalone", orientation: "any", background_color: "#0b0c10", theme_color: "#14161c",
  icons: [
    { src: "icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
    { src: "icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
    { src: "icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
  ],
}, null, 2);

const page = html.replace("<!-- splash -->", splashTags.join("\n"));
const output = {
  "index.html": page, [glueName]: glue, [synthName]: synth, [appName]: app, [wasmName]: wasm, [bundleName]: bundle,
  "manifest.webmanifest": manifest, ...pictures,
};

// The service worker lists every file, and its version is all of them hashed, so any change at all makes a new cache.
const everything = createHash("sha256");
for (const [name, content] of Object.entries(output)) everything.update(name).update(content);
output["sw.js"] = readFileSync(join(here, "web", "sw.js"), "utf8")
  .replace("__VERSION__", everything.digest("hex").slice(0, 16))
  .replace("__FILES__", JSON.stringify(Object.keys(output).map((name) => (name === "index.html" ? "./" : name))));

let total = 0;
for (const [name, content] of Object.entries(output)) {
  writeFileSync(join(outDir, name), content);
  const size = Buffer.byteLength(content);
  total += size;
  console.log(String(size).padStart(9), name);
  if (size > 25 * 1024 * 1024) fail(name + " is over the 25 MiB file limit");
}
console.log(String(total).padStart(9), "total in", outDir);
