import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import 'package:flutter/scheduler.dart';
import '../../widgets/common_video_player.dart';
import '../../widgets/shimmer_loading.dart';
import '../../utils/date_utils.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> with WidgetsBindingObserver {
  final String baseUrl = Config.baseUrl;

  String account = '';
  String remark = '';
  String todayDate = '';

  // 🔥 任务时间范围选择（学生端也需跟随范围配置）
  List<dynamic> taskTimeRanges = [];
  String? selectedRangeId;
  List<dynamic> rangeWeeks = [];
  String? selectedWeekStr;

  // ====================== 修复 1：补全「其他」科目 ======================
  final List<String> tabs = ['语文', '数学', '英语', '其他'];
  final Map<String, String> subjectMap = {
    '语文': 'chinese',
    '数学': 'math',
    '英语': 'english',
    '其他': 'other',
  };

  int activeTab = 0;
  List<dynamic> videoList = [];
  bool isLoading = false;
  int openIndex = -1;
  int _videoPage = 1;
  bool _videoHasMore = true;
  bool _videoLoadingMore = false;
  int _videoLastLoadTime = 0; // 防抖：防止滚动事件重复触发
  String _currentVideoSubject = '';

  Map<String, dynamic> studyStats = {
    'require': 0,
    'finished': 0.0,
    'percent': 0.0,
  };

  final ScrollController _scrollController = ScrollController();

  // ====================== 修复 2：视频计时全套逻辑（挂钟时间戳，消除 Timer 漂移）======================
  bool timerVisible = false;
  int sessionSeconds = 0;  // ✅ 当前会话累计时间（未提交，单位：秒，int）
  int totalSubmittedSeconds = 0;  // ✅ 已提交的总时间
  Timer? timerInterval;
  Timer? submitInterval;
  bool _submitting = false; // 防止并发提交
  bool _wasBuffering = false; // 记住上一轮缓冲状态，避免 onBuffering 高频回调反复重造 Timer

  // 🔥 全屏切换宽限期：进入/退出全屏时方向锁定、surface 重建会让 isPlaying 瞬时翻转，
  //    若此时 onPause 触发 _stopTimer 会作废挂钟基准导致计时停止/归零。
  //    宽限期内冻结 UI 刷新（不 cancel 计时器、不清基准），并抑制 _resumeTimer 的重建，
  //    让「全屏中方向切换」不中断计时；宽限期结束由 _finishOrientationSwitch 恢复刷新。
  bool _inOrientationSwitch = false;
  Timer? _orientationSwitchTimer;

  // 🔥 跟踪当前/最近打开的视频 ID：用于"同视频恢复播放不重置挂钟、仅换视频/收起卡片才 reset"
  String _lastVideoId = '';
  bool _hasActiveVideoSession = false; // 是否有打开中/暂停中的视频（决定 _resetTimer 是否真正清零）

  // 🔥 挂钟时间戳：每次开始计时记录起始时刻，每次结算（提交/暂停/停止）记录已结算到此刻的墙钟值
  // 这样即使 Timer.periodic 漂移，只要用「now - sessionStart」就能算出真实的流逝秒数
  DateTime? _sessionStart; // 本轮播放开始时刻

  /// 取当前未提交秒数（基于挂钟，精确到整数秒）
  int get _pendingSeconds {
    if (_sessionStart == null) return 0;
    // 毫秒级精度（floor）：消除 30s 结算整数秒"对齐"导致的多计/少计
    final elapsed = DateTime.now().difference(_sessionStart!).inMilliseconds;
    return elapsed ~/ 1000;
  }

  // 任务时间范围判断
  bool _isInRange = false;

  // 学习统计是否正在加载（首帧为 true，接口返回后置 false）
  // 用于消除「数据未返回时先渲染空状态、返回后再刷新」的闪烁
  bool _statsLoading = true;

  // 进度卡片固定最小高度：三态（加载中/空状态/正常）统一，避免卡片随状态收缩、下边界上移
  static const double _statsCardMinHeight = 108;

  // 🔥 区分「用户真正暂停」与「全屏切换假暂停」：
  //   真正暂停时，宽限期结束应提交剩余时间并停止计时；
  //   假暂停时，宽限期结束应恢复计时。
  bool _videoPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _initUserAndDate().then((_) {
      _fetchVideoPage(1);
      loadTimeRanges().then((_) => loadStudyStats());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _orientationSwitchTimer?.cancel();
    _orientationSwitchTimer = null;
    _stopTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // ✅ 应用真正进入后台（不可见）→ 结算并提交累计时间、停 UI
      _stopTimer();
    } else if (state == AppLifecycleState.inactive) {
      // 🔥 修复：inactive 在 Android 上会被「屏幕旋转、全屏切换、来电/对话框部分遮挡」触发，
      //    此时视频通常仍在播放。若在此 _stopTimer 会作废挂钟基准、停掉计时器，
      //    导致全屏观看的这段时间不再累计（计时停留在进入全屏前的值）。
      //    因此只在 inactive 时冻结 UI 刷新（不提交、不置空基准），resumed 后再恢复；
      //    真正的后台（paused）才走 _stopTimer 结算。
      _pauseTimer();
    } else if (state == AppLifecycleState.resumed) {
      // ✅ 应用恢复前台时，如果视频仍在播放则继续计时
      // 挂钟基准 _sessionStart 在 _pauseTimer 中被保留，恢复 UI 刷新即可继续累计
      _resumeTimer();
      // 注意：这里不重新基准，由视频的 onPlay 回调 / 宽限期统一驱动
    }
  }

  Future<void> _initUserAndDate() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfo = prefs.getString('userInfo');
    if (userInfo != null) {
      try {
        final user = jsonDecode(userInfo);
        setState(() {
          account = user['account'] ?? '';
          remark = user['remark'] ?? '';
        });
      } catch (e, stackTrace) {
        debugPrint('[_initUserAndDate] parse userInfo failed: $e\n$stackTrace');
      }
    }
    setState(() {
      todayDate = DateTime.now().toIso8601String().split('T')[0];
    });
  }

  void switchTab(int idx) {
    _resetTimer();
    setState(() {
      activeTab = idx;
      openIndex = -1; // 切换tab时收起视频
      isLoading = true; // 显示加载动画
      // 不立即清空列表，等 _fetchVideoPage 完成后再替换
      _videoPage = 1;
      _videoHasMore = true;
      _videoLoadingMore = false;
      _videoLastLoadTime = 0;
      _currentVideoSubject = subjectMap[tabs[idx]] ?? '';
    });
    // 重置滚动条到顶部，避免位置错乱
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _fetchVideoPage(1);
    loadStudyStats();
  }

  void _onScroll() {
    // 防抖加载更多（距离上次请求不足400ms则忽略）
    if (_videoLoadingMore || !_videoHasMore) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _videoLastLoadTime < 400) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 80) {
      _loadMoreVideos();
    }
  }

  Future<void> _fetchVideoPage(int page) async {
    // 保存当前滚动位置，防止加载中跳顶
    final prevOffset = _scrollController.hasClients
        ? _scrollController.offset : 0.0;
    final subject = _currentVideoSubject.isNotEmpty
        ? _currentVideoSubject
        : (subjectMap[tabs[activeTab]] ?? '');
    // 在请求前立即标记加载中，防止并发重复请求
    setState(() {
      _videoLoadingMore = true;
      if (page == 1) isLoading = true;
    });
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/video'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        'action': 'getAll',
        'subject': subject,
        'page': '$page',
        'limit': '10',
      }),
      )).body);
      if (data['success'] == true) {
        final newList = data['data'] ?? [];
        final pag = data['pagination'] ?? {};
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
        if (_scrollController.hasClients && page > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollController.jumpTo(prevOffset);
          });
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[_fetchVideoPage] failed: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          isLoading = false;
          _videoLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreVideos() async {
    if (_videoLoadingMore || !_videoHasMore) return;
    await _fetchVideoPage(_videoPage + 1);
  }

  Future<void> _refreshVideos() async {
    // 刷新前重置滚动位置，避免 RefreshIndicator 判定时 offset 非 0
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() {
      _videoPage = 1;
      _videoHasMore = true;
      _videoLoadingMore = false;
      videoList = [];
      isLoading = true;
    });
    await _fetchVideoPage(1);
    await loadStudyStats();
  }

  // ====================== 任务时间范围加载（学生端） ======================

  Future<void> loadTimeRanges() async {
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getTimeRanges'}),
      )).body);
      if (data['success'] == true) {
        final ranges = data['data'] as List? ?? [];
        setState(() => taskTimeRanges = ranges);

        // 自动选择包含今天的范围；若无匹配则不设置 selectedRangeId（保留 null），
        // 使 loadStudyStats 回退到全局默认周配置，避免从已过期范围加载空数据
        if (selectedRangeId == null && ranges.isNotEmpty) {
          final todayStr =
              '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
          String? matchedId;
          for (final r in ranges) {
            if (todayStr.compareTo(r['startDate'] ?? '') >= 0 &&
                todayStr.compareTo(r['endDate'] ?? '') <= 0) {
              matchedId = r['_id'];
              break;
            }
          }
          // 不再 fallback 到第一个范围；只有匹配今天的范围才设为选中
          if (matchedId != null) {
            selectedRangeId = matchedId;
          } else {
            selectedRangeId = null;
          }
        }

        // 判断今天是否在某个时间范围内
        _updateIsInRange();

        // 加载选中范围的周列表并默认选中当前周
        if (selectedRangeId != null) {
          await loadRangeWeeks(selectedRangeId!);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[loadTimeRanges] failed: $e\n$stackTrace');
    }
  }

  Future<void> loadRangeWeeks(String rangeId) async {
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getRangeWeeks', 'rangeId': rangeId}),
      )).body);
      if (data['success'] == true) {
        final weeks = data['data'] as List? ?? [];
        // 默认选中当前周：优先精确匹配当前 ISO 周字符串
        String? defaultWeekStr;
        if (weeks.isNotEmpty) {
          final currentWeekStr = getIsoWeekStr(DateTime.now());
          for (final w in weeks) {
            if (w['weekStr'] == currentWeekStr) {
              defaultWeekStr = w['weekStr'] as String?;
              break;
            }
          }
          // 如果当前周不在范围内，找最近的过去周
          if (defaultWeekStr == null) {
            final todayStr = todayDate.isEmpty
                ? DateTime.now().toIso8601String().split('T')[0]
                : todayDate;
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
          rangeWeeks = weeks;
          selectedWeekStr = defaultWeekStr;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[loadRangeWeeks] failed: $e\n$stackTrace');
    }
  }

  /// 安全解析数字（兼容 int / double / String 三种类型）
  int _safeParseInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  /// 安全解析 double（兼容 int / double / String），用于读取后端"分钟"值
  double _safeParseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is int) return val.toDouble();
    if (val is double) return val;
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  /// 判断今天是否在某个任务时间范围内
  void _updateIsInRange() {
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    bool inRange = false;
    for (final r in taskTimeRanges) {
      final start = r['startDate'] as String? ?? '';
      final end = r['endDate'] as String? ?? '';
      if (todayStr.compareTo(start) >= 0 && todayStr.compareTo(end) <= 0) {
        inRange = true;
        break;
      }
    }
    setState(() => _isInRange = inRange);
  }

  /// 安全获取 weekday（兼容 int / double / String）
  int _safeParseWeekday(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  Future<void> loadStudyStats() async {
    // 仅在首次加载（尚无数据）时显示骨架占位；已有数据时直接静默刷新，避免卡片整个重载闪烁
    final bool hasData = studyStats['require'] != 0 || studyStats['finished'] != 0 || studyStats['percent'] != 0.0;
    if (!hasData) {
      setState(() => _statsLoading = true);
    }
    try {
      List<dynamic> configList = [];

      // 优先：范围 + 周配置
      if (selectedRangeId != null && selectedWeekStr != null) {
        final weekConfigData = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'action': 'getRangeWeekConfig',
          'rangeId': selectedRangeId,
          'weekStr': selectedWeekStr,
        }),
      )).body);
        if (weekConfigData['success'] == true) {
          final data = weekConfigData['data'];
          if (data is List && data.isNotEmpty) {
            configList = data;
          }
        }
      }

      // 回退：全局默认周配置
      if (configList.isEmpty) {
        final globalConfigData = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getConfig'}),
      )).body);
        if (globalConfigData['success'] == true) {
          final data = globalConfigData['data'];
          if (data is List && data.isNotEmpty) {
            configList = data;
          }
        }
      }

      final recordData = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        'action': 'getUserStudyRecord',
        'userid': account,
        'date': todayDate,
      }),
      )).body);

      final weekDay = DateTime.now().weekday;
      final todayConfig = configList.firstWhere(
        (e) => _safeParseWeekday(e['weekday']) == weekDay,
        orElse: () => {'subjects': {}},
      );
      final subjects = todayConfig['subjects'] as Map? ?? {};
      final record = recordData['success'] == true
          ? (recordData['data'] as Map? ?? {})
          : {};

      final subKey = subjectMap[tabs[activeTab]]!;
      final require = _safeParseInt(subjects[subKey]);
      // ✅ 已学时长：后端存的是「分钟」（可能是 0.5/1.5 等小数），直接按 double 取，
      //    不再走 _safeParseInt 的 int 截断，避免"刚提交 30s 读回 0"的假象
      final finished = _safeParseDouble(record[subKey]);
      // 进度百分比封顶 100%，避免超过要求时长后进度条溢出
      final rawPercent = require > 0 ? (finished / require) * 100 : 0.0;
      final percent = rawPercent > 100 ? 100.0 : rawPercent;

      setState(() {
        studyStats = {
          'require': require,
          'finished': finished,
          'percent': percent,
        };
        _statsLoading = false; // 数据就绪，退出加载态
      });
    } catch (e, stackTrace) {
      debugPrint('[loadStudyStats] failed: $e\n$stackTrace');
      if (mounted) {
        setState(() => _statsLoading = false);
      }
    }
  }

  // ====================== 核心：启动计时（挂钟时间戳，精确）======================
  // videoId 用于区分"同视频恢复"与"换视频"：
  //   - 首次/换视频（_lastVideoId != videoId）→ 重新基准挂钟
  //   - 同视频恢复（_lastVideoId == videoId 且 _sessionStart != null）→ 保留挂钟，仅补建定时器
  void _startTimer(String videoId) {
    // 不在任务时间范围内，禁止启动计时
    if (!_isInRange) return;

    final isNewVideo = _lastVideoId != videoId;
    final hasActiveSession = _hasActiveVideoSession;
    final shouldResetBase = isNewVideo || !hasActiveSession;

    _lastVideoId = videoId;
    _hasActiveVideoSession = true;

    if (shouldResetBase) {
      setState(() {
        timerVisible = true;
        _sessionStart = DateTime.now();
        // 仅当挂钟基准已被真正作废（_stopTimer/_resetTimer 置 null）才清零计数；
        // 否则（如全屏切换后恢复播放、基准仍有效）保留已累计的 totalSubmitted，避免计时归零
        if (_sessionStart == null) {
          sessionSeconds = 0;
          totalSubmittedSeconds = 0;
        }
      });
    } else {
      // 同视频恢复：保留 _sessionStart 挂钟基准，不清零 sessionSeconds
      // 仅让悬浮计时器可见（若 _pauseTimer 期间被隐藏）
      setState(() => timerVisible = true);
    }

    // 🔥 重建定时器前先取消旧定时器，防止 onPlay 多次触发（全屏切换、缓冲结束等）
    //    导致 Timer.periodic 层层叠加 → 30s 提交/UI 刷新被高频重入（进度百分比几秒就刷一次）
    _cancelTimerInternal();

    // UI 刷新定时器：每 1 秒刷新悬浮计时器
    // 🔥 进度卡片完全由 loadStudyStats() 驱动；此处仅更新 sessionSeconds（悬浮计时器显示）
    timerInterval = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      sessionSeconds = _pendingSeconds;
      setState(() {});
    });

    // 提交定时器：每 30 秒结算一次
    submitInterval = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_submitting) {
        _submitting = true;
        final toSubmit = _pendingSeconds;
        if (toSubmit > 0) {
          // 🔥 同步原子结算（消除闪动/漂移）：
          //    1) 挂钟基准直接重置为「结算时刻 now」，pending 归零；
          //    2) totalSubmittedSeconds 立即加上 toSubmit（UI 显示 = total + pending，
          //       网络 await 期间 pending≈0、total 已含这段，画面不再闪 0/闪 30）；
          //    3) 之后网络在 await 中失败/成功都不再影响挂钟精度（结算已对齐）
          _sessionStart = DateTime.now();
          setState(() {
            totalSubmittedSeconds += toSubmit;
            sessionSeconds = 0;
          });
          // 🔥 每 30 秒提交后强制刷新后端最新数据，进度卡片以服务端为准
          await submitStudyTime(toSubmit, refreshStats: true);
        }
        _submitting = false;
      }
    });
  }

  // 🔥 内部取消：停掉 UI 刷新 + 30s 提交两个周期定时器并置空（供 _startTimer/_resumeTimer 重建前调用）
  void _cancelTimerInternal() {
    timerInterval?.cancel();
    submitInterval?.cancel();
    timerInterval = null;
    submitInterval = null;
  }

  // ====================== 核心：停止计时（挂钟结算）======================
  // 用户主动暂停/关闭视频都提交剩余挂钟时间，保证时间不丢；
  // 缓冲/全屏切换走 _pauseTimer（保留挂钟基准、不提交）
  void _stopTimer({bool refreshStats = true}) async {
    // 不在任务时间范围内，不提交也不处理
    if (!_isInRange) {
      timerInterval?.cancel();
      submitInterval?.cancel();
      timerInterval = null;
      submitInterval = null;
      _sessionStart = null;
      _lastVideoId = '';
      _hasActiveVideoSession = false;
      return;
    }

    // 🔥 挂钟结算：同步原子结算（同 30s 定时器结算逻辑，避免 await 期间闪动/丢时间）
    final toSubmit = _pendingSeconds;
    if (toSubmit > 0) {
      _sessionStart = DateTime.now();
      setState(() {
        totalSubmittedSeconds += toSubmit;
        sessionSeconds = 0;
      });
      await submitStudyTime(toSubmit, refreshStats: refreshStats);
    }
    // 🔥 终止挂钟基准，下次启动时重新对齐
    _sessionStart = null;

    timerInterval?.cancel();
    submitInterval?.cancel();

    setState(() {
      timerInterval = null;
      submitInterval = null;
      _hasActiveVideoSession = false; // 释放会话绑定，下次 _startTimer 会重新基准
      // ✅ 关键修复：不清零 timerVisible，让计时器持续显示总学习时间
    });
  }

  // ====================== 🔥 暂停计时（缓冲/全屏切换时使用，不提交）======================
  void _pauseTimer() {
    if (_videoPaused) return; // 已在暂停态，不重复处理
    _videoPaused = true;
    timerInterval?.cancel();
    submitInterval?.cancel();

    setState(() {
      timerInterval = null;
      submitInterval = null;
      // 保留 _sessionStart，挂钟继续累计
    });
  }

  // ====================== 🔥 恢复计时（缓冲结束后使用）======================
  void _resumeTimer() {
    // 不在任务时间范围内，不恢复计时
    if (!_isInRange) return;
    // 🔥 全屏切换冻结期内不恢复 UI 刷新（宽限期结束由 _finishOrientationSwitch 统一处理）
    if (_inOrientationSwitch) return;
    // 🔥 定时器已在跑（UI 刷新定时器活跃）则不重建，防止叠加
    if (timerInterval?.isActive ?? false) return;

    setState(() {
      timerVisible = true;
      _videoPaused = false; // 清除暂停标记，允许下次正常暂停流程
      // 挂钟基准不变，UI 刷新恢复
      sessionSeconds = _pendingSeconds;
    });

    // 🔥 先取消旧定时器再重建，防止 _resumeTimer 被多次触发时 Timer.periodic 叠加
    _cancelTimerInternal();
    // UI 刷新定时器：每 1 秒刷新悬浮计时器
    // 🔥 进度卡片完全由 loadStudyStats() 驱动；此处仅更新 sessionSeconds（悬浮计时器显示）
    timerInterval = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      sessionSeconds = _pendingSeconds;
      setState(() {});
    });

    submitInterval = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_submitting) {
        _submitting = true;
        final toSubmit = _pendingSeconds;
        if (toSubmit > 0) {
          // 同步原子结算（同 _startTimer 内提交逻辑，消除闪动/漂移）
          _sessionStart = DateTime.now();
          setState(() {
            totalSubmittedSeconds += toSubmit;
            sessionSeconds = 0;
          });
          // 🔥 每 30 秒提交后强制刷新后端最新数据，进度卡片以服务端为准
          await submitStudyTime(toSubmit, refreshStats: true);
        }
        _submitting = false;
      }
    });
  }

  // ====================== 完全退出视频时清零 ======================
  void _resetTimer() async {
    // 不在任务时间范围内，不清零也不提交
    if (!_isInRange) {
      _cancelTimerInternal();
      _sessionStart = null;
      _lastVideoId = '';
      _hasActiveVideoSession = false;
      return;
    }
    // 先同步原子结算剩余时间（挂钟结算），再发网络
    final toSubmit = _pendingSeconds;
    if (toSubmit > 0) {
      _sessionStart = DateTime.now();
      setState(() {
        totalSubmittedSeconds += toSubmit;
        sessionSeconds = 0;
      });
      // 退出视频时刷新进度卡片，让用户看到最新入库数据
      await submitStudyTime(toSubmit, refreshStats: true);
    }

    _cancelTimerInternal();

    setState(() {
      timerInterval = null;
      submitInterval = null;
      sessionSeconds = 0;           // ✅ 清零当前会话时间
      totalSubmittedSeconds = 0;    // ✅ 清零已提交时间
      timerVisible = false;         // ✅ 隐藏计时器
      _sessionStart = null;         // ✅ 终止挂钟基准
      _wasBuffering = false;        // ✅ 重置缓冲状态标志
      _lastVideoId = '';            // ✅ 释放视频会话绑定
      _hasActiveVideoSession = false;
    });
  }

  // ====================== 🔥 全屏切换宽限期：冻结UI但保留挂钟（不中断计时）======================
  // 进入/退出全屏时 isPlaying 会瞬时翻转触发 onPause，并非用户真正暂停。
  // 宽限期内：
  //   - 不 cancel 计时器、不置 _sessionStart=null（挂钟继续累计，全屏期间时间照算）
  //   - 抑制 UI 刷新（冻结显示值），避免 _stopTimer 作废基准导致计时停止/归零
  // 宽限期结束（2.5s 无新 onPause）若仍处于"假暂停"（_sessionStart 仍有效）再真正 _stopTimer。
  void _beginOrientationSwitch() {
    if (!_inOrientationSwitch) {
      _inOrientationSwitch = true;
      // 🔥 标记为「真正暂停」；若后续无新 onPause（全屏切换假暂停），_finishOrientationSwitch 会恢复计时
      //    若有新 onPause（用户真暂停），_videoPaused 保持 true，宽限期结束后提交剩余时间
      _videoPaused = true;
      setState(() {
        // 冻结 UI 刷新（timerInterval cancel），但保留挂钟基准 _sessionStart，
        // 全屏切换期间流逝的时间照常累计
        timerInterval?.cancel();
        timerInterval = null;
        sessionSeconds = _pendingSeconds; // 冻结当前显示值
      });
    }
    _orientationSwitchTimer?.cancel();
    _orientationSwitchTimer =
        Timer(const Duration(milliseconds: 2500), _finishOrientationSwitch);
  }

  void _finishOrientationSwitch() {
    if (!_inOrientationSwitch) return;
    _inOrientationSwitch = false;
    _orientationSwitchTimer?.cancel();
    _orientationSwitchTimer = null;
    if (_videoPaused) {
      // 🔥 用户真正暂停：宽限期结束，提交剩余时间并停止计时
      _videoPaused = false;
      _stopTimer();
    } else {
      // 🔥 全屏切换假暂停：恢复计时，挂钟基准不变
      if (_sessionStart != null) {
        _resumeTimer();
      }
    }
  }

  // ====================== 构建悬浮计时器组件 ======================
  Widget _buildFloatingTimer() {
    return _FloatingTimerWidget(
      displayText: formatTime,
    );
  }

  /// [refreshStats]：提交成功后是否立即刷新进度卡片。
  /// 30s 周期提交本身已携带新数据，无需再查一次；停止/关闭/切换 Tab 等
  /// 需要即时反馈的路径传 true。
  Future<void> submitStudyTime(int seconds, {bool refreshStats = true}) async {
    if (account.isEmpty || seconds <= 0) return;
    // 不在任务时间范围内时，禁止提交学习数据
    if (!_isInRange) return;
    final subject = subjectMap[tabs[activeTab]];
    final minutes = seconds / 60;
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        'action': 'addRecord',
        'userid': account,
        'date': todayDate,
        'subject': subject,
        'minutes': minutes,
        'remark': remark,
      }),
      );
      final body = jsonDecode(resp.body);
      // 🔥 必须校验后端 success：addRecord 在「不在任务时间范围」等情况下返回
      //    success:false 但 HTTP 200，旧代码直接刷新卡片导致误以为已入库、数据没更新
      if (body['success'] != true) {
        debugPrint('[submitStudyTime] 后端拒绝入库: ${body['message']}');
        // 🔥 后端拒绝时停止计时并清零，避免累积时间不入库、进度卡片与实际不符
        _resetTimer();
        return;
      }
      if (mounted) {
        if (refreshStats) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            loadStudyStats();
          });
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[submitStudyTime] failed: $e\n$stackTrace');
    }
  }

  String get formatTime {
    // ✅ 显示总学习时间（已提交 + 当前会话），保持 MM:SS 格式
    int totalSeconds = totalSubmittedSeconds + _pendingSeconds;
    int min = totalSeconds ~/ 60;
    int sec = totalSeconds % 60;
    return '已学习：${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── 固定层：标题栏 + 标签栏（不随列表滚动）──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "学习中心",
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, '/public/browser');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.book, size: 16, color: Colors.black87),
                                SizedBox(width: 4),
                                Text(
                                  '课程资源',
                                  style: TextStyle(fontSize: 13, color: Colors.black87),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(22),
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
                          int idx = e.key;
                          String t = e.value;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => switchTab(idx),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: activeTab == idx ? Colors.blue : Colors.transparent,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: activeTab == idx ? Colors.white : Colors.black54,
                                    fontWeight: activeTab == idx ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── 进度卡片（与标题/标签栏同一固定层，不随视频列表滚动）──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      // 固定最小高度：三态统一，卡片不再随状态收缩、下边界上移
                      constraints: const BoxConstraints(minHeight: _statsCardMinHeight),
                      child: _statsLoading
                          // 数据未返回：渲染骨架占位（等高），避免先显示空状态再刷新的闪烁
                          ? Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.blue,
                                ),
                              ),
                            )
                          : _isInRange
                          ? (studyStats['require'] == 0
                              // 空状态（无任务）：卡片整体样式、尺寸与正常进度卡片完全一致，仅左上角文字为「今日，XX科暂无任务」
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "今日 ${tabs[activeTab]} 暂无任务",
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text("要求：${studyStats['require']} 分钟",
                                            style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                        Text("已学：${(studyStats['finished'] as num).toDouble().toStringAsFixed(1)} 分钟",
                                            style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: (studyStats['percent'] as num).toDouble() / 100,
                                        backgroundColor: Colors.black12,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                        minHeight: 6,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text("完成度：${(studyStats['percent'] as num).toDouble().toStringAsFixed(1)}%",
                                        style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "今日 ${tabs[activeTab]} 学习进度",
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text("要求：${studyStats['require']} 分钟",
                                            style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                        Text("已学：${(studyStats['finished'] as num).toDouble().toStringAsFixed(1)} 分钟",
                                            style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: (studyStats['percent'] as num).toDouble() / 100,
                                        backgroundColor: Colors.black12,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                        minHeight: 6,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text("完成度：${(studyStats['percent'] as num).toDouble().toStringAsFixed(1)}%",
                                        style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                  ],
                                ))
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Text(
                                  "不在任务时间范围，当前无需学习",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFFE65100),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  "如果进行学习，数据不会上传到云端",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            // ── 滚动层：仅视频卡片列表（独立滚动，顶部/底部渐变参考考试界面）──
            // 灰屏根因（计时器嵌套 Positioned）已修复，此处安全加回与考试界面一致的 ShaderMask(dstIn) 渐隐
            Positioned(
              top: 222,
              left: 0,
              right: 0,
              bottom: 0,
              // ✅ 对齐管理员端写法：骨架占满整个区域，避免嵌套进 CustomScrollView 导致高度为 0 灰屏
              child: isLoading
                  ? const VideoListShimmer()
                  : ShaderMask(
                      shaderCallback: (bounds) {
                        return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [
                      0.0,    // 顶部完全透明
                      0.02,   // 顶部渐隐结束（约 20px 内淡入）
                      0.92,   // 底部渐隐开始（距离底部 60px）
                      1.0     // 底部完全透明
                    ],
                    colors: [
                      Colors.black.withValues(alpha: 0.0),  // 顶部：完全透明（隐藏）
                      Colors.black.withValues(alpha: 1.0),  // 渐变结束：完全不透明（显示）
                      Colors.black.withValues(alpha: 1.0),  // 保持显示
                      Colors.black.withValues(alpha: 0.0),  // 底部：完全透明（隐藏）
                    ],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: RefreshIndicator(
                  onRefresh: _refreshVideos,
                  color: Colors.blue,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // 视频列表
                    SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index == videoList.length) {
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
                                  var video = videoList[index];
                                  bool isOpen = openIndex == index;
                                  final videoId = video['videoId'] ?? video['_id'] ?? 'video_$index';
                                  return Container(
                                    key: Key(videoId),
                                    margin: const EdgeInsets.only(bottom: 8),
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
                                    child: Column(
                                      children: [
                                        ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          onTap: () {
                                            setState(() {
                                              if (isOpen) {
                                                // ✅ 收起卡片 → 销毁播放器、清零计时
                                                _resetTimer();
                                                openIndex = -1;
                                              } else {
                                                // ✅ 展开卡片（含从另一个展开视频切换过来）：
                                                //    旧卡片随 openIndex 改变自动收起，旧 CommonVideoPlayer 被移除 →
                                                //    onVideoClosed 触发 _resetTimer 清零（同一 setState 批次内完成，顺序一致）
                                                openIndex = index;
                                              }
                                            });
                                          },
                                          leading: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.video_library, color: Colors.blue, size: 20),
                                          ),
                                          title: Text(video['name'] ?? '视频', style: const TextStyle(color: Colors.black87, fontSize: 14)),
                                          trailing: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              isOpen ? Icons.expand_less : Icons.expand_more,
                                              color: Colors.black54,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                        if (isOpen)
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                            child: Stack(
                                              children: [
                                                CommonVideoPlayer(
                                                  key: ValueKey<String>('$videoId'),
                                                  videoUrl: video['url'] ?? '',
                                                  videoType: video['isOnline'] == true ? 2 : 1,
                                                  autoPlay: true,
                                                  onVideoClosed: () {
                                                    // ✅ 视频关闭（卡片收起/切换/销毁）→ 彻底清零累计，下次重新计时
                                                    _resetTimer();
                                                    // 仅在关闭的仍是当前展开卡片时才收起；
                                                    // 若用户已切换到另一视频（openIndex 已变），不破坏新展开状态
                                                    setState(() {
                                                      if (openIndex == index) {
                                                        openIndex = -1;
                                                      }
                                                    });
                                                  },
                                                  onPlay: () {
                                                    // 任意时刻收到播放信号 = 挂钟基准重新对齐（同视频恢复保留基准）
                                                    _startTimer(videoId);
                                                  },
                                                  onPause: () {
                                                    // ✅ 全屏切换期「假暂停」拦截：进入/退出全屏时 isPlaying 会瞬时翻转
                                                    //    （方向锁定 + surface 重建），并非用户真正暂停。
                                                    //    宽限期内冻结 UI 刷新但不作废挂钟基准、不 cancel 计时器，
                                                    //    让计时在切换期间持续累计；宽限期结束后若仍在「假暂停」状态再真正 _stopTimer。
                                                    _beginOrientationSwitch();
                                                  },
                                                  onEnd: () {
                                                    // ✅ 视频播完提交剩余时间、不隐藏计时器、不收起卡片
                                                    _stopTimer();
                                                    setState(() => openIndex = -1);
                                                  },
                                                  onBuffering: (isBuffering) {
                                                    // ✅ 只在缓冲状态「真正翻转」时暂停/恢复，
                                                    //    避免 CommonVideoPlayer 每次 state 变化都回调导致的 Timer 反复重造（计时器不跳动）
                                                    if (isBuffering && _wasBuffering) return;
                                                    if (!isBuffering && !_wasBuffering) return;
                                                    _wasBuffering = isBuffering;
                                                    if (isBuffering) {
                                                      _pauseTimer();
                                                    } else {
                                                      // 缓冲结束恢复播放：挂钟保留，恢复 UI 刷新与 30s 周期提交
                                                      _resumeTimer();
                                                    }
                                                  },
                                                ),
                                                if (timerVisible)
                                                  Positioned(
                                                    left: 8,
                                                    top: 8,
                                                    child: _buildFloatingTimer(),
                                                  ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              childCount: videoList.length + 1,
                              ),
                            ),
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
}

// ====================== 独立计时器组件（避免主页面频繁重建）======================
class _FloatingTimerWidget extends StatefulWidget {
  final String displayText;

  const _FloatingTimerWidget({
    required this.displayText,
  });

  @override
  State<_FloatingTimerWidget> createState() => _FloatingTimerWidgetState();
}

class _FloatingTimerWidgetState extends State<_FloatingTimerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 不再返回 Positioned——由父级控制位置，避免嵌套 Positioned 导致定位错乱
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
        ),
        child: Text(
          widget.displayText,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}
