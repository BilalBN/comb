/// A note body as a list of lines ("blocks") that the editor can show as
/// real checkboxes, bullets and headings, then turn back into exactly the
/// same markdown. One block is always one line, so a block's index is the
/// line number (which "Make task" uses).
library;

enum BlockKind { text, heading, bullet, check, embed }

class Block {
  Block(this.kind, this.text, {this.indent = '', this.marker = '-', this.done = false, this.level = 0, this.raw});

  factory Block.parse(String line) {
    final check = _check.firstMatch(line);
    if (check != null) {
      return Block(
        BlockKind.check,
        check.group(4) ?? '',
        indent: check.group(1)!,
        marker: check.group(2)!,
        done: check.group(3)!.toLowerCase() == 'x',
        raw: line,
      );
    }
    final bullet = _bullet.firstMatch(line);
    if (bullet != null) return Block(BlockKind.bullet, bullet.group(3)!, indent: bullet.group(1)!, marker: bullet.group(2)!, raw: line);
    final heading = _heading.firstMatch(line);
    if (heading != null) return Block(BlockKind.heading, heading.group(2)!, level: heading.group(1)!.length, raw: line);
    final embed = _embed.firstMatch(line);
    if (embed != null) return Block(BlockKind.embed, embed.group(1)!, raw: line);
    return Block(BlockKind.text, line, raw: line);
  }

  BlockKind kind;
  String text;
  String indent;
  String marker;
  bool done;

  /// 1–3 for headings.
  int level;

  /// The line as it was read; written back unchanged until the block is edited.
  String? raw;

  static final _check = RegExp(r'^(\s*)([-*]) \[( |x|X)\](?: (.*))?$');
  static final _bullet = RegExp(r'^(\s*)([-*]) (.*)$');
  static final _heading = RegExp(r'^(#{1,6}) (.*)$');
  static final _embed = RegExp(r'^!\[\[([^\]]+)\]\]\s*$');

  bool get isList => kind == BlockKind.check || kind == BlockKind.bullet;

  /// Marks the block as changed so it is written from its parts.
  void touch() => raw = null;

  String toLine() {
    if (raw != null) return raw!;
    return switch (kind) {
      BlockKind.check => '$indent$marker [${done ? 'x' : ' '}] $text',
      BlockKind.bullet => '$indent$marker $text',
      BlockKind.heading => '${'#' * level.clamp(1, 6)} $text',
      BlockKind.embed => '![[$text]]',
      BlockKind.text => text,
    };
  }
}

List<Block> parseBlocks(String body) => body.split('\n').map(Block.parse).toList();

String serializeBlocks(List<Block> blocks) => blocks.map((b) => b.toLine()).join('\n');

/// Where `[[links]]` are in a line of text, for showing them as links.
class LinkSpan {
  LinkSpan(this.start, this.end, this.target, this.label);

  /// The whole `[[...]]`, in the raw text.
  final int start, end;
  final String target;
  final String label;
}

final _link = RegExp(r'\[\[([^\]|#\n]+)(#[^\]|\n]*)?(?:\|([^\]\n]*))?\]\]');

List<LinkSpan> linkSpans(String text) => [
  for (final m in _link.allMatches(text)) LinkSpan(m.start, m.end, m.group(1)!.trim(), (m.group(3) ?? m.group(1)!).trim()),
];
