import 'package:farly/models/remote_layout.dart';
import 'package:farly/storage/layout_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote layout round-trips and keeps intentional hides', () {
    const trimmed = RemoteLayout(
      blocks: [RemoteBlockId.pad, RemoteBlockId.chrome],
      chrome: [ChromeId.home, ChromeId.back],
    );
    final restored = RemoteLayout.fromJson(trimmed.toJson());
    expect(restored.chrome, [ChromeId.home, ChromeId.back]);
    expect(restored.blocks, [RemoteBlockId.pad, RemoteBlockId.chrome]);
    expect(restored.blocks, isNot(contains(RemoteBlockId.transport)));
    expect(RemoteLayout.defaults.isDefault, isTrue);
    expect(trimmed.isDefault, isFalse);
  });

  test('empty blocks and chrome fall back to defaults', () {
    final restored = RemoteLayout.fromJson(const {
      'blocks': <String>[],
      'chrome': <String>[],
    });
    expect(restored.blocks, RemoteLayout.defaults.blocks);
    expect(restored.chrome, RemoteLayout.defaults.chrome);
  });

  test('memory layout store persists writes', () async {
    final store = MemoryLayoutStore();
    final next = RemoteLayout.defaults.copyWith(
      chrome: const [ChromeId.home, ChromeId.menu],
      blocks: const [
        RemoteBlockId.pad,
        RemoteBlockId.levels,
        RemoteBlockId.chrome,
        RemoteBlockId.transport,
        RemoteBlockId.shortcuts,
        RemoteBlockId.powerRow,
      ],
    );
    await store.write(next);
    expect(await store.read(), same(next));
  });
}
