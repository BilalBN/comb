import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../data/frontmatter.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'fields.dart';

class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.c, required this.note});
  final AppController c;
  final Note note;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final _title = TextEditingController(text: widget.note.title == 'Untitled' ? '' : widget.note.title);
  late final _body = TextEditingController(text: widget.note.body);
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();
  Timer? _save;

  AppController get c => widget.c;
  Note get note => widget.note;

  @override
  void initState() {
    super.initState();
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) _saveTitle();
    });
    if (_title.text.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _titleFocus.requestFocus());
  }

  @override
  void didUpdateWidget(NoteEditor old) {
    super.didUpdateWidget(old);
    // Edits that arrive from another device or from Obsidian.
    if (_save == null && !_bodyFocus.hasFocus && _body.text != note.body) _body.text = note.body;
  }

  @override
  void dispose() {
    _flush();
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _flush() {
    if (_save != null) {
      _save!.cancel();
      _saveBody();
    }
  }

  void _saveTitle() {
    final v = _title.text.trim();
    if (v.isNotEmpty && v != note.title) c.saveNote(note, newTitle: v);
  }

  void _saveBody() {
    _save = null;
    if (_body.text != note.body) {
      note.body = _body.text;
      c.saveNote(note);
    }
  }

  int _cursorLine() {
    final pos = _body.selection.baseOffset.clamp(0, _body.text.length);
    return '\n'.allMatches(_body.text.substring(0, pos)).length;
  }

  void _makeTask() {
    _flush();
    final line = _cursorLine();
    try {
      final task = c.edit((lib) => lib.makeTaskFromLine(note, line));
      _body.text = note.body;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task made: ${task.title}'),
          action: SnackBarAction(label: 'Open', onPressed: () => c.selectTask(task)),
        ),
      );
    } on ArgumentError {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Put the cursor on a line with some text first.')));
    }
  }

  void _insertChecklist() {
    final sel = _body.selection;
    final at = sel.baseOffset < 0 ? _body.text.length : sel.baseOffset;
    final before = _body.text.substring(0, at);
    final prefix = before.isEmpty || before.endsWith('\n') ? '- [ ] ' : '\n- [ ] ';
    _body.value = TextEditingValue(
      text: before + prefix + _body.text.substring(at),
      selection: TextSelection.collapsed(offset: at + prefix.length),
    );
    _bodyFocus.requestFocus();
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 700), _saveBody);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final lib = c.library!;
    final space = lib.spaceOfNote(note);
    final linkedTasks = linksIn(note.body).map(lib.taskByTitle).whereType<Task>().toSet().toList();
    final back = lib.backlinks(note.title);

    return CallbackShortcutsHolder(
      onMakeTask: _makeTask,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 48),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                icon: Icon(Icons.arrow_back, size: 18, color: t.sub),
                onPressed: () {
                  _flush();
                  _saveTitle();
                  c.selectNote(null);
                },
              ),
              const SizedBox(width: 4),
              Text(note.kind.label, style: t.small),
              const Spacer(),
              QuietButton(label: 'Checklist item', icon: Icons.check_box_outlined, onPressed: _insertChecklist),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Turns the line the cursor is on into a task (⌘↩)',
                child: QuietButton(label: 'Make task', icon: Icons.task_alt, onPressed: _makeTask),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(Icons.more_horiz, color: t.sub),
                onSelected: (v) async {
                  if (v == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete this note?'),
                        content: Text('"${note.title}" will be removed from all your devices.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      _save?.cancel();
                      _save = null;
                      c.selectNote(null);
                      c.edit((l) => l.deleteNote(note));
                    }
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete note'))],
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            focusNode: _titleFocus,
            style: t.title,
            decoration: const InputDecoration(
              hintText: 'Title',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) {
              _saveTitle();
              _bodyFocus.requestFocus();
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SpacePicker(lib: lib, value: space, onChanged: (s) => c.edit((l) => l.moveNote(note, s))),
              PopupMenuButton<NoteKind>(
                tooltip: 'Note type',
                onSelected: (k) {
                  note.kind = k;
                  c.saveNote(note);
                },
                itemBuilder: (_) => [
                  for (final k in NoteKind.values.where((k) => k != NoteKind.daily)) PopupMenuItem(value: k, child: Text(k.label)),
                ],
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(note.kind.label, style: t.body),
                      Icon(Icons.expand_more, size: 16, color: t.sub),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: SuggestField(
                  value: note.project,
                  options: lib.projectNames,
                  hint: 'Project',
                  onChanged: (v) {
                    note.project = v;
                    c.saveNote(note);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _body,
            focusNode: _bodyFocus,
            maxLines: null,
            minLines: 16,
            style: t.text(15, height: 1.6),
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Write anything. "- [ ] " starts a checklist item; put the cursor on a line and press Make task to turn it into a task. Link with [[Name]].',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) {
              _save?.cancel();
              _save = Timer(const Duration(milliseconds: 700), _saveBody);
            },
          ),
          if (linkedTasks.isNotEmpty) ...[
            const SizedBox(height: 24),
            Divider(color: t.line),
            SectionLabel('Tasks from this note · ${linkedTasks.length}'),
            for (final task in linkedTasks)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: DoneCircle(
                  done: task.done,
                  onTap: () {
                    c.edit((l) => l.setTaskDone(task, !task.done));
                    _body.text = note.body;
                  },
                ),
                title: Text(task.title, style: t.bodyStrong.copyWith(decoration: task.done ? TextDecoration.lineThrough : null)),
                subtitle: task.due == null ? null : Text(dueLabel(task.due, c.now), style: t.small),
                onTap: () => c.selectTask(task),
              ),
          ],
          if (back.notes.isNotEmpty || back.tasks.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionLabel('Linked here'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in back.notes)
                  ActionChip(
                    label: Text(n.title, style: t.text(12, color: t.accent)),
                    backgroundColor: t.accentTint,
                    side: BorderSide.none,
                    onPressed: () => c.selectNote(n),
                  ),
                for (final x in back.tasks.where((x) => !linkedTasks.contains(x)))
                  ActionChip(
                    label: Text(x.title, style: t.text(12, color: t.accent)),
                    backgroundColor: t.accentTint,
                    side: BorderSide.none,
                    onPressed: () => c.selectTask(x),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// ⌘↩ makes a task from the current line.
class CallbackShortcutsHolder extends StatelessWidget {
  const CallbackShortcutsHolder({super.key, required this.onMakeTask, required this.child});
  final VoidCallback onMakeTask;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      CallbackShortcuts(bindings: {const SingleActivator(LogicalKeyboardKey.enter, meta: true): onMakeTask}, child: child);
}
