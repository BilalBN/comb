/// The person's tasks, notes and Spaces, read from and written to markdown
/// files. Everything goes through a [FileSource], so the same logic runs on
/// top of the sync engine in the app and an in-memory map in tests.
library;

import 'dart:convert';

import '../core/crypto.dart' show newRecordId;
import 'frontmatter.dart';
import 'models.dart';
import 'quick_add.dart';
import 'templates.dart';

abstract class FileSource {
  Map<String, String> snapshot();
  void write(String path, String content);
  void rename(String from, String to);
  void delete(String path);
}

class MemoryFiles implements FileSource {
  final Map<String, String> files = {};
  @override
  Map<String, String> snapshot() => Map.of(files);
  @override
  void write(String path, String content) => files[path] = content;
  @override
  void rename(String from, String to) {
    final c = files.remove(from);
    if (c != null) files[to] = c;
  }

  @override
  void delete(String path) => files.remove(path);
}

const spaceColors = ['green', 'blue', 'violet', 'teal', 'orange', 'pink', 'graphite'];

class Library {
  Library(this.source, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    reload();
  }

  final FileSource source;
  final DateTime Function() _clock;

  final List<Task> tasks = [];
  final List<Note> notes = [];
  final List<Space> spaces = [];
  WorkspaceSettings settings = WorkspaceSettings();

  DateTime get now => _clock();
  String get today => isoDay(now);

  // ------------------------------------------------------------ loading

  void reload() {
    tasks.clear();
    notes.clear();
    spaces.clear();
    final files = source.snapshot();
    final ws = files[workspacePath];
    if (ws != null) {
      try {
        final j = jsonDecode(ws) as Map<String, dynamic>;
        spaces.addAll(((j['spaces'] as List?) ?? const []).map((e) => Space.fromJson(e as Map<String, dynamic>)));
        settings = WorkspaceSettings.fromJson(j['settings'] as Map<String, dynamic>?);
      } on FormatException {
        // Leave Spaces empty rather than failing to open.
      }
    }
    files.forEach((path, content) {
      if (!path.toLowerCase().endsWith('.md') || path.startsWith('.')) return;
      final type = MarkdownDoc.parse(content).fields['type']?.toString();
      if (type == 'task' || (type == null && path.startsWith('Tasks/'))) {
        tasks.add(Task.fromMarkdown(path, content));
      } else {
        notes.add(Note.fromMarkdown(path, content));
      }
    });
    spaces.sort((a, b) => a.order.compareTo(b.order));
  }

  // ------------------------------------------------------------ Spaces

  Space? spaceById(String? id) => id == null ? null : spaces.where((s) => s.id == id).firstOrNull;

  /// "Crypt4Bits/Gridnova" for a sub-space; the name for a top-level one.
  String spacePath(Space s) {
    final parts = <String>[];
    Space? cur = s;
    final seen = <String>{};
    while (cur != null && seen.add(cur.id)) {
      parts.insert(0, safeName(cur.name));
      cur = spaceById(cur.parentId);
    }
    return parts.join('/');
  }

  Space? spaceByPath(String? path) {
    if (path == null || path.isEmpty) return null;
    final lower = path.toLowerCase();
    return spaces.where((s) => spacePath(s).toLowerCase() == lower).firstOrNull ??
        spaces.where((s) => s.name.toLowerCase() == lower).firstOrNull;
  }

  List<Space> children(Space? parent) =>
      spaces.where((s) => s.parentId == parent?.id && !s.archived).toList()..sort((a, b) => a.order.compareTo(b.order));

