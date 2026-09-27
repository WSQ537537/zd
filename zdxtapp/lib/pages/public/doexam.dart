import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import 'dart:async';
import 'package:zdxtapp/utils/formula_renderer.dart';
import 'package:zdxtapp/utils/toast.dart';

class DoExamPage extends StatefulWidget {
  final String paperId;
  const DoExamPage({super.key, required this.paperId});

  @override
  State<DoExamPage> createState() => _DoExamPageState();
}

class _DoExamPageState extends State<DoExamPage> {
  final String baseUrl = Config.baseUrl;

  // 试卷信息
  String paperTitle = "";
  String subject = "";
  String examMode = ""; // totalTime / perQuestion
  int totalTime = 600;

  // 题目
  List<dynamic> questions = [];
  int currentIndex = 0;
  dynamic userAnswer;
  List<dynamic> answerList = [];

  // 计时
  int timeLeft = 0;
  int totalTimeLeft = 0;
  Timer? perTimer;
  Timer? totalTimer;

  bool loading = true;
  bool _isSubmitting = false;
  String account = "";
  String userRemark = "";

  // 填空专用
  List<String> fillAnswers = [];
  int fillBlankCount = 0;
  
  // 🔥 核心修复：填空题的 TextEditingController 列表，避免每次重建
  List<TextEditingController> fillControllers = [];
  
