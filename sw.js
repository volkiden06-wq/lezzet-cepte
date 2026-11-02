const CACHE_NAME = 'yemek-tadinda-shell-v18';
const APP_SHELL = ['/', '/index.html', '/manifest.webmanifest', '/app-icon.svg'];
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL);
    // Optional PNG shortcuts must never block service-worker installation.
    await Promise.all(['/favicon-32.png', '/app-icon-192.png', '/app-icon-512.png']
      .map(path => cache.add(path).catch(error => console.warn('Optional app icon not cached:', path, error))));
    await self.skipWaiting();
  })());
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; }
  catch (_) { data = { body: event.data ? event.data.text() : '' }; }
  const title = data.title || 'YEMEK TADINDA';
  const orderNumber = data.orderNumber ? String(data.orderNumber) : null;
  const options = {
    body: data.body || 'Yeni bir duyurumuz var.',
    icon: '/app-icon.svg',
    badge: '/app-icon.svg',
    image: data.image || undefined,
    tag: data.tag || (orderNumber ? 'yemek-tadinda-order-' + orderNumber : 'yemek-tadinda-campaign'),
    renotify: true,
    silent: false,
    vibrate: [300, 150, 300, 150, 600],
    requireInteraction: true,
    data: { url: data.url || '/', orderNumber }
  };
  event.waitUntil((async () => {
    try { await self.registration.showNotification(title, options); }
    catch (error) {
      console.error('Primary notification display failed:', error);
      await self.registration.showNotification(title, {
        body: options.body, tag: options.tag, renotify: true, silent: false,
        vibrate: options.vibrate, requireInteraction: true, data: options.data
      });
    }
    if (orderNumber) {
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of windows) client.postMessage({ type: 'YEMEK_TADINDA_NEW_ORDER', orderNumber, title, body: options.body });
    }
  })());
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = new URL(event.notification.data && event.notification.data.url || '/', self.location.origin).href;
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const client of list) {
      if (client.url.startsWith(self.location.origin) && 'focus' in client) {
        client.navigate(target);
        return client.focus();
      }
    }
    return clients.openWindow(target);
  }));
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).then(response => {
      const copy = response.clone();
      caches.open(CACHE_NAME).then(cache => cache.put('/index.html', copy));
      return response;
    }).catch(() => caches.match('/index.html').then(response => response || caches.match('/'))));
    return;
  }
  if (['/manifest.webmanifest', '/app-icon.svg', '/favicon-32.png', '/app-icon-192.png', '/app-icon-512.png'].includes(url.pathname)) {
    event.respondWith(caches.match(request).then(cached => cached || fetch(request)));
  }
});