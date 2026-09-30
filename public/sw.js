// 所有 GET（畫面檔與查詢 API）：網路優先，成功即更新快取；離線時回快取。
// 寫入（POST）不經快取，由 app.js 的待傳佇列負責斷線重傳。
const CACHE = 'erp-v2';
const SHELL = ['./', 'index.html', 'style.css', 'app.js', 'manifest.webmanifest', 'icon.svg'];
self.addEventListener('install', e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())));
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  e.respondWith(fetch(req)
    .then(r => { if (r.ok) { const c = r.clone(); caches.open(CACHE).then(ca => ca.put(req, c)); } return r; })
    .catch(() => caches.match(req, { ignoreSearch: false }).then(r => r ||
      new Response('{"error":"離線且無快取資料"}', { status: 503, headers: { 'content-type': 'application/json' } }))));
});
