double _asDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0.0;
}

double? _asNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

/// One (cohort, currency) row from `get_cohort_contribution_report(p_as_of)`.
///
/// `marginRatio` is NULL when earned revenue is zero; `hasTrainerCost` is
/// false when no non-cancelled trainer due ended by the as-of date.
class CohortContributionRow {
  final String cohortId;
  final String cohortName;
  final String courseName;
  final String currency;
  final double earnedRevenue;
  final double trainerCost;
  final double contributionMargin;
  final double? marginRatio;
  final int traineesCount;
  final bool hasTrainerCost;

  const CohortContributionRow({
    required this.cohortId,
    required this.cohortName,
    required this.courseName,
    required this.currency,
    required this.earnedRevenue,
    required this.trainerCost,
    required this.contributionMargin,
    required this.marginRatio,
    required this.traineesCount,
    required this.hasTrainerCost,
  });

  factory CohortContributionRow.fromMap(Map<String, dynamic> map) {
    return CohortContributionRow(
      cohortId: (map['cohort_id'] ?? '').toString(),
      cohortName: (map['cohort_name'] ?? '').toString(),
      courseName: (map['course_name'] ?? '').toString(),
      currency: (map['currency'] ?? '').toString(),
      earnedRevenue: _asDouble(map['earned_revenue']),
      trainerCost: _asDouble(map['trainer_cost']),
      contributionMargin: _asDouble(map['contribution_margin']),
      marginRatio: _asNullableDouble(map['margin_ratio']),
      traineesCount: _asInt(map['trainees_count']),
      hasTrainerCost: map['has_trainer_cost'] == true,
    );
  }
}

/// Per-currency aggregate. Never mix currencies: ratios are weighted as
/// Σmargin / Σearned within a single currency.
class CohortContributionSummary {
  final String currency;
  final int cohortsCount;
  final double earnedRevenue;
  final double trainerCost;
  final double contributionMargin;
  final int cohortsWithoutTrainerCost;

  const CohortContributionSummary({
    required this.currency,
    required this.cohortsCount,
    required this.earnedRevenue,
    required this.trainerCost,
    required this.contributionMargin,
    required this.cohortsWithoutTrainerCost,
  });

  factory CohortContributionSummary.fromRows(
    String currency,
    List<CohortContributionRow> rows,
  ) {
    var earned = 0.0;
    var cost = 0.0;
    var margin = 0.0;
    var missingCost = 0;
    for (final r in rows) {
      earned += r.earnedRevenue;
      cost += r.trainerCost;
      margin += r.contributionMargin;
      if (!r.hasTrainerCost) missingCost++;
    }
    return CohortContributionSummary(
      currency: currency,
      cohortsCount: rows.length,
      earnedRevenue: earned,
      trainerCost: cost,
      contributionMargin: margin,
      cohortsWithoutTrainerCost: missingCost,
    );
  }

  /// Weighted margin ratio; NULL when there is no earned revenue to weight by.
  double? get weightedMarginRatio =>
      earnedRevenue > 0 ? contributionMargin / earnedRevenue : null;
}
