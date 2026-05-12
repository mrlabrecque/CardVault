/// Trailing print-run suffix on parallel labels (e.g. `Red /149` → `Red`).
/// Matches [stripSerialSuffix] in `supabase/functions/_shared/cardhedge_text.ts`.
String stripCatalogParallelSerialSuffix(String raw) {
  return raw.replaceAll(RegExp(r'\s*/\d+$'), '').trim();
}

/// Builds a single natural-language line for CardHedge `match_card`, aligned
/// with the sold-comps eBay query shape in `comps_master_refresh.ts`
/// (`buildCardEbayQuery`).
String buildCardHedgeMatchQuery({
  required int? year,
  required String? releaseName,
  required String? setName,
  required String player,
  required String? cardNumber,
  required String parallelName,
  required bool isAuto,
  required bool isPatch,
  required bool isRookie,
  required int? serialMax,
}) {
  final parts = <String>[
    if (year != null) '$year',
    if (releaseName != null && releaseName.trim().isNotEmpty) releaseName.trim(),
  ];

  final setLabel = (setName ?? '').trim();
  final setLower = setLabel.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final releaseLower = (releaseName ?? '').toLowerCase();
  // Match edge `buildCardHedgeSearchSetLabel`: "Base Set" is our DB checklist label, not a CardHedge product token.
  final isCanonicalBaseSet =
      setLower.isEmpty || setLower == 'base' || setLower == 'base set';
  if (setLabel.isNotEmpty &&
      !isCanonicalBaseSet &&
      !releaseLower.contains(setLabel.toLowerCase())) {
    parts.add(setLabel);
  }

  parts.add(player.trim());
  final num = (cardNumber ?? '').trim();
  if (num.isNotEmpty) {
    parts.add('#$num');
  }

  final attrs = <String>[];
  final parallelLabel = stripCatalogParallelSerialSuffix(parallelName);
  if (parallelLabel.isNotEmpty && parallelLabel.toLowerCase() != 'base') {
    attrs.add(parallelLabel);
  }
  if (isAuto) attrs.add('Auto');
  if (isPatch) attrs.add('Patch');
  if (serialMax != null && serialMax > 0) attrs.add('/$serialMax');
  if (isRookie) attrs.add('RC');

  final joined = [...parts, ...attrs].where((s) => s.isNotEmpty).join(' ');
  if (parallelLabel.isNotEmpty && parallelLabel.toLowerCase() != 'base') {
    // Anchor the LLM on the exact parallel; CardHedge can still return Base
    // with high confidence if this is buried earlier in the string.
    return '$joined | parallel: $parallelLabel (not base)';
  }
  return joined;
}

/// CardHedge categories are title case (e.g. `Basketball`). Best-effort from
/// our [sport] release field.
String? cardHedgeCategoryFromSport(String? sport) {
  final s = sport?.trim();
  if (s == null || s.isEmpty) return null;
  return s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

/// CardHedge `category` values we keep for Portfolio Movers (matches catalog sports).
/// Top-movers only accepts one `category` query string, not an array — we request
/// uncategorized then drop rows outside this set in one round-trip.
const Set<String> cardHedgeMoverCategoryAllowlist = {
  'Baseball',
  'Basketball',
  'Football',
  'Soccer',
  'Hockey',
};

/// Returns canonical category label if [category] is in [cardHedgeMoverCategoryAllowlist].
String? canonicalCardHedgeMoverCategory(String? category) {
  final c = category?.trim().toLowerCase() ?? '';
  if (c.isEmpty) return null;
  for (final a in cardHedgeMoverCategoryAllowlist) {
    if (a.toLowerCase() == c) return a;
  }
  return null;
}

/// Maps Portfolio Movers sport chips to CardHedge `category` on `/v1/cards/top-movers`.
String? cardHedgeCategoryForMoversFilter(String? uiSport) {
  switch (uiSport) {
    case 'NBA':
      return 'Basketball';
    case 'NFL':
      return 'Football';
    case 'MLB':
      return 'Baseball';
    case 'NHL':
      return 'Hockey';
    case 'Soccer':
      return 'Soccer';
    default:
      return null;
  }
}
