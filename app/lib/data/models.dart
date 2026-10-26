/// Spaces, tasks and notes as Comb sees them. Each task and note is one
/// markdown file; Spaces and shared settings live in `.comb/workspace.json`.
library;

import 'package:flutter/foundation.dart';

import 'frontmatter.dart';

const workspacePath = '.comb/workspace.json';

class Space {
  Space({
    required this.id,
    required this.name,
    this.parentId,
    this.color = 'blue',
    List<String>? categories,
    this.email,
    this.logoPath,
    this.archived = false,
    this.order = 0,
  }) : categories = categories ?? [];

  final String id;
  String name;
  String? parentId;

  /// A named palette colour (see ui/theme/tokens.dart), not a hex value,
  /// so it adapts to light and dark themes.
  String color;
  List<String> categories;
  String? email;
  String? logoPath;
  bool archived;
  int order;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'parent': parentId,
        'color': color,
        'categories': categories,
        'email': email,
        'logo': logoPath,
        'archived': archived,
        'order': order,
      };

  static Space fromJson(Map<String, dynamic> j) => Space(
        id: j['id'] as String,
        name: j['name'] as String,
        parentId: j['parent'] as String?,
        color: (j['color'] as String?) ?? 'blue',
        categories: ((j['categories'] as List?) ?? const []).cast<String>().toList(),
        email: j['email'] as String?,
        logoPath: j['logo'] as String?,
        archived: (j['archived'] as bool?) ?? false,
        order: (j['order'] as num?)?.toInt() ?? 0,
      );
}

class WorkspaceSettings {
  WorkspaceSettings({this.urgentWithinDays = 2});
  int urgentWithinDays;
  Map<String, Object?> toJson() => {'urgent_within_days': urgentWithinDays};
  static WorkspaceSettings fromJson(Map<String, dynamic>? j) =>
      WorkspaceSettings(urgentWithinDays: (j?['urgent_within_days'] as num?)?.toInt() ?? 2);
}

enum TaskStatus { todo, doing, waiting, done }

enum Priority { high, low }

enum NoteKind { plain, meeting, call, project, person, daily }

extension NoteKindLabel on NoteKind {
  String get label => switch (this) {
        NoteKind.plain => 'Note',
        NoteKind.meeting => 'Meeting',
        NoteKind.call => 'Call',
        NoteKind.project => 'Project',
        NoteKind.person => 'Person',
        NoteKind.daily => 'Daily note',
      };
}

extension TaskStatusLabel on TaskStatus {
  String get label => switch (this) {
        TaskStatus.todo => 'To do',
        TaskStatus.doing => 'Doing',
        TaskStatus.waiting => 'Waiting',
        TaskStatus.done => 'Done',
      };
}

/// A due date with an optional time of day.
@immutable
class Due {
  const Due(this.date, {this.hasTime = false});
  final DateTime date;
  final bool hasTime;

  static Due? parse(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final dt = DateTime.tryParse(s);
    if (dt == null) return null;
    return Due(dt, hasTime: s.contains('T'));
  }

  DateTime get day => DateTime(date.year, date.month, date.day);

  String serialize() {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = '${date.year}-${two(date.month)}-${two(date.day)}';
    return hasTime ? '${d}T${two(date.hour)}:${two(date.minute)}' : d;
  }

  @override
  bool operator ==(Object other) => other is Due && other.date == date && other.hasTime == hasTime;
  @override
  int get hashCode => Object.hash(date, hasTime);
}

