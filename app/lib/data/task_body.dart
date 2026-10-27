/// A task's markdown, split the way the task panel shows it: free notes,
/// a checklist, and attached files. Written back in that order, so the file
/// stays plain markdown that Obsidian reads as before.
library;

class ChecklistItem {
  ChecklistItem(this.text, {this.done = false, this.indent = ''});
  String text;
  bool done;
  String indent;

  String toLine() => '$indent- [${done ? 'x' : ' '}] $text';
}

class TaskBody {
  TaskBody({this.notes = '', List<ChecklistItem>? checklist, List<String>? files}) : checklist = checklist ?? [], files = files ?? [];

  factory TaskBody.parse(String body) {
    final notes = <String>[];
    final checklist = <ChecklistItem>[];
    final files = <String>[];
    for (final line in body.replaceAll('\r\n', '\n').split('\n')) {
      final check = _check.firstMatch(line);
      if (check != null) {
        checklist.add(ChecklistItem(check.group(3) ?? '', done: check.group(2)!.toLowerCase() == 'x', indent: check.group(1)!));
        continue;
      }
      final file = _file.firstMatch(line);
      if (file != null) {
        files.add(file.group(1)!);
        continue;
      }
      notes.add(line);
    }
    return TaskBody(notes: notes.join('\n').trim(), checklist: checklist, files: files);
  }

  static final _check = RegExp(r'^(\s*)[-*] \[( |x|X)\](?: (.*))?$');
  static final _file = RegExp(r'^\s*!\[\[([^\]]+)\]\]\s*$');

  String notes;
  final List<ChecklistItem> checklist;
  final List<String> files;

  /// Notes, then the checklist, then files, with a blank line between.
  /// Empty checklist items are left out.
  String compose() {
    final parts = <String>[
      if (notes.trim().isNotEmpty) notes.trim(),
      if (checklist.any((c) => c.text.trim().isNotEmpty))
        checklist.where((c) => c.text.trim().isNotEmpty).map((c) => (c..text = c.text.trim()).toLine()).join('\n'),
      if (files.isNotEmpty) files.map((f) => '![[$f]]').join('\n'),
    ];
    return parts.isEmpty ? '' : '${parts.join('\n\n')}\n';
  }
}
