import 'package:farly/control/remote_session.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/models/remote_action.dart';
import 'package:farly/state/remote_controller.dart';
import 'package:farly/state/youtube_grid.dart';
import 'package:farly/widgets/tv_keyboard_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const u = RemoteAction.up, d = RemoteAction.down;
const l = RemoteAction.left, r = RemoteAction.right, s = RemoteAction.select;

void main() {
  test('cats from A', () {
    // C(0,2) A(0,0) T(2,5) S(2,4)
    expect(youtubeGridActions('cats').actions, [
      r, r, s, //
      l, l, s,
      d, d, r, r, r, r, r, s,
      l, s,
    ]);
  });

  test('space goes to row 3 col 0, down, select, up', () {
    final plan = youtubeGridActions('a b');
    expect(plan.actions, [
      s, // A
      d, d, d, d, s, u, // to (3,0), SPACE, back up
      u, u, u, r, s, // B (0,1) from (3,0)
    ]);
    expect(plan.end, (row: 0, col: 1));
  });

  test('unsupported characters error and send nothing', () {
    final plan = youtubeGridActions('a1b2!');
    expect(plan.actions, isEmpty);
    expect(plan.unsupported, ['1', '2', '!']);
    expect(plan.error, contains('1 2 !'));
  });

  test('mixed case, dash and apostrophe work; never left from col 0', () {
    expect(
      youtubeGridActions('CaTs').actions,
      youtubeGridActions('cats').actions,
    );
    expect(youtubeGridActions("-'").error, isNull);
    final keys = youtubeGridActions('a hat').actions;
    // Left after a Down-from-SPACE round trip would leave the grid.
    expect(keys, isNot(contains(l)));
  });

  test('search button path from the end cursor', () {
    expect(youtubeSearchActions((row: 3, col: 0)), [d, r, r, s]);
    expect(youtubeSearchActions((row: 0, col: 2)), [d, d, d, l, l, d, r, r, s]);
  });

  group('controller and sheet', () {
    final tv = const FarlyDevice(
      id: 'x',
      name: 'TV',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
    );

    test('grid keys go through send in order; cancel stops', () async {
      final session = _Session();
      final c = RemoteController(
        device: tv,
        onCredentials: (_) {},
        sessions: (_, _) => session,
      );
      await c.connect();
      await Future<void>.delayed(Duration.zero);
      expect(
        await c.sendKeysInOrder([r, s, d], spacing: Duration.zero),
        isTrue,
      );
      expect(session.sent, [r, s, d]);
      session.sent.clear();
      final run = c.sendKeysInOrder([
        r,
        r,
        r,
        r,
      ], spacing: const Duration(milliseconds: 5));
      c.cancelKeys();
      expect(await run, isFalse);
      expect(session.sent.length, lessThan(4));
      c.dispose();
    });

    Future<({int enters, List<RemoteAction> keys, List<String> searches})> pump(
      WidgetTester tester, {
      required bool supported,
    }) async {
      var enters = 0;
      final keys = <RemoteAction>[];
      final searches = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTvKeyboardSheet(
                context: context,
                onSend: (_) async => true,
                onEnter: () async => enters++,
                onSearchYoutube: supported
                    ? (q) async {
                        searches.add(q);
                        return true;
                      }
                    : null,
                onSendKeys: (k) async {
                  keys.addAll(k);
                  return true;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'cats');
      return (enters: enters, keys: keys, searches: searches);
    }

    testWidgets('Search YouTube only shows when supported', (tester) async {
      await pump(tester, supported: false);
      expect(find.text('Search YouTube'), findsNothing);
      expect(find.text('Type on YouTube’s keyboard'), findsOneWidget);
    });

    testWidgets('Search YouTube sends the text', (tester) async {
      final res = await pump(tester, supported: true);
      await tester.tap(find.text('Search YouTube'));
      await tester.pumpAndSettle();
      expect(res.searches, ['cats']);
    });

    testWidgets('grid typing sends keys and never Enter', (tester) async {
      var enters = 0;
      final keys = <RemoteAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTvKeyboardSheet(
                context: context,
                onSend: (_) async => true,
                onEnter: () async => enters++,
                onSendKeys: (k) async {
                  keys.addAll(k);
                  return true;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'cats');
      await tester.tap(find.text('Type on YouTube’s keyboard'));
      await tester.pumpAndSettle();
      expect(keys, youtubeGridActions('cats').actions);
      await tester.tap(find.text('Done')); // field was cleared
      await tester.pumpAndSettle();
      expect(enters, 0);
    });

    Future<({List<String> searches, List<int> enters})> pumpUnconfirmed(
      WidgetTester tester, {
      bool password = false,
    }) async {
      final searches = <String>[];
      final enters = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTvKeyboardSheet(
                context: context,
                onSend: (_) async => false, // no TV text box took it
                onEnter: () async => enters.add(1),
                onSearchYoutube: (q) async {
                  searches.add(q);
                  return true;
                },
                onSendKeys: (_) async => true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (password) {
        await tester.tap(find.byIcon(Icons.visibility_rounded));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), 'baby sleep song');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      return (searches: searches, enters: enters);
    }

    testWidgets('Done searches YouTube when no TV text box took the text',
        (tester) async {
      final res = await pumpUnconfirmed(tester);
      expect(res.searches, ['baby sleep song']);
      expect(res.enters, isEmpty);
    });

    testWidgets('Done never sends a password to YouTube search',
        (tester) async {
      final res = await pumpUnconfirmed(tester, password: true);
      expect(res.searches, isEmpty);
      expect(res.enters, isEmpty);
    });
  });
}

class _Session extends NotedSession {
  _Session() : super(phase: SessionPhase.ready, detail: 'ok');
  final sent = <RemoteAction>[];
  @override
  bool get supportsText => true;
  @override
  Future<CommandResult> send(RemoteAction action) async {
    sent.add(action);
    return const CommandResult(true);
  }
}
