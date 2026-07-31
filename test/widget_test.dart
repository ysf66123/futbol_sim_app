import 'package:flutter_test/flutter_test.dart';

import 'package:football_sim_flutter/src/app/app.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const FootballSimApp());
    await tester.pump();

    expect(find.textContaining('Yükleniyor'), findsOneWidget);
  });
}
