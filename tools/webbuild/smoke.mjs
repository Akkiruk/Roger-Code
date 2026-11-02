// Boots a built copy in a real browser and plays the opening by keyboard. A build that crashes must never reach the website.
//   node tools/webbuild/smoke.mjs [dir]     needs playwright installed beside it, and exits non-zero on any failure
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(process.argv[2] || join(here, "out", "blightmare"));
const TYPES = {
  ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".txt": "text/plain", ".png": "image/png",
  ".webmanifest": "application/manifest+json",
};

const server = createServer(async (req, res) => {
  const name = new URL(req.url, "http://x").pathname.replace(/^\/+/, "") || "index.html";
  try {
    const body = await readFile(join(root, name));
    res.writeHead(200, { "content-type": TYPES[extname(name)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((done) => server.listen(0, "127.0.0.1", done));
const url = "http://127.0.0.1:" + server.address().port + "/";

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));

async function check(where) {
  const crash = await page.evaluate(() => {
    const box = document.getElementById("crash");
    return box && getComputedStyle(box).display !== "none" ? box.textContent : null;
  });
  if (crash) throw new Error("crashed at " + where + ": " + crash);
  if (errors.length) throw new Error("page error at " + where + ": " + errors[0]);
}

/** How many colours are on the wall: a blank or dead picture has one. */
const colours = () => page.evaluate(() => {
  const canvas = document.querySelector("canvas");
  const data = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data;
  const seen = new Set();
  for (let i = 0; i < data.length; i += 4 * 97) seen.add(data[i] << 16 | data[i + 1] << 8 | data[i + 2]);
  return seen.size;
});

try {
  await page.goto(url, { waitUntil: "load" });
  await page.waitForTimeout(2500);
  await check("the title");
  if (await colours() < 2) throw new Error("the title never drew");
  for (const key of ["Enter", "Enter"]) {
    await page.keyboard.press(key);
    await page.waitForTimeout(700);
    await check("starting");
  }
  await page.keyboard.type("Ada");
  await page.keyboard.press("Enter");
  for (let i = 0; i < 12; i++) {
    await page.keyboard.press("Enter");
    await page.waitForTimeout(250);
  }
  await check("the opening");
  for (const key of ["w", "d", "ArrowLeft", "m", "Escape"]) {
    await page.keyboard.press(key);
    await page.waitForTimeout(300);
  }
  await check("walking");
  if (await colours() < 4) throw new Error("the game stopped drawing");

  // the home screen app: everything the service worker promises has to exist, or installing it fails outright
  const worker = await readFile(join(root, "sw.js"), "utf8");
  const listed = JSON.parse(worker.match(/const FILES = (\[.*\]);/)[1]);
  for (const name of listed) await readFile(join(root, name === "./" ? "index.html" : name));
  if (/__VERSION__|__FILES__/.test(worker)) throw new Error("the service worker was not filled in");
  const manifest = JSON.parse(await readFile(join(root, "manifest.webmanifest"), "utf8"));
  for (const icon of manifest.icons) {
    const png = await readFile(join(root, icon.src));
    if (png.readUInt32BE(16) + "x" + png.readUInt32BE(20) !== icon.sizes) throw new Error(icon.src + " is the wrong size");
  }

  // a phone: the panel has to show the words on the wall, and a tap on it has to go on
  const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const small = await phone.newPage();
  small.on("pageerror", (e) => errors.push(String(e)));
  await small.goto(url, { waitUntil: "load" });
  await small.waitForTimeout(2500);
  const tapWall = async (x, y) => {
    const box = await small.locator("#wall").boundingBox();
    await small.touchscreen.tap(box.x + x / 121 * box.width, box.y + y / 81 * box.height);
    await small.waitForTimeout(500);
  };
  await tapWall(60, 40);
  await tapWall(60, 64);
  await tapWall(60, 62);
  const words = await small.locator("#panelBody").innerText();
  if (words.length < 20) throw new Error("the phone panel stayed empty: " + words);
  const box = await small.locator("#panelBody").boundingBox();
  await small.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
  // a slow machine takes a few ticks to show it: wait for the change rather than a fixed time
  let changed = false;
  for (let i = 0; i < 25 && !changed; i++) {
    await small.waitForTimeout(200);
    changed = await small.locator("#panelBody").innerText() !== words;
  }
  if (!changed) throw new Error("a tap on the phone panel did nothing: " + words.slice(0, 120));
  // the opening's SKIP, from the panel, goes to the title
  const skip = small.locator('#panelBody [data-id^="skip,"]');
  if (await skip.count()) {
    await skip.first().tap();
    let titled = false;
    for (let i = 0; i < 25 && !titled; i++) {
      await small.waitForTimeout(200);
      titled = (await small.locator("#panelBody").innerText()).includes("BLIGHTMARE");
    }
    if (!titled) throw new Error("SKIP on the phone panel didn't reach the title");
  }
  if (errors.length) throw new Error("page error on a phone: " + errors[0]);
  await phone.close();
  console.log("smoke test passed");
} catch (e) {
  console.error(String(e.message || e));
  process.exitCode = 1;
} finally {
  await browser.close();
  server.close();
}
