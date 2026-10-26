import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../../data/views.dart';
import '../detail/note_editor.dart';
import '../detail/task_detail.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'board_view.dart';
import 'calendar_view.dart';
import 'matrix_view.dart';
import 'notes_view.dart';
import 'quick_add_bar.dart';
import 'sidebar.dart';
import 'task_row.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _quickFocus = FocusNode();
  final _searchFocus = FocusNode();

  AppController get c => widget.controller;

  @override
  void dispose() {
    _quickFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _newNote() {
    final space = c.view == NavView.space ? c.library!.spaceById(c.spaceId) : null;
    final n = c.edit((lib) => lib.createNote(title: 'Untitled', space: space));
    c.selectNote(n);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.library == null) return const Scaffold(body: SizedBox.shrink());
        final note = c.selectedNote;
        final task = c.selectedTask;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => _quickFocus.requestFocus(),
            const SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true): _newNote,
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => _searchFocus.requestFocus(),
            const SingleActivator(LogicalKeyboardKey.keyL, meta: true): c.lockNow,
            const SingleActivator(LogicalKeyboardKey.escape): () => c.selectTask(null),
            const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () => c.go(NavView.today),
            const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () => c.go(NavView.matrix),
            const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () => c.go(NavView.board),
            const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () => c.go(NavView.notes),
            const SingleActivator(LogicalKeyboardKey.digit5, meta: true): () => c.go(NavView.calendar),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Sidebar(c: c, searchFocus: _searchFocus),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ..._banners(context),
                        Expanded(
                          child: note != null ? NoteEditor(key: ValueKey(note.id ?? note.path), c: c, note: note) : _content(context),
                        ),
                      ],
                    ),
                  ),
                  if (task != null && note == null)
                    Container(
                      width: 380,
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: t.line)),
                      ),
                      child: TaskDetail(key: ValueKey(task.id ?? task.path), c: c, task: task),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _banners(BuildContext context) => [
    if (c.library != null && c.library!.spaces.isEmpty)
      HomeBanner(
        key: const Key('banner-spaces'),
        text: 'You have no Spaces yet. Add one for each part of your life, for example Personal, Work and your business.',
        action: 'Add Spaces',
        onPressed: () => showSettings(context, c, tab: SettingsTab.spaces),
      ),
    if (c.mirrorError != null)
      HomeBanner(
        key: const Key('banner-folder'),
        text: c.mirrorError!,
        action: 'Folder settings',
        warning: true,
        onPressed: () => showSettings(context, c, tab: SettingsTab.sync),
      ),
  ];

  Widget _content(BuildContext context) {
    switch (c.view) {
      case NavView.matrix:
        return _Page(
          title: 'Matrix',
          subtitle: 'Drag a task to another box to change its priority or urgency',
          filter: true,
          c: c,
          child: MatrixView(c: c),
        );
      case NavView.board:
        return _Page(
          title: 'Board',
          subtitle: 'Drag tasks between columns',
          filter: true,
          c: c,
          child: BoardView(c: c),
        );
      case NavView.notes:
        return _Page(
          title: 'Notes',
          filter: true,
          c: c,
          actions: [QuietButton(label: 'New note', icon: Icons.add, onPressed: _newNote)],
          child: NotesView(c: c),
        );
      case NavView.calendar:
        return _Page(
          title: 'Calendar',
          subtitle: 'Drag a task to another day to move it',
          filter: true,
          c: c,
          scroll: true,
          maxWidth: 1240,
          child: CalendarView(c: c),
        );
      case NavView.review:
        return _Page(
          title: 'Weekly review',
          subtitle: 'What got done, what slipped, what is waiting',
          filter: true,
          c: c,
          scroll: true,
          child: _review(),
        );
      case NavView.search:
        return _Page(title: 'Search', subtitle: '"${c.searchQuery}"', c: c, scroll: true, child: _search());
      default:
        return _Page(
          title: _title(),
          subtitle: _subtitle(),
          filter: c.view == NavView.today || c.view == NavView.upcoming,
          c: c,
          scroll: true,
          actions: [
            if (c.view == NavView.today)
              QuietButton(
                label: "Today's note",
                icon: Icons.edit_note,
                onPressed: () => c.selectNote(c.edit((lib) => lib.dailyNote(c.now))),
              ),
            if (c.view == NavView.space) QuietButton(label: 'New note', icon: Icons.add, onPressed: _newNote),
          ],
          header: QuickAddBar(c: c, focusNode: _quickFocus),
          child: _list(),
        );
    }
  }

  String _title() => switch (c.view) {
    NavView.inbox => 'Inbox',
    NavView.today => 'Today',
    NavView.upcoming => 'Upcoming',
    NavView.space => c.library!.spaceById(c.spaceId)?.name ?? 'Space',
    _ => '',
  };

  String? _subtitle() => switch (c.view) {
    NavView.today => '${longDate(c.now)} · ${c.filterIds == null ? 'all Spaces' : 'filtered'}',
    NavView.inbox => 'Tasks without a Space. Open one to give it a Space.',
    NavView.upcoming => 'The next 30 days',
    _ => null,
  };

  Widget _list() {
    final v = c.views;
    switch (c.view) {
      case NavView.inbox:
        return TaskSections(
          c: c,
          sections: [('', v.inbox())],
          empty: 'Inbox is empty. New tasks without a #Space land here.',
          showSpace: false,
        );
      case NavView.today:
        final today = v.today();
        final overdue = today.where(v.isOverdue).toList();
        final rest = today.where((x) => !v.isOverdue(x)).toList();
        final done = v.doneToday();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaskSections(c: c, sections: [('Overdue', overdue), (overdue.isEmpty ? '' : 'Today', rest)], empty: 'Nothing due today.'),
            if (done.isNotEmpty) _DoneToday(c: c, tasks: done),
          ],
        );
      case NavView.upcoming:
        final groups = v.upcoming();
        return TaskSections(
          c: c,
          sections: [for (final e in groups.entries) (dueLabel(Due(e.key), c.now), e.value)],
          empty: 'Nothing scheduled in the next 30 days.',
        );
      case NavView.space:
        final s = c.library!.spaceById(c.spaceId);
        if (s == null) return const EmptyHint('This Space was removed.');
        final all = v.inSpace(s);
        final notes = Views(c.library!).notesIn(space: s);
        final end = DateTime(c.now.year, c.now.month, c.now.day + 1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaskSections(
              c: c,
              sections: [
                ('Today and overdue', all.where((x) => x.due != null && x.due!.day.isBefore(end)).toList()),
                ('Coming up', all.where((x) => x.due != null && !x.due!.day.isBefore(end)).toList()),
                ('Anytime', all.where((x) => x.due == null).toList()),
              ],
              empty: 'No open tasks here yet.',
            ),
            if (notes.isNotEmpty) ...[SectionLabel('Notes · ${notes.length}'), for (final n in notes.take(20)) NoteRow(c: c, note: n)],
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _review() {
    final r = c.views.review();
    return TaskSections(
      c: c,
      sections: [
        ('Slipped (overdue)', r.slipped),
        ('Waiting on someone', r.waiting),
        ('High priority with no date', r.undated),
        ('Done in the last 7 days', r.done),
      ],
      empty: 'Nothing to review yet.',
    );
  }

  Widget _search() {
    final r = c.views.search(c.searchQuery);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskSections(c: c, sections: [('Tasks', r.tasks)], empty: 'No tasks match.'),
        if (r.notes.isNotEmpty) ...[SectionLabel('Notes · ${r.notes.length}'), for (final n in r.notes) NoteRow(c: c, note: n)],
      ],
    );
  }
}

