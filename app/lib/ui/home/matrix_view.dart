import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../../data/views.dart';
import '../theme.dart';
import '../widgets.dart';

class MatrixView extends StatelessWidget {
  const MatrixView({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final m = c.views.matrix();
    Widget axis(String s) => Text(
      s,
      style: t.text(13, weight: FontWeight.w600, color: t.sub),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 640;
        if (narrow) {
          return ListView(
            children: [
              for (final q in Quadrant.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    height: 280,
                    child: _Box(c: c, q: q, tasks: m[q]!),
                  ),
                ),
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 96),
                Expanded(child: Center(child: axis('Urgent'))),
                const SizedBox(width: 12),
                Expanded(child: Center(child: axis('Not urgent'))),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 96, child: Center(child: axis('High priority'))),
                  Expanded(
                    child: _Box(c: c, q: Quadrant.doNow, tasks: m[Quadrant.doNow]!),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Box(c: c, q: Quadrant.schedule, tasks: m[Quadrant.schedule]!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 96, child: Center(child: axis('Low priority'))),
                  Expanded(
                    child: _Box(c: c, q: Quadrant.delegate, tasks: m[Quadrant.delegate]!),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Box(c: c, q: Quadrant.later, tasks: m[Quadrant.later]!),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.c, required this.q, required this.tasks});
  final AppController c;
  final Quadrant q;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final strong = q == Quadrant.doNow;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => c.views.quadrantOf(d.data) != q,
      onAcceptWithDetails: (d) => c.edit((lib) => c.views.moveToQuadrant(d.data, q)),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Semantics(
          label: q.label,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hovering ? t.accentTint : (strong ? t.accentTint.withValues(alpha: 0.55) : (q == Quadrant.later ? t.side : t.bg)),
              border: Border.all(color: strong || hovering ? t.accent : t.line, width: strong ? 1.5 : 1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(q.label, style: t.text(15, weight: FontWeight.w600)),
                    ),
                    Text('${tasks.length}', style: t.small),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: tasks.isEmpty
                      ? Text('Drop tasks here', style: t.text(13, color: t.faint))
                      : ListView.separated(
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _Card(c: c, task: tasks[i]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.c, required this.task});
  final AppController c;
  final Task task;

  Widget _face(BuildContext context, {bool lifted = false}) {
    final t = context.comb;
    final space = c.library!.spaceOf(task);
    return Material(
      color: t.bg,
      elevation: lifted ? 4 : 0,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => c.selectTask(task),
        child: Container(
          width: lifted ? 280 : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: c.selectedTaskPath == task.path ? t.accent : t.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              DoneCircle(done: task.done, size: 18, onTap: () => c.edit((lib) => lib.setTaskDone(task, true))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title, style: t.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (space != null) ...[SpaceDot(space.color, size: 7), const SizedBox(width: 6)],
                        Flexible(
                          child: Text(
                            [space?.name, if (task.due != null) dueLabel(task.due, c.now)].whereType<String>().join(' · '),
                            style: t.small,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Draggable<Task>(
      data: task,
      feedback: _face(context, lifted: true),
      childWhenDragging: Opacity(opacity: 0.35, child: _face(context)),
      child: _face(context),
    );
  }
}
