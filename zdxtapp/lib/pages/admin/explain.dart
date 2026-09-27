import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/io.dart';
import 'package:zdxtapp/config.dart';

import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/formula_renderer.dart';

class ExplainPage extends StatefulWidget {
  const ExplainPage({super.key});
  @override
  State<ExplainPage> createState() => _ExplainPageState();
}

class _ExplainPageState extends State<ExplainPage> {
  final String baseUrl = Config.baseUrl;
  IOWebSocketChannel? _wsChannel;
  Timer? _wsReconnectTimer;
  Timer? _pingTimer;
  int _wsConnectAttempts = 0;
  bool _isConnected = false;
  bool _pendingJoin = false;
  bool screenOnline = false;
  static const int _wsMaxReconnectAttempts = 30;

  // ===== 阶段状态 =====
  bool isExplaining = false;
  String? selectedExamId;
  String? selectedExamName;
  List<Map<String, dynamic>> examList = [];
  bool loadingExams = true;

  // ===== 题目导航 =====
  List<Map<String, dynamic>> questions = [];
  Map<String, dynamic>? currentFullQuestion;
  bool loadingQuestions = false;
  int currentQIndex = 0;

  // ===== 显隐控制 =====
  bool showAnswer = false;
  bool showAnalysis = false;
  bool showStats = false;

  // ===== 统计 =====
  List<Map<String, dynamic>> correctUsers = [];
  List<Map<String, dynamic>> wrongUsers = [];
  bool loadingStats = false;
  String activeStatsTab = 'correct';
  // 按 'examId_questionIndex' 缓存，避免同题重复请求（value = [correctUsers, wrongUsers]）
  final Map<String, List<List<Map<String, dynamic>>>> _statsCache = {};
  // 防止并发重复请求：key 同 cache
  final Set<String> _statsInflight = {};
  // 快速指令去重：最近一次直接发送的指令（cmd+questionIndex），避免连点堆队列
  String? _lastDirectCmd;

  // ===== 答错学生原始答案弹窗 =====
  final bool _loadingWrongDetail = false;

  // ===== 题目详情加载状态 =====
  bool _detailLoading = false;

  // ===== 提示反馈 =====
  String feedbackMsg = '';
  Timer? feedbackTimer;

  // ===== 指令队列（已废弃，保留字段避免编译错误） =====
  // final Queue<Map<String, dynamic>> _cmdQueue = Queue();
  // bool _isProcessingQueue = false;

  @override
  void initState() {
    super.initState();
    _checkExplainStatus();
  }

