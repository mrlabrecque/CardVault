/// User-facing strings for the external price guide integration.
///
/// Do not use vendor names (e.g. CardHedge) in UI copy — say **price guide** instead.
abstract final class PriceGuideCopy {
  PriceGuideCopy._();

  static const noPriceGuide = 'No price guide';
  static const priceGuideMatchIdLabel = 'Price guide';

  static const soldCompsUnavailableMessage =
      'Price guide values are not on file for this card yet, so sold comps and grade '
      'trends are hidden. Switch to For Sale to browse active eBay listings.';

  static const recentPricesUnavailableFootnote =
      'Price guide values are not on file for this card yet. N/A means we have not '
      'synced current values for this variant.';

  static const forSaleNeedsPriceGuide =
      'Link the price guide to compare listings to market value.';

  static const dealsVsPriceGuideTitle = 'Deals vs price guide';

  static const listingVsPriceGuide = 'Listing vs price guide';

  static String vsPriceGuideGrade(String grade) => 'vs $grade price guide';

  static const catalogNotLinkedValue =
      'This copy is not linked to the catalog, so the price guide is not available.';

  static const variantNotMatchedValue =
      'This variant is not matched to the price guide yet. Try again from the catalog card page.';

  static const marketDataWhenMatched =
      'Market data will appear once this variant is matched to the price guide.';

  static const debugLookupTitle = 'Price guide lookup (no link saved)';
  static const debugRequestJsonLabel = 'Request JSON (catalog lookup):';
  static const debugRetryLookup = 'Retry price guide lookup';
  static const debugNoResponse = 'No price guide response (search did not return)';

  static String priceGuideLastUpdated(String relative, String clock) =>
      'Price guide last updated $relative · $clock';

  static const noPriceGuideTimestamp =
      'No price guide timestamp yet — it updates when catalog values are fetched.';

  static String noPriceGuideSalesForGrade(String grade) =>
      'No price guide sales returned for $grade.';

  static String noPriceGuideSalesInRange(String grade) =>
      'No price guide sales in the selected date range at $grade.';
}
