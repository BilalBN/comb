import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/task_body.dart';
import '../theme.dart';
import 'markdown_editor.dart';

/// A task's checklist: tick, edit, reorder by dragging, remove, and an
/// "Add an item" line. Empty items disappear when you leave them.
class ChecklistEditor extends StatefulWidget {
  const ChecklistEditor({super.key, required this.items, required this.onChanged, this.onToggled});

  /// Edited in place; [onChanged] says when.
  final List<ChecklistItem> items;
  final VoidCallback onChanged;

  /// A tick, which is saved straight away.
  final VoidCallback? onToggled;

  @override
  State<ChecklistEditor> createState() => ChecklistEditorState();
}

class ChecklistEditorState extends State<ChecklistEditor> {
  final _ctl = <ChecklistItem, LinkTextController>{};
  final _focus = <ChecklistItem, FocusNode>{};
  final _add = TextEditingController();
  final _addFocus = FocusNode();
  ChecklistItem? _hover;

  List<ChecklistItem> get items => widget.items;

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChecklistEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Forget controllers for items that are gone (the list was reloaded).
    for (final gone in _ctl.keys.where((k) => !items.contains(k)).toList()) {
      _ctl.remove(gone)!.dispose();
      _focus.remove(gone)!.dispose();
    }
    for (final it in items) {
      final c = _ctl[it];
      if (c != null && c.text != it.text && !(_focus[it]?.hasFocus ?? false)) c.text = it.text;
    }
  }

  LinkTextController _controller(ChecklistItem it) => _ctl.putIfAbsent(it, () => LinkTextController(text: it.text));

  FocusNode _node(ChecklistItem it) => _focus.putIfAbsent(it, () {
    final f = FocusNode(onKeyEvent: (_, e) => _key(it, e));
    f.addListener(() {
      if (!mounted) return;
      _controller(it).showMarks = f.hasFocus;
      if (!f.hasFocus && it.text.trim().isEmpty && items.contains(it)) {
        _remove(it);
      } else {
        setState(() {});
      }
    });
    return f;
  });

  KeyEventResult _key(ChecklistItem it, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ctl = _controller(it);
    if (e.logicalKey == LogicalKeyboardKey.backspace && ctl.text.isEmpty) {
      final i = items.indexOf(it);
      _remove(it);
      if (i > 0) _focusItem(items[i - 1]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _focusItem(ChecklistItem it) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !items.contains(it)) return;
    _node(it).requestFocus();
    final c = _controller(it);
    c.selection = TextSelection.collapsed(offset: c.text.length);
  });

  void _remove(ChecklistItem it) {
    setState(() => items.remove(it));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctl.remove(it)?.dispose();
      _focus.remove(it)?.dispose();
    });
    widget.onChanged();
  }

  void _addItem(String text) {
    final s = text.trim();
    if (s.isEmpty) return;
    setState(() => items.add(ChecklistItem(s)));
    _add.clear();
    _addFocus.requestFocus();
    widget.onChanged();
  }

  /// Enter in an item: a new item right below it.
  void _insertAfter(ChecklistItem it) {
    if (it.text.trim().isEmpty) {
      _addFocus.requestFocus();
      return;
    }
    final next = ChecklistItem('');
    setState(() => items.insert(items.indexOf(it) + 1, next));
    _focusItem(next);
  }

  /// Puts the cursor in "Add an item".
  void focusAdd() => _addFocus.requestFocus();

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final done = items.where((i) => i.done && i.text.trim().isNotEmpty).length;
    final total = items.where((i) => i.text.trim().isNotEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Checklist', style: t.label),
            if (total > 0) ...[const SizedBox(width: 8), Text('$done/$total', style: t.small)],
          ],
        ),
        const SizedBox(height: 4),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: items.length,
          onReorderItem: (from, to) {
            setState(() => items.insert(to, items.removeAt(from)));
            widget.onChanged();
          },
          proxyDecorator: (child, _, _) => Material(color: t.bg, elevation: 3, borderRadius: BorderRadius.circular(8), child: child),
          itemBuilder: (context, i) {
            final it = items[i];
            return MouseRegion(
              key: ObjectKey(it),
              onEnter: (_) => setState(() => _hover = it),
              onExit: (_) {
                if (_hover == it) setState(() => _hover = null);
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: _Box(
                      done: it.done,
                      onTap: () {
                        setState(() => it.done = !it.done);
                        widget.onChanged();
                        widget.onToggled?.call();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller(it)
                        ..linkColor = t.accent
                        ..markColor = t.faint,
                      focusNode: _node(it),
                      maxLines: null,
                      textInputAction: TextInputAction.done,
                      style: t
                          .text(14, color: it.done ? t.sub : t.ink)
                          .copyWith(decoration: it.done ? TextDecoration.lineThrough : null, decorationColor: t.sub),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 7),
                      ),
                      onChanged: (s) {
                        it.text = s;
                        widget.onChanged();
                      },
                      onSubmitted: (_) => _insertAfter(it),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 100),
                    opacity: _hover == it ? 1 : 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Remove',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close, size: 15, color: t.sub),
                          onPressed: () => _remove(it),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.drag_indicator, size: 16, color: t.faint),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Row(
          children: [
            Icon(Icons.add, size: 17, color: t.faint),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _add,
                focusNode: _addFocus,
                style: t.text(14),
                decoration: InputDecoration(
                  hintText: 'Add an item',
                  hintStyle: t.text(14, color: t.faint),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 7),
                ),
                onSubmitted: _addItem,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.done, required this.onTap});
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
          child: Container(
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
