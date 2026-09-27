import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/ui_helpers.dart';

class SignManagePage extends StatefulWidget {
  const SignManagePage({super.key});

  @override
  State<SignManagePage> createState() => _SignManagePageState();
}

class _SignManagePageState extends State<SignManagePage> {
  final String baseUrl = Config.baseUrl;

  bool showCreateSign = false;
  bool showSignHistory = false;
  bool signRunning = false;
  bool signEnded = false;

  String signType = 'code';
  String signCode = '';
  int countdown = 60;
  String subject = '语文';
  String title = '';
  int leftTime = 0;

  // 本地平滑倒计时（解决5秒轮询导致的迟钝感）
  int _localLeftTime = 0;
  Timer? _localTickTimer;
  // 用于校准的起点偏移（服务器时间 vs 客户端时间差）
  int _leftTimeAnchor = 0;
  DateTime? _anchorTime;

  // 用 Map 存储避免列表整体替换导致的闪烁
  Map<String, String> _signedMap = {};
  Map<String, String> _unsignedMap = {};
  List<String> signedList = [];
  List<String> unsignedList = [];

  String historySubject = '语文';
  List allHistoryList = [];
  List filteredList = [];
  final ScrollController historyScrollController = ScrollController();
  double historyScrollOffset = 0;

  bool showClearPanel = false;
  bool clearMode = false;
  List<String> selectedSubjects = [];
  List<String> allSubjects = [];
  List<String> knownSubjects = ['语文', '数学', '英语', '其他'];

  Timer? pollTimer;

  @override
  void initState() {
    super.initState();
    openCreateSign();
  }

  @override
  void dispose() {
    stopPoll();
    _localTickTimer?.cancel();
    historyScrollController.dispose();
    super.dispose();
  }

  void closeAll() {
    _stopLocalTick();
    setState(() {
      showSignHistory = false;
      signRunning = false;
      signEnded = false;
    });
  }

