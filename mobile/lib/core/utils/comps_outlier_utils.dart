import '../models/comp.dart';

/// Minimum sold listings before we drop one low + one high outlier.
const int kCompsOutlierTrimMinCount = 3;

/// Trimmed stats for sold comps: one lowest and one highest sale excluded when
/// [comps.length] >= [kCompsOutlierTrimMinCount] and prices vary.
class CompsOutlierStats {
  const CompsOutlierStats({
    required this.outlierIndices,
    required this.includedIndices,
  });

  final Set<int> outlierIndices;
  final List<int> includedIndices;

  bool isOutlier(int index) => outlierIndices.contains(index);

  bool get hasOutliers => outlierIndices.isNotEmpty;

  int get includedCount => includedIndices.length;

  static CompsOutlierStats fromComps(List<Comp> comps) {
    if (comps.isEmpty) {
      return const CompsOutlierStats(outlierIndices: {}, includedIndices: []);
    }
    if (comps.length < kCompsOutlierTrimMinCount) {
      return CompsOutlierStats(
        outlierIndices: const {},
        includedIndices: [for (var i = 0; i < comps.length; i++) i],
      );
    }

    var minIdx = 0;
    var maxIdx = 0;
    for (var i = 1; i < comps.length; i++) {
      if (comps[i].price < comps[minIdx].price) minIdx = i;
      if (comps[i].price > comps[maxIdx].price) maxIdx = i;
    }

    if (comps[minIdx].price == comps[maxIdx].price) {
      return CompsOutlierStats(
        outlierIndices: const {},
        includedIndices: [for (var i = 0; i < comps.length; i++) i],
      );
    }

    final outliers = <int>{minIdx};
    if (maxIdx != minIdx) outliers.add(maxIdx);

    final included = <int>[
      for (var i = 0; i < comps.length; i++)
        if (!outliers.contains(i)) i,
    ];

    return CompsOutlierStats(
      outlierIndices: outliers,
      includedIndices: included,
    );
  }

  static List<Comp> includedComps(List<Comp> comps) {
    final stats = fromComps(comps);
    return [for (final i in stats.includedIndices) comps[i]];
  }

  static double? averagePrice(List<Comp> comps) {
    final included = includedComps(comps);
    if (included.isEmpty) return null;
    var sum = 0.0;
    for (final c in included) {
      sum += c.price;
    }
    return sum / included.length;
  }

  static double? trimmedLow(List<Comp> comps) {
    final included = includedComps(comps);
    if (included.isEmpty) return null;
    return included.map((c) => c.price).reduce((a, b) => a < b ? a : b);
  }

  static double? trimmedHigh(List<Comp> comps) {
    final included = includedComps(comps);
    if (included.isEmpty) return null;
    return included.map((c) => c.price).reduce((a, b) => a > b ? a : b);
  }
}
