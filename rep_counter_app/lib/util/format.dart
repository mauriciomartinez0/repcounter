// Spanish number and date formatting, as the designs write them:
// "3.660 kg", "0,46 m/s", "Dom 4 oct", "1:24".

const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

/// Thousands with a dot, decimals with a comma, no trailing ",0".
String formatNumber(num value, {int decimals = 0}) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  var parts = fixed.split('.');
  var whole = parts[0];
  var fraction = parts.length > 1 ? parts[1] : '';
  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write('.');
    buffer.write(whole[i]);
  }
  final sign = negative ? '−' : '';
  return fraction.isEmpty ? '$sign$buffer' : '$sign$buffer,$fraction';
}

/// "+180", "−3", "+0,07".
String formatSigned(num value, {int decimals = 0}) {
  final text = formatNumber(value, decimals: decimals);
  return value > 0 ? '+$text' : text;
}

/// Weight with up to one decimal ("60", "52,5").
String formatKg(double kg) => formatNumber(kg, decimals: 1);

/// Velocity always with two decimals ("0,46").
String formatVelocity(double v) =>
    v.toStringAsFixed(2).replaceAll('.', ',');

/// "1:24", "12:05".
String formatClock(int totalSeconds) {
  final s = totalSeconds.abs();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "Dom 4 oct".
String formatDay(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// "dom 27 sep".
String formatDayLower(DateTime d) => formatDay(d).toLowerCase();

/// "4 oct".
String formatShortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// "4 × 8 · 60 kg", "3 × 12 · corporal".
String formatSetsSummary(int sets, int reps, double? kg,
        {String bodyweight = 'corporal'}) =>
    '$sets × $reps · ${kg == null ? bodyweight : '${formatKg(kg)} kg'}';

String plural(int n, String one, String many) => n == 1 ? one : many;
