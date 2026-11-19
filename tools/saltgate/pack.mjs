// Builds Games/Saltgate/saltgate.pak: the game's code and content in one compressed file, which saltgate.lua (through
// sgpak.lua) inflates into memory at boot. The repo keeps the readable sources; the pak is what the deploy index ships
// (startup.lua's "-- manifest-ship:" line), so run this and commit the pak whenever anything under sg/, content/,
// music/ or pine3d/ changes. Tests/saltgate_pak_test.lua fails while the pak is stale.
//   node tools/saltgate/pack.mjs            (no packages needed: Node's own zlib)
//
// Lua files are minified without moving anything off its line: comments and indentation go, every line break stays,
// so a crash trace's "sg/core/app.lua:123" is the same line in the readable source and no line map is needed.
// Format: "SGPAK1 <payload bytes>\n" then the payload as raw deflate. Payload: one "path<TAB>bytes\n" line a file, an
// empty line, then the files' bytes one after another in that order.
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { deflateRawSync, constants } from "node:zlib";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const game = resolve(here, "..", "..", "Games", "Saltgate");
export const ROOTS = ["sg", "content", "music", "pine3d"];
const SKIP = (rel) => rel.endsWith(".md") || rel.endsWith(".txt") && rel.startsWith("pine3d/") || rel.endsWith(".bak");

function walk(dir, out = []) {
  for (const name of readdirSync(dir).sort()) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

// ---------------------------------------------------------------- the minifier

const WORD = /[A-Za-z0-9_]/;

function longBracket(src, i) {
  // at "[": the level of a long bracket "[==[" starting here, or -1
  let j = i + 1, level = 0;
  while (src[j] === "=") { level++; j++; }
  return src[j] === "[" ? level : -1;
}

/** Lua 5.1 source with comments and indentation gone and every line break kept. */
export function minify(src) {
  let text = "";
  let prev = null; // { last char, kind } of the last token on this output line
  let i = 0;
  const n = src.length;
  const emit = (tok, kind) => {
    if (prev) {
      const a = prev.last, b = tok[0];
      const space =
        (WORD.test(a) && WORD.test(b)) ||
        (prev.kind === "num" && (b === "." || WORD.test(b))) ||
        (a === "." && (b === "." || /[0-9]/.test(b))) ||
        (a === "-" && b === "-") ||
        (a === "[" && (b === "[" || b === "=")) ||
        ("=<>~".includes(a) && b === "=");
      if (space) text += " ";
    }
    // a token with line breaks in it (a long string, a string with "\" and a line break) keeps them as written,
    // so the lines after it stay where they were
    text += tok;
    prev = { last: tok[tok.length - 1], kind };
  };
  const breaksIn = (s) => s.replace(/\r\n|\n\r/g, "\n").replace(/\r/g, "\n").split("\n").length - 1;
  while (i < n) {
    const c = src[i];
    if (c === "\n" || c === "\r") {
      // "\r\n" and "\n\r" are one line break, as Lua counts them
      const d = src[i + 1];
      i += (d === "\n" || d === "\r") && d !== c ? 2 : 1;
      text += "\n";
      prev = null;
      continue;
    }
    if (c === " " || c === "\t" || c === "\f" || c === "\v") { i++; continue; }
    if (c === "-" && src[i + 1] === "-") {
      if (src[i + 2] === "[") {
        const level = longBracket(src, i + 2);
        if (level >= 0) {
          const close = "]" + "=".repeat(level) + "]";
          const end = src.indexOf(close, i + 2);
          if (end < 0) throw new Error("unfinished long comment");
          const breaks = breaksIn(src.slice(i, end));
          if (breaks > 0) { text += "\n".repeat(breaks); prev = null; }
          i = end + close.length;
          continue;
        }
      }
      while (i < n && src[i] !== "\n" && src[i] !== "\r") i++;
      continue;
    }
    if (c === "[") {
      const level = longBracket(src, i);
      if (level >= 0) {
        const close = "]" + "=".repeat(level) + "]";
        const end = src.indexOf(close, i);
        if (end < 0) throw new Error("unfinished long string");
        emit(src.slice(i, end + close.length), "str");
        i = end + close.length;
        continue;
      }
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < n && src[j] !== c) {
        if (src[j] === "\\") j++;
        else if (src[j] === "\n") throw new Error("unfinished string at " + i);
        j++;
      }
      emit(src.slice(i, j + 1), "str");
      i = j + 1;
      continue;
    }
    if (/[0-9]/.test(c) || (c === "." && /[0-9]/.test(src[i + 1] ?? ""))) {
      const m = /^(0[xX][0-9a-fA-F]*|[0-9]*\.?[0-9]*(?:[eE][+-]?[0-9]+)?)[A-Za-z0-9_]*/.exec(src.slice(i, i + 64));
      emit(m[0], "num");
      i += m[0].length;
      continue;
    }
    if (/[A-Za-z_]/.test(c)) {
      let j = i + 1;
      while (j < n && WORD.test(src[j])) j++;
      emit(src.slice(i, j), "name");
      i = j;
      continue;
    }
    const three = src.slice(i, i + 3), two = src.slice(i, i + 2);
    const op = three === "..." ? three : ["..", "==", "~=", "<=", ">="].includes(two) ? two : c;
    emit(op, "op");
    i += op.length;
  }
  return text.replace(/\n+$/, "\n");
}

// ---------------------------------------------------------------- the pack

/** The pack. opts.override: { [path] = text } used instead of those files (a test's planted bug). */
export function build(opts = {}) {
  const files = [];
  for (const root of ROOTS) {
    for (const full of walk(join(game, root))) {
      const rel = relative(game, full).replace(/\\/g, "/");
      if (SKIP(rel)) continue;
      let bytes = opts.override?.[rel] != null ? Buffer.from(opts.override[rel], "latin1") : readFileSync(full);
      if (rel.endsWith(".lua")) bytes = Buffer.from(minify(bytes.toString("latin1")), "latin1");
      files.push({ rel, bytes, raw: statSync(full).size });
    }
  }
  const header = files.map((f) => `${f.rel}\t${f.bytes.length}\n`).join("") + "\n";
  const payload = Buffer.concat([Buffer.from(header, "latin1"), ...files.map((f) => f.bytes)]);
  const packed = deflateRawSync(payload, { level: 9, memLevel: 9, windowBits: 15, strategy: constants.Z_DEFAULT_STRATEGY });
  const pak = Buffer.concat([Buffer.from(`SGPAK1 ${payload.length}\n`, "latin1"), packed]);
  return { files, payload, pak };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { files, payload, pak } = build();
  writeFileSync(join(game, "saltgate.pak"), pak);
  const raw = files.reduce((s, f) => s + f.raw, 0);
  console.log(`${files.length} files: ${raw} bytes readable, ${payload.length} minified, saltgate.pak ${pak.length} bytes`);
}
