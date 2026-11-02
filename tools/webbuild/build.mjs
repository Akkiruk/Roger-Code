// Builds the browser version of BLIGHTMARE: real Lua 5.1 in wasm, the game's real sources, a stand-in for CC:Tweaked.
//   npm install --prefix tools/webbuild      once, for lua-wasm-bindings
//   node tools/webbuild/build.mjs [--out dir]
// .github/workflows/publish-web.yml runs this on every push that touches the game, so elawondra.com keeps up by itself.
// Static files only, all named relative to the page, so it works under any folder. Roger-Code is only read.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
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

const output = { "index.html": html, [glueName]: glue, [synthName]: synth, [appName]: app, [wasmName]: wasm, [bundleName]: bundle };
let total = 0;
for (const [name, content] of Object.entries(output)) {
  writeFileSync(join(outDir, name), content);
  const size = Buffer.byteLength(content);
  total += size;
  console.log(String(size).padStart(9), name);
  if (size > 25 * 1024 * 1024) fail(name + " is over the 25 MiB file limit");
}
console.log(String(total).padStart(9), "total in", outDir);
