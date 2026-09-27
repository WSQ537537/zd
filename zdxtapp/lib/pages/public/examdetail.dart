import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/formula_renderer.dart'; // 🔥 新公式渲染器
import 'package:zdxtapp/pages/public/aichat.dart';

class ExamDetail extends StatefulWidget {
  final String paperId;
  final String account;

  const ExamDetail({
    super.key,
    required this.paperId,
    required this.account,
  });

  @override
  State<ExamDetail> createState() => _ExamDetailState();
}

class _ExamDetailState extends State<ExamDetail> {
  String paperTitle = '';
  String submitTime = '';
  num totalScore = 0;
  num totalQuestionScore = 0;

  bool loading = true;

  List<dynamic> singleList = [];
  List<dynamic> multiList = [];
  List<dynamic> fillList = [];
  List<dynamic> shortList = [];

  num singleScore = 0;
  num multiScore = 0;
  num fillScore = 0;
  num shortScore = 0;

  num singleTotalScore = 0;
  num multiTotalScore = 0;
  num fillTotalScore = 0;
  num shortTotalScore = 0;

  final String baseUrl = Config.baseUrl;

  // ✅ 悬浮标题卡片 GlobalKey：滚动区据此读取卡片实际渲染高度，实现列表自适应（标题换行变高时不遮挡）
  final GlobalKey _headerKey = GlobalKey();
  // ✅ 卡片高度 ValueNotifier：卡片布局完成后写入实际高度并 notify，触发滚动区重建
  final ValueNotifier<double> _headerHeight = ValueNotifier<double>(140.0);

  @override
  void initState() {
    super.initState();
    initData();
  }

  @override
  void dispose() {
    _headerHeight.dispose();
    super.dispose();
  }

