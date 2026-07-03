import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'annonce/screens/create_annonce_screen.dart';
import 'firebase_options.dart';
import 'models/annonce.dart';
import 'models/chat.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/blocked_users_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/add_status_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/delete_account_screen.dart';
import 'screens/id_scan_screen.dart';
import 'screens/my_listings_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/payment_screen.dart';
import 'screens/phone_auth_screen.dart';
import 'screens/product_list_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/seller_dashboard_screen.dart';
import 'screens/simple_placeholder_screen.dart';
import 'screens/status_feed_screen.dart';
import 'screens/subscription_screen.dart';
import 'search/screens/search_screen.dart';
import 'services/notification_service.dart';
import 'services/firestore_bootstrap.dart';
import 'services/service_locator.dart';
import 'widgets/occasion_logo.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirestoreBootstrap.configure(FirebaseFirestore.instance);
  configureServices();

  // Lance l'interface immédiatement. L'initialisation des notifications est
  // volontairement non bloquante : sur le web, la demande de permission FCM et
  // flutter_local_notifications peuvent ne jamais se résoudre, ce qui laissait
  // l'application sur une page blanche tant que runApp() n'était pas appelé.
  runApp(const ProviderScope(child: OccasionApp()));
  unawaited(NotificationService.init(appNavigatorKey));
}

class OccasionApp extends StatelessWidget {
  const OccasionApp({super.key});

  static final _router = GoRouter(
    navigatorKey: appNavigatorKey,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _AuthGate()),
      GoRoute(path: '/home', builder: (context, state) => const MainNav()),
      GoRoute(
        path: '/buyer-home',
        builder: (context, state) =>
            const _RoleGuard(role: UserRole.buyer, child: BuyerNav()),
      ),
      GoRoute(
        path: '/seller-dashboard',
        builder: (context, state) =>
            const _RoleGuard(role: UserRole.seller, child: SellerNav()),
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const _AuthGuard(child: IdScanScreen()),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const _AuthGuard(child: ProfileScreen()),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const _AuthGuard(child: ProfileScreen()),
      ),
      GoRoute(
        path: '/cart',
        builder: (context, state) =>
            const _RoleGuard(role: UserRole.buyer, child: CartScreen()),
      ),
      GoRoute(
        path: '/orders',
        builder: (_, _) =>
            const _RoleGuard(role: UserRole.buyer, child: OrdersScreen()),
      ),
      GoRoute(
        path: '/addresses',
        builder: (_, _) => const _RoleGuard(
          role: UserRole.buyer,
          child: SimplePlaceholderScreen(
            title: 'Adresses de livraison',
            icon: Icons.location_on_outlined,
            message: 'Vos adresses de livraison apparaîtront ici.',
          ),
        ),
      ),
      GoRoute(
        path: '/payment',
        builder: (_, _) =>
            const _RoleGuard(role: UserRole.buyer, child: PaymentScreen()),
      ),
      GoRoute(
        path: '/subscription',
        builder: (_, _) => const _RoleGuard(
          role: UserRole.seller,
          child: SubscriptionScreen(),
        ),
      ),
      GoRoute(
        path: '/role-selection',
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/phone-auth',
        builder: (context, state) {
          final role = state.extra as UserRole?;

          return PhoneAuthScreen(role: role);
        },
      ),
      GoRoute(
        path: '/favorites',
        builder: (_, _) => const _RoleGuard(
          role: UserRole.buyer,
          child: SimplePlaceholderScreen(
            title: 'Favoris',
            icon: Icons.favorite_outline,
            message: 'Vos annonces favorites apparaîtront ici.',
            primaryLabel: 'Voir les produits',
            primaryRoute: '/products',
          ),
        ),
      ),
      GoRoute(
        path: '/status',
        builder: (context, state) =>
            const _RoleGuard(role: UserRole.buyer, child: StatusFeedScreen()),
      ),
      GoRoute(
        path: '/add-status',
        builder: (context, state) =>
            const _RoleGuard(role: UserRole.seller, child: AddStatusScreen()),
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) =>
            const _AuthGuard(child: ProductListScreen()),
      ),
      GoRoute(
        path: '/create-annonce',
        builder: (context, state) {
          final annonce = state.extra is Annonce
              ? state.extra! as Annonce
              : null;
          return _RoleGuard(
            role: UserRole.seller,
            child: CreateAnnonceScreen(initialAnnonce: annonce),
          );
        },
      ),
      GoRoute(
        path: '/publish-product',
        builder: (context, state) {
          final annonce = state.extra is Annonce
              ? state.extra! as Annonce
              : null;
          return _RoleGuard(
            role: UserRole.seller,
            child: CreateAnnonceScreen(initialAnnonce: annonce),
          );
        },
      ),
      GoRoute(
        path: '/my-listings',
        builder: (context, state) =>
            const _RoleGuard(role: UserRole.seller, child: MyListingsScreen()),
      ),
      GoRoute(
        path: '/seller-orders',
        builder: (_, _) => const _RoleGuard(
          role: UserRole.seller,
          child: SimplePlaceholderScreen(
            title: 'Commandes reçues',
            icon: Icons.local_shipping_outlined,
            message:
                'Les commandes reçues par votre boutique apparaîtront ici.',
          ),
        ),
      ),
      GoRoute(
        path: '/seller-revenue',
        builder: (_, _) => const _RoleGuard(
          role: UserRole.seller,
          child: SimplePlaceholderScreen(
            title: 'Revenus',
            icon: Icons.account_balance_wallet_outlined,
            message: 'Vos revenus vendeur apparaîtront ici.',
          ),
        ),
      ),
      GoRoute(
        path: '/seller-statistics',
        builder: (_, _) => const _RoleGuard(
          role: UserRole.seller,
          child: SimplePlaceholderScreen(
            title: 'Statistiques',
            icon: Icons.bar_chart_outlined,
            message: 'Les statistiques de vos annonces apparaîtront ici.',
          ),
        ),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const _AuthGuard(child: SearchScreen()),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) =>
            const _AuthGuard(child: NotificationsScreen()),
      ),
      GoRoute(
        path: '/chat-list',
        builder: (context, state) => const _AuthGuard(child: ChatListScreen()),
      ),
      GoRoute(
        path: '/buyer-messages',
        builder: (context, state) => const _RoleGuard(
          role: UserRole.buyer,
          child: ChatListScreen(
            title: 'Messages privés',
            emptySubtitle: 'Contactez un vendeur depuis une annonce.',
          ),
        ),
      ),
      GoRoute(
        path: '/seller-messages',
        builder: (context, state) => const _RoleGuard(
          role: UserRole.seller,
          child: ChatListScreen(
            title: 'Messages acheteurs',
            emptySubtitle:
                'Les conversations avec les acheteurs apparaîtront ici.',
          ),
        ),
      ),
      GoRoute(
        path: '/chat-room',
        pageBuilder: (context, state) {
          final chat = state.extra as Chat;

          return CustomTransitionPage<void>(
            key: state.pageKey,
            child: _AuthGuard(child: ChatScreen(chat: chat)),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  );
                },
          );
        },
      ),
      GoRoute(
        path: '/open-chat',
        builder: (context, state) {
          final args = state.extra as Map<String, Object?>? ?? const {};

          return _AuthGuard(child: _OpenChatScreen(args: args));
        },
      ),
      GoRoute(path: '/auth', builder: (context, state) => const _AuthPage()),
      GoRoute(
        path: '/login',
        builder: (context, state) => const PhoneAuthScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/blocked-users',
        builder: (context, state) {
          final userId = state.extra as String? ?? '';

          return _AuthGuard(child: BlockedUsersScreen(currentUserId: userId));
        },
      ),
      GoRoute(
        path: '/delete-account',
        builder: (context, state) {
          final userId = state.extra as String? ?? '';

          return _AuthGuard(child: DeleteAccountScreen(userId: userId));
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Occasion',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(primary: Colors.blue),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[900],
          elevation: 0,
        ),
      ),
      routerConfig: _router,
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final currentUser = authState.currentUser;

    if (authState.isLoading) {
      return const Scaffold(body: Center(child: OccasionLogo(size: 132)));
    }

    if (currentUser == null) {
      return const _AuthPage();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.saveToken(currentUser.id);
    });

    return const MainNav();
  }
}

class _RoleGuard extends ConsumerWidget {
  const _RoleGuard({required this.role, required this.child});

  final UserRole role;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).currentUser;
    if (user == null) return const _AuthPage();
    if (user.role == role) return child;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.go(user.isSeller ? '/seller-dashboard' : '/buyer-home');
    });

    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _AuthGuard extends ConsumerWidget {
  const _AuthGuard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    if (authState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (authState.currentUser == null) return const _AuthPage();
    return child;
  }
}

class MainNav extends ConsumerWidget {
  const MainNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).currentUser;
    if (user == null) return const _AuthPage();
    return user.isSeller ? const SellerNav() : const BuyerNav();
  }
}

class BuyerNav extends ConsumerStatefulWidget {
  const BuyerNav({super.key});

  @override
  ConsumerState<BuyerNav> createState() => _BuyerNavState();
}

class _BuyerNavState extends ConsumerState<BuyerNav> {
  int _index = 0;

  static const _pages = [
    StatusFeedScreen(),
    ProductListScreen(),
    ChatListScreen(
      title: 'Messages privés',
      emptySubtitle: 'Contactez un vendeur depuis une annonce.',
    ),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;
    if (user == null) return const _AuthPage();
    if (!user.isBuyer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/seller-dashboard');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    _listenChats(user.id);
    final unreadCount = _unreadCount(ref);

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Feed',
          ),
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Produits',
          ),
          NavigationDestination(
            icon: _MessageBadge(unreadCount: unreadCount),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Compte',
          ),
        ],
      ),
    );
  }

  void _listenChats(String userId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatNotifierProvider.notifier).listenChats(userId);
    });
  }
}

class SellerNav extends ConsumerStatefulWidget {
  const SellerNav({super.key});

  @override
  ConsumerState<SellerNav> createState() => _SellerNavState();
}

class _SellerNavState extends ConsumerState<SellerNav> {
  int _index = 0;

  static const _pages = [
    SellerDashboardScreen(),
    MyListingsScreen(),
    ChatListScreen(
      title: 'Messages acheteurs',
      emptySubtitle: 'Les conversations avec les acheteurs apparaîtront ici.',
    ),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;
    if (user == null) return const _AuthPage();
    if (!user.isSeller) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/buyer-home');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    _listenChats(user.id);
    final unreadCount = _unreadCount(ref);

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Annonces',
          ),
          NavigationDestination(
            icon: _MessageBadge(unreadCount: unreadCount),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  void _listenChats(String userId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatNotifierProvider.notifier).listenChats(userId);
    });
  }
}

class _MessageBadge extends StatelessWidget {
  const _MessageBadge({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: unreadCount > 0,
      label: Text('$unreadCount'),
      child: const Icon(Icons.chat_bubble_outline),
    );
  }
}

int _unreadCount(WidgetRef ref) {
  return ref.watch(
    chatNotifierProvider.select(
      (state) =>
          state.chats.fold<int>(0, (total, chat) => total + chat.unreadCount),
    ),
  );
}

class _OpenChatScreen extends ConsumerStatefulWidget {
  const _OpenChatScreen({required this.args});

  final Map<String, Object?> args;

  @override
  ConsumerState<_OpenChatScreen> createState() => _OpenChatScreenState();
}

class _OpenChatScreenState extends ConsumerState<_OpenChatScreen> {
  late Future<Chat> _chatFuture;

  @override
  void initState() {
    super.initState();
    _chatFuture = _openChat();
  }

  Future<Chat> _openChat() {
    final me = ref.read(authNotifierProvider).currentUser;
    final sellerId = widget.args['sellerId'] as String?;
    final sellerName = widget.args['sellerName'] as String? ?? 'Vendeur';
    final buyerId = widget.args['buyerId'] as String? ?? me?.id;
    final buyerName =
        widget.args['buyerName'] as String? ?? me?.name ?? 'Acheteur';
    final listingId = widget.args['listingId'] as String?;
    final listingTitle = widget.args['listingTitle'] as String?;

    if (me == null) {
      throw StateError('Utilisateur non connecté.');
    }
    if (sellerId == null || sellerId.trim().isEmpty) {
      throw StateError('Vendeur introuvable.');
    }
    if (buyerId == null || buyerId.trim().isEmpty) {
      throw StateError('Acheteur introuvable.');
    }

    return ref
        .read(chatNotifierProvider.notifier)
        .openChat(
          buyerId: me.isBuyer ? me.id : buyerId,
          sellerId: me.isSeller ? me.id : sellerId,
          buyerName: me.isBuyer ? me.name : buyerName,
          sellerName: me.isSeller ? me.name : sellerName,
          buyerProfileImageUrl: me.isBuyer ? me.profileImageUrl : null,
          sellerProfileImageUrl: me.isSeller ? me.profileImageUrl : null,
          listingId: listingId,
          listingTitle: listingTitle,
        );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Chat>(
      future: _chatFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Messages')),
            body: Center(
              child: const Text(
                "Impossible d'ouvrir cette conversation pour le moment.",
              ),
            ),
          );
        }

        return ChatScreen(chat: snapshot.data!);
      },
    );
  }
}

class _AuthPage extends ConsumerWidget {
  const _AuthPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Connexion')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OccasionLogo(size: 132),
                const SizedBox(height: 18),
                Text(
                  'Occasion',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Connectez-vous ou créez un compte pour continuer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400]),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: authState.isAuthenticated
                      ? null
                      : () => context.go('/login'),
                  icon: const Icon(Icons.login),
                  label: const Text('Se connecter'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: authState.isAuthenticated
                      ? null
                      : () => context.go('/register'),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Inscription'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
