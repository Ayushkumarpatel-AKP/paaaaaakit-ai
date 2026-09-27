/// Indian rupee (₹) formatting with Indian digit grouping (1,23,456.78).
///
/// The whole app prices in the Indian market, so every money value goes through
/// here instead of being hand-formatted per screen.
String formatInr(num value, {int decimals = 2}) {
  final isNegative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final intPart = parts.first;
  final decPart = parts.length > 1 ? parts[1] : '';

  String grouped;
  if (intPart.length <= 3) {
    grouped = intPart;
  } else {
    final last3 = intPart.substring(intPart.length - 3);
    var rest = intPart.substring(0, intPart.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    grouped = '${groups.join(',')},$last3';
  }

  final sign = isNegative ? '-' : '';
  return '₹$sign$grouped${decimals > 0 ? '.$decPart' : ''}';
}

/// Rupee amount plus a unit suffix, e.g. `₹1,350.00 / 1k units`.
String formatInrWithUnit(num value, String unit, {int decimals = 2}) =>
    '${formatInr(value, decimals: decimals)} $unit';
