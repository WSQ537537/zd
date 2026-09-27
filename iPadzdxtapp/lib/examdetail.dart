import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config.dart';
import 'formula_renderer.dart';
import 'aichat.dart';

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

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<void> initData() async {
    await getDetail();
  }

  Future<void> getDetail() async {
    setState(() => loading = true);

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/exam'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "action": "getUserExamDetail",
          "account": widget.account,
          "examId": widget.paperId,
        }),
      );

      final Map<String, dynamic> data = jsonDecode(res.body);

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

          singleTotalScore = singleList.fold<num>(0, (t, q) => t + ((q['score'] ?? 0) as num));
          multiTotalScore = multiList.fold<num>(0, (t, q) => t + ((q['score'] ?? 0) as num));
          fillTotalScore = fillList.fold<num>(0, (t, q) => t + ((q['score'] ?? 0) as num));
          shortTotalScore = shortList.fold<num>(0, (t, q) => t + ((q['score'] ?? 0) as num));

          totalQuestionScore = singleTotalScore + multiTotalScore + fillTotalScore + shortTotalScore;
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  String fmtTime(dynamic s) {
    if (s == null) return '';
    try {
      DateTime d = DateTime.parse(s.toString());
      return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
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

  void _askAiAboutQuestion(Map question) {
    String questionText = question['title'] ?? '';
    String userAnswer = question['userAnswer'] ?? '未作答';
    String standardAnswer = question['standardAnswer'] ?? '无';

    // 首行为固定提示
    String prefix = '【请详细解答以下问题】\n';

    // 题型标注
    String qType = '题型：';
    final t = (question['type'] ?? '').toString();
    if (t == 'single') {
      qType += '单选题';
    } else if (t == 'multi') {
      qType += '多选题';
    } else if (t == 'fill') {
      qType += '填空题';
    } else if (t == 'short') {
      qType += '简答题';
    } else {
      qType += '其他';
    }

    StringBuffer sb = StringBuffer();
    sb.writeln(prefix);
    sb.writeln(questionText);
    sb.writeln();
    sb.writeln(qType);

    if (question['options'] != null && (question['options'] as List).isNotEmpty) {
      List<String> options = List<String>.from(question['options'] ?? []);
      for (int i = 0; i < options.length; i++) {
        sb.writeln('${String.fromCharCode(65 + i)}. ${options[i]}');
      }
      sb.writeln();
    }

    sb.writeln('标准答案：$standardAnswer');
    sb.writeln('我的答案：$userAnswer');

    final aiQuestion = sb.toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatPage(initialQuestion: aiQuestion),
      ),
    );
  }

  // ==================== 平板1:2分栏布局 ====================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    if (!isTablet) {
      return _buildMobileLayout();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1890FF)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          paperTitle,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Row(
        children: [
          Expanded(flex: 1, child: _buildLeftPanel()),
          Expanded(flex: 2, child: _buildRightPanel()),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "试卷信息",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
            ),
            const SizedBox(height: 20),
            _buildInfoCard("试卷名称", paperTitle, Icons.article),
            const SizedBox(height: 12),
            _buildInfoCard("交卷时间", submitTime, Icons.access_time),
            const SizedBox(height: 12),
            _buildScoreCard("总得分", totalScore, totalQuestionScore, Icons.emoji_events),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              "各题型得分",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF666666)),
            ),
            const SizedBox(height: 12),
            if (singleList.isNotEmpty)
              _buildTypeScoreCard("单选题", singleScore, singleTotalScore, Icons.check_circle, Colors.blue),
            if (multiList.isNotEmpty)
              _buildTypeScoreCard("多选题", multiScore, multiTotalScore, Icons.done_all, Colors.purple),
            if (fillList.isNotEmpty)
              _buildTypeScoreCard("填空题", fillScore, fillTotalScore, Icons.edit, Colors.orange),
            if (shortList.isNotEmpty)
              _buildTypeScoreCard("简答题", shortScore, shortTotalScore, Icons.article, Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1890FF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF1890FF), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(value.isEmpty ? '--' : value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCard(String label, num score, num total, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1890FF), Color(0xFF096DD9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1890FF).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 6),
                Text(
                  "$score / $total",
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeScoreCard(String type, num score, num total, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(type, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const Spacer(),
          Text(
            "$score / $total",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    if (loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载答卷详情...', style: TextStyle(fontSize: 14, color: Colors.black54)),
          ],
        ),
      );
    }

    if (singleList.isEmpty && multiList.isEmpty && fillList.isEmpty && shortList.isEmpty) {
      return const Center(
        child: Text('暂无答题记录', style: TextStyle(fontSize: 16, color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (singleList.isNotEmpty) _buildTypeSection('单选题', Icons.description, singleList, singleScore, singleTotalScore),
          if (multiList.isNotEmpty) _buildTypeSection('多选题', Icons.push_pin, multiList, multiScore, multiTotalScore),
          if (fillList.isNotEmpty) _buildTypeSection('填空题', Icons.edit, fillList, fillScore, fillTotalScore),
          if (shortList.isNotEmpty) _buildTypeSection('简答题', Icons.article, shortList, shortScore, shortTotalScore),
        ],
      ),
    );
  }

  Widget _buildTypeSection(String title, IconData icon, List list, score, total) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xff1890ff).withValues(alpha: 0.12), const Color(0xff1890ff).withValues(alpha: 0.05)],
              ),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xff1890ff)),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff1890ff))),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xffff7a2f).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('得分：$score / $total', style: const TextStyle(color: Color(0xffff7a2f), fontSize: 13)),
                ),
              ],
            ),
          ),
          ...list.asMap().entries.map((item) {
            int i = item.key;
            var q = item.value;
            return _questionItem(q, i + 1);
          }),
        ],
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
          // 🔥 平板端适配：使用 renderMixedText 替代 renderMathText
          FormulaRenderer.renderMixedText(
            q['title'],
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),

          if (q['imgUrl'] != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Image.network(
                q['imgUrl'].startsWith('http') ? q['imgUrl'] : '$baseUrl${q['imgUrl']}',
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
                    Text('${String.fromCharCode(65 + j)}.'),
                    const SizedBox(width: 6),
                    Expanded(
                      // 🔥 平板端适配：使用 renderMixedText 替代 renderMathText
                      child: FormulaRenderer.renderMixedText(
                        opt,
                        style: const TextStyle(fontSize: 14),
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
                Text('我的答案：${q['userAnswer'] ?? '未作答'}'),
                const SizedBox(height: 6),
                Text('标准答案：${q['standardAnswer'] ?? '无'}'),
              ],
            ),
          ),

          const SizedBox(height: 10),
          // 🔥 平板端适配：使用 renderMixedText 替代 renderMathText
          FormulaRenderer.renderMixedText(
            '📖 解析：${q['analysis'] ?? '暂无解析'}',
            style: const TextStyle(color: Colors.black54, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ==================== 手机端布局 ====================
  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
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
          if (loading)
            const Center(
              child: Text('正在加载答卷详情...', style: TextStyle(fontSize: 16, color: Colors.black54)),
            )
          else
            SingleChildScrollView(
              padding: const EdgeInsets.only(top: 90, left: 16, right: 16, bottom: 60),
              child: Column(
                children: [
                  _paperHeader(),
                  if (singleList.isNotEmpty) _buildTypeSection('单选题', Icons.description, singleList, singleScore, singleTotalScore),
                  if (multiList.isNotEmpty) _buildTypeSection('多选题', Icons.push_pin, multiList, multiScore, multiTotalScore),
                  if (fillList.isNotEmpty) _buildTypeSection('填空题', Icons.edit, fillList, fillScore, fillTotalScore),
                  if (shortList.isNotEmpty) _buildTypeSection('简答题', Icons.article, shortList, shortScore, shortTotalScore),

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
                ],
              ),
            ),

          Positioned(
            top: 60,
            left: 20,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 100,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset.zero)],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_back_ios, size: 16, color: Color(0xff1890ff)),
                    SizedBox(width: 4),
                    Text('返回', style: TextStyle(color: Color(0xff1890ff), fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paperHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset.zero)],
      ),
      child: Column(
        children: [
          Text(
            paperTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('交卷时间：$submitTime'),
              Text('总分：$totalScore / $totalQuestionScore'),
            ],
          ),
        ],
      ),
    );
  }
}
