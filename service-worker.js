const CACHE = 'aziza-v1';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './shop.png.png',
  './paz1.jpg',
  './paz2.jpg',
  './paz3.jpg',
  './paz4.jpg',
  './logo-192.png',
  './logo-512.png',
  './favicon.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  e.respondWith(
    caches.match(e.request).then((r) => r || fetch(e.request))
  );
});