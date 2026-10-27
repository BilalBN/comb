import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/blocks.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../theme.dart';
import 'link_picker.dart';

/// Shows `[[links]]` as links: the brackets disappear unless the line is
/// being edited, so the text never moves under the cursor.
class LinkTextController extends TextEditingController {
  LinkTextController({super.text});

  bool showMarks = false;
  Color linkColor = Colors.blue;
  Color markColor = Colors.grey;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final links = linkSpans(text);
    if (links.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final base = style ?? const TextStyle();
    final mark = showMarks
        ? base.copyWith(color: markColor, decoration: TextDecoration.none)
        : base.copyWith(color: Colors.transparent, fontSize: 0.1, letterSpacing: 0, decoration: TextDecoration.none);
    final linkStyle = base.copyWith(color: linkColor, fontWeight: FontWeight.w500);
    final children = <InlineSpan>[];
    var i = 0;
    for (final l in links) {
      if (l.start > i) children.add(TextSpan(text: text.substring(i, l.start)));
      final inner = text.substring(l.start + 2, l.end - 2);
      final pipe = inner.indexOf('|');
      if (pipe >= 0 && !showMarks) {
        // [[Target|Label]] shows only the label.
        children.add(TextSpan(text: '[[${inner.substring(0, pipe + 1)}', style: mark));
        children.add(TextSpan(text: inner.substring(pipe + 1), style: linkStyle));
      } else {
        children.add(TextSpan(text: '[[', style: mark));
        children.add(TextSpan(text: inner, style: linkStyle));
      }
      children.add(TextSpan(text: ']]', style: mark));
      i = l.end;
    }
    if (i < text.length) children.add(TextSpan(text: text.substring(i)));
    return TextSpan(style: base, children: children);
  }
}

class _Line {
  _Line(this.block) : ctl = LinkTextController(text: block.kind == BlockKind.embed ? '' : block.text);
  Block block;
  final LinkTextController ctl;
  late final FocusNode focus;
  String last = '';
  bool tappedWhileIdle = false;
}

/// A markdown editor that shows checklists, bullets, headings and links as
/// they look, not as their symbols. Every line is one block; the markdown
/// it produces is what Obsidian sees.
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    super.key,
    required this.text,
    required this.onChanged,
    required this.lib,
    this.onOpenLink,
    this.onMakeTask,
    this.onOpenEmbed,
    this.onToggleCheck,
    this.hint = 'Write something…',
    this.toolbar = true,
    this.size = 15,
    this.selfTitle,
  });

  final String text;
  final ValueChanged<String> onChanged;
  final Library lib;
  final ValueChanged<String>? onOpenLink;

  /// Turns line [index] into a task; hidden when null.
  final ValueChanged<int>? onMakeTask;
  final ValueChanged<String>? onOpenEmbed;

  /// Called after a checkbox is ticked or unticked by a click.
  final VoidCallback? onToggleCheck;
  final String hint;
  final bool toolbar;
  final double size;

  /// The note's own title, left out of the link list.
  final String? selfTitle;

  @override
  State<MarkdownEditor> createState() => MarkdownEditorState();
}

class MarkdownEditorState extends State<MarkdownEditor> {
  final _lines = <_Line>[];
  String _current = '';
  _Line? _active;
  _Line? _hover;

  @override
  void initState() {
    super.initState();
    _load(widget.text);
  }

  @override
  void didUpdateWidget(MarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Changes from another device or Obsidian, while nobody is typing here.
    if (widget.text != _current && !_lines.any((l) => l.focus.hasFocus)) {
      setState(() => _load(widget.text));
    }
  }

  @override
  void dispose() {
    for (final l in _lines) {
      _disposeLine(l);
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- model

  void _load(String text) {
    for (final l in _lines) {
      _disposeLine(l);
    }
    _lines
      ..clear()
      ..addAll(parseBlocks(text).map(_newLine));
    _current = text;
    _active = null;
  }

  /// Replaces the text from outside (after Make task, an attachment...).
  void reload(String text) => setState(() => _load(text));

  /// The markdown as it is right now.
  String get value => serializeBlocks(_lines.map((l) => l.block).toList());

  _Line _newLine(Block b) {
    final l = _Line(b);
    l.last = l.ctl.text;
    l.focus = FocusNode(onKeyEvent: (_, e) => _onKey(l, e));
    l.focus.addListener(() {
      if (!mounted) return;
      l.ctl.showMarks = l.focus.hasFocus;
      if (l.focus.hasFocus) _active = l;
      setState(() {});
    });
    l.ctl.addListener(() => _onEdit(l));
    return l;
  }

  void _disposeLine(_Line l) {
    l.ctl.dispose();
    l.focus.dispose();
  }

  void _emit() {
    final s = value;
    if (s == _current) return;
    _current = s;
    widget.onChanged(s);
  }

  void _focus(_Line l, int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_lines.contains(l)) return;
      l.focus.requestFocus();
      l.ctl.selection = TextSelection.collapsed(offset: offset.clamp(0, l.ctl.text.length));
    });
  }

  void _onEdit(_Line l) {
    final text = l.ctl.text;
    if (text == l.last) return;
    final before = l.last;
    l.last = text;
    if (text.contains('\n')) {
      _splitPasted(l);
      return;
    }
    l.block
      ..text = text
      ..touch();
    _emit();
    // Typing [[ opens the link list.
    final at = l.ctl.selection.baseOffset;
    if (text.length > before.length && at >= 2 && text.substring(at - 2, at) == '[[' && !text.substring(at).startsWith(']]')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickLink(l, at - 2, at));
    }
  }

  void _splitPasted(_Line l) {
    final caret = l.ctl.selection.baseOffset.clamp(0, l.ctl.text.length);
    final tail = l.ctl.text.length - caret;
    final parts = l.ctl.text.split('\n');
    final i = _lines.indexOf(l);
    _setText(l, parts.first);
    final added = [for (final p in parts.skip(1)) _newLine(Block.parse(p))];
    setState(() => _lines.insertAll(i + 1, added));
    final lastLine = added.last;
    _focus(lastLine, lastLine.ctl.text.length - tail);
    _emit();
  }

  void _setText(_Line l, String text) {
    l.last = text;
    l.ctl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    l.block
      ..text = text
      ..touch();
  }

  // ------------------------------------------------------------- keyboard

  KeyEventResult _onKey(_Line l, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final v = l.ctl.value;
    if (v.composing.isValid && !v.composing.isCollapsed) return KeyEventResult.ignored;
    final sel = v.selection;
    final i = _lines.indexOf(l);
    final key = e.logicalKey;
    final hw = HardwareKeyboard.instance;
    final atStart = sel.isCollapsed && sel.baseOffset == 0;
    final atEnd = sel.isCollapsed && sel.baseOffset == v.text.length;

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (hw.isMetaPressed || hw.isControlPressed) {
        if (widget.onMakeTask != null) _makeTaskOn(l);
        return KeyEventResult.handled;
      }
      _enter(l, sel);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace && atStart) {
      _backspace(l, i);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete && atEnd && i < _lines.length - 1) {
      final next = _lines[i + 1];
      if (next.block.kind != BlockKind.embed) {
        final at = v.text.length;
        _setText(l, v.text + next.ctl.text);
        _remove(next);
        _focus(l, at);
        _emit();
      }
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) && atStart && i > 0) {
      final prev = _previousText(i);
      if (prev != null) _focus(prev, prev.ctl.text.length);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) && atEnd && i < _lines.length - 1) {
      final next = _nextText(i);
      if (next != null) _focus(next, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab && l.block.isList) {
      setState(() {
        if (hw.isShiftPressed) {
          l.block.indent = l.block.indent.length >= 2 ? l.block.indent.substring(2) : '';
        } else {
          l.block.indent = '${l.block.indent}  ';
        }
        l.block.touch();
      });
      _emit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  _Line? _previousText(int i) {
    for (var k = i - 1; k >= 0; k--) {
      if (_lines[k].block.kind != BlockKind.embed) return _lines[k];
    }
    return null;
  }

  _Line? _nextText(int i) {
    for (var k = i + 1; k < _lines.length; k++) {
      if (_lines[k].block.kind != BlockKind.embed) return _lines[k];
    }
    return null;
  }

  void _enter(_Line l, TextSelection sel) {
    final b = l.block;
    final text = l.ctl.text;
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    // Enter on an empty list item ends the list.
    if (b.isList && text.isEmpty) {
      setState(() {
        if (b.indent.isNotEmpty) {
          b.indent = b.indent.length >= 2 ? b.indent.substring(2) : '';
        } else {
          b.kind = BlockKind.text;
        }
        b.touch();
      });
      _emit();
      return;
    }
    final i = _lines.indexOf(l);
    // Enter at the very start pushes the line down.
    if (start == 0 && end == 0 && text.isNotEmpty) {
      final above = _newLine(b.isList ? Block(b.kind, '', indent: b.indent, marker: b.marker) : Block(BlockKind.text, ''));
      setState(() => _lines.insert(i, above));
      _focus(l, 0);
      _emit();
      return;
    }
    final rest = text.substring(end);
    _setText(l, text.substring(0, start));
    final next = _newLine(b.isList ? Block(b.kind, rest, indent: b.indent, marker: b.marker) : Block(BlockKind.text, rest));
    setState(() => _lines.insert(i + 1, next));
    _focus(next, 0);
    _emit();
  }

  void _backspace(_Line l, int i) {
    final b = l.block;
    if (b.kind != BlockKind.text) {
      // First backspace removes the checkbox, bullet or heading.
      setState(() {
        b
          ..kind = BlockKind.text
          ..indent = ''
          ..touch();
      });
      _emit();
      return;
    }
    if (i == 0) return;
    final prev = _lines[i - 1];
    if (prev.block.kind == BlockKind.embed) {
      if (l.ctl.text.isEmpty) {
        _remove(l);
        _emit();
      }
      return;
    }
    final at = prev.ctl.text.length;
    _setText(prev, prev.ctl.text + l.ctl.text);
    _remove(l);
    _focus(prev, at);
    _emit();
  }

  void _remove(_Line l) {
    setState(() => _lines.remove(l));
    if (_active == l) _active = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _disposeLine(l));
  }

  // -------------------------------------------------------------- actions

  _Line _target() {
    final a = _active;
    if (a != null && _lines.contains(a) && a.block.kind != BlockKind.embed) return a;
    final last = _lines.isEmpty ? null : _lines.last;
    if (last != null && last.block.kind == BlockKind.text && last.ctl.text.isEmpty) return last;
    final l = _newLine(Block(BlockKind.text, ''));
    setState(() => _lines.add(l));
    return l;
  }

  /// Checklist button: turns the current line into a checklist item, or
  /// back into text.
  void toggleKind(BlockKind kind, {int level = 2}) {
    final l = _target();
    final b = l.block;
    setState(() {
      if (b.kind == kind && (kind != BlockKind.heading || b.level == level)) {
        b.kind = BlockKind.text;
      } else {
        b.kind = kind;
        b.level = level;
        if (kind == BlockKind.check) b.done = false;
        if (kind == BlockKind.heading) b.indent = '';
      }
      b.touch();
    });
    _focus(l, l.ctl.selection.baseOffset < 0 ? l.ctl.text.length : l.ctl.selection.baseOffset);
    _emit();
  }

  /// Checklist button: the current line becomes a checklist item (or
  /// stops being one). Enter then adds the next item.
  void addChecklistItem() => toggleKind(BlockKind.check);

  /// Link button: links the selected words, or asks what to link to.
  Future<void> insertLink() async {
    final l = _target();
    var sel = l.ctl.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: l.ctl.text.length);
    await _pickLink(l, sel.start, sel.end, initial: sel.textInside(l.ctl.text));
  }

  Future<void> _pickLink(_Line l, int start, int end, {String initial = ''}) async {
    final title = await pickLink(context, widget.lib, initial: initial, exclude: widget.selfTitle);
    if (!mounted || !_lines.contains(l)) return;
    if (title == null) {
      _focus(l, end);
      return;
    }
    final text = l.ctl.text;
    final s = start.clamp(0, text.length);
    final e = end.clamp(s, text.length);
    final insert = '[[$title]]';
    _setText(l, text.substring(0, s) + insert + text.substring(e));
    _focus(l, s + insert.length);
    _emit();
  }

  /// ⌘↩ or the button on a line.
  void makeTask() {
    final l = _active;
    if (l != null) _makeTaskOn(l);
  }

  void _makeTaskOn(_Line l) {
    if (widget.onMakeTask == null || !_lines.contains(l)) return;
    _emit();
    widget.onMakeTask!(_lines.indexOf(l));
  }

  void _toggleCheck(_Line l) {
    setState(() {
      l.block
        ..done = !l.block.done
        ..touch();
    });
    _emit();
    widget.onToggleCheck?.call();
  }

  /// The link the cursor is in, on the line being edited.
  LinkSpan? _linkAtCursor(_Line l) {
    final at = l.ctl.selection.baseOffset;
    if (at < 0) return null;
    for (final s in linkSpans(l.ctl.text)) {
      if (at > s.start && at < s.end) return s;
    }
    return null;
  }

  // ---------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final empty = _lines.length == 1 && _lines.first.ctl.text.isEmpty && _lines.first.block.kind == BlockKind.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.toolbar) ...[_toolbar(t), const SizedBox(height: 10)],
        for (final l in _lines) _line(context, t, l, hint: empty ? widget.hint : null),
        // Clicking under the last line continues writing there.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final last = _lines.isEmpty ? null : _lines.last;
            if (last != null && last.block.kind != BlockKind.embed && last.ctl.text.isEmpty) {
              _focus(last, 0);
            } else {
              final l = _newLine(Block(BlockKind.text, ''));
              setState(() => _lines.add(l));
              _focus(l, 0);
            }
          },
          child: const SizedBox(height: 48),
        ),
      ],
    );
  }

  Widget _toolbar(CombTokens t) {
    Widget btn(IconData icon, String tip, VoidCallback onTap, {String? label}) => Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: t.sub),
              if (label != null) ...[const SizedBox(width: 5), Text(label, style: t.text(13, color: t.sub))],
            ],
          ),
        ),
      ),
    );
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        btn(Icons.check_box_outlined, 'Checklist item', addChecklistItem, label: 'Checklist'),
        btn(Icons.format_list_bulleted, 'Bullet list', () => toggleKind(BlockKind.bullet)),
        btn(Icons.title, 'Heading', () => toggleKind(BlockKind.heading)),
        btn(Icons.link, 'Link to a note, task or person ([[)', insertLink, label: 'Link'),
        if (widget.onMakeTask != null)
          btn(Icons.task_alt, 'Make a task from this line (⌘↩)', () => _makeTaskOn(_target()), label: 'Make task'),
      ],
    );
  }

  TextStyle _style(CombTokens t, Block b) {
    final base = t.text(widget.size, height: 1.5);
    return switch (b.kind) {
      BlockKind.heading => t.text(
        switch (b.level) {
          1 => widget.size + 9,
          2 => widget.size + 5,
          _ => widget.size + 2,
        },
        weight: FontWeight.w600,
        height: 1.35,
      ),
      BlockKind.check when b.done => base.copyWith(color: t.sub, decoration: TextDecoration.lineThrough, decorationColor: t.sub),
      _ => base,
    };
  }

  Widget _line(BuildContext context, CombTokens t, _Line l, {String? hint}) {
    final b = l.block;
    if (b.kind == BlockKind.embed) return _embed(t, l);
    l.ctl
      ..linkColor = t.accent
      ..markColor = t.faint;
    final style = _style(t, b);
    final lineHeight = (style.fontSize ?? 15) * (style.height ?? 1.5);
    final indent = b.isList ? (b.indent.replaceAll('\t', '    ').length ~/ 2) * 22.0 : 0.0;
    final editing = l.focus.hasFocus;
    final link = editing ? _linkAtCursor(l) : null;
    final showMake =
        widget.onMakeTask != null && _hover == l && !editing && l.ctl.text.trim().isNotEmpty && linkSpans(l.ctl.text).length != 1;

    final field = Listener(
      onPointerDown: (_) => l.tappedWhileIdle = !l.focus.hasFocus,
      child: TextField(
        controller: l.ctl,
        focusNode: l.focus,
        maxLines: null,
        style: style,
        cursorHeight: (style.fontSize ?? 15) * 1.25,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          hintText: hint,
          hintStyle: style.copyWith(color: t.faint),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: b.kind == BlockKind.heading ? 6 : 2),
        ),
        onTap: () {
          // A click on a link opens it, unless the line was already being edited.
          if (!l.tappedWhileIdle) return;
          final at = l.ctl.selection.baseOffset;
          final hit = linkSpans(l.ctl.text).where((s) => at > s.start && at < s.end).firstOrNull;
          if (hit != null && widget.onOpenLink != null) {
            l.focus.unfocus();
            widget.onOpenLink!(hit.target);
          }
        },
      ),
    );

    Widget lead() {
      final box = SizedBox(
        height: lineHeight + 4,
        child: Center(
          child: switch (b.kind) {
            BlockKind.check => _CheckBox(done: b.done, onTap: () => _toggleCheck(l)),
            BlockKind.bullet => Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: t.ink, shape: BoxShape.circle),
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      );
      return SizedBox(width: 26, child: box);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = l),
      onExit: (_) {
        if (_hover == l) setState(() => _hover = null);
      },
      child: Padding(
        padding: EdgeInsets.only(left: indent, top: b.kind == BlockKind.heading ? 8 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (b.isList) lead(),
            Expanded(child: field),
            if (link != null && widget.onOpenLink != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 2),
                child: TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => widget.onOpenLink!(link.target),
                  icon: const Icon(Icons.north_east, size: 14),
                  label: Text('Open ${link.target}', overflow: TextOverflow.ellipsis),
                ),
              ),
            if (showMake)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Tooltip(
                  message: 'Make a task from this line (⌘↩)',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _makeTaskOn(l),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.task_alt, size: 15, color: t.accent),
                          const SizedBox(width: 4),
                          Text(
                            'Task',
                            style: t.text(12, color: t.accent, weight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _embed(CombTokens t, _Line l) {
    final name = l.block.text.split('/').last;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onOpenEmbed == null ? null : () => widget.onOpenEmbed!(l.block.text),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.attach_file, size: 16, color: t.sub),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name, style: t.text(13), overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: 'Remove from here',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 15, color: t.sub),
                  onPressed: () {
                    _remove(l);
                    _emit();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.done, required this.onTap});
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return Semantics(
      checked: done,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: done ? t.accent : Colors.transparent,
              border: Border.all(color: done ? t.accent : t.faint, width: 1.5),
              borderRadius: BorderRadius.circular(5),
            ),
            child: done ? Icon(Icons.check, size: 12, color: t.bg) : null,
          ),
        ),
      ),
    );
  }
}

/// Opens what a `[[link]]` points at: a note, a task, or a new note.
void openLinkTarget(
  String target, {
  required Library lib,
  required void Function(Note) openNote,
  required void Function(Task) openTask,
  required Note Function(String) createNote,
}) {
  final note = lib.noteByTitle(target);
  if (note != null) return openNote(note);
  final task = lib.taskByTitle(target);
  if (task != null) return openTask(task);
  openNote(createNote(target));
}
