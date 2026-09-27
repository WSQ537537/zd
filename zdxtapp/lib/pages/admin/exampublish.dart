import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🔥 添加 FilteringTextInputFormatter
import 'dart:convert';
import 'dart:async'; // 🔥 添加async库以使用scheduleMicrotask
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/pages/admin/exampublishai.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/formula_renderer.dart'; // 🔥 新公式渲染器 - 重新添加，因为需要实时预览功能

class Exampublish extends StatefulWidget {
  const Exampublish({super.key});

  @override
  State<Exampublish> createState() => ExampublishState();
}

class ExampublishState extends State<Exampublish> {
  final String baseUrl = Config.baseUrl;

  String mode = 'ai';
  String lightBtn = '';

  final List<String> subjectList = ['语文', '数学', '英语', '其他'];
  int subjectIndex = 0;

  String paperName = '';
  String questionScope = '';

  final List<String> examStatusList = ['自由', '强制'];
  int examStatusIndex = 0;

  String startTimeText = '';
  String endTimeText = '';

  late TextEditingController startYearController;
  late TextEditingController startMonthController;
  late TextEditingController startDayController;
  late TextEditingController startHourController;
  late TextEditingController startMinuteController;
  late TextEditingController startSecondController;

  late TextEditingController endYearController;
  late TextEditingController endMonthController;
  late TextEditingController endDayController;
  late TextEditingController endHourController;
  late TextEditingController endMinuteController;
  late TextEditingController endSecondController;

  String timeType = 'per';
  final List<String> timeUnits = ['分', '秒'];
  int totalTime = 0;
  int totalTimeUnitIndex = 1;

  late List<Map> questionTypes;

  String importContent = '';
  Map? paperResult;
  
  // 🔥 新增：AI 出题流式状态
  bool isAIGenerating = false; // AI是否正在生成
  String aiRawContent = ''; // AI流式返回的原始内容
  List<Map<String, dynamic>> aiParsedQuestions = []; // 已解析的题目列表
  
  // 🔥 核心修复：防抖定时器，避免频繁setState
  Timer? _parseDebounceTimer;
  
  // 🔥 新增：记录上次解析的题目数量，避免重复更新
  int _lastParsedCount = 0;

  // 🔥 核心修复：使用全局 TextEditingController 避免每次重建
  late TextEditingController paperNameController;
  late TextEditingController questionScopeController;
  late TextEditingController importContentController;

  // 🔥 核心修复：数值输入框使用稳定 key 的持久化控制器，避免每次重建泄漏
  final Map<String, TextEditingController> _numCtrls = {};

  TextEditingController _numCtrl(String key, int value) {
    return _numCtrls.putIfAbsent(
      key,
      () => TextEditingController(text: value.toString()),
    );
  }

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    final end = now.add(const Duration(hours: 24));

    // 🔥 初始化文本控制器
    paperNameController = TextEditingController(text: paperName);
    questionScopeController = TextEditingController(text: questionScope);
    importContentController = TextEditingController(text: importContent);

    startYearController = TextEditingController(text: now.year.toString());
    startMonthController = TextEditingController(text: pad2(now.month));
    startDayController = TextEditingController(text: pad2(now.day));
    startHourController = TextEditingController(text: pad2(now.hour));
    startMinuteController = TextEditingController(text: pad2(now.minute));
    startSecondController = TextEditingController(text: pad2(now.second));

    endYearController = TextEditingController(text: end.year.toString());
    endMonthController = TextEditingController(text: pad2(end.month));
    endDayController = TextEditingController(text: pad2(end.day));
    endHourController = TextEditingController(text: pad2(end.hour));
    endMinuteController = TextEditingController(text: pad2(end.minute));
    endSecondController = TextEditingController(text: pad2(end.second));

    _updateStartTimeString();
    _updateEndTimeString();

