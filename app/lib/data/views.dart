/// The ways of looking at tasks: Today, Upcoming, Inbox, Matrix, Board.
library;

import 'library.dart';
import 'models.dart';

enum Quadrant { doNow, schedule, delegate, later }

extension QuadrantInfo on Quadrant {
  String get label => switch (this) {
    Quadrant.doNow => 'Do now',
    Quadrant.schedule => 'Schedule it',
    Quadrant.delegate => 'Delegate or do quickly',
    Quadrant.later => 'Drop or later',
  };
  bool get urgent => this == Quadrant.doNow || this == Quadrant.delegate;
  Priority get priority => (this == Quadrant.doNow || this == Quadrant.schedule) ? Priority.high : Priority.low;
}

/// Filters by Space (including sub-spaces). Null = all Spaces.
class SpaceFilter {
  const SpaceFilter(this.ids);
  final Set<String>? ids;
  static const all = SpaceFilter(null);
  bool matches(Library lib, Space? s) => ids == null || (s != null && ids!.contains(s.id));
}

class Views {
  Views(this.lib, {this.filter = SpaceFilter.all});
  final Library lib;
  final SpaceFilter filter;

  DateTime get _now => lib.now;
  DateTime get _today => DateTime(_now.year, _now.month, _now.day);

  Iterable<Task> get _open => lib.tasks.where((t) => !t.done && filter.matches(lib, lib.spaceOf(t)));

  bool isUrgent(Task t) {
    if (t.urgentOverride != null) return t.urgentOverride!;
    final due = t.due;
    if (due == null) return false;
    final limit = _today.add(Duration(days: lib.settings.urgentWithinDays + 1));
    return due.day.isBefore(limit);
  }

  bool isOverdue(Task t) {
    final due = t.due;
    if (due == null || t.done) return false;
    return due.hasTime ? due.date.isBefore(_now) : due.day.isBefore(_today);
  }