class _DoneToday extends StatefulWidget {
  const _DoneToday({required this.c, required this.tasks});
  final AppController c;
  final List<Task> tasks;
  @override
  State<_DoneToday> createState() => _DoneTodayState();
}

class _DoneTodayState extends State<_DoneToday> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => open = !open),
            icon: Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: t.sub),
            label: Text('Done today · ${widget.tasks.length}', style: t.text(13, color: t.sub)),
          ),
        ),
        if (open)
          for (final task in widget.tasks) TaskRow(c: widget.c, task: task),
      ],
    );
  }
}

/// A page: title, optional Space filter, optional header, content.
class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.c,
    required this.child,
    this.subtitle,
    this.filter = false,
    this.header,
    this.actions = const [],
    this.scroll = false,
    this.maxWidth = 860,
  });
  final String title;
  final String? subtitle;
  final AppController c;
  final bool filter;
  final Widget? header;
  final List<Widget> actions;
  final Widget child;
  final bool scroll;

  /// Lists read best in a column, not stretched across a wide window.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final top = Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: t.title),
                  if (subtitle != null) Text(subtitle!, style: t.text(13, color: t.sub)),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...actions,
                  if (filter) SpaceFilterButton(c: c),
                ],
              ),
            ],
          ),
          if (header != null) ...[const SizedBox(height: 18), header!],
          const SizedBox(height: 8),
        ],
      ),
    );
    if (scroll) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  top,
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        top,
        Expanded(
          child: Padding(padding: const EdgeInsets.fromLTRB(32, 8, 32, 24), child: child),
        ),
      ],
    );
  }
}

/// "All Spaces ▾": shows one Space (with its sub-Spaces) or all of them.
class SpaceFilterButton extends StatelessWidget {
  const SpaceFilterButton({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final lib = c.library!;
    final tops = lib.children(null);
    Space? current;
    for (final s in tops) {
      if (c.filterIds != null && c.filterIds!.contains(s.id) && c.filterIds!.length == lib.subtreeIds(s).length) current = s;
    }
    final label = c.filterIds == null ? 'All Spaces' : (current?.name ?? 'Filtered');
    return PopupMenuButton<String>(
      tooltip: 'Show one Space',
      position: PopupMenuPosition.under,
      onSelected: (id) => c.setFilter(id.isEmpty ? null : lib.subtreeIds(lib.spaceById(id)!)),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: '',
          child: Row(
            children: [
              Icon(Icons.all_inclusive, size: 15, color: t.sub),
              const SizedBox(width: 10),
              const Text('All Spaces'),
              if (c.filterIds == null) ...[const Spacer(), Icon(Icons.check, size: 16, color: t.accent)],
            ],
          ),
        ),
        for (final s in tops)
          PopupMenuItem(
            value: s.id,
            child: Row(
              children: [
                SpaceDot(s.color),
                const SizedBox(width: 10),
                Text(s.name),
                if (current == s) ...[const Spacer(), Icon(Icons.check, size: 16, color: t.accent)],
              ],
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.filterIds == null ? null : t.accentTint,
          border: Border.all(color: c.filterIds == null ? t.line : t.accent.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (current != null) ...[SpaceDot(current.color, size: 7), const SizedBox(width: 6)],
            Text(label, style: t.text(13)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: t.sub),
          ],
        ),
      ),
    );
  }
}

/// A one-line notice across the top of the main area.
class HomeBanner extends StatelessWidget {
  const HomeBanner({super.key, required this.text, required this.action, required this.onPressed, this.warning = false});
  final String text;
  final String action;
  final VoidCallback onPressed;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: warning ? t.urgentBg : t.accentTint,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          Icon(warning ? Icons.error_outline : Icons.info_outline, size: 18, color: warning ? t.urgentInk : t.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: t.body)),
          const SizedBox(width: 10),
          TextButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }
}