    questionTypes = [
      {'type': 'single', 'label': '单选题', 'count': 0, 'score': 2, 'time': 0, 'timeUnitIndex': 1},
      {'type': 'multi', 'label': '多选题', 'count': 0, 'score': 2, 'time': 0, 'timeUnitIndex': 1},
      {'type': 'fill', 'label': '填空题', 'count': 0, 'score': 2, 'time': 0, 'timeUnitIndex': 1},
      {'type': 'short', 'label': '简答题', 'count': 0, 'score': 5, 'time': 0, 'timeUnitIndex': 1},
    ];
  }

  String pad2(int n) => n.toString().padLeft(2, '0');

  void showToast(String msg) {
    ToastUtil.show(context, msg);
  }

  void _updateStartTimeString() {
    try {
      final year = int.parse(startYearController.text);
      final month = int.parse(startMonthController.text);
      final day = int.parse(startDayController.text);
      final hour = int.parse(startHourController.text);
      final minute = int.parse(startMinuteController.text);
      final second = int.parse(startSecondController.text);

      final dateTime = DateTime(year, month, day, hour, minute, second);
      setState(() {
        startTimeText =
            '${dateTime.year}-${pad2(dateTime.month)}-${pad2(dateTime.day)} ${pad2(dateTime.hour)}:${pad2(dateTime.minute)}:${pad2(dateTime.second)}';
      });
    } catch (e) {
      debugPrint('❌ 开始时间解析失败: $e');
    }
  }

  void _updateEndTimeString() {
    try {
      final year = int.parse(endYearController.text);
      final month = int.parse(endMonthController.text);
      final day = int.parse(endDayController.text);
      final hour = int.parse(endHourController.text);
      final minute = int.parse(endMinuteController.text);
      final second = int.parse(endSecondController.text);

      DateTime(year, month, day, hour, minute, second);
      setState(() {
        endTimeText =
            '$year-${pad2(month)}-${pad2(day)} ${pad2(hour)}:${pad2(minute)}:${pad2(second)}';
      });
    } catch (e) {
      debugPrint('❌ 结束时间解析失败: $e');
    }
  }

  void goBack() {
    Navigator.pop(context);
  }

  @override
  void dispose() {
    paperNameController.dispose();
    questionScopeController.dispose();
    importContentController.dispose();
    startYearController.dispose();
    startMonthController.dispose();
    startDayController.dispose();
    startHourController.dispose();
    startMinuteController.dispose();
    startSecondController.dispose();
    endYearController.dispose();
    endMonthController.dispose();
    endDayController.dispose();
    endHourController.dispose();
    endMinuteController.dispose();
    endSecondController.dispose();
    for (final c in _numCtrls.values) {
      c.dispose();
    }
    _numCtrls.clear();
    _parseDebounceTimer?.cancel(); // 🔥 核心修复：清理防抖定时器
    super.dispose();
  }

  void switchMode(String m) {
    setState(() => lightBtn = m);
    Future.delayed(const Duration(milliseconds: 150), () {
      setState(() {
        lightBtn = '';
        mode = m;
      });
    });
  }

  void toggleTimeUnit(int idx) {
    setState(() {
      questionTypes[idx]['timeUnitIndex'] = questionTypes[idx]['timeUnitIndex'] == 0 ? 1 : 0;
    });
    debugPrint('🔄 [时间单位] 题型 ${questionTypes[idx]['label']} 切换为: ${timeUnits[questionTypes[idx]['timeUnitIndex']]}');
  }

  void toggleTotalTimeUnit() {
    setState(() {
      totalTimeUnitIndex = totalTimeUnitIndex == 0 ? 1 : 0;
    });
    debugPrint('🔄 [时间单位] 总计时切换为: ${timeUnits[totalTimeUnitIndex]}');
  }

  int getQuestionScore(String type) {
    var item = questionTypes.firstWhere((e) => e['type'] == type, orElse: () => {'score': 0});
    return item['score'] ?? 0;
  }

  List getQuestionsByType(String type) {
    if (paperResult == null || paperResult!['questions'] == null) return [];

    final questions = paperResult!['questions'] as List;

    return questions.where((q) {
      String qType = (q['type'] ?? '').toString().toLowerCase();
      return qType == type;
    }).toList();
  }

  // 🔥 AI 出题
  Future<void> submitAI() async {
    if (paperName.trim().isEmpty) {
      ToastUtil.show(context, "请输入试卷名称");
      return;
    }

    if (questionScope.trim().isEmpty) {
      ToastUtil.show(context, "请输入出题范围");
      return;
    }

    try {
      setState(() {
        isAIGenerating = true;
        aiRawContent = '';  // 重置原始内容
        aiParsedQuestions = [];  // 重置解析的题目
        _lastParsedCount = 0;  // 🔥 核心修复：重置解析计数器
      });

      final params = {
        "paperName": paperName.trim(),
        "subject": subjectList[subjectIndex].trim(),
        "questionScope": questionScope.trim(),
        "questionTypes": [
          {"type":"single","label":"单选题","count":questionTypes[0]['count'] ?? 0,"score":questionTypes[0]['score'] ?? 0},
          {"type":"multi","label":"多选题","count":questionTypes[1]['count'] ?? 0,"score":questionTypes[1]['score'] ?? 0},
          {"type":"fill","label":"填空题","count":questionTypes[2]['count'] ?? 0,"score":questionTypes[2]['score'] ?? 0},
          {"type":"short","label":"简答题","count":questionTypes[3]['count'] ?? 0,"score":questionTypes[3]['score'] ?? 0},
        ],
      };

      debugPrint("📤 传给AI的完整参数: ${jsonEncode(params)}");

      // 🔥 修复3：调用流式生成方法，实时接收并解析
      await Exampublishai.generatePaperByAIStream(
        params,
        onChunkReceived: (String chunk) {
          // 实时接收原始内容
          if (!mounted) return;
          setState(() {
            aiRawContent += chunk;
          });
          
          // 🔥 尝试实时解析JSON（可能不完整，需要容错）
          _tryParseAIContent(aiRawContent);
        },
        onComplete: (Map<String, dynamic> result) {
          // 生成完成
          if (!mounted) return;
          setState(() {
            isAIGenerating = false;
            paperResult = result;
            aiRawContent = '';
            aiParsedQuestions = [];
          });
          ToastUtil.show(context, "试卷生成成功");
        },
        onError: (String error) {
          // 生成失败
          if (!mounted) return;
          setState(() {
            isAIGenerating = false;
            aiRawContent = '';
            aiParsedQuestions = [];
          });
          ToastUtil.show(context, "生成失败：$error");
        },
      );

    } catch (e) {
      if (!mounted) return;
      setState(() {
        isAIGenerating = false;
        aiRawContent = '';
        aiParsedQuestions = [];
      });
      ToastUtil.show(context, "生成失败：$e");
    }
  }

  // 🔥 新增：尝试实时解析 AI 返回的内容（带防抖）
  void _tryParseAIContent(String content) {
    // 🔥 核心修复：取消之前的定时器
    _parseDebounceTimer?.cancel();
    
    // 🔥 优化：减少防抖时间到200ms，提升实时性
    _parseDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      try {
        // 第1层：尝试直接解析整个内容
        try {
          final result = jsonDecode(content);
          if (result is Map && result['questions'] != null && result['questions'] is List) {
            _updateParsedQuestions(result['questions']);
            return;
          }
        } catch (e) {
          // 整个内容不能解析，继续下面的步骤
        }
        
        // 第2层：使用安全的JSON解析（处理不完整JSON）
        final safeResult = Exampublishai.safeJsonParse(content, silent: true); // 🔥 核心修复：静默模式，不打印错误日志
        if (safeResult != null && safeResult['questions'] != null && safeResult['questions'] is List) {
          _updateParsedQuestions(safeResult['questions']);
          return;
        }
        
        // 第3层：尝试找到最外层的JSON对象边界
        int braceLevel = 0;
        int startIdx = content.indexOf('{');
        if (startIdx == -1) return;
        
        String jsonCandidate = '';
        bool inString = false;
        bool escaped = false;
        
        for (int i = startIdx; i < content.length; i++) {
          String char = content[i];
          
          if (escaped) {
            jsonCandidate += char;
            escaped = false;
            continue;
          }
          
          if (char == '\\' && inString) {
            jsonCandidate += char;
            escaped = true;
            continue;
          }
          
          if (char == '"') {
            inString = !inString;
          }
          
          jsonCandidate += char;
          
          if (!inString) {
            if (char == '{') {
              braceLevel++;
            } else if (char == '}') {
              braceLevel--;
              if (braceLevel == 0) {
                // 找到了一个完整的JSON对象
                try {
                  final result = jsonDecode(jsonCandidate);
                  if (result is Map && result['questions'] != null && result['questions'] is List) {
                    _updateParsedQuestions(result['questions']);
                    return;
                  }
                } catch (e) {
                  // 继续寻找下一个可能的完整对象
                }
                jsonCandidate = '';
              }
            }
          }
        }
        
        // 第4层：如果还没找到完整的最外层对象，尝试解析内部的题目数组
        int questionsStartIndex = content.indexOf('"questions"');
        if (questionsStartIndex == -1) return;
        
        int arrayStartIndex = content.indexOf('[', questionsStartIndex);
        if (arrayStartIndex == -1) return;
        
        String arrayCandidate = '';
        int bracketLevel = 0;
        inString = false;
        escaped = false;
        
        for (int i = arrayStartIndex; i < content.length; i++) {
          String char = content[i];
          
          if (escaped) {
            arrayCandidate += char;
            escaped = false;
            continue;
          }
          
          if (char == '\\' && inString) {
            arrayCandidate += char;
            escaped = true;
            continue;
          }
          
          if (char == '"') {
            inString = !inString;
          }
          
          arrayCandidate += char;
          
          if (!inString) {
            if (char == '[') {
              bracketLevel++;
            } else if (char == ']') {
              bracketLevel--;
              if (bracketLevel == 0) {
                // 找到了完整的题目数组
                try {
                  String jsonArray = '{"questions": $arrayCandidate}';
                  final result = jsonDecode(jsonArray);
                  if (result is Map && result['questions'] != null && result['questions'] is List) {
                    _updateParsedQuestions(result['questions']);
                    return;
                  }
                } catch (e) {
                  // 即使解析失败也继续，可能只是部分内容
                }
                return;
              }
            }
          }
        }
        
      } catch (e) {
        // 🔥 核心修复：静默失败，不影响用户体验，只在debug模式下打印
        debugPrint('⚠️ 实时解析AI内容失败: $e');
      }
    });
  }

  // 🔥 辅助方法：更新解析的题目列表
  void _updateParsedQuestions(List questions) {
    try {
      // 🔥 核心修复：检查题目数量是否有变化，避免重复更新
      if (questions.length == _lastParsedCount) {
        // 题目数量没变，不更新（除非是首次）
        if (_lastParsedCount > 0) {
          return;
        }
      }
      
      // 🔥 核心修复：实时预览时直接使用原始内容
      // 原因：
      // 1. AI 返回的内容应该已经是正确的 LaTeX 格式（Prompt 中明确要求）
      // 2. 最终提交时会统一调用 formatPaperData 进行格式化
      // 3. 避免重复调用 wrapAndFormatLatex 导致的问题
      final formattedQuestions = questions.map((q) {
        try {
          return {
            ...q,
            // 🔥 直接使用原始内容，不做任何转换
            'title': q['title'] ?? '',
            'answer': q['answer'] ?? '',
            'analysis': q['analysis'] ?? '',
            'options': (q['options'] as List?)?.map((opt) => opt.toString()).toList() ?? [],
          };
        } catch (e) {
          debugPrint('⚠️ 单道题目格式化失败: $e');
          // 返回原始数据
          return q;
        }
      }).toList().cast<Map<String, dynamic>>();
      
      // 使用setState更新UI
      if (mounted) {
        setState(() {
          aiParsedQuestions = formattedQuestions;
          _lastParsedCount = questions.length; // 🔥 更新记录
        });
        
        // 🔥 调试：打印解析成功信息
        debugPrint('✅ [实时预览] 已解析 ${questions.length} 道题目');
      }
    } catch (e) {
      debugPrint('❌ 更新解析题目失败: $e');
    }
  }

  // ====================== 【核心：终极修复 - 先切大题型块，再解析题目，彻底杜绝串题】======================
  Future<void> parseImport() async {
    final content = importContent.trim();
    if (content.isEmpty) {
      showToast("请粘贴试卷内容");
      return;
    }
    if (paperName.isEmpty) {
      showToast("请输入试卷名称");
      return;
    }

    // 🔥 核心增强：添加详细调试日志
    debugPrint('\n🔍 ========================================');
    debugPrint('🔍 [导入出题] 开始解析文档');
    debugPrint('🔍 [导入出题] 文档总长度: ${content.length} 字符');
    debugPrint(' [导入出题] 文档预览（前500字符）:');
    debugPrint(content.substring(0, content.length > 500 ? 500 : content.length));
    debugPrint('🔍 ========================================\n');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final questions = _parseByTypeBlocksFirst(content);
      if (!mounted) return;
      Navigator.pop(context);

      if (questions.isEmpty) {
        // 🔥 核心增强：提供更详细的错误提示
        debugPrint('\n❌ ========================================');
        debugPrint('❌ [导入出题] 解析失败：未识别到有效题目');
        debugPrint(' [导入出题] 请检查文档是否包含以下题型标题：');
        debugPrint('❌   - 单选题');
        debugPrint('❌   - 多选题');
        debugPrint('❌   - 填空题');
        debugPrint('❌   - 简答题');
        debugPrint('❌ [导入出题] 每个题型标题必须单独占一行');
        debugPrint('❌ ========================================\n');
        
        showToast("未识别到有效题目，请检查格式（需包含「单选题」「多选题」「填空题」「简答题」标题）");
        return;
      }

      Map<String, int> typeCount = {
        "single": 0, "multi": 0, "fill": 0, "short": 0
      };
      for (var q in questions) {
        typeCount[q['type']] = (typeCount[q['type']] ?? 0) + 1;
      }

      setState(() {
        for (var t in questionTypes) {
          t['count'] = typeCount[t['type']] ?? 0;
        }

        final formattedQuestions = questions.map((q) {
          return {
            ...q,
            'title': Exampublishai.formatSpecialText(q['title'] ?? ''),
            'answer': Exampublishai.formatSpecialText(q['answer'] ?? ''),
            'analysis': Exampublishai.formatSpecialText(q['analysis'] ?? ''),
            'options': (q['options'] as List?)?.map((opt) => Exampublishai.formatSpecialText(opt.toString())).toList() ?? [],
          };
        }).toList();

        paperResult = {
          "paperName": paperName,
          "subject": subjectList[subjectIndex],
          "questions": formattedQuestions,
        };
      });

      debugPrint('\n✅ [导入出题] 解析成功！共 ${questions.length} 题');
      debugPrint('✅ [导入出题] 题型分布:');
      debugPrint('   - 单选题: ${typeCount["single"]} 题');
      debugPrint('   - 多选题: ${typeCount["multi"]} 题');
      debugPrint('   - 填空题: ${typeCount["fill"]} 题');
      debugPrint('   - 简答题: ${typeCount["short"]} 题');
      debugPrint('✅ ========================================\n');

      showToast("解析成功：共 ${questions.length} 题");
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      debugPrint('\n❌ [导入出题] 解析异常: $e');
      showToast("解析失败：$e");
    }
  }

  // 🔥 终极核心：先按大题型标题切分全文，再在块内解析
  List<Map<String, dynamic>> _parseByTypeBlocksFirst(String text) {
    List<Map<String, dynamic>> allQuestions = [];

    // 预处理：统一换行
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return allQuestions;

    // 🔥 核心修复：定义题型映射，支持带编号的题型标题
    final typeMap = [
      {'label': '单选题', 'type': 'single'},
      {'label': '多选题', 'type': 'multi'},
      {'label': '填空题', 'type': 'fill'},
      {'label': '简答题', 'type': 'short'},
    ];
    
    debugPrint('\n🔍 [题型识别] 开始识别题型标题...');
    debugPrint(' [题型识别] 文本总长度: ${text.length} 字符');
        
    // 1. 先找到所有题型标题的位置（支持带编号的题型标题）
    List<Map<String, dynamic>> typePositions = [];
    for (var t in typeMap) {
      final label = t['label'] as String;
      final type = t['type'] as String;
          
      // 🔥 核心修复：使用更精确的正则表达式匹配题型标题
      // 支持的格式：
      // - 一、单选题
      // - (一) 单选题
      // - 单选题
      // - 1. 单选题
      // - 一、单选题(5题)
      // - 一、单选题（2道）
      // - 单选题  （后面可以有内容，不强制行尾）
      final regex = RegExp(
        r'^\s*(?:[一-龥]+[、，,.]\s*|\(\s*[一-龥]+\s*\)\s*|\d+[.、]\s*)?' + 
        RegExp.escape(label) + 
        r'\s*(?:\([^)]*\))?\s*(?:（[^）]*）)?\s*$',
        multiLine: true,
      );
      final matches = regex.allMatches(text);
          
      int matchCount = 0;
      for (final match in matches) {
        // 🔥 核心修复：去除匹配结果中的前导/后随空白字符
        String matchedText = match.group(0)?.trim() ?? '';
        if (matchedText.isEmpty) continue;
        
        typePositions.add({
          'pos': match.start,
          'label': label,
          'type': type,
          'matched': matchedText, // 记录实际匹配到的文本（已trim）
        });
        matchCount++;
      }
          
      debugPrint('   - $label: 找到 $matchCount 处');
    }

    // 按位置排序并去重（同一位置只保留第一个题型标签）
    typePositions.sort((a, b) => (a['pos'] as int).compareTo(b['pos'] as int));
    
    // 去重：移除同一位置的重复题型标签
    List<Map<String, dynamic>> uniquePositions = [];
    for (int i = 0; i < typePositions.length; i++) {
      if (i == 0 || typePositions[i]['pos'] != typePositions[i - 1]['pos']) {
        uniquePositions.add(typePositions[i]);
      }
    }
    typePositions = uniquePositions;

    debugPrint('🔍 [题型识别] 去重后题型块数量: ${typePositions.length}');
    for (int i = 0; i < typePositions.length; i++) {
      final pos = typePositions[i]['pos'] as int;
      final label = typePositions[i]['label'] as String;
      final matched = typePositions[i]['matched'] as String;
      // 显示题型标题前后的内容，便于调试
      final previewStart = pos > 20 ? pos - 20 : 0;
      final previewEnd = pos + matched.length + 20 < text.length ? pos + matched.length + 20 : text.length;
      final preview = text.substring(previewStart, previewEnd).replaceAll('\n', '\\n');
      debugPrint('   - 题型 ${i + 1}: "$label" (匹配: "$matched") at position $pos');
      debugPrint('     上下文: ...$preview...');
    }
    
    if (typePositions.isEmpty) {
      debugPrint(' [题型识别] 未找到任何题型标题！');
      debugPrint(' [题型识别] 请检查文档是否包含以下题型标题：');
      debugPrint('❌   - 一、单选题 或 单选题');
      debugPrint('❌   - 二、多选题 或 多选题');
      debugPrint('❌   - 三、填空题 或 填空题');
      debugPrint('❌   - 四、简答题 或 简答题');
      debugPrint(' [题型识别] 每个题型标题必须单独占一行');
    }
    debugPrint('========================================\n');

    // 2. 切分题型块并解析
    for (int i = 0; i < typePositions.length; i++) {
      final current = typePositions[i];
      final int startPos = current['pos'] as int;
      final String label = current['label'] as String;
      final String matched = current['matched'] as String;
      final int start = startPos + matched.length;
      
      // 🔥 核心修复：验证 start 位置是否有效
      if (start >= text.length) {
        debugPrint('⚠️ [导入出题] 题型块 "$label" 起始位置 $start 超出文本长度 ${text.length}，跳过');
        continue;
      }
      
      // 计算结束位置
      final int end = (i < typePositions.length - 1) 
          ? typePositions[i + 1]['pos'] as int
          : text.length;
      
      // 🔥 核心修复：验证 end 位置是否有效
      if (end > text.length) {
        debugPrint('⚠️ [导入出题] 题型块 "$label" 结束位置 $end 超出文本长度 ${text.length}，调整为 ${text.length}');
      }
      
      //  核心修复：确保 start < end
      if (start >= end) {
        debugPrint('️ [导入出题] 题型块 "$label" 起始位置 $start >= 结束位置 $end，跳过');
        continue;
      }
      
      final String blockText = text.substring(start, end).trim();
      final String blockType = current['type'] as String;

      debugPrint('📝 [导入出题] 解析题型块 "$label" ($blockType)，长度: ${blockText.length}');
      if (blockText.isNotEmpty) {
        final preview = blockText.substring(0, blockText.length > 100 ? 100 : blockText.length).replaceAll('\n', '\\n');
        debugPrint('   内容预览: $preview...');
      }

      // 在这个块内，只解析当前题型的题目
      final blockQuestions = _parseQuestionsInBlock(blockText, blockType);
      debugPrint('✅ [导入出题] 题型块 "$label" 解析成功 ${blockQuestions.length} 道题目');
      allQuestions.addAll(blockQuestions);
    }

    debugPrint('🎉 [导入出题] 总共解析 ${allQuestions.length} 道题目');
    return allQuestions;
  }

  // 解析单个题型块内的题目（强制指定题型，绝不串题）
  List<Map<String, dynamic>> _parseQuestionsInBlock(String blockText, String fixedType) {
    List<Map<String, dynamic>> result = [];

    if (blockText.trim().isEmpty) {
      debugPrint('⚠️ [导入出题] 题型块内容为空，跳过解析');
      return result;
    }

    // 🔥 核心修复1：先按题目编号分割，再处理每个题目块
    // 使用更严格的正则：必须是行首的数字+点/顿号+空格或换行
    List<String> rawQuestionBlocks = [];
    
    // 分割题目（在题目编号前分割）
    List<String> splitParts = blockText.split(RegExp(r'(?=^\s*\d+[.、]\s)', multiLine: true));
    
    debugPrint('📝 [导入出题] 题型 "$fixedType" 初步分割出 ${splitParts.length} 个部分');
    
    // 过滤和合并题目块
    for (int i = 0; i < splitParts.length; i++) {
      String part = splitParts[i].trim();
      
      // 🔥 核心修复2：严格验证是否为有效题目
      // 必须满足：以数字编号开头 + 有实际内容（不只是空白）
      if (part.isEmpty) continue;
      
      // 检查是否以题目编号开头
      if (!RegExp(r'^\s*\d+[.、]').hasMatch(part)) {
        // 如果不是第一部分且不以编号开头，合并到上一个题目
        if (rawQuestionBlocks.isNotEmpty) {
          rawQuestionBlocks[rawQuestionBlocks.length - 1] += '\n$part';
        }
        continue;
      }
      
      // 🔥 核心修复3：验证题目是否有实质内容（排除纯编号行）
      // 移除编号后，剩余内容不能为空
      String contentWithoutNumber = part.replaceFirst(RegExp(r'^\s*\d+[.、]\s*'), '').trim();
      if (contentWithoutNumber.isEmpty) {
        debugPrint('⚠️ [导入出题] 跳过空题目（只有编号无内容）');
        continue;
      }
      
      // 🔥 核心修复4：进一步验证内容质量（至少要有10个字符或包含中文/字母）
      bool hasValidContent = contentWithoutNumber.length >= 10 || 
                             RegExp(r'[\u4e00-\u9fa5a-zA-Z]').hasMatch(contentWithoutNumber);
      if (!hasValidContent) {
        debugPrint('⚠️ [导入出题] 跳过无效题目（内容过短或无意义字符）: ${contentWithoutNumber.substring(0, contentWithoutNumber.length > 20 ? 20 : contentWithoutNumber.length)}');
        continue;
      }
      
      rawQuestionBlocks.add(part);
    }
    
    debugPrint('✅ [导入出题] 题型 "$fixedType" 过滤后有 ${rawQuestionBlocks.length} 道有效题目');

    int successCount = 0;
    int failCount = 0;
    
    for (String qBlock in rawQuestionBlocks) {
      qBlock = qBlock.trim();
      if (qBlock.isEmpty) continue;

      try {
        final question = _parseSingleQuestion(qBlock, fixedType);
        if (question != null) {
          result.add(question);
          successCount++;
        } else {
          failCount++;
          debugPrint('⚠️ [导入出题] 题目解析返回null，可能缺少答案标记');
        }
      } catch (e) {
        failCount++;
        debugPrint('❌ [导入出题] 单道题目解析失败: $e');
        debugPrint('   题目内容预览: ${qBlock.substring(0, qBlock.length > 50 ? 50 : qBlock.length)}...');
      }
    }

    debugPrint('✅ [导入出题] 题型 "$fixedType" 解析完成: 成功 $successCount 道，失败 $failCount 道');
    return result;
  }

  // 解析单道题（传入强制题型）
  Map<String, dynamic>? _parseSingleQuestion(String block, String fixedType) {
    try {
      // 不再按行分割，而是直接查找关键标记位置
      String content = block.trim();
      
      if (content.isEmpty) {
        debugPrint('⚠️ [导入出题] 题目内容为空，跳过');
        return null;
      }
      
      // 查找多种可能的答案标记
      int answerIndex = -1;
      String answerMarker = '';
      
      // 检查多种可能的答案标记格式
      final answerMarkers = ['答案：', '答案:', '参考答案：', '参考答案:'];
      for (String marker in answerMarkers) {
        int pos = content.indexOf(marker);
        if (pos != -1) {
          answerIndex = pos;
          answerMarker = marker;
          break;
        }
      }
      
      // 如果是选择题但没找到答案，直接返回null（因为选择题必须有答案）
      if ((fixedType == 'single' || fixedType == 'multi') && answerIndex == -1) {
        debugPrint('⚠️ [导入出题] $fixedType 类型题目缺少答案标记，跳过');
        return null;
      }
      
      // 如果是填空题或简答题，即使没有答案也可以继续解析
      String title;
      String rawAnswer = '';
      String analysis = '';
      
      if (answerIndex != -1) {
        // 🔥 核心修复：验证索引范围后再进行 substring 操作
        if (answerIndex < 0 || answerIndex > content.length) {
          debugPrint('❌ [导入出题] 答案标记位置越界: answerIndex=$answerIndex, contentLength=${content.length}');
          return null;
        }
        
        // 提取题干（标题）
        title = content.substring(0, answerIndex).trim();
        
        // 查找"解析："的位置（如果有）
        int analysisIndex = -1;
        String analysisMarker = '';
        final analysisMarkers = ['解析：', '解析:', '答案解析：', '答案解析:'];
        for (String marker in analysisMarkers) {
          int pos = content.indexOf(marker, answerIndex);
          if (pos != -1) {
            analysisIndex = pos;
            analysisMarker = marker;
            break;
          }
        }
        
        // 提取答案
        if (analysisIndex != -1) {
          // 🔥 核心修复：验证索引范围
          int answerStart = answerIndex + answerMarker.length;
          int answerEnd = analysisIndex;
          
          if (answerStart >= 0 && answerStart <= content.length && 
              answerEnd >= answerStart && answerEnd <= content.length) {
            // 有解析部分
            rawAnswer = content.substring(answerStart, answerEnd).trim();
            
            int analysisStart = analysisIndex + analysisMarker.length;
            if (analysisStart >= 0 && analysisStart <= content.length) {
              analysis = content.substring(analysisStart).trim();
            } else {
              debugPrint('⚠️ [导入出题] 解析起始位置越界');
              analysis = '';
            }
          } else {
            debugPrint('⚠️ [导入出题] 答案区间越界: start=$answerStart, end=$answerEnd');
            rawAnswer = '';
            analysis = '';
          }
        } else {
          // 没有解析部分
          int answerStart = answerIndex + answerMarker.length;
          if (answerStart >= 0 && answerStart <= content.length) {
            rawAnswer = content.substring(answerStart).trim();
          } else {
            debugPrint('⚠️ [导入出题] 答案起始位置越界: answerStart=$answerStart');
            rawAnswer = '';
          }
        }
      } else {
        // 没有找到答案标记，整个内容都是题干
        title = content;
      }
      
      // 去掉开头的题号
      title = title.replaceFirst(RegExp(r'^\d+\.\s*'), '');
      
      // 🔥 调试：输出提取选项前的题干
      debugPrint('\n [选项提取] 提取选项前的题干:');
      debugPrint(title);
      debugPrint(' [选项提取] 题干长度: ${title.length}\n');
      
      // 处理选项（如果适用）
      List<String> options = [];
      if (fixedType == 'single' || fixedType == 'multi') {
        // 🔥 全新方案：直接在原始文本上匹配选项标记，不使用占位符
        // 核心思路：用正则找到 A. B. C. D. 标记位置，按位置切分题干和选项
        //
        // 🔥 兼容性增强（v2）：
        // 1. 同时支持"行首标记"和"行内连续标记"两种排版
        //    - 行首：A. xxx\nB. yyy\nC. zzz
        //    - 行内：A. xxx B. yyy C. zzz（同一行内空格分隔）
        // 2. 兼容全部分隔符：. 、 ． ） ) （ ( ： : - — 空格 等
        // 3. 序列验证：提取的字母必须构成 A→B→C→D 连续序列，防止误匹配题干中的"B类""C项"等
        // 4. 至少需要2个连续标记才认定为选项区

        // 第1步：用宽松正则找出所有候选选项标记位置
        // 候选标记 = 大写字母A-D + 分隔符（支持多种）
        // (?<=^|\n|\s) 确保标记前是行首或空白，避免匹配 "xB." 中的 "B."
        final candidateRegex = RegExp(
          r'(?<=^|\n|\s)([A-D])\s*(?:[.、．）)（(：:\-—]|\s+(?=[A-D]\s*(?:[.、．）)（(：:\-—]|$)))\s*',
          multiLine: true,
        );
        final candidates = candidateRegex.allMatches(title).toList();

        debugPrint('🔍 [选项提取] 候选标记数: ${candidates.length}');
        for (final m in candidates) {
          debugPrint('   候选 ${m.group(1)} at ${m.start}');
        }

        // 第2步：序列验证 —— 从候选中筛选出构成 A,B,C,D 连续序列的最长子串
        // 例如：候选 [B, C, D] 也合法（题干里碰巧有B），只要它们彼此连续
        // 但必须从某个字母开始，后续按字母表顺序递增
        List<RegExpMatch> markerMatches = [];
        if (candidates.isNotEmpty) {
          // 尝试从每个候选作为起点，找到最长的连续序列
          List<RegExpMatch> bestSeq = [];
          for (int start = 0; start < candidates.length; start++) {
            final seq = <RegExpMatch>[candidates[start]];
            int expectedLetter = candidates[start].group(1)!.codeUnitAt(0); // 'A'=65
            for (int j = start + 1; j < candidates.length; j++) {
              final nextLetter = candidates[j].group(1)!.codeUnitAt(0);
              if (nextLetter == expectedLetter + 1) {
                seq.add(candidates[j]);
                expectedLetter = nextLetter;
              } else if (nextLetter > expectedLetter + 1) {
                break; // 字母跳了，序列中断
              }
              // nextLetter <= expectedLetter 的情况：重复字母，跳过继续找
            }
            if (seq.length > bestSeq.length) {
              bestSeq = seq;
            }
          }
          // 至少2个连续标记才认定为选项
          if (bestSeq.length >= 2) {
            markerMatches = bestSeq;
          }
        }

        debugPrint('🔍 [选项提取] 验证后选项标记数: ${markerMatches.length}');
        for (final m in markerMatches) {
          debugPrint('   标记 ${m.group(1)} at ${m.start}');
        }

        if (markerMatches.length >= 2) {
          // 找到至少2个连续选项标记，提取选项内容
          // 第一个选项标记之前的内容是题干
          final firstMarkerStart = markerMatches.first.start;
          // 题干 = 第一个选项标记之前的所有内容（去掉行首的空白）
          String questionStem = title.substring(0, firstMarkerStart).trim();

          // 提取每个选项的内容：从当前标记的字母之后到下一个标记之前
          for (int i = 0; i < markerMatches.length; i++) {
            final match = markerMatches[i];
            final letter = match.group(1)!;

            // 选项内容从标记匹配结束位置开始
            int contentStart = match.end;
            // 到下一个标记开始位置结束（或到字符串末尾）
            int contentEnd = (i + 1 < markerMatches.length)
                ? markerMatches[i + 1].start
                : title.length;

            String content = title.substring(contentStart, contentEnd).trim();

            // 清理选项内容：去掉首尾换行和多余空格，但保留内部结构
            content = content
                .replaceAll(RegExp(r'^[\s\n\r]+'), '')
                .replaceAll(RegExp(r'[\s\n\r]+$'), '')
                .replaceAll(RegExp(r' {2,}'), ' ')
                .trim();

            if (content.isNotEmpty) {
              options.add(content);
              debugPrint('   ✅ 选项 $letter: ${content.length > 60 ? '${content.substring(0, 60)}...' : content}');
            } else {
              // 选项内容为空，可能是纯公式选项被误判
              debugPrint('   ⚠️ 选项 $letter 内容为空');
              options.add('');
            }
          }

          // 更新题干：只保留选项标记之前的内容
          title = questionStem;
          debugPrint('   📝 提取后题干: ${title.length > 100 ? '${title.substring(0, 100)}...' : title}');
          debugPrint('   📊 共提取 ${options.length} 个选项');
        } else {
          debugPrint('   ⚠️ 选项标记不足2个（${markerMatches.length}个），跳过选项提取');
        }
      }
      
      // 格式化答案
      String finalAnswer = rawAnswer;
      if (fixedType == 'single' || fixedType == 'multi') {
        final letters = RegExp(r'[A-Z]').allMatches(rawAnswer).map((m) => m.group(0)!).toList();
        finalAnswer = letters.join('');
        if (fixedType == 'single' && finalAnswer.length > 1) {
          finalAnswer = finalAnswer[0];
        }
      }

      // 🔥 安全检查：确保返回的数据不含占位符残留
      // 如果有占位符残留，说明选项提取中的公式保护/还原逻辑有bug
      title = _cleanPlaceholderString(title);
      analysis = _cleanPlaceholderString(analysis);
      for (int i = 0; i < options.length; i++) {
        options[i] = _cleanPlaceholderString(options[i]);
      }

      return {
        'type': fixedType, // 强制使用传入的题型，绝不自动推断
        'title': title,
        'options': options,
        'answer': finalAnswer,
        'analysis': analysis,
      };
    } catch (e) {
      debugPrint('❌ [导入出题] _parseSingleQuestion 异常: $e');
      debugPrint('   题目内容预览: ${block.substring(0, block.length > 100 ? 100 : block.length)}...');
      return null;
    }
  }
  // ====================== 【解析结束】======================

  bool _isPublishing = false;

  // 🔥 新增：数据清洗函数，确保 JSON 序列化安全
  String _sanitizeJsonString(String? text) {
    if (text == null || text.isEmpty) return '';
    
    String result = text;
    
    // 1. 替换控制字符（保留换行符和制表符）
    result = result.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    
    // 2. 确保反斜杠正确转义（LaTeX 公式中的 \frac, \sqrt 等）
    // jsonEncode 会自动处理，但我们需要确保原始数据没有损坏
    
    // 3. 清理可能导致 JSON 解析失败的字符
    result = result.replaceAll('\r', ''); // 移除回车符
    
    return result;
  }

  Future<void> publishPaper() async {
    if (paperResult == null) return;
    if (startTimeText.isEmpty || endTimeText.isEmpty) return;

    if (_isPublishing) {
      debugPrint('⚠️ 正在发布中，请勿重复点击');
      return;
    }

    setState(() {
      _isPublishing = true;
    });

    int totalSec = 0;
    List? perTypeTimeData;

    if (timeType == 'total') {
      totalSec = totalTimeUnitIndex == 0 ? totalTime * 60 : totalTime;
      perTypeTimeData = null;
      debugPrint("⏱️ [总计时] 原始值: $totalTime ${timeUnits[totalTimeUnitIndex]}, 转换后: $totalSec秒");
    } else {
      perTypeTimeData = questionTypes.map((item) {
        int t = item['time'] ?? 0;
        if (item['timeUnitIndex'] == 0) {
          t *= 60;
        }
        debugPrint("⏱️ [每题计时] 题型 ${item['label']}: ${item['time']} ${timeUnits[item['timeUnitIndex']]} -> $t秒");
        return {
          'type': item['type'],
          'score': item['score'] ?? 0,
          'time': t,
        };
      }).toList();
      totalSec = 0;
    }

    List questions = (paperResult!['questions'] as List).map((q) {
      String key = q['type'] ?? 'single';
      var cfg = questionTypes.firstWhere(
        (e) => e['type'] == key,
        orElse: () => {'score': 0, 'time': 0}
      );

      return {
        'type': key,
        // �� 核心修复：发布前统一调用 wrapAndFormatLatex，确保所有公式正确包裹
        'title': Exampublishai.wrapAndFormatLatex(q['title'] ?? ''),
        'options': (q['options'] as List?)?.map((opt) => Exampublishai.wrapAndFormatLatex(opt.toString())).toList() ?? [],
        'answer': Exampublishai.wrapAndFormatLatex(q['answer'] ?? ''),
        'analysis': Exampublishai.wrapAndFormatLatex(q['analysis'] ?? ''),
        'score': cfg['score'] ?? 0,
      };
    }).toList();

    var data = {
      'action': 'createExam',
      'examName': _sanitizeJsonString(paperResult!['paperName'] ?? paperName),
      'subject': _sanitizeJsonString(paperResult!['subject'] ?? subjectList[subjectIndex]),
      'examTime': '$startTimeText - $endTimeText',
      'status': examStatusList[examStatusIndex],
      'timingType': timeType == 'total' ? 'totalTime' : 'perQuestionTime',
      'totalTime': timeType == 'total' ? totalSec : null,
      'perTypeTime': perTypeTimeData,
      'questions': questions,
    };

    debugPrint('📤 发布试卷数据构建完成');
    debugPrint('   - 试卷名称: ${data['examName']}');
    debugPrint('   - 科目: ${data['subject']}');
    debugPrint('   - 题目数量: ${(data['questions'] as List).length}');
    debugPrint('   - 计时类型: ${data['timingType']}');
    
    // 🔥 调试：检查第一题的数据格式
    if ((data['questions'] as List).isNotEmpty) {
      final firstQuestion = (data['questions'] as List)[0];
      debugPrint('   - 第一题类型: ${firstQuestion['type']}');
      debugPrint('   - 第一题标题长度: ${firstQuestion['title'].length}');
      debugPrint('   - 第一题答案长度: ${firstQuestion['answer'].length}');
      debugPrint('   - 第一题解析长度: ${firstQuestion['analysis'].length}');
    }

    // 🔥 安全检查：清理可能残留的占位符（防止占位符被存入数据库）
    _cleanupPlaceholders(data);

    String jsonData;
    try {
      jsonData = jsonEncode(data);
      debugPrint('✅ JSON 序列化成功，数据大小: ${jsonData.length} 字节');
    } catch (e) {
      debugPrint('❌ JSON 序列化失败: $e');
      throw Exception('数据格式化失败: $e');
    }

    debugPrint('📤 开始发送请求到: $baseUrl/api/exam');

    try {
      final result = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/exam'),
        headers: {"Content-Type": "application/json"},
        body: jsonData,  // 修复：jsonData 已是序列化后的字符串，不要再 jsonEncode 一次
      )).body);

      debugPrint('✅ 发布响应: $result');

      if (result['success'] == true) {
        if (mounted) {
          ToastUtil.show(context, '试卷发布成功');
        }
      } else {
        if (mounted) {
          ToastUtil.show(context, '发布失败: ${result['msg'] ?? '未知错误'}');
        }
      }
    } catch (e) {
      debugPrint('❌ 发布异常: $e');
      if (mounted) {
        ToastUtil.show(context, '发布异常: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
        });
      }
    }
  }

  /// 安全检查：递归清理数据中可能残留的占位符
  /// 防止 OPT_FORMULA 或 BLOCK_FORMULA 等占位符被存入数据库
  void _cleanupPlaceholders(dynamic data) {
    if (data is Map) {
      final keys = data.keys.toList();
      for (final key in keys) {
        final value = data[key];
        if (value is String) {
          data[key] = _cleanPlaceholderString(value);
        } else {
          _cleanupPlaceholders(value);
        }
      }
    } else if (data is List) {
      for (int i = 0; i < data.length; i++) {
        final value = data[i];
        if (value is String) {
          data[i] = _cleanPlaceholderString(value);
        } else {
          _cleanupPlaceholders(value);
        }
      }
    }
  }

  /// 清理字符串中的占位符
  String _cleanPlaceholderString(String s) {
    var r = s;
    // {{OPT_FORMULA_BLOCK_0}} 等
    r = r.replaceAll(
      RegExp(r'\{\{OPT_FORMULA_(?:BLOCK|INLINE|WRAPPED)_\d+\}\}'),
      '',
    );
    // <<BLOCK_FORMULA_0>>, <<BLOC $K_FORMULA_0$ >> 等变体
    r = r.replaceAll(
      RegExp(r'<<\s*BLOC[K]?\s*[\$_]*\s*FORMULA[_\s]*\d+\s*[\$_]*\s*>>', caseSensitive: false),
      '',
    );
    return r;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1890ff), Color(0xFF096dd9)],
              ),
            ),
          ),
          Positioned(
            top: 50, left: 15, right: 15,
            child: Row(
              children: [
                GestureDetector(
                  onTap: goBack,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.white38, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 15),
                        SizedBox(width: 2),
                        Text('返回', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: modeBtn('AI出题', 'ai')),
                const SizedBox(width: 10),
                Expanded(child: modeBtn('导入出题', 'import')),
              ],
            ),
          ),

          Positioned.fill(
            top: 120,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  if (mode == 'ai') aiPanel(),
                  if (mode == 'import') importPanel(),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget modeBtn(String text, String m) {
    bool active = mode == m;
    bool light = lightBtn == m;
    return GestureDetector(
      onTap: () => switchMode(m),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: light
              ? Colors.white.withValues(alpha: 0.35)
              : active
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white30),
        ),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget aiPanel() {
    return glassPanel(child: formBody(false));
  }

  Widget importPanel() {
    return glassPanel(child: formBody(true));
  }

  Widget glassPanel({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget formBody(bool isImport) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: Text('出题发布', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
        const SizedBox(height: 20),
        formLine('科目', picker(subjectList, subjectIndex, (v) => setState(() => subjectIndex = v))),
        formLine('试卷名称', input('请输入试卷名', paperName, (v) => setState(() => paperName = v))),
        if (!isImport) formLine('出题范围', input('范围', questionScope, (v) => setState(() => questionScope = v))),
        formLine('考试类型', picker(examStatusList, examStatusIndex, (v) => setState(() => examStatusIndex = v))),
        formLine('考试时间', timeRow()),
        formLine('计时方式', timeTypeRow()),
        const SizedBox(height: 15),
        const Text('题型设置', style: TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 10),
        questionTypeTable(),
        if (timeType == 'total') formLine('总时间', totalTimeInput()),
        if (isImport) importEditor(),
        const SizedBox(height: 20),
        submitBtn(isImport ? '解析导入' : '生成试卷', () => isImport ? parseImport() : submitAI()),
        
        // 🔥 核心修复：AI生成过程中显示加载动画
        if (isAIGenerating) paperPreview(),
        
        // 🔥 核心修复：生成完成后显示结果和发布按钮
        if (!isAIGenerating && paperResult != null) ...[
          paperPreview(),
          const SizedBox(height: 20),
          submitBtn(_isPublishing ? '发布中...' : '发布试卷', publishPaper),
        ],
      ],
    );
  }

  Widget formLine(String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14))),
          const SizedBox(width: 10),
          // 🔥 核心修复：使用 Flexible 而非 Expanded，允许子组件根据自身大小调整
          Flexible(child: child),
        ],
      ),
    );
  }

  Widget input(String hint, String val, Function(String) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: val == paperName ? paperNameController : questionScopeController,
        autofocus: false,
        decoration: InputDecoration(border: InputBorder.none, hintText: hint),
        style: const TextStyle(fontSize: 14),
        onChanged: onChanged,
      ),
    );
  }

  Widget picker(List<String> list, int idx, Function(int) onChanged) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(context: context, builder: (c) {
          return SizedBox(height: 250, child: ListView.builder(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.1),
            itemCount: list.length, itemBuilder: (_, i) {
            return ListTile(title: Text(list[i]), onTap: () {onChanged(i); Navigator.pop(c);});
          }));
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(14)),
        child: Text(list[idx], style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget timeRow() {
    return Column(
      children: [
        _buildTimeSelector(label: '开始时间', isStartTime: true),
        const SizedBox(height: 12),
        _buildTimeSelector(label: '结束时间', isStartTime: false),
      ],
    );
  }

  Widget _buildTimeSelector({
    required String label,
    required bool isStartTime,
  }) {
    final timeText = isStartTime ? startTimeText : endTimeText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _showTimePickerDialog(isStartTime),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  timeText.isEmpty ? '点击选择时间' : timeText,
                  style: TextStyle(
                    color: timeText.isEmpty ? Colors.grey : Colors.black87,
                    fontSize: 14,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showTimePickerDialog(bool isStartTime) async {
    final yearController = TextEditingController(
      text: isStartTime ? startYearController.text : endYearController.text
    );
    final monthController = TextEditingController(
      text: isStartTime ? startMonthController.text : endMonthController.text
    );
    final dayController = TextEditingController(
      text: isStartTime ? startDayController.text : endDayController.text
    );
    final hourController = TextEditingController(
      text: isStartTime ? startHourController.text : endHourController.text
    );
    final minuteController = TextEditingController(
      text: isStartTime ? startMinuteController.text : endMinuteController.text
    );
    final secondController = TextEditingController(
      text: isStartTime ? startSecondController.text : endSecondController.text
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isStartTime ? '选择开始时间' : '选择结束时间'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请分别输入年、月、日、时、分、秒', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(flex: 4, child: _dialogTimeField('年', yearController, 4)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _dialogTimeField('月', monthController, 2)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _dialogTimeField('日', dayController, 2)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(flex: 2, child: _dialogTimeField('时', hourController, 2)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _dialogTimeField('分', minuteController, 2)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _dialogTimeField('秒', secondController, 2)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_validateAndUpdateTime(
                isStartTime,
                yearController,
                monthController,
                dayController,
                hourController,
                minuteController,
                secondController,
              )) {
                Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    yearController.dispose();
    monthController.dispose();
    dayController.dispose();
    hourController.dispose();
    minuteController.dispose();
    secondController.dispose();
  }

  Widget _dialogTimeField(String unit, TextEditingController controller, int maxLength) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        counterText: '',
        hintText: unit,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      style: const TextStyle(fontSize: 14),
      textAlign: TextAlign.center,
    );
  }

  bool _validateAndUpdateTime(
    bool isStartTime,
    TextEditingController yearCtrl,
    TextEditingController monthCtrl,
    TextEditingController dayCtrl,
    TextEditingController hourCtrl,
    TextEditingController minCtrl,
    TextEditingController secCtrl,
  ) {
    try {
      final year = int.parse(yearCtrl.text);
      final month = int.parse(monthCtrl.text);
      final day = int.parse(dayCtrl.text);
      final hour = int.parse(hourCtrl.text);
      final minute = int.parse(minCtrl.text);
      final second = int.parse(secCtrl.text);

      // 🔥 核心修复：先做范围校验，避免越界值直接抛异常导致误报“格式不正确”
      if (year < 2000 || year > 2100) {
        showToast('年份需在 2000-2100 之间');
        return false;
      }
      if (month < 1 || month > 12) {
        showToast('月份需在 1-12 之间');
        return false;
      }
      if (day < 1 || day > 31) {
        showToast('日期需在 1-31 之间');
        return false;
      }
      if (hour < 0 || hour > 23) {
        showToast('小时需在 0-23 之间');
        return false;
      }
      if (minute < 0 || minute > 59) {
        showToast('分钟需在 0-59 之间');
        return false;
      }
      if (second < 0 || second > 59) {
        showToast('秒需在 0-59 之间');
        return false;
      }

      DateTime(year, month, day, hour, minute, second);

      if (isStartTime) {
        startYearController.text = year.toString();
        startMonthController.text = pad2(month);
        startDayController.text = pad2(day);
        startHourController.text = pad2(hour);
        startMinuteController.text = pad2(minute);
        startSecondController.text = pad2(second);
        _updateStartTimeString();
      } else {
        endYearController.text = year.toString();
        endMonthController.text = pad2(month);
        endDayController.text = pad2(day);
        endHourController.text = pad2(hour);
        endMinuteController.text = pad2(minute);
        endSecondController.text = pad2(second);
        _updateEndTimeString();
      }

      return true;
    } catch (e) {
      showToast('时间格式不正确，请检查输入');
      return false;
    }
  }

  Widget timeTypeRow() {
    return Row(
      children: [
        Expanded(child: typeBtn('每题计时', timeType == 'per', () => setState(() => timeType = 'per'))),
        const SizedBox(width: 10),
        Expanded(child: typeBtn('总计', timeType == 'total', () => setState(() => timeType = 'total'))),
      ],
    );
  }

  Widget typeBtn(String t, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: active ? const Color(0xFF1890ff) : Colors.black87, fontSize: 14)),
      ),
    );
  }

  Widget questionTypeTable() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: Text('题型', style: TextStyle(color: Colors.white, fontSize: 14))),
            Expanded(flex: 2, child: Text('题数', style: TextStyle(color: Colors.white, fontSize: 14))),
            Expanded(flex: 2, child: Text('每题分', style: TextStyle(color: Colors.white, fontSize: 14))),
            if (timeType == 'per')
              Expanded(flex: 3, child: Text('每题时间', style: TextStyle(color: Colors.white, fontSize: 14))),
          ],
        ),
        const SizedBox(height: 8),
        ...questionTypes.asMap().entries.map((e) {
          int idx = e.key;
          var item = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(item['label'], style: const TextStyle(color: Colors.white, fontSize: 14))),
                Expanded(flex: 2, child: numInput('count_${item['type']}', item['count'], (v) => setState(() => item['count'] = int.tryParse(v) ?? 0))),
                Expanded(flex: 2, child: numInput('score_${item['type']}', item['score'], (v) => setState(() => item['score'] = int.tryParse(v) ?? 0))),

                if (timeType == 'per')
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      onTap: () => toggleTimeUnit(idx),
                      behavior: HitTestBehavior.opaque, // 🔥 核心修复：确保整个区域可点击
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center, // 🔥 核心修复：居中对齐
                          mainAxisSize: MainAxisSize.min, // 🔥 核心修复：根据内容调整大小
                          children: [
                            SizedBox(
                              width: 40, // 🔥 核心修复：固定输入框宽度
                              child: numInput('time_${item['type']}', item['time'], (v) => setState(() => item['time'] = int.tryParse(v) ?? 0)),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              timeUnits[item['timeUnitIndex']],
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget numInput(String key, int value, Function(String) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
      child: TextField(
        onChanged: onChanged,
        controller: _numCtrl(key, value),
        autofocus: false, // 🔥 修复：禁止自动聚焦
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(border: InputBorder.none),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget totalTimeInput() {
    return GestureDetector(
      onTap: toggleTotalTimeUnit,
      behavior: HitTestBehavior.opaque, // 🔥 核心修复：确保整个区域可点击
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // 🔥 核心修复：居中对齐
          mainAxisSize: MainAxisSize.min, // 🔥 核心修复：根据内容调整大小
          children: [
            SizedBox(
              width: 60, // 🔥 核心修复：固定输入框宽度
              child: numInput('total_time', totalTime, (v) => setState(() => totalTime = int.tryParse(v) ?? 0)),
            ),
            const SizedBox(width: 8),
            Text(
              timeUnits[totalTimeUnitIndex],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget importEditor() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85), 
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              const Icon(
                Icons.edit_note,
                color: Colors.blueAccent,
                size: 24,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '粘贴题目内容',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // 说明文字
          Text(
            '请粘贴完整的试卷内容，包含题型标题（如：单选题、多选题、填空题、简答题）',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          
          // 文本输入框
          Container(
            constraints: const BoxConstraints(minHeight: 200, maxHeight: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: TextField(
              maxLines: null,
              expands: false,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '在此粘贴题目内容...\n\n示例格式：\n一、单选题\n1. 题目内容...\nA. 选项A\nB. 选项B\nC. 选项C\nD. 选项D\n答案：A\n\n二、多选题\n...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                contentPadding: EdgeInsets.all(12),
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 14, height: 1.5),
              onChanged: (value) {
                importContent = value;
              },
              controller: importContentController,
            ),
          ),
          
          // 字符统计
          if (importContent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '已输入 ${importContent.length} 个字符',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget submitBtn(String text, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    );
  }

  Widget paperPreview() {
    // 🔥 修复：AI 生成中时显示实时内容
    if (isAIGenerating) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24)
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 🔥 核心修复：使用 AnimatedBuilder 确 CircularProgressIndicator 持续旋转
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'AI 正在出题中...',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                // 🔥 添加题目数量指示器
                if (aiParsedQuestions.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    margin: const EdgeInsets.only(left: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.withValues(alpha: 0.6), Colors.blue.withValues(alpha: 0.4)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.8), width: 1),
                    ),
                    child: Text(
                      '${aiParsedQuestions.length}题',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            
            // 🔥 核心修复：AI 生成中显示加载动画，不显示实时预览
            if (isAIGenerating)
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue.withValues(alpha: 0.2),
                      Colors.purple.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    // 🔥 加载动画
                    const SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 🔥 动态提示文字
                    const Text(
                      '🤖 AI 正在思考并生成题目...',
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 🔥 字符计数
                    Text(
                      '已接收 ${aiRawContent.length} 字符',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 15),
                    // 🔥 进度条（基于字符数估算）
                    if (aiRawContent.isNotEmpty)
                      LinearProgressIndicator(
                        value: (aiRawContent.length / 5000).clamp(0.0, 1.0), // 假设最多5000字符
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    const SizedBox(height: 12),
                    // 🔥 提示信息
                    const Text(
                      '请耐心等待，题目将在生成完成后显示',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              )
          ],
        ),
      );
    }

    // 原有的结果展示逻辑
    if (paperResult != null) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24)
        ),
        child: _buildPaperPreview(Map<String, dynamic>.from(paperResult!)),
      );
    }

    // 默认提示
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24)
      ),
      child: const Text(
        '预览区域将在试卷生成完成后显示',
        style: TextStyle(color: Colors.white70, fontSize: 14),
      ),
    );
  }

  // 构建选择题选项
  List<Widget> _buildOptions(List<dynamic> options, String? type) {
    final optionWidgets = <Widget>[];
    final isMulti = type == 'multi';
    
    for (int i = 0; i < options.length; i++) {
      String letter = String.fromCharCode(65 + i); // A, B, C, D...
      
      // 🔥 核心修复：选项中的公式应该作为行内公式显示（不换行）
      // 将 $$...$$ 转换为 $...$，确保公式和选项字母在同一行
      String optionContent = options[i].toString();
      optionContent = optionContent.replaceAllMapped(
        RegExp(r'\$\$([\s\S]*?)\$\$', multiLine: true, dotAll: true),
        (match) => '\$${match.group(1)}\$',
      );
      
      optionWidgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '[$letter] ',
                style: TextStyle(
                  color: isMulti ? Colors.purpleAccent : Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: FormulaRenderer.renderMixedText(
                        optionContent,  // 使用转换后的内容
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return optionWidgets;
  }
  
  // 构建填空题答案（按分号分隔）
  List<Widget> _buildFillBlankAnswers(String answer) {
    // 直接返回整个答案字符串，保持分号分隔的格式
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth,
            ),
            child: FormulaRenderer.renderMixedText(
              answer,
              style: const TextStyle(color: Colors.greenAccent, fontSize: 13, height: 1.5),
            ),
          );
        },
      ),
    ];
  }
  
  // 构建完整的试卷预览
  Widget _buildPaperPreview(Map<String, dynamic> paperResult) {
    final questions = paperResult['questions'] as List?;
    if (questions == null || questions.isEmpty) {
      return const Text(
        '暂无题目',
        style: TextStyle(color: Colors.white70, fontSize: 14),
      );
    }
    
    // 按题型分组
    final Map<String, List<Map<String, dynamic>>> groupedQuestions = {};
    for (var q in questions.cast<Map<String, dynamic>>()) {
      final type = q['type']?.toString() ?? 'single';
      if (!groupedQuestions.containsKey(type)) {
        groupedQuestions[type] = [];
      }
      groupedQuestions[type]!.add(q);
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          paperResult['paperName'] ?? '未知试卷',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          '科目：${paperResult['subject'] ?? '未知'}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 20),
        ...groupedQuestions.entries.map((entry) {
          final type = entry.key;
          final qs = entry.value;
          final typeLabel = {'single': '单选题', 'multi': '多选题', 'fill': '填空题', 'short': '简答题'}[type] ?? '未知题型';
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '$typeLabel (${qs.length}题)',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ...qs.asMap().entries.map((qEntry) {
                final index = qEntry.key + 1;
                final q = qEntry.value;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // 🔥 核心修复：题干中的公式应该作为行内公式显示（不换行）
                          // 将 $$...$$ 转换为 $...$，确保公式和题干文字在同一行
                          String titleContent = q['title'] ?? '';
                          titleContent = titleContent.replaceAllMapped(
                            RegExp(r'\$\$([\s\S]*?)\$\$', multiLine: true, dotAll: true),
                            (match) => '\$${match.group(1)}\$',
                          );
                          
                          return ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                            ),
                            child: FormulaRenderer.renderMixedText(
                              '$index. $titleContent',
                              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                            ),
                          );
                        },
                      ),
                      if (q['options'] != null && q['options'] is List && (q['options'] as List).isNotEmpty)
                        ..._buildOptions(q['options'], q['type']),
                      if (q['answer'] != null && q['answer'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 20, top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('参考答案：', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              if (q['type'] == 'fill')
                                ..._buildFillBlankAnswers(q['answer'].toString())
                              else
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    // 🔥 核心修复：答案中的公式应该作为行内公式显示（不换行）
                                    String answerContent = q['answer'].toString();
                                    answerContent = answerContent.replaceAllMapped(
                                      RegExp(r'\$\$([\s\S]*?)\$\$', multiLine: true, dotAll: true),
                                      (match) => '\$${match.group(1)}\$',
                                    );
                                    
                                    return ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: constraints.maxWidth,
                                      ),
                                      child: FormulaRenderer.renderMixedText(
                                        answerContent,
                                        style: const TextStyle(color: Colors.greenAccent, fontSize: 13, height: 1.5),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      if (q['analysis'] != null && q['analysis'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 20, top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('解析：', style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  //  核心修复：解析中的公式应该作为行内公式显示（不换行）
                                  String analysisContent = q['analysis'].toString();
                                  analysisContent = analysisContent.replaceAllMapped(
                                    RegExp(r'\$\$([\s\S]*?)\$\$', multiLine: true, dotAll: true),
                                    (match) => '\$${match.group(1)}\$',
                                  );
                                  
                                  return ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: constraints.maxWidth,
                                    ),
                                    child: FormulaRenderer.renderMixedText(
                                      analysisContent,
                                      style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }
}