  // 🔥 核心修复：简答题的 TextEditingController，避免每次重建
  TextEditingController? shortAnswerController;

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
    // 🔥 核心修复：清理填空题控制器
    for (var controller in fillControllers) {
      controller.dispose();
    }
    // 🔥 核心修复：清理简答题控制器
    shortAnswerController?.dispose();
    super.dispose();
  }

  // 格式化时间
  String formatTime(int seconds) {
    int min = seconds ~/ 60;
    int sec = seconds % 60;
    return "${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
  }

  // 题型文字
  String getQuestionTypeText(String type) {
    switch (type) {
      case "single": return "单选题";
      case "multi": return "多选题";
      case "fill": return "填空题";
      case "short": return "简答题";
      default: return "未知题型";
    }
  }

  // 获取当前题目
  dynamic get currentQuestion {
    if (questions.isEmpty || currentIndex < 0 || currentIndex >= questions.length) return null;
    return questions[currentIndex];
  }

  // 加载试卷
  Future<void> fetchPaperAndQuestions() async {
    setState(() => loading = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/exam'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "getExamById",
        "examId": widget.paperId,
      }),
      )).body);
      if (data["success"] == true) {
        final d = data["data"];
        final questionsList = d["questions"] ?? [];
        
        //  核心修复：先计算第一题的计时时间，避免使用未更新的 currentQuestion
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
      // ignore: avoid_print
      print(e);
    } finally {
      setState(() => loading = false);
    }
  }

  // 初始化当前题答案
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
      
      // 🔥 核心修复：初始化或更新填空题控制器
      if (fillControllers.length != cnt) {
        // dispose 旧控制器
        for (var controller in fillControllers) {
          controller.dispose();
        }
        // 创建新控制器
        fillControllers = List.generate(cnt, (i) => TextEditingController(text: fillAnswers[i]));
      } else {
        // 更新现有控制器的文本
        for (int i = 0; i < cnt; i++) {
          fillControllers[i].text = fillAnswers[i];
        }
      }
      
      userAnswer = fillAnswers.join(';');
    } else if (type == "short") {
      // 🔥 核心修复：初始化简答题控制器
      String ansText = ans?.toString() ?? '';
      if (shortAnswerController == null) {
        shortAnswerController = TextEditingController(text: ansText);
      } else {
        shortAnswerController!.text = ansText;
      }
      userAnswer = ansText;
    } else {
      userAnswer = ans;
    }
    // 无需额外setState，initCurrentAnswer已通过上方逻辑更新界面
  }

  // 自动计算填空空数
  int getRealBlankCount(Map q) {
    String title = q["title"] ?? "";
    int c1 = RegExp(r'\([^)]*\)').allMatches(title).length;
    int c2 = RegExp(r'_{2,}').allMatches(title).length;
    int c3 = RegExp(r'（.*?）').allMatches(title).length;
    int c4 = RegExp(r'\[.*?\]').allMatches(title).length;
    int maxCount = [c1, c2, c3, c4].reduce((a, b) => a > b ? a : b);
    return maxCount > 0 ? maxCount : 1;
  }

  // 开启考试计时
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
              debugPrint(' [分题计时] 切换到第${currentIndex + 1}题');
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

  // 选项选择
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

  // 保存答案
  void saveAnswer() {
    if (currentQuestion == null) return;
    if (currentQuestion["type"] == "fill") {
      String ans = fillAnswers.join(';');
      answerList[currentIndex] = ans;
    } else {
      answerList[currentIndex] = userAnswer;
    }
  }

  // 上一题
  void prevQuestion() {
    if (currentIndex <= 0) return;
    saveAnswer();
    setState(() => currentIndex--);
    initCurrentAnswer();
    if (examMode == "perQuestion") {
      perTimer?.cancel();
      
      // 🔥 核心修复：等待setState完成后再获取新题目的时间
      Future.delayed(Duration.zero, () {
        if (mounted && currentQuestion != null) {
          final newTime = currentQuestion["questionTime"] ?? 30;
          debugPrint(' [分题计时] 切换到上一题（第${currentIndex + 1}题）');
          debugPrint('   题目时间: $newTime');
          
          setState(() {
            timeLeft = newTime;
          });
          startPerQuestionTimer();
        }
      });
    }
  }

  // 下一题
  void nextQuestion() {
    if (questions.isNotEmpty && currentIndex >= questions.length - 1) return;
    saveAnswer();
    setState(() => currentIndex++);
    initCurrentAnswer();
    if (examMode == "perQuestion") {
      perTimer?.cancel();
      
      // 🔥 核心修复：等待setState完成后再获取新题目的时间
      Future.delayed(Duration.zero, () {
        if (mounted && currentQuestion != null) {
          final newTime = currentQuestion["questionTime"] ?? 30;
          debugPrint(' [分题计时] 切换到下一题（第${currentIndex + 1}题）');
          debugPrint('   题目时间: $newTime');
          
          setState(() {
            timeLeft = newTime;
          });
          startPerQuestionTimer();
        }
      });
    }
  }

  // 交卷
  Future<void> submitPaper() async {
    if (_isSubmitting) return;
    _isSubmitting = true;
    perTimer?.cancel();
    totalTimer?.cancel();
    saveAnswer();

    ToastUtil.show(context, "提交中...");

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
        Uri.parse('$baseUrl/api/exam'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      ToastUtil.showSuccess(context, "交卷成功");
      
      // ✅ 核心修复：返回true标记，触发父页面刷新
      Navigator.of(context).pop(true);
    } catch (e) {
      _isSubmitting = false;
      if (!mounted) return;
      ToastUtil.showError(context, "提交失败");
    }
  }

  // 🔥 新方式：使用FormulaRenderer渲染题目内容（支持公式）
  Widget renderQuestionContent(String? content) {
    if (content == null || content.isEmpty) return const SizedBox();
    
    // 🔥 关键修复：直接传入原始文本，FormulaRenderer 内部会自动预处理
    // 不再需要页面级别的预处理，避免双重预处理导致的问题
    return FormulaRenderer.renderMixedText(
      content,
      style: const TextStyle(fontSize: 16),
    );
  }

  // 🔥 退出答题确认弹窗（dialogCtx 由调用方传入，保证弹窗关闭后仍能正确 pop）
  void _showExitConfirmDialog(BuildContext dialogCtx) {
    showDialog(
      context: dialogCtx,
      barrierColor: Colors.black54,
      builder: (overlayCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("退出答题"),
        content: const Text(
          "确认要退出吗？退出将不保留本次答题痕迹，下次进入将重新作答。",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(overlayCtx),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () {
              perTimer?.cancel();
              totalTimer?.cancel();
              Navigator.pop(dialogCtx); // 关闭弹窗
              Navigator.pop(dialogCtx); // 退出答题页
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("确认"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showExitConfirmDialog(context);
        } else {
          perTimer?.cancel();
          totalTimer?.cancel();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: Column(
          children: [
            // 🔥 1. 顶部固定区域（返回按钮 + 科目标题 + 计时 + 试卷标题）
            SizedBox(
              height: MediaQuery.of(context).padding.top + 110, // 🔥 精确高度：状态栏 + 白色卡片容器高度（约102px）+ 微调
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 整体白色背景容器
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // 第一排：返回按钮 + 科目标题 + 倒计时
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 左侧：返回按钮
                              InkWell(
                                onTap: () => _showExitConfirmDialog(context),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: const Text("←", style: TextStyle(color: Color(0xFF1890FF), fontSize: 18, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              
                              // 中间：科目标题
                              Expanded(
                                child: Text(
                                  subject,
                                  style: const TextStyle(color: Color(0xFF1890FF), fontSize: 15, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              
                              // 右侧：倒计时（带标签）
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: examMode == "perQuestion" ? const Color(0xFFFFF3F3) : const Color(0xFFF0F7FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  examMode == "perQuestion"
                                      ? "本题 ${formatTime(timeLeft)}"
                                      : "考试 ${formatTime(totalTimeLeft)}",
                                  style: TextStyle(
                                    color: examMode == "perQuestion" ? Colors.red : const Color(0xFF1890FF),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 10),
                          
                          // 第二排：试卷标题（居中）
                          Text(
                            paperTitle,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),  // 🔥 修复：Positioned 结束
                ],    // 🔥 Stack children 结束
              ),
            ),

            // 🔥 2. 中间可滚动内容区（占据剩余空间）
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      top: 0, // 🔥 紧贴顶部栏下边界，无间距
                      left: 16,
                      right: 16,
                      bottom: 16,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth, // 🔥 确保子元素至少有这么宽
                        maxWidth: constraints.maxWidth, // 🔥 关键修复：限制最大宽度，确保自动换行
                      ),
                      child: loading
                          ? Column(
                              children: [
                                const SizedBox(height: 100),
                                const CircularProgressIndicator(),
                                const SizedBox(height: 20),
                                Text("加载试卷中...", style: TextStyle(color: Colors.grey[600])),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                          // 题目
                          if (currentQuestion != null)
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 题号 + 分值
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("第${currentIndex + 1}题 / 共${questions.length}题"),
                                      Text("${currentQuestion["score"] ?? 0}分", style: const TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(getQuestionTypeText(currentQuestion["type"]), style: const TextStyle(color: Color(0xFF1890FF))),
                                  const SizedBox(height: 12),

                                  // 🔥 简化方案：使用 Container 限制最大宽度，直接控制换行
                                  renderQuestionContent(currentQuestion["title"]),
                                  const SizedBox(height: 12),

                                  // 图片
                                  if (currentQuestion["imgUrl"] != null && currentQuestion["imgUrl"].isNotEmpty)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(currentQuestion["imgUrl"], fit: BoxFit.cover),
                                    ),

                                  const SizedBox(height: 20),

                                  // 单选 / 多选
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
                                          margin: const EdgeInsets.only(bottom: 10),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: selected ? const Color(0xFF1890FF) : Colors.grey.shade300),
                                            borderRadius: BorderRadius.circular(10),
                                            color: selected ? const Color(0xFFE6F7FF) : Colors.white,
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text("$label. ", style: const TextStyle(fontSize: 16)),
                                              // 🔥 修复：使用 Flexible 让选项自然换行
                                              Flexible(
                                                fit: FlexFit.loose,
                                                child: renderQuestionContent(opt),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),

                                  // 填空
                                  if (currentQuestion["type"] == "fill")
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text("请按顺序填写答案：", style: TextStyle(color: Colors.grey, fontSize: 14)),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: List.generate(fillBlankCount, (index) {
                                            return SizedBox(
                                              width: 150,
                                              child: TextField(
                                                controller: fillControllers[index],
                                                decoration: InputDecoration(
                                                  labelText: "第${index + 1}空",
                                                  border: const OutlineInputBorder(),
                                                ),
                                                onChanged: (val) {
                                                  fillAnswers[index] = val;
                                                  userAnswer = fillAnswers.join(';');
                                                },
                                              ),
                                            );
                                          }),
                                        ),
                                      ],
                                    ),

                                  // 简答
                                  if (currentQuestion["type"] == "short")
                                    TextField(
                                      controller: shortAnswerController,
                                      maxLines: 5,
                                      decoration: const InputDecoration(
                                        hintText: "请输入答案",
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          userAnswer = val;
                                        });
                                      },
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
            ), // ✅ 关闭 ConstrainedBox

            // 🔥 3. 底部按钮区（Column布局中固定在底部）
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12, // 🔥 适配底部安全区
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
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (examMode == "totalTime" && currentIndex > 0)
                    ElevatedButton(
                      onPressed: prevQuestion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1890FF),
                        side: const BorderSide(color: Color(0xFF1890FF)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: const Text("上一题"),
                    ),
                  if (currentIndex < questions.length - 1)
                    ElevatedButton(
                      onPressed: nextQuestion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1890FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: const Text("下一题"),
                    ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: submitPaper,
                    child: const Text("交卷"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
