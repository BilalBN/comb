import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/frontmatter.dart';
import '../../data/models.dart';
import '../editor/markdown_editor.dart';
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
  final _titleFocus = FocusNode();
  final _editor = GlobalKey<MarkdownEditorState>();
  String? _pending;
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
  void dispose() {
    _flush();
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _flush() {
    _save?.cancel();
    _save = null;
    final b = _pending;
    _pending = null;
    if (b != null && b != note.body) {
      note.body = b;
      c.saveNote(note);
    }
  }

  void _saveTitle() {
    final v = _title.text.trim();
    if (v.isNotEmpty && v != note.title) c.saveNote(note, newTitle: v);
  }

  void _makeTask(int line) {
    _flush();
    try {
      final task = c.edit((lib) => lib.makeTaskFromLine(note, line));
      _editor.currentState?.reload(note.body);
      showNotice(context, 'Task made: ${task.title}', action: 'Open', onAction: () => c.selectTask(task));
    } on ArgumentError {
      showNotice(context, 'Write something on that line first.');
    }
  }

  void _openLink(String target) {
    _flush();
    final lib = c.library!;
    openLinkTarget(
      target,
      lib: lib,
      openNote: c.selectNote,
      openTask: c.selectTask,
      createNote: (title) => c.edit((l) => l.createNote(title: title, space: lib.spaceOfNote(note))),
    );
  }

  Future<void> _delete() async {
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
      _pending = null;
      c.selectNote(null);
      c.edit((l) => l.deleteNote(note));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final lib = c.library!;
    final space = lib.spaceOfNote(note);
    final linkedTasks = linksIn(note.body).map(lib.taskByTitle).whereType<Task>().toSet().toList();
    final back = lib.backlinks(note.title);
    final backTasks = back.tasks.where((x) => !linkedTasks.contains(x)).toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(40, 20, 40, 48),
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    _flush();
                    _saveTitle();
                    c.selectNote(null);
                  },
                  icon: Icon(Icons.arrow_back, size: 16, color: t.sub),
                  label: Text('Notes', style: t.text(13, color: t.sub)),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: Icon(Icons.more_horiz, color: t.sub),
                  onSelected: (v) {
                    if (v == 'delete') _delete();
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
              onSubmitted: (_) => _saveTitle(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SpacePicker(lib: lib, value: space, onChanged: (s) => c.edit((l) => l.moveNote(note, s))),
                PropMenu<NoteKind>(
                  value: note.kind,
                  items: NoteKind.values.where((k) => k != NoteKind.daily || note.kind == NoteKind.daily).toList(),
                  label: (k) => k.label,
                  leading: (k) => Icon(_kindIcon(k), size: 15, color: t.sub),
                  onSelected: (k) {
                    note.kind = k;
                    c.saveNote(note);
                  },
                ),
                SizedBox(
                  width: 200,
                  child: SuggestField(
                    plain: true,
                    value: note.project,
                    options: lib.projectNames,
                    hint: '+ Project',
                    onChanged: (v) {
                      note.project = v;
                      c.saveNote(note);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: t.line, height: 1),
            const SizedBox(height: 12),
            MarkdownEditor(
              key: _editor,
              text: _pending ?? note.body,
              lib: lib,
              selfTitle: note.title,
              hint: 'Write anything. Use the buttons above for a checklist or a link, and turn any line into a task.',
              onChanged: (s) {
                _pending = s;
                _save?.cancel();
                _save = Timer(const Duration(milliseconds: 600), _flush);
              },
              onToggleCheck: _flush,
              onMakeTask: _makeTask,
              onOpenLink: _openLink,
            ),
            if (linkedTasks.isNotEmpty) ...[
              const SizedBox(height: 8),
              SectionLabel('Tasks from this note · ${linkedTasks.length}'),
              for (final task in linkedTasks)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: DoneCircle(
                    done: task.done,
                    onTap: () {
                      _flush();
                      c.edit((l) => l.setTaskDone(task, !task.done));
                      _editor.currentState?.reload(note.body);
                    },
                  ),
                  title: Text(task.title, style: t.bodyStrong.copyWith(decoration: task.done ? TextDecoration.lineThrough : null)),
                  subtitle: task.due == null ? null : Text(dueLabel(task.due, c.now), style: t.small),
                  onTap: () => c.selectTask(task),
                ),
            ],
            if (back.notes.isNotEmpty || backTasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              SectionLabel('Linked here'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in back.notes)
                    ActionChip(
                      avatar: Icon(Icons.description_outlined, size: 14, color: t.accent),
                      label: Text(n.title, style: t.text(12, color: t.accent)),
                      backgroundColor: t.accentTint,
                      side: BorderSide.none,
                      onPressed: () => c.selectNote(n),
                    ),
                  for (final x in backTasks)
                    ActionChip(
                      avatar: Icon(Icons.check_circle_outline, size: 14, color: t.accent),
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
      ),
    );
  }
}

IconData _kindIcon(NoteKind k) => switch (k) {
  NoteKind.meeting => Icons.groups_outlined,
  NoteKind.call => Icons.call_outlined,
  NoteKind.daily => Icons.today_outlined,
  NoteKind.project => Icons.folder_outlined,
  NoteKind.person => Icons.person_outline,
  NoteKind.plain => Icons.description_outlined,
};
