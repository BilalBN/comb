import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'task_row.dart';

/// A month with the tasks written in each day. Click a day to see its list
/// below; drag a task onto another day to move it there.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key, required this.c});
  final AppController c;
  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime month = DateTime(widget.c.now.year, widget.c.now.month);
  late DateTime selected = DateTime(widget.c.now.year, widget.c.now.month, widget.c.now.day);
  DateTime? _dropHover;
  bool _wide = true;

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  Map<DateTime, List<Task>> _tasks() {
    final v = widget.c.views;
    final out = <DateTime, List<Task>>{};
    for (final m in [DateTime(month.year, month.month - 1), month, DateTime(month.year, month.month + 1)]) {
      out.addAll(v.month(m.year, m.month));
    }
    return out;
  }

  void _move(Task task, DateTime day) {
    final old = task.due;
    if (old != null && old.day == day) return;
    task.due = old != null && old.hasTime
        ? Due(DateTime(day.year, day.month, day.day, old.date.hour, old.date.minute), hasTime: true)
        : Due(day);
    widget.c.saveTask(task);
    setState(() => selected = day);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final c = widget.c;
    final days = _tasks();
    final first = DateTime(month.year, month.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1)); // Monday
    final count = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((first.weekday - 1 + count) / 7).ceil();
    final today = DateTime(c.now.year, c.now.month, c.now.day);
    final dayTasks = days[selected] ?? const <Task>[];

    return LayoutBuilder(
      builder: (context, box) {
        _wide = box.maxWidth / 7 > 90;
        return _body(context, t, days, start, rows, today, dayTasks);
      },
    );
  }

  Widget _body(
    BuildContext context,
    CombTokens t,
    Map<DateTime, List<Task>> days,
    DateTime start,
    int rows,
    DateTime today,
    List<Task> dayTasks,
  ) {
    final c = widget.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${_monthNames[month.month - 1]} ${month.year}', style: t.heading, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'Previous month',
              icon: Icon(Icons.chevron_left, color: t.sub),
              onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
            ),
            TextButton(
              onPressed: () => setState(() {
                month = DateTime(today.year, today.month);
                selected = today;
              }),
              child: const Text('Today'),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: Icon(Icons.chevron_right, color: t.sub),
              onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Row(
                children: [
                  for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(d, textAlign: TextAlign.center, style: t.label),
                      ),
                    ),
                ],
              ),
              for (var r = 0; r < rows; r++)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(child: _cell(context, DateTime(start.year, start.month, start.day + r * 7 + col), days, today, col)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionLabel('${dueLabel(Due(selected), c.now, withDay: true)} · ${dayTasks.length}'),
        if (dayTasks.isEmpty) const EmptyHint('Nothing due this day.'),
        for (final task in dayTasks) TaskRow(key: ValueKey(task.path), c: c, task: task),
      ],
    );
  }

  Widget _cell(BuildContext context, DateTime date, Map<DateTime, List<Task>> days, DateTime today, int col) {
    final t = context.comb;
    final inMonth = date.month == month.month;
    final tasks = days[date] ?? const <Task>[];
    final isToday = date == today;
    final isSelected = date == selected;
    const shown = 3;

    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) {
        setState(() => _dropHover = date);
        return true;
      },
      onLeave: (_) => setState(() => _dropHover = null),
      onAcceptWithDetails: (d) {
        setState(() => _dropHover = null);
        _move(d.data, date);
      },
      builder: (context, _, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => selected = date),
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          decoration: BoxDecoration(
            color: _dropHover == date
                ? t.accentTint
                : isSelected
                ? t.select
                : (inMonth ? null : t.side),
            border: Border(
              top: BorderSide(color: t.line),
              left: col == 0 ? BorderSide.none : BorderSide(color: t.line),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: isToday ? BoxDecoration(color: t.accent, shape: BoxShape.circle) : null,
                  child: Text(
                    '${date.day}',
                    style: t.text(
                      12.5,
                      weight: isToday ? FontWeight.w700 : FontWeight.w500,
                      color: isToday ? t.bg : (inMonth ? t.ink : t.faint),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              for (final task in tasks.take(shown)) _chip(context, task, wide: _wide),
              if (tasks.length > shown)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text(
                    '+${tasks.length - shown} more',
                    style: t.text(11, color: t.sub, weight: FontWeight.w500),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, Task task, {bool wide = true}) {
    final t = context.comb;
    final c = widget.c;
    final space = c.library!.spaceOf(task);
    final urgent = c.views.isUrgent(task);
    final color = t.space(space?.color);
    final chip = Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: t.dark ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border(left: BorderSide(color: color, width: 2.5)),
      ),
      child: Row(
        children: [
          if (task.due?.hasTime == true && wide) ...[
            Text(
              _time(task.due!.date),
              style: t.text(10.5, color: t.sub, weight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text(11.5, weight: FontWeight.w500, color: urgent ? t.urgentInk : t.ink),
            ),
          ),
        ],
      ),
    );
    return Draggable<Task>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 150, child: Opacity(opacity: 0.9, child: chip)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: () => c.selectTask(task), child: chip),
      ),
    );
  }

  static String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute == 0 ? '' : ':${d.minute.toString().padLeft(2, '0')}';
    return '$h$m${d.hour < 12 ? 'a' : 'p'}';
  }
}
