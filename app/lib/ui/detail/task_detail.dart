import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/frontmatter.dart';
import '../../data/models.dart';
import '../editor/markdown_editor.dart';
import '../theme.dart';
import '../widgets.dart';
import 'fields.dart';

/// The task panel: title, a short list of properties, then notes with a
/// real checklist.
class TaskDetail extends StatefulWidget {
  const TaskDetail({super.key, required this.c, required this.task});
  final AppController c;
  final Task task;

  @override
  State<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<TaskDetail> {
  late final _title = TextEditingController(text: widget.task.title);
  final _titleFocus = FocusNode();
  final _editor = GlobalKey<MarkdownEditorState>();
  String? _pendingBody;
  Timer? _bodySave;

  AppController get c => widget.c;
  Task get task => widget.task;

  @override
  void initState() {
    super.initState();
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) _saveTitle();
    });
  }

  @override
  void didUpdateWidget(TaskDetail old) {
    super.didUpdateWidget(old);
    if (!_titleFocus.hasFocus && _title.text != task.title) _title.text = task.title;
  }

  @override
  void dispose() {
    _flushBody();
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _saveTitle() {
    final v = _title.text.trim();
    if (v.isNotEmpty && v != task.title) c.saveTask(task, newTitle: v);
  }

  void _flushBody() {
    _bodySave?.cancel();
    _bodySave = null;
    final b = _pendingBody;
    _pendingBody = null;
    if (b != null && b != task.body) {
      task.body = b;
      c.saveTask(task);
    }
  }

  void _set(void Function() change) {
    _flushBody();
    change();
    c.saveTask(task);
  }

  Future<void> _attach() async {
    final file = await openFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      if (mounted) showNotice(context, 'Files up to 25 MB can be attached.');
      return;
    }
    _flushBody();
    await c.attachFile(task, file.name, bytes);
    _editor.currentState?.reload(task.body);
  }

  Future<void> _openAttachment(String path) async {
    final bytes = await c.readAttachment(path);
    if (bytes == null) return;
    final tmp = Directory('${Directory.systemTemp.path}/comb-open');
    await tmp.create(recursive: true);
    final f = File('${tmp.path}/${path.split('/').last}');
    await f.writeAsBytes(bytes, flush: true);
    if (Platform.isMacOS) {
      await Process.run('open', [f.path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', f.path]);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this task?'),
        content: Text('"${task.title}" will be removed from all your devices.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      _bodySave?.cancel();
      _pendingBody = null;
      c.selectTask(null);
      c.edit((l) => l.deleteTask(task));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final lib = c.library!;
    final views = c.views;
    final space = lib.spaceOf(task);
    final autoUrgent = (() {
      final saved = task.urgentOverride;
      task.urgentOverride = null;
      final v = views.isUrgent(task);
      task.urgentOverride = saved;
      return v;
    })();
    final back = lib.backlinks(task.title);
    final categories = {...?space?.categories, ...lib.tasks.map((x) => x.category).whereType<String>()}.toList()..sort();
    final overdue = views.isOverdue(task);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text([space?.name, task.project].whereType<String>().join(' › '), style: t.small, overflow: TextOverflow.ellipsis),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_horiz, size: 18, color: t.sub),
              onSelected: (v) {
                if (v == 'delete') _delete();
                if (v == 'attach') _attach();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'attach', child: Text('Attach a file')),
                PopupMenuItem(value: 'delete', child: Text('Delete task')),
              ],
            ),
            IconButton(
              tooltip: 'Close (Esc)',
              icon: Icon(Icons.close, size: 18, color: t.sub),
              onPressed: () => c.selectTask(null),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: DoneCircle(
                done: task.done,
                size: 22,
                onTap: () {
                  _flushBody();
                  c.edit((l) => l.setTaskDone(task, !task.done));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _title,
                focusNode: _titleFocus,
                maxLines: null,
                style: t.heading.copyWith(decoration: task.done ? TextDecoration.lineThrough : null),
                decoration: const InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onSubmitted: (_) => _saveTitle(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        PropRow(
          icon: Icons.layers_outlined,
          label: 'Space',
          child: PropMenu<String>(
            value: space?.id ?? '',
            items: ['', ..._spaceIds()],
            label: (id) => id.isEmpty ? 'Inbox' : lib.spaceById(id)!.name,
            leading: (id) => id.isEmpty ? Icon(Icons.inbox_outlined, size: 14, color: t.sub) : SpaceDot(lib.spaceById(id)!.color),
            onSelected: (id) => _set(() => task.spaceName = id.isEmpty ? null : lib.spacePath(lib.spaceById(id)!)),
          ),
        ),
        PropRow(
          icon: Icons.event_outlined,
          label: 'Due',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: PropValue(
                  empty: task.due == null,
                  onTap: () async {
                    final d = await pickDue(context, task.due, c.now);
                    if (d != task.due) _set(() => task.due = d);
                  },
                  child: Text(
                    task.due == null ? 'Add a date' : dueLabel(task.due, c.now, withDay: true),
                    style: overdue ? t.text(14, color: t.urgentInk, weight: FontWeight.w500) : null,
                  ),
                ),
              ),
              if (task.due != null)
                IconButton(
                  tooltip: 'Remove date',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 14, color: t.faint),
                  onPressed: () => _set(() => task.due = null),
                ),
            ],
          ),
        ),
        PropRow(
          icon: Icons.repeat,
          label: 'Repeat',
          child: PropMenu<Repeat?>(
            value: task.repeat,
            items: const [null, ...Repeat.values],
            label: (r) => r?.label ?? 'Never',
            onSelected: (r) => _set(() {
              task.repeat = r;
              if (r != null && task.due == null) task.due = Due(DateTime(c.now.year, c.now.month, c.now.day));
            }),
          ),
        ),
        PropRow(
          icon: Icons.flag_outlined,
          label: 'Priority',
          child: PropMenu<Priority>(
            value: task.priority,
            items: Priority.values,
            label: (p) => p == Priority.high ? 'High' : 'Low',
            leading: (p) =>
                Icon(p == Priority.high ? Icons.flag : Icons.outlined_flag, size: 15, color: p == Priority.high ? t.accent : t.faint),
            onSelected: (p) => _set(() => task.priority = p),
          ),
        ),
        PropRow(
          icon: Icons.bolt_outlined,
          label: 'Urgent',
          child: PropMenu<bool?>(
            value: task.urgentOverride,
            items: const [null, true, false],
            label: (v) => switch (v) {
              null => autoUrgent ? 'Yes · due soon' : 'No · not due soon',
              true => 'Yes',
              false => 'No',
            },
            onSelected: (v) => _set(() => task.urgentOverride = v),
          ),
        ),
        PropRow(
          icon: Icons.radio_button_checked_outlined,
          label: 'Status',
          child: PropMenu<TaskStatus>(
            value: task.status,
            items: TaskStatus.values,
            label: (s) => s.label,
            onSelected: (s) => c.edit((l) => c.views.moveToStatus(task, s)),
          ),
        ),
        if (task.status == TaskStatus.waiting)
          PropRow(
            icon: Icons.hourglass_empty,
            label: 'Waiting on',
            child: SuggestField(
              plain: true,
              value: task.waitingOn,
              options: lib.peopleNames,
              hint: 'Who',
              onChanged: (v) => _set(() => task.waitingOn = v),
            ),
          ),
        PropRow(
          icon: Icons.folder_outlined,
          label: 'Project',
          child: SuggestField(
            plain: true,
            value: task.project,
            options: lib.projectNames,
            hint: 'Add a project',
            onChanged: (v) => _set(() => task.project = v),
          ),
        ),
        PropRow(
          icon: Icons.sell_outlined,
          label: 'Category',
          child: SuggestField(
            plain: true,
            value: task.category,
            options: categories,
            hint: 'Add a category',
            onChanged: (v) => _set(() => task.category = v),
          ),
        ),
        PropRow(
          icon: Icons.people_outline,
          label: 'People',
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final p in task.people)
                InputChip(
                  label: Text(p, style: t.text(12)),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () => _set(() => task.people.remove(p)),
                  backgroundColor: t.accentTint,
                  side: BorderSide.none,
                ),
              SizedBox(
                width: 130,
                child: SuggestField(
                  key: ValueKey(task.people.length),
                  plain: true,
                  value: null,
                  options: lib.peopleNames,
                  hint: 'Add person',
                  onChanged: (v) {
                    if (v != null && !task.people.contains(v)) _set(() => task.people.add(v));
                  },
                ),
              ),
            ],
          ),
        ),
        if (task.fromNote != null || (task.source != null && !{'manual', 'note'}.contains(task.source)))
          PropRow(
            icon: Icons.call_split,
            label: 'From',
            child: task.fromNote != null
                ? PropValue(
                    onTap: () {
                      final n = lib.noteByTitle(task.fromNote!);
                      if (n != null) c.selectNote(n);
                    },
                    child: Text(
                      task.fromNote!,
                      style: t.text(14, color: t.accent, weight: FontWeight.w500),
                    ),
                  )
                : PropValue(child: Text(_sourceLabel(task.source!))),
          ),
        if (task.repeat != null && task.lastDone != null)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text('Last done ${task.lastDone}', style: t.small),
          ),
        const SizedBox(height: 14),
        Divider(color: t.line, height: 1),
        const SizedBox(height: 14),
        MarkdownEditor(
          key: _editor,
          text: _pendingBody ?? task.body,
          lib: lib,
          size: 14,
          selfTitle: task.title,
          hint: 'Notes, a checklist, links…',
          onChanged: (s) {
            _pendingBody = s;
            _bodySave?.cancel();
            _bodySave = Timer(const Duration(milliseconds: 600), _flushBody);
          },
          onToggleCheck: _flushBody,
          onOpenEmbed: _openAttachment,
          onOpenLink: (target) {
            _flushBody();
            openLinkTarget(
              target,
              lib: lib,
              openNote: c.selectNote,
              openTask: c.selectTask,
              createNote: (title) => c.edit((l) => l.createNote(title: title, space: space)),
            );
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _attach,
            icon: Icon(Icons.attach_file, size: 16, color: t.sub),
            label: Text('Attach a file', style: t.text(13, color: t.sub)),
          ),
        ),
        if (back.notes.isNotEmpty || back.tasks.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Linked from', style: t.label),
          const SizedBox(height: 6),
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
              for (final x in back.tasks)
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
        const SizedBox(height: 24),
        if (task.created != null) Text('Created ${unlink(task.created)}', style: t.small),
      ],
    );
  }

  List<String> _spaceIds() {
    final lib = c.library!;
    final out = <String>[];
    void walk(Space? parent) {
      for (final s in lib.children(parent)) {
        out.add(s.id);
        walk(s);
      }
    }

    walk(null);
    return out;
  }

  static String _sourceLabel(String s) => switch (s) {
    'whatsapp' => 'WhatsApp',
    'email' => 'Email',
    'share' => 'Shared',
    _ => s,
  };
}
