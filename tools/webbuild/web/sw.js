// Opens BLIGHTMARE with no network, and never mixes two builds. The build fills in VERSION and FILES.
// Each build has a cache of its own, whole before it takes over. The page asks the network first, so a new build shows on the next
// launch, and if there's no network the old page comes from the old cache with the files it was built with. A running game has
// loaded everything it needs, so swapping the cache under it does nothing to it.
"use strict";

const VERSION = "__VERSION__";
const FILES = __FILES__;
const PREFIX = "blightmare-";
const CACHE = PREFIX + VERSION;
const NETWORK_WAIT_MS = 3000; // a phone on one bar of signal shouldn't sit on a dark screen with a good copy to hand

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(FILES.map((name) => new Request(name, { cache: "reload" }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(names.filter((name) => name.startsWith(PREFIX) && name !== CACHE).map((name) => caches.delete(name))))
      .then(() => self.clients.claim()),
  );
});

async function networkFirst(request, key) {
  const cache = await caches.open(CACHE);
  try {
    const answer = await Promise.race([
      fetch(request),
      new Promise((_, stop) => setTimeout(() => stop(new Error("slow")), NETWORK_WAIT_MS)),
    ]);
    if (answer.ok) return answer;
  } catch {
    // no network: the copy below
  }
  return (await cache.match(key)) || fetch(request);
}

async function cacheFirst(request) {
  const cache = await caches.open(CACHE);
  return (await cache.match(request)) || fetch(request);
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== location.origin) return;
  if (request.mode === "navigate") {
    event.respondWith(networkFirst(request, "./"));
  } else if (/\.[0-9a-f]{10}\.[a-z]+$/.test(url.pathname)) {
    event.respondWith(cacheFirst(request));
  } else {
    event.respondWith(networkFirst(request, request));
  }
});
