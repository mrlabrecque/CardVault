import 'package:intl/intl.dart';

final NumberFormat _usdCurrency = NumberFormat.currency(
  locale: 'en_US',
  symbol: r'$',
  decimalDigits: 2,
);

/// Always formats as USD with grouping (e.g. `$1,234.56`).
String formatUsd(num amount) => _usdCurrency.format(amount);

/// Use on list surfaces when a missing or zero value should read as [naLabel].
String formatUsdOrNa(
  double? amount, {
  bool zeroIsNa = true,
  String naLabel = 'N/A',
}) {
  if (amount == null) return naLabel;
  if (zeroIsNa && amount == 0) return naLabel;
  return formatUsd(amount);
}

/// P/L and deltas: `+$1,234.56` / `-$1,234.56`; zero is `$0.00`.
String formatUsdSigned(num amount) {
  if (amount > 0) return '+${formatUsd(amount)}';
  if (amount < 0) return '-${formatUsd(amount.abs())}';
  return formatUsd(amount);
}

/// Compact USD for chart axes (full [formatUsd] under 1k, otherwise `$12k` / `$1.2k`).
String formatUsdCompact(num amount) {
  final negative = amount < 0;
  final a = amount.abs();
  late String body;
  if (a >= 1000) {
    final k = a / 1000;
    final digits = k >= 10 ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
    body = '\$${digits}k';
  } else {
    body = formatUsd(a);
  }
  return negative ? '-$body' : body;
}
