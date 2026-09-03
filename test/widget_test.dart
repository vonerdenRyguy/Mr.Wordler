// Basic smoke test: the app boots and the menu screen shows up with
// its title and both action buttons.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:namer_app/main.dart';
import 'package:namer_app/util/theme_notifier.dart';

void main() {
  testWidgets('Menu screen shows title and buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeNotifier(),
        child: const MyApp(),
      ),
    );

    expect(find.text('Mr. Wordler'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
  });
}
