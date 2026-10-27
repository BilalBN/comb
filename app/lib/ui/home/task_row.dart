import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../../data/task_body.dart';
import '../theme.dart';
import '../widgets.dart';

/// One task in a list: tick, title, and a quiet line of what matters
/// (date, Space, checklist, project). Urgent shows as a red date and a bolt,
/// high priority as a flag.
class TaskRow extends StatefulWidget {
  const TaskRow({super.key, required this.c, required this.task, this.showSpace = true, this.compact = false});
  final AppController c;
  final Task task;
  final bool showSpace;
  final bool compact;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final c = widget.c;
    final task = widget.task;
    final lib = c.library!;
    final views = c.views;
    final space = lib.spaceOf(task);
    final selected = c.selectedTaskPath == task.path;
    final urgent = !task.done && views.isUrgent(task);
    final overdue = !task.done && views.isOverdue(task);
    final high = task.priority == Priority.high;
    final checks = task.subtasks;
    final parts = TaskBody.parse(task.body);
    final hasNotes = parts.notes.isNotEmpty;
    final dateColor = overdue || urgent ? t.urgentInk : t.sub;

    Widget meta(IconData icon, String text, {Color? color}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color ?? t.faint),
        const SizedBox(width: 4),
        Text(text, style: t.text(12, color: color ?? t.sub)),
      ],
    );

    final details = <Widget>[
      if (task.due != null) meta(Icons.event_outlined, dueLabel(task.due, c.now), color: task.done ? null : dateColor),
      if (urgent && task.due == null) meta(Icons.bolt, 'Urgent', color: t.urgentInk),
      if (task.repeat != null) meta(Icons.repeat, task.repeat!.label),
      if (checks.isNotEmpty) meta(Icons.check_box_outlined, '${checks.where((s) => s.done).length}/${checks.length}'),
      if (task.project != null) meta(Icons.folder_outlined, task.project!),
      if (task.status == TaskStatus.waiting)
        meta(Icons.hourglass_empty, task.waitingOn == null ? 'Waiting' : 'Waiting on ${task.waitingOn}'),
      if (task.status == TaskStatus.doing) meta(Icons.play_circle_outline, 'Doing'),
      if (hasNotes) Icon(Icons.notes, size: 13, color: t.faint),
      if (parts.files.isNotEmpty) meta(Icons.attach_file, '${parts.files.length}'),
    ];

    return Semantics(
      selected: selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => c.selectTask(selected ? null : task),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: widget.compact ? 6 : t.rowPad - 3),
            decoration: BoxDecoration(
              color: selected ? t.select : (_hover ? t.side : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Tick(done: task.done, high: high, onTap: () => c.edit((lib) => lib.setTaskDone(task, !task.done))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                task.title,
                                style: t
                                    .text(14.5, weight: FontWeight.w500, height: 1.35, color: task.done ? t.sub : t.ink)
                                    .copyWith(decoration: task.done ? TextDecoration.lineThrough : null, decorationColor: t.sub),
                              ),
                            ),
                            if (high && !task.done) ...[const SizedBox(width: 6), Icon(Icons.flag, size: 13, color: t.accent)],
                            if (urgent && task.due != null) ...[const SizedBox(width: 4), Icon(Icons.bolt, size: 14, color: t.urgentInk)],
                          ],
                        ),
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Wrap(spacing: 12, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: details),
                      ],
                    ],
                  ),
                ),
                if (widget.showSpace && space != null) ...[
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SpaceDot(space.color, size: 7),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(space.name, style: t.small, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The round tick. High-priority tasks get an accent ring.
class _Tick extends StatelessWidget {
  const _Tick({required this.done, required this.high, required this.onTap});
  final bool done;
  final bool high;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final ring = done ? t.accent : (high ? t.accent : t.faint);
    return Semantics(
      button: true,
      checked: done,
      label: done ? 'Mark not done' : 'Mark done',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? t.accent : null,
              border: Border.all(color: ring, width: 1.6),
            ),
            child: done ? Icon(Icons.check, size: 13, color: t.bg) : null,
          ),
        ),
      ),
    );
  }
}

/// A list of tasks under section labels.
class TaskSections extends StatelessWidget {
  const TaskSections({super.key, required this.c, required this.sections, this.empty = 'Nothing here.', this.showSpace = true});
  final AppController c;
  final List<(String, List<Task>)> sections;
  final String empty;
  final bool showSpace;

  @override
  Widget build(BuildContext context) {
    final nonEmpty = sections.where((s) => s.$2.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return EmptyHint(empty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in nonEmpty) ...[
          if (s.$1.isNotEmpty) SectionLabel('${s.$1} · ${s.$2.length}'),
          for (final task in s.$2) TaskRow(key: ValueKey(task.path), c: c, task: task, showSpace: showSpace),
        ],
      ],
    );
  }
}
