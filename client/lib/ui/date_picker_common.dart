/// Shared helpers for the timetable date picker (day rail + month sheet).

const List<String> kWeekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

const List<String> kMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Number of classes on a calendar day (drives the dots).
typedef ClassCountOf = int Function(DateTime day);

/// Strips the time (and any UTC flag) so days compare and index safely.
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole calendar days from [a] to [b], immune to DST shifts.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

int monthIndex(DateTime d) => d.year * 12 + (d.month - 1);

DateTime monthFromIndex(int index) => DateTime(index ~/ 12, index % 12 + 1);

String monthYearLabel(DateTime d) => '${kMonthNames[d.month - 1]} ${d.year}';

String classCountLabel(int n) =>
    n == 0 ? 'no classes' : (n == 1 ? '1 class' : '$n classes');

/// Screen-reader label, e.g. "Friday 20 November, 2 classes".
String dayLabel(DateTime d, {required int classes, bool today = false}) =>
    '${kWeekdayNames[d.weekday - 1]} ${d.day} ${kMonthNames[d.month - 1]}'
    '${today ? ', today' : ''}, ${classCountLabel(classes)}';
