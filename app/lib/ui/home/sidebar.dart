import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../../data/views.dart';
import '../brand.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';
import '../widgets.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.c, required this.searchFocus});
  final AppController c;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final lib = c.library!;
    final v = c.views;
    final allViews = Views(lib);

    Widget nav(NavView view, String label, IconData icon, {int? count}) {
      final on = c.view == view;
      return _NavItem(label: label, icon: icon, on: on, count: count, onTap: () => c.go(view));
    }

    final topSpaces = lib.children(null);

    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: t.side,
        border: Border(right: BorderSide(color: t.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
            child: Row(
              children: [
                const CombMark(),
                const SizedBox(width: 10),
                Text('Comb', style: t.text(16, weight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Lock Comb (⌘L)',
                  icon: Icon(Icons.lock_outline, size: 18, color: t.sub),
                  onPressed: c.lockNow,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              focusNode: searchFocus,
              decoration: const InputDecoration(hintText: 'Search (⌘F)', prefixIcon: Icon(Icons.search, size: 18)),
              onChanged: c.search,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                nav(NavView.inbox, 'Inbox', Icons.inbox_outlined, count: allViews.inbox().length),
                nav(NavView.today, 'Today', Icons.today_outlined, count: v.today().length),
                nav(NavView.upcoming, 'Upcoming', Icons.date_range_outlined),
                nav(NavView.calendar, 'Calendar', Icons.calendar_month_outlined),
                nav(NavView.matrix, 'Matrix', Icons.grid_view_outlined),
                nav(NavView.board, 'Board', Icons.view_kanban_outlined),
                nav(NavView.notes, 'Notes', Icons.notes_outlined),
                nav(NavView.review, 'Weekly review', Icons.fact_check_outlined),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 6),
                  child: Text('Spaces', style: t.label),
                ),
                for (final s in topSpaces) ..._spaceTree(context, s, 0),
                _NavItem(
                  label: 'New Space',
                  icon: Icons.add,
                  quiet: true,
                  onTap: () => showSettings(context, c, tab: SettingsTab.spaces),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
            child: Row(
              children: [
                Icon(
                  c.syncStatus == SyncStatus.offline || c.syncStatus == SyncStatus.error || c.syncStatus == SyncStatus.signedOut
                      ? Icons.cloud_off_outlined
                      : Icons.lock_outline,
                  size: 14,
                  color: t.sub,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.syncLabel, style: t.small, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: Icon(Icons.settings_outlined, size: 18, color: t.sub),
                  onPressed: () => showSettings(context, c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _spaceTree(BuildContext context, Space s, int depth) {
    final lib = c.library!;
    final count = Views(lib).openCount(s);
    return [
      _NavItem(
        label: s.name,
        dot: s.color,
        indent: depth * 18.0,
        on: c.view == NavView.space && c.spaceId == s.id,
        count: count == 0 ? null : count,
        onTap: () => c.go(NavView.space, space: s.id),
      ),
      for (final child in lib.children(s)) ..._spaceTree(context, child, depth + 1),
    ];
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.dot,
    this.on = false,
    this.count,
    this.indent = 0,
    this.quiet = false,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? dot;
  final bool on;
  final int? count;
  final double indent;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final color = on ? t.accent : (quiet ? t.sub : t.ink);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: on ? t.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: EdgeInsets.only(left: 10 + indent, right: 10),
            child: Row(
              children: [
                if (icon != null) Icon(icon, size: 17, color: color),
                if (dot != null) SpaceDot(dot, size: 8),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: t.text(14, weight: on ? FontWeight.w600 : FontWeight.w400, color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count != null) Text('$count', style: t.small),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
