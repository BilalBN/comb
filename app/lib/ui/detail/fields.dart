import 'package:flutter/material.dart';

import '../../data/library.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Label on the left, control on the right.
class FieldRow extends StatelessWidget {
  const FieldRow({super.key, required this.label, required this.child, this.stacked = false});
  final String label;
  final Widget child;

  /// Label above the control, for wide controls in a narrow panel.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(label, style: context.comb.text(13, color: context.comb.sub));
    if (stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [labelText, const SizedBox(height: 6), child]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 96, child: labelText),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ),
    );
  }
}

/// Choose a Space (or none) from the tree.
class SpacePicker extends StatelessWidget {
  const SpacePicker({super.key, required this.lib, required this.value, required this.onChanged, this.allowNone = true});
  final Library lib;
  final Space? value;
  final ValueChanged<Space?> onChanged;
  final bool allowNone;

  List<(Space, int)> _flat() {
    final out = <(Space, int)>[];
    void walk(Space? parent, int depth) {
      for (final s in lib.children(parent)) {
        out.add((s, depth));
        walk(s, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final items = _flat();
    return PopupMenuButton<String>(
      tooltip: 'Choose Space',
      onSelected: (id) => onChanged(id == '' ? null : lib.spaceById(id)),
      itemBuilder: (context) => [
        if (allowNone)
          PopupMenuItem(
            value: '',
            child: Text('No Space (Inbox)', style: t.body),
          ),
        for (final (s, depth) in items)
          PopupMenuItem(
            value: s.id,
            child: Padding(
              padding: EdgeInsets.only(left: depth * 16.0),
              child: Row(
                children: [
                  SpaceDot(s.color),
                  const SizedBox(width: 10),
                  Text(s.name, style: t.body),
                ],
              ),
            ),
          ),
      ],
      child: _Box(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null) ...[SpaceDot(value!.color), const SizedBox(width: 8)],
            Text(value?.name ?? 'No Space', style: t.body),
            const SizedBox(width: 6),
            Icon(Icons.expand_more, size: 16, color: t.sub),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 36),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      border: Border.all(color: context.comb.line),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
}

/// A text field that offers matching names as you type and saves on Enter
/// or when it loses focus.
class SuggestField extends StatefulWidget {
  const SuggestField({super.key, required this.value, required this.options, required this.onChanged, this.hint = '', this.plain = false});
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String hint;

  /// No box around it: for the property list in the task panel.
  final bool plain;

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: widget.value ?? ''),
      optionsBuilder: (v) {
        final q = v.text.toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return widget.options.where((o) => o.toLowerCase().contains(q)).take(8);
      },
      onSelected: (s) => widget.onChanged(s),
      fieldViewBuilder: (context, controller, focus, onSubmit) {
        focus.addListener(() {
          if (!focus.hasFocus) {
            final v = controller.text.trim();
            if (v != (widget.value ?? '')) widget.onChanged(v.isEmpty ? null : v);
          }
        });
        return TextField(
          controller: controller,
          focusNode: focus,
          style: t.body,
          decoration: widget.plain
              ? InputDecoration(
                  hintText: widget.hint,
                  hintStyle: t.text(14, color: t.faint),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                )
              : InputDecoration(hintText: widget.hint),
          onSubmitted: (s) {
            onSubmit();
            widget.onChanged(s.trim().isEmpty ? null : s.trim());
          },
        );
      },
    );
  }
}

/// Choose a due date: quick picks, a calendar and an optional time, in one
/// small window. Returns [current] unchanged when cancelled, and null for
/// "No date".
Future<Due?> pickDue(BuildContext context, Due? current, DateTime now) async {
  final r = await showDialog<_DueResult>(
    context: context,
    builder: (_) => _DueDialog(current: current, now: now),
  );
  if (r == null) return current;
  return r.due;
}

class _DueResult {
  const _DueResult(this.due);
  final Due? due;
}

class _DueDialog extends StatefulWidget {
  const _DueDialog({required this.current, required this.now});
  final Due? current;
  final DateTime now;
  @override
  State<_DueDialog> createState() => _DueDialogState();
}

class _DueDialogState extends State<_DueDialog> {
  late DateTime day = widget.current?.day ?? DateTime(widget.now.year, widget.now.month, widget.now.day);
  late TimeOfDay? time = widget.current?.hasTime == true ? TimeOfDay.fromDateTime(widget.current!.date) : null;

