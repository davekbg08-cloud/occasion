import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/theme/motion.dart';

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int value = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => value++),
    child: Text('compteur $value'),
  );
}

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('FadeIndexedStack : changer d’onglet conserve l’état des autres '
      'onglets', (tester) async {
    Widget stack(int index) => _app(
      FadeIndexedStack(
        index: index,
        children: const [_Counter(), Text('onglet 2')],
      ),
    );

    await tester.pumpWidget(stack(0));
    await tester.tap(find.text('compteur 0'));
    await tester.pump();
    expect(find.text('compteur 1'), findsOneWidget);

    await tester.pumpWidget(stack(1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(stack(0));
    await tester.pumpAndSettle();
    expect(find.text('compteur 1'), findsOneWidget);
  });

  testWidgets('AppearOnce : contenu pleinement visible à la fin, et '
      'immédiatement si l’utilisateur a réduit les animations', (tester) async {
    await tester.pumpWidget(_app(const AppearOnce(child: Text('carte'))));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);

    await tester.pumpWidget(
      _app(const AppearOnce(child: Text('carte')), reduceMotion: true),
    );
    expect(find.byType(Opacity), findsNothing);
    expect(find.text('carte'), findsOneWidget);
  });

  testWidgets('PressableScale ne bloque jamais le tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        PressableScale(
          child: TextButton(onPressed: () => taps++, child: const Text('ok')),
        ),
      ),
    );
    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('SkeletonPulse s’arrête quand les animations sont réduites', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const SkeletonPulse(width: 10, height: 10), reduceMotion: true),
    );
    // pumpAndSettle échouerait (délai dépassé) si l’animation tournait.
    await tester.pumpAndSettle();
  });

  testWidgets('RollingSwitcher passe à l’élément suivant après l’intervalle, '
      'puis revient au premier', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RollingSwitcher(
          interval: Duration(seconds: 3),
          items: [Text('batterie'), Text('iphone')],
        ),
      ),
    );
    expect(find.text('batterie'), findsOneWidget);
    expect(find.text('iphone'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('iphone'), findsOneWidget);
    expect(find.text('batterie'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('batterie'), findsOneWidget);
  });

  testWidgets('RollingSwitcher reste sur le premier élément quand les '
      'animations sont réduites', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: RollingSwitcher(
            interval: Duration(seconds: 3),
            items: [Text('batterie'), Text('iphone')],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('batterie'), findsOneWidget);
    expect(find.text('iphone'), findsNothing);
  });
}
