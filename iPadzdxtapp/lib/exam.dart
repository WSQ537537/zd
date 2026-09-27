import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'doexam.dart';
import 'examdetail.dart';
import 'aichat.dart';
import 'mine.dart';
import 'dart:async';

class ExamPage extends StatefulWidget {
  const ExamPage({super.key});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  List<dynamic> paperList = [];
  bool loading = true;
  bool loadFailed = false; // ✅ 请求失败标志位：失败时不显示「暂无试卷」，避免数据未加载完成就渲染空态
  String account = "";
  final String baseUrl = Config.baseUrl;

  final ScrollController _scrollController = ScrollController();
  
  // 🔥 个人中心面板显示状态
  bool showMinePanel = false;
  
  // 🔥 定时刷新相关
  Timer? _refreshTimer;
  bool _isNavigating = false; // 防止重复跳转

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
    _startAutoRefresh(); // 🔥 启动自动刷新
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _refreshTimer?.cancel(); // 🔥 取消定时器
    super.dispose();
  }

  void _onScroll() {}

  String splitExamTime(String? timeStr, int type) {
    if (timeStr == null || timeStr.isEmpty) return '';
    
    List<String> parts = [];
    
    if (timeStr.contains('至')) {
      parts = timeStr.split('至');
    } else if (timeStr.contains(' - ')) {
      parts = timeStr.split(' - ');
    } else if (timeStr.contains('-') && !timeStr.contains(' - ')) {
      final match = RegExp(r'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s*-\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})').firstMatch(timeStr);
      if (match != null) {
        parts = [match.group(1)!, match.group(2)!];
      }
    } else if (timeStr.contains('~')) {
      parts = timeStr.split('~');
    }
    
    if (parts.isEmpty) return '';
    
    if (type == 0) return parts[0].trim();
    if (type == 1 && parts.length > 1) return parts[1].trim();
    return '';
  }

  Future<void> _loadData() async {
    await _getAccount();
    await _getPaperList();
    setState(() => loading = false);
  }

  Future<void> _getAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfo = prefs.getString("userInfo");
    if (userInfo != null) {
      final map = jsonDecode(userInfo);
      account = map["account"] ?? "";
    }
  }

  Future<void> _getPaperList() async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "action": "getUserExamList",
          "account": account.trim(),
          "page": "1",
          "limit": "20",
        },
      );
      
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        List<dynamic> list = data["list"] ?? [];
        
        setState(() {
          paperList = list;
          loadFailed = false;
        });
        
        // 🔥 检测强制试卷并自动跳转
        _checkAndNavigateToForceExam(list);
      } else {
        if (mounted) setState(() => loadFailed = true);
      }
    } catch (e) {
      debugPrint("获取试卷列表失败: $e");
      if (mounted) setState(() => loadFailed = true);
    }
  }
  
  // 启动自动刷新（每15秒）
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted && !_isNavigating) {
        _getPaperList();
      }
    });
  }
  
  // 检测并跳转到强制试卷
  void _checkAndNavigateToForceExam(List<dynamic> list) {
    if (_isNavigating || !mounted) return;
    
    // 查找第一个状态为"强制"且未完成的试卷
    for (var paper in list) {
      final status = paper['status']?.toString().trim();
      final isDone = paper['isDone'] ?? false;
      
      if (status == '强制' && !isDone) {
        // 检查是否可以开始答题
        final canStart = canStartExam(paper);
        if (canStart) {
          _isNavigating = true;
          _refreshTimer?.cancel(); // 停止刷新
          
          // 使用 postFrameCallback 避免在 setState 过程中跳转
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isNavigating) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DoExamPage(paperId: paper['examId'].toString()),
                ),
              ).then((result) {
                // 从答题页面返回后，重新加载数据并恢复刷新
                if (mounted) {
                  _loadData();
                  _startAutoRefresh();
                  _isNavigating = false;
                }
              });
            } else {
              _isNavigating = false;
            }
          });
          break; // 只处理第一个强制试卷
        }
      }
    }
  }

  Future<void> handlePaperBtn(dynamic examId, bool isDone) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 直接执行逻辑，无需伪等待（避免阻塞跳转的 50ms 延时）
      if (!mounted) return;
      Navigator.pop(context);

      if (isDone) {
        if (mounted) {
          // 🔥 进入详情页时停止刷新
          _refreshTimer?.cancel();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExamDetail(
                paperId: examId.toString(),
                account: account,
              ),
            ),
          ).then((_) {
            // 🔥 返回试卷列表页时恢复刷新
            if (mounted) {
              _startAutoRefresh();
            }
          });
        }
      } else {
        if (!mounted) return;
        // 🔥 进入答题页时停止刷新
        _refreshTimer?.cancel();
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DoExamPage(paperId: examId.toString())),
        );
        if (result == true && mounted) {
          await _loadData();
        }
        // 🔥 返回试卷列表页时恢复刷新
        if (mounted) {
          _startAutoRefresh();
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  String getStatusText(Map paper) {
    final timeStr = paper["examTime"];
    final start = splitExamTime(timeStr, 0);
    final end = splitExamTime(timeStr, 1);
    
    if (start.isEmpty || end.isEmpty) return "未设置";
    
    final now = DateTime.now();
    final startTime = DateTime.tryParse(start);
    final endTime = DateTime.tryParse(end);
    
    if (startTime == null || endTime == null) return "未设置";
    
    if (now.isBefore(startTime)) return "未开始";
    if (now.isAfter(endTime)) return "已结束";
    return "答题已开放";
  }

  Color getStatusColor(String status) {
    if (status == "未开始") return Colors.grey;
    if (status == "答题已开放") return Colors.green;
    return Colors.red;
  }

  bool canStartExam(Map paper) {
    final status = getStatusText(paper);
    return status == "答题已开放";
  }

  String formatTime(int? sec) {
    if (sec == null || sec <= 0) return '0分钟';
    int m = sec ~/ 60;
    int s = sec % 60;
    return s == 0 ? '$m分钟' : '$m分$s秒';
  }

  // ==================== 平板1:2分栏布局 ====================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;

    if (!isTablet) {
      return _buildMobileLayout();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Row(
        children: [
          Expanded(
            flex: 1,
            child: showMinePanel 
                ? MinePanel(onClose: () {
                    setState(() => showMinePanel = false);
                  })
                : _buildLeftPanel(screenHeight),
          ),
          Expanded(
            flex: 2,
            child: _buildRightPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(double screenHeight) {
    int totalCount = paperList.length;
    int doneCount = paperList.where((p) => p['isDone'] ?? false).length;
    int undoneCount = totalCount - doneCount;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            "试卷中心",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 40),
          _buildStatCard("总试卷数", "$totalCount", Icons.article, Colors.blue),
          const SizedBox(height: 16),
          _buildStatCard("已完成", "$doneCount", Icons.check_circle, Colors.green),
          const SizedBox(height: 16),
          _buildStatCard("未完成", "$undoneCount", Icons.pending, Colors.orange),
          const Spacer(),
          // 🔥 放大品牌文字，上移位置，居中对齐
          const Center(
            child: Column(
              children: [
                Text(
                  "智答星途 · 考试系统",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "智能答题 · 星途相伴",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          // 🔥 底部两个圆形按钮
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 左侧：齿轮设置图标（显示个人中心面板）
              GestureDetector(
                onTap: () {
                  debugPrint('⚙️ 设置按钮被点击，显示个人中心面板');
                  setState(() => showMinePanel = true);
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.settings,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              // 右侧：AI助手图标（跳转到aichat）
              GestureDetector(
                onTap: () {
                  debugPrint('🤖 AI助手按钮被点击');
                  // 🔥 进入其他页面时停止刷新
                  _refreshTimer?.cancel();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AiChatPage()),
                  ).then((_) {
                    // 🔥 返回试卷列表页时恢复刷新
                    if (mounted) {
                      _startAutoRefresh();
                    }
                  });
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1890FF), Color(0xFF096dd9)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1890FF).withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.smart_toy,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            if (loading)
              const Center(child: CircularProgressIndicator()),
            
            if (!loading && loadFailed && paperList.isEmpty)
              const Center(
                child: Text("加载失败，请下拉刷新重试", style: TextStyle(color: Colors.grey, fontSize: 16)),
              ),

            if (!loading && !loadFailed && paperList.isEmpty)
              const Center(
                child: Text("暂无试卷", style: TextStyle(color: Colors.grey, fontSize: 16)),
              ),

            if (!loading && paperList.isNotEmpty)
              _buildExamGrid(),

            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          ],
        ),
      ),
    );
  }

  Widget _buildExamGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.4,
      ),
      itemCount: paperList.length,
      itemBuilder: (context, index) {
        final paper = paperList[index];
        final status = getStatusText(paper);
        final startTime = splitExamTime(paper["examTime"] ?? "", 0);
        final endTime = splitExamTime(paper["examTime"] ?? "", 1);
        bool canStart = canStartExam(paper);
        bool isDone = paper['isDone'] ?? false;
        bool disabled = !canStart && !isDone;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      paper['examName'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: getStatusColor(status),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text('科目：${paper['subject'] ?? ''}',
                      style: const TextStyle(color: Color(0xFF666666), fontSize: 13)),
                  ),
                  Text('类型：${paper['status'] ?? '自由'}',
                    style: const TextStyle(color: Colors.orange, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('开始：$startTime',
                      style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('结束：$endTime',
                      style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
                    if (paper['timingType'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        paper['timingType'] == 'totalTime'
                            ? '总计时：${formatTime(paper['totalTime'])}'
                            : '每题计时',
                        style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: disabled
                              ? Colors.grey.withValues(alpha: 0.3)
                              : (isDone ? Colors.green : const Color(0xFF1890FF)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: disabled
                            ? null
                            : () async {
                                await handlePaperBtn(paper['examId'], isDone);
                              },
                        child: Text(
                          isDone ? '试卷详情' : '开始答题',
                          style: const TextStyle(fontSize: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          const Positioned(
            top: 20,
            left: 16,
            child: Text(
              "试卷",
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          RefreshIndicator(
            onRefresh: _loadData,
            color: Colors.white,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 70),
              children: [
                if (loading)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),

                if (!loading && loadFailed && paperList.isEmpty)
                  const Center(
                    child: Text("加载失败，请下拉刷新重试", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),

                if (!loading && !loadFailed && paperList.isEmpty)
                  const Center(
                    child: Text("暂无试卷", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),

                ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: paperList.map((paper) {
                    final status = getStatusText(paper);
                    final startTime = splitExamTime(paper["examTime"] ?? "", 0);
                    final endTime = splitExamTime(paper["examTime"] ?? "", 1);
                    bool canStart = canStartExam(paper);
                    bool isDone = paper['isDone'] ?? false;
                    bool disabled = !canStart && !isDone;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  paper['examName'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF333333),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: getStatusColor(status),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  status,
                                  style: const TextStyle(color: Colors.white, fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text('科目：${paper['subject'] ?? ''}', 
                                  style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
                              ),
                              const SizedBox(width: 8),
                              Text('类型：${paper['status'] ?? '自由'}',
                                  style: const TextStyle(color: Colors.orange, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('开始：$startTime', 
                                      style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text('结束：$endTime', 
                                      style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
                                    if (paper['timingType'] != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        paper['timingType'] == 'totalTime'
                                            ? '总计时：${formatTime(paper['totalTime'])}'
                                            : '每题计时',
                                        style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: disabled
                                      ? Colors.grey.withValues(alpha: 0.5)
                                      : (isDone ? Colors.green : const Color(0xFF1890FF)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: disabled
                                    ? null
                                    : () async {
                                        await handlePaperBtn(paper['examId'], isDone);
                                      },
                                child: Text(
                                  isDone ? '试卷详情' : '开始答题',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),

                SizedBox(height: MediaQuery.of(context).size.height * 0.35),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
