import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/library.dart';
import '../../data/models.dart';
import '../theme.dart';

enum LinkKind { note, task, person, create }

class LinkChoice {
  const LinkChoice(this.title, this.kind, {this.sub});
  final String title;
  final LinkKind kind;
  final String? sub;
}

/// Everything a note can link to, best matches first.
List<LinkChoice> linkChoices(Library lib, String query, {String? exclude}) {
  final q = query.trim().toLowerCase();
  final seen = <String>{if (exclude != null) exclude.toLowerCase()};
  final out = <(int, LinkChoice)>[];
  void add(String title, LinkKind kind, {String? sub}) {
    final key = title.toLowerCase();
    if (title.trim().isEmpty || seen.contains(key)) return;
    final rank = q.isEmpty
        ? 1
        : key == q
        ? 0
        : key.startsWith(q)
        ? 1
        : key.contains(q)
        ? 2
        : -1;
    if (rank < 0) return;
    seen.add(key);
    out.add((rank, LinkChoice(title, kind, sub: sub)));
  }

  final notes = [...lib.notes]..sort((a, b) => (b.created ?? '').compareTo(a.created ?? ''));
  for (final n in notes) {
    add(n.title, LinkKind.note, sub: n.kind.label);
  }
  for (final t in lib.tasks.where((t) => !t.done)) {
    add(t.title, LinkKind.task, sub: 'Task');
  }
  for (final p in lib.peopleNames) {
    add(p, LinkKind.person, sub: 'Person');
  }
  for (final p in lib.projectNames) {
    add(p, LinkKind.note, sub: 'Project');
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  final list = out.map((e) => e.$2).take(40).toList();
  if (q.isNotEmpty && !list.any((c) => c.title.toLowerCase() == q)) {
    list.add(LinkChoice(query.trim(), LinkKind.create, sub: 'New note'));
  }
  return list;
}

/// A search box over notes, tasks and people. Returns the title to link.
Future<String?> pickLink(BuildContext context, Library lib, {String initial = '', String? exclude}) => showDialog<String>(
  context: context,
  builder: (_) => _LinkPicker(lib: lib, initial: initial, exclude: exclude),
);

class _LinkPicker extends StatefulWidget {
  const _LinkPicker({required this.lib, required this.initial, this.exclude});
  final Library lib;
  final String initial;
  final String? exclude;
  @override
  State<_LinkPicker> createState() => _LinkPickerState();
}

class _LinkPickerState extends State<_LinkPicker> {
  late final _q = TextEditingController(text: widget.initial);
  int _hi = 0;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final items = linkChoices(widget.lib, _q.text, exclude: widget.exclude);
    if (_hi >= items.length) _hi = 0;
    return Dialog(
      alignment: const Alignment(0, -0.5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(() => _hi = (_hi + 1).clamp(0, items.length - 1)),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(() => _hi = (_hi - 1).clamp(0, items.length - 1)),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Link to a note, task or person', prefixIcon: Icon(Icons.link, size: 18)),
                  onChanged: (_) => setState(() => _hi = 0),
                  onSubmitted: (_) {
                    if (items.isNotEmpty) Navigator.pop(context, items[_hi].title);
                  },
                ),
              ),
              Flexible(
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Type a name to link to.', style: t.small),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final c = items[i];
                          return ListTile(
                            dense: true,
                            selected: i == _hi,
                            selectedTileColor: t.select,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            leading: Icon(
                              switch (c.kind) {
                                LinkKind.note => Icons.description_outlined,
                                LinkKind.task => Icons.check_circle_outline,
                                LinkKind.person => Icons.person_outline,
                                LinkKind.create => Icons.add,
                              },
                              size: 18,
                              color: t.sub,
                            ),
                            title: Text(c.kind == LinkKind.create ? 'Create "${c.title}"' : c.title, style: t.body),
                            trailing: c.sub == null ? null : Text(c.sub!, style: t.small),
                            onTap: () => Navigator.pop(context, c.title),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
