import 'package:farly/models/remote_layout.dart';
import 'package:farly/storage/layout_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote layout round-trips and fills missing blocks', () {
    const trimmed = RemoteLayout(
      blocks: [RemoteBlockId.pad, RemoteBlockId.chrome],
      chrome: [ChromeId.home, ChromeId.back],
    );
    final restored = RemoteLayout.fromJson(trimmed.toJson());
    expect(restored.chrome, [ChromeId.home, ChromeId.back]);
    expect(restored.blocks.first, RemoteBlockId.pad);
    expect(restored.blocks, containsAll(RemoteBlockId.values));
    expect(RemoteLayout.defaults.isDefault, isTrue);
    expect(trimmed.isDefault, isFalse);
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