  int _byDue(Task a, Task b) {
    final ad = a.due?.date, bd = b.due?.date;
    if (ad == null && bd == null) return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (ad == null) return 1;
    if (bd == null) return -1;
    final c = ad.compareTo(bd);
    if (c != 0) return c;
    if (a.priority != b.priority) return a.priority == Priority.high ? -1 : 1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  /// Due today or overdue, high priority first within the same time.
  List<Task> today() {
    final end = _today.add(const Duration(days: 1));
    return _open.where((t) => t.due != null && t.due!.day.isBefore(end)).toList()..sort(_byDue);
  }

  /// After today, grouped by day.
  Map<DateTime, List<Task>> upcoming({int days = 30}) {
    final start = _today.add(const Duration(days: 1));
    final end = _today.add(Duration(days: days + 1));
    final out = <DateTime, List<Task>>{};
    final list = _open.where((t) => t.due != null && !t.due!.day.isBefore(start) && t.due!.day.isBefore(end)).toList()..sort(_byDue);
    for (final t in list) {
      out.putIfAbsent(t.due!.day, () => []).add(t);
    }
    return out;
  }

  /// Captured but not sorted yet: no Space, or no date and no Space.
  List<Task> inbox() => lib.tasks.where((t) => !t.done && lib.spaceOf(t) == null).toList()..sort(_byDue);

  List<Task> anytime() => _open.where((t) => t.due == null && lib.spaceOf(t) != null).toList()..sort(_byDue);

  Quadrant quadrantOf(Task t) {
    final urgent = isUrgent(t);
    final high = t.priority == Priority.high;
    if (urgent && high) return Quadrant.doNow;
    if (!urgent && high) return Quadrant.schedule;
    if (urgent) return Quadrant.delegate;
    return Quadrant.later;
  }

  Map<Quadrant, List<Task>> matrix() {
    final out = {for (final q in Quadrant.values) q: <Task>[]};
    for (final t in _open) {
      out[quadrantOf(t)]!.add(t);
    }
    for (final l in out.values) {
      l.sort(_byDue);
    }
    return out;
  }

  /// Moving a task in the Matrix sets its priority, and urgency by hand
  /// unless the automatic rule already agrees.
  void moveToQuadrant(Task t, Quadrant q) {
    t.priority = q.priority;
    t.urgentOverride = null;
    if (isUrgent(t) != q.urgent) t.urgentOverride = q.urgent;
    lib.saveTask(t);
  }

  Map<TaskStatus, List<Task>> board({bool includeDone = true}) {
    final out = {for (final s in TaskStatus.values) s: <Task>[]};
    final doneSince = _today.subtract(const Duration(days: 7));
    for (final t in lib.tasks.where((t) => filter.matches(lib, lib.spaceOf(t)))) {
      if (t.done) {
        if (!includeDone) continue;
        final c = DateTime.tryParse(t.completed ?? '');
        if (c != null && c.isBefore(doneSince)) continue;
      }
      out[t.status]!.add(t);
    }
    for (final l in out.values) {
      l.sort(_byDue);
    }
    return out;
  }

  void moveToStatus(Task t, TaskStatus s) {
    if (s == TaskStatus.done) {
      lib.setTaskDone(t, true);
    } else {
      if (t.done) lib.setTaskDone(t, false);
      t.status = s;
      lib.saveTask(t);
    }
  }

  List<Task> doneToday() => lib.tasks.where((t) => t.done && t.completed == lib.today && filter.matches(lib, lib.spaceOf(t))).toList();

  int openCount(Space s) {
    final ids = lib.subtreeIds(s);
    return lib.tasks.where((t) => !t.done && ids.contains(lib.spaceOf(t)?.id)).length;
  }

  List<Task> inSpace(Space s) {
    final ids = lib.subtreeIds(s);
    return lib.tasks.where((t) => !t.done && ids.contains(lib.spaceOf(t)?.id)).toList()..sort(_byDue);
  }

  List<Note> notesIn({Space? space, NoteKind? kind}) {
    final ids = space == null ? null : lib.subtreeIds(space);
    return lib.notes.where((n) => (ids == null || ids.contains(lib.spaceOfNote(n)?.id)) && (kind == null || n.kind == kind)).toList()..sort(
      (a, b) => (b.created ?? '').compareTo(a.created ?? '') != 0
          ? (b.created ?? '').compareTo(a.created ?? '')
          : a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
  }

  ({List<Task> tasks, List<Note> notes}) search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return (tasks: const [], notes: const []);
    return (
      tasks: lib.tasks.where((t) => t.title.toLowerCase().contains(q) || t.body.toLowerCase().contains(q)).toList()..sort(_byDue),
      notes: lib.notes.where((n) => n.title.toLowerCase().contains(q) || n.body.toLowerCase().contains(q)).toList(),
    );
  }

  /// The weekly review: what got done, what slipped, what is waiting.
  ({List<Task> done, List<Task> slipped, List<Task> waiting, List<Task> undated}) review() {
    final weekAgo = _today.subtract(const Duration(days: 7));
    bool inFilter(Task t) => filter.matches(lib, lib.spaceOf(t));
    final done = lib.tasks.where((t) {
      final when = DateTime.tryParse(t.completed ?? t.lastDone ?? '');
      return inFilter(t) && when != null && !when.isBefore(weekAgo);
    }).toList()..sort((a, b) => (b.completed ?? b.lastDone ?? '').compareTo(a.completed ?? a.lastDone ?? ''));
    return (
      done: done,
      slipped: _open.where(isOverdue).toList()..sort(_byDue),
      waiting: _open.where((t) => t.status == TaskStatus.waiting).toList()..sort(_byDue),
      undated: _open.where((t) => t.due == null && t.priority == Priority.high).toList()..sort(_byDue),
    );
  }

  /// Open tasks due on each day of a month.
  Map<DateTime, List<Task>> month(int year, int month) {
    final out = <DateTime, List<Task>>{};
    for (final t in _open) {
      final d = t.due?.day;
      if (d == null || d.year != year || d.month != month) continue;
      out.putIfAbsent(d, () => []).add(t);
    }
    for (final l in out.values) {
      l.sort(_byDue);
    }
    return out;
  }
}
