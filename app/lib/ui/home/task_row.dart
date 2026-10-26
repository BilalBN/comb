import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';

class TaskRow extends StatelessWidget {
  const TaskRow({super.key, required this.c, required this.task, this.showSpace = true, this.compact = false});
  final AppController c;
  final Task task;
  final bool showSpace;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final lib = c.library!;
    final views = c.views;
    final space = lib.spaceOf(task);
    final selected = c.selectedTaskPath == task.path;
    final urgent = views.isUrgent(task);
    final overdue = views.isOverdue(task);
    final meta = <Widget>[
      if (showSpace && space != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpaceDot(space.color, size: 7),
            const SizedBox(width: 6),
            Text(space.name, style: t.small),
          ],
        ),
      if (task.project != null) Text(task.project!, style: t.small),
      if (task.due != null)
        Text(
          dueLabel(task.due, c.now),
          style: t.text(12, color: overdue ? t.urgentInk : t.sub, weight: overdue ? FontWeight.w500 : FontWeight.w400),
        ),
      if (task.repeat != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.repeat, size: 12, color: t.sub),
            const SizedBox(width: 3),
            Text(task.repeat!.label, style: t.small),
          ],
        ),
      if (task.status == TaskStatus.waiting) Text(task.waitingOn == null ? 'Waiting' : 'Waiting on ${task.waitingOn}', style: t.small),
      if (task.status == TaskStatus.doing) Text('Doing', style: t.small),
      if (task.subtasks.isNotEmpty) Text('${task.subtasks.where((s) => s.done).length}/${task.subtasks.length}', style: t.small),
    ];

    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? t.select : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => c.selectTask(selected ? null : task),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : t.rowPad),
            decoration: BoxDecoration(
              border: selected ? null : Border(bottom: BorderSide(color: t.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DoneCircle(done: task.done, onTap: () => c.edit((lib) => lib.setTaskDone(task, !task.done))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: t.bodyStrong.copyWith(
                          decoration: task.done ? TextDecoration.lineThrough : null,
                          color: task.done ? t.sub : t.ink,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Wrap(spacing: 12, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: meta),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!task.done && urgent) Pill.urgent(context),
                if (!task.done && urgent && task.priority == Priority.high) const SizedBox(width: 6),
                if (!task.done && task.priority == Priority.high) Pill.high(context),
              ],
            ),
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
