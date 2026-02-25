import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('renders benchmark controls', (WidgetTester tester) async {
    await tester.pumpWidget(const BenchmarkExampleApp());

    expect(find.text('Preset'), findsOneWidget);
    expect(find.text('Require Rust init (fail fast)'), findsOneWidget);
    expect(find.text('Run local benchmark'), findsOneWidget);
  });
}
