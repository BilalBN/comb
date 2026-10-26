import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../../data/quick_add.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Add a task" with a live preview of what was understood.
class QuickAddBar extends StatefulWidget {
  const QuickAddBar({super.key, required this.c, this.focusNode});
  final AppController c;
  final FocusNode? focusNode;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _text = TextEditingController();
  QuickAdd? _preview;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      final s = _text.text.trim();
      setState(() => _preview = s.isEmpty ? null : parseQuickAdd(s, spaces: widget.c.library!.spaces, now: widget.c.now));
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final s = _text.text.trim();
    if (s.isEmpty) return;
    final task = widget.c.quickAdd(s);
    _text.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${task.title}"'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(label: 'Open', onPressed: () => widget.c.selectTask(task)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final p = _preview;
    final chips = <Widget>[
      if (p?.space != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpaceDot(p!.space!.color, size: 7),
            const SizedBox(width: 5),
            Text(p.space!.name, style: t.small),
          ],
        ),
      if (p?.due != null) Text(dueLabel(p!.due, widget.c.now), style: t.small),
      if (p?.repeat != null) Text(p!.repeat!.label, style: t.small),
      if (p?.priority == Priority.high) Text('High', style: t.small),
      if (p?.urgent == true) Text('Urgent', style: t.text(12, color: t.urgentInk)),
      if (p != null && p.people.isNotEmpty) Text(p.people.map((e) => '@$e').join(' '), style: t.small),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: widget.focusNode,
                decoration: const InputDecoration(
                  hintText: 'Add a task, e.g. Call GCD tomorrow 4pm #CAX !h',
                  prefixIcon: Icon(Icons.add, size: 18),
                ),
                onSubmitted: (_) {
                  _add();
                  widget.focusNode?.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 8),
            PrimaryButton(label: 'Add', onPressed: _add),
          ],
        ),
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 6),
            child: Wrap(
              spacing: 12,
              children: [
                Text('Will add:', style: t.small),
                ...chips,
              ],
            ),
          ),
      ],
    );
  }
}
