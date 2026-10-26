import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';

class BoardView extends StatelessWidget {
  const BoardView({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final board = c.views.board();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in TaskStatus.values) ...[
          Expanded(
            child: _Column(c: c, status: s, tasks: board[s]!),
          ),
          if (s != TaskStatus.done) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.c, required this.status, required this.tasks});
  final AppController c;
  final TaskStatus status;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => d.data.status != status,
      onAcceptWithDetails: (d) => c.edit((lib) => c.views.moveToStatus(d.data, status)),
      builder: (context, cand, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cand.isNotEmpty ? t.accentTint : t.side,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cand.isNotEmpty ? t.accent : t.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(status.label, style: t.text(14, weight: FontWeight.w600)),
                ),
                Text('${tasks.length}', style: t.small),
              ],
            ),
            if (status == TaskStatus.done) Text('Last 7 days', style: t.small),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: tasks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final task = tasks[i];
                  final card = _card(context, task);
                  return Draggable<Task>(
                    data: task,
                    feedback: SizedBox(
                      width: 240,
                      child: Material(elevation: 4, borderRadius: BorderRadius.circular(10), child: card),
                    ),
                    childWhenDragging: Opacity(opacity: 0.35, child: card),
                    child: card,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Task task) {
    final t = context.comb;
    final space = c.library!.spaceOf(task);
    final urgent = c.views.isUrgent(task);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => c.selectTask(task),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.selectedTaskPath == task.path ? t.accent : t.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              style: t.bodyStrong.copyWith(decoration: task.done ? TextDecoration.lineThrough : null),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (space != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SpaceDot(space.color, size: 7),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(space.name, style: t.small, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                if (task.due != null) Text(dueLabel(task.due, c.now), style: t.small),
                if (!task.done && urgent) Pill.urgent(context),
                if (!task.done && task.priority == Priority.high) Pill.high(context),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
