import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/remote_tree.dart';

class _Node {
  final String name;
  final List<_Node>? kids; // null = file
  const _Node(this.name, [this.kids]);
}

void main() {
  test('collectRemoteFiles walks selected folders recursively and keeps relative paths', () async {
    const tree = _Node('root', [
      _Node('a.bin'),
      _Node('dir', [
        _Node('.'),
        _Node('..'),
        _Node('b.bin'),
        _Node('sub', [_Node('c.bin')]),
        _Node('empty', []),
      ]),
    ]);
    final visited = <String>[];

    final files = await collectRemoteFiles<_Node>(
      tree.kids!,
      nameOf: (n) => n.name,
      isDir: (n) => n.kids != null,
      children: (dir, rel) async {
        visited.add(rel);
        return dir.kids!;
      },
    );

    expect(files.map((f) => f.relPath), ['a.bin', 'dir/b.bin', 'dir/sub/c.bin']);
    expect(files.last.entry.name, 'c.bin');
    expect(visited, ['dir', 'dir/sub', 'dir/empty']); // '.' and '..' never followed
  });
}
