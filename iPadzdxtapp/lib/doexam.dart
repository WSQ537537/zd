import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'utils/toast.dart';
import 'dart:async';
import 'formula_renderer.dart';

class DoExamPage extends StatefulWidget {
  final String paperId;
  const DoExamPage({super.key, required this.paperId});

  @override
  State<DoExamPage> createState() => _DoExamPageState();
}

class _DoExamPageState extends State<DoExamPage> {
  final String baseUrl = Config.baseUrl;

  String paperTitle = "";
  String subject = "";
  String examMode = "";
  int totalTime = 600;

  List<dynamic> questions = [];
  int currentIndex = 0;
  dynamic userAnswer;
  List<dynamic> answerList = [];

  int timeLeft = 0;
  int totalTimeLeft = 0;
  Timer? perTimer;
  Timer? totalTimer;

  bool loading = true;
  String account = "";
  String userRemark = "";

  List<String> fillAnswers = [];
  int fillBlankCount = 0;
  
  final Map<int, TextEditingController> shortAnswerControllers = {};
  final Map<int, List<TextEditingController>> fillControllers = {};
  
  // 🔥 新增：追踪最大已答题目索引（用于顺序推进控制）
  int maxAnsweredIndex = -1; // -1 表示还未答过任何题目

  @override
  void initState() {
    super.initState();
    initUserInfo();
  }

  Future<void> initUserInfo() async {
    final sp = await SharedPreferences.getInstance();
    final userInfo = sp.getString("userInfo");
    if (userInfo != null && userInfo.isNotEmpty) {
      final info = jsonDecode(userInfo);
      account = info["account"] ?? "";
      userRemark = info["remark"] ?? "";
    }
    fetchPaperAndQuestions();
  }

  @override
  void dispose() {
    perTimer?.cancel();
    totalTimer?.cancel();
    for (var controller in shortAnswerControllers.values) {
      controller.dispose();
    }
    for (var controllers in fillControllers.values) {
      for (var c in controllers) {
        c.dispose();
      }
    }
    super.dispose();
  }

  String formatTime(int seconds) {
    int min = seconds ~/ 60;
    int sec = seconds % 60;
    return "${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
  }

  String getQuestionTypeText(String type) {
    switch (type) {
      case "single": return "单选题";
      case "multi": return "多选题";
      case "fill": return "填空题";
      case "short": return "简答题";
      default: return "未知题型";
    }
  }

  dynamic get currentQuestion {
    if (questions.isEmpty || currentIndex >= questions.length) return null;
    return questions[currentIndex];
  }

