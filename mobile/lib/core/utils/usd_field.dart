import 'package:currency_text_input_formatter/currency_text_input_formatter.dart';
import 'package:flutter/services.dart';

/// Shared USD entry using [CurrencyTextInputFormatter]: users type **digits only**
/// (amount is entered in cents internally; the field shows grouped currency, e.g. `$40.00`).
///
/// One formatter instance per price [TextField] (holds internal formatting state).
CurrencyTextInputFormatter createUsdCurrencyInputFormatter({bool enableNegative = false}) =>
    CurrencyTextInputFormatter.simpleCurrency(
      locale: 'en_US',
      decimalDigits: 2,
      enableNegative: enableNegative,
    );

/// Initial text for fields using [createUsdCurrencyInputFormatter] (typed digit-by-digit as USD).
String formatUsdInputInitial(double? amount) {
  if (amount == null) return '';
  return createUsdCurrencyInputFormatter().formatDouble(amount);
}

/// Reads a formatted currency field (`$1,234.56`, grouping, spaces).
double? parseUsdInput(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  final cleaned = t.replaceAll(',', '').replaceAll(RegExp(r'[\$\s\u00a0]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

List<TextInputFormatter> usdCurrencyInputFormatters({bool enableNegative = false}) =>
    [createUsdCurrencyInputFormatter(enableNegative: enableNegative)];