  Due get _due => time == null ? Due(day) : Due(DateTime(day.year, day.month, day.day, time!.hour, time!.minute), hasTime: true);

  void _done([DateTime? d]) => Navigator.pop(
    context,
    _DueResult(d == null ? _due : (time == null ? Due(d) : Due(DateTime(d.year, d.month, d.day, time!.hour, time!.minute), hasTime: true))),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    DateTime plus(int n) => DateTime(today.year, today.month, today.day + n);
    final toMonday = (8 - today.weekday) % 7;
    final nextMonday = plus(toMonday == 0 ? 7 : toMonday);
    final saturday = plus((6 - today.weekday) % 7);
    Widget quick(IconData icon, String label, DateTime d) => ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(icon, size: 18, color: t.sub),
      title: Text(label, style: t.body),
      trailing: Text(dueLabel(Due(d), widget.now, withDay: true), style: t.small),
      onTap: () => _done(d),
    );
    final times = const [
      TimeOfDay(hour: 9, minute: 0),
      TimeOfDay(hour: 12, minute: 0),
      TimeOfDay(hour: 15, minute: 0),
      TimeOfDay(hour: 17, minute: 0),
      TimeOfDay(hour: 19, minute: 0),
    ];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              quick(Icons.today_outlined, 'Today', today),
              quick(Icons.wb_sunny_outlined, 'Tomorrow', plus(1)),
              quick(Icons.weekend_outlined, 'This weekend', saturday),
              quick(Icons.next_week_outlined, 'Next week', nextMonday),
              Divider(color: t.line),
              CalendarDatePicker(
                initialDate: day,
                firstDate: DateTime(widget.now.year - 5),
                lastDate: DateTime(widget.now.year + 10),
                onDateChanged: (d) => setState(() => day = d),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.schedule, size: 16, color: t.sub),
                    ChoiceChip(label: const Text('No time'), selected: time == null, onSelected: (_) => setState(() => time = null)),
                    for (final x in times)
                      ChoiceChip(label: Text(x.format(context)), selected: time == x, onSelected: (_) => setState(() => time = x)),
                    ActionChip(
                      label: Text(time != null && !times.contains(time) ? time!.format(context) : 'Other…'),
                      onPressed: () async {
                        final x = await showTimePicker(context: context, initialTime: time ?? const TimeOfDay(hour: 9, minute: 0));
                        if (x != null) setState(() => time = x);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (widget.current != null)
                    TextButton(onPressed: () => Navigator.pop(context, const _DueResult(null)), child: const Text('No date')),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 4),
                  FilledButton(onPressed: _done, child: const Text('Set date')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line in the task panel's property list: icon, name, value.
class PropRow extends StatelessWidget {
  const PropRow({super.key, required this.icon, required this.label, required this.child});
  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Row(
        children: [
          Icon(icon, size: 16, color: t.sub),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: Text(label, style: t.text(13, color: t.sub)),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ),
    );
  }
}

/// A value in the property list that looks like text and highlights on hover.
class PropValue extends StatelessWidget {
  const PropValue({super.key, required this.child, this.onTap, this.empty = false});
  final Widget child;
  final VoidCallback? onTap;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      hoverColor: t.select,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: DefaultTextStyle.merge(
          style: empty ? t.text(14, color: t.faint) : t.body,
          child: child,
        ),
      ),
    );
  }
}

/// A property whose value is picked from a short menu.
class PropMenu<T> extends StatelessWidget {
  const PropMenu({super.key, required this.value, required this.items, required this.label, required this.onSelected, this.leading});
  final T value;
  final List<T> items;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final Widget Function(T)? leading;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return PopupMenuButton<int>(
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: (i) => onSelected(items[i]),
      itemBuilder: (_) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem(
            value: i,
            height: 38,
            child: Row(
              children: [
                if (leading != null) ...[leading!(items[i]), const SizedBox(width: 10)],
                Text(label(items[i]), style: t.body),
                if (items[i] == value) ...[const Spacer(), Icon(Icons.check, size: 16, color: t.accent)],
              ],
            ),
          ),
      ],
      child: IgnorePointer(
        child: PropValue(
          onTap: () {},
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!(value), const SizedBox(width: 8)],
              Flexible(child: Text(label(value), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}
