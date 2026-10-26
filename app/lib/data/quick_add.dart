/// Turns "Call GCD tomorrow 4pm #CAX !h !u @Ravi" into a task.
///
/// Recognised anywhere in the text:
///   #Space or #Parent/Child   Space (matched by name, any case)
///   !h !high  /  !l !low       priority
///   !u !urgent                 urgent (by hand)
///   @Name                      person
///   today, tomorrow, tmr, monday..sunday (next one), next week,
///   in 3 days, 28 oct, oct 28, 28/10, 2026-10-28
///   4pm, 4:30pm, 16:00, at 9
///   every day / daily, every weekday, every week / weekly, every month /
///   monthly, every year / yearly   repeat
library;

import 'models.dart';

class QuickAdd {
  QuickAdd({required this.title, this.space, this.priority, this.urgent, this.due, this.repeat, this.people = const []});
  final String title;
  final Space? space;
  final Priority? priority;
  final bool? urgent;
  final Due? due;
  final Repeat? repeat;
  final List<String> people;
}

const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
const _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

QuickAdd parseQuickAdd(String input, {required List<Space> spaces, required DateTime now}) {
  var text = ' ${input.trim()} ';
  Space? space;
  Priority? priority;
  bool? urgent;
  final people = <String>[];
  DateTime? day;
  int? hour;
  int? minute;

  String cut(RegExp re, void Function(Match m) onMatch) {
    final m = re.firstMatch(text);
    if (m == null) return text;
    onMatch(m);
    return text.replaceRange(m.start, m.end, ' ');
  }

  // Spaces: longest name first, so "#Crypt4Bits/Gridnova" beats "#Crypt4Bits".
  final tagRe = RegExp(r'(?<=\s)#([\p{L}\p{N}_\-/]+)(?=\s)', unicode: true);
  for (final m in tagRe.allMatches(text).toList().reversed) {
    final tag = m.group(1)!.toLowerCase();
    final last = tag.split('/').last;
    final match = spaces.where((s) => !s.archived && s.name.toLowerCase().replaceAll(' ', '') == last).firstOrNull;
    if (match != null) {
      space ??= match;
      text = text.replaceRange(m.start, m.end, ' ');
    }
  }

  text = cut(RegExp(r'(?<=\s)!(h|high)(?=\s)', caseSensitive: false), (_) => priority = Priority.high);
  text = cut(RegExp(r'(?<=\s)!(l|low)(?=\s)', caseSensitive: false), (_) => priority = Priority.low);
  text = cut(RegExp(r'(?<=\s)!(u|urgent)(?=\s)', caseSensitive: false), (_) => urgent = true);

  final atRe = RegExp(r'(?<=\s)@([\p{L}\p{N}_\-.]+)(?=\s)', unicode: true);
  for (final m in atRe.allMatches(text).toList().reversed) {
    people.insert(0, m.group(1)!);
    text = text.replaceRange(m.start, m.end, ' ');
  }

  final today = DateTime(now.year, now.month, now.day);

  // Time first, so "28/10 4pm" doesn't read 4 as a day.
  text = cut(RegExp(r'(?<=\s)(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?=\s)', caseSensitive: false), (m) {
    var h = int.parse(m.group(1)!);
    final ampm = m.group(3)!.toLowerCase();
    if (ampm == 'pm' && h < 12) h += 12;
    if (ampm == 'am' && h == 12) h = 0;
    hour = h;
    minute = int.tryParse(m.group(2) ?? '') ?? 0;
  });
  if (hour == null) {
    text = cut(RegExp(r'(?<=\s)(?:at\s+)?([01]?\d|2[0-3]):([0-5]\d)(?=\s)'), (m) {
      hour = int.parse(m.group(1)!);
      minute = int.parse(m.group(2)!);
    });
  }
  if (hour == null) {
    text = cut(RegExp(r'(?<=\s)at\s+(\d{1,2})(?=\s)', caseSensitive: false), (m) {
      final h = int.parse(m.group(1)!);
      if (h <= 23) {
        hour = h;
        minute = 0;
      }
    });
  }

  text = cut(RegExp(r'(?<=\s)(today|tonight)(?=\s)', caseSensitive: false), (_) => day = today);
  if (day == null) {
    text = cut(RegExp(r'(?<=\s)(tomorrow|tmr|tmrw)(?=\s)', caseSensitive: false), (_) => day = today.add(const Duration(days: 1)));
  }
  if (day == null) {
    text = cut(RegExp(r'(?<=\s)next\s+week(?=\s)', caseSensitive: false), (_) {
      final daysToMonday = (DateTime.monday - today.weekday + 7) % 7;
      day = today.add(Duration(days: daysToMonday == 0 ? 7 : daysToMonday));
    });
  }
  if (day == null) {
    text = cut(RegExp(r'(?<=\s)in\s+(\d{1,3})\s+(day|days|week|weeks)(?=\s)', caseSensitive: false), (m) {
      final n = int.parse(m.group(1)!);
      day = today.add(Duration(days: m.group(2)!.toLowerCase().startsWith('week') ? n * 7 : n));
    });
  }
  if (day == null) {
    final names = _weekdays.map((w) => '$w|${w.substring(0, 3)}').join('|');
    text = cut(RegExp('(?<=\\s)(?:on\\s+|next\\s+)?($names)(?=\\s)', caseSensitive: false), (m) {
      final word = m.group(1)!.toLowerCase();
      final target = _weekdays.indexWhere((w) => w == word || w.startsWith(word)) + 1;
      var diff = (target - today.weekday + 7) % 7;
      if (diff == 0) diff = 7;
      day = today.add(Duration(days: diff));
    });
  }
  if (day == null) {
    text = cut(RegExp(r'(?<=\s)(\d{4})-(\d{2})-(\d{2})(?=\s)'), (m) {
      day = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    });
  }
  if (day == null) {
    final mon = _months.join('|');
    text = cut(RegExp('(?<=\\s)(\\d{1,2})\\s+($mon)[a-z]*(?=\\s)', caseSensitive: false), (m) {
      day = _nextDate(today, _months.indexOf(m.group(2)!.toLowerCase().substring(0, 3)) + 1, int.parse(m.group(1)!));
    });
    if (day == null) {
      text = cut(RegExp('(?<=\\s)($mon)[a-z]*\\s+(\\d{1,2})(?=\\s)', caseSensitive: false), (m) {
        day = _nextDate(today, _months.indexOf(m.group(1)!.toLowerCase().substring(0, 3)) + 1, int.parse(m.group(2)!));
      });
    }
  }
  if (day == null) {
    // Day first, as written in India: 28/10 is 28 October.
    text = cut(RegExp(r'(?<=\s)(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?(?=\s)'), (m) {
      final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        final y = m.group(3);
        day = y == null ? _nextDate(today, mo, d) : DateTime(y.length == 2 ? 2000 + int.parse(y) : int.parse(y), mo, d);
      }
    });
  }

  // Repeats: "every …" anywhere; a bare "daily" or "weekly" only as the
  // last word, so a title like "Weekly status update" keeps its word.
  Repeat? repeat;
  for (final (re, r) in [
    (RegExp(r'(?<=\s)every\s+week\s*days?(?=\s)', caseSensitive: false), Repeat.weekdays),
    (RegExp(r'(?<=\s)every\s+day(?=\s)', caseSensitive: false), Repeat.daily),
    (RegExp(r'(?<=\s)every\s+week(?=\s)', caseSensitive: false), Repeat.weekly),
    (RegExp(r'(?<=\s)every\s+month(?=\s)', caseSensitive: false), Repeat.monthly),
    (RegExp(r'(?<=\s)every\s+year(?=\s)', caseSensitive: false), Repeat.yearly),
    (RegExp(r'(?<=\s)daily\s*$', caseSensitive: false), Repeat.daily),
    (RegExp(r'(?<=\s)weekly\s*$', caseSensitive: false), Repeat.weekly),
    (RegExp(r'(?<=\s)monthly\s*$', caseSensitive: false), Repeat.monthly),
    (RegExp(r'(?<=\s)(yearly|annually)\s*$', caseSensitive: false), Repeat.yearly),
  ]) {
    if (repeat != null) break;
    text = cut(re, (_) => repeat = r);
  }

  if (day == null && hour != null) {
    final candidate = DateTime(today.year, today.month, today.day, hour!, minute!);
    day = candidate.isBefore(now) ? today.add(const Duration(days: 1)) : today;
  }

  Due? due;
  if (day != null) {
    due = hour == null ? Due(day!) : Due(DateTime(day!.year, day!.month, day!.day, hour!, minute ?? 0), hasTime: true);
  }

  final title = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return QuickAdd(title: title, space: space, priority: priority, urgent: urgent, due: due, repeat: repeat, people: people);
}

DateTime _nextDate(DateTime today, int month, int dayOfMonth) {
  var d = DateTime(today.year, month, dayOfMonth);
  if (d.isBefore(today)) d = DateTime(today.year + 1, month, dayOfMonth);
  return d;
}
