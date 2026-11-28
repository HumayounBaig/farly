import 'package:farly/state/feedback_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redact', () {
    test('strips IPv4, IPv6, MAC, hostnames and tokens', () {
      expect(redact('connect 192.168.1.20:8002 failed'), 'connect [redacted]:8002 failed');
      expect(redact('to fe80::1a2b:3c4d%en0 now'), 'to [redacted] now');
      expect(redact('to 2001:db8:0:0:0:0:0:1 now'), 'to [redacted] now');
      expect(redact('to ::ffff:192.168.1.5 now'), 'to [redacted] now');
      expect(redact('mac AA:BB:CC:11:22:33 seen'), 'mac [redacted] seen');
      expect(redact('mac aa-bb-cc-11-22-33 seen'), 'mac [redacted] seen');
      expect(redact('host living-room-tv.local down'), 'host [redacted] down');
      expect(redact('token 3f9a8c1e5b7d4a2f9c0e1d2b3a4f5e6d ok'), 'token [redacted] ok');
      expect(redact('key QUJDREVGR0hJSktMTU5PUFFSU1RVVldY=='), 'key [redacted]');
    });

    test('leaves a normal sentence and a clock time alone', () {
      const line = 'Samsung ready: Connection dropped at 12:34:56. Trying again.';
      expect(redact(line), line);
    });
  });

  test('ring buffer keeps only the newest lines', () {
    final log = FeedbackLog(capacity: 3);
    for (var i = 0; i < 5; i++) {
      log.add('line $i');
    }
    expect(log.lines.length, 3);
    expect(log.lines.first, endsWith('line 2'));
    expect(log.lines.last, endsWith('line 4'));
  });

  test('add redacts before storing', () {
    final log = FeedbackLog()..add('fail 10.0.0.5');
    expect(log.lines.single, isNot(contains('10.0.0.5')));
  });

  group('feedbackUri', () {
    test('never splits an emoji when trimming', () {
      final uri = feedbackUri('😀' * 100, log: FeedbackLog(), maxLength: 400);
      final title = uri.queryParameters['title']!;
      expect(title, matches(RegExp(r'^Feedback: (😀)+$')));
      expect(title.runes.length, lessThanOrEqualTo('Feedback: '.length + 60));
      expect(feedbackUri('😀' * 100, log: FeedbackLog()).queryParameters['title'], 'Feedback: ${'😀' * 60}');
      expect(uri.queryParameters['body']!.runes.every((r) => r < 0xD800 || r > 0xDFFF), isTrue);
    });
    test('encodes title and body and sets the label', () {
      final uri = feedbackUri('TV & remote "broke"', log: FeedbackLog());
      expect(uri.toString(), startsWith('$feedbackIssueBase?'));
      expect(uri.queryParameters['title'], 'Feedback: TV & remote "broke"');
      expect(uri.queryParameters['labels'], 'feedback');
      expect(uri.toString(), isNot(contains('&remote')));
    });

    test('title is cut to about 60 characters', () {
      final uri = feedbackUri('x ' * 100, log: FeedbackLog());
      expect(uri.queryParameters['title']!.length, 'Feedback: '.length + 60);
    });

    test('caps length by dropping the oldest log lines first', () {
      final log = FeedbackLog();
      for (var i = 0; i < 150; i++) {
        log.add('event number $i happened');
      }
      final uri = feedbackUri('it broke', log: log, maxLength: 2000);
      final body = uri.queryParameters['body']!;
      expect(uri.toString().length, lessThanOrEqualTo(2000));
      expect(body, contains('…older lines trimmed'));
      expect(body, contains('event number 149'));
      expect(body, isNot(contains('event number 0 ')));
    });

    test('omits the log when disabled', () {
      final log = FeedbackLog()..add('secret-ish line');
      final uri = feedbackUri('hi', log: log, includeLog: false);
      expect(uri.queryParameters['body'], 'hi');
    });
  });
}
