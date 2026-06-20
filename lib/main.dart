import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/chat.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/cart_screen.dart';
import 'screens/add_status_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/id_scan_screen.dart';
import 'screens/payment_screen.dart';
import 'screens/phone_auth_screen.dart';
import 'screens/product_list_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/status_feed_screen.dart';
import 'screens/subscription_screen.dart';
import 'services/notification_service.dart';
import 'services/service_locator.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeFirebase();
  configureServices();
  await NotificationService.init(appNavigatorKey);
  runApp(const ProviderScope(child: OccasionApp()));
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('Firebase non initialise : $error');
  }
}

class OccasionApp extends StatelessWidget {
  const OccasionApp({super.key});

  static final _router = GoRouter(
    navigatorKey: appNavigatorKey,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _AuthGate()),
      GoRoute(path: '/home', builder: (context, state) => const MainNav()),
      GoRoute(path: '/scan', builder: (context, state) => const IdScanScreen()),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
      GoRoute(path: '/payment', builder: (_, _) => const PaymentScreen()),
      GoRoute(
        path: '/subscription',
        builder: (_, _) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/role-selection',
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/phone-auth',
        builder: (context, state) {
          final role = state.extra as UserRole? ?? UserRole.buyer;

          return PhoneAuthScreen(role: role);
        },
      ),
      GoRoute(
        path: '/status',
        builder: (context, state) => const StatusFeedScreen(),
      ),
      GoRoute(
        path: '/add-status',
        builder: (context, state) => const AddStatusScreen(),
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) => const ProductListScreen(),
      ),
      GoRoute(
        path: '/chat-list',
        builder: (context, state) => const ChatListScreen(),
      ),
      GoRoute(
        path: '/chat-room',
        pageBuilder: (context, state) {
          final chat = state.extra as Chat;

          return CustomTransitionPage<void>(
            key: state.pageKey,
            child: ChatScreen(chat: chat),
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

          return _OpenChatScreen(args: args);
        },
      ),
      GoRoute(path: '/auth', builder: (context, state) => const _AuthPage()),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Gestion Money RDC',
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (currentUser == null) {
      return const RoleSelectionScreen();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.saveToken(currentUser.id);
    });

    return const MainNav();
  }
}

class MainNav extends ConsumerStatefulWidget {
  const MainNav({super.key});

  @override
  ConsumerState<MainNav> createState() => _MainNavState();
}

class _MainNavState extends ConsumerState<MainNav> {
  int _index = 0;

  static const _pages = [
    StatusFeedScreen(),
    ProductListScreen(),
    ChatListScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;
    if (user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(chatNotifierProvider.notifier).listenChats(user.id);
      });
    }

    final unreadCount = ref.watch(
      chatNotifierProvider.select(
        (state) =>
            state.chats.fold<int>(0, (sum, chat) => sum + chat.unreadCount),
      ),
    );

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
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
        ],
      ),
    );
  }
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
    final sellerId = widget.args['sellerId'] as String? ?? 'seller-demo';
    final sellerName = widget.args['sellerName'] as String? ?? 'Vendeur';
    final buyerId = widget.args['buyerId'] as String? ?? me?.id ?? 'buyer-demo';
    final buyerName =
        widget.args['buyerName'] as String? ?? me?.name ?? 'Acheteur';

    return ref
        .read(chatNotifierProvider.notifier)
        .openChat(
          buyerId: me?.isBuyer == false ? buyerId : me?.id ?? buyerId,
          sellerId: me?.isSeller == true ? me!.id : sellerId,
          buyerName: me?.isBuyer == false ? buyerName : me?.name ?? buyerName,
          sellerName: me?.isSeller == true ? me!.name : sellerName,
          buyerProfileImageUrl: me?.isBuyer == true
              ? me?.profileImageUrl
              : null,
          sellerProfileImageUrl: me?.isSeller == true
              ? me?.profileImageUrl
              : null,
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
              child: Text('Impossible d ouvrir le chat : ${snapshot.error}'),
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
        child: FilledButton.icon(
          onPressed: authState.isAuthenticated
              ? null
              : () async {
                  await ref.read(authNotifierProvider.notifier).login();
                  if (!context.mounted) return;
                  context.go('/home');
                },
          icon: const Icon(Icons.login),
          label: Text(
            authState.isAuthenticated ? 'Déjà connecté' : 'Se connecter',
          ),
        ),
      ),
    );
  }
}
