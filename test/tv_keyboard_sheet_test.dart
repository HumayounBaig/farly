import 'package:farly/widgets/tv_keyboard_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<int> typeAndTapDone(WidgetTester tester, bool landed) async {
    var enters = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTvKeyboardSheet(
              context: context,
              onSend: (_) async => landed,
              failureDetail: () => 'no echo',
              onEnter: () async => enters++,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'cats');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    return enters;
  }

  testWidgets('Done presses Enter when the text landed', (tester) async {
    expect(await typeAndTapDone(tester, true), 1);
    expect(find.text('no echo'), findsNothing);
  });

  testWidgets('Done does not press Enter when the text did not land', (
    tester,
  ) async {
    expect(await typeAndTapDone(tester, false), 0);
    expect(find.text('no echo'), findsOneWidget);
    expect(find.text('cats'), findsOneWidget); // text kept in the box
  });
}
