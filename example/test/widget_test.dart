import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('renders request lab and benchmark tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Request Lab'), findsOneWidget);
    expect(find.text('Benchmark'), findsOneWidget);
    expect(find.text('Send request'), findsOneWidget);

    await tester.tap(find.text('Benchmark'));
    await tester.pumpAndSettle();

    expect(find.text('Preset'), findsOneWidget);
    expect(find.text('Require Rust init (fail fast)'), findsOneWidget);
    expect(find.text('Run local benchmark'), findsOneWidget);
  });
}
