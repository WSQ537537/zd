import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/upload_progress.dart';
import '../../widgets/common_video_player.dart';
import '../../widgets/shimmer_loading.dart';
import 'package:zdxtapp/utils/ui_helpers.dart'; // 🔥 全局UI辅助工具
import '../../utils/date_utils.dart';

/// 将 DateTime 格式化为 yyyy-MM-dd
String _fmtDateStr(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$m-$dd';
}

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  final String baseUrl = Config.baseUrl;
  int mainTab = 1;

  final List<String> weekList = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  String selDay = '周一';
  Map<String, Map<String, String>> timeData = {};

  final List<String> tabs = ['语文', '数学', '英语', '其他'];
  final Map<String, String> subjectMap = {
    '语文': 'chinese',
    '数学': 'math',
    '英语': 'english',
    '其他': 'other'
  };
  int activeTab = 0; // 默认语文
  List<dynamic> videoList = [];
  bool isLoading = false;
  int openIndex = -1;
  int _videoPage = 1;
  bool _videoHasMore = true;
  bool _videoLoadingMore = false;
  int _videoLastLoadTime = 0; // 防抖：防止滚动事件重复触发
  final ScrollController _videoScrollController = ScrollController();
  String _currentVideoSubject = '';

  // 批量删除模式
  bool _batchDeleteMode = false;
  Set<String> _selectedVideoIds = {};
  bool _videoBatchClearing = false; // 是否处于"清除勾选"中间状态（再次取消则退出模式）
  bool _videoBatchDeleting = false;

  List<dynamic> batchList = [];
  bool showBatchPopup = false;
  int currentIndex = 0;
  int totalCount = 0;
  String currentVideoName = '';
  bool uploading = false;
  int uploadingIndex = 0;
  int uploadingTotal = 0;
  String uploadingName = '';
  double uploadProgress = 0;

  String searchKey = '';
  List<dynamic> userProgressList = [];
  bool progressLoading = false;
  int expandedUser = -1;
  Map<int, int> expandedWeek = {};

  // 🔥 搜索栏展开/收起状态
  bool isSearchExpanded = false;
  // 🔥 周偏移：0=本周, -1=上周, ..., -20=20周前
  int selectedWeekOffset = 0;
  // 🔥 搜索输入控制器
  late TextEditingController progressSearchController;

  // 🔥 任务时间范围管理
  List<dynamic> taskTimeRanges = [];
  String? selectedRangeId;
  // 🔥 进度查询页的时间范围+周选择器状态
  List<dynamic> progressRangeWeeks = [];
  String? progressSelectedWeekStr;
  // 🔥 周配置管理（新）
  List<dynamic> selectedRangeWeeks = [];
  String? selectedWeekStr;
  List<dynamic> currentWeekConfig = [];
  Map<int, Map<String, String>> weekEditorData = {};
  bool weekConfigLoading = false;
  // 周配置编辑器：按 (weekday, subject) 缓存 controller 和 focusNode，防止重建时失焦
  final Map<String, FocusNode> _weekInputFocusNodes = {};
  final Map<String, TextEditingController> _weekInputControllers = {};

  bool showOnlineVideoPopup = false;
  String onlineVideoUrl = '';
  String onlineVideoName = '';
  String biliParseUrl = '';

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    progressSearchController = TextEditingController();
    initTimeData();
    _videoScrollController.addListener(_onVideoScroll);
    _fetchVideoPage(1);
  }

  @override
  void dispose() {
    progressSearchController.dispose();
    _videoScrollController.removeListener(_onVideoScroll);
    _videoScrollController.dispose();
    for (final node in _weekInputFocusNodes.values) {
      node.dispose();
    }
    for (final ctrl in _weekInputControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void initTimeData() {
    setState(() {
      timeData = {
        '周一': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周二': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周三': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周四': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周五': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周六': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周日': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
      };
    });
  }

  Future<void> handleMainTabChange(int index) async {
    if (!mounted) return;
    setState(() => mainTab = index);
    if (index == 1) {
      setState(() {
        // 进入视频界面默认选中语文
        activeTab = 0;
        _currentVideoSubject = 'chinese';
        // 不立即清空列表，等 _fetchVideoPage 完成后替换
        openIndex = -1;
        _videoPage = 1;
        _videoHasMore = true;
        _videoLoadingMore = false;
        _videoLastLoadTime = 0;
      });
      if (_videoScrollController.hasClients) {
        _videoScrollController.jumpTo(0);
      }
      _fetchVideoPage(1);
    } else if (index == 0) {
      await loadTimeConfig();
      await loadTaskTimeRanges();
      await loadRangeWeeks();
    } else if (index == 2) {
      searchKey = '';
      await loadTaskTimeRanges();
      // 自动加载当前选中范围的周列表
      if (selectedRangeId != null) {
        await _loadProgressRangeWeeks(selectedRangeId!);
      }
      await searchProgress();
    }
  }

  Future<void> loadTimeConfig() async {
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getConfig'}),
      )).body);
      if (res['success'] == true) {
        final Map<String, Map<String, String>> newData = {};
        for (final day in weekList) {
          newData[day] = {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'};
        }

        final weekMap = {1: '周一', 2: '周二', 3: '周三', 4: '周四', 5: '周五', 6: '周六', 7: '周日'};
        for (final item in res['data'] ?? []) {
          final day = weekMap[item['weekday']];
          if (day != null) {
            newData[day] = {
              'yw': item['subjects']['chinese']?.toString() ?? '0',
              'sx': item['subjects']['math']?.toString() ?? '0',
              'en': item['subjects']['english']?.toString() ?? '0',
              'ot': item['subjects']['other']?.toString() ?? '0',
            };
          }
        }
        setState(() => timeData = newData);
      }
    } catch (e) {
      debugPrint('❌ loadTimeConfig异常: $e');
    }
  }

  Future<void> saveTimeConfig() async {
    try {
      final weekMap = {'周一': 1, '周二': 2, '周三': 3, '周四': 4, '周五': 5, '周六': 6, '周日': 7};
      final List<Map<String, dynamic>> weekConfig = [];

      for (final entry in timeData.entries) {
        final day = entry.key;
        final sub = entry.value;
        weekConfig.add({
          'weekday': weekMap[day],
          'subjects': {
            'chinese': int.tryParse(sub['yw'] ?? '0') ?? 0,
            'math': int.tryParse(sub['sx'] ?? '0') ?? 0,
            'english': int.tryParse(sub['en'] ?? '0') ?? 0,
            'other': int.tryParse(sub['ot'] ?? '0') ?? 0,
          }
        });
      }

      await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'setConfig', 'weekConfig': weekConfig}),
      )).body);
      await loadTimeConfig();
      if (mounted) {
        ToastUtil.show(context, '保存成功');
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.show(context, '保存失败');
      }
    }
  }

  // ====================== 任务时间范围管理 ======================

  Future<void> loadTaskTimeRanges() async {
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getTimeRanges'}),
      )).body);
      if (res['success'] == true) {
        setState(() {
          taskTimeRanges = res['data'] ?? [];
          // 自动选择当前时间所在的范围，或第一个范围
          if (selectedRangeId == null && taskTimeRanges.isNotEmpty) {
            final today = DateTime.now();
            final todayStr =
                '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
            for (final r in taskTimeRanges) {
              if (todayStr.compareTo(r['startDate'] ?? '') >= 0 &&
                  todayStr.compareTo(r['endDate'] ?? '') <= 0) {
                selectedRangeId = r['_id'];
                break;
              }
            }
            selectedRangeId ??= taskTimeRanges.isNotEmpty
                ? taskTimeRanges[0]['_id']
                : null;
          }
        });
      }
    } catch (e) {
      debugPrint('❌ loadTaskTimeRanges异常: $e');
    }
  }

  Future<void> saveTaskTimeRange(Map<String, dynamic> rangeData) async {
    final currentContext = context;
    try {
      final isEdit = rangeData['_id'] != null;
      final startDate = rangeData['startDate'] as String? ?? '';
      final endDate = rangeData['endDate'] as String? ?? '';
      final todayStr =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      final bool inRange =
          startDate.isNotEmpty && endDate.isNotEmpty &&
              todayStr.compareTo(startDate) >= 0 && todayStr.compareTo(endDate) <= 0;
      final body = <String, dynamic>{
        'action': isEdit ? 'updateTimeRange' : 'addTimeRange',
        ...rangeData,
        'inRange': inRange,
      };
      if (isEdit) {
        body['rangeId'] = rangeData['_id'];
      }
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      )).body);
      if (res['success'] == true) {
        await loadTaskTimeRanges();
        if (mounted) {
          if (mainTab == 0 && selectedRangeId != null) {
            await loadRangeWeeks();
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) ToastUtil.show(currentContext, isEdit ? '修改成功' : '新增成功');
          });
        }
      }
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ToastUtil.show(currentContext, '操作失败');
      });
    }
  }

  Future<void> deleteTaskTimeRange(String rangeId) async {
    final currentContext = context;
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'action': 'deleteTimeRange',
          'rangeId': rangeId,
        }),
      )).body);
      final data = res;
      if (data['success'] == true) {
        // 先确认是否删除了当前选中范围，再决定是否重置周状态
        final wasSelected = selectedRangeId == rangeId;
        if (wasSelected) {
          setState(() {
            selectedRangeId = null;
            selectedWeekStr = null;
            selectedRangeWeeks = [];
          });
        }
        await loadTaskTimeRanges();
        // 若当前在配置页且有选中范围，加载其周列表
        if (mounted && mainTab == 0 && selectedRangeId != null) {
          await loadRangeWeeks();
        }
        // 若删除的是当前进度页选中的范围，需重新加载进度周列表
        if (wasSelected && mounted && mainTab == 2 && selectedRangeId != null) {
          await _loadProgressRangeWeeks(selectedRangeId!);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ToastUtil.show(currentContext, '删除成功');
        });
      }
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ToastUtil.show(currentContext, '删除失败');
      });
    }
  }

  // ====================== 周配置管理（新） ======================

  /// 加载选定范围的所有周选项
  Future<void> loadRangeWeeks() async {
    if (selectedRangeId == null) return;
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getRangeWeeks', 'rangeId': selectedRangeId}),
      )).body);
      if (res['success'] == true) {
        final weeks = res['data'] as List? ?? [];
        setState(() => selectedRangeWeeks = weeks);

        // 默认选中当前周
        if (selectedWeekStr == null || !weeks.any((w) => w['weekStr'] == selectedWeekStr)) {
          // 优先精确匹配当前 ISO 周字符串
          final currentWeekStr = getIsoWeekStr(DateTime.now());
          String? bestWeek;
          for (final w in weeks) {
            if (w['weekStr'] == currentWeekStr) {
              bestWeek = w['weekStr'] as String?;
              break;
            }
          }
          // 如果当前周不在范围内，找周一 <= today 的最新一周
          if (bestWeek == null) {
            final todayStr = DateTime.now().toIso8601String().split('T')[0];
            for (final w in weeks) {
              final ws = w['weekStr'] as String?;
              if (ws != null) {
                final mondayStr = isoWeekToMonday(ws);
                if (mondayStr != null && mondayStr.compareTo(todayStr) <= 0) {
                  bestWeek = ws;
                }
              }
            }
          }
          selectedWeekStr = bestWeek ?? weeks.firstWhere(
            (w) => w['weekStr'] != null,
            orElse: () => {},
          )['weekStr'] as String?;
        }

        // 加载默认周配置
        if (selectedWeekStr != null) {
          await loadWeekConfig(selectedWeekStr!);
        }
      }
    } catch (e) {
      debugPrint('❌ loadRangeWeeks异常: $e');
    }
  }

  /// 加载指定周的配置
  Future<void> loadWeekConfig(String weekStr) async {
    if (selectedRangeId == null) return;
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getRangeWeekConfig', 'rangeId': selectedRangeId, 'weekStr': weekStr}),
      )).body);
      if (res['success'] == true) {
        final configList = res['data'] as List? ?? [];
        // 同步初始化编辑器数据
        final newData = <int, Map<String, String>>{};
        for (int wd = 1; wd <= 7; wd++) {
          newData[wd] = {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'};
        }
        for (final item in configList) {
          final wd = item['weekday'] as int?;
          final subjects = item['subjects'] as Map? ?? {};
          if (wd != null && newData.containsKey(wd)) {
            newData[wd]!['yw'] = (subjects['chinese'] ?? 0).toString();
            newData[wd]!['sx'] = (subjects['math'] ?? 0).toString();
            newData[wd]!['en'] = (subjects['english'] ?? 0).toString();
            newData[wd]!['ot'] = (subjects['other'] ?? 0).toString();
          }
        }
        setState(() {
          currentWeekConfig = configList;
          weekEditorData = newData;
        });
        // 同步更新缓存 controller，确保保存时读到最新数据
        for (int wd = 1; wd <= 7; wd++) {
          for (final key in ['yw', 'sx', 'en', 'ot']) {
            final cacheKey = '${wd}_$key';
            if (_weekInputControllers.containsKey(cacheKey)) {
              _weekInputControllers[cacheKey]!.text = newData[wd]![key] ?? '0';
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ loadWeekConfig异常: $e');
    }
  }

  /// 保存某周配置
  Future<void> saveWeekConfig(String weekStr, List<dynamic> config) async {
    if (selectedRangeId == null) return;
    setState(() => weekConfigLoading = true);
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'action': 'saveRangeWeekConfig',
          'rangeId': selectedRangeId,
          'weekStr': weekStr,
          'config': config,
        }),
      )).body);
      if (res['success'] == true) {
        if (mounted) ToastUtil.show(context, '保存成功');
        await loadWeekConfig(weekStr);
      } else {
        if (mounted) ToastUtil.show(context, '保存失败');
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, '保存失败');
    } finally {
      if (mounted) setState(() => weekConfigLoading = false);
    }
  }

  /// 显示"高级应用"配置弹窗
  Widget _buildRadioOption({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? const Color(0xFF1890FF) : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1890FF),
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showApplyToAllDialog() {
    if (selectedRangeId == null) return;

    final allController = TextEditingController();
    final chineseController = TextEditingController();
    final mathController = TextEditingController();
    final englishController = TextEditingController();
    final otherController = TextEditingController();

    bool mergeSubjects = true;
    bool applyToEachWeek = true;
    Set<int> selectedWeekdays = {1, 2, 3, 4, 5};
    String applyScope = 'all'; // 'all'=全部范围, 'custom'=自定义子范围
    DateTime? customStart;
    DateTime? customEnd;

    final dayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    // 获取当前任务时间范围的起止日期，用于限制自定义子范围
    final rangeItem = taskTimeRanges.firstWhere(
      (r) => r['_id'] == selectedRangeId,
      orElse: () => null,
    );
    final rangeStartDate = rangeItem != null ? DateTime.tryParse('${rangeItem['startDate']}T00:00:00') : null;
    final rangeEndDate = rangeItem != null ? DateTime.tryParse('${rangeItem['endDate']}T00:00:00') : null;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('高级应用', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 学科模式
                  const Text('学科模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRadioOption(
                          selected: mergeSubjects,
                          label: '合并学科',
                          onTap: () => setDialogState(() => mergeSubjects = true),
                        ),
                      ),
                      Expanded(
                        child: _buildRadioOption(
                          selected: !mergeSubjects,
                          label: '隔离学科',
                          onTap: () => setDialogState(() => mergeSubjects = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 合并学科：一个输入框
                  if (mergeSubjects) ...[
                    TextField(
                      controller: allController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '时长（分钟）',
                        hintText: '输入应用到所有学科的时长',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  // 隔离学科：四个输入框
                  if (!mergeSubjects) ...[
                    TextField(
                      controller: chineseController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '语文（分钟）', border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: mathController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '数学（分钟）', border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: englishController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '英语（分钟）', border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: otherController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '其他（分钟）', border: OutlineInputBorder(), isDense: true),
                    ),
                  ],
                  const Divider(height: 24),
                  // 应用范围
                  const Text('应用范围', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRadioOption(
                          selected: applyScope == 'all',
                          label: '全部',
                          onTap: () => setDialogState(() => applyScope = 'all'),
                        ),
                      ),
                      Expanded(
                        child: _buildRadioOption(
                          selected: applyScope == 'custom',
                          label: '自定义',
                          onTap: () => setDialogState(() => applyScope = 'custom'),
                        ),
                      ),
                    ],
                  ),
                  // 自定义子范围日期选择
                  if (applyScope == 'custom') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (rangeStartDate == null) return;
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: customStart ?? rangeStartDate,
                                firstDate: rangeStartDate,
                                lastDate: customEnd ?? rangeEndDate ?? rangeStartDate,
                                helpText: '选择子范围起始',
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  customStart = picked;
                                  if (customEnd != null && customEnd!.isBefore(picked)) {
                                    customEnd = picked;
                                  }
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.date_range, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    customStart != null ? _fmtDateStr(customStart!) : '选择开始日期',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (rangeEndDate == null) return;
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: customEnd ?? rangeEndDate,
                                firstDate: customStart ?? rangeStartDate ?? rangeEndDate,
                                lastDate: rangeEndDate,
                                helpText: '选择子范围结束',
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  customEnd = picked;
                                  if (customStart != null && customStart!.isAfter(picked)) {
                                    customStart = picked;
                                  }
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.date_range, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    customEnd != null ? _fmtDateStr(customEnd!) : '选择结束日期',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  // 应用方式
                  const Text('应用方式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  _buildRadioOption(
                    selected: applyToEachWeek,
                    label: applyScope == 'custom' ? '应用到每周（选择周几）' : '应用到每周（范围内所有周）',
                    onTap: () => setDialogState(() => applyToEachWeek = true),
                  ),
                  // 周几多选（仅"应用到每周"时显示）
                  if (applyToEachWeek) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: List.generate(7, (i) {
                        final wd = i + 1;
                        final selected = selectedWeekdays.contains(wd);
                        return FilterChip(
                          label: Text(dayNames[i], style: const TextStyle(fontSize: 12)),
                          selected: selected,
                          onSelected: (_) {
                            setDialogState(() {
                              if (selected) {
                                selectedWeekdays.remove(wd);
                              } else {
                                selectedWeekdays.add(wd);
                              }
                            });
                          },
                          padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }),
                      ),
                    ],
                    _buildRadioOption(
                      selected: !applyToEachWeek,
                      label: '应用到每一天（范围内所有日期）',
                      onTap: () => setDialogState(() => applyToEachWeek = false),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        applyScope == 'custom' ? '将应用到所选子范围内匹配的周/天' : '将应用到任务时间范围内的所有周',
                        style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _executeApplyToAll(
                  mergeSubjects: mergeSubjects,
                  allController: allController,
                  chineseController: chineseController,
                  mathController: mathController,
                  englishController: englishController,
                  otherController: otherController,
                  applyScope: applyScope,
                  customStart: customStart,
                  customEnd: customEnd,
                  applyToEachWeek: applyToEachWeek,
                  selectedWeekdays: selectedWeekdays,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: UIHelpers.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('确认应用'),
            ),
          ],
        ),
      ),
    );
  }

  /// 执行高级应用
  Future<void> _executeApplyToAll({
    required bool mergeSubjects,
    required TextEditingController allController,
    required TextEditingController chineseController,
    required TextEditingController mathController,
    required TextEditingController englishController,
    required TextEditingController otherController,
    required String applyScope,
    DateTime? customStart,
    DateTime? customEnd,
    required bool applyToEachWeek,
    required Set<int> selectedWeekdays,
  }) async {
    if (selectedRangeId == null) return;
    if (applyScope == 'custom' && (customStart == null || customEnd == null)) {
      ToastUtil.show(context, '请选择自定义起止日期');
      return;
    }
    if (applyScope == 'custom' && applyToEachWeek && selectedWeekdays.isEmpty) {
      ToastUtil.show(context, '请至少选择一个星期');
      return;
    }
    setState(() => weekConfigLoading = true);
    try {
      final values = mergeSubjects
          ? {'all': int.tryParse(allController.text)} // null=留空，保留原值
          : {
              'chinese': int.tryParse(chineseController.text),
              'math': int.tryParse(mathController.text),
              'english': int.tryParse(englishController.text),
              'other': int.tryParse(otherController.text),
            };
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'action': 'applyConfigToAll',
          'rangeId': selectedRangeId,
          'subjectMode': mergeSubjects ? 'all' : 'isolate',
          'values': values,
          'weekdays': selectedWeekdays.toList(),
          'applyMode': applyToEachWeek ? 'weekly' : 'daily',
          'subStart': applyScope == 'custom' ? _fmtDateStr(customStart!) : null,
          'subEnd': applyScope == 'custom' ? _fmtDateStr(customEnd!) : null,
        }),
      )).body);
      if (res['success'] == true) {
        if (mounted) ToastUtil.show(context, '已应用到全部周');
        await loadRangeWeeks();
      } else {
        if (mounted) ToastUtil.show(context, '应用失败: ${res['message'] ?? ''}');
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, '操作失败');
    } finally {
      if (mounted) setState(() => weekConfigLoading = false);
    }
  }

  /// 加载进度查询页的周列表（当范围改变时调用）
  Future<void> _loadProgressRangeWeeks(String rangeId) async {
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getRangeWeeks', 'rangeId': rangeId}),
      )).body);
      if (res['success'] == true) {
        final weeks = res['data'] as List? ?? [];
        // 默认选中当前周：优先精确匹配当前 ISO 周字符串
        String? defaultWeekStr;
        if (weeks.isNotEmpty) {
          final currentWeekStr = getIsoWeekStr(DateTime.now());
          // 精确匹配当前周
          for (final w in weeks) {
            if (w['weekStr'] == currentWeekStr) {
              defaultWeekStr = w['weekStr'] as String?;
              break;
            }
          }
          // 如果当前周不在范围内，找最近的过去周
          if (defaultWeekStr == null) {
            final todayStr = DateTime.now().toIso8601String().split('T')[0];
            for (final w in weeks) {
              final ws = w['weekStr'] as String?;
              if (ws != null) {
                final mondayStr = isoWeekToMonday(ws);
                if (mondayStr != null && mondayStr.compareTo(todayStr) <= 0) {
                  defaultWeekStr = ws;
                }
              }
            }
          }
          defaultWeekStr ??= weeks[0]['weekStr'] as String?;
        }
        setState(() {
          progressRangeWeeks = weeks;
          progressSelectedWeekStr = defaultWeekStr;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadProgressRangeWeeks异常: $e');
    }
  }

  void toggleVideoPlay(int idx) {
    setState(() {
      if (openIndex == idx) {
        openIndex = -1;
      } else {
        openIndex = idx;
      }
    });
  }

  Future<void> chooseVideos() async {
    try {
      final List<XFile> videos = await _picker.pickMultiVideo();
      if (videos.isEmpty) return;

      // 过滤视频格式，同时收集有效和无效的文件名提示
      final List<Map<String, dynamic>> validVideos = [];
      final List<String> rejectedNames = [];
      for (final XFile video in videos) {
        final String fileName = video.name.toLowerCase();
        if (!fileName.endsWith('.mp4') && !fileName.endsWith('.mov') &&
            !fileName.endsWith('.avi') && !fileName.endsWith('.mkv') &&
            !fileName.endsWith('.wmv') && !fileName.endsWith('.flv')) {
          rejectedNames.add(video.name);
          continue;
        }
        String name = video.name;
        if (name.contains('.')) {
          name = name.substring(0, name.lastIndexOf('.'));
        }
        validVideos.add({
          'path': video.path,
          'name': name.trim(),
          'editing': false,
        });
      }

      if (validVideos.isEmpty) {
        if (mounted) {
          ToastUtil.show(context, rejectedNames.isNotEmpty ? '所选文件均不是视频格式' : '未选择视频');
        }
        return;
      }

      if (rejectedNames.isNotEmpty && mounted) {
        ToastUtil.show(context, '已跳过 ${rejectedNames.length} 个非视频文件');
      }

      batchList = validVideos;

      setState(() {
        totalCount = batchList.length;
        currentIndex = 0;
        currentVideoName = batchList[0]['name'];
        showBatchPopup = true;
      });
    } catch (e) {
      if (mounted) {
        ToastUtil.show(context, '选择视频失败: $e');
      }
    }
  }

  void switchTab(int idx) {
    if (activeTab == idx) return;
    setState(() {
      activeTab = idx;
      openIndex = -1; // 切换tab时收起视频，避免残留播放器重建
      isLoading = true; // 显示加载动画，避免旧数据闪烁
      // 不立即清空列表，等 _fetchVideoPage 完成后再替换，防止跳顶
      _videoPage = 1;
      _videoHasMore = true;
      _videoLoadingMore = false;
      _videoLastLoadTime = 0;
      _currentVideoSubject = subjectMap[tabs[idx]] ?? '';
    });
    // 重置滚动条到顶部，避免位置错乱
    if (_videoScrollController.hasClients) {
      _videoScrollController.jumpTo(0);
    }
    _fetchVideoPage(1);
  }

  void showOnlineVideoDialog() {
    setState(() {
      onlineVideoUrl = '';
      onlineVideoName = '';
      showOnlineVideoPopup = true;
    });
  }

  void _onVideoScroll() {
    if (_videoLoadingMore || !_videoHasMore) return;
    // 防抖：距离上次加载更多不足400ms则忽略，防止 jumpTo 恢复位置后重复触发
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _videoLastLoadTime < 400) return;
    final maxScroll = _videoScrollController.position.maxScrollExtent;
    final currentScroll = _videoScrollController.position.pixels;
    if (currentScroll >= maxScroll - 80) {
      _loadMoreVideos();
    }
  }

  Future<void> _fetchVideoPage(int page) async {
    // 保存当前滚动位置，防止加载中跳顶
    final prevOffset = _videoScrollController.hasClients
        ? _videoScrollController.offset : 0.0;
    final subject = _currentVideoSubject.isNotEmpty
        ? _currentVideoSubject
        : (subjectMap[tabs[activeTab]] ?? '');
    // 在请求前立即标记加载中，防止并发重复请求
    setState(() {
      _videoLoadingMore = true;
      if (page == 1) isLoading = true;
    });
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/video'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'action': 'getAll',
          'subject': subject,
          'page': '$page',
          'limit': '10',
        }),
      )).body);
      if (res['success'] == true) {
        final newList = res['data'] ?? [];
        final pag = res['pagination'] ?? {};
        // 修复：用返回条数判断是否有更多，比 total 更可靠
        final limit = int.tryParse((pag['limit'] ?? 10).toString()) ?? 10;
        final hasMore = newList.length >= limit;
        setState(() {
          isLoading = false;
          if (page == 1) {
            videoList = newList;
          } else {
            videoList = [...videoList, ...newList];
          }
          _videoPage = page;
          _videoHasMore = hasMore;
          _videoLoadingMore = false;
          _videoLastLoadTime = DateTime.now().millisecondsSinceEpoch;
        });
        // 恢复滚动位置，避免加载更多后跳回顶部
        if (_videoScrollController.hasClients && page > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _videoScrollController.jumpTo(prevOffset);
          });
        }
      }
    } catch (e) {
      debugPrint('Load video error: $e');
      setState(() {
        isLoading = false;
        _videoLoadingMore = false;
      });
    }
  }

  Future<void> _loadMoreVideos() async {
    if (_videoLoadingMore || !_videoHasMore) return;
    await _fetchVideoPage(_videoPage + 1);
  }

  Future<void> loadVideoList() async {
    // 保存当前滚动位置
    final prevOffset = _videoScrollController.hasClients
        ? _videoScrollController.offset : 0.0;
    setState(() {
      isLoading = true;
      videoList.clear();
    });
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/video'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'action': 'getAll',
          'subject': _currentVideoSubject.isNotEmpty
              ? _currentVideoSubject
              : subjectMap[tabs[activeTab]] ?? ''
        }),
      )).body);
      if (res['success'] == true) {
        setState(() => videoList = res['data'] ?? []);
      }
    } finally {
      setState(() => isLoading = false);
    }
    // 恢复滚动位置
    if (_videoScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _videoScrollController.jumpTo(prevOffset);
      });
    }
  }

  Future<void> deleteVideo(dynamic item) async {
    try {
      await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/video'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'delete', 'videoId': item['_id'] ?? item['videoId']}),
      )).body);
      _fetchVideoPage(1);
    } catch (e) {
      debugPrint('❌ deleteVideo异常: $e');
    }
  }

  void _exitBatchDeleteMode() {
    setState(() {
      _batchDeleteMode = false;
      _selectedVideoIds.clear();
      _videoBatchClearing = false;
      _videoBatchDeleting = false;
    });
  }

  Future<void> _batchDeleteVideos() async {
    if (_selectedVideoIds.isEmpty) return;
    // 确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text("批量删除",
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          "确定要删除选中的 ${_selectedVideoIds.length} 个视频吗？\n删除后无法恢复。",
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text("取消", style: TextStyle(fontSize: 14, color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("删除",
                style: TextStyle(
                    fontSize: 14,
                    color: UIHelpers.errorColor,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _videoBatchDeleting = true);
    try {
      for (final vid in _selectedVideoIds) {
        await jsonDecode((await http.post(
          Uri.parse('$baseUrl/api/video'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({'action': 'delete', 'videoId': vid}),
        )).body);
      }
      _exitBatchDeleteMode();
      await _fetchVideoPage(1);
    } catch (e) {
      debugPrint('❌ 批量删除异常: $e');
      setState(() => _videoBatchDeleting = false);
    }
  }

  void toggleUserWeek(int idx) {
    setState(() {
      if (expandedUser == idx) {
        expandedUser = -1;
      } else {
        expandedUser = idx;
        expandedWeek.clear();
      }
    });
  }

  void toggleWeekDetail(int userIdx, int weekIdx) {
    setState(() {
      if (expandedWeek[userIdx] == weekIdx) {
        expandedWeek[userIdx] = -1;
      } else {
        expandedWeek[userIdx] = weekIdx;
      }
    });
  }

  Future<void> searchProgress() async {
    setState(() => progressLoading = true);
    try {
      // 查找当前选中的时间范围
      String? startDate;
      String? endDate;
      String? rangeId;
      if (selectedRangeId != null && taskTimeRanges.isNotEmpty) {
        for (final r in taskTimeRanges) {
          if (r['_id'] == selectedRangeId) {
            startDate = r['startDate'];
            endDate = r['endDate'];
            rangeId = r['_id'];
            break;
          }
        }
      }

      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'action': 'searchProgress',
          'searchKey': searchKey.trim(),
          'startDate': startDate,
          'endDate': endDate,
          'rangeId': rangeId,
          'weekStr': progressSelectedWeekStr,
        }),
      )).body);
      debugPrint('📊 Admin端完整响应: $res');

      if (res['success'] == true) {
        setState(() => userProgressList = res['data'] ?? []);
      } else {
        debugPrint('❌ 后端返回失败: ${res['message']}');
      }
    } catch (e) {
      debugPrint('❌ searchProgress异常: $e');
    } finally {
      setState(() => progressLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildMainTab(),
                const SizedBox(height: 16),
                Expanded(
                  child: IndexedStack(
                    index: mainTab,
                    children: [
                      _buildTimePage(),
                      _buildVideoPage(),
                      _buildProgressPage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showBatchPopup) _buildBatchUploadDialog(),
          if (showOnlineVideoPopup) _buildOnlineVideoDialog(),
        ],
      ),
    );
  }

  Widget _buildMainTab() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildMainTabItem("学习要求配置", 0),
          _buildMainTabItem("科目视频管理", 1),
          _buildMainTabItem("用户学习进度", 2),
        ],
      ),
    );
  }

  Widget _buildMainTabItem(String text, int idx) {
    return Expanded(
      child: GestureDetector(
        onTap: () => handleMainTabChange(idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: mainTab == idx ? UIHelpers.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(UIHelpers.radiusRound),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: mainTab == idx ? Colors.white : Colors.black87,
              fontWeight: mainTab == idx ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimePage() {
    return Scrollable(
      physics: const AlwaysScrollableScrollPhysics(),
      viewportBuilder: (context, scrollOffset) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [
                0.0,
                0.02,
                0.92,
                1.0,
              ],
              colors: [
                Colors.black.withValues(alpha: 0.0),
                Colors.black.withValues(alpha: 1.0),
                Colors.black.withValues(alpha: 1.0),
                Colors.black.withValues(alpha: 0.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ====================== 任务时间范围选择器 ======================
                _buildTimeRangeSection(),
                const SizedBox(height: 20),
                // ====================== 周配置编辑器（新） ======================
                if (selectedRangeId != null) ...[
                  // 周标签栏
                  _buildWeekTabs(),
                  const SizedBox(height: 16),
                  // 当前周配置编辑器
                  if (selectedWeekStr != null) ...[
                    _buildWeekConfigEditor(),
                    const SizedBox(height: 16),
                    // 操作按钮区：应用到全部（左） + 保存配置（右）
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: weekConfigLoading ? null : () => _showApplyToAllDialog(),
                            icon: const Icon(Icons.settings, size: 18),
                            label: const Text('高级应用'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: UIHelpers.primaryColor,
                              side: BorderSide(color: UIHelpers.primaryColor),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: weekConfigLoading ? null : () => saveWeekConfig(
                              selectedWeekStr!,
                              _buildWeekConfigFromEditor(),
                            ),
                            icon: const Icon(Icons.save, size: 18),
                            label: const Text('保存配置'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: UIHelpers.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('请先选择时间范围并等待周数据加载', style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                  ],
                ],
                // 底部留白，确保按钮不被导航栏遮挡
                SizedBox(height: MediaQuery.of(context).size.height * 0.15),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建周标签栏
  Widget _buildWeekTabs() {
    if (selectedRangeWeeks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('暂无周数据，请先创建时间范围', style: TextStyle(color: Colors.grey))),
      );
    }

    // 计算当前周的 weekStr
    final now = DateTime.now();
    final currentWeekStr = getIsoWeekStr(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('周配置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: selectedRangeWeeks.length,
            itemBuilder: (ctx, idx) {
              final w = selectedRangeWeeks[idx];
              final weekStr = w['weekStr'] as String?;
              final weekLabel = w['weekLabel'] as String? ?? weekStr ?? '';
              final isPartial = w['isPartialWeek'] == true;
              final isSelected = weekStr == selectedWeekStr;
              final isCurrentWeek = weekStr == currentWeekStr;
              return GestureDetector(
                onTap: weekConfigLoading ? null : () async {
                  if (weekStr == selectedWeekStr) return;
                  setState(() {
                    selectedWeekStr = weekStr;
                    weekConfigLoading = true;
                  });
                  await loadWeekConfig(weekStr!);
                  if (mounted) setState(() => weekConfigLoading = false);
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? UIHelpers.primaryColor : Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: isPartial ? Border.all(color: Colors.orange.shade300, width: 1.5) : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weekLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (isCurrentWeek)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white.withValues(alpha: 0.25) : Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '当前周',
                            style: TextStyle(
                              fontSize: 9,
                              color: isSelected ? Colors.white70 : Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else if (isPartial)
                        Text(
                          '残缺周',
                          style: TextStyle(fontSize: 9, color: isSelected ? Colors.white70 : Colors.orange),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 构建周配置编辑器
  Widget _buildWeekConfigEditor() {
    // 确保 weekEditorData 已初始化
    if (weekEditorData.isEmpty) {
      for (int wd = 1; wd <= 7; wd++) {
        weekEditorData[wd] = {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'};
      }
    }
    final weekInfo = selectedRangeWeeks.firstWhere(
      (w) => w['weekStr'] == selectedWeekStr,
      orElse: () => <String, dynamic>{},
    );
    final isPartialWeek = weekInfo['isPartialWeek'] == true;
    final rangeDoc = taskTimeRanges.firstWhere(
      (r) => r['_id'] == selectedRangeId,
      orElse: () => <String, dynamic>{},
    );
    final rangeStart = rangeDoc['startDate'] as String? ?? '';
    final rangeEnd = rangeDoc['endDate'] as String? ?? '';
    // 使用实际周一日期（非裁剪后的）判断哪些天在范围外
    final actualMondayStr = weekInfo['mondayDate'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                '周日期：${weekInfo['weekLabel'] ?? selectedWeekStr}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              if (isPartialWeek)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Chip(
                    label: Text('残缺周', style: TextStyle(fontSize: 10)),
                    backgroundColor: Colors.orange.withValues(alpha: 0.15),
                    labelStyle: const TextStyle(color: Colors.orange, fontSize: 10),
                  ),
                ),
            ],
          ),
        ),
        for (int wd = 1; wd <= 7; wd++) ...[
          _buildWeekDayEditorRow(
            weekday: wd,
            dayName: weekList[wd - 1],
            data: weekEditorData[wd]!,
            isEditable: true,
            readOnlyDays: isPartialWeek
                ? _getPartialWeekReadOnlyDays(actualMondayStr, rangeStart, rangeEnd)
                : {},
          ),
        ],
      ],
    );
  }

  /// 计算残缺周内哪些天是只读的（基于实际周一日期）
  Set<String> _getPartialWeekReadOnlyDays(
    String actualMondayStr, String? rangeStart, String? rangeEnd,
  ) {
    final readOnly = <String>{};
    if (actualMondayStr.isEmpty || rangeStart == null || rangeEnd == null) return readOnly;
    try {
      final monday = DateTime.parse(actualMondayStr);
      for (int wd = 1; wd <= 7; wd++) {
        final dayDate = monday.add(Duration(days: wd - 1));
        final dayStr = dayDate.toIso8601String().split('T')[0];
        if (dayStr.compareTo(rangeStart) < 0 || dayStr.compareTo(rangeEnd) > 0) {
          readOnly.add(weekList[wd - 1]);
        }
      }
    } catch (_) {}
    return readOnly;
  }

  Widget _buildWeekDayEditorRow({
    required int weekday,
    required String dayName,
    required Map<String, String> data,
    required bool isEditable,
    required Set<String> readOnlyDays,
  }) {
    final isReadOnly = readOnlyDays.contains(dayName) || !isEditable;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isReadOnly ? Colors.grey.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: isReadOnly ? Border.all(color: Colors.grey.shade300, width: 1) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                dayName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isReadOnly ? FontWeight.normal : FontWeight.w600,
                  color: isReadOnly ? Colors.grey : Colors.black87,
                ),
              ),
            ),
            ...['语文', '数学', '英语', '其他'].map((label) {
              final key = {'语文': 'yw', '数学': 'sx', '英语': 'en', '其他': 'ot'}[label]!;
              final cacheKey = '${weekday}_$key';
              // 懒创建：确保 controller 和 focusNode 跨重建不丢失，避免光标闪退
              if (!_weekInputControllers.containsKey(cacheKey)) {
                _weekInputControllers[cacheKey] = TextEditingController(text: data[key]);
                _weekInputFocusNodes[cacheKey] = FocusNode();
                // 监听失焦事件：内容为空时恢复默认 0 并同步 weekEditorData
                _weekInputFocusNodes[cacheKey]!.addListener(() {
                  if (!_weekInputFocusNodes[cacheKey]!.hasFocus &&
                      _weekInputControllers[cacheKey]!.text.isEmpty) {
                    _weekInputControllers[cacheKey]!.text = '0';
                    // 同步回 weekEditorData
                    final wdStr = cacheKey.split('_').first;
                    final wd = int.tryParse(wdStr) ?? 0;
                    if (wd >= 1 && wd <= 7 && weekEditorData.containsKey(wd)) {
                      weekEditorData[wd]![key] = '0';
                    }
                  }
                });
              }
              final ctrl = _weekInputControllers[cacheKey]!;
              final node = _weekInputFocusNodes[cacheKey]!;
              return Expanded(
                child: TextField(
                  enabled: !isReadOnly,
                  keyboardType: TextInputType.number,
                  controller: ctrl,
                  focusNode: node,
                  decoration: InputDecoration(
                    labelText: label,
                    labelStyle: TextStyle(fontSize: 11, color: isReadOnly ? Colors.grey : Colors.black54),
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: isReadOnly,
                    fillColor: Colors.grey.withValues(alpha: 0.1),
                  ),
                  onTap: isReadOnly ? null : () {
                    if (ctrl.text == '0') {
                      ctrl.clear();
                    }
                  },
                  onChanged: isReadOnly ? null : (v) => data[key] = v,
                  onEditingComplete: isReadOnly ? null : () => FocusScope.of(context).unfocus(),
                  onSubmitted: isReadOnly ? null : (_) => FocusScope.of(context).unfocus(),
                ),
              );
            }),
            const Text('分', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  List<dynamic> _buildWeekConfigFromEditor() {
    final result = <Map<String, dynamic>>[];
    for (int wd = 1; wd <= 7; wd++) {
      final d = weekEditorData[wd] ?? {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'};
      result.add({
        'weekday': wd,
        'subjects': {
          'chinese': int.tryParse(d['yw'] ?? '0') ?? 0,
          'math': int.tryParse(d['sx'] ?? '0') ?? 0,
          'english': int.tryParse(d['en'] ?? '0') ?? 0,
          'other': int.tryParse(d['ot'] ?? '0') ?? 0,
        }
      });
    }
    return result;
  }

  // ====================== 任务时间范围管理 UI ======================

  Widget _buildTimeRangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('任务时间范围', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(
              onTap: () => _showTimeRangeEditDialog(null),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: UIHelpers.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: UIHelpers.primaryColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: UIHelpers.primaryColor),
                    const SizedBox(width: 4),
                    Text('新增', style: TextStyle(fontSize: 13, color: UIHelpers.primaryColor)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (taskTimeRanges.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2), style: BorderStyle.solid),
            ),
            child: const Center(
              child: Text('暂无时间范围配置\n点击右上角「新增」创建', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
            ),
          )
        else
          ...taskTimeRanges.map((r) => _buildTimeRangeCard(r)),
      ],
    );
  }

  Widget _buildTimeRangeCard(dynamic r) {
    final isSelected = r['_id'] == selectedRangeId;
    return GestureDetector(
      onTap: () async {
        setState(() {
          selectedRangeId = r['_id'];
          selectedWeekStr = null;
          selectedRangeWeeks = [];
        });
        await loadRangeWeeks();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? UIHelpers.primaryColor.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: UIHelpers.primaryColor.withValues(alpha: 0.4), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r['name'] ?? '未命名', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${r['startDate']} ~ ${r['endDate']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              color: UIHelpers.primaryColor,
              onPressed: () => _showTimeRangeEditDialog(r),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: UIHelpers.errorColor,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('确认删除'),
                    content: Text('删除「${r['name'] ?? '未命名'}」时间范围？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          deleteTaskTimeRange(r['_id']);
                        },
                        child: Text('删除', style: TextStyle(color: UIHelpers.errorColor)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTimeRangeEditDialog(dynamic existingRange) {
    final isEdit = existingRange != null;
    final nameCtrl = TextEditingController(text: isEdit ? existingRange['name'] ?? '' : '');
    String startDate = isEdit ? existingRange['startDate'] ?? '' : '';
    String endDate = isEdit ? existingRange['endDate'] ?? '' : '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? '编辑时间范围' : '新增时间范围'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '范围名称',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  startDate =
                                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(startDate.isEmpty ? '开始日期' : startDate,
                                  style: TextStyle(fontSize: 14, color: startDate.isEmpty ? Colors.grey : Colors.black)),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('~'),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  endDate =
                                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(endDate.isEmpty ? '结束日期' : endDate,
                                  style: TextStyle(fontSize: 14, color: endDate.isEmpty ? Colors.grey : Colors.black)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty || startDate.isEmpty || endDate.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('请填写完整信息')),
                      );
                      return;
                    }
                    final rangeData = {
                      'name': nameCtrl.text.trim(),
                      'startDate': startDate,
                      'endDate': endDate,
                    };
                    if (isEdit) {
                      rangeData['_id'] = existingRange['_id'];
                    }
                    Navigator.pop(ctx);
                    saveTaskTimeRange(rangeData);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UIHelpers.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildVideoPage() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: tabs.asMap().entries.map((e) {
              return Expanded(
                child: GestureDetector(
                  onTap: () => switchTab(e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: activeTab == e.key ? UIHelpers.primaryColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
                    ),
                    child: Text(
                      e.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: activeTab == e.key ? Colors.white : Colors.black87,
                        fontWeight: activeTab == e.key ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _batchDeleteMode
                ? Row(
                    children: [
                      // 取消按钮
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_selectedVideoIds.isNotEmpty) {
                              // 第一次点击：清除勾选（标记处于清除状态）
                              setState(() {
                                _selectedVideoIds.clear();
                                _videoBatchClearing = true;
                              });
                            } else if (_videoBatchClearing) {
                              // 第二次点击（清除后再次点击）：退出批量删除模式
                              _exitBatchDeleteMode();
                            } else {
                              // 从未勾选：直接退出
                              _exitBatchDeleteMode();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black87,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text("取消", style: TextStyle(fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 全选按钮
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedVideoIds = videoList
                                  .map((v) => (v['_id'] ?? v['videoId'] ?? '') as String)
                                  .where((id) => id.isNotEmpty)
                                  .toSet();
                              _videoBatchClearing = false;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: UIHelpers.primaryColor,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text("全选", style: TextStyle(fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 批量删除按钮
                      Expanded(
                        flex: 3,
                        child: ElevatedButton(
                          onPressed: _selectedVideoIds.isEmpty || _videoBatchDeleting
                              ? null
                              : () => _batchDeleteVideos(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _selectedVideoIds.isEmpty ? Colors.grey.shade300 : UIHelpers.errorColor,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _videoBatchDeleting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(
                                  _selectedVideoIds.isEmpty
                                      ? "删除"
                                      : "删除（${_selectedVideoIds.length}）",
                                  style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.video_library, size: 18,
                              color: UIHelpers.primaryColor),
                          const SizedBox(width: 8),
                          const Text("视频上传",
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: chooseVideos,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: UIHelpers.primaryColor,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text("上传本地视频"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: showOnlineVideoDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: UIHelpers.successColor,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text("上传在线视频"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        const SizedBox(height: 16),
        //  视频列表区域（自适应渐变效果：参考 student study 的渐变逻辑）
        Expanded(
          child: isLoading
              ? const VideoListShimmer()
              : videoList.isEmpty
              ? const Center(child: Text("暂无视频", style: TextStyle(fontSize: 13, color: Colors.grey)))
              : ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [
                        0.0,    // 🔥 顶部完全透明
                        0.02,   // 🔥 极小渐变区域（只在滚动超出边界时生效）
                        0.92,   // 底部渐隐开始（距离底部60px）
                        1.0     // 底部结束（完全透明）
                      ],
                      colors: [
                        Colors.black.withValues(alpha: 0.0),  // 完全透明（隐藏）
                        Colors.black.withValues(alpha: 1.0),  // 完全不透明（显示）
                        Colors.black.withValues(alpha: 1.0),  // 完全不透明（显示）
                        Colors.black.withValues(alpha: 0.0),  // 完全透明（隐藏）
                      ],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.builder(
                    controller: _videoScrollController,
                    padding: const EdgeInsets.only(top: 12, bottom: 100),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: videoList.length + (_videoLoadingMore ? 1 : (_videoHasMore ? 0 : 1)),
                    itemBuilder: (ctx, idx) {
                      if (idx == videoList.length) {
                        if (_videoLoadingMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                          );
                        }
                        if (!_videoHasMore && videoList.isNotEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: Text("暂无更多", style: TextStyle(fontSize: 13, color: Colors.grey))),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                      final item = videoList[idx];
                      final videoId = item['videoId'] ?? item['_id'] ?? 'video_$idx';
                      final String realVideoId =
                          item['_id'] ?? item['videoId'] ?? '';
                      final bool isSelected =
                          _selectedVideoIds.contains(realVideoId);
                      return GestureDetector(
                        key: Key(videoId),
                        onLongPress: _batchDeleteMode
                            ? null
                            : () {
                                setState(() {
                                  _batchDeleteMode = true;
                                  _selectedVideoIds.clear();
                                  _videoBatchClearing = false;
                                });
                              },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? UIHelpers.primaryColor
                                    .withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: isSelected
                                ? Border.all(
                                    color: UIHelpers.primaryColor, width: 1.5)
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: isSelected ? 0.04 : 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 左侧勾选圆圈（批量删除模式下显示）
                              if (_batchDeleteMode)
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedVideoIds
                                              .remove(realVideoId);
                                        } else {
                                          _selectedVideoIds
                                              .add(realVideoId);
                                        }
                                        _videoBatchClearing = false;
                                      });
                                    },
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? UIHelpers.primaryColor
                                            : Colors.white,
                                        border: Border.all(
                                          color: isSelected
                                              ? UIHelpers.primaryColor
                                              : Colors.grey.shade400,
                                          width: 2,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(
                                              Icons.check,
                                              size: 14,
                                              color: Colors.white)
                                          : null,
                                    ),
                                  ),
                                ),
                              // 卡片内容区域
                              Expanded(
                                child: Column(
                                  children: [
                                    ListTile(
                                      leading: Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: UIHelpers.primaryColor
                                              .withValues(alpha: 0.10),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                            Icons.video_library_rounded,
                                            size: 20,
                                            color:
                                                UIHelpers.primaryColor),
                                      ),
                                      title: Text(
                                        item["name"] ?? "",
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                      ),
                                      trailing:
                                          _batchDeleteMode
                                              ? null
                                              : Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                          horizontal: 12,
                                                          vertical: 6),
                                                  decoration:
                                                      BoxDecoration(
                                                    color: UIHelpers
                                                        .errorColor
                                                        .withValues(alpha: 0.15),
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(
                                                          UIHelpers
                                                              .radiusSmall),
                                                    border: Border.all(
                                                        color: UIHelpers
                                                            .errorColor
                                                            .withValues(
                                                                alpha: 0.4)),
                                                  ),
                                                  child: GestureDetector(
                                                    onTap: () {
                                                      final name = item['name'] ??
                                                          '未命名';
                                                      showDialog(
                                                        context: context,
                                                        builder:
                                                            (ctx) => AlertDialog(
                                                          shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                      14)),
                                                          title: const Text(
                                                              "确认删除",
                                                              style: TextStyle(
                                                                  fontSize: 16,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600)),
                                                          content: Text(
                                                            "确定要删除视频「$name」吗？\n删除后无法恢复。",
                                                            style: const TextStyle(
                                                                fontSize: 14,
                                                                height: 1.6),
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      ctx),
                                                              child: const Text(
                                                                  "取消",
                                                                  style:
                                                                      TextStyle(
                                                                          fontSize:
                                                                              14,
                                                                          color: Colors
                                                                              .grey)),
                                                            ),
                                                            TextButton(
                                                              onPressed: () {
                                                                Navigator.pop(
                                                                    ctx);
                                                                deleteVideo(item);
                                                              },
                                                              child: const Text(
                                                                  "删除",
                                                                  style:
                                                                      TextStyle(
                                                                          fontSize:
                                                                              14,
                                                                          color: UIHelpers
                                                                              .errorColor,
                                                                          fontWeight: FontWeight
                                                                              .w500)),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                    child: const Text(
                                                        "删除",
                                                        style: TextStyle(
                                                            color: UIHelpers
                                                                .errorColor,
                                                            fontSize: 13)),
                                                  ),
                                                ),
                                      onTap: _batchDeleteMode
                                          ? () {
                                              // 批量模式下点卡片 = 勾选
                                              setState(() {
                                                if (isSelected) {
                                                  _selectedVideoIds.remove(
                                                      realVideoId);
                                                } else {
                                                  _selectedVideoIds.add(
                                                      realVideoId);
                                                }
                                                _videoBatchClearing = false;
                                              });
                                            }
                                          : () {
                                              setState(() {
                                                openIndex =
                                                    openIndex == idx ? -1 : idx;
                                              });
                                            },
                                    ),
                                    if (openIndex == idx &&
                                        !_batchDeleteMode)
                                      Padding(
                                        padding:
                                            const EdgeInsets.fromLTRB(
                                                16, 0, 16, 16),
                                        child: CommonVideoPlayer(
                                          videoUrl: item["url"] ?? '',
                                          videoType:
                                              item["isOnline"] == true
                                                  ? 2
                                                  : 1,
                                          autoPlay: true,
                                          onVideoClosed: () {
                                            setState(() {
                                              if (openIndex == idx) {
                                                openIndex = -1;
                                              }
                                            });
                                          },
                                          onEnd: () {
                                            setState(() {
                                              openIndex = -1;
                                            });
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),

      ],
    );
  }

  Widget _buildProgressPage() {
    // 🔥 生成时间范围选项列表（从已配置的任务时间范围中获取）
    List<DropdownMenuItem<String>> rangeDropdownItems = [];
    if (taskTimeRanges.isNotEmpty) {
      for (final r in taskTimeRanges) {
        final label = '${r['name'] ?? '未命名'} (${r['startDate']} ~ ${r['endDate']})';
        rangeDropdownItems.add(
          DropdownMenuItem<String>(
            value: r['_id'] as String,
            child: Text(label, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
        );
      }
    }

    // 计算显示天数：基于选中周的实际日期判断
    int currentDayIndex = DateTime.now().weekday - 1;
    int displayDayCount = 7;
    bool isFutureRange = false;

    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // 残缺周：检测超出时间范围的日期（灰色不可展开）
    Set<int> partialWeekOutOfRangeDays = {};
    bool isPartialWeek = false;
    String partialWeekRangeText = '';

    if (progressSelectedWeekStr != null && progressRangeWeeks.isNotEmpty) {
      final weekInfo = progressRangeWeeks.firstWhere(
        (w) => w['weekStr'] == progressSelectedWeekStr,
        orElse: () => <String, dynamic>{},
      );
      final mondayDate = weekInfo['mondayDate'] as String? ?? '';
      final sundayDate = weekInfo['sundayDate'] as String? ?? '';
      isPartialWeek = weekInfo['isPartialWeek'] == true;

      // 计算残缺周中超出范围的日期
      if (isPartialWeek && mondayDate.isNotEmpty) {
        final rangeDoc = taskTimeRanges.firstWhere(
          (r) => r['_id'] == selectedRangeId,
          orElse: () => <String, dynamic>{},
        );
        final rangeStart = rangeDoc['startDate'] as String? ?? '';
        final rangeEnd = rangeDoc['endDate'] as String? ?? '';
        if (rangeStart.isNotEmpty && rangeEnd.isNotEmpty) {
          partialWeekRangeText = ' ($rangeStart ~ $rangeEnd)';
          final monday = DateTime.parse(mondayDate);
          for (int wd = 1; wd <= 7; wd++) {
            final dayDate = monday.add(Duration(days: wd - 1));
            final dayStr = dayDate.toIso8601String().split('T')[0];
            if (dayStr.compareTo(rangeStart) < 0 || dayStr.compareTo(rangeEnd) > 0) {
              partialWeekOutOfRangeDays.add(wd);
            }
          }
        }
      }

      if (mondayDate.isNotEmpty && sundayDate.isNotEmpty) {
        if (todayStr.compareTo(mondayDate) >= 0 && todayStr.compareTo(sundayDate) <= 0) {
          displayDayCount = currentDayIndex + 1;
        } else if (todayStr.compareTo(mondayDate) > 0) {
          displayDayCount = 7;
        } else {
          isFutureRange = true;
        }
      }
    } else if (selectedRangeId != null && taskTimeRanges.isNotEmpty) {
      for (final r in taskTimeRanges) {
        if (r['_id'] == selectedRangeId) {
          final endDate = r['endDate'] ?? '';
          final startDate = r['startDate'] ?? '';
          if (todayStr.compareTo(startDate) >= 0 && todayStr.compareTo(endDate) <= 0) {
            displayDayCount = currentDayIndex + 1;
          } else if (todayStr.compareTo(endDate) > 0) {
            displayDayCount = 7;
          } else {
            isFutureRange = true;
          }
          break;
        }
      }
    }

    return Column(
      children: [
        // 🔥 搜索栏区域：收起态（搜索图标 + 日期选择器）/ 展开态（搜索框 + 关闭按钮）
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isSearchExpanded
              ? // ===== 展开态：搜索框 + 搜索按钮 + 关闭按钮 =====
              Row(
                  key: const ValueKey('expanded'),
                  children: [
                    Expanded(
                      child: TextField(
                        controller: progressSearchController,
                        autofocus: true,
                        onChanged: (v) => searchKey = v,
                        decoration: InputDecoration(
                          hintText: "输入用户/手机号搜索",
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.85),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (_) => searchProgress(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: searchProgress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UIHelpers.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      child: const Text("搜索"),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          isSearchExpanded = false;
                          searchKey = '';
                          progressSearchController.clear();
                        });
                      },
                      icon: const Icon(Icons.close, size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.85),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ],
                )
              : // ===== 收起态：搜索图标 + 日期选择器 =====
              Row(
                  key: const ValueKey('collapsed'),
                  children: [
                    // 左侧：搜索图标（点击展开）
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          isSearchExpanded = true;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search, size: 22, color: UIHelpers.primaryColor),
                            const SizedBox(width: 4),
                            Text('搜索', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 右侧：时间范围下拉选择器
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: taskTimeRanges.isEmpty
                            ? const Center(child: Text('请先配置时间范围', style: TextStyle(fontSize: 13, color: Colors.grey)))
                            : DropdownButton<String>(
                                value: selectedRangeId,
                                isExpanded: true,
                                underline: const SizedBox(),
                                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                                items: rangeDropdownItems,
                                onChanged: (v) async {
                                  if (v != null) {
                                    setState(() {
                                      selectedRangeId = v;
                                      progressSelectedWeekStr = null;
                                      progressRangeWeeks = [];
                                    });
                                    // 加载该范围内的周列表
                                    await _loadProgressRangeWeeks(v);
                                    await searchProgress();
                                  }
                                },
                              ),
                      ),
                    ),
                  ],
                ),
        ),
        // 🔥 周选择器（范围选定后才显示）
        if (selectedRangeId != null && progressRangeWeeks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<String>(
                    value: progressSelectedWeekStr,
                    isExpanded: true,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                    items: progressRangeWeeks.map((w) {
                      final weekStr = w['weekStr'] as String?;
                      final weekLabel = w['weekLabel'] as String? ?? weekStr ?? '';
                      return DropdownMenuItem<String>(
                        value: weekStr,
                        child: Text(
                          weekLabel,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) async {
                      if (v != null) {
                        setState(() => progressSelectedWeekStr = v);
                        await searchProgress();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: progressLoading
              ? const Center(child: CircularProgressIndicator())
              : userProgressList.isEmpty
              ? const Center(child: Text("暂无用户数据", style: TextStyle(color: Colors.black54)))
              : ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [
                        0.0,    // 🔥 顶部完全透明
                        0.02,   // 🔥 极小渐变区域（只在滚动超出边界时生效）
                        0.92,   // 底部渐隐开始（距离底部60px）
                        1.0     // 底部结束（完全透明）
                      ],
                      colors: [
                        Colors.black.withValues(alpha: 0.0),  // 完全透明（隐藏）
                        Colors.black.withValues(alpha: 1.0),  // 完全不透明（显示）
                        Colors.black.withValues(alpha: 1.0),  // 完全不透明（显示）
                        Colors.black.withValues(alpha: 0.0),  // 完全透明（隐藏）
                      ],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      top: 12,  // 第一个用户卡片与搜索框的间距
                      bottom: MediaQuery.of(context).size.height * 0.35,  // 底部留白，内容自然渐隐
                    ),
                    itemCount: userProgressList.length,
                    itemBuilder: (ctx, userIdx) {
                      final user = userProgressList[userIdx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ExpansionTile(
                          title: Text("${user['name']} | ${user['phone']}"),
                          onExpansionChanged: (v) => toggleUserWeek(userIdx),
                          children: () {
                            List<Widget> weekTiles = [];
                            // 残缺周提示条
                            if (isPartialWeek) {
                              weekTiles.add(
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '残缺周：超出范围的日期已置灰$partialWeekRangeText',
                                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                                  ),
                                ),
                              );
                            }
                            // 残缺周时显示全部7天（含灰色不可展开的超出范围日期）
                            int effectiveDayCount = isPartialWeek ? 7 : displayDayCount;
                            for (int weekIdx = 0; weekIdx < effectiveDayCount && weekIdx < weekList.length; weekIdx++) {
                              final weekData = user['weekData'];
                              if (weekData is! List || weekIdx >= weekData.length) {
                                continue;
                              }
                              final weekday = weekIdx + 1; // 1=周一 ... 7=周日
                              final isOutOfRange = partialWeekOutOfRangeDays.contains(weekday);

                              if (isOutOfRange) {
                                // 残缺周超出范围：灰色不可展开
                                weekTiles.add(
                                  ListTile(
                                    title: Text(
                                      weekList[weekIdx],
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                    subtitle: const Text(
                                      '超出时间范围',
                                      style: TextStyle(color: Colors.grey, fontSize: 12),
                                    ),
                                    trailing: const Icon(Icons.block, color: Colors.grey, size: 18),
                                    enabled: false,
                                  ),
                                );
                              } else if (!isFutureRange || weekIdx < displayDayCount) {
                                weekTiles.add(
                                  ExpansionTile(
                                    title: Text(weekList[weekIdx]),
                                    children: [
                                      _buildSubjectProgress("语文", user, weekIdx, "yw"),
                                      _buildSubjectProgress("数学", user, weekIdx, "sx"),
                                      _buildSubjectProgress("英语", user, weekIdx, "en"),
                                      _buildSubjectProgress("其他", user, weekIdx, "ot"),
                                    ],
                                  )
                                );
                              }
                            }
                            // 当前时间范围内且还没到周末时，显示剩余天数的占位符
                            if (!isFutureRange && !isPartialWeek && displayDayCount < 7) {
                              for (int futureIdx = displayDayCount; futureIdx < weekList.length; futureIdx++) {
                                weekTiles.add(
                                  ExpansionTile(
                                    title: Text(weekList[futureIdx]),
                                    subtitle: const Text("尚未开始", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                                    children: [],
                                  )
                                );
                              }
                            }
                            return weekTiles;
                          }(),
                        ),
                      );
                    },
                  ),
                ),
        ),

      ],
    );
  }

  Widget _buildSubjectProgress(String name, dynamic user, int weekIdx, String key) {
    final weekData = user['weekData'];
    if (weekData is! List || weekIdx >= weekData.length) {
      return const SizedBox.shrink();
    }

    final weekItem = weekData[weekIdx] ?? {};
    final nowValue = weekItem[key];
    final targetValue = weekItem['${key}Target'];

    final now = nowValue is num ? nowValue.toDouble() : (double.tryParse(nowValue?.toString() ?? '0') ?? 0.0);
    final target = targetValue is num ? targetValue.toDouble() : (double.tryParse(targetValue?.toString() ?? '0') ?? 0.0);

    // 进度百分比：上限固定 100%，计算值超过 100% 也只展示 100%
    final rawPercent = target <= 0 ? 0.0 : now / target * 100;
    final percent = rawPercent > 100 ? 100.0 : rawPercent;

    // 已学时长：展示真实原始数值，不受 100% 限制，超过继续正常累加
    final nowDisplay = now.toStringAsFixed(1);

    // 配色：根据百分比动态着色
    final Color barColor =
        percent >= 100 ? Colors.green : (percent >= 70 ? UIHelpers.primaryColor : Colors.orange.shade400);

    // 科目图标与背景色（白/沙/微透风格）
    final Color subjectAccent = _subjectAccentColor(name);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 科目图标
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: subjectAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(
                      _subjectIcon(name),
                      size: 16,
                      color: subjectAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          // 进度百分比标识（不是折线图）
                          Text(
                            '${percent.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: barColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '已学 $nowDisplay 分钟 / 要求 ${target.toInt()} 分钟',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 优化后的进度条：带轨道、圆角、动态配色
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 8,
                backgroundColor: Colors.grey.withValues(alpha: 0.15),
                color: barColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 科目对应的主题色
  Color _subjectAccentColor(String name) {
    switch (name) {
      case '语文':
        return const Color(0xFFE91E63);
      case '数学':
        return const Color(0xFF2196F3);
      case '英语':
        return const Color(0xFF4CAF50);
      case '其他':
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  /// 科目对应的图标
  IconData _subjectIcon(String name) {
    switch (name) {
      case '语文':
        return Icons.menu_book_rounded;
      case '数学':
        return Icons.calculate_rounded;
      case '英语':
        return Icons.translate_rounded;
      case '其他':
      default:
        return Icons.school_rounded;
    }
  }

  Future<void> startBatchUpload() async {
    if (batchList.isEmpty) return;

    setState(() {
      uploading = true;
      uploadingIndex = 0;
      uploadingTotal = batchList.length;
    });

    int successCount = 0;

    for (int i = 0; i < batchList.length; i++) {
      if (!mounted) return;

      final video = batchList[i];
      final uploadId = 'study_video_${DateTime.now().millisecondsSinceEpoch}_$i';
      final fileName = video['name'] ?? '视频';

      setState(() {
        uploadingName = fileName;
        uploadingIndex = i + 1;
        uploadProgress = 0;
      });

      try {
        UploadProgressManager.startUpload(uploadId, fileName);
        debugPrint('📤 开始上传视频: $fileName');
        if (mounted) {
          showUploadProgress(context, uploadId);
        }

        final result = await UploadProgressManager.uploadFileWithProgress(
          url: "$baseUrl/api/video",
          filePath: video['path'],
          fieldName: 'file',
          uploadId: uploadId,
          fields: {
            'action': 'write',
            'subject': subjectMap[tabs[activeTab]] ?? '',
            'name': fileName,
          },
          onProgress: (progress) {
            setState(() {
              uploadProgress = progress * 100;
            });
            UploadProgressManager.updateProgress(uploadId, progress);
          },
        );

        bool uploadSuccess = false;
        String errorMsg = '上传失败';

        if (result['success'] == true) {
          final responseData = result['data'];
          if (responseData is Map<String, dynamic>) {
            if (responseData['success'] == true) {
              uploadSuccess = true;
            } else {
              errorMsg = responseData['message'] ?? '服务器返回上传失败';
            }
          }
        } else {
          errorMsg = result['error'] ?? '上传失败';
        }

        if (uploadSuccess) {
          UploadProgressManager.uploadSuccess(uploadId);
          successCount++;
        } else {
          UploadProgressManager.uploadFailed(uploadId, errorMsg);
          if (mounted) {
            ToastUtil.show(context, '$fileName 上传失败: $errorMsg');
          }
        }
      } catch (e) {
        final errorMsg = '上传异常: $e';
        UploadProgressManager.uploadFailed(uploadId, errorMsg);
        if (mounted) {
          ToastUtil.show(context, '$fileName $errorMsg');
        }
      } finally {
        // 确保每个视频上传结束后关闭进度对话框
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (mounted) {
      setState(() {
        uploading = false;
        showBatchPopup = false;
        batchList.clear();
      });

      if (successCount == uploadingTotal) {
        ToastUtil.show(context, '批量上传完成');
      } else if (successCount > 0) {
        ToastUtil.show(context, '批量上传完成，$successCount/$uploadingTotal 个视频上传成功');
      } else {
        ToastUtil.show(context, '批量上传失败');
      }
      _fetchVideoPage(1);
    }
  }

  Widget _buildBatchUploadDialog() {
    return Stack(
      children: [
        ModalBarrier(color: Colors.black54, dismissible: !uploading),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "批量上传视频",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "共 ${batchList.length} 个视频",
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (uploading)
                    Column(
                      children: [
                        Text(
                          "正在上传：$uploadingName",
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "进度：$uploadingIndex / $uploadingTotal",
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: uploadingTotal > 0 ? uploadingIndex / uploadingTotal : 0,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(UIHelpers.primaryColor),
                        ),
                      ],
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        itemCount: batchList.length,
                        itemBuilder: (ctx, idx) {
                          final video = batchList[idx];
                          final isEditing = video['editing'] == true;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  const Icon(Icons.video_library, color: Colors.blue, size: 32),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: isEditing
                                        ? TextField(
                                      controller: TextEditingController(text: video['name']),
                                      autofocus: true,
                                      onChanged: (value) {
                                        setState(() {
                                          batchList[idx]['name'] = value;
                                        });
                                      },
                                      onSubmitted: (value) {
                                        FocusScope.of(context).unfocus();
                                        setState(() => batchList[idx]['editing'] = false);
                                      },
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    )
                                        : Text(
                                      video['name'],
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(isEditing ? Icons.check : Icons.edit, size: 20),
                                    onPressed: () {
                                      if (isEditing) {
                                        // 点勾时先收起键盘，再从 batchList 读取已实时同步的值
                                        FocusScope.of(context).unfocus();
                                        setState(() => batchList[idx]['editing'] = false);
                                      } else {
                                        setState(() {
                                          batchList[idx]['editing'] = true;
                                          currentIndex = idx;
                                          currentVideoName = batchList[idx]['name'].toString();
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (!uploading)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                showBatchPopup = false;
                                batchList.clear();
                              });
                            },
                            child: const Text("取消"),
                          ),
                        ),
                      if (!uploading) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: uploading ? null : () {
                            for (int i = 0; i < batchList.length; i++) {
                              if (batchList[i]['editing'] == true) {
                                if (i == currentIndex) {
                                  batchList[i]['name'] = currentVideoName.trim();
                                }
                                batchList[i]['editing'] = false;
                              }
                            }
                            startBatchUpload();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: UIHelpers.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            uploading ? "上传中..." : "开始上传",
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineVideoDialog() {
    return GestureDetector(
      onTap: () {
        setState(() {
          showOnlineVideoPopup = false;
        });
      },
      child: Stack(
        children: [
          ModalBarrier(color: Colors.black54, dismissible: true),
          Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "上传在线视频",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      onChanged: (v) => setState(() => onlineVideoUrl = v),
                      decoration: const InputDecoration(
                        labelText: "视频链接",
                        border: OutlineInputBorder(),
                        hintText: "请输入视频网址",
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      onChanged: (v) => setState(() => onlineVideoName = v),
                      decoration: const InputDecoration(
                        labelText: "视频名称",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                showOnlineVideoPopup = false;
                              });
                            },
                            child: const Text("取消"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: onlineVideoUrl.isEmpty || onlineVideoName.isEmpty
                                ? null
                                : uploadOnlineVideo,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: UIHelpers.successColor,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("上传"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> uploadOnlineVideo() async {
    if (!mounted) return;
    
    try {
      final resp = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/video'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'action': 'write',
          'subject': subjectMap[tabs[activeTab]],
          'name': onlineVideoName.trim(),
          'url': onlineVideoUrl.trim(),
          'isOnline': true,
        }),
      )).body);

      if (resp['success'] == true) {
        if (mounted) ToastUtil.show(context, "上传成功");
        if (mounted) {
          setState(() {
            showOnlineVideoPopup = false;
            onlineVideoUrl = "";
            onlineVideoName = "";
          });
          _fetchVideoPage(1);
        }
      } else {
        if (mounted) ToastUtil.show(context, "上传失败");
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, "上传异常");
    }
  }
}