  // ==================== 检查是否有正在进行的讲解（断点续控） ====================
  Future<void> _checkExplainStatus() async {
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/explain'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getExplainStatus'}),
      )).body);
      if (data['success'] == true && data['data']?['active'] == true && mounted) {
        final d = data['data'] as Map<String, dynamic>;
        final examId = d['examId'] as String;
        final examName = d['examName'] as String? ?? '';
        final qIdx = d['currentQuestionIndex'] as int? ?? 0;
        // 恢复 session 状态
        setState(() {
          isExplaining = true;
          selectedExamId = examId;
          selectedExamName = examName;
          currentQIndex = qIdx;
          _detailLoading = true;
        });
        // 重新加载题目列表和当前题目
        await _loadQuestions(examId);
        if (mounted) {
          _connectWs();
          _sendWsJoin();
          await _fetchFullQuestion(qIdx);
        }
        return;
      }
    } catch (e) {
      debugPrint('检查讲解状态失败: $e');
    }
    // 没有正在进行的讲解，正常加载试卷列表
    if (mounted) _loadExamList();
  }

  @override
  void dispose() {
    _closeWs();
    feedbackTimer?.cancel();
    _wsReconnectTimer?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }

  // ==================== 时间格式化 ====================
  String _fmtTime(String? t) {
    if (t == null || t.isEmpty) return '';
    try {
      final parsed = DateTime.parse(t);
      final cst = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
      return "${cst.year}-${cst.month.toString().padLeft(2, '0')}-${cst.day.toString().padLeft(2, '0')} "
          "${cst.hour.toString().padLeft(2, '0')}:${cst.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return t;
    }
  }

  // ==================== WebSocket 连接 ====================
  void _connectWs() {
    _closeWs();
    _wsConnectAttempts += 1;
    final wsUrl = Config.wsUrl.replaceFirst('http', 'ws');
    debugPrint('🔌 开始连接 WS: $wsUrl/explain-ws (尝试第$_wsConnectAttempts 次)');
    try {
      final channel = IOWebSocketChannel.connect('$wsUrl/explain-ws');
      channel.stream.listen(
        (message) {
          debugPrint('📥 WS 收到消息: ${message.toString().substring(0, message.toString().length > 200 ? 200 : message.toString().length)}');
          _handleWsMessage(message);
        },
        onDone: () {
          debugPrint('❌ WS 连接关闭 (onDone)');
          setState(() => _isConnected = false);
          _scheduleWsReconnect();
        },
        onError: (error) {
          debugPrint('❌ WS 连接错误: $error');
          setState(() => _isConnected = false);
          _scheduleWsReconnect();
        },
        cancelOnError: false,
      );
      _wsChannel = channel;
      debugPrint('✅ WS channel 已创建，等待服务端握手...');
      // 不再立即置 _isConnected=true（连接尚未确认）。
      // 服务端回 'connected' 后才真正标记已连接并发送 admin_join，
      // 避免 join 早于服务端就绪的时序竞态。
      _wsConnectAttempts = 0;
      _pendingJoin = true;
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _sendWsPing());
    } catch (e) {
      debugPrint('❌ WS 连接异常: $e');
      _scheduleWsReconnect();
    }
  }

  void _closeWs() {
    _wsReconnectTimer?.cancel();
    _pingTimer?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;
    setState(() => _isConnected = false);
  }

  void _scheduleWsReconnect() {
    _wsReconnectTimer?.cancel();
    // 重连上限：避免服务端长期不可用时无限重连
    if (_wsConnectAttempts >= _wsMaxReconnectAttempts) {
      debugPrint('⛔ explain WS 已达重连上限($_wsMaxReconnectAttempts次)，停止自动重连');
      _wsConnectAttempts = 0;
      return;
    }
    // 指数退避：首次5s，后续 2^attempt 秒，上限60s
    final delayMs = _wsConnectAttempts == 0
        ? 5000
        : (1 << _wsConnectAttempts) * 1000;
    final delaySec = (delayMs ~/ 1000).clamp(1, 60);
    debugPrint('🔁 explain WS 重连延迟 ${delaySec}s（第$_wsConnectAttempts次）');
    _wsReconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (isExplaining && mounted) {
        _wsConnectAttempts += 1;
        _connectWs();
      }
    });
  }

  void _sendWsPing() {
    if (_wsChannel != null && _isConnected) {
      _wsChannel!.sink.add(jsonEncode({'type': 'ping'}));
    }
  }

  void _sendWsJoin() {
    if (isExplaining && _isConnected && _wsChannel != null) {
      _wsChannel!.sink.add(jsonEncode({'type': 'admin_join'}));
    }
  }

  void _handleWsMessage(dynamic raw) {
    if (!mounted) return;
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>?;
      if (msg == null) return;
      final type = msg['type'] as String?;
      if (type == null) return;

      if (type == 'connected') {
        debugPrint('✅ WS 收到 connected 消息，examId=${msg['examId']}, _pendingJoin=$_pendingJoin');
        setState(() => _isConnected = true);
        _wsConnectAttempts = 0;
        // 服务端就绪后才发送 join，避免 join 早于服务端处理
        if (_pendingJoin) {
          _pendingJoin = false;
          debugPrint('📡 补发 admin_join');
          _sendWsJoin();
        }
        // 检查大屏是否在线
        _checkScreenOnline();
        return;
      }
      if (type == 'pong') return;

      // 大屏主动推送（答错学生信息）
      if (type == 'wrong-answer') {
        // 大屏推送的数据，这里暂不处理（由后端通过 HTTP 通知手机端）
        return;
      }

      // 其他指令型消息（next/prev/jump/show-answer/show-stats等）
      // 已通过 WebSocket 实时推送，不再走 HTTP sendCmd
    } catch (e) {
      debugPrint('处理 WebSocket 消息失败: $e');
    }
  }

  // ==================== 检查大屏是否在线 ====================
  Future<void> _checkScreenOnline() async {
    if (selectedExamId == null) return;
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/explain'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getExplainStatus'}),
      )).body);
      if (mounted && data['success'] == true) {
        setState(() => screenOnline = data['data']?['screenOnline'] as bool? ?? false);
      }
    } catch (e) {
      debugPrint('检查大屏在线状态失败: $e');
    }
  }

  // ==================== 安全过滤：只保留 Map 类型项 ====================
  /// 后端返回 List 时，过滤掉非 Map 脏数据，避免 .cast<Map> 崩溃
  List<Map<String, dynamic>> _safeMapList(dynamic val) {
    if (val is List) {
      return val.whereType<Map>().map((item) => item as Map<String, dynamic>).toList();
    }
    return [];
  }

  // ==================== 加载试卷列表 ====================
  Future<void> _loadExamList() async {
    setState(() => loadingExams = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/exam'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getExamList', 'page': 1, 'limit': 50}),
      )).body);
      if (data['success'] == true && data['list'] != null) {
        setState(() => examList = _safeMapList(data['list']));
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, '加载失败');
    } finally {
      if (mounted) setState(() => loadingExams = false);
    }
  }

  // ==================== 加载题目列表 ====================
  Future<void> _loadQuestions(String examId) async {
    setState(() => loadingQuestions = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/explain'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getExamQuestions', 'examId': examId}),
      )).body);
      if (data['success'] == true && mounted) {
        setState(() {
          questions = _safeMapList(data['data']['questions']);
        });
      } else if (mounted) {
        ToastUtil.show(context, data['msg'] ?? '加载题目失败');
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, '加载题目失败：$e');
    } finally {
      if (mounted) setState(() => loadingQuestions = false);
    }
  }

  // ==================== 开始讲解 ====================
  Future<void> _startExplain() async {
    if (isExplaining || selectedExamId == null) return;
    setState(() => isExplaining = true);

    try {
      // 通过 HTTP 创建 session（这是唯一需要 HTTP 的地方）
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/explain'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'startExplaining', 'examId': selectedExamId}),
      )).body);
      if (data['success'] == true && mounted) {
        final screenOnlineFlag = data['data']?['screenOnline'] as bool? ?? false;
        setState(() {
          currentQIndex = 0;
          showAnswer = false;
          showAnalysis = false;
          showStats = false;
        });
        _connectWs();
        debugPrint('🔌 WS 连接已发起，等待 connected...');
        // 延迟 500ms 后尝试发送 admin_join，确保 WS 连接已建立
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && isExplaining) {
            debugPrint('📡 延迟后尝试发送 admin_join（_isConnected=$_isConnected）');
            _sendWsJoin();
          }
        });
        await _fetchFullQuestion(0);
        // 根据服务端返回的 screenOnline 标志显示提示
        if (screenOnlineFlag) {
          _showFeedback('讲解已开始，大屏已同步');
        } else {
          _showFeedback('讲解已开始，等待大屏连接...');
        }
      } else {
        setState(() => isExplaining = false);
        if (mounted) ToastUtil.show(context, data['msg'] ?? '启动失败');
      }
    } catch (e) {
      setState(() => isExplaining = false);
      if (mounted) ToastUtil.show(context, '启动失败，请检查网络');
    }
  }

  // ==================== 结束讲解 ====================
  Future<void> _endExplain() async {
    final examId = selectedExamId;
    if (examId == null) return;
    // 通过 HTTP 调用 endExplaining，确保服务端 session 可靠清除（不依赖 WS 连接状态）
    try {
      await http.post(
        Uri.parse('$baseUrl/api/explain'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'endExplaining', 'examId': examId}),
      );
    } catch (e) {
      debugPrint('❌ 结束讲解 HTTP 请求失败: $e');
    }
    // 同时尝试通过 WS 发送 endExplaining（如果连接还活着）
    _sendWsCmd('endExplaining', currentQIndex);
    _closeWs();
    if (mounted) {
      setState(() {
        isExplaining = false;
        currentQIndex = 0;
        showAnswer = false;
        showAnalysis = false;
        showStats = false;
        questions = [];
        currentFullQuestion = null;
        selectedExamId = null;
        selectedExamName = null;
      });
      // 重新加载试卷列表，回到初始状态
      _loadExamList();
    }
  }

  // ==================== 发送指令（WS 直发，无 HTTP 依赖） ====================
  void _sendCmd(String cmd, [int? questionIndex, Map<String, dynamic>? extraData]) {
    if (selectedExamId == null) return;
    final qIndex = questionIndex ?? currentQIndex;
    // 连点同指令去重
    final key = '$cmd|$qIndex';
    if (key == _lastDirectCmd) return;
    _lastDirectCmd = key;
    _sendWsCmd(cmd, qIndex, extraData);
  }

  /// 通过 WebSocket 实时发送指令（~20ms 延迟，无 HTTP 往返）
  void _sendWsCmd(String cmd, int qIndex, [Map<String, dynamic>? extraData]) {
    if (_wsChannel == null || !_isConnected) {
      debugPrint('⚠️ WS 未连接，指令未发送: $cmd (channel=${_wsChannel != null}, connected=$_isConnected)');
      return;
    }
    try {
      final msg = {'type': 'cmd', 'cmd': cmd, 'questionIndex': qIndex};
      if (extraData != null) msg.addAll(Map<String, Object>.from(extraData as Map));
      _wsChannel!.sink.add(jsonEncode(msg));
      debugPrint('✅ WS 已发送指令: $cmd, qIndex=$qIndex');
    } catch (e) {
      debugPrint('❌ WS 发送指令失败: $e');
    }
  }

  /// 切换题目时清除快速指令缓存，让下一条指令重新走快速路径
  void _resetFastCmdCache() {
    _lastDirectCmd = null;
  }

  // ==================== 下一题 ====================
  void _nextQuestion() {
    if (currentQIndex >= questions.length - 1) {
      _showFeedback('已是最后一题');
      return;
    }
    final idx = currentQIndex + 1;
    setState(() {
      currentQIndex = idx;
      showAnswer = false;
      showAnalysis = false;
      showStats = false;
      _detailLoading = false; // 立即清除 loading，按钮不阻塞
      _resetFastCmdCache(); // 换题后重置快速指令缓存
    });
    _sendCmd('next', idx);
    _showFeedback('第 ${idx + 1} 题');
    // 后台异步加载，不阻塞 UI
    _loadQuestionInBackground(idx);
  }

  // ==================== 上一题 ====================
  void _prevQuestion() {
    if (currentQIndex <= 0) return;
    final idx = currentQIndex - 1;
    setState(() {
      currentQIndex = idx;
      showAnswer = false;
      showAnalysis = false;
      showStats = false;
      _detailLoading = false;
      _resetFastCmdCache(); // 换题后重置快速指令缓存
    });
    _sendCmd('prev', idx);
    _showFeedback('第 ${idx + 1} 题');
    _loadQuestionInBackground(idx);
  }

  // ==================== 跳转到指定题 ====================
  void _jumpToQuestion(int idx) {
    if (idx == currentQIndex) { Navigator.pop(context); return; }
    setState(() {
      currentQIndex = idx;
      showAnswer = false;
      showAnalysis = false;
      showStats = false;
      _detailLoading = false;
      _resetFastCmdCache(); // 换题后重置快速指令缓存
    });
    _sendCmd('jump', idx);
    _showFeedback('第 ${idx + 1} 题');
    _loadQuestionInBackground(idx);
    if (mounted) Navigator.pop(context);
  }

  // ==================== 后台异步加载题目详情（不阻塞 UI）====================
  Future<void> _loadQuestionInBackground(int index) async {
    if (selectedExamId == null) return;
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/explain'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getQuestionDetail', 'examId': selectedExamId, 'questionIndex': index}),
      )).body);
      if (data['success'] == true && mounted) {
        final d = data['data'] as Map<String, dynamic>?;
        setState(() => currentFullQuestion = d);
        if (isExplaining) _pushQuestionToScreen(index, d);
      }
    } catch (e) {
      debugPrint('后台加载题目失败: $e');
    }
  }

  // ==================== 加载单题完整数据 ====================
  Future<void> _fetchFullQuestion(int index) async {
    if (selectedExamId == null) return;
    setState(() => _detailLoading = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/explain'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getQuestionDetail', 'examId': selectedExamId, 'questionIndex': index}),
      )).body);
      if (data['success'] == true && mounted) {
        final d = data['data'] as Map<String, dynamic>?;
        setState(() {
          currentFullQuestion = d;
          _detailLoading = false;
        });
        // 主动将题目数据推送给大屏，防止时序问题导致大屏不同步
        if (isExplaining) {
          _pushQuestionToScreen(index, d);
        }
      } else if (mounted) {
        setState(() => _detailLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _detailLoading = false);
    }
  }

  // ==================== 推送题目给大屏（WS 直发） ====================
  void _pushQuestionToScreen(int index, Map<String, dynamic>? question) {
    if (question == null || selectedExamId == null) return;
    // 直接走 WS，不等 HTTP 往返
    _sendWsCmd('question', index, {
      'examName': selectedExamName ?? '',
      'totalQuestions': questions.length,
      'question': question,
    });
  }

  // ==================== 加载统计（带缓存 + 防并发） ====================
  Future<void> _loadStats() async {
    if (selectedExamId == null) return;
    final cacheKey = '${selectedExamId}_$currentQIndex';
    // 命中缓存直接返回，避免同题重复请求
    if (_statsCache.containsKey(cacheKey)) {
      final pairs = _statsCache[cacheKey]!;
      setState(() {
        correctUsers = pairs[0];
        wrongUsers = pairs[1];
        activeStatsTab = 'correct';
      });
      return;
    }
    if (_statsInflight.contains(cacheKey)) return;
    _statsInflight.add(cacheKey);
    setState(() => loadingStats = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/explain'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'getQuestionStats', 'examId': selectedExamId, 'questionIndex': currentQIndex}),
      )).body);
      if (data['success'] == true && mounted) {
        final d = data['data'] as Map<String, dynamic>? ?? {};
        final correct = _safeMapList(d['correctUsers']);
        final wrong = _safeMapList(d['wrongUsers']);
        _statsCache[cacheKey] = [correct, wrong];
        setState(() {
          correctUsers = correct;
          wrongUsers = wrong;
          activeStatsTab = 'correct';
        });
      }
    } catch (e) {
      debugPrint('加载统计失败: $e');
    } finally {
      _statsInflight.remove(cacheKey);
      if (mounted) setState(() => loadingStats = false);
    }
  }

  // ==================== 切换答案显隐 ====================
  Future<void> _toggleAnswer(bool show) async {
    setState(() => showAnswer = show);
    _sendCmd(show ? 'show-answer' : 'hide-answer', currentQIndex);
    _showFeedback(show ? '已显示答案' : '已隐藏答案');
  }

  // ==================== 切换解析显隐 ====================
  Future<void> _toggleAnalysis(bool show) async {
    setState(() => showAnalysis = show);
    _sendCmd(show ? 'show-analysis' : 'hide-analysis', currentQIndex);
    _showFeedback(show ? '已显示解析' : '已隐藏解析');
  }

  // ==================== 切换统计显隐（乐观响应） ====================
  Future<void> _toggleStats(bool show) async {
    // 立即响应 UI，不等网络；缓存命中的话 _loadStats 也会瞬间完成
    if (show) await _loadStats();
    setState(() => showStats = show);
    final extraData = show
        ? {'correctUsers': correctUsers, 'wrongUsers': wrongUsers}
        : null;
    // 直接调用 _sendCmd 把指令插入队列头，确保 show-stats 紧跟当前操作
    if (show) {
      _sendCmd('show-stats', currentQIndex, extraData);
    } else {
      _sendCmd('hide-stats', currentQIndex, null);
    }
    _showFeedback(show ? '已显示答题统计' : '已隐藏统计');
  }

  // ==================== 查看答错学生原始答案 ====================
  Future<void> _showWrongAnswerDetail(Map<String, dynamic> user) async {
    final account = user['account'] ?? '';
    final remark = (user['remark'] ?? '').toString();
    final userAnswer = (user['userAnswer'] ?? '').toString();
    final displayName = remark.isNotEmpty ? '$account ($remark)' : account;
    _sendCmd('wrong-answer', currentQIndex, {'account': displayName, 'userAnswer': userAnswer});
    if (mounted) _showWrongAnswerModal({'account': displayName, 'userAnswer': userAnswer});
  }

  // ==================== 反馈提示 ====================
  void _showFeedback(String msg) {
    setState(() => feedbackMsg = msg);
    feedbackTimer?.cancel();
    feedbackTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => feedbackMsg = '');
    });
  }

  // ==================== 阶段1：试卷选择界面 ====================
  Widget _buildExamSelection() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('讲解中心', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1a1a2e),
      ),
      body: loadingExams
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF667eea)))
          : examList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.assignment_outlined, size: 64, color: Color(0xFFcccccc)),
                      SizedBox(height: 16),
                      Text('暂无已发布试卷', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      '选择试卷开始讲解',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1a1a2e)),
                    ),
                    const SizedBox(height: 12),
                    ...examList.map((exam) {
                      final examId = exam['examId'] as String?;
                      final examName = exam['examName'] as String? ?? '未命名试卷';
                      final createTime = exam['createTime'] as String? ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            if (examId == selectedExamId) return;
                            setState(() {
                              selectedExamId = examId;
                              selectedExamName = examName;
                            });
                            _loadQuestions(examId!);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selectedExamId == examId ? const Color(0xFF667eea) : Colors.grey.shade200,
                                width: selectedExamId == examId ? 2 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: selectedExamId == examId
                                      ? const Color(0xFF667eea).withValues(alpha: 0.12)
                                      : Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: selectedExamId == examId ? const Color(0xFF667eea) : const Color(0xFFF0F0FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.assignment,
                                    color: selectedExamId == examId ? Colors.white : const Color(0xFF667eea),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        examName,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: selectedExamId == examId ? const Color(0xFF667eea) : const Color(0xFF1a1a2e),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        createTime.isNotEmpty ? '创建于 ${_fmtTime(createTime)}' : '',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selectedExamId == examId)
                                  const Icon(Icons.check_circle, color: Color(0xFF667eea), size: 24),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF667eea),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: loadingQuestions || selectedExamId == null ? null : _startExplain,
                        child: loadingQuestions
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('开始讲解', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                    if (loadingQuestions)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Center(child: Text('正在加载题目...', style: TextStyle(color: Colors.grey, fontSize: 13))),
                      ),
                  ],
                ),
    );
  }

  // ==================== 阶段2：讲解遥控界面 ====================
  Widget _buildRemoteControl() {
    final fullQ = currentFullQuestion;
    final summaryQ = questions.isNotEmpty ? questions[currentQIndex] : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(selectedExamName ?? '讲解中', style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1a1a2e),
        leading: IconButton(
          icon: const Icon(Icons.grid_view),
          tooltip: '答题卡',
          onPressed: () => _showAnswerSheetDialog(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => showDialog(context: context, builder: (_) => _buildEndDialog()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Text('结束', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2))],
                      ),
                      child: _detailLoading
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFF667eea)))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(color: const Color(0xFF667eea), borderRadius: BorderRadius.circular(8)),
                                      child: Text('第 ${currentQIndex + 1} 题', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                    ),
                                    const Spacer(),
                                    if (fullQ != null || summaryQ != null) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: const Color(0xFFF0F0FF), borderRadius: BorderRadius.circular(6)),
                                        child: Text(_typeLabel(fullQ?['type'] ?? summaryQ?['type'] ?? ''), style: const TextStyle(fontSize: 12, color: Color(0xFF667eea), fontWeight: FontWeight.w500)),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(6)),
                                        child: Text('${fullQ?['score'] ?? summaryQ?['score'] ?? 0}分', style: const TextStyle(fontSize: 12, color: Color(0xFFB8860B), fontWeight: FontWeight.w500)),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                          child: FormulaRenderer.renderMixedText(
                            fullQ?['title'] ?? summaryQ?['title'] ?? '题目加载中...',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1a1a2e), height: 1.5),
                          ),
                        );
                      },
                    ),
                    if ((fullQ?['imgUrl'] ?? summaryQ?['imgUrl']) != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          '${(fullQ?['imgUrl'] ?? summaryQ?['imgUrl'] ?? '').startsWith('http') ? '' : Config.baseUrl}${fullQ?['imgUrl'] ?? summaryQ?['imgUrl']}',
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Container(
                            height: 120,
                            color: Colors.grey.shade100,
                            child: const Center(child: Text('图片加载失败', style: TextStyle(color: Colors.grey))),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (fullQ != null && (fullQ['options'] as List?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      const Text('选项', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1a1a2e))),
                      const SizedBox(height: 10),
                      ...['A', 'B', 'C', 'D', 'E', 'F'].asMap().entries.map((entry) {
                        final label = entry.value;
                        final idx = entry.key;
                        final opts = fullQ['options'] as List?;
                        final opt = (opts != null && idx < opts.length) ? opts[idx] : null;
                        if (opt == null || opt.toString().isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(color: const Color(0xFFF0F0FF), borderRadius: BorderRadius.circular(8)),
                                alignment: Alignment.center,
                                child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF667eea))),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (ctx, constraints) {
                                    return ConstrainedBox(
                                      constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                      child: FormulaRenderer.renderMixedText(
                                        opt.toString(),
                                        style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    if (showAnswer && fullQ != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2))]),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('答案', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1a1a2e))),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (ctx, constraints) {
                                return ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                  child: FormulaRenderer.renderMixedText(
                                    (fullQ['standardAnswer'] ?? fullQ['answer'] ?? '').toString(),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF2e7d32)),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (showAnalysis && fullQ != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2))]),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('解析', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1a1a2e))),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (ctx, constraints) {
                                return ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                  child: FormulaRenderer.renderMixedText(
                                    fullQ['analysis'] ?? '',
                                    style: const TextStyle(fontSize: 14, color: Color(0xFF555555), height: 1.6),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (showStats) ...[
                      _buildStatsCard(),
                      const SizedBox(height: 140),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          onPressed: _prevQuestion,
                          child: const Text('上一题', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF667eea),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: _nextQuestion,
                          child: const Text('下一题', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildToggleRow(),
                ],
              ),
            ),
          ),
          if (feedbackMsg.isNotEmpty)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFF1a1a2e), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  feedbackMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 题型中文化 ====================
  String _typeLabel(String type) {
    const map = {'single': '单选题', 'multi': '多选题', 'fill': '填空题', 'short': '简答题'};
    return map[type] ?? type;
  }

  // ==================== 显示控制行 ====================
  Widget _buildToggleRow() {
    return Row(
      children: [
        Expanded(child: _buildToggleBtn('答案', showAnswer, Colors.green, () => _toggleAnswer(!showAnswer))),
        const SizedBox(width: 12),
        Expanded(child: _buildToggleBtn('解析', showAnalysis, Colors.blue, () => _toggleAnalysis(!showAnalysis))),
        const SizedBox(width: 12),
        Expanded(child: _buildToggleBtn('统计', showStats, Colors.orange, () => _toggleStats(!showStats))),
      ],
    );
  }

  Widget _buildToggleBtn(String label, bool on, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: on ? color.withValues(alpha: 0.1) : const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? color : Colors.grey.shade200, width: on ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(on ? Icons.check_circle : Icons.circle_outlined, size: 22, color: on ? color : Colors.grey.shade400),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? color : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  // ==================== 统计卡片 ====================
  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatChip('答对', correctUsers.length, Colors.green),
              const SizedBox(width: 10),
              _buildStatChip('答错', wrongUsers.length, Colors.red),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  // 刷新时清除缓存，强制重新请求
                  final cacheKey = '${selectedExamId}_$currentQIndex';
                  _statsCache.remove(cacheKey);
                  await _loadStats();
                  // _loadStats 完成后数据已在 correctUsers/wrongUsers 中，直接同步大屏
                  if (showStats) {
                    _sendCmd('show-stats', currentQIndex, {
                      'correctUsers': correctUsers,
                      'wrongUsers': wrongUsers,
                    });
                  }
                },
                child: const Text('刷新', style: TextStyle(fontSize: 13, color: Color(0xFF667eea))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Tab 切换
          Row(
            children: [
              _buildStatTab('答对', 'correct', Colors.green),
              const SizedBox(width: 8),
              _buildStatTab('答错', 'wrong', Colors.red),
            ],
          ),
          if (loadingStats)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (activeStatsTab == 'correct')
            ..._buildUserList(correctUsers, false)
          else
            ..._buildUserList(wrongUsers, true),
        ],
      ),
    );
  }

  Widget _buildStatTab(String label, String key, Color color) {
    final isActive = activeStatsTab == key;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() => activeStatsTab = key);
          _sendCmd('switch-tab', currentQIndex, {'tab': key});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? color : Colors.grey.shade200),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? color : Colors.grey.shade600)),
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text('$label $count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    );
  }

  List<Widget> _buildUserList(List<Map<String, dynamic>> users, bool isWrong) {
    if (users.isEmpty) {
      return [const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('暂无数据', style: TextStyle(fontSize: 13, color: Colors.grey))))];
    }
    return users.map((u) {
      final account = u['account'] ?? '';
      final remark = (u['remark'] ?? '').toString();
      final display = remark.isNotEmpty ? '$account ($remark)' : account;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Expanded(
                child: Text(display, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1a1a2e))),
              ),
              if (isWrong)
                TextButton(
                  onPressed: () => _showWrongAnswerDetail(u),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('查看', style: TextStyle(fontSize: 12, color: Color(0xFF667eea))),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // ==================== 答错学生原始答案弹窗 ====================
  void _showWrongAnswerModal(Map<String, dynamic> info) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text('${info['account'] ?? '学生'} 的原始作答', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1a1a2e)))),
          ],
        ),
        content: _loadingWrongDetail
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            : LayoutBuilder(
                builder: (ctx, constraints) {
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: FormulaRenderer.renderMixedText(
                      info['userAnswer'] ?? '',
                      style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
                    ),
                  );
                },
              ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _sendCmd('hide-wrong-answer', currentQIndex);
            },
            child: const Text('关闭', style: TextStyle(color: Color(0xFF667eea))),
          ),
        ],
      ),
    );
  }

  // ==================== 答题卡弹窗 ====================
  void _showAnswerSheetDialog(BuildContext context) {
    // 按题型分组（英文转中文）
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (var q in questions) {
      final type = _typeLabel((q['type'] ?? '其他').toString().replaceAll(RegExp(r'[（）\(\)]'), ''));
      groups.putIfAbsent(type, () => []).add(q);
    }
    // 中文题型排序
    const typeOrder = ['单选题', '多选题', '填空题', '简答题', '计算题', '证明题', '解答题'];
    final orderedTypes = typeOrder.where((t) => groups.containsKey(t)).toList();
    for (var entry in groups.entries) {
      if (!typeOrder.contains(entry.key) && !orderedTypes.contains(entry.key)) {
        orderedTypes.add(entry.key);
      }
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxHeight: 600),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(color: Color(0xFF667eea), borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
                child: Row(
                  children: const [
                    Icon(Icons.view_list, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('答题卡', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              // 内容区
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: orderedTypes.isEmpty
                        ? [const Center(child: Text('暂无题目数据', style: TextStyle(color: Colors.grey)))]
                        : orderedTypes.map((type) {
                            final items = groups[type] ?? [];
                            if (items.isEmpty) return const SizedBox.shrink();
                            // 计算题号区间
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(type, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF667eea))),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: items.map((q) {
                                      final qIdx = q['index'] as int? ?? 0;
                                      final isSelected = qIdx == currentQIndex;
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () => _jumpToQuestion(qIdx),
                                        child: Container(
                                          width: 44,
                                          height: 32,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isSelected ? const Color(0xFF667eea) : Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: isSelected ? const Color(0xFF667eea) : Colors.grey.shade300),
                                          ),
                                          child: Text(
                                            '${qIdx + 1}',
                                            style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? Colors.white : const Color(0xFF333333)),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                  ),
                ),
              ),
              // 关闭按钮
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('关闭', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 结束确认弹窗 ====================
  Widget _buildEndDialog() {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      title: const Text('结束讲解', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1a1a2e))),
      content: const Text('确定要结束当前讲解吗？大屏将恢复为"暂无讲解"。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Color(0xFF667eea)))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () { Navigator.pop(context); _endExplain(); },
          child: const Text('确认结束', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ==================== 构建页面 ====================
  @override
  Widget build(BuildContext context) {
    return isExplaining ? _buildRemoteControl() : _buildExamSelection();
  }
}

