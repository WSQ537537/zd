import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/date_utils.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  // 绑定学生列表（独立于学习进度数据）
  List<Map<String, String>> boundStudents = [];
  // 学习进度数据（按选中范围/周查询结果）
  List<dynamic> userProgressList = [];
  bool progressLoading = true;
  // 当前选中的学生索引（基于 boundStudents）
  int _selectedStudentIndex = 0;
  bool hasStartedLoading = false;

  bool hasBoundStudents = false;
  final String baseUrl = Config.baseUrl;

  // 标记任务时间范围数据是否已取到（未取到前不渲染“未设定任务时间范围”占位）
  bool taskTimeRangesLoaded = false;
  // 第二段：时间范围 + 周选择
  List<dynamic> taskTimeRanges = [];
  String? selectedRangeId;
  List<dynamic> rangeWeeks = [];
  String? selectedWeekStr;
  // 标记周选择是否为手动触发（true=手动，false/null=联动）
  bool _isWeekUserSelected = false;

  @override
  void initState() {
    super.initState();
    checkAndLoad();
  }

  Future<void> checkAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfo = prefs.getString("userInfo");
    if (userInfo == null) {
      debugPrint('[Study] checkAndLoad: userInfo=null，未登录');
      setState(() => progressLoading = false);
      return;
    }
    final parentAccount = jsonDecode(userInfo)["account"] ?? "";
    debugPrint('[Study] checkAndLoad: parentAccount=$parentAccount');

    try {
      setState(() => hasStartedLoading = true);
      final bindRes = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "getParentBoundStudents", "parentAccount": parentAccount}),
      )).body);
      final bindData = bindRes;
      if (bindData["success"] == true) {
        final students = bindData["data"] as List? ?? [];
        debugPrint('[Study] checkAndLoad: getParentBoundStudents success, students count=${students.length}, data=$students');
        // 提取 account 和 remark，存入独立列表供学生选择器使用
        final boundList = students
            .map((s) => {"account": s["account"] as String? ?? "", "remark": s["remark"] as String? ?? ""})
            .toList();
        setState(() {
          boundStudents = boundList;
          hasBoundStudents = boundList.isNotEmpty;
        });

        if (hasBoundStudents) {
          // 🔥 不调用 searchProgress 在这里：由 loadTimeRanges 内部负责触发
          await loadTimeRanges();
        } else {
          // 无绑定学生：范围数据永远不会被加载，直接置位使卡片按“未设定范围”展示
          setState(() {
            taskTimeRangesLoaded = true;
            progressLoading = false;
          });

        }
      } else {
        setState(() => progressLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => progressLoading = false);

    }
  }

  Future<void> loadTimeRanges() async {
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getTimeRanges'}),
      )).body);
      final data = res;
      if (data['success'] == true) {
        final ranges = data['data'] as List? ?? [];
        setState(() {
          taskTimeRanges = ranges;
          taskTimeRangesLoaded = true;
        });
        _selectCurrentRange(ranges);
      } else {
        setState(() {
          taskTimeRanges = [];
          taskTimeRangesLoaded = true;
          progressLoading = false;

        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          taskTimeRangesLoaded = true;
          progressLoading = false;
        });
      }
    }
  }

  /// 自动选择当前时间范围
  /// 若当前不在任何范围内：回退到第一个范围（与 admin 一致）
  void _selectCurrentRange(List<dynamic> ranges) {
    if (ranges.isEmpty) {
      setState(() => progressLoading = false);
      return;
    }
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    String? currentRangeId;
    for (final r in ranges) {
      final startDate = r['startDate'] as String? ?? '';
      final endDate = r['endDate'] as String? ?? '';
      if (startDate.isNotEmpty && endDate.isNotEmpty &&
          todayStr.compareTo(startDate) >= 0 && todayStr.compareTo(endDate) <= 0) {
        currentRangeId = r['_id'] as String?;
        break;
      }
    }
    // 回退到第一个范围（确保始终有选中项）
    currentRangeId ??= ranges.isNotEmpty ? ranges[0]['_id'] as String? : null;
    if (currentRangeId != null) {
      setState(() {
        selectedRangeId = currentRangeId;
        _isWeekUserSelected = false;
      });
      _loadRangeWeeks(currentRangeId);
    } else {
      setState(() {
        selectedRangeId = null;
        selectedWeekStr = null;
        rangeWeeks = [];
        progressLoading = false;
        _isWeekUserSelected = false;
      });
    }
  }

  Future<void> _loadRangeWeeks(String rangeId) async {
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getRangeWeeks', 'rangeId': rangeId}),
      )).body);
      final data = res;
      if (data['success'] == true) {
        final weeks = data['data'] as List? ?? [];
        setState(() {
          rangeWeeks = weeks;
        });
        if (!_isWeekUserSelected) {
          _selectCurrentWeek(weeks, isInRange: _isInTimeRange());
        } else if (weeks.isNotEmpty && selectedWeekStr != null) {
          // 用户手动选中了周且周列表非空时，清空旧数据重新拉取
          setState(() { progressLoading = true; userProgressList = []; });
          _searchProgress();
        } else {
          // 用户手动选中了周但周列表为空，清除加载状态，避免灰屏
          setState(() { selectedWeekStr = null; progressLoading = false; userProgressList = []; });
        }
      } else {
        setState(() => progressLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => progressLoading = false);
    }
  }

  void _selectCurrentWeek(List<dynamic> weeks, {bool isInRange = false}) {
    if (weeks.isEmpty) {
      setState(() {
        selectedWeekStr = null;
        progressLoading = false;
        userProgressList = [];
        _isWeekUserSelected = false;
      });
      return;
    }
    final now = DateTime.now();
    final currentWeekStr = getIsoWeekStr(now);
    final todayStr = now.toIso8601String().split('T')[0];
    debugPrint('[Study] _selectCurrentWeek: now=$now, getIsoWeekStr(now)=$currentWeekStr, isInRange=$isInRange');
    debugPrint('[Study] _selectCurrentWeek: rangeWeeks available: ${weeks.map((w) => w['weekStr']).toList()}');
    String? matchedWeekStr;
    // 优先：若范围包含今天，精确匹配当前 ISO 周
    if (isInRange) {
      for (final week in weeks) {
        if (week['weekStr'] == currentWeekStr) {
          matchedWeekStr = week['weekStr'];
          break;
        }
      }
    }
    // 其次：找最近的过去周（周一 <= 今天），避免选到未来周导致进度为0
    if (matchedWeekStr == null) {
      for (final w in weeks) {
        final ws = w['weekStr'] as String?;
        if (ws != null) {
          final mondayStr = isoWeekToMonday(ws);
          if (mondayStr != null && mondayStr.compareTo(todayStr) <= 0) {
            matchedWeekStr = ws;
          }
        }
      }
    }
    matchedWeekStr ??= weeks.first['weekStr'] as String;
    debugPrint('[Study] _selectCurrentWeek: auto-selected weekStr=$matchedWeekStr (matched=${matchedWeekStr == currentWeekStr ? "yes" : "no, fallback"})');
    setState(() {
      selectedWeekStr = matchedWeekStr;
      progressLoading = true;
      userProgressList = [];
    });
    _searchProgress();
  }

  Future<void> _searchProgress() async {
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoStr = prefs.getString("userInfo");
      if (userInfoStr == null) {
        if (!mounted) return;
        setState(() => progressLoading = false);
        return;
      }
      setState(() => progressLoading = true);

      final userInfo = jsonDecode(userInfoStr);
      final parentAccount = userInfo["account"] ?? "";

      String? startDate, endDate;
      if (selectedRangeId != null && taskTimeRanges.isNotEmpty) {
        for (final r in taskTimeRanges) {
          if (r['_id'] == selectedRangeId) {
            startDate = r['startDate'];
            endDate = r['endDate'];
            break;
          }
        }
      }

      final currentStudentAccount = boundStudents.isNotEmpty
          ? boundStudents[_selectedStudentIndex]['account'] ?? ''
          : '';

      debugPrint('[Study] _searchProgress: parentAccount=$parentAccount, studentAccount=$currentStudentAccount, selectedRangeId=$selectedRangeId, selectedWeekStr=$selectedWeekStr, startDate=$startDate, endDate=$endDate');
      debugPrint('[Study] _searchProgress: boundStudents count=${boundStudents.length}, taskTimeRanges count=${taskTimeRanges.length}');

      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'action': 'searchProgress',
          'parentAccount': parentAccount,
          'studentAccount': currentStudentAccount,
          'startDate': startDate,
          'endDate': endDate,
          'rangeId': selectedRangeId,
          'weekStr': selectedWeekStr,
        }),
      )).body);

      final data = res;
      debugPrint('[Study] searchProgress response: $data, weekStr=$selectedWeekStr, student=$currentStudentAccount, range=$selectedRangeId');
      if (data['success'] == true) {
        final rawData = data['data'];
        debugPrint('[Study] searchProgress raw data type=${rawData?.runtimeType}, value=$rawData');
        debugPrint('[Study] rawData type=${rawData.runtimeType}, length=${rawData is List ? (rawData).length : "N/A"}');
        if (rawData is List) {
          for (int i = 0; i < (rawData).length; i++) {
            final item = rawData[i] as Map?;
            final weekData = (item?['weekData'] as List?) ?? <dynamic>[];
            final weekDataText = weekData
                .map((d) => (d as Map?)?.entries.map((entry) => '${entry.key}:${entry.value}').join(', '))
                .toList();
            debugPrint('[Study]   entry[$i]: name=${item?['name']}, weekData=$weekDataText');
          }
          setState(() { userProgressList = rawData; progressLoading = false; });
        } else if (rawData is Map) {
          final entry = rawData[currentStudentAccount];
          if (entry != null) {
            setState(() { userProgressList = [entry]; progressLoading = false; });
          } else {
            setState(() { userProgressList = []; progressLoading = false; });
          }
        } else {
          setState(() { userProgressList = []; progressLoading = false; });
        }
      } else {
        if (mounted) setState(() { userProgressList = []; progressLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { userProgressList = []; progressLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 8),
              child: Text("学习记录中心",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),

            ),
            // 整体卡片
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                clipBehavior: Clip.antiAlias,
                // 仅"首次加载且学生列表尚未返回"才显示整卡 loading；
                // 学生列表返回后框架（一、二段）常驻，后续切换学生/范围/周的加载
                // 只由第三段 _ProgressSection 内部展示（需求5：一、二段不重绘）
                child: (progressLoading && boundStudents.isEmpty)
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1), strokeWidth: 3))
                    : hasBoundStudents == false
                        ? const Center(child: Text("暂无绑定学生，请前往我的-设置页面绑定",
                            style: TextStyle(color: Color.fromARGB(179, 0, 0, 0))))
                        : _buildCardContent(),
              ),
            ),
            // 底部安全留白（紧贴功能栏上边界）
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCardContent() {
    // 情况⓪：任务时间范围数据尚未取到 → 持续显示加载指示，避免提前渲染“未设定任务时间范围”占位
    if (!taskTimeRangesLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0D47A1), strokeWidth: 3),
      );
    }

    // 情况①：无任务时间范围 → 第二段置灰，第三段提示无法查看
    if (taskTimeRanges.isEmpty) {
      return _buildCardWithEmptyRange();
    }

    // 情况②：有任务时间范围，当前是否在其中
    final isInRange = _isInTimeRange();
    return Column(
      children: [
        // ===== 第一段：学生选择（RepaintBoundary 防止重绘）=====
        RepaintBoundary(
          child: _buildStudentSelector(),
        ),
        const Divider(height: 1, color: Color(0xFFE0E0E0)),

        // ===== 第二段：时间范围 + 周选择（RepaintBoundary 防止重绘）=====
        RepaintBoundary(
          child: _buildTimeRangeRow(isInRange),
        ),
        const Divider(height: 1, color: Color(0xFFE0E0E0)),

        // ===== 第三段：周一至周日数据卡片（独立 StatefulWidget，内部管理展开状态）=====
        Expanded(
          child: _ProgressSection(
            progressLoading: progressLoading,
            userProgressList: userProgressList,
            studentAccount: boundStudents.isNotEmpty ? boundStudents[_selectedStudentIndex]['account'] : null,
            selectedWeekStr: selectedWeekStr,
            rangeWeeks: rangeWeeks,
            isInRange: isInRange,
            onRefresh: () => _searchProgress(),
          ),
        ),
      ],
    );
  }

  /// 无任务时间范围时的卡片：第二段置灰不可点，第三段提示暂无范围
  Widget _buildCardWithEmptyRange() {
    return Column(
      children: [
        // 第一段：学生选择
        RepaintBoundary(child: _buildStudentSelector()),
        const Divider(height: 1, color: Color(0xFFE0E0E0)),
        // 第二段：置灰不可点击
        RepaintBoundary(child: _buildTimeRangeRow(false)),
        const Divider(height: 1, color: Color(0xFFE0E0E0)),
        // 第三段：暂无任务时间范围，无法查看
        const Expanded(
          child: Center(child: Text("暂无任务时间范围，无法查看", style: TextStyle(color: Colors.grey))),
        ),
      ],
    );
  }

  /// 判断是否有任何时间范围包含当前日期（用于控制第三段是否展示数据视图）
  /// 注意：不在任务范围内时仍可手动选择范围/周查看历史数据，只有完全无范围时才锁定
  bool _isInTimeRange() {
    if (taskTimeRanges.isEmpty) return false;
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    for (final r in taskTimeRanges) {
      final startDate = r['startDate'] as String? ?? '';
      final endDate = r['endDate'] as String? ?? '';
      if (startDate.isNotEmpty && endDate.isNotEmpty &&
          todayStr.compareTo(startDate) >= 0 && todayStr.compareTo(endDate) <= 0) {
        return true;
      }
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 第一段：学生选择器（使用独立的 boundStudents 列表）
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildStudentSelector() {
    return Container(
      height: 56,
      color: const Color(0xFFFAFAFA),
      child: boundStudents.isEmpty
          ? const Center(child: Text("暂无学生数据", style: TextStyle(color: Colors.grey, fontSize: 13)))
          : ListView.builder(
              primary: false,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: boundStudents.length,
              itemBuilder: (ctx, i) {
                final student = boundStudents[i];
                final account = student['account'] as String;
                final remark = student['remark'] as String;
                final isSelected = i == _selectedStudentIndex;
                final offsetKey = ValueKey(account);
                return _StudentChip(
                  key: offsetKey,
                  account: account,
                  remark: remark,
                  isSelected: isSelected,
                  onTap: () => _switchStudent(i),
                );
              },
            ),
    );
  }

  void _switchStudent(int index) {
    setState(() {
      _selectedStudentIndex = index;
      // 切换学生时：清空范围手动选择、清空周手动选择
      selectedRangeId = null;
      _isWeekUserSelected = false;
      selectedWeekStr = null;
      progressLoading = true;
    });
    // 重新联动选中当前时间范围及当前周
    _selectCurrentRange(taskTimeRanges);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 第二段：时间范围 + 周选择（2:1 比例）
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildTimeRangeRow(bool isInRange) {
    return Column(
      children: [
        // 提示文字：无范围时提示配置，不在范围内时提示可查看历史
        if (taskTimeRanges.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text('未设定任务时间范围，请前往管理端配置', style: const TextStyle(fontSize: 12, color: Color(0xFFBDBDBD))),
          )
        else if (!isInRange)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text('当前时间不在任务范围内，可查看历史数据', style: const TextStyle(fontSize: 12, color: Color(0xFFBDBDBD))),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: const Color(0xFFF8F9FA),
          child: Row(
            children: [
              // 时间范围选择（宽度 1/2）
              Expanded(
                child: _buildDropdown<String>(
                  value: selectedRangeId,
                  items: taskTimeRanges,
                  itemLabel: (r) => (r['name'] ?? r['_id']) as String,
                  hint: "任务范围",
                  valueGetter: (r) => r['_id'] as String?,
                  onChanged: (value) {
                    if (value == null) return;
                    // 切换范围时重置周联动状态
                    setState(() {
                      selectedRangeId = value;
                      _isWeekUserSelected = false;
                    });
                    _loadRangeWeeks(value);
                  },
                  isInRange: isInRange,
                ),
              ),
              const SizedBox(width: 8),
              // 周选择（宽度 1/2）
              Expanded(
                child: _buildDropdown<String>(
                  value: selectedWeekStr,
                  items: rangeWeeks,
                  itemLabel: (w) => (w['weekLabel'] ?? '') as String,
                  hint: "选择周",
                  valueGetter: (w) => w['weekStr'] as String?,
                  onChanged: (value) {
                    if (value == null) return;
                    // 手动选择周时锁定周选择，后续切换范围不覆盖
                    setState(() {
                      selectedWeekStr = value;
                      _isWeekUserSelected = true;
                    });
                    _searchProgress();
                  },
                  isInRange: isInRange,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required List<dynamic> items,
    required String Function(dynamic) itemLabel,
    required String hint,
    required ValueChanged<T?> onChanged,
    required bool isInRange,
    bool disabled = false,
    required T? Function(dynamic) valueGetter,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: disabled
            ? Colors.grey.shade200
            : (value != null)
                ? const Color(0xFF1890FF).withValues(alpha: 0.12)
                : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: disabled ? Colors.grey.shade300 : Colors.grey.shade300),
      ),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        hint: Text(hint, style: TextStyle(color: disabled ? Colors.grey.shade400 : Colors.grey.shade400, fontSize: 12)),
        dropdownColor: Colors.white,
        icon: Icon(Icons.arrow_drop_down, color: disabled ? Colors.grey : (value != null ? const Color(0xFF1890FF) : Colors.grey), size: 20),
        items: items.map((item) {
          final itemValue = valueGetter(item);
          return DropdownMenuItem<T>(
            value: itemValue,
            child: Text(
              itemLabel(item),
              style: TextStyle(
                color: (value == itemValue) ? const Color(0xFF1890FF) : Colors.black87,
                fontSize: 12,
              ),
            ),
          );
        }).toList(),
        onChanged: disabled ? null : onChanged,
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// 第三段独立 StatefulWidget：数据区域，切换学生/范围/周时不触发第一二段重绘
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressSection extends StatefulWidget {
  final bool progressLoading;
  final List<dynamic> userProgressList;
  final String? studentAccount;
  final String? selectedWeekStr;
  final List<dynamic> rangeWeeks;
  final bool isInRange;
  final VoidCallback onRefresh;

  const _ProgressSection({
    required this.progressLoading,
    required this.userProgressList,
    required this.studentAccount,
    required this.selectedWeekStr,
    required this.rangeWeeks,
    required this.isInRange,
    required this.onRefresh,
  });

  @override
  State<_ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends State<_ProgressSection> {
  /// 互斥展开：同一时刻仅允许一项展开（内部状态，不暴露给父组件）
  int? _expandedDayIndex;

  @override
  void didUpdateWidget(covariant _ProgressSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换学生 / 切换周 / 切换范围 时，全部收回卡片
    if (oldWidget.studentAccount != widget.studentAccount ||
        oldWidget.selectedWeekStr != widget.selectedWeekStr) {
      setState(() => _expandedDayIndex = null);
    }
  }

  void _toggleExpand(int dayIndex) {
    setState(() {
      if (_expandedDayIndex == dayIndex) {
        _expandedDayIndex = null; // 再次点击收起
      } else {
        _expandedDayIndex = dayIndex; // 互斥：自动收起旧项
      }
    });
  }

  /// 自适应展开方向：dayIndex >= 4 时向上展开（避免底部内容被截断）
  bool get _expandUpward => _expandedDayIndex != null && _expandedDayIndex! >= 4;

  static Widget _buildWeekCard(
    Map<String, dynamic> progress,
    String? selectedWeekStr,
    List<dynamic> rangeWeeks,
    int? expandedDayIndex,
    bool expandUpward,
    ValueChanged<int> onExpandToggle,
  ) {
    final weekData = List<dynamic>.from(progress['weekData'] ?? []);
    while (weekData.length < 7) {
      weekData.add(<String, dynamic>{'yw': 0, 'sx': 0, 'en': 0, 'ot': 0, 'ywTarget': 0, 'sxTarget': 0, 'enTarget': 0, 'otTarget': 0});
    }
    final todayStr = DateTime.now().toIso8601String().split('T')[0];

    // 从 rangeWeeks 中查找当前选中周的元数据
    Map<String, dynamic>? weekInfo;
    if (selectedWeekStr != null && rangeWeeks.isNotEmpty) {
      for (final w in rangeWeeks) {
        if (w['weekStr'] == selectedWeekStr) {
          weekInfo = w;
          break;
        }
      }
    }
    final isPartialWeek = weekInfo?['isPartialWeek'] == true;
    final mondayInRange = weekInfo?['mondayInRange'] as String? ?? '';
    final sundayInRange = weekInfo?['sundayInRange'] as String? ?? '';
    final mondayDate = weekInfo?['mondayDate'] as String? ?? '';

    // 判断该周是否"尚未到达"（最早展示日期严格晚于今天 → 整周置灰、不可交互）
    // 残缺周按实际裁剪范围 mondayInRange 判断；完整周按 mondayDate 判断
    // 只要最早展示日期 <= 今天（已到达当日或已过去），卡片即允许展开
    final weekStartForCompare = isPartialWeek ? mondayInRange : mondayDate;
    final isNotReachedWeek = weekStartForCompare.isNotEmpty &&
        DateTime.tryParse(weekStartForCompare) != null &&
        weekStartForCompare.compareTo(todayStr) > 0;

    // 计算残缺周中超出范围的日期索引（周一=0 … 周日=6）
    final Set<int> partialWeekOutOfRangeDays = {};
    if (isPartialWeek && mondayDate.isNotEmpty) {
      final monday = DateTime.tryParse(mondayDate);
      if (monday != null) {
        for (int wd = 0; wd < 7; wd++) {
          final dayStr = monday.add(Duration(days: wd)).toIso8601String().split('T')[0];
          if (dayStr.compareTo(mondayInRange) < 0 || dayStr.compareTo(sundayInRange) > 0) {
            partialWeekOutOfRangeDays.add(wd);
          }
        }
      }
    }

    // 判断某天是否为未来日期（完整周内今天之后的天数）
    bool isDayFuture(int dayIndex) {
      if (mondayDate.isEmpty) return true;
      final monday = DateTime.tryParse(mondayDate);
      if (monday == null) return true;
      final dayDate = monday.add(Duration(days: dayIndex));
      return dayDate.toIso8601String().split('T')[0].compareTo(todayStr) > 0;
    }

    final dayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isNotReachedWeek ? Colors.grey.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isNotReachedWeek ? Colors.grey.shade300 : Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isNotReachedWeek ? 0.02 : 0.04), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Column(
          children: List.generate(7, (dayIndex) {
            final dayDataRaw = weekData[dayIndex] as Map<String, dynamic>?;
            final dayData = dayDataRaw ?? <String, dynamic>{};
            final isOutOfRange = isPartialWeek && partialWeekOutOfRangeDays.contains(dayIndex);
            final isFuture = !isOutOfRange && isDayFuture(dayIndex);
            // 尚未到达的周内所有天均不可交互；残缺周中仅超范围天数不可交互
            final isInteractive = !isOutOfRange && !(isNotReachedWeek && !isFuture);
            final isRangeDay = !isOutOfRange && !isFuture && !isNotReachedWeek;
            final isExpanded = isInteractive && expandedDayIndex == dayIndex;

            final rowBgColor = isOutOfRange ? Colors.grey.shade100 : (isNotReachedWeek ? Colors.grey.shade100 : null);
            return Column(
              children: [
                InkWell(
                  onTap: (isOutOfRange || isNotReachedWeek) ? null : () => onExpandToggle(dayIndex),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: rowBgColor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isRangeDay ? const Color(0xFF1890FF).withValues(alpha: 0.1) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                dayNames[dayIndex].replaceAll('周', ''),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isRangeDay ? FontWeight.w600 : FontWeight.w400,
                                  color: isRangeDay ? const Color(0xFF1890FF) : Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dayNames[dayIndex],
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isRangeDay ? FontWeight.w600 : FontWeight.w400,
                                    color: isOutOfRange ? Colors.grey : (isRangeDay ? Colors.black87 : Colors.grey),
                                  ),
                                ),
                                if (isOutOfRange)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text('不在范围内', style: const TextStyle(fontSize: 12, color: Color(0xFFBDBDBD))),
                                  )
                                else if (isFuture)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text('还未开始', style: const TextStyle(fontSize: 12, color: Color(0xFFBDBDBD))),
                                  ),
                              ],
                            ),
                          ),
                          if (isRangeDay || (isFuture && !isNotReachedWeek))
                            Icon(
                              isExpanded ? Icons.expand_less : Icons.expand_more,
                              color: const Color(0xFF1890FF),
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 展开面板：根据 expandUpward 决定动画对齐方向
                if (isExpanded)
                  AnimatedCrossFade(
                    firstChild: isFuture
                        ? _buildFutureNotStartedPanel(dayNames[dayIndex])
                        : _buildExpandedPanel(dayData, dayNames[dayIndex], false),
                    secondChild: isFuture
                        ? _buildFutureNotStartedPanel(dayNames[dayIndex])
                        : _buildExpandedPanel(dayData, dayNames[dayIndex], true),
                    crossFadeState: expandUpward ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                    sizeCurve: Curves.easeInOut,
                  ),
                const Divider(height: 1, color: Color(0xFFF0F0F0)),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// 构建展开后的科目详情面板
  static Widget _buildExpandedPanel(Map<String, dynamic> dayData, String dayLabel, bool expandUpward) {
    final subjects = [
      {'name': '语文', 'key': 'yw', 'targetKey': 'ywTarget'},
      {'name': '数学', 'key': 'sx', 'targetKey': 'sxTarget'},
      {'name': '英语', 'key': 'en', 'targetKey': 'enTarget'},
      {'name': '其他', 'key': 'ot', 'targetKey': 'otTarget'},
    ];
    return Align(
      alignment: expandUpward ? Alignment.bottomCenter : Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: subjects.map((s) {
            // 防御性解析：后端返回 double（如 1.0167 分钟），用 double.tryParse 避免 int 截断为 0
            final minutes = double.tryParse((dayData[s['key'] as String] ?? 0).toString()) ?? 0.0;
            final target = double.tryParse((dayData[s['targetKey'] as String] ?? 0).toString()) ?? 0.0;
            // 进度百分比：上限锁定 100%，即使实际完成超过目标也只展示 100%
            final ratio = target > 0 ? (minutes / target).clamp(0.0, 1.0) : 0.0;
            final pct = target > 0 ? (ratio * 100).toStringAsFixed(0) : '—';
            final color = _getProgressColor(minutes, target);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      s['name']!,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF666666), fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: target > 0 ? ratio.clamp(0.0, 1.0) : 0.0,
                                  minHeight: 6,
                                  borderRadius: BorderRadius.circular(4),
                                  color: color,
                                  backgroundColor: Colors.grey.shade200,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "$pct%",
                              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "要求：${target.toStringAsFixed(1)} 分钟",
                              style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7)),
                            ),
                            Text(
                              "已学：${minutes.toStringAsFixed(1)} 分钟",
                              style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  static Color _getProgressColor(double minutes, double target) {
    // 无要求时长（学生自学）：灰色加深，区分非任务内容
    if (target <= 0) return Colors.grey.shade500;
    final ratio = minutes / target;
    if (ratio >= 1.0) return const Color(0xFF4CAF50);
    if (ratio >= 0.5) return const Color(0xFFFF9800);
    return const Color(0xFF1890FF);
  }

  /// 构建"还未开始"占位面板（用于完整周内未来的日期）
  static Widget _buildFutureNotStartedPanel(String dayLabel) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          '$dayLabel 还未开始',
          style: const TextStyle(fontSize: 13, color: Color(0xFFBDBDBD)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      // 🔍 诊断日志：打印当前状态，用于排查家长端数据不渲染问题
      debugPrint('[Study][ProgressSection] build called: progressLoading=${widget.progressLoading}, isInRange=${widget.isInRange}, selectedWeekStr=${widget.selectedWeekStr}, studentAccount=${widget.studentAccount}, userProgressList.length=${widget.userProgressList.length}');
      if (widget.userProgressList.isNotEmpty) {
        debugPrint('[Study][ProgressSection] userProgressList[0].name=${(widget.userProgressList[0] as Map?)?['name']}, weekData[0]=${(widget.userProgressList[0] as Map?)?['weekData']}');
      }
      if (widget.progressLoading) {
        return const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1), strokeWidth: 3));
      }
      if (!widget.isInRange && widget.selectedWeekStr == null) {
        return _buildEmptyState('不在任务时间范围内，暂无数据', '');
      }
      // 只展示当前选中学生的数据（后端返回字段为 name=学员账号, phone=备注）
      List<dynamic> filteredList = widget.studentAccount != null
          ? widget.userProgressList.where((p) => (p as Map<String, dynamic>)['name'] == widget.studentAccount).toList()
          : widget.userProgressList;
      debugPrint('[Study][ProgressSection] filteredList.length=${filteredList.length} (studentAccount=${widget.studentAccount}, listSize=${widget.userProgressList.length})');
      // 兜底：后端对无学习记录的学生不返回条目，此时用全 0 骨架渲染，
      // 保证第三段固定为周一至周日 7 天列表（需求6）
      if (filteredList.isEmpty && widget.selectedWeekStr != null) {
        filteredList = [
          <String, dynamic>{
            'name': widget.studentAccount ?? '',
            'phone': '',
            'weekData': List.generate(
              7,
              (_) => <String, dynamic>{'yw': 0, 'sx': 0, 'en': 0, 'ot': 0, 'ywTarget': 0, 'sxTarget': 0, 'enTarget': 0, 'otTarget': 0},
            ),
            '__zeroDataHint': true,
          }
        ];
      }
      if (filteredList.isEmpty) {
        return _buildEmptyState('暂无学习数据', widget.selectedWeekStr != null ? '该周暂无学习记录' : '请切换学生或范围查看');
      }
      return RefreshIndicator(
        onRefresh: () async => widget.onRefresh(),
        color: Color(0xFF0D47A1),
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: filteredList.length,
          itemBuilder: (ctx, idx) => _buildWeekCard(
            filteredList[idx] as Map<String, dynamic>,
            widget.selectedWeekStr,
            widget.rangeWeeks,
            _expandedDayIndex,
            _expandUpward,
            _toggleExpand,
          ),
        ),
      );
    } catch (e) {
      return const Center(child: Text("数据加载异常，请下拉刷新重试", style: TextStyle(color: Colors.grey)));
    }
  }

  static Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF666666))),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF999999))),
        ],
      ),
    );
  }
}

class _StudentChip extends StatefulWidget {
  final String account;
  final String remark;
  final bool isSelected;
  final VoidCallback onTap;
  const _StudentChip({
    super.key,
    required this.account,
    required this.remark,
    required this.isSelected,
    required this.onTap,
  });
  @override
  State<_StudentChip> createState() => _StudentChipState();
}

class _StudentChipState extends State<_StudentChip> {
  Offset? _pointerDownPos;
  static const double _tapDistanceThreshold = 10.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Listener(
        onPointerDown: (e) => _pointerDownPos = e.position,
        onPointerUp: (e) {
          if (_pointerDownPos != null) {
            final distance = (e.position - _pointerDownPos!).distance;
            if (distance < _tapDistanceThreshold) {
              widget.onTap();
            }
            _pointerDownPos = null;
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected ? const Color(0xFF1890FF) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.isSelected ? const Color(0xFF1890FF) : Colors.grey.shade300),
            boxShadow: widget.isSelected
                ? [BoxShadow(color: const Color(0xFF1890FF).withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.account, style: TextStyle(color: widget.isSelected ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(width: 4),
              Text("(${widget.remark})", style: TextStyle(color: widget.isSelected ? Colors.white70 : Colors.black54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

