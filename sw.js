/* مُعلّمي — Service Worker v2
   إصلاح: app.js كان يُخزَّن "cache-first" فيبقى المستخدم على نسخة قديمة بعد كل تحديث.
   الآن: الكود والتنقّل "network-first" (تصل التحديثات فورًا)، وباقي الملفات
   "stale-while-revalidate" (سريعة وتُحدَّث في الخلفية)، مع تنظيف الكاش القديم. */
const CACHE = "muallim-v2";
const ASSETS = [
  "./", "./index.html", "./app.js", "./manifest.webmanifest",
  "./icon-180.png", "./icon-192.png", "./icon-512.png"
];

self.addEventListener("install", (e) => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then((c) => Promise.all(ASSETS.map((u) => c.add(u).catch(() => null))))
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

function networkFirst(req) {
  return fetch(req)
    .then((res) => {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
      return res;
    })
    .catch(() => caches.match(req).then((hit) => hit || caches.match("./index.html")));
}

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  // التنقّل بين الصفحات: الشبكة أولًا مع الرجوع للكاش عند عدم الاتصال
  if (req.mode === "navigate") { e.respondWith(networkFirst(req)); return; }

  // الكود والإعدادات: الشبكة أولًا حتى تصل التحديثات فورًا
  if (url.origin === location.origin && /\.(js|webmanifest)$/.test(url.pathname)) {
    e.respondWith(networkFirst(req));
    return;
  }

  // باقي الطلبات: من الكاش فورًا مع تحديثها في الخلفية
  e.respondWith(
    caches.match(req).then((hit) => {
      const fetcher = fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
          return res;
        })
        .catch(() => hit);
      return hit || fetcher;
    })
  );
});
