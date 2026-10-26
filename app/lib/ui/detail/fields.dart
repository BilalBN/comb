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
  const SuggestField({super.key, required this.value, required this.options, required this.onChanged, this.hint = ''});
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String hint;

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
          decoration: InputDecoration(hintText: widget.hint),
          onSubmitted: (s) {
            onSubmit();
            widget.onChanged(s.trim().isEmpty ? null : s.trim());
          },
        );
      },
    );
  }
}

Future<Due?> pickDue(BuildContext context, Due? current, DateTime now) async {
  final date = await showDatePicker(
    context: context,
    initialDate: current?.date ?? now,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 10),
  );
  if (date == null) return current;
  if (!context.mounted) return Due(date);
  final wantTime = current?.hasTime ?? false;
  final time = await showTimePicker(
    context: context,
    initialTime: wantTime ? TimeOfDay.fromDateTime(current!.date) : const TimeOfDay(hour: 9, minute: 0),
    helpText: 'Add a time (Cancel for no time)',
  );
  if (time == null) return Due(date);
  return Due(DateTime(date.year, date.month, date.day, time.hour, time.minute), hasTime: true);
}
