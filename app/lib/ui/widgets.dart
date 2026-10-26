/// Small building blocks used across Comb's screens.
library;

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'theme.dart';

class SpaceDot extends StatelessWidget {
  const SpaceDot(this.color, {super.key, this.size = 8});
  final String? color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: context.comb.space(color), shape: BoxShape.circle),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.bg, this.fg, this.outlined = false});
  final String text;
  final Color? bg;
  final Color? fg;
  final bool outlined;

  factory Pill.urgent(BuildContext context) => Pill('Urgent', bg: context.comb.urgentBg, fg: context.comb.urgentInk);
  factory Pill.high(BuildContext context) => Pill('High', fg: context.comb.ink, outlined: true);

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: outlined ? null : bg,
        border: outlined ? Border.all(color: t.line) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: t.text(11, weight: FontWeight.w600, color: fg ?? t.ink, height: 1.2),
      ),
    );
  }
}

/// The black (or white, in dark mode) main button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: t.ink,
        foregroundColor: t.bg,
        disabledBackgroundColor: t.ink.withValues(alpha: 0.4),
        disabledForegroundColor: t.bg,
        minimumSize: const Size(88, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: t.text(14, weight: FontWeight.w500),
      ),
      child: busy
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.bg))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
                Text(label),
              ],
            ),
    );
  }
}

class QuietButton extends StatelessWidget {
  const QuietButton({super.key, required this.label, required this.onPressed, this.icon, this.danger = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    final color = danger ? t.urgentInk : t.ink;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: t.line),
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: t.text(13, weight: FontWeight.w500),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 6)],
          Text(label),
        ],
      ),
    );
  }
}

/// A row of mutually exclusive choices (Light / Dark / Auto…).
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.values, required this.selected, required this.label, required this.onChanged});
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    // Scrolls sideways instead of overflowing when the space is narrow.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in values)
              Semantics(
                button: true,
                selected: v == selected,
                child: InkWell(
                  onTap: () => onChanged(v),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    color: v == selected ? t.ink : null,
                    child: Text(
                      label(v),
                      style: t.text(13, weight: v == selected ? FontWeight.w600 : FontWeight.w400, color: v == selected ? t.bg : t.ink),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A round "mark done" button.
class DoneCircle extends StatelessWidget {
  const DoneCircle({super.key, required this.done, required this.onTap, this.size = 20});
  final bool done;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.comb;
    return Semantics(
      button: true,
      checked: done,
      label: done ? 'Mark not done' : 'Mark done',
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? t.accent : null,
              border: Border.all(color: done ? t.accent : t.faint, width: 1.5),
            ),
            child: done ? Icon(Icons.check, size: size * 0.7, color: t.bg) : null,
          ),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
    child: Row(
      children: [
        Expanded(child: Text(text, style: context.comb.label)),
        ?trailing,
      ],
    ),
  );
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
    child: Text(text, style: context.comb.text(14, color: context.comb.sub)),
  );
}

/// "4 PM", "Tomorrow 9 AM", "Fri", "28 Oct". [withDay] keeps "Today" with a time.
String dueLabel(Due? due, DateTime now, {bool withDay = false}) {
  if (due == null) return '';
  final today = DateTime(now.year, now.month, now.day);
  final diff = due.day.difference(today).inDays;
  final time = due.hasTime ? _time(due.date) : null;
  String day;
  if (diff == 0) {
    day = 'Today';
  } else if (diff == 1) {
    day = 'Tomorrow';
  } else if (diff == -1) {
    day = 'Yesterday';
  } else if (diff > 1 && diff < 7) {
    day = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][due.date.weekday - 1];
  } else {
    day = '${due.date.day} ${_months[due.date.month - 1]}${due.date.year != now.year ? ' ${due.date.year}' : ''}';
  }
  if (time == null) return day;
  return diff == 0 && !withDay ? time : '$day $time';
}

String _time(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute == 0 ? '' : ':${d.minute.toString().padLeft(2, '0')}';
  return '$h$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String longDate(DateTime d) {
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}
