import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/frontmatter.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'fields.dart';

class TaskDetail extends StatefulWidget {
  const TaskDetail({super.key, required this.c, required this.task});
  final AppController c;
  final Task task;

  @override
  State<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<TaskDetail> {
  late final _title = TextEditingController(text: widget.task.title);
  late final _body = TextEditingController(text: widget.task.body);
  final _titleFocus = FocusNode();
  final _subtask = TextEditingController();
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
    if (_bodySave == null && _body.text != task.body) _body.text = task.body;
  }

  @override
  void dispose() {
    if (_bodySave != null) {
      _bodySave!.cancel();
      _saveBody();
    }
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _subtask.dispose();
    super.dispose();
  }

  void _saveTitle() {
    final v = _title.text.trim();
    if (v.isNotEmpty && v != task.title) c.saveTask(task, newTitle: v);
  }

  void _saveBody() {
    _bodySave = null;
    if (_body.text != task.body) {
      task.body = _body.text;
      c.saveTask(task);
    }
  }

  void _set(void Function() change) {
    change();
    c.saveTask(task);
  }

  Future<void> _attach() async {
    final file = await openFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Files up to 25 MB can be attached.')));
      return;
    }
    await c.attachFile(task, file.name, bytes);
    _body.text = task.body;
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
    final attachments = RegExp(r'!\[\[([^\]]+)\]\]').allMatches(task.body).map((m) => m.group(1)!).toList();
    final back = lib.backlinks(task.title);
    final categories = {...?space?.categories, ...lib.tasks.map((x) => x.category).whereType<String>()}.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Row(
          children: [
            Expanded(child: Text([space?.name, task.project].whereType<String>().join(' › '), style: t.small)),
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
              padding: const EdgeInsets.only(top: 10),
              child: DoneCircle(done: task.done, size: 22, onTap: () => c.edit((l) => l.setTaskDone(task, !task.done))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _title,
                focusNode: _titleFocus,
                maxLines: null,
                style: t.heading,
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
        const SizedBox(height: 8),
        FieldRow(
          label: 'Space',
          child: SpacePicker(lib: lib, value: space, onChanged: (s) => _set(() => task.spaceName = s == null ? null : lib.spacePath(s))),
        ),
        FieldRow(
          label: 'Category',
          child: SuggestField(
            value: task.category,
            options: categories,
            hint: 'e.g. Client',
            onChanged: (v) => _set(() => task.category = v),
          ),
        ),
        FieldRow(
          label: 'Project',
          child: SuggestField(
            value: task.project,
            options: lib.projectNames,
            hint: 'e.g. HCL Museum',
            onChanged: (v) => _set(() => task.project = v),
          ),
        ),
        FieldRow(
          label: 'Priority',
          child: Segmented<Priority>(
            values: Priority.values,
            selected: task.priority,
            label: (p) => p == Priority.high ? 'High' : 'Low',
            onChanged: (p) => _set(() => task.priority = p),
          ),
        ),
        FieldRow(
          label: 'Urgent',
          stacked: true,
          child: Segmented<bool?>(
            values: const [null, true, false],
            selected: task.urgentOverride,
            label: (v) => v == null ? 'Auto (${autoUrgent ? 'yes' : 'no'})' : (v ? 'Yes' : 'No'),
            onChanged: (v) => _set(() => task.urgentOverride = v),
          ),
        ),
        FieldRow(
          label: 'Status',
          stacked: true,
          child: Segmented<TaskStatus>(
            values: TaskStatus.values,
            selected: task.status,
            label: (s) => s.label,
            onChanged: (s) => c.edit((l) => c.views.moveToStatus(task, s)),
          ),
        ),
        if (task.status == TaskStatus.waiting)
          FieldRow(
            label: 'Waiting on',
            child: SuggestField(
              value: task.waitingOn,
              options: lib.peopleNames,
              hint: 'Who',
              onChanged: (v) => _set(() => task.waitingOn = v),
            ),
          ),
        FieldRow(
          label: 'Due',
          child: Row(
            children: [
              QuietButton(
                label: task.due == null ? 'Add date' : dueLabel(task.due, c.now, withDay: true),
                icon: Icons.event_outlined,
                onPressed: () async {
                  final d = await pickDue(context, task.due, c.now);
                  if (d != task.due) _set(() => task.due = d);
                },
              ),
              if (task.due != null)
                IconButton(
                  tooltip: 'Remove date',
                  icon: Icon(Icons.close, size: 16, color: t.sub),
                  onPressed: () => _set(() => task.due = null),
                ),
            ],
          ),
        ),
        FieldRow(
          label: 'Repeat',
          child: PopupMenuButton<Repeat?>(
            tooltip: 'Repeat',
            initialValue: task.repeat,
            onSelected: (r) => _set(() {
              task.repeat = r;
              if (r != null && task.due == null) task.due = Due(DateTime(c.now.year, c.now.month, c.now.day));
            }),
            itemBuilder: (_) => [
              const PopupMenuItem<Repeat?>(value: null, child: Text('Does not repeat')),
              for (final r in Repeat.values) PopupMenuItem<Repeat?>(value: r, child: Text(r.label)),
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
                  Icon(Icons.repeat, size: 16, color: t.sub),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(task.repeat?.label ?? 'Does not repeat', style: t.body, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (task.repeat != null && task.lastDone != null)
          FieldRow(
            label: '',
            child: Text('Last done ${task.lastDone}', style: t.small),
          ),
        FieldRow(
          label: 'People',
          stacked: true,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in task.people)
                InputChip(
                  label: Text(p, style: t.text(12)),
                  onDeleted: () => _set(() => task.people.remove(p)),
                  backgroundColor: t.accentTint,
                  side: BorderSide.none,
                ),
              SizedBox(
                width: 140,
                child: SuggestField(
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
        if (task.source != null || task.fromNote != null)
          FieldRow(
            label: 'From',
            child: Wrap(
              spacing: 8,
              children: [
                if (task.source != null && task.source != 'manual' && task.source != 'note')
                  Text(_sourceLabel(task.source!), style: t.body),
                if (task.fromNote != null)
                  ActionChip(
                    label: Text(task.fromNote!, style: t.text(12, color: t.accent)),
                    backgroundColor: t.accentTint,
                    side: BorderSide.none,
                    onPressed: () {
                      final n = lib.noteByTitle(task.fromNote!);
                      if (n != null) c.selectNote(n);
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Divider(color: t.line),
        const SizedBox(height: 8),
        if (task.subtasks.isNotEmpty) ...[
          Text('Checklist', style: t.label),
          for (final s in task.subtasks)
            CheckboxListTile(
              value: s.done,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(s.text, style: t.body.copyWith(decoration: s.done ? TextDecoration.lineThrough : null)),
              onChanged: (_) {
                c.edit((l) => l.toggleSubtask(task, s.line));
                _body.text = task.body;
              },
            ),
        ],
        TextField(
          controller: _subtask,
          decoration: const InputDecoration(hintText: 'Add a checklist item', prefixIcon: Icon(Icons.add, size: 18)),
          onSubmitted: (s) {
            if (s.trim().isEmpty) return;
            task.body = '${task.body.trimRight()}${task.body.trim().isEmpty ? '' : '\n'}- [ ] ${s.trim()}\n';
            c.saveTask(task);
            _body.text = task.body;
            _subtask.clear();
          },
        ),
        const SizedBox(height: 12),
        Text('Notes', style: t.label),
        const SizedBox(height: 6),
        TextField(
          controller: _body,
          maxLines: null,
          minLines: 5,
          style: t.body,
          decoration: const InputDecoration(hintText: 'Details, links like [[HCL Museum]], anything'),
          onChanged: (_) {
            _bodySave?.cancel();
            _bodySave = Timer(const Duration(milliseconds: 700), _saveBody);
          },
        ),
        const SizedBox(height: 12),
        for (final a in attachments)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openAttachment(a),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: t.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.attach_file, size: 16, color: t.sub),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(a.split('/').last, style: t.text(13), overflow: TextOverflow.ellipsis),
                    ),
                    Text('Encrypted', style: t.small),
                  ],
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: QuietButton(label: 'Attach a file', icon: Icons.attach_file, onPressed: _attach),
        ),
        if (back.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Linked from', style: t.label),
          const SizedBox(height: 6),
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
            ],
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Text(task.created == null ? '' : 'Created ${unlink(task.created)}', style: t.small),
            const Spacer(),
            QuietButton(
              label: 'Delete',
              danger: true,
              icon: Icons.delete_outline,
              onPressed: () async {
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
                  c.selectTask(null);
                  c.edit((l) => l.deleteTask(task));
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  static String _sourceLabel(String s) => switch (s) {
    'whatsapp' => 'WhatsApp',
    'email' => 'Email',
    'share' => 'Shared',
    _ => s,
  };
}
