/* eslint-disable no-undef */
/**
 * FCM background handler for PlanetMM web.
 * Build scripts replace __FIREBASE_*__ and __BASE_PATH__ at build time.
 */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: '__FIREBASE_API_KEY__',
  authDomain: '__FIREBASE_AUTH_DOMAIN__',
  projectId: '__FIREBASE_PROJECT_ID__',
  storageBucket: '__FIREBASE_STORAGE_BUCKET__',
  messagingSenderId: '__FIREBASE_MESSAGING_SENDER_ID__',
  appId: '__FIREBASE_APP_ID__',
  measurementId: '__FIREBASE_MEASUREMENT_ID__',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title =
    payload.notification?.title ||
    payload.data?.title ||
    'PlanetMM';
  const body =
    payload.notification?.body ||
    payload.data?.body ||
    'You have a new update';

  return self.registration.showNotification(title, {
    body,
    icon: '__BASE_PATH__icons/Icon-192.png',
    badge: '__BASE_PATH__icons/Icon-192.png',
    tag: payload.data?.type || 'planetmm',
    data: payload.data || {},
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = '__BASE_PATH__';
  event.waitUntil(
    clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((windowClients) => {
        for (const client of windowClients) {
          if ('focus' in client) {
            return client.focus();
          }
        }
        if (clients.openWindow) {
          return clients.openWindow(target);
        }
        return undefined;
      }),
  );
});
