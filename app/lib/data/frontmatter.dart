/// Markdown files with YAML frontmatter, read and written the way Obsidian
/// expects. Keys Comb doesn't know (added in Obsidian) are kept as they are.
library;

import 'package:yaml/yaml.dart';

class MarkdownDoc {
  MarkdownDoc(this.fields, this.body);

  /// Ordered: writing keeps this order, so diffs stay small.
  final Map<String, Object?> fields;
  String body;

  static MarkdownDoc parse(String text) {
    final normalized = text.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) return MarkdownDoc({}, normalized);
    final end = normalized.indexOf('\n---', 4);
    if (end < 0) return MarkdownDoc({}, normalized);
    final yamlText = normalized.substring(4, end);
    var bodyStart = end + 4;
    if (bodyStart < normalized.length && normalized[bodyStart] == '\n') bodyStart++;
    final body = bodyStart <= normalized.length ? normalized.substring(bodyStart) : '';
    final fields = <String, Object?>{};
    try {
      final loaded = loadYaml(yamlText);
      if (loaded is YamlMap) {
        for (final e in loaded.entries) {
          fields[e.key.toString()] = _plain(e.value);
        }
      }
    } on YamlException {
      return MarkdownDoc({}, normalized);
    }
    return MarkdownDoc(fields, body);
  }

  static Object? _plain(Object? v) {
    if (v is YamlList) return v.map(_plain).toList();
    if (v is YamlMap) return {for (final e in v.entries) e.key.toString(): _plain(e.value)};
    return v;
  }

  String render() {
    final lines = <String>[];
    fields.forEach((k, v) {
      if (v == null) return;
      if (v is List) {
        if (v.isEmpty) return;
        lines.add('$k:');
        for (final item in v) {
          lines.add('  - ${_scalar(item)}');
        }
      } else {
        lines.add('$k: ${_scalar(v)}');
      }
    });
    if (lines.isEmpty) return body;
    return '---\n${lines.join('\n')}\n---\n$body';
  }

  static String _scalar(Object? v) {
    if (v is bool || v is num) return '$v';
    final s = v.toString();
    final needsQuotes = s.isEmpty ||
        RegExp(r'^[\s\-?:,\[\]{}#&*!|>%@`"' "'" r']').hasMatch(s) ||
        s.contains(': ') ||
        s.contains(' #') ||
        s.endsWith(':') ||
        s != s.trim() ||
        RegExp(r'^(true|false|yes|no|null|~|on|off)$', caseSensitive: false).hasMatch(s) ||
        RegExp(r'^[-+]?\d').hasMatch(s) && !RegExp(r'^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2})?$').hasMatch(s);
    if (!needsQuotes) return s;
    return '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
}

/// `[[Title]]` and `[[Title|shown text]]` links in a body.
final wikiLink = RegExp(r'\[\[([^\]|#\n]+)(?:#[^\]|\n]*)?(?:\|[^\]\n]*)?\]\]');

Iterable<String> linksIn(String text) => wikiLink.allMatches(text).map((m) => m.group(1)!.trim());

String unlink(Object? value) {
  if (value == null) return '';
  final s = value.toString();
  final m = wikiLink.firstMatch(s);
  return m != null ? m.group(1)!.trim() : s;
}

String link(String title) => '[[$title]]';