  /// 卡片布局完成后回调：把实际渲染高度写入 _headerHeight 并通知滚动区重建
  void _measureHeader() {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.size.height > 0) {
      final h = box.size.height;
      if (h != _headerHeight.value) {
        _headerHeight.value = h;
      }
    }
  }

  Future<void> initData() async {
    await getDetail();
  }

  Future<void> getDetail() async {
    setState(() => loading = true);

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/exam'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "getUserExamDetail",
        "account": widget.account,
        "examId": widget.paperId,
      }),
      )).body);

      if (data['success'] == true || data['code'] == 0) {
        final d = data['data'] ?? {};

        setState(() {
          paperTitle = d['paperName'] ?? '试卷${widget.paperId}';
          submitTime = fmtTime(d['submitTime']);
          totalScore = d['totalScore'] ?? 0;
          final examDetail = d['examDetail'] ?? [];

          singleList = examDetail.where((q) => (q['type']?.toString().trim() ?? '') == 'single').toList();
          multiList = examDetail.where((q) => (q['type']?.toString().trim() ?? '') == 'multi').toList();
          fillList = examDetail.where((q) => (q['type']?.toString().trim() ?? '') == 'fill').toList();
          shortList = examDetail.where((q) => (q['type']?.toString().trim() ?? '') == 'short').toList();

          singleScore = singleList.fold(0, (num t, q) => t + (q['userScore'] ?? 0));
          multiScore = multiList.fold(0, (num t, q) => t + (q['userScore'] ?? 0));
          fillScore = fillList.fold(0, (num t, q) => t + (q['userScore'] ?? 0));
          shortScore = shortList.fold(0, (num t, q) => t + (q['userScore'] ?? 0));

          singleTotalScore = singleList.fold<num>(0, (t, q) => t + _numOf(q['score']));
          multiTotalScore = multiList.fold<num>(0, (t, q) => t + _numOf(q['score']));
          fillTotalScore = fillList.fold<num>(0, (t, q) => t + _numOf(q['score']));
          shortTotalScore = shortList.fold<num>(0, (t, q) => t + _numOf(q['score']));

          totalQuestionScore = singleTotalScore + multiTotalScore + fillTotalScore + shortTotalScore;
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  num _numOf(dynamic v) {
    if (v is num) return v;
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  String fmtTime(dynamic s) {
    if (s == null) return '';
    try {
      final parsed = DateTime.parse(s.toString());
      final cst = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
      return "${cst.year}-${cst.month.toString().padLeft(2, '0')}-${cst.day.toString().padLeft(2, '0')} ${cst.hour.toString().padLeft(2, '0')}:${cst.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return '';
    }
  }

  bool isUserSel(dynamic opt, Map q) {
    final idx = (q['options']?.indexOf(opt) ?? -1) as int;
    if (idx < 0) return false;
    final letter = String.fromCharCode(65 + idx);

    if (q['type'] == 'single') {
      return q['userAnswer'] == opt || q['userAnswer'] == letter;
    }
    if (q['type'] == 'multi') {
      final ua = q['userAnswer'];
      if (ua is String) return ua.contains(letter);
      if (ua is List) return ua.contains(opt);
    }
    return false;
  }

  bool isStdAns(dynamic opt, Map q) {
    final idx = (q['options']?.indexOf(opt) ?? -1) as int;
    if (idx < 0) return false;
    final letter = String.fromCharCode(65 + idx);

    if (q['type'] == 'single') {
      return q['standardAnswer'] == opt || q['standardAnswer'] == letter;
    }
    if (q['type'] == 'multi') {
      final sa = q['standardAnswer'];
      if (sa is String) return sa.contains(letter);
      if (sa is List) return sa.contains(opt);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 背景
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xfff0f4fc), Color(0xffe6edf8)],
              ),
            ),
          ),

          // 内容
          if (loading)
            const Center(
              child: Text('正在加载答卷详情...', style: TextStyle(fontSize: 16, color: Colors.black54)),
            )
          else
            Stack(
              children: [
                // 🔥 固定标题卡片：不随内容滚动，紧贴顶部（只预留状态栏）
                // ✅ 卡片布局完成后测量其实际高度写入 _headerHeight，驱动滚动区重建（标题换行变高时不遮挡）
                Positioned(
                  key: _headerKey,
                  top: MediaQuery.of(context).padding.top + 2, // 🔥 从 +8 改成 +2，大幅上移
                  left: 16,
                  right: 16,
                  child: Builder(
                    builder: (ctx) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());
                      return _paperHeader();
                    },
                  ),
                ),

                // 滚动内容区域
                ValueListenableBuilder<double>(
                  valueListenable: _headerHeight,
                  builder: (context, headerH, _) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          // 滚动区上边界 = 状态栏 + 卡片实际高度 + 少量间距（12），紧贴悬浮卡片下边界
                          padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top + 2 + headerH + 12,
                            left: 16,
                            right: 16,
                            bottom: 60,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                              maxWidth: constraints.maxWidth,
                            ),
                            child: Column(
                              children: [
                                // 🔥 连续编号：将所有题型合并后按类型分组渲染
                                ..._buildContinuousSections(),

                                if (singleList.isEmpty && multiList.isEmpty && fillList.isEmpty && shortList.isEmpty)
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text('暂无答题记录', textAlign: TextAlign.center),
                                  ),

                                const SizedBox(height: 30),
                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),

          // ======================================
          // ✅ 修复完成：位置正常 + 完整显示 + 可点击
          // ======================================
          // 🔥 已删除顶部返回按钮，改为在 _paperHeader 中集成
        ],
      ),
    );
  }

  Widget _paperHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        // 🔥 磨砂半透明白色（不透明但能看到背景渐变）
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        // 🔥 增强阴影 → 滚动内容经过时会出现明显光影
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 18,    // 更大模糊
            spreadRadius: 1,   // 轻微扩散
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 👇 下面所有内容完全不动
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xff1890ff).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.arrow_back_ios, size: 14, color: Color(0xff1890ff)),
                      SizedBox(width: 4),
                      Text('返回', style: TextStyle(color: Color(0xff1890ff), fontSize: 13)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  paperTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 60),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '交卷时间：$submitTime',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xffff7a2f).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '总分：$totalScore / $totalQuestionScore',
              style: const TextStyle(fontSize: 14, color: Color(0xffff7a2f), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSection(String title, IconData icon, List list, score, total, [int startIdx = 1]) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xff1890ff).withValues(alpha: 0.12), const Color(0xff1890ff).withValues(alpha: 0.05)],
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xff1890ff)),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff1890ff))),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xffff7a2f).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('得分：$score / $total', style: const TextStyle(color: Color(0xffff7a2f))),
                ),
              ],
            ),
          ),
          ...list.asMap().entries.map((item) {
            int i = item.key;
            var q = item.value;
            return _questionItem(q, startIdx + i);
          }),
        ],
      ),
    );
  }

  // 按题型分组，但使用连续全局编号
  List<Widget> _buildContinuousSections() {
    int globalIdx = 1;
    List<Widget> widgets = [];
    void addSection(String title, IconData icon, List<Map> items, num score, num total) {
      widgets.add(_buildTypeSection(title, icon, items, score, total, globalIdx));
      globalIdx += items.length;
    }
    if (singleList.isNotEmpty) addSection('单选题', Icons.description, singleList.cast<Map>(), singleScore, singleTotalScore);
    if (multiList.isNotEmpty) addSection('多选题', Icons.push_pin, multiList.cast<Map>(), multiScore, multiTotalScore);
    if (fillList.isNotEmpty) addSection('填空题', Icons.edit, fillList.cast<Map>(), fillScore, fillTotalScore);
    if (shortList.isNotEmpty) addSection('简答题', Icons.article, shortList.cast<Map>(), shortScore, shortTotalScore);
    return widgets;
  }

  // 新增：问AI关于题目
  void _askAiAboutQuestion(Map question) {
    // 🔥 核心修复：直接使用原始题目内容，不做任何处理
    // FormulaRenderer 已经处理了 Unicode 解码，这里直接使用即可
    String questionText = question['title'] ?? '';
    String userAnswer = question['userAnswer'] ?? '未作答';
    String standardAnswer = question['standardAnswer'] ?? '无';
    
    debugPrint('🔍 [问AI] 原始题目内容: $questionText');
    debugPrint('🔍 [问AI] 题目内容长度: ${questionText.length}');
    debugPrint('🔍 [问AI] 是否包含反斜杠: ${questionText.contains("\\")}');
    debugPrint('🔍 [问AI] 是否包含美元符号: ${questionText.contains("\$")}');
    
    // 🔥 修复：根据题型严格按规范传参，不多传、不漏传、不乱传
    String aiQuestion;
    
    // 🔥 核心需求：在所有内容最开头固定添加提示文字
    String promptPrefix = '请详细解答以下题目:\n\n';
    
    // 判断题型：通过options字段是否存在来区分
    if (question['options'] != null && question['options'].isNotEmpty) {
      // 单选、多选题：传 题干 + 选项 + 用户答案 + 标准答案
      List<String> options = List<String>.from(question['options'] ?? []);
      String optionsText = options.asMap().entries.map((entry) {
        int index = entry.key;
        String option = entry.value;
        return '${String.fromCharCode(65 + index)}. $option';
      }).join('\n');
      
      aiQuestion = '''$promptPrefix题目：$questionText

选项：
$optionsText

我的答案：$userAnswer
标准答案：$standardAnswer
''';
    } else {
      // 填空、简答题：传 题干 + 用户答案 + 标准答案
      aiQuestion = '''$promptPrefix题目：$questionText

我的答案：$userAnswer
标准答案：$standardAnswer
''';
    }

    debugPrint('🔍 [问AI] 传递给AI的完整内容:\n$aiQuestion');
    
    // 跳转到AI聊天页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatPage(initialQuestion: aiQuestion),
      ),
    );
  }
  
  Widget _questionItem(Map q, int index) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xff1890ff).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('第$index题'),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xfffa8c16).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('得分：${q['userScore'] ?? 0} / ${q['score']}'),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      _askAiAboutQuestion(q);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xff1890ff), Color(0xff096dd9)]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          Text('🤖', style: TextStyle(fontSize: 12)),
                          SizedBox(width: 4),
                          Text('问AI', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          // ✅ 题目内容支持数学公式
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth,
                ),
                child: FormulaRenderer.renderMixedText(
                  q['title'],
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
              );
            },
          ),

          if (q['imgUrl'] != null && q['imgUrl'].toString().isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  q['imgUrl'].startsWith('http') ? q['imgUrl'] : '$baseUrl${q['imgUrl']}',
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

          const SizedBox(height: 10),

          if (q['options'] != null && q['options'].isNotEmpty)
            ...q['options'].asMap().entries.map((optItem) {
              int j = optItem.key;
              var opt = optItem.value;
              bool user = isUserSel(opt, q);
              bool std = isStdAns(opt, q);

              Color bg = Colors.grey.shade100;
              Color border = Colors.transparent;

              if (std) {
                bg = Colors.green.shade50;
                border = Colors.green;
              } else if (user) {
                bg = Colors.orange.shade50;
                border = Colors.orange;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(color: border, width: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${String.fromCharCode(65 + j)}.', style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    // 🔥 核心修复：使用 Flexible 替代 Expanded，确保正确换行
                    Flexible(
                      fit: FlexFit.loose,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                            ),
                            child: FormulaRenderer.renderMixedText(
                              opt,
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                      child: FormulaRenderer.renderMixedText(
                        '我的答案：${q['userAnswer'] ?? '未作答'}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                      child: FormulaRenderer.renderMixedText(
                        '标准答案：${q['standardAnswer'] ?? '无'}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth,
                ),
                child: FormulaRenderer.renderMixedText(
                  '📖 解析：${q['analysis'] ?? '暂无解析'}',
                  style: const TextStyle(color: Colors.black54, fontSize: 14, height: 1.5),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

