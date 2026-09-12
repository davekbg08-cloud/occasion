// Service worker Firebase Cloud Messaging pour la PWA Occasion.
//
// Rôle : afficher une notification système (bannière + vibration) quand un
// push arrive alors que l'onglet n'est PAS au premier plan (en arrière-plan
// ou complètement fermé) — l'équivalent web du comportement déjà en place
// côté Android natif. Quand l'onglet est au premier plan, c'est le flux
// FirebaseMessaging.onMessage côté Dart qui gère l'affichage (voir
// lib/services/notification_service.dart) ; ce fichier ne s'exécute pas
// dans ce cas, donc pas de risque de doublon.
//
// Portée : Chrome/Edge sur Android affichent la bannière ET font vibrer
// l'appareil. Les navigateurs desktop affichent la bannière mais ne
// peuvent pas vibrer (pas de matériel). Safari iOS ne supporte le Web
// Push que pour une PWA ajoutée à l'écran d'accueil (iOS 16.4+), et ne
// respecte pas le motif de vibration.

importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js'
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js'
);

firebase.initializeApp({
  apiKey: 'AIzaSyDsZ-F8Tpl77yZUxkRkXOr-HnGrfr6OcbM',
  appId: '1:101610899328:web:94ef5e76085b599b486365',
  messagingSenderId: '101610899328',
  projectId: 'occasion-10cdb',
  authDomain: 'occasion-10cdb.firebaseapp.com',
  storageBucket: 'occasion-10cdb.firebasestorage.app',
});

const messaging = firebase.messaging();

// Base href de l'app déployée (flutter build web --base-href /occasion/).
const APP_BASE_PATH = '/occasion/';

messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  const notif = payload.notification || {};

  const title = notif.title || data.title || 'Occasion';
  const body = notif.body || data.body || '';
  // Route déjà résolue côté serveur (voir sendToUser -> pushData.route dans
  // functions/index.js, ex. "/chat/abc123") — jamais reconstruite ici à
  // partir d'un type/id, pour rester la seule source de vérité (même
  // principe que _buildPayload côté Dart, notification_service.dart).
  const route = data.route || '/notifications';

  self.registration.showNotification(title, {
    body: body,
    icon: '/occasion/icons/Icon-192.png',
    badge: '/occasion/icons/Icon-192.png',
    vibrate: [200, 100, 200, 100, 200],
    tag: data.chatId || data.orderId || data.id || undefined,
    data: { route: route },
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const route = (event.notification.data && event.notification.data.route) || '/notifications';
  // Stratégie d'URL par défaut de Flutter web (hash) — l'app ne surcharge
  // jamais usePathUrlStrategy() (vérifié dans lib/main.dart), donc les URLs
  // réelles sont toujours de la forme .../occasion/#/chat/xyz.
  const targetUrl = new URL(`${APP_BASE_PATH}#${route}`, self.location.origin).href;

  event.waitUntil(
    clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if (client.url.includes(APP_BASE_PATH) && 'focus' in client) {
            client.navigate(targetUrl);
            return client.focus();
          }
        }
        if (clients.openWindow) {
          return clients.openWindow(targetUrl);
        }
      })
  );
});
