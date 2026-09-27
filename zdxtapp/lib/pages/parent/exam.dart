import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/formula_renderer.dart';
import 'package:zdxtapp/utils/ui_helpers.dart';

class ExamPage extends StatefulWidget {
  const ExamPage({super.key});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  bool loading = true;
  bool loadError = false;
  String loadErrorMsg = "";
  List<Map<String, String>> boundStudents = [];
  bool hasBoundStudents = false;
  final String baseUrl = Config.baseUrl;
  int _selectedBoundIndex = 0;

  // 用于直接操控 ExamListSection，避免切换学生时重建整个页面
  final GlobalKey<_ExamListSectionState> _examListKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    checkAndLoad();
  }

  Future<void> checkAndLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfo = prefs.getString("userInfo");
      if (userInfo == null) {
        if (!mounted) return;
        debugPrint('❌ checkAndLoad: userInfo is null');
        setState(() => loading = false);
        return;
      }
      final parentAccount = jsonDecode(userInfo)["account"] ?? "";
      debugPrint('📡 checkAndLoad: parentAccount=$parentAccount');

      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "getParentBoundStudents", "parentAccount": parentAccount}),
      ).timeout(Duration(seconds: 10))).body);

      final data = res;

      if (!mounted) return;


      if (data["success"] == true) {
        final students = data["data"] as List? ?? [];
        final hasStudents = students.isNotEmpty;
        final boundList = students.map((s) => {"account": s["account"] as String? ?? "", "remark": s["remark"] as String? ?? ""}).toList();
        setState(() {
          hasBoundStudents = hasStudents;
          boundStudents = boundList;
          loading = false;
        });
        if (hasStudents) {
          // 通知 ExamListSection 加载第一个学生
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_examListKey.currentState != null) {
              _examListKey.currentState!.switchStudent(boundStudents[0]["account"] ?? "");
            }
          });
        } else {
          setState(() => loading = false);
        }
      } else {
        setState(() { loading = false; loadError = true; loadErrorMsg = "加载失败"; });

      }
    } catch (e) {
      if (mounted) {
        setState(() { loading = false; loadError = true; loadErrorMsg = "加载失败"; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _examPageBody();
  }

  Widget _examPageBody() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 56),
        child: loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1), strokeWidth: 3))
            : loadError
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text("加载失败，请检查网络后重试", style: TextStyle(color: Colors.black54, fontSize: 14)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => checkAndLoad(),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text("重新加载"),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1890FF)),
                        ),
                      ],
                    ),
                  )
                : !hasBoundStudents
                    ? const Center(
                        child: Text("暂无绑定学生，请前往我的-设置页面绑定",
                            style: TextStyle(color: Color.fromARGB(179, 0, 0, 0))))
                    : _buildCardContent(),
      ),
    );
  }

  Widget _buildCardContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 8),
          child: Text("试卷详情中心",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
        // 整体卡片
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 学生选择器（不响应 setState 重建）
                  RepaintBoundary(child: _buildStudentSelector()),
                  const Divider(height: 1, color: Color(0xFFE0E0E0)),
                  // 考试列表（独立 StatefulWidget，通过 GlobalKey 直接操控）
                  RepaintBoundary(
                    child: _ExamListSection(
                      key: _examListKey,
                      baseUrl: baseUrl,
                      boundStudents: boundStudents,
                      initialAccount: _selectedBoundIndex >= 0 && _selectedBoundIndex < boundStudents.length
                          ? boundStudents[_selectedBoundIndex]["account"] ?? ""
                          : "",
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

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
                final isSelected = i == _selectedBoundIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ExamStudentChip(
                    key: ValueKey(student['account']),
                    account: student["account"] ?? "",
                    remark: student["remark"] ?? "",
                    isSelected: isSelected,
                    onTap: () {
                      if (i == _selectedBoundIndex) return;
                      setState(() => _selectedBoundIndex = i);
                      // 直接调用 ExamListSection 的方法，避免整页重建
                      _examListKey.currentState?.switchStudent(student["account"] ?? "");
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 考试列表：独立 StatefulWidget，通过 GlobalKey 直接操控，不跟随父页面重建
// ─────────────────────────────────────────────────────────────────────────────
class _ExamListSection extends StatefulWidget {
  final String baseUrl;
  final List<Map<String, String>> boundStudents;
  final String initialAccount;

  const _ExamListSection({
    super.key,
    required this.baseUrl,
    required this.boundStudents,
    required this.initialAccount,
  });

  @override
  State<_ExamListSection> createState() => _ExamListSectionState();
}

class _ExamListSectionState extends State<_ExamListSection> {
  List<Map<String, dynamic>> userList = [];
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = true;
  bool loadError = false;
  int currentPage = 1;
  static const int pageSize = 10;
  String _currentAccount = "";
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounce;

  @override
  void initState() {
    super.initState();
    _currentAccount = widget.initialAccount;
    _scrollController.addListener(_onScroll);
    if (_currentAccount.isNotEmpty) {
      _fetchExamPage(1);
    }
  }

  @override
  void didUpdateWidget(_ExamListSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级传入的 initialAccount 变化时重新加载
    if (widget.initialAccount != oldWidget.initialAccount && widget.initialAccount.isNotEmpty) {
      switchStudent(widget.initialAccount);
    }
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    if (_scrollController.hasClients) {
      _scrollController.removeListener(_onScroll);
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 400), () {
      if (loadingMore || !hasMore || loading) return;
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 80) {
        _loadMore();
      }
    });
  }

  /// 切换学生：重置分页并重新拉取
  void switchStudent(String account) {
    if (!mounted) return;
    setState(() {
      _currentAccount = account;
      currentPage = 1;
      hasMore = true;
      userList = [];
      loadError = false;
    });
    _fetchExamPage(1);
  }

  Future<void> _fetchExamPage(int page) async {
    if (!mounted || _currentAccount.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoStr = prefs.getString("userInfo");
      if (userInfoStr == null) {
        if (!mounted) return;

        setState(() => loading = false);
        return;
      }
      final parentAccount = jsonDecode(userInfoStr)["account"] ?? "";
      if (page == 1) setState(() => loading = true);


      final res = await jsonDecode((await http.post(
        Uri.parse("${widget.baseUrl}/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "getParentExamStatistics",
          "parentAccount": parentAccount,
          "studentAccount": _currentAccount,
          "page": "$page",
          "limit": "$pageSize",
        }),
      ).timeout(Duration(seconds: 10))).body);

      if (!mounted) return;
      final data = res;

      if (data["success"] == true) {
        final rawList = data["data"]?["userList"] ?? <dynamic>[];
        final pag = data["data"]?["pagination"] ?? <String, dynamic>{};
        final totalPages = int.tryParse((pag["totalPages"] ?? 0).toString()) ?? 0;

        final processedList = List<Map<String, dynamic>>.from(rawList).map((user) {
          final remark = (user["remark"] != null && (user["remark"] as String).isNotEmpty) ? user["remark"] : "无";
          return {
            ...user,
            "remark": remark,
            "examList": List<Map<String, dynamic>>.from(user["examList"] ?? []),
          };
        }).toList();

        setState(() {
          // 后端已按 studentAccount 单学生维度分页，userList 即为当前页该学生的记录，
          // 直接摊开累加即可，无需再按 account 二次过滤（否则切学生/多绑定时会丢数据导致空页）
          final examRecords = <Map<String, dynamic>>[];
          for (final user in processedList) {
            examRecords.addAll(user["examList"]);
          }
          if (page == 1) {
            userList = examRecords;
          } else {
            userList = [...userList, ...examRecords];
          }
          currentPage = page;
          hasMore = page < totalPages;
          loadError = false;
          loading = false;
          loadingMore = false;
        });
      } else {
        setState(() { userList = []; loadError = true; loading = false; loadingMore = false; hasMore = false; });
      }

    } catch (e) {
      if (mounted) {
        setState(() { loading = false; loadingMore = false; loadError = true; hasMore = false; });
      }
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || !hasMore) return;
    setState(() => loadingMore = true);
    final nextPage = currentPage + 1;
    await _fetchExamPage(nextPage);
    if (mounted) setState(() => loadingMore = false);
  }

  String fmtTime(String? t) {
    if (t == null || t.isEmpty) return "未知时间";
    try {
      final parsed = DateTime.parse(t);
      final cst = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
      return "${cst.year}-${cst.month.toString().padLeft(2,'0')}-${cst.day.toString().padLeft(2,'0')} ${cst.hour.toString().padLeft(2,'0')}:${cst.minute.toString().padLeft(2,'0')}";
    } catch (_) { return t; }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => switchStudent(_currentAccount),
      color: const Color(0xFF1890FF),
      child: Container(
        constraints: const BoxConstraints(minHeight: 200),
        child: loading && userList.isEmpty
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1), strokeWidth: 2)),
              )
            : loadError && userList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 36, color: Colors.grey),
                        const SizedBox(height: 8),
                        const Text("加载失败，请重试", style: TextStyle(color: Colors.black54, fontSize: 13)),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => switchStudent(_currentAccount),
                          child: const Text("重新加载", style: TextStyle(color: Color(0xFF1890FF))),
                        ),
                      ],
                    ),
                  )
                : userList.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text("暂无答题记录", style: TextStyle(color: Colors.black54, fontSize: 14)),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        shrinkWrap: true,
                        // 使用 AlwaysScrollableScrollPhysics：让 RefreshIndicator 能接管顶部下拉刷新。
                        // 原来的 ClampingScrollPhysics 会吞掉下拉手势，导致 RefreshIndicator 不触发
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: userList.length + (hasMore || loadingMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i >= userList.length) {
                            if (loadingMore) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D47A1))),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }
                          final exam = userList[i];
                          return _buildExamCard(exam);
                        },
                      ),
      ),
    );
  }

  Widget _buildExamCard(Map<String, dynamic> exam) {
    return GestureDetector(
      onTap: () => _showExamDetail(exam),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          title: Text(exam["examName"] ?? "试卷",
              style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text("提交：${fmtTime(exam["submitTime"])}  |  得分：${(exam["totalScore"] ?? 0).toString()}",
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF1890FF).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: const Text("查看", style: TextStyle(color: Color(0xFF1890FF), fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  void _showExamDetail(Map<String, dynamic> exam) {
    final examId = exam["examId"]?.toString() ?? "";
    if (examId.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExamDetailSheet(
        baseUrl: widget.baseUrl,
        account: _currentAccount,
        examId: examId,
        examName: exam["examName"] ?? "试卷详情",
        fallbackSubmitTime: exam["submitTime"],
        fallbackTotalScore: exam["totalScore"],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 考试详情底部弹窗
// ─────────────────────────────────────────────────────────────────────────────
class _ExamDetailSheet extends StatefulWidget {
  final String baseUrl;
  final String account;
  final String examId;
  final String examName;
  final String? fallbackSubmitTime;
  final dynamic fallbackTotalScore;

  const _ExamDetailSheet({
    required this.baseUrl,
    required this.account,
    required this.examId,
    required this.examName,
    this.fallbackSubmitTime,
    this.fallbackTotalScore,
  });

  @override
  State<_ExamDetailSheet> createState() => _ExamDetailSheetState();
}

class _ExamDetailSheetState extends State<_ExamDetailSheet> {
  bool loading = true;
  bool loadError = false;
  String loadErrorMsg = "";
  List singleList = [];
  List multiList = [];
  List fillList = [];
  List shortList = [];
  // 详情接口返回的总分（权威值），列表回退值兜底
  num? detailTotalScore;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    if (!mounted) return;
    setState(() { loading = true; loadError = false; });
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse("${widget.baseUrl}/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "getUserExamDetail",
          "account": widget.account,
          "examId": widget.examId,
        }),
      ).timeout(Duration(seconds: 10))).body);
      if (!mounted) return;
      final data = res;
      if (data["success"] == true || data["code"] == 0) {
        final d = data["data"] ?? <String, dynamic>{};
        final detail = List.from(d["examDetail"] ?? []);
        setState(() {
          detailTotalScore = num.tryParse(d["totalScore"]?.toString() ?? "") ;
          singleList = detail.where((q) => (q["type"]?.toString().trim() ?? "") == "single").toList();
          multiList = detail.where((q) => (q["type"]?.toString().trim() ?? "") == "multi").toList();
          fillList = detail.where((q) => (q["type"]?.toString().trim() ?? "") == "fill").toList();
          shortList = detail.where((q) => (q["type"]?.toString().trim() ?? "") == "short").toList();
          loading = false;
        });
      } else {
        setState(() { loading = false; loadError = true; loadErrorMsg = "加载失败"; });
      }
    } catch (e) {
      if (mounted) setState(() { loading = false; loadError = true; loadErrorMsg = "加载失败"; });
    }
  }

  String fmtTime(String? t) {
    if (t == null || t.isEmpty) return "未知时间";
    try {
      final parsed = DateTime.parse(t);
      final cst = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
      return "${cst.year}-${cst.month.toString().padLeft(2, '0')}-${cst.day.toString().padLeft(2, '0')} ${cst.hour.toString().padLeft(2, '0')}:${cst.minute.toString().padLeft(2, '0')}";
    } catch (_) { return t; }
  }

  String getAnswerLetter(Map q, ans) {
    final opts = List<String>.from(q["options"] ?? []);
    if (ans == null) return "";
    int idx = opts.indexWhere((o) => o == ans);
    if (idx >= 0) return String.fromCharCode(65 + idx);
    return ans.toString();
  }

  String getMultiAnswerLetter(Map q, ans) {
    if (ans == null) return "";
    List arr = ans is List ? ans : ans.toString().split(",");
    return arr.map((a) => getAnswerLetter(q, a)).join("、");
  }

  /// 动态获取数值（兼容 String/num）
  num _numOf(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildDetailSheet();
    } catch (e) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        child: const Center(
          child: Text("详情加载异常", style: TextStyle(color: Colors.grey)),
        ),
      );
    }
  }

  Widget _buildDetailSheet() {
    // 各题型已得分（前端累加 userScore）
    final singleScore = singleList.fold<num>(0, (t, q) => t + _numOf(q["userScore"]));
    final multiScore = multiList.fold<num>(0, (t, q) => t + _numOf(q["userScore"]));
    final fillScore = fillList.fold<num>(0, (t, q) => t + _numOf(q["userScore"]));
    final shortScore = shortList.fold<num>(0, (t, q) => t + _numOf(q["userScore"]));
    // 各题型满分（前端累加 score）
    final singleFull = singleList.fold<num>(0, (t, q) => t + _numOf(q["score"]));
    final multiFull = multiList.fold<num>(0, (t, q) => t + _numOf(q["score"]));
    final fillFull = fillList.fold<num>(0, (t, q) => t + _numOf(q["score"]));
    final shortFull = shortList.fold<num>(0, (t, q) => t + _numOf(q["score"]));
    // 总分 = 各题型满分之和；已得分 = 各题型已得分之和
    final totalQuestionScore = singleFull + multiFull + fillFull + shortFull;
    final totalScore = singleScore + multiScore + fillScore + shortScore;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(widget.examName,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.black54)),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1), strokeWidth: 3))
                : loadError
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            const Text("加载失败，请检查网络后重试", style: TextStyle(color: Colors.black54, fontSize: 14)),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: _loadDetail,
                              child: const Text("重试", style: TextStyle(color: Color(0xFF0D47A1))),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(color: const Color(0xFFF0F7FF), borderRadius: BorderRadius.circular(10)),
                              child: Text("提交时间：${fmtTime(widget.fallbackSubmitTime)}    得分：$totalScore / $totalQuestionScore",
                                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
                            ),
                            if (singleList.isNotEmpty) buildQuestionSection("单选题", singleList, true, 0, singleScore, singleFull),
                            if (multiList.isNotEmpty) buildQuestionSection("多选题", multiList, false, singleList.length, multiScore, multiFull),
                            if (fillList.isNotEmpty) buildQuestionSection("填空题", fillList, null, singleList.length + multiList.length, fillScore, fillFull),
                            if (shortList.isNotEmpty) buildQuestionSection("简答题", shortList, null, singleList.length + multiList.length + fillList.length, shortScore, shortFull),
                            if (singleList.isEmpty && multiList.isEmpty && fillList.isEmpty && shortList.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: Center(child: Text("暂无题目明细", style: TextStyle(color: Colors.black54))),
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget buildQuestionSection(String title, List list, bool? isSingle, [int startIdx = 0, num sectionScore = 0, num sectionFull = 0]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500)),
              if (sectionFull > 0)
                Text("得分：$sectionScore / $sectionFull", style: TextStyle(color: UIHelpers.warningColor, fontSize: 13)),
            ],
          ),
        ),
        for (int i = 0; i < list.length; i++) buildQuestion(list[i] as Map, startIdx + i + 1, isSingle),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget buildQuestion(Map q, int num, bool? isSingle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("第 $num 题", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              Text("得分：${q["userScore"] ?? 0}/${q["score"] ?? 0}", style: TextStyle(color: UIHelpers.warningColor)),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 100),
              child: FormulaRenderer.renderMixedText(
                q["title"] ?? "无题目",
                style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (isSingle != null && q["options"] != null)
            for (int j = 0; j < (q["options"] as List).length; j++)
              buildOption(q["options"][j], j, q, isSingle),
          if (q["imgUrl"] != null && q["imgUrl"].toString().isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  q["imgUrl"],
                  fit: BoxFit.contain,
                  height: 150,
                  errorBuilder: (a, b, c) => Container(
                    height: 150,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                    child: const Text("图片加载失败", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 100),
              child: FormulaRenderer.renderMixedText(
                "我的答案：${isSingle == true ? getAnswerLetter(q, q["userAnswer"]) : (isSingle == false ? getMultiAnswerLetter(q, q["userAnswer"]) : q["userAnswer"] ?? "未作答")}",
                style: const TextStyle(color: Colors.black54, fontSize: 14),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 100),
              child: FormulaRenderer.renderMixedText(
                "标准答案：${isSingle == true ? getAnswerLetter(q, q["standardAnswer"]) : (isSingle == false ? getMultiAnswerLetter(q, q["standardAnswer"]) : q["standardAnswer"] ?? "无")}",
                style: TextStyle(color: UIHelpers.successColor, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 100),
              child: FormulaRenderer.renderMixedText(
                "解析：${q["analysis"] ?? "暂无解析"}",
                style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildOption(String opt, int j, Map q, bool isSingle) {
    bool isUser = false, isStd = false;
    final letter = String.fromCharCode(65 + j);
    if (isSingle) {
      isUser = q["userAnswer"] == opt || q["userAnswer"] == letter;
      isStd = q["standardAnswer"] == opt || q["standardAnswer"] == letter;
    } else {
      isUser = (q["userAnswer"] ?? "").toString().contains(letter);
      isStd = (q["standardAnswer"] ?? "").toString().contains(letter);
    }
    Color bg = Colors.transparent;
    if (isUser) bg = UIHelpers.warningColor.withValues(alpha: 0.15);
    if (isStd) bg = UIHelpers.successColor.withValues(alpha: 0.15);
    if (isUser && isStd) bg = const Color(0xFF20C997).withValues(alpha: 0.15);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: bg, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$letter. ", style: const TextStyle(color: Colors.black87, fontSize: 13)),
          Flexible(
            fit: FlexFit.loose,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 140),
                child: FormulaRenderer.renderMixedText(
                  opt,
                  style: const TextStyle(color: Colors.black87, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 考试界面学生选择 chip
// ─────────────────────────────────────────────────────────────────────────────
class _ExamStudentChip extends StatefulWidget {
  final String account;
  final String remark;
  final bool isSelected;
  final VoidCallback onTap;
  const _ExamStudentChip({
    super.key,
    required this.account,
    required this.remark,
    required this.isSelected,
    required this.onTap,
  });
  @override
  State<_ExamStudentChip> createState() => _ExamStudentChipState();
}

class _ExamStudentChipState extends State<_ExamStudentChip> {
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

