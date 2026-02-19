/* eslint-disable no-restricted-globals */
// Minimal COI service worker for static hosts that cannot set COOP/COEP headers
// (for example GitHub Pages). Adapted from the public coi-serviceworker pattern.

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('message', (event) => {
  if (event?.data?.type === 'activate') {
    self.skipWaiting();
  }
});

self.addEventListener('fetch', (event) => {
  const { request } = event;

  // Work around a Chrome edge case for navigation preload + cache mode.
  if (request.cache === 'only-if-cached' && request.mode !== 'same-origin') {
    return;
  }

  event.respondWith((async () => {
    const response = await fetch(request);

    // Opaque cross-origin responses cannot be rewrapped.
    if (!response || response.status === 0) {
      return response;
    }

    const headers = new Headers(response.headers);
    headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
    headers.set('Cross-Origin-Opener-Policy', 'same-origin');
    headers.set('Cross-Origin-Resource-Policy', 'same-origin');

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers
    });
  })());
});