  /// The Space and all Spaces under it.
  Set<String> subtreeIds(Space s) {
    final out = <String>{s.id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final c in spaces) {
        if (c.parentId != null && out.contains(c.parentId) && out.add(c.id)) grew = true;
      }
    }
    return out;
  }

  Space? spaceOf(Task t) => spaceByPath(t.spaceName);
  Space? spaceOfNote(Note n) => spaceByPath(n.spaceName);

  void _saveWorkspace() {
    final j = {'spaces': spaces.map((s) => s.toJson()).toList(), 'settings': settings.toJson()};
    source.write(workspacePath, const JsonEncoder.withIndent('  ').convert(j));
  }

  Space addSpace(String name, {Space? parent, String? color, List<String>? categories}) {
    final s = Space(
      id: 's_${newRecordId().substring(0, 10)}',
      name: name.trim(),
      parentId: parent?.id,
      color: color ?? spaceColors[spaces.length % spaceColors.length],
      categories: categories,
      order: spaces.length,
    );
    spaces.add(s);
    _saveWorkspace();
    return s;
  }

  void saveSettings() => _saveWorkspace();

  /// Renames or moves a Space. Every task and note in it (and under it) is
  /// updated, and note folders follow. Links are untouched: they use titles.
  void updateSpace(Space s, {String? name, String? color, List<String>? categories, String? email, Object? parent = _keep}) {
    final before = {for (final id in subtreeIds(s)) id: spacePath(spaceById(id)!)};
    if (parent != _keep) {
      final p = parent as Space?;
      if (p != null && subtreeIds(s).contains(p.id)) {
        throw ArgumentError('A Space cannot be moved inside itself.');
      }
      s.parentId = p?.id;
    }
    if (name != null && name.trim().isNotEmpty) s.name = name.trim();
    if (color != null) s.color = color;
    if (categories != null) s.categories = categories;
    if (email != null) s.email = email.isEmpty ? null : email;
    _saveWorkspace();

    final after = {for (final id in before.keys) id: spacePath(spaceById(id)!)};
    for (final id in before.keys) {
      final from = before[id]!, to = after[id]!;
      if (from == to) continue;
      for (final t in tasks.where((t) => t.spaceName?.toLowerCase() == from.toLowerCase()).toList()) {
        t.spaceName = to;
        source.write(t.path, t.toMarkdown());
      }
      for (final n in notes.where((n) => n.spaceName?.toLowerCase() == from.toLowerCase()).toList()) {
        n.spaceName = to;
        final newPath = n.path.startsWith('$from/') ? '$to/${n.path.substring(from.length + 1)}' : n.path;
        source.write(n.path, n.toMarkdown());
        if (newPath != n.path) {
          source.rename(n.path, newPath);
          n.path = newPath;
        }
      }
    }
  }

  void archiveSpace(Space s, {bool archived = true}) {
    s.archived = archived;
    _saveWorkspace();
  }

  void reorderSpaces(List<Space> ordered) {
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].order = i;
    }
    spaces.sort((a, b) => a.order.compareTo(b.order));
    _saveWorkspace();
  }

  // ------------------------------------------------------------ tasks

  String _uniquePath(String folder, String title, {String? except}) {
    final base = safeName(title);
    final taken = {...tasks.map((t) => t.path), ...notes.map((n) => n.path)}..remove(except);
    var candidate = folder.isEmpty ? '$base.md' : '$folder/$base.md';
    var n = 2;
    while (taken.contains(candidate)) {
      candidate = folder.isEmpty ? '$base $n.md' : '$folder/$base $n.md';
      n++;
    }
    return candidate;
  }

  Task? taskByTitle(String title) {
    final lower = title.toLowerCase();
    return tasks.where((t) => t.title.toLowerCase() == lower).firstOrNull;
  }

  Task createTask({
    required String title,
    Space? space,
    String? category,
    String? project,
    Priority priority = Priority.low,
    bool? urgent,
    Due? due,
    Repeat? repeat,
    List<String> people = const [],
    String? source,
    String? fromNote,
    String body = '',
  }) {
    final t = Task(
      path: _uniquePath('Tasks', title.trim().isEmpty ? 'New task' : title),
      title: '',
      id: 't_${newRecordId().substring(0, 10)}',
      spaceName: space == null ? null : spacePath(space),
      category: category,
      project: project,
      priority: priority,
      urgentOverride: urgent,
      due: due,
      repeat: repeat,
      people: [...people],
      source: source,
      fromNote: fromNote,
      created: today,
      body: body,
    );
    t.title = titleFromPath(t.path);
    tasks.add(t);
    this.source.write(t.path, t.toMarkdown());
    return t;
  }

  Task createFromQuickAdd(String input, {Space? defaultSpace, String? source, String? fromNote, String? project}) {
    final q = parseQuickAdd(input, spaces: spaces, now: now);
    return createTask(
      title: q.title.isEmpty ? input.trim() : q.title,
      space: q.space ?? defaultSpace,
      priority: q.priority ?? Priority.low,
      urgent: q.urgent,
      due: q.due ?? (q.repeat != null ? Due(DateTime(now.year, now.month, now.day)) : null),
      repeat: q.repeat,
      people: q.people,
      source: source,
      fromNote: fromNote,
      project: project,
    );
  }

  /// Saves a task after its fields were changed. A new title renames the
  /// file and updates every `[[link]]` that pointed at the old one.
  void saveTask(Task t, {String? newTitle}) {
    if (newTitle != null && newTitle.trim().isNotEmpty && safeName(newTitle) != t.title) {
      final oldTitle = t.title;
      final newPath = _uniquePath('Tasks', newTitle, except: t.path);
      source.rename(t.path, newPath);
      t.path = newPath;
      t.title = titleFromPath(newPath);
      _relink(oldTitle, t.title);
    }
    source.write(t.path, t.toMarkdown());
  }

  void deleteTask(Task t) {
    tasks.remove(t);
    source.delete(t.path);
  }

  /// Marks a task done or open, and ticks the matching line in any note
  /// that links to it.
  void setTaskDone(Task t, bool done) {
    // A repeating task moves to its next date instead of staying done.
    if (done && t.repeat != null) {
      final from = t.due?.date ?? now;
      final next = t.repeat!.next(from, now);
      t
        ..due = Due(next, hasTime: t.due?.hasTime ?? false)
        ..status = TaskStatus.todo
        ..completed = null
        ..lastDone = today;
      source.write(t.path, t.toMarkdown());
      return;
    }
    t.status = done ? TaskStatus.done : (t.status == TaskStatus.done ? TaskStatus.todo : t.status);
    t.completed = done ? today : null;
    source.write(t.path, t.toMarkdown());
    for (final n in notes) {
      final updated = _setLineTick(n.body, t.title, done);
      if (updated != n.body) {
        n.body = updated;
        source.write(n.path, n.toMarkdown());
      }
    }
  }

  void toggleSubtask(Task t, int line) {
    final lines = t.body.split('\n');
    final m = checklistLine.firstMatch(lines[line]);
    if (m == null) return;
    final mark = m.group(2)!.toLowerCase() == 'x' ? ' ' : 'x';
    lines[line] = '${m.group(1)}[$mark] ${m.group(3)}';
    t.body = lines.join('\n');
    source.write(t.path, t.toMarkdown());
  }

  String _setLineTick(String body, String taskTitle, bool done) {
    final lines = body.split('\n');
    var changed = false;
    for (var i = 0; i < lines.length; i++) {
      final m = checklistLine.firstMatch(lines[i]);
      if (m == null) continue;
      if (!linksIn(m.group(3)!).any((l) => l.toLowerCase() == taskTitle.toLowerCase())) continue;
      final want = done ? 'x' : ' ';
      if (m.group(2)!.toLowerCase() != want) {
        lines[i] = '${m.group(1)}[$want] ${m.group(3)}';
        changed = true;
      }
    }
    return changed ? lines.join('\n') : body;
  }

  void _relink(String oldTitle, String newTitle) {
    final re = RegExp(r'\[\[' + RegExp.escape(oldTitle) + r'(#[^\]|]*)?(\|[^\]]*)?\]\]', caseSensitive: false);
    String fix(String s) => s.replaceAllMapped(re, (m) => '[[$newTitle${m.group(1) ?? ''}${m.group(2) ?? ''}]]');
    for (final n in notes) {
      final b = fix(n.body);
      final p = n.project?.toLowerCase() == oldTitle.toLowerCase() ? newTitle : n.project;
      if (b != n.body || p != n.project) {
        n
          ..body = b
          ..project = p;
        source.write(n.path, n.toMarkdown());
      }
    }
    for (final t in tasks) {
      final b = fix(t.body);
      var touched = b != t.body;
      t.body = b;
      if (t.fromNote?.toLowerCase() == oldTitle.toLowerCase()) {
        t.fromNote = newTitle;
        touched = true;
      }
      if (t.project?.toLowerCase() == oldTitle.toLowerCase()) {
        t.project = newTitle;
        touched = true;
      }
      if (touched) source.write(t.path, t.toMarkdown());
    }
  }

  // ------------------------------------------------------------ notes

  String _noteFolder(NoteKind kind, Space? space) {
    final sp = space == null ? null : spacePath(space);
    return switch (kind) {
      NoteKind.daily => 'Daily',
      NoteKind.person => 'People',
      NoteKind.project => sp == null ? 'Projects' : '$sp/Projects',
      _ => sp == null ? 'Notes' : '$sp/Notes',
    };
  }

  /// The starting text for a new note of this type: the person's own
  /// template note if there is one, otherwise the built-in one.
  String templateFor(NoteKind kind) {
    final own = notes.where((n) => n.path == templatePath(kind)).firstOrNull;
    return own?.body ?? builtInTemplates[kind] ?? '';
  }

  Note createNote({required String title, NoteKind kind = NoteKind.plain, Space? space, String? project, String? body}) {
    body ??= templateFor(kind);
    final n = Note(
      path: _uniquePath(_noteFolder(kind, space), title.trim().isEmpty ? 'Untitled' : title),
      title: '',
      id: 'n_${newRecordId().substring(0, 10)}',
      kind: kind,
      spaceName: space == null ? null : spacePath(space),
      project: project,
      created: today,
      body: body,
    );
    n.title = titleFromPath(n.path);
    notes.add(n);
    source.write(n.path, n.toMarkdown());
    return n;
  }

  Note dailyNote(DateTime day) {
    final title = isoDay(day);
    final existing = notes.where((n) => n.path == 'Daily/$title.md').firstOrNull;
    if (existing != null) return existing;
    return createNote(title: title, kind: NoteKind.daily);
  }

  Note? noteByTitle(String title) {
    final lower = title.toLowerCase();
    return notes.where((n) => n.title.toLowerCase() == lower).firstOrNull;
  }

  /// Saves an edited note. Ticking `- [x] [[Some task]]` in a note marks
  /// that task done (and unticking reopens it), however the note was edited.
  void saveNote(Note n, {String? newTitle}) {
    if (newTitle != null && newTitle.trim().isNotEmpty && safeName(newTitle) != n.title) {
      final oldTitle = n.title;
      final folder = n.path.contains('/') ? n.path.substring(0, n.path.lastIndexOf('/')) : '';
      final newPath = _uniquePath(folder, newTitle, except: n.path);
      source.rename(n.path, newPath);
      n.path = newPath;
      n.title = titleFromPath(newPath);
      _relink(oldTitle, n.title);
    }
    source.write(n.path, n.toMarkdown());
    syncTicksFromNote(n);
  }

  void moveNote(Note n, Space? space) {
    n.spaceName = space == null ? null : spacePath(space);
    final newPath = _uniquePath(_noteFolder(n.kind, space), n.title, except: n.path);
    source.write(n.path, n.toMarkdown());
    if (newPath != n.path) {
      source.rename(n.path, newPath);
      n.path = newPath;
    }
  }

  void deleteNote(Note n) {
    notes.remove(n);
    source.delete(n.path);
  }

  void syncTicksFromNote(Note n) {
    for (final line in n.body.split('\n')) {
      final m = checklistLine.firstMatch(line);
      if (m == null) continue;
      final done = m.group(2)!.toLowerCase() == 'x';
      for (final title in linksIn(m.group(3)!)) {
        final t = taskByTitle(title);
        if (t == null || t.done == done) continue;
        t.status = done ? TaskStatus.done : TaskStatus.todo;
        t.completed = done ? today : null;
        source.write(t.path, t.toMarkdown());
      }
    }
  }

  /// "Make task" on one line of a note: the line becomes a linked
  /// checklist item and the task remembers which note it came from.
  Task makeTaskFromLine(Note n, int lineIndex) {
    final lines = n.body.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) throw RangeError.index(lineIndex, lines);
    final raw = lines[lineIndex];
    final m = checklistLine.firstMatch(raw);
    final indent = RegExp(r'^\s*').firstMatch(raw)!.group(0)!;
    final text = (m != null ? m.group(3)! : raw.replaceFirst(RegExp(r'^\s*([-*]|\d+\.)\s+'), '')).trim();
    if (text.isEmpty) throw ArgumentError('That line is empty.');
    final existing = linksIn(text).map(taskByTitle).whereType<Task>().firstOrNull;
    if (existing != null) return existing;
    final task = createFromQuickAdd(text, defaultSpace: spaceOfNote(n), source: 'note', fromNote: n.title, project: n.project);
    lines[lineIndex] = '$indent- [ ] ${link(task.title)}';
    n.body = lines.join('\n');
    source.write(n.path, n.toMarkdown());
    return task;
  }

  /// Notes and tasks that link to [title].
  ({List<Note> notes, List<Task> tasks}) backlinks(String title) {
    final lower = title.toLowerCase();
    bool hit(String body) => linksIn(body).any((l) => l.toLowerCase() == lower);
    return (
      notes: notes.where((n) => n.title.toLowerCase() != lower && (hit(n.body) || n.project?.toLowerCase() == lower)).toList(),
      tasks: tasks
          .where(
            (t) =>
                hit(t.body) ||
                t.fromNote?.toLowerCase() == lower ||
                t.project?.toLowerCase() == lower ||
                t.people.any((p) => p.toLowerCase() == lower),
          )
          .toList(),
    );
  }

  List<String> get projectNames {
    final names = <String>{
      ...notes.where((n) => n.kind == NoteKind.project).map((n) => n.title),
      ...tasks.map((t) => t.project).whereType<String>(),
    };
    return names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> get peopleNames {
    final names = <String>{
      ...notes.where((n) => n.kind == NoteKind.person).map((n) => n.title),
      ...tasks.expand((t) => t.people),
      ...tasks.map((t) => t.waitingOn).whereType<String>(),
    };
    return names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}

const _keep = Object();
