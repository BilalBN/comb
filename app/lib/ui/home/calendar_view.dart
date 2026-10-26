import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'task_row.dart';

/// A month of due dates. Pick a day to see its tasks below.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key, required this.c});
  final AppController c;
  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime month = DateTime(widget.c.now.year, widget.c.now.month);
  late DateTime selected = DateTime(widget.c.now.year, widget.c.now.month, widget.c.now.day);

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

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final c = widget.c;
    final days = c.views.month(month.year, month.month);
    final first = DateTime(month.year, month.month, 1);
    final lead = first.weekday - 1; // Monday first
    final count = DateTime(month.year, month.month + 1, 0).day;
    final cells = lead + count;
    final rows = (cells / 7).ceil();
    final today = DateTime(c.now.year, c.now.month, c.now.day);
    final dayTasks = days[selected] ?? const <Task>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
            ),
            Flexible(
              child: Text('${_monthNames[month.month - 1]} ${month.year}', style: t.heading, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                month = DateTime(today.year, today.month);
                selected = today;
              }),
              child: const Text('Today'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
              Expanded(
                child: Center(child: Text(d, style: t.label)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Row(children: [for (var col = 0; col < 7; col++) Expanded(child: _cell(context, r * 7 + col - lead + 1, count, days, today))]),
        const SizedBox(height: 16),
        SectionLabel('${dueLabel(Due(selected), c.now)} · ${dayTasks.length}'),
        if (dayTasks.isEmpty) const EmptyHint('Nothing due this day.'),
        for (final task in dayTasks) TaskRow(c: c, task: task),
      ],
    );
  }

  Widget _cell(BuildContext context, int day, int count, Map<DateTime, List<Task>> days, DateTime today) {
    final t = context.comb;
    if (day < 1 || day > count) return const SizedBox(height: 72);
    final date = DateTime(month.year, month.month, day);
    final tasks = days[date] ?? const <Task>[];
    final isToday = date == today;
    final isSelected = date == selected;
    final urgentCount = tasks.where(widget.c.views.isUrgent).length;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSelected ? t.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => selected = date),
          child: Container(
            height: 68,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border.all(color: isSelected ? t.accent : t.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$day',
                  style: t.text(13, weight: isToday ? FontWeight.w700 : FontWeight.w400, color: isToday ? t.accent : t.ink),
                ),
                const Spacer(),
                if (tasks.isNotEmpty)
                  Text(
                    '${tasks.length} task${tasks.length == 1 ? '' : 's'}${urgentCount > 0 ? ' · $urgentCount urgent' : ''}',
                    style: t.text(11, color: urgentCount > 0 ? t.urgentInk : t.sub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
