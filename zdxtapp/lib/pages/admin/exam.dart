import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:zdxtapp/config.dart';

import 'package:zdxtapp/utils/toast.dart';

import 'package:zdxtapp/pages/admin/exammanage.dart';
import 'package:zdxtapp/pages/admin/examanalyze.dart';
import 'package:zdxtapp/pages/admin/exampublish.dart';
import 'package:zdxtapp/pages/public/examdetail.dart';
import 'package:zdxtapp/pages/public/doexam.dart';
import 'package:zdxtapp/widgets/shimmer_loading.dart';

class ExamPage extends StatefulWidget {
  const ExamPage({super.key});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  String lightBtn = '';
  String? _pressedBtn;
  List<dynamic> paperList = [];
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = true;
  int currentPage = 1;
  final int pageSize = 10;
  String account = '';
  final String baseUrl = Config.baseUrl;

  bool isRequesting = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _onLoad();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (loadingMore || !hasMore || loading) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 80) {
      _loadMore();
    }
  }

  void _onLoad() async {
    final sp = await SharedPreferences.getInstance();
    final userInfo = sp.getString('userInfo');
    if (userInfo != null && userInfo.isNotEmpty) {
      try {
        final info = jsonDecode(userInfo);
        account = info['account'] ?? '';
      } catch (e) {
        debugPrint("⚠️ admin/exam jsonDecode 失败: $e");
      }
    }
    getPaperList();
  }

  Future<void> getPaperList() async {
    if (loading || isRequesting) return;
    currentPage = 1;
    hasMore = true;
    setState(() { paperList = []; loadingMore = false; });
    await _fetchExamPage(1);
  }

  Future<void> _loadMore() async {
    if (loadingMore || !hasMore || loading) return;
    setState(() => loadingMore = true);
    final nextPage = currentPage + 1;
    await _fetchExamPage(nextPage);
    setState(() => loadingMore = false);
  }

  Future<void> _fetchExamPage(int page) async {
    if (loading || isRequesting) return;
    setState(() => loading = true);
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/exam'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'action': 'getUserExamList',
          'account': account,
          'page': '$page',
          'limit': '$pageSize',
        }),
      ).timeout(Duration(seconds: 8))).body);

      Map data;
      try {
        data = res;
      } catch (e) {
        debugPrint("⚠️ admin/exam jsonDecode 失败: $e");
        return;
      }
      if (data['success'] == true) {
        List<dynamic> rawList = data['list'] ?? [];
        dynamic pagData = data['pagination'] ?? {};
        int totalPages = int.tryParse((pagData['totalPages'] ?? 1).toString()) ?? 1;

        List<Map<String, dynamic>> newList = rawList.map((paper) {
          return Map<String, dynamic>.from(paper as Map<String, dynamic>)
            ..['hasDone'] = paper['isDone'] ?? false;
        }).toList();

        setState(() {
          if (page == 1) {
            paperList = newList;
          } else {
            paperList = [...paperList, ...newList];
          }
          currentPage = page;
          hasMore = page < totalPages;
        });
      }
    } catch (e) {
      debugPrint("❌ [Admin端] 获取试卷列表失败: $e");
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> forceRefreshPaperList() async {
    final sp = await SharedPreferences.getInstance();
    sp.remove('paperListCache');
    sp.remove('paperListCacheTime');
    await getPaperList();
  }

  // 🔥 核心修复：添加 hasDone 参数，避免在方法内部重新查询
  Future<void> handlePaperBtn(dynamic examId, bool hasDone) async {
    debugPrint("🔍 handlePaperBtn 被调用，examId: $examId, hasDone: $hasDone");

    if (!mounted) return;

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 关闭加载对话框
      if (mounted) {
        Navigator.pop(context);
      }
      
      debugPrint("🔍 准备跳转，hasDone: $hasDone");

      if (hasDone) {
        debugPrint("🔍 跳转到 ExamDetail");
        debugPrint("🔍 paperId: ${examId.toString()}, account: $account");
        if (mounted) {
          try {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExamDetail(
                  paperId: examId.toString(),
                  account: account,
                ),
              ),
            );
            debugPrint("✅ ExamDetail 跳转成功");
          } catch (e, stackTrace) {
            debugPrint("❌ ExamDetail 跳转异常: $e");
            debugPrint("❌ 堆栈信息: $stackTrace");
          }
        }
      } else {
        debugPrint("🔍 跳转到 DoExamPage，paperId: ${examId.toString()}");
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DoExamPage(paperId: examId.toString())),
          );
          debugPrint("✅ DoExamPage 跳转成功");
          
          // 从答题页面返回后，刷新列表
          if (mounted) {
            await forceRefreshPaperList();
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint("❌ 跳转失败：$e");
      debugPrint("❌ 堆栈信息：$stackTrace");
      
      // 确保关闭加载对话框
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ToastUtil.showError(context, '操作失败：$e');
      }
    }
  }

  String formatTime(int? sec) {
    if (sec == null || sec <= 0) return '0分钟';
    int m = sec ~/ 60;
    int s = sec % 60;
    return s == 0 ? '$m分钟' : '$m分$s秒';
  }

  String splitExamTime(String? timeStr, int type) {
    if (timeStr == null || timeStr.isEmpty) return '';
    
    // 🔥 修复：支持多种分隔符格式（至、-、~）
    List<String> parts = [];
    
    // 优先尝试中文"至"
    if (timeStr.contains('至')) {
      parts = timeStr.split('至');
    }
    // 其次尝试" - "（空格+短横线+空格）
    else if (timeStr.contains(' - ')) {
      parts = timeStr.split(' - ');
    }
    // 再尝试"-"（无空格）
    else if (timeStr.contains('-') && !timeStr.contains(' - ')) {
      // 需要区分日期中的"-"和分隔符"-"
      // 日期格式如: 2026-05-03 19:20:25-2026-05-04 19:20:25
      final match = RegExp(r'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s*-\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})').firstMatch(timeStr);
      if (match != null) {
        parts = [match.group(1)!, match.group(2)!];
      }
    }
    // 最后尝试"~"
    else if (timeStr.contains('~')) {
      parts = timeStr.split('~');
    }
    
    if (parts.isEmpty) return '';
    
    if (type == 0) return parts[0].trim();
    return parts.length > 1 ? parts[1].trim() : '';
  }

  String getStatusText(Map<String, dynamic> paper) {
    if (paper['examTime'] == null || paper['examTime'].isEmpty) return '未设置';
    
    try {
      int now = DateTime.now().millisecondsSinceEpoch;
      String startStr = splitExamTime(paper['examTime'], 0);
      String endStr = splitExamTime(paper['examTime'], 1);

      // 🔥 修复：添加日期解析错误处理
      if (startStr.isEmpty || endStr.isEmpty) {
        debugPrint('⚠️ 考试时间格式异常: ${paper['examTime']}');
        return '时间格式错误';
      }

      int startTime = DateTime.parse(startStr).millisecondsSinceEpoch;
      int endTime = DateTime.parse(endStr).millisecondsSinceEpoch;

      if (now < startTime) return '未开始';
      if (now >= startTime && now <= endTime) return '答题已开放';
      return '已结束';
    } catch (e) {
      debugPrint('❌ 解析考试时间失败: $e, 原始数据: ${paper['examTime']}');
      return '时间解析错误';
    }
  }

  bool canStartExam(Map<String, dynamic> paper) {
    if (paper['examTime'] == null || paper['examTime'].isEmpty) return false;
    
    try {
      int now = DateTime.now().millisecondsSinceEpoch;
      String startStr = splitExamTime(paper['examTime'], 0);
      String endStr = splitExamTime(paper['examTime'], 1);

      // 🔥 修复：添加日期解析错误处理
      if (startStr.isEmpty || endStr.isEmpty) {
        return false;
      }

      int startTime = DateTime.parse(startStr).millisecondsSinceEpoch;
      int endTime = DateTime.parse(endStr).millisecondsSinceEpoch;

      return now >= startTime && now <= endTime;
    } catch (e) {
      debugPrint('❌ 判断考试状态失败: $e');
      return false;
    }
  }

  // 获取按钮文字
  String getButtonText(Map<String, dynamic> paper, bool hasDone) {
    String status = getStatusText(paper);
    
    if (status == '未开始') {
      return '未开始';  // 🔥 核心修复：未开始时显示"未开始"，而不是"开始答题"
    } else if (status == '答题已开放') {
      return hasDone ? '试卷详情' : '开始答题';
    } else {
      // 已结束
      return hasDone ? '试卷详情' : '已结束';
    }
  }

  // 获取按钮颜色
  Color? getButtonColor(Map<String, dynamic> paper, bool hasDone) {
    String status = getStatusText(paper);
    
    if (status == '未开始') {
      // 未开始：灰色
      return Colors.grey.withValues(alpha: 0.5);
    } else if (status == '答题已开放') {
      // 进行中：有记录绿色，无记录蓝色
      return hasDone ? Colors.green : const Color(0xFF1890FF);
    } else {
      // 已结束：有记录绿色，无记录灰色
      return hasDone ? Colors.green : Colors.grey.withValues(alpha: 0.5);
    }
  }

  // 判断按钮是否可用
  bool isButtonEnabled(Map<String, dynamic> paper, bool hasDone) {
    String status = getStatusText(paper);
    
    if (status == '未开始') {
      // 未开始：不可点击
      return false;
    } else if (status == '答题已开放') {
      // 进行中：可点击
      return true;
    } else {
      // 已结束：有记录可点击，无记录不可点击
      return hasDone;
    }
  }

  void goTest() {
    setState(() => lightBtn = 'test');
    Future.delayed(const Duration(milliseconds: 150), () {
      setState(() => lightBtn = '');
      forceRefreshPaperList();
    });
  }

  void goQuestion() {
    debugPrint('🔍 goQuestion 被调用');
    setState(() => lightBtn = 'question');
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) {
        debugPrint('❌ 页面未挂载，取消跳转');
        return;
      }
      debugPrint('✅ 准备跳转到 Exampublish 页面');
      setState(() => lightBtn = '');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const Exampublish()),
      ).then((_) {
        debugPrint('✅ 从 Exampublish 页面返回');
      }).catchError((error) {
        debugPrint('❌ 跳转失败: $error');
      });
    });
  }

  void goManage() {
    debugPrint('🔍 goManage 被调用');
    setState(() => lightBtn = 'manage');
    Future.delayed(const Duration(milliseconds: 150), () {
     if (!mounted) {
        debugPrint('❌ 页面未挂载，取消跳转');
        return;
      }
      debugPrint('✅ 准备跳转到 ExamManage 页面');
      setState(() => lightBtn = '');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ExamManage()),
      ).then((_) {
        debugPrint('✅ 从 ExamManage 页面返回');
      }).catchError((error) {
        debugPrint('❌ 跳转失败: $error');
      });
    });
  }

  void goPaperStat() {
    debugPrint('🔍 goPaperStat 被调用');
    setState(() => lightBtn = 'stat');
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) {
        debugPrint('❌ 页面未挂载，取消跳转');
        return;
      }
      debugPrint('✅ 准备跳转到 Examanalyze 页面');
      setState(() => lightBtn = '');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const Examanalyze()),
      ).then((_) {
        debugPrint('✅ 从 Examanalyze 页面返回');
      }).catchError((error) {
        debugPrint('❌ 跳转失败: $error');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ✅ 固定区域：顶部导航按钮（无渐隐）
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _navBtn('出题管理', 'question', false, goQuestion),
                _navBtn('测试管理', 'test', true, goTest),
                _navBtn('试卷管理', 'manage', false, goManage),
                _navBtn('试卷统计', 'stat', false, goPaperStat),
              ],
            ),
          ),
          
          // ✅ 可滚动内容区域：试卷列表（智能局部渐隐效果）
          Positioned(
            top: 58,
            left: 0,
            right: 0,
            bottom: 0,
            child: ShaderMask(
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
              child: loading
                  ? const Center(child: ExamListShimmer())
                  : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 60),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: paperList.length + (loadingMore ? 1 : (!hasMore && paperList.isNotEmpty ? 1 : 0)),
                itemBuilder: (context, index) {
                  if (index == paperList.length) {
                    if (loadingMore) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    if (!hasMore && paperList.isNotEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: Text("暂无更多", style: TextStyle(fontSize: 13, color: Colors.grey))),
                      );
                    }
                    return const SizedBox.shrink();
                  }
                  final paper = paperList[index];
                  bool hasDone = paper['hasDone'] ?? false;
                  String buttonText = getButtonText(paper, hasDone);
                  Color? buttonColor = getButtonColor(paper, hasDone);
                  bool buttonEnabled = isButtonEnabled(paper, hasDone);

                  debugPrint('🔍 [Admin端] 试卷: ${paper['examName']}, hasDone: $hasDone, buttonEnabled: $buttonEnabled, buttonText: $buttonText');

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
                                color: getStatusText(paper) == '未开始'
                                    ? Colors.grey
                                    : getStatusText(paper) == '答题已开放'
                                        ? Colors.green
                                        : Colors.red,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                getStatusText(paper),
                                style: const TextStyle(color: Colors.black87, fontSize: 10),
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
                                  Text('开始：${splitExamTime(paper['examTime'], 0)}',
                                    style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text('结束：${splitExamTime(paper['examTime'], 1)}',
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
                                backgroundColor: buttonColor,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: buttonEnabled
                                  ? () async {
                                      await handlePaperBtn(paper['examId'], hasDone);
                                    }
                                  : null,
                              child: Text(
                                buttonText,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(String text, String key, bool active, VoidCallback onTap) {
    final bool pressed = _pressedBtn == key;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        onTapDown: (_) => setState(() => _pressedBtn = key),
        onTapUp: (_) => setState(() => _pressedBtn = null),
        onTapCancel: () => setState(() => _pressedBtn = null),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: pressed
                ? Colors.white.withValues(alpha: active ? 0.28 : 0.18)
                : Colors.white.withValues(alpha: active ? 0.14 : 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.32 : 0.16),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: pressed ? 0.18 : 0.10),
                blurRadius: pressed ? 10 : 6,
                offset: Offset(0, pressed ? 4 : 2),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: active ? 0.15 : 0.06),
                blurRadius: 8,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? const Color(0xFF1890FF) : const Color(0xFF4A4A4A),
                fontWeight: active || pressed ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
