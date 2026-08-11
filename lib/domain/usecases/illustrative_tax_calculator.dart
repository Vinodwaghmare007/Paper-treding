/// Pure arithmetic for the illustrative calculator on tax_education_screen.dart
/// — India's Section 115BBH flat 30% tax on gains from transferring a
/// Virtual Digital Asset (VDA), and Section 194S's 1% TDS withheld on the
/// full trade value (not just the gain) at the time of the transaction.
///
/// Deliberately takes two free-standing numbers a user types in, not
/// anything read from this app's own paper-trading P&L — see
/// tax_education_screen.dart's doc comment for why that separation is a
/// hard requirement, not a style choice: this app's trades are simulated,
/// so wiring this calculator to real trade data would misleadingly imply
/// a real tax liability exists where none does.
class IllustrativeTaxResult {
  const IllustrativeTaxResult({
    required this.hypotheticalProfit,
    required this.hypotheticalTradeValue,
    required this.taxOnGains,
    required this.tds,
  });

  final double hypotheticalProfit;
  final double hypotheticalTradeValue;
  final double taxOnGains;
  final double tds;

  double get totalCost => taxOnGains + tds;
  double get netAfterCosts => hypotheticalProfit - totalCost;
}

class IllustrativeTaxCalculator {
  /// Section 115BBH — flat rate, no slab, no deduction other than cost of
  /// acquisition, applied only to a net gain (a loss owes no tax under
  /// this section, though it also can't be set off elsewhere — see the
  /// misconceptions list on tax_education_screen.dart).
  static const double capitalGainsTaxRate = 0.30;

  /// Section 194S — withheld on the full consideration of the transfer,
  /// regardless of whether that transfer was itself a gain or a loss.
  static const double tdsRate = 0.01;

  static IllustrativeTaxResult calculate({
    required double hypotheticalProfit,
    required double hypotheticalTradeValue,
  }) {
    final taxOnGains = hypotheticalProfit > 0 ? hypotheticalProfit * capitalGainsTaxRate : 0.0;
    final tds = hypotheticalTradeValue > 0 ? hypotheticalTradeValue * tdsRate : 0.0;
    return IllustrativeTaxResult(
      hypotheticalProfit: hypotheticalProfit,
      hypotheticalTradeValue: hypotheticalTradeValue,
      taxOnGains: taxOnGains,
      tds: tds,
    );
  }
}
