import 'dart:async';

import 'package:flutter/material.dart';

/// Animations de l'app : courtes, discrètes, et désactivées quand le
/// téléphone demande de réduire les animations (accessibilité).
abstract final class OccasionMotion {
  static const short = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
  static const enter = Curves.easeOutCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Transition entre écrans : fondu + légère montée (Material 3). Le balayage
/// retour natif d'iOS est conservé via `CupertinoPageTransitionsBuilder`
/// dans le thème.
class OccasionPageTransitionsBuilder extends PageTransitionsBuilder {
  const OccasionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (OccasionMotion.reduced(context)) return child;
    final enter = CurvedAnimation(
      parent: animation,
      curve: OccasionMotion.enter,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(enter),
        child: child,
      ),
    );
  }
}

/// `IndexedStack` qui fond l'onglet affiché à chaque changement, sans
/// reconstruire les autres (position de défilement et état conservés).
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: OccasionMotion.short,
    value: 1,
  );

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index && !OccasionMotion.reduced(context)) {
      _controller.forward(from: 0.4);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _controller,
        curve: OccasionMotion.enter,
      ),
      child: IndexedStack(index: widget.index, children: widget.children),
    );
  }
}

/// Fait apparaître [child] une seule fois (fondu + légère montée). [order]
/// décale un peu les premiers éléments d'une liste, jamais au-delà de
/// quelques dizaines de millisecondes.
class AppearOnce extends StatelessWidget {
  const AppearOnce({super.key, required this.child, this.order = 0});

  final Widget child;
  final int order;

  @override
  Widget build(BuildContext context) {
    if (OccasionMotion.reduced(context)) return child;
    final delayMs = (order.clamp(0, 5)) * 40;
    final total = OccasionMotion.medium + Duration(milliseconds: delayMs);
    final start = delayMs / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: OccasionMotion.enter),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Léger enfoncement au toucher (cartes) — retour visuel immédiat, sans
/// intercepter le tap lui-même.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child});

  final Widget child;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    if (OccasionMotion.reduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Bloc gris qui « respire » doucement : remplace les roues de chargement
/// dans les emplacements d'images et les squelettes de liste.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({
    super.key,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
    this.color,
  });

  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final Color? color;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (OccasionMotion.reduced(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? Colors.white.withValues(alpha: 0.08);
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.45,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: widget.borderRadius,
        ),
      ),
    );
  }
}

/// Fait défiler [items] l'un après l'autre, chacun glissant vers le haut
/// pour laisser monter le suivant (texte d'aide de la barre de recherche,
/// ligne d'infos des cartes annonce). [initialDelay] décale le premier
/// changement pour que les cartes voisines ne bougent pas toutes en même
/// temps. Animations réduites : seul le premier élément est affiché.
class RollingSwitcher extends StatefulWidget {
  const RollingSwitcher({
    super.key,
    required this.items,
    this.interval = const Duration(seconds: 3),
    this.initialDelay = Duration.zero,
    this.onChanged,
    this.alignment = Alignment.centerLeft,
  });

  final List<Widget> items;
  final Duration interval;
  final Duration initialDelay;
  final ValueChanged<int>? onChanged;
  final AlignmentGeometry alignment;

  @override
  State<RollingSwitcher> createState() => _RollingSwitcherState();
}

class _RollingSwitcherState extends State<RollingSwitcher> {
  Timer? _timer;
  int _index = 0;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = OccasionMotion.reduced(context);
    _schedule(widget.initialDelay + widget.interval);
  }

  @override
  void didUpdateWidget(RollingSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.items.length) _index = 0;
    if (oldWidget.items.length != widget.items.length) {
      _schedule(widget.interval);
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = null;
    if (_reduced || widget.items.length < 2) return;
    _timer = Timer(delay, _next);
  }

  void _next() {
    if (!mounted || widget.items.length < 2) return;
    setState(() => _index = (_index + 1) % widget.items.length);
    widget.onChanged?.call(_index);
    _schedule(widget.interval);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final current = KeyedSubtree(
      key: ValueKey(_index),
      child: widget.items[_index],
    );
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        switchInCurve: OccasionMotion.enter,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: widget.alignment,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) {
          // Entrant : monte depuis le bas. Sortant (animation inversée) :
          // continue vers le haut.
          final incoming = child.key == current.key;
          final offset = Tween<Offset>(
            begin: incoming ? const Offset(0, 1) : const Offset(0, -1),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: current,
      ),
    );
  }
}
