import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

const feedbackIssueBase = 'https://github.com/HumayounBaig/farly/issues/new';

final _patterns = [
  RegExp(r'\b[0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){5}\b'), // MAC
  RegExp(r'(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}(?:%\w+)?'), // IPv6, full
  RegExp(r'[0-9a-fA-F:]*::[0-9a-fA-F:.]*(?:%\w+)?'), // IPv6, compressed or IPv4-mapped
  RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b'), // IPv4
  RegExp(r'[\w-]+\.(?:local|lan|home|localdomain|internal)\b'), // hostnames
  RegExp(r'[A-Za-z0-9+/=_-]{20,}'), // tokens, keys, long hex/base64
];

/// Strips anything that could identify a person, network or pairing.
String redact(String text) {
  for (final pattern in _patterns) {
    text = text.replaceAll(pattern, '[redacted]');
  }
  return text;
}

/// In-memory ring buffer of redacted lines. Never written to disk or sent.
class FeedbackLog {
  FeedbackLog({this.capacity = 150});

  final int capacity;
  final _lines = Queue<String>();
  final brands = <String>{};

  List<String> get lines => List.unmodifiable(_lines);

  void add(String message, {DateTime? now}) {
    final stamp = (now ?? DateTime.now()).toUtc().toString().substring(0, 19);
    _lines.add('$stamp ${redact(message)}');
    while (_lines.length > capacity) {
      _lines.removeFirst();
    }
  }

  List<String> header() {
    final os = kIsWeb
        ? 'web'
        : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    final tvs = brands.isEmpty ? 'none' : (brands.toList()..sort()).join(', ');
    return [redact('Platform: $os'), 'TVs: $tvs'];
  }

  /// The exact diagnostic text that goes into an issue.
  String report([List<String>? body]) =>
      [...header(), ...(body ?? lines)].join('\n');
}

final feedbackLog = FeedbackLog();

/// Prefilled GitHub issue link, trimmed to [maxLength]: oldest log lines go
/// first, then the description itself.
Uri feedbackUri(
  String description, {
  FeedbackLog? log,
  bool includeLog = true,
  int maxLength = 7000,
}) {
  final source = log ?? feedbackLog;
  var text = description.trim();
  var dropped = 0;
  final all = includeLog ? source.lines : const <String>[];
  Uri build() {
    final diag = includeLog
        ? '\n\n```\n${dropped > 0 ? '…older lines trimmed\n' : ''}'
              '${source.report(all.sublist(dropped))}\n```'
        : '';
    final head = _clip(text, 60);
    return Uri.parse(feedbackIssueBase).replace(
      queryParameters: {
        'title': 'Feedback: $head',
        'body': '$text$diag',
        'labels': 'feedback',
      },
    );
  }

  var uri = build();
  while (uri.toString().length > maxLength && dropped < all.length) {
    dropped += 1;
    uri = build();
  }
  while (uri.toString().length > maxLength && text.isNotEmpty) {
    text = _clip(text, text.runes.length * 9 ~/ 10);
    uri = build();
  }
  return uri;
}

/// Cuts by code point so an emoji is never split into a broken surrogate.
String _clip(String text, int max) => text.runes.length <= max
    ? text
    : String.fromCharCodes(text.runes.take(max));
