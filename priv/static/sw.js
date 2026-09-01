// Minimal service worker: only makes the app installable and speeds up
// repeat loads of static assets. It never touches LiveView page loads,
// the /live websocket, or any other request, so game state is always fresh.
const CACHE_NAME = "high-society-static-v1";
const CACHEABLE_PREFIXES = ["/assets/", "/images/", "/audio/"];

self.addEventListener("install", event => {
  self.skipWaiting();
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", event => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (!CACHEABLE_PREFIXES.some(prefix => url.pathname.startsWith(prefix))) return;

  event.respondWith(
    caches.open(CACHE_NAME).then(async cache => {
      const cached = await cache.match(request);
      if (cached) return cached;

      const response = await fetch(request);
      if (response.ok) cache.put(request, response.clone());
      return response;
    })
  );
});