  Future<void> fetchPaperAndQuestions() async {
    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "getExamById",
          "examId": widget.paperId,
        }),
      );
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        final d = data["data"];
        final questionsList = d["questions"] ?? [];
        
        // 🔥 核心修复：先计算第一题的计时时间，避免使用未更新的 currentQuestion
        int firstQuestionTime = 30; // 默认30秒
        if (questionsList.isNotEmpty) {
          final firstQuestion = questionsList[0];
          firstQuestionTime = firstQuestion["questionTime"] ?? 30;
          
          // 调试日志
          debugPrint('🔔 [分题计时] 第一题信息:');
          debugPrint('   题目类型: ${firstQuestion["type"]}');
          debugPrint('   题目时间: ${firstQuestion["questionTime"]}');
          debugPrint('   使用计时: $firstQuestionTime');
        }
        
        setState(() {
          paperTitle = d["examName"] ?? "";
          subject = d["subject"] ?? "";
          examMode = d["timingType"] == "perQuestionTime" ? "perQuestion" : "totalTime";
          // 修复：安全地解析totalTime，避免FormatException
          int parsedTotalTime = 30; // 默认30秒
          try {
            if (d["totalTime"] != null) {
              parsedTotalTime = int.parse(d["totalTime"].toString());
            }
          } catch (e) {
            debugPrint('⚠️ 解析totalTime失败: ${d["totalTime"]}, 错误: $e');
            parsedTotalTime = 30; // 默认值
          }
          totalTime = parsedTotalTime;
          questions = questionsList;
          answerList = List.filled(questions.length, null);
          totalTimeLeft = totalTime;
          timeLeft = firstQuestionTime; // ✅ 使用提前计算的时间
        });
        
        // 调试日志
        debugPrint('🔔 [分题计时] 考试模式: $examMode');
        debugPrint('🔔 [分题计时] 初始计时: $timeLeft 秒');
        
        initCurrentAnswer();
        startExamMode();
      }
    } catch (e) {
      print(e);
    } finally {
      setState(() => loading = false);
    }
  }

  void initCurrentAnswer() {
    if (currentQuestion == null) return;
    final type = currentQuestion["type"];
    final ans = answerList[currentIndex];

    if (type == "multi") {
      userAnswer = ans ?? [];
    } else if (type == "fill") {
      int cnt = getRealBlankCount(currentQuestion);
      setState(() => fillBlankCount = cnt);
      List<String> arr = [];
      if (ans != null && ans is String) {
        arr = ans.split(RegExp(r'[;；]'));
      }
      fillAnswers = List.generate(cnt, (i) => arr.length > i ? arr[i] : "");
      // 管理填空题 Controller，避免每次 build 重建
      if (!fillControllers.containsKey(currentIndex)) {
        fillControllers[currentIndex] = List.generate(
          cnt,
          (i) => TextEditingController(text: fillAnswers[i]),
        );
      } else {
        // 如果空数变了，重建 controllers
        final existing = fillControllers[currentIndex]!;
        if (existing.length != cnt) {
          for (var c in existing) {
            c.dispose();
          }
          fillControllers[currentIndex] = List.generate(
            cnt,
            (i) => TextEditingController(text: fillAnswers[i]),
          );
        }
      }
      userAnswer = fillAnswers.join(';');
    } else if (type == "short") {
      if (!shortAnswerControllers.containsKey(currentIndex)) {
        shortAnswerControllers[currentIndex] = TextEditingController();
      }
      final controller = shortAnswerControllers[currentIndex]!;
      controller.text = ans?.toString() ?? "";
      userAnswer = controller.text;
    } else {
      userAnswer = ans;
    }
    setState(() {});
  }

  int getRealBlankCount(Map q) {
    String title = q["title"] ?? "";
    int c1 = RegExp(r'\([^)]*\)').allMatches(title).length;
    int c2 = RegExp(r'_{2,}').allMatches(title).length;
    int c3 = RegExp(r'（.*?）').allMatches(title).length;
    int c4 = RegExp(r'\[.*?\]').allMatches(title).length;
    int maxCount = [c1, c2, c3, c4].reduce((a, b) => a > b ? a : b);
    return maxCount > 0 ? maxCount : 1;
  }

  // 🔥 判断题目是否真正已作答
  bool _isQuestionAnswered(int index) {
    if (index >= answerList.length) return false;
    final answer = answerList[index];
    
    if (answer == null) return false;
    
    final question = questions[index];
    final type = question["type"];
    
    // 单选题：必须有非空字符串答案
    if (type == "single") {
      return answer is String && answer.isNotEmpty;
    }
    
    // 多选题：必须是非空列表且有选项
    if (type == "multi") {
      return answer is List && answer.isNotEmpty;
    }
    
    // 填空题：必须是包含非空内容的字符串
    if (type == "fill") {
      if (answer is! String || answer.isEmpty) return false;
      // 检查是否有至少一个空填了内容
      final parts = answer.split(RegExp(r'[;；]'));
      return parts.any((part) => part.trim().isNotEmpty);
    }
    
    // 简答题：必须有非空字符串答案
    if (type == "short") {
      return answer is String && answer.trim().isNotEmpty;
    }
    
    return false;
  }

  List<Map<String, dynamic>> getOptions(Map question) {
    final opts = question["options"];
    if (opts == null || opts is! List) return [];
    return opts.map((e) => e as Map<String, dynamic>).toList();
  }

  void startExamMode() {
    if (examMode == "perQuestion") {
      startPerQuestionTimer();
    } else {
      startTotalTimer();
    }
  }

  void startPerQuestionTimer() {
    perTimer?.cancel();
    perTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timeLeft <= 0) {
        saveAnswer();
        if (currentIndex >= questions.length - 1) {
          submitPaper();
        } else {
          setState(() => currentIndex++);
          initCurrentAnswer();
          
          // 🔥 核心修复：等待setState完成后再获取新题目的时间
          Future.delayed(Duration.zero, () {
            if (mounted && currentQuestion != null) {
              final newTime = currentQuestion["questionTime"] ?? 30;
              debugPrint('🔔 [分题计时] 切换到第${currentIndex + 1}题');
              debugPrint('   题目类型: ${currentQuestion["type"]}');
              debugPrint('   题目时间: ${currentQuestion["questionTime"]}');
              debugPrint('   使用计时: $newTime');
              
              setState(() {
                timeLeft = newTime;
              });
            }
          });
        }
      } else {
        setState(() => timeLeft--);
      }
    });
  }

  void startTotalTimer() {
    totalTimer?.cancel();
    totalTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (totalTimeLeft <= 0) {
        submitPaper();
      } else {
        setState(() => totalTimeLeft--);
      }
    });
  }

  void selectAnswer(String optLabel) {
    final type = currentQuestion["type"];
    setState(() {
      if (type == "single") {
        userAnswer = optLabel;
      } else if (type == "multi") {
        if (userAnswer == null || userAnswer is! List) {
          userAnswer = [];
        }
        if (userAnswer.contains(optLabel)) {
          userAnswer.remove(optLabel);
        } else {
          userAnswer.add(optLabel);
        }
      }
    });
  }

  void saveAnswer() {
    if (currentQuestion == null) return;
    if (currentQuestion["type"] == "fill") {
      String ans = fillAnswers.join(';');
      answerList[currentIndex] = ans;
    } else {
      answerList[currentIndex] = userAnswer;
    }
    
    // 🔥 更新最大已答题目索引
    if (currentIndex > maxAnsweredIndex) {
      maxAnsweredIndex = currentIndex;
    }
  }

  void prevQuestion() {
    saveAnswer();
    setState(() => currentIndex--);
    initCurrentAnswer();
    if (examMode == "perQuestion") {
      perTimer?.cancel();
      
      // 🔥 核心修复：等待setState完成后再获取新题目的时间
      Future.delayed(Duration.zero, () {
        if (mounted && currentQuestion != null) {
          final newTime = currentQuestion["questionTime"] ?? 30;
          debugPrint('🔔 [分题计时] 切换到上一题（第${currentIndex + 1}题）');
          debugPrint('   题目时间: $newTime');
          
          setState(() {
            timeLeft = newTime;
          });
          startPerQuestionTimer();
        }
      });
    }
  }

  void nextQuestion() {
    saveAnswer();
    setState(() => currentIndex++);
    initCurrentAnswer();
    if (examMode == "perQuestion") {
      perTimer?.cancel();
      
      // 🔥 核心修复：等待setState完成后再获取新题目的时间
      Future.delayed(Duration.zero, () {
        if (mounted && currentQuestion != null) {
          final newTime = currentQuestion["questionTime"] ?? 30;
          debugPrint('🔔 [分题计时] 切换到下一题（第${currentIndex + 1}题）');
          debugPrint('   题目时间: $newTime');
          
          setState(() {
            timeLeft = newTime;
          });
          startPerQuestionTimer();
        }
      });
    }
  }

  Future<void> submitPaper() async {
    perTimer?.cancel();
    totalTimer?.cancel();
    saveAnswer();

    ToastUtil.show(context, "提交中..");

    final data = {
      "action": "submitExam",
      "account": account,
      "examId": widget.paperId,
      "remark": userRemark,
      "answers": questions.asMap().entries.map((e) {
        int i = e.key;
        var q = e.value;
        var a = answerList[i];
        if (q["type"] == "multi" && a is List) {
          a.sort();
          a = a.join('');
        }
        return {
          "questionTitle": q["title"],
          "answer": a,
          "score": q["score"],
          "type": q["type"],
          "standardAnswer": q["standardAnswer"],
          "analysis": q["analysis"],
        };
      }).toList(),
    };

    try {
      await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );
      if (!mounted) return;
      ToastUtil.show(context, "交卷成功");
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ToastUtil.show(context, "提交失败");
    }
  }

  // 使用FormulaRenderer渲染题目内容（支持公式）
  Widget renderQuestionContent(String? content) {
    if (content == null || content.isEmpty) return const SizedBox();
    
    // 🔥 关键修复：直接传入原始文本，FormulaRenderer 内部会自动预处理
    // 不再需要页面级别的预处理，避免双重预处理导致的问题
    // 🔥 平板端适配：使用 renderMixedText 替代 renderMathText
    return FormulaRenderer.renderMixedText(
      content,
      style: const TextStyle(fontSize: 16),
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

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        perTimer?.cancel();
        totalTimer?.cancel();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF1890FF)),
            onPressed: () {
              perTimer?.cancel();
              totalTimer?.cancel();
              Navigator.pop(context);
            },
          ),
          title: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF1890FF),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(subject, style: const TextStyle(color: Color(0xFF1890FF), fontSize: 14)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  paperTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: examMode == "perQuestion" ? const Color(0xFFFFF3F3) : const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                examMode == "perQuestion"
                    ? "本题: ${formatTime(timeLeft)}"
                    : "总时: ${formatTime(totalTimeLeft)}",
                style: TextStyle(
                  color: examMode == "perQuestion" ? Colors.red : const Color(0xFF1890FF),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        body: Row(
          children: [
            Expanded(flex: 1, child: _buildLeftPanel()),
            Expanded(flex: 2, child: _buildRightPanel()),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildLeftPanel() {
    // 🔥 按题型分组
    final Map<String, List<int>> typeGroups = {};
    for (int i = 0; i < questions.length; i++) {
      final type = questions[i]["type"] ?? "unknown";
      if (!typeGroups.containsKey(type)) {
        typeGroups[type] = [];
      }
      typeGroups[type]!.add(i);
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFF5F7FA),
            child: Column(
              children: [
                Text(
                  "答题卡",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "${currentIndex + 1} / ${questions.length}",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1890FF)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: typeGroups.length,
              itemBuilder: (context, groupIndex) {
                final entry = typeGroups.entries.elementAt(groupIndex);
                final type = entry.key;
                final indices = entry.value;
                
                return _buildTypeGroup(type, indices);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  // 🔥 构建题型分组
  Widget _buildTypeGroup(String type, List<int> indices) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 题型标题 - 居中对齐
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              getQuestionTypeText(type),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ),
        // 题号网格
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: indices.map((index) => _buildQuestionNumber(index)).toList(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
  
  // 🔥 构建单个题号按钮
  Widget _buildQuestionNumber(int index) {
    final isCurrent = index == currentIndex;
    // 🔥 修复高亮判断逻辑：只有真正有答案才标记为已答
    final isAnswered = _isQuestionAnswered(index);
    
    // 🔥 判断是否可点击：
    // 总计时模式：所有题目都可点击跳转
    // 分题计时模式：只有当前题目和已完成的题目（index <= maxAnsweredIndex）可点击
    final isClickable = examMode == "totalTime" 
        ? true  // 总计时模式：自由跳转
        : (isCurrent || (index <= maxAnsweredIndex));  // 分题计时：顺序推进
    
    // 确定颜色 - 修复：只有当前题目才高亮显示
    Color bgColor;
    Color textColor;
    Color borderColor;
    
    if (isCurrent) {
      // 当前正在作答：蓝色高亮
      bgColor = const Color(0xFF1890FF);
      textColor = Colors.white;
      borderColor = const Color(0xFF1890FF);
    } else if (isAnswered) {
      // 已完成作答：绿色标识
      bgColor = const Color(0xFFE6F7FF);
      textColor = Colors.green.shade700;
      borderColor = Colors.green.shade300;
    } else {
      // 未作答：灰色
      bgColor = Colors.grey.shade100;
      textColor = Colors.grey.shade500;
      borderColor = Colors.grey.shade300;
    }
    
    return GestureDetector(
      onTap: isClickable ? () {
        saveAnswer();
        setState(() => currentIndex = index);
        initCurrentAnswer();
        // 分题计时模式下跳题时重置计时器
        if (examMode == "perQuestion") {
          perTimer?.cancel();
          if (currentQuestion != null) {
            final newTime = currentQuestion["questionTime"] ?? 30;
            setState(() => timeLeft = newTime);
          }
          startPerQuestionTimer();
        }
      } : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: isCurrent ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            "${index + 1}",
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return loading
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text("加载试卷中..", style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: currentQuestion != null
                ? Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
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
                            Text(
                              "第 ${currentIndex + 1} 题",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              "${currentQuestion["score"] ?? 0}分",
                              style: const TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          getQuestionTypeText(currentQuestion["type"]),
                          style: const TextStyle(color: Color(0xFF1890FF), fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        renderQuestionContent(currentQuestion["title"]),
                        const SizedBox(height: 16),
                        if (currentQuestion["imgUrl"] != null && currentQuestion["imgUrl"].isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(currentQuestion["imgUrl"], fit: BoxFit.cover),
                          ),
                        // 🔥 只读模式提示（仅分题计时模式）
                        if (examMode == "perQuestion" && currentIndex < maxAnsweredIndex)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  "此题已作答，仅可查看",
                                  style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),
                        _buildAnswerArea(),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          );
  }

  Widget _buildAnswerArea() {
    // 🔥 判断是否只读：仅在分题计时模式下，当前查看的题目索引小于最大已答题目索引时，表示是历史题目，只能查看
    // 总计时模式下不限制编辑权限
    final isReadOnly = examMode == "perQuestion" && currentIndex < maxAnsweredIndex;
    
    if (["single", "multi"].contains(currentQuestion["type"])) {
      return Column(
        children: List.generate(currentQuestion["options"].length, (i) {
          String opt = currentQuestion["options"][i];
          String label = String.fromCharCode(65 + i);
          bool selected = false;
          if (currentQuestion["type"] == "single") {
            selected = userAnswer == label;
          } else if (currentQuestion["type"] == "multi") {
            selected = userAnswer != null && userAnswer.contains(label);
          }
          
          return isReadOnly
              ? _buildReadOnlyOption(label, opt, selected)
              : GestureDetector(
                  onTap: () => selectAnswer(label),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: selected ? const Color(0xFF1890FF) : Colors.grey.shade300, width: 2),
                      borderRadius: BorderRadius.circular(10),
                      color: selected ? const Color(0xFFE6F7FF) : Colors.white,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF1890FF) : Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: selected ? Colors.white : Colors.grey.shade700,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: renderQuestionContent(opt),
                        ),
                      ],
                    ),
                  ),
                );
        }),
      );
    }

    if (currentQuestion["type"] == "fill") {
      final controllers = fillControllers[currentIndex] ?? [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("请按顺序填写答案", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(fillBlankCount, (index) {
              return SizedBox(
                width: 160,
                child: TextField(
                  onChanged: isReadOnly ? null : (val) {
                    fillAnswers[index] = val;
                    userAnswer = fillAnswers.join(';');
                  },
                  controller: index < controllers.length ? controllers[index] : TextEditingController(text: fillAnswers[index]),
                  decoration: InputDecoration(
                    labelText: "空 ${index + 1}",
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  style: const TextStyle(fontSize: 16),
                  enabled: !isReadOnly,
                  readOnly: isReadOnly,
                ),
              );
            }),
          ),
        ],
      );
    }

    if (currentQuestion["type"] == "short") {
      return TextField(
        controller: shortAnswerControllers[currentIndex],
        onChanged: isReadOnly ? null : (val) {
          userAnswer = val;
          if (answerList.length <= currentIndex) {
            answerList.addAll(List.filled(currentIndex - answerList.length + 1, null));
          }
          answerList[currentIndex] = val;
        },
        maxLines: 8,
        decoration: InputDecoration(
          hintText: isReadOnly ? "（此题已作答，仅可查看）" : "请输入答案",
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        style: const TextStyle(fontSize: 16),
      );
    }

    return const SizedBox.shrink();
  }
  
  // 🔥 构建只读选项（用于查看历史答案）
  Widget _buildReadOnlyOption(String label, String opt, bool selected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(10),
        color: Colors.grey.shade50,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: selected ? Colors.green : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: renderQuestionContent(opt),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    // 🔥 判断是否只读：仅在分题计时模式下，当前查看的题目索引小于最大已答题目索引时
    // 总计时模式下不限制导航
    final isReadOnly = examMode == "perQuestion" && currentIndex < maxAnsweredIndex;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 🔥 只读模式下不显示导航按钮
          if (!isReadOnly && examMode == "totalTime" && currentIndex > 0) ...[
            ElevatedButton.icon(
              onPressed: prevQuestion,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text("上一题"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (!isReadOnly && currentIndex < questions.length - 1) ...[
            ElevatedButton.icon(
              onPressed: nextQuestion,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text("下一题"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1890FF),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          ElevatedButton.icon(
            onPressed: submitPaper,
            icon: const Icon(Icons.check, size: 18),
            label: const Text("交卷"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 手机端布局（保持原样）====================
  Widget _buildMobileLayout() {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        perTimer?.cancel();
        totalTimer?.cancel();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: loading
                  ? const SizedBox.shrink()
                  : Container(
                      padding: const EdgeInsets.fromLTRB(16, 95, 16, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1890FF),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(subject, style: const TextStyle(color: Color(0xFF1890FF), fontSize: 14)),
                                ],
                              ),
                              Flexible(
                                child: Text(
                                  paperTitle,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: examMode == "perQuestion" ? const Color(0xFFFFF3F3) : const Color(0xFFF0F7FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              examMode == "perQuestion"
                                  ? "本题剩余: ${formatTime(timeLeft)}"
                                  : "考试剩余: ${formatTime(totalTimeLeft)}",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: examMode == "perQuestion" ? Colors.red : const Color(0xFF1890FF),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Positioned.fill(
              top: examMode == "perQuestion" ? 190 : 180,
              bottom: 0,
              child: loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 20),
                          Text("加载试卷中..", style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final contentHeight = _calculateContentHeight(constraints.maxWidth);
                        final isShortContent = contentHeight < (constraints.maxHeight - 50);

                        return SingleChildScrollView(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 16,
                            bottom: isShortContent ? 16 : 100,
                          ),
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: currentQuestion != null
                              ? Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("${currentIndex + 1} / ${questions.length}", style: const TextStyle(fontSize: 14)),
                                          Text("${currentQuestion["score"] ?? 0}分", style: const TextStyle(color: Colors.red, fontSize: 14)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(getQuestionTypeText(currentQuestion["type"]), style: const TextStyle(color: Color(0xFF1890FF), fontSize: 13)),
                                      const SizedBox(height: 10),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final screenHeight = MediaQuery.of(context).size.height;
                                          final maxTitleHeight = screenHeight * 2 / 3;
                                          
                                          return ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: constraints.maxWidth,
                                              maxHeight: maxTitleHeight,
                                            ),
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.vertical,
                                              physics: const BouncingScrollPhysics(),
                                              child: renderQuestionContent(currentQuestion["title"]),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      if (currentQuestion["imgUrl"] != null && currentQuestion["imgUrl"].isNotEmpty)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(currentQuestion["imgUrl"], fit: BoxFit.cover),
                                        ),
                                      const SizedBox(height: 16),
                                      if (["single", "multi"].contains(currentQuestion["type"]))
                                        ...List.generate(currentQuestion["options"].length, (i) {
                                          String opt = currentQuestion["options"][i];
                                          String label = String.fromCharCode(65 + i);
                                          bool selected = false;
                                          if (currentQuestion["type"] == "single") {
                                            selected = userAnswer == label;
                                          } else if (currentQuestion["type"] == "multi") {
                                            selected = userAnswer != null && userAnswer.contains(label);
                                          }
                                          return GestureDetector(
                                            onTap: () => selectAnswer(label),
                                            child: Container(
                                              margin: const EdgeInsets.only(bottom: 8),
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              decoration: BoxDecoration(
                                                border: Border.all(color: selected ? const Color(0xFF1890FF) : Colors.grey.shade300),
                                                borderRadius: BorderRadius.circular(8),
                                                color: selected ? const Color(0xFFE6F7FF) : Colors.white,
                                              ),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text("$label. ", style: const TextStyle(fontSize: 14)),
                                                  Expanded(
                                                    child: LayoutBuilder(
                                                      builder: (context, optionConstraints) {
                                                        return ConstrainedBox(
                                                          constraints: BoxConstraints(
                                                            maxWidth: optionConstraints.maxWidth,
                                                            maxHeight: 100,
                                                          ),
                                                          child: SingleChildScrollView(
                                                            scrollDirection: Axis.vertical,
                                                            physics: const BouncingScrollPhysics(),
                                                            child: renderQuestionContent(opt),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                      if (currentQuestion["type"]?.toString().trim() == "fill")
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text("请按顺序填写答案", style: TextStyle(color: Colors.grey, fontSize: 13)),
                                            const SizedBox(height: 10),
                                            Builder(
                                              builder: (context) {
                                                final controllers = fillControllers[currentIndex] ?? [];
                                                return Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: List.generate(fillBlankCount, (index) {
                                                    return SizedBox(
                                                      width: 120,
                                                      child: TextField(
                                                        onChanged: (val) {
                                                          fillAnswers[index] = val;
                                                          userAnswer = fillAnswers.join(';');
                                                        },
                                                        controller: index < controllers.length ? controllers[index] : TextEditingController(text: fillAnswers[index]),
                                                        decoration: InputDecoration(
                                                          labelText: "${index + 1}",
                                                          border: const OutlineInputBorder(),
                                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                        ),
                                                        style: const TextStyle(fontSize: 14),
                                                      ),
                                                    );
                                                  }),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      if (currentQuestion["type"]?.toString().trim() == "short")
                                        TextField(
                                          controller: shortAnswerControllers[currentIndex],
                                          onChanged: (val) {
                                            userAnswer = val;
                                            if (answerList.length <= currentIndex) {
                                              answerList.addAll(List.filled(currentIndex - answerList.length + 1, null));
                                            }
                                            answerList[currentIndex] = val;
                                          },
                                          maxLines: 5,
                                          decoration: const InputDecoration(
                                            hintText: "请输入答案",
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                          ),
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        );
                      },
                    ),
            ),
            if (!loading && currentQuestion != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final contentHeight = _calculateContentHeight(constraints.maxWidth);
                    final isShortContent = contentHeight < (constraints.maxHeight - 50);

                    return Container(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: MediaQuery.of(context).padding.bottom + (isShortContent ? 8 : 12),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (examMode == "totalTime" && currentIndex > 0)
                            Expanded(
                              child: ElevatedButton(
                                onPressed: prevQuestion,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text("上一题", style: TextStyle(fontSize: 14)),
                              ),
                            ),
                          if (examMode == "totalTime" && currentIndex > 0) const SizedBox(width: 10),
                          if (currentIndex < questions.length - 1)
                            Expanded(
                              child: ElevatedButton(
                                onPressed: nextQuestion,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1890FF),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text("下一题", style: TextStyle(fontSize: 14)),
                              ),
                            ),
                          if (currentIndex < questions.length - 1) const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: submitPaper,
                              child: const Text("交卷", style: TextStyle(fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              child: Material(
                color: Colors.transparent,
                elevation: 4,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () {
                    perTimer?.cancel();
                    totalTimer?.cancel();
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 16, color: Color(0xFF1890FF)),
                        SizedBox(width: 4),
                        Text("返回", style: TextStyle(color: Color(0xFF1890FF), fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateContentHeight(double maxWidth) {
    if (currentQuestion == null) return 0;
    
    double height = 0;
    height += 40;
    String title = currentQuestion["title"] ?? "";
    int lines = (title.length / (maxWidth / 8)).ceil();
    height += (lines * 25).toDouble(); 
    if (currentQuestion["imgUrl"] != null && currentQuestion["imgUrl"].isNotEmpty) {
      height += 200;
    }
    if (["single", "multi"].contains(currentQuestion["type"])) {
      height += (currentQuestion["options"] as List).length * 50;
    } else if (currentQuestion["type"] == "fill") {
      height += fillBlankCount * 60;
    } else if (currentQuestion["type"] == "short") {
      height += 150;
    }
    
    return height;
  }
}
