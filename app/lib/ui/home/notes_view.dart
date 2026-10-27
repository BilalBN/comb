import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../../data/views.dart';
import '../theme.dart';
import '../widgets.dart';

class NotesView extends StatefulWidget {
  const NotesView({super.key, required this.c});
  final AppController c;
  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  NoteKind? kind;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final c = widget.c;
    final lib = c.library!;
    final filter = c.filterIds;
    final notes = Views(lib).notesIn(kind: kind).where((n) => filter == null || filter.contains(lib.spaceOfNote(n)?.id)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [_kindChip(context, null, 'All'), for (final k in NoteKind.values) _kindChip(context, k, k.label)],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: notes.isEmpty
              ? EmptyHint(kind == null ? 'No notes yet. Make one with New note (⇧⌘N).' : 'No ${kind!.label.toLowerCase()} notes yet.')
              : ListView(
                  children: [for (final n in notes) NoteRow(c: c, note: n)],
                ),
        ),
        Text('${notes.length} notes', style: t.small),
      ],
    );
  }

  Widget _kindChip(BuildContext context, NoteKind? k, String label) {
    final t = context.comb;
    final on = kind == k;
    return ChoiceChip(
      label: Text(label, style: t.text(13, color: on ? t.bg : t.ink)),
      selected: on,
      showCheckmark: false,
      selectedColor: t.ink,
      backgroundColor: t.bg,
      side: BorderSide(color: on ? t.ink : t.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (_) => setState(() => kind = k),
    );
  }
}

class NoteRow extends StatelessWidget {
  const NoteRow({super.key, required this.c, required this.note});
  final AppController c;
  final Note note;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final space = c.library!.spaceOfNote(note);
    final preview = note.body.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && !l.startsWith('#')).take(1).join();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => c.selectNote(note),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: t.rowPad),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(
          children: [
            Icon(_icon(note.kind), size: 18, color: t.sub),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.title, style: t.bodyStrong),
                  if (preview.isNotEmpty) Text(preview, style: t.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (space != null) ...[SpaceDot(space.color, size: 7), const SizedBox(width: 6), Text(space.name, style: t.small)],
            const SizedBox(width: 12),
            Text(note.kind.label, style: t.small),
          ],
        ),
      ),
    );
  }

  static IconData _icon(NoteKind k) => switch (k) {
    NoteKind.plain => Icons.description_outlined,
    NoteKind.meeting => Icons.groups_outlined,
    NoteKind.call => Icons.call_outlined,
    NoteKind.project => Icons.folder_outlined,
    NoteKind.person => Icons.person_outline,
    NoteKind.daily => Icons.today_outlined,
  };
}