  /// 启动本地倒计时 tick（每秒更新 UI，不依赖网络）
  void _startLocalTick(int startLeftTime) {
    _stopLocalTick();
    _leftTimeAnchor = startLeftTime;
    _anchorTime = DateTime.now();
    _localLeftTime = startLeftTime;
    _localTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_anchorTime!).inSeconds;
      final remaining = (_leftTimeAnchor - elapsed).clamp(0, 999999);
      if (remaining != _localLeftTime) {
        setState(() => _localLeftTime = remaining);
      }
    });
  }

  void _stopLocalTick() {
    _localTickTimer?.cancel();
    _localTickTimer = null;
    _anchorTime = null;
  }

  /// 增量同步：只更新变化的部分，避免列表闪烁
  void _syncSignedUnsigned(List dynamicList, bool isSigned) {
    final newMap = <String, String>{};
    for (final item in dynamicList) {
      if (item is String) {
        newMap[item] = item;
      } else if (item is Map) {
        final name = item['name'] ?? item['account'] ?? '';
        if (name.isNotEmpty) newMap[name] = name;
      }
    }
    if (isSigned) {
      final oldMap = _signedMap;
      // 检测新增
      for (final entry in newMap.entries) {
        if (!oldMap.containsKey(entry.key)) {
          setState(() => signedList.add(entry.value));
        }
      }
      // 检测移除（理论上不会移除已签到的人）
      for (final name in oldMap.keys) {
        if (!newMap.containsKey(name)) {
          setState(() => signedList.remove(name));
        }
      }
      _signedMap = newMap;
    } else {
      final oldMap = _unsignedMap;
      for (final entry in newMap.entries) {
        if (!oldMap.containsKey(entry.key)) {
          setState(() => unsignedList.add(entry.value));
        }
      }
      for (final name in oldMap.keys) {
        if (!newMap.containsKey(name)) {
          setState(() => unsignedList.remove(name));
        }
      }
      _unsignedMap = newMap;
    }
  }

  Future<void> openCreateSign() async {
    final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'status'}),
      )).body);
    if (res['success'] == true && res['data'] != null) {
      final d = res['data'];
      if (d['running'] == true) {
        final lt = (d['leftTime'] as num?)?.toInt() ?? 0;
        setState(() {
          signRunning = true;
          signEnded = false;
          leftTime = lt;
          _localLeftTime = lt;
          _leftTimeAnchor = lt;
          _anchorTime = DateTime.now();
          subject = d['subject'] ?? '语文';
          title = d['title'] ?? '';
          signedList = List<String>.from(d['signedList'] ?? []);
          unsignedList = List<String>.from(d['unsignedList'] ?? []);
          _signedMap = {};
          for (final s in signedList) {
            _signedMap[s] = s;
          }
          _unsignedMap = {};
          for (final u in unsignedList) {
            _unsignedMap[u] = u;
          }
        });
        _startLocalTick(lt);
        startPoll();
        return;
      }
      if (d['running'] == false && d['closed'] == false) {
        setState(() {
          signRunning = true;
          signEnded = true;
          leftTime = 0;
          _localLeftTime = 0;
          signedList = List<String>.from(d['signedList'] ?? []);
          unsignedList = List<String>.from(d['unsignedList'] ?? []);
          _signedMap = {};
          for (final s in signedList) {
            _signedMap[s] = s;
          }
          _unsignedMap = {};
          for (final u in unsignedList) {
            _unsignedMap[u] = u;
          }
          subject = d['subject'] ?? '';
          title = d['title'] ?? '';
          final sub = d['subject'] as String?;
          if (sub != null && sub.isNotEmpty && !knownSubjects.contains(sub)) knownSubjects.add(sub);
        });
        return;
      }
    }
    _stopLocalTick();
    setState(() {
      signCode = '';
      title = '';
      countdown = 60;
      leftTime = 0;
      _localLeftTime = 0;
    });
  }

  Future<void> openSignHistory() async {
    closeAll();
    setState(() => showSignHistory = true);
    final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'history'}),
      )).body);
    if (res['success'] == true) {
      final historyData = res['data'] ?? [];
      setState(() {
        allHistoryList = historyData;
        filteredList = historyData
            .where((item) => (item['subject'] ?? '其他') == historySubject)
            .toList();
      });
      _fetchHistorySubjects(historyData);
    }
  }

  Future<void> _fetchHistorySubjects(List data) async {
    final subjects = <String>{};
    for (final item in data) {
      final s = item['subject'] ?? '其他';
      if (s.isNotEmpty) subjects.add(s);
    }
    if (subjects.isEmpty) subjects.add('语文');
    setState(() => allSubjects = subjects.toList());
  }

  void openClearPanel() {
    setState(() => selectedSubjects = []);
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _buildClearPanel(),
    );
  }

  void _closeClearDialog() {
    Navigator.pop(context);
    setState(() => showClearPanel = false);
  }

  Future<void> confirmClearHistory() async {
    _closeClearDialog();
    final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        'action': 'clearHistory',
        'subjects': clearMode ? [] : selectedSubjects,
      }),
      )).body);
    if (res['success'] == true) {
      if (!mounted) return;
      ToastUtil.showSuccess(context, '清除成功');
      await openSignHistory();
    } else {
      if (!mounted) return;
      ToastUtil.showError(context, res['message'] ?? '清除失败');
    }
  }

  Widget _buildClearPanel() {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('清除签到历史'),
      content: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择操作类型：',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildClearOptionChip(
                      '全部清除',
                      clearMode,
                      () => setS(() => clearMode = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildClearOptionChip(
                      '部分清除',
                      !clearMode,
                      () => setS(() => clearMode = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (!clearMode) ...[
                const Text('选择要清除的科目（可多选）：',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: knownSubjects.map((s) {
                    final selected = selectedSubjects.contains(s);
                    return GestureDetector(
                      onTap: () => setS(() {
                        if (selected) {
                          selectedSubjects.remove(s);
                        } else {
                          selectedSubjects.add(s);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? UIHelpers.primaryColor
                              : Colors.grey.shade200,
                          borderRadius:
                              BorderRadius.circular(UIHelpers.radiusMedium),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              selected ? Icons.check_circle : Icons.circle_outlined,
                              size: 18,
                              color: selected
                                  ? Colors.white
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(s,
                                style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.black87)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
                if (selectedSubjects.isNotEmpty)
                  Text('已选 ${selectedSubjects.length} 个科目',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _closeClearDialog(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            if (clearMode) {
              confirmClearHistory();
            } else if (selectedSubjects.isNotEmpty) {
              showDialog(
                context: context,
                barrierColor: Colors.black54,
                builder: (_) => _buildConfirmClearDialog(),
              );
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: UIHelpers.primaryColor),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildConfirmClearDialog() {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('确认清除'),
      content: Text(
        '确定要清除【${selectedSubjects.join('、')}】的历史签到记录吗？此操作不可恢复。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: confirmClearHistory,
          style: ElevatedButton.styleFrom(backgroundColor: UIHelpers.errorColor),
          child: const Text('确认清除'),
        ),
      ],
    );
  }

  Widget _buildClearOptionChip(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? UIHelpers.primaryColor : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
        ),
        child: Center(
          child: Text(text,
              style: TextStyle(
                  color: active ? Colors.white : Colors.black87,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }

  Future<void> startSign() async {
    if (signType == 'code' && signCode.isEmpty) {
      ToastUtil.show(context, '请输入4位口令');
      return;
    }
    if (countdown <= 0) {
      ToastUtil.show(context, '倒计时必须大于0');
      return;
    }
    final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        'action': 'create',
        'type': signType,
        'code': signCode,
        'time': countdown,
        'subject': subject,
        'title': title,
      }),
      )).body);
    if (res['success'] == true) {
      closeAll();
      _stopLocalTick();
      final lt = countdown;
      setState(() {
        signRunning = true;
        signEnded = false;
        leftTime = lt;
        _localLeftTime = lt;
        _leftTimeAnchor = lt;
        _anchorTime = DateTime.now();
        signedList = [];
        unsignedList = [];
        _signedMap = {};
        _unsignedMap = {};
      });
      _startLocalTick(lt);
      startPoll();
    }
  }

  void startPoll() {
    stopPoll();
    // 从5秒缩短到2秒，减少倒计时更新延迟
    pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'status'}),
      )).body);
        if (res['success'] != true) {
          stopPoll();
          return;
        }
        final d = res['data'];
        final lt = (d['leftTime'] as num?)?.toInt() ?? 0;
        final wasRunning = d['running'] == true;

        setState(() {
          // 服务器倒计时校准（仅在差值>2秒时修正，避免每轮都重置本地 tick）
          if (wasRunning && _anchorTime != null) {
            final drift = _localLeftTime - lt;
            if (drift.abs() > 2) {
              _leftTimeAnchor = lt;
              _anchorTime = DateTime.now();
              _localLeftTime = lt;
            }
          }
          leftTime = lt;
          // 增量同步 signed/unsigned 列表，避免整体替换闪烁
          if (wasRunning) {
            _syncSignedUnsigned(d['signedList'] ?? [], true);
            _syncSignedUnsigned(d['unsignedList'] ?? [], false);
          }
          if (!wasRunning) {
            // 签到结束：停止本地 tick，使用服务器数据填充
            _stopLocalTick();
            signEnded = true;
            signedList = List<String>.from(d['signedList'] ?? []);
            unsignedList = List<String>.from(d['unsignedList'] ?? []);
            _signedMap = {};
            for (final s in signedList) {
              _signedMap[s] = s;
            }
            _unsignedMap = {};
            for (final u in unsignedList) {
              _unsignedMap[u] = u;
            }
            stopPoll();
          }
        });
      } catch (e) {
        debugPrint("⚠️ signmanage poll error: $e");
        stopPoll();
      }
    });
  }

  void stopPoll() {
    if (pollTimer != null) {
      pollTimer!.cancel();
      pollTimer = null;
    }
  }

  Future<void> stopSign() async {
    await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'stop'}),
      )).body);
    stopPoll();
    _stopLocalTick();
    setState(() => signEnded = true);
  }

  Future<void> closeSignPanel() async {
    await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'action': 'close'}),
      )).body);
    stopPoll();
    _stopLocalTick();
    closeAll();
  }

  void openSignDetail(Map<String, dynamic> item) {
    historyScrollOffset = historyScrollController.offset;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _buildDetailDialog(item),
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (historyScrollController.hasClients) {
          historyScrollController.animateTo(
            historyScrollOffset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1890FF), Color(0xFF096DD9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _glassBackBtn(),
                    const Text('签到点名',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    if (showSignHistory)
                      _glassDangerBtn('清除', () => openClearPanel())
                    else
                      const SizedBox(width: 56),
                  ],
                ),
              ),
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 玻璃质感控件 ───────────────────────────────────────

  Widget _glassBackBtn() {
    return InkWell(
      onTap: () => Navigator.pop(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Text('返回',
            style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
    );
  }

  Widget _glassDangerBtn(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: UIHelpers.errorColor.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    );
  }

  Widget _buildContent() {
    if (signRunning) return _buildRunningPanel();

    final modeCards = Row(
      children: [
        Expanded(
          child: _buildModeCard(
            title: '现场点名',
            subtitle: '发起签到',
            icon: Icons.qr_code_scanner,
            isActive: !showSignHistory,
            onTap: () => setState(() => showSignHistory = false),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildModeCard(
            title: '历史签到',
            subtitle: '记录查看',
            icon: Icons.history,
            isActive: showSignHistory,
            onTap: showSignHistory ? () {} : openSignHistory,
          ),
        ),
      ],
    );

    if (!showSignHistory) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 12),
              modeCards,
              const SizedBox(height: 12),
              _buildCreatePanel(),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          modeCards,
          const SizedBox(height: 8),
          Expanded(child: _buildHistoryPanel()),
        ],
      ),
    );
  }

  // 模式切换卡片（玻璃质感）
  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive
                ? [
                    UIHelpers.primaryColor.withValues(alpha: 0.85),
                    UIHelpers.primaryColor.withValues(alpha: 0.6),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.06),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? UIHelpers.primaryColor.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: isActive ? 12 : 8,
              offset: Offset(0, isActive ? 5 : 3),
            ),
            // 顶部高光
            BoxShadow(
              color: Colors.white.withValues(alpha: isActive ? 0.15 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 顶部光泽渐变条
            Positioned(
              top: 0, left: 0, right: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Container(
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: isActive ? 0.20 : 0.08),
                        Colors.white.withValues(alpha: isActive ? 0.05 : 0.01),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.75),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 创建签到面板（玻璃质感）
  Widget _buildCreatePanel() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.14),
            Colors.white.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('签到方式',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildChip('二维码', signType == 'qrcode',
                  () => setState(() => signType = 'qrcode')),
              const SizedBox(width: 10),
              _buildChip('4位口令', signType == 'code',
                  () => setState(() => signType = 'code')),
            ],
          ),
          const SizedBox(height: 16),
          const Text('科目',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['语文', '数学', '英语', '其他']
                .map((s) => _buildChip(s, subject == s,
                    () => setState(() {
                          subject = s;
                          if (!knownSubjects.contains(s)) knownSubjects.add(s);
                        })))
                .toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => title = v,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: '标题（选填）',
              hintStyle: TextStyle(color: Colors.grey.shade600),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          if (signType == 'code')
            TextField(
              onChanged: (v) => signCode = v,
              maxLength: 4,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                  color: Colors.black87, letterSpacing: 4),
              decoration: InputDecoration(
                hintText: '4位口令',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => countdown = int.tryParse(v) ?? 60,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: '倒计时（秒）',
              hintStyle: TextStyle(color: Colors.grey.shade600),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: startSign,
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('开始签到',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: UIHelpers.warningColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 2,
              minimumSize: const Size(double.infinity, 0),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // 运行中的签到面板（玻璃质感 + 平滑倒计时）
  Widget _buildRunningPanel() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部标题栏（玻璃质感）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('签到进行中',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  if (!signEnded)
                    _glassDangerBtn('结束', stopSign)
                  else
                    _glassBackBtn2('关闭', closeSignPanel),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 信息卡片（玻璃质感）
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _iconChip(Icons.book, Colors.white.withValues(alpha: 0.9), 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$subject 课堂签到',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _iconChip(Icons.title, Colors.yellowAccent.withValues(alpha: 0.9), 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                                color: Colors.yellowAccent, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  // 倒计时行（本地平滑更新 + 进度条）
                  Row(
                    children: [
                      _iconChip(Icons.timer, Colors.white.withValues(alpha: 0.9), 18),
                      const SizedBox(width: 8),
                      Text('倒计时：',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: _localLeftTime <= 10
                              ? UIHelpers.errorColor.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_localLeftTime 秒',
                          style: TextStyle(
                            color: _localLeftTime <= 10
                                ? UIHelpers.errorColor
                                : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (!signEnded) _buildProgressChip(),
                    ],
                  ),
                  if (!signEnded) const SizedBox(height: 10),
                  if (!signEnded) _buildCountdownBar(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _iconChip(Icons.people, Colors.white.withValues(alpha: 0.9), 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '已签：${signedList.length} / 未签：${unsignedList.length}',
                          style: TextStyle(
                            color: signedList.length > unsignedList.length
                                ? UIHelpers.successColor
                                : UIHelpers.warningColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (signedList.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.check_circle,
                      color: UIHelpers.successColor, size: 20),
                  const SizedBox(width: 8),
                  Text('已签到 (${signedList.length})',
                      style: TextStyle(
                          color: UIHelpers.successColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: signedList
                    .map((e) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: UIHelpers.successColor
                                .withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(10),
                            border: Border.all(
                                color: UIHelpers.successColor
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Text(e.toString(),
                              style: TextStyle(
                                  color: UIHelpers.successColor,
                                  fontSize: 13)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
            if (unsignedList.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.cancel,
                      color: UIHelpers.errorColor, size: 20),
                  const SizedBox(width: 8),
                  Text('未签到 (${unsignedList.length})',
                      style: TextStyle(
                          color: UIHelpers.errorColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: unsignedList
                    .map((e) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: UIHelpers.errorColor
                                .withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(10),
                            border: Border.all(
                                color: UIHelpers.errorColor
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Text(e.toString(),
                              style: TextStyle(
                                  color: UIHelpers.errorColor,
                                  fontSize: 13)),
                        ))
                    .toList(),
              ),
            ],
            if (signedList.isEmpty && unsignedList.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text('等待学生签到...',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _iconChip(IconData icon, Color color, double size) {
    return Icon(icon, color: color, size: size);
  }

  Widget _buildProgressChip() {
    final total = signedList.length + unsignedList.length;
    if (total == 0) return const SizedBox.shrink();
    final rate = ((signedList.length / total) * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$rate%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
    );
  }

  Widget _buildCountdownBar() {
    final total = countdown;
    if (total <= 0) return const SizedBox.shrink();
    final remaining = _localLeftTime;
    final progress = (remaining / total).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Container(
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: progress > 0.3
                      ? [UIHelpers.successColor, UIHelpers.successColor.withValues(alpha: 0.7)]
                      : [UIHelpers.errorColor, UIHelpers.errorColor.withValues(alpha: 0.7)],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _glassBackBtn2(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    );
  }

  // 历史签到面板（玻璃质感）
  Widget _buildHistoryPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 科目标签行（玻璃质感固定头部）
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Text(
                '科目：',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['语文', '数学', '英语', '其他']
                    .map((s) => _buildChip(s, historySubject == s, () {
                          setState(() => historySubject = s);
                          filteredList = allHistoryList
                              .where((item) =>
                                  (item['subject'] ?? '其他') == s)
                              .toList();
                        }))
                    .toList(),
              ),
            ],
          ),
        ),
        // 滚动记录列表
        Flexible(
          child: SingleChildScrollView(
            controller: historyScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (filteredList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('暂无签到记录',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14)),
                    ),
                  )
                else
                  ...filteredList.map((item) {
                    final signedCount = item['signedList']?.length ?? 0;
                    final totalCount = item['allStudents']?.length ?? 0;
                    final rate = totalCount > 0
                        ? (signedCount / totalCount * 100).round()
                        : 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item['title'] ?? '未命名签到',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => openSignDetail(item),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: UIHelpers.primaryColor
                                      .withValues(alpha: 0.2),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                child: const Text('详情',
                                    style: TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(item['subject'] ?? '',
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 13)),
                              const SizedBox(width: 12),
                              Text('$signedCount/$totalCount',
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 13)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: rate >= 80
                                      ? UIHelpers.successColor
                                          .withValues(alpha: 0.2)
                                      : (rate >= 60
                                          ? UIHelpers.warningColor
                                              .withValues(alpha: 0.2)
                                          : UIHelpers.errorColor
                                              .withValues(alpha: 0.2)),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$rate%',
                                  style: TextStyle(
                                    color: rate >= 80
                                        ? UIHelpers.successColor
                                        : (rate >= 60
                                            ? UIHelpers.warningColor
                                            : UIHelpers.errorColor),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 居中弹窗：显示签到详情（玻璃质感）
  Widget _buildDetailDialog(Map<String, dynamic> item) {
    final signedList = item['signedList'] ?? [];
    final unsignedList = item['unsignedList'] ?? [];
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1890FF), Color(0xFF096DD9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部导航栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _dialogBackBtn(() => Navigator.pop(context)),
                  const Spacer(),
                  const Text('签到详情',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 信息卡片
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    _iconChip(Icons.book, Colors.white.withValues(alpha: 0.9), 18),
                    const SizedBox(width: 8),
                    Text(item['subject'] ?? '',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    const SizedBox(width: 16),
                    _iconChip(Icons.title, Colors.white.withValues(alpha: 0.9), 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item['title'] ?? '未命名签到',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 已签到列表
            if (signedList.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: UIHelpers.successColor, size: 18),
                    const SizedBox(width: 6),
                    Text('已签到 (${signedList.length})',
                        style: TextStyle(
                            color: UIHelpers.successColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: signedList
                      .map<Widget>((e) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: UIHelpers.successColor
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: UIHelpers.successColor
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Text(e.toString(),
                                style: TextStyle(
                                    color: UIHelpers.successColor,
                                    fontSize: 12)),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
            // 未签到列表
            if (unsignedList.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.cancel,
                        color: UIHelpers.errorColor, size: 18),
                    const SizedBox(width: 6),
                    Text('未签到 (${unsignedList.length})',
                        style: TextStyle(
                            color: UIHelpers.errorColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: unsignedList
                      .map<Widget>((e) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: UIHelpers.errorColor
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: UIHelpers.errorColor
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Text(e.toString(),
                                style: TextStyle(
                                    color: UIHelpers.errorColor,
                                    fontSize: 12)),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (signedList.isEmpty && unsignedList.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无签到数据',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _dialogBackBtn(VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildChip(String text, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? UIHelpers.warningColor
              : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: active ? null : Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Text(text,
            style: TextStyle(
                color: active ? Colors.white : Colors.white70)),
      ),
    );
  }
}
