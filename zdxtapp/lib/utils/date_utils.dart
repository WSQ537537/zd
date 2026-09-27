/// 计算 date 所在 ISO 周的 ISO 年与周号（标准 ISO 8601 算法，正确处理跨年周与 53 周年）
List<int> _isoYearAndWeek(DateTime date) {
  // 该日期所在周的周一（Dart 中 weekday: 周一=1, 周日=7）
  final monday = DateTime(date.year, date.month, date.day).subtract(
    Duration(days: date.weekday - 1),
  );
  // 该周一所在周的 1 月 4 日一定落在该 ISO 年内
  final jan4 = DateTime(monday.year, 1, 4);
  final jan4Monday = DateTime(jan4.year, jan4.month, jan4.day).subtract(
    Duration(days: jan4.weekday - 1),
  );
  final weekNum = ((monday.difference(jan4Monday).inDays) ~/ 7) + 1;
  return [monday.year, weekNum];
}

/// 将 DateTime 转换为 ISO 8601 周字符串（如 "2026-W35"，跨年周时 ISO 年可能 != 自然年）
String getIsoWeekStr(DateTime date) {
  final List<int> yw = _isoYearAndWeek(date);
  return '${yw[0]}-W${yw[1].toString().padLeft(2, '0')}';
}

/// 将 ISO 周字符串（如 "2026-W35"）转换为该周的周一日期（yyyy-MM-dd）
String? isoWeekToMonday(String weekStr) {
  final m = RegExp(r'^(\d{4})-W(\d{1,2})$').firstMatch(weekStr);
  if (m == null) return null;
  final isoYear = int.parse(m.group(1)!);
  final weekNum = int.parse(m.group(2)!);
  // ISO 年 jan4 的所在周一作为基准，第 1 周周一 = jan4Monday，第 n 周周一 = +（n-1）*7 天
  final jan4 = DateTime(isoYear, 1, 4);
  final jan4Monday = DateTime(jan4.year, jan4.month, jan4.day)
      .subtract(Duration(days: jan4.weekday - 1));
  final monday = jan4Monday.add(Duration(days: (weekNum - 1) * 7));
  return monday.toIso8601String().split('T')[0];
}