String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Task {
  Task({
    required this.path,
    required this.title,
    this.id,
    this.spaceName,
    this.category,
    this.project,
    this.priority = Priority.low,
    this.urgentOverride,
    this.status = TaskStatus.todo,
    this.due,
    this.waitingOn,
    List<String>? people,
    this.source,
    this.fromNote,
    this.created,
    this.completed,
    this.body = '',
    Map<String, Object?>? extra,
  })  : people = people ?? [],
        extra = extra ?? {};

  String path;
  String title;
  String? id;
  String? spaceName;
  String? category;
  String? project;
  Priority priority;

  /// Null = automatic (urgent when due soon). True/false = set by hand.
  bool? urgentOverride;
  TaskStatus status;
  Due? due;
  String? waitingOn;
  List<String> people;
  String? source;
  String? fromNote;
  String? created;
  String? completed;
  String body;

  /// Frontmatter keys Comb doesn't use, kept untouched.
  Map<String, Object?> extra;

  bool get done => status == TaskStatus.done;

  static const _known = {
    'id', 'type', 'space', 'category', 'project', 'priority', 'urgent', 'status', 'due',
    'waiting_on', 'people', 'source', 'from', 'created', 'completed',
  };

  static Task fromMarkdown(String path, String text) {
    final doc = MarkdownDoc.parse(text);
    final f = doc.fields;
    final urgent = f['urgent'];
    return Task(
      path: path,
      title: titleFromPath(path),
      id: f['id']?.toString(),
      spaceName: f['space']?.toString(),
      category: f['category']?.toString(),
      project: f['project'] == null ? null : unlink(f['project']),
      priority: f['priority']?.toString().toLowerCase() == 'high' ? Priority.high : Priority.low,
      urgentOverride: urgent is bool ? urgent : null,
      status: TaskStatus.values.firstWhere((s) => s.name == f['status']?.toString(), orElse: () => TaskStatus.todo),
      due: Due.parse(f['due']),
      waitingOn: f['waiting_on'] == null ? null : unlink(f['waiting_on']),
      people: ((f['people'] as List?) ?? const []).map(unlink).where((p) => p.isNotEmpty).toList(),
      source: f['source']?.toString(),
      fromNote: f['from'] == null ? null : unlink(f['from']),
      created: f['created'] == null ? null : unlink(f['created']),
      completed: f['completed']?.toString(),
      body: doc.body,
      extra: {for (final e in f.entries) if (!_known.contains(e.key)) e.key: e.value},
    );
  }

  String toMarkdown() {
    final fields = <String, Object?>{
      'id': id,
      'type': 'task',
      'space': spaceName,
      'category': category,
      'project': project == null ? null : link(project!),
      'priority': priority.name,
      'urgent': urgentOverride,
      'status': status.name,
      'due': due?.serialize(),
      'waiting_on': waitingOn == null ? null : link(waitingOn!),
      'people': people.map(link).toList(),
      'source': source,
      'from': fromNote == null ? null : link(fromNote!),
      'created': created == null ? null : link(created!),
      'completed': completed,
      ...extra,
    };
    return MarkdownDoc(fields, body).render();
  }

  /// `- [ ]` / `- [x]` lines in the body.
  List<({int line, bool done, String text})> get subtasks {
    final out = <({int line, bool done, String text})>[];
    final lines = body.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final m = checklistLine.firstMatch(lines[i]);
      if (m != null) out.add((line: i, done: m.group(2)!.toLowerCase() == 'x', text: m.group(3)!));
    }
    return out;
  }
}

class Note {
  Note({
    required this.path,
    required this.title,
    this.id,
    this.kind = NoteKind.plain,
    this.spaceName,
    this.project,
    this.created,
    this.body = '',
    Map<String, Object?>? extra,
  }) : extra = extra ?? {};

  String path;
  String title;
  String? id;
  NoteKind kind;
  String? spaceName;
  String? project;
  String? created;
  String body;
  Map<String, Object?> extra;

  static const _known = {'id', 'type', 'kind', 'space', 'project', 'created'};

  static Note fromMarkdown(String path, String text) {
    final doc = MarkdownDoc.parse(text);
    final f = doc.fields;
    final kindName = f['kind']?.toString();
    return Note(
      path: path,
      title: titleFromPath(path),
      id: f['id']?.toString(),
      kind: NoteKind.values.firstWhere((k) => k.name == kindName,
          orElse: () => path.startsWith('Daily/') ? NoteKind.daily : NoteKind.plain),
      spaceName: f['space']?.toString(),
      project: f['project'] == null ? null : unlink(f['project']),
      created: f['created'] == null ? null : unlink(f['created']),
      body: doc.body,
      extra: {for (final e in f.entries) if (!_known.contains(e.key)) e.key: e.value},
    );
  }

  String toMarkdown() {
    final fields = <String, Object?>{
      'id': id,
      'type': 'note',
      'kind': kind.name,
      'space': spaceName,
      'project': project == null ? null : link(project!),
      'created': created == null ? null : link(created!),
      ...extra,
    };
    return MarkdownDoc(fields, body).render();
  }
}

final checklistLine = RegExp(r'^(\s*[-*] )\[( |x|X)\] (.*)$');

String titleFromPath(String path) {
  final name = path.split('/').last;
  return name.toLowerCase().endsWith('.md') ? name.substring(0, name.length - 3) : name;
}

/// File names must work on Mac, Windows, Android and iOS.
String safeName(String title) {
  final cleaned = title.replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return 'Untitled';
  return cleaned.length > 120 ? cleaned.substring(0, 120).trim() : cleaned;
}
