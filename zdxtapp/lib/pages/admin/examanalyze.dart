import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zdxtapp/utils/formula_renderer.dart'; // 🔥 新公式渲染器
import 'package:zdxtapp/config.dart';

import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/ui_helpers.dart'; // 🔥 全局UI辅助工具
import 'package:zdxtapp/widgets/shimmer_loading.dart';

class Examanalyze extends StatefulWidget {
  const Examanalyze({super.key});

  @override
  State<Examanalyze> createState() => _ExamanalyzeState();
}

class _ExamanalyzeState extends State<Examanalyze> {
  final String baseUrl = Config.baseUrl;
  bool loading = true;
  List userList = [];

  Map<String, dynamic> currentRejudgeInfo = {};

  // 🔥 核心修复：试卷详情抽屉是无状态 builder，重判后主页面 setState 不会触发已打开抽屉重建。
  // 用 ValueNotifier 通知 open detail drawer 重新拉取数据渲染。
  static final ValueNotifier<String> _detailDrawerRefresh = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    Future.microtask(() => getStatisticsData());
  }

  // ====================== 接口获取统计数据 ======================
  Future<void> getStatisticsData() async {
    setState(() => loading = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "getExamStatistics"}),
      )).body);
      if (data["success"] == true) {
        List raw = data["data"]["userList"] ?? [];
        setState(() {
          userList = raw.map((u) {
            final userRemark = u['remark'] != null && (u['remark'] as String).isNotEmpty
                ? u['remark']
                : '无';

            return {
              ...u,
              "remark": userRemark, // 赋值备注
              "expand": false,
              "examList": (u["examList"] ?? []).map((e) {
                return {
                  ...e,
                  "expand": false,
                  "singleList": e["singleList"] ?? [],
                  "multiList": e["multiList"] ?? [],
                  "fillList": e["fillList"] ?? [],
                  "shortList": e["shortList"] ?? [],
                };
              }).toList()
            };
          }).toList();
        });
      }
    } catch (e) {
      // 错误处理
    } finally {
      setState(() => loading = false);
    }
  }

  // ====================== 展开用户 ======================
  void toggleUser(int index) {
    setState(() {
      userList[index]["expand"] = !userList[index]["expand"];
      if (userList[index]["expand"]) {
        for (var e in userList[index]["examList"]) {
          e["expand"] = false;
        }
      }
    });
  }

  // ====================== 答案转字母 ======================
  String getAnswerLetter(Map q, dynamic ans) {
    if (ans == null || q["options"] == null) return "未作答";
    int idx = q["options"].indexOf(ans);
    return idx >= 0 ? String.fromCharCode(65 + idx) : ans.toString();
  }

  String getMultiAnswerLetter(Map q, dynamic ans) {
    if (ans == null) return "未作答";
    List arr = [];
    if (ans is String) arr = ans.split(",");
    if (ans is List) arr = ans;
    return arr.map((a) => getAnswerLetter(q, a)).join("、");
  }

  // ====================== 时间格式化 ======================
  String fmtTime(String? t) {
    if (t == null || t.isEmpty) return "未知时间";
    try {
      final parsed = DateTime.parse(t);
      final cst = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
      return "${cst.year}-${cst.month.toString().padLeft(2, '0')}-${cst.day.toString().padLeft(2, '0')} "
          "${cst.hour.toString().padLeft(2, '0')}:${cst.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return t;
    }
  }

  // ====================== 打开重判弹窗 ======================
  void openRejudge(int uIdx, int eIdx, Map q, String type, int idx) {
    currentRejudgeInfo = {
      "uIdx": uIdx,
      "eIdx": eIdx,
      "qType": type,
      "qIdx": idx,
      "account": userList[uIdx]["account"],
      "examId": userList[uIdx]["examList"][eIdx]["examId"],
    };
    final scoreController = TextEditingController(
      text: (q["userScore"] ?? 0).toString(),
    );
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogCtx) => _RejudgeDialog(
        scoreController: scoreController,
        maxScore: q["score"] ?? 0,
        onConfirm: () => confirmRejudge(scoreController.text, q),
      ),
    );
  }

  // ====================== 确认重判 ======================
  Future<void> confirmRejudge(String newScoreStr, Map currentQ) async {
    if (currentRejudgeInfo.isEmpty) {
      ToastUtil.showError(context, "当前没有选中题目");
      return;
    }

    double score = double.tryParse(newScoreStr) ?? -1;
    double max = double.tryParse((currentQ["score"] ?? 0).toString()) ?? 0;
    developer.log("confirmRejudge start: type=${currentRejudgeInfo['qType']} qIndex=${currentRejudgeInfo['qIdx']} newScore=$newScoreStr max=$max");

    if (score < 0 || score > max) {
      developer.log("score out of range: score=$score max=$max");
      ToastUtil.showError(context, "分数不合法");
      return;
    }

    try {
      developer.log("sending request to $baseUrl/api/exam, body: ${jsonEncode({
        "action": "rejudgeQuestion",
        "account": currentRejudgeInfo["account"],
        "examId": currentRejudgeInfo["examId"],
        "qType": currentRejudgeInfo["qType"],
        "qIndex": currentRejudgeInfo["qIdx"].toString(),
        "newScore": newScoreStr,
      })}");
      final response = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "rejudgeQuestion",
          "account": currentRejudgeInfo["account"],
          "examId": currentRejudgeInfo["examId"],
          "qType": currentRejudgeInfo["qType"],
          "qIndex": currentRejudgeInfo["qIdx"].toString(),
          "newScore": newScoreStr,
        }),
      );
      developer.log("response status=${response.statusCode} body=${response.body}");
      final data = jsonDecode(response.body);
      developer.log("parsed data: $data");
      if (data["success"] == true) {
        int u = currentRejudgeInfo["uIdx"];
        int e = currentRejudgeInfo["eIdx"];
        int globalIdx = currentRejudgeInfo["qIdx"];

        // 🔥 核心修复：globalIdx 是全局拉通索引，不能直接用作 ${t}List 的局部索引。
        // 通过全局 questions 数组定位题目后更新 userScore。
        // 关键：重判后必须把新分数同步到各题型子列表（${t}List），
        // 因为 UI 读的是子列表的 userScore，不是 questions 的。
        final exam = userList[u]["examList"][e];
        final qType = currentRejudgeInfo["qType"] as String?;

        // 1. 定位全局 questions 数组中对应题目，更新 userScore
        final allQuestions = exam["questions"] as List? ?? [];
        if (globalIdx >= 0 && globalIdx < allQuestions.length) {
          allQuestions[globalIdx]["userScore"] = score;
        }

        // 2. 根据 qType 定位对应的子列表，找到该题并同步新分数
        List? targetList;
        if (qType == "single") {
          targetList = exam["singleList"] as List?;
        } else if (qType == "multi") {
          targetList = exam["multiList"] as List?;
        } else if (qType == "fill") {
          targetList = exam["fillList"] as List?;
        } else if (qType == "short") {
          targetList = exam["shortList"] as List?;
        }

        if (targetList != null) {
          // 通过题目特征（type + title/content）在子列表中定位该题
          final targetQuestion = allQuestions[globalIdx];
          final targetType = targetQuestion["type"]?.toString() ?? '';
          final targetTitle = targetQuestion["title"]?.toString() ?? targetQuestion["content"]?.toString() ?? '';
          
          for (int li = 0; li < targetList.length; li++) {
            final Map<String, dynamic> qm = targetList[li] is Map<String, dynamic> ? targetList[li] : Map<String, dynamic>.from(targetList[li]);
            final qTypeStr = qm["type"]?.toString() ?? '';
            final qTitle = qm["title"]?.toString() ?? qm["content"]?.toString() ?? '';
            // 题型匹配 + 题目内容匹配，确认是同一道题
            if (qTypeStr == targetType && qTitle == targetTitle) {
              qm["userScore"] = score;
              targetList[li] = qm;
              break;
            }
          }
        }

        setState(() {
          calculateExamScore(u, e);
          // 🔥 核心修复：通知已打开的试卷详情抽屉重新拉取最新数据，分数即时刷新
          _detailDrawerRefresh.value = DateTime.now().toIso8601String();
        });

        if (mounted) {
          ToastUtil.showSuccess(context, "重判成功");
          // 🔥 核心修复：重判弹窗（_RejudgeDialog）是独立 dialog 层，
          // 确认按钮 onConfirm 只触发了数据刷新，并未关闭弹窗。
          // 这里补一次 pop 关闭重判弹窗；若 canPop 则说明还有 dialog 栈。
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        }
      } else {
        // 🔥 核心修复：显示后端返回的具体失败原因，而非笼统的"重判失败"
        if (mounted) {
          ToastUtil.showError(context, data["msg"] ?? "重判失败");
        }
      }
    } catch (e) {
      developer.log("confirmRejudge exception: $e");
      if (mounted) {
        ToastUtil.showError(context, "重判失败：网络异常 $e");
      }
    }
  }

  // ====================== 重新计算总分 ======================
  void calculateExamScore(int uIdx, int eIdx) {
    var exam = userList[uIdx]["examList"][eIdx];

    double calc(List list) {
      double s = 0;
      for (var q in list) {
        s += double.tryParse(q["userScore"].toString()) ?? 0;
      }
      return s;
    }

    double s = calc(exam["singleList"]);
    double m = calc(exam["multiList"]);
    double f = calc(exam["fillList"]);
    double sh = calc(exam["shortList"]);

    exam["singleScore"] = s;
    exam["multiScore"] = m;
    exam["fillScore"] = f;
    exam["shortScore"] = sh;
    exam["totalScore"] = s + m + f + sh;
  }

  // ====================== 删除试卷记录 ======================
  Future<void> deleteExamRecord(int uIdx, int eIdx) async {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("删除后无法恢复"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("取消")),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              String account = userList[uIdx]["account"];
              String examId = userList[uIdx]["examList"][eIdx]["examId"];

              final data = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
                  "action": "deleteExamRecord",
                  "account": account,
                  "examId": examId,
                }),
      )).body);
              if (data["success"] == true) {
                setState(() {
                  userList[uIdx]["examList"].removeAt(eIdx);
                  if (userList[uIdx]["examList"].isEmpty) userList.removeAt(uIdx);
                });
                if (mounted) {
                  ToastUtil.showSuccess(context, "删除成功");
                }
              }
            },
            child: const Text("删除", style: TextStyle(color: UIHelpers.errorColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _onRefresh() async {
    await getStatisticsData();
  }

  // ====================== 主界面 ======================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UIHelpers.bgColorLight,
      appBar: AppBar(
        title: const Text("试卷统计", style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true, // 🔥 核心修复：标题居中
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context)),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: Stack(
          children: [
            loading
                ? const Center(child: ExamListShimmer())
                : userList.isEmpty
                    ? const Center(
                        child: Text("暂无答题记录", style: TextStyle(fontSize: 14, color: Colors.grey)))
                    : ListView.builder(
                        padding: EdgeInsets.only(
                            left: 12, right: 12, top: 12, bottom: MediaQuery.of(context).size.height * 0.35),
                        itemCount: userList.length,
                        itemBuilder: (c, uIndex) {
                          var user = userList[uIndex];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 15),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(UIHelpers.radiusLarge)),
                            child: Column(
                              children: [
                                // 用户头（备注已修复）
                                ListTile(
                                  onTap: () => toggleUser(uIndex),
                                  title: Text(
                                    "用户：${user["account"]}\n备注：${user["remark"] ?? "无"}",
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  trailing: Icon(user["expand"] ? Icons.expand_more : Icons.chevron_right),
                                ),

                              // 试卷列表
                              if (user["expand"])
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 15),
                                  child: user["examList"].isEmpty
                                      ? const Text("该用户暂无答题记录")
                                      : Column(
                                          children: [
                                            for (int eIndex = 0; eIndex < user["examList"].length; eIndex++)
                                              buildExamItem(uIndex, eIndex),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }

  // ====================== 试卷项 ======================
  Widget buildExamItem(int uIndex, int eIndex) {
    var user = userList[uIndex];
    var exam = user["examList"][eIndex];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(UIHelpers.radiusMedium)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // 左侧 4 份：试卷标题 / 提交时间 / 得分
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    exam["examName"] ?? "未知试卷",
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fmtTime(exam["submitTime"]),
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "得分：${exam["totalScore"] ?? 0} 分",
                    style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 右侧 1 份：查看 / 删除 垂直排列
            SizedBox(
              width: 72,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => showExamDetailModal(uIndex, eIndex),
                    child: const Text("查看", style: TextStyle(color: UIHelpers.primaryColor, fontSize: 12))),
                  TextButton(
                    onPressed: () => deleteExamRecord(uIndex, eIndex),
                    child: const Text("删除", style: TextStyle(color: UIHelpers.errorColor, fontSize: 12))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====================== 打开试卷详情弹窗（抽屉式，参考家长端） ======================
  void showExamDetailModal(int uIndex, int eIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (dialogCtx) {
        // 🔥 核心修复：ValueListenableBuilder 监听 _detailDrawerRefresh，
        // 每次重判成功后 value 变化会触发本抽屉重新拉取最新数据并重建，分数即时刷新。
        // 关闭抽屉后 ValueListenableBuilder 自动移除监听，无需手动清理。
        return ValueListenableBuilder(
          valueListenable: _detailDrawerRefresh,
          builder: (context, value, _) {
            // 每次重建都从 userList 拉取最新 exam（子列表/分数已被 confirmRejudge 更新）
            final freshExam = userList[uIndex]["examList"][eIndex];
            return Container(
              height: MediaQuery.of(dialogCtx).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部标题 + 关闭按钮（重判保留原弹窗）
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "试卷详情：${freshExam["examName"] ?? "未知试卷"}",
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          icon: const Icon(Icons.close,
                              color: Colors.black54, size: 22),
                        ),
                      ],
                    ),
                  ),
                  // 内容区
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: buildExamDetailWidget(uIndex, eIndex, freshExam),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ====================== 试卷详情（弹窗内容） ======================
  Widget buildExamDetailWidget(int uIndex, int eIndex, Map exam) {
    num total = (exam["singleTotalScore"] ?? 0) +
        (exam["multiTotalScore"] ?? 0) +
        (exam["fillTotalScore"] ?? 0) +
        (exam["shortTotalScore"] ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 试卷头
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: const Color(0xFFE8F3FF), borderRadius: BorderRadius.circular(UIHelpers.radiusLarge)),
          child: Column(
            children: [
              Text(exam["examName"] ?? "未知试卷", style: UIHelpers.titleMedium),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("提交:${fmtTime(exam["submitTime"])}", style: const TextStyle(color: Colors.grey)),
                  Text("得分:${exam["totalScore"] ?? 0} / $total", style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 单选题（从第1题开始）
        if ((exam["singleList"] ?? []).isNotEmpty)
          buildQuestionSection("📝 单选题", exam["singleList"] ?? [], "single", uIndex, eIndex,
              (exam["singleScore"] ?? 0).toDouble(), (exam["singleTotalScore"] ?? 0).toDouble(), 0),

        const SizedBox(height: 12),

        // 多选题（从单选题数量之后开始）
        if ((exam["multiList"] ?? []).isNotEmpty)
          buildQuestionSection("☑️ 多选题", exam["multiList"] ?? [], "multi", uIndex, eIndex,
              (exam["multiScore"] ?? 0).toDouble(), (exam["multiTotalScore"] ?? 0).toDouble(),
              (exam["singleList"] ?? []).length),

        const SizedBox(height: 12),

        // 填空题（从前两类题数量之和开始）
        if ((exam["fillList"] ?? []).isNotEmpty)
          buildQuestionSection("✏️ 填空题", exam["fillList"] ?? [], "fill", uIndex, eIndex,
              (exam["fillScore"] ?? 0).toDouble(), (exam["fillTotalScore"] ?? 0).toDouble(),
              (exam["singleList"] ?? []).length + (exam["multiList"] ?? []).length),

        const SizedBox(height: 12),

        // 简答题（从前三类题数量之和开始）
        if ((exam["shortList"] ?? []).isNotEmpty)
          buildQuestionSection("📄 简答题", exam["shortList"] ?? [], "short", uIndex, eIndex,
              (exam["shortScore"] ?? 0).toDouble(), (exam["shortTotalScore"] ?? 0).toDouble(),
              (exam["singleList"] ?? []).length + (exam["multiList"] ?? []).length + (exam["fillList"] ?? []).length),
      ],
    );
  }
  // ====================== 题型模块 ======================
  Widget buildQuestionSection(String title, List list, String type, int u, int e, double score, double total, [int startIdx = 0]) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(UIHelpers.radiusLarge)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            color: const Color(0xFFE8F3FF),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: UIHelpers.primaryColor, fontSize: 16)),
                Text("得分：$score / $total"),
              ],
            ),
          ),

          // 题目列表
          for (int i = 0; i < list.length; i++)
            buildQuestionItem(list[i], startIdx + i, type, u, e),
        ],
      ),
    );
  }

  // ====================== 单题展示 ======================
  Widget buildQuestionItem(Map q, int index, String type, int u, int e) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：题号 + 重判 + 得分
          Row(
            children: [
              Text("第${index + 1}题"),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => openRejudge(u, e, q, type, index),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8F3FF)),
                child: const Text("重判", style: TextStyle(color: UIHelpers.primaryColor, fontSize: 12)),
              ),
              const Spacer(),
              Text("得分：${q["userScore"] ?? 0} / ${q["score"] ?? 0}"),
            ],
          ),

          const SizedBox(height: 10),

          // 题目内容
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 100, // ✅ 添加宽度约束
              ),
              child: FormulaRenderer.renderMixedText(
                q["title"] ?? "无题目内容",
                style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
                // 🔥 修复：移除 autoWrapLatex，避免对已有正确格式的公式进行二次包裹
              ),
            ),
          ),

          // 选项
          if (q["options"] != null && q["options"].isNotEmpty)
            ...q["options"].asMap().entries.map((entry) {
              int j = entry.key;
              String opt = entry.value.toString();
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(UIHelpers.radiusSmall)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${String.fromCharCode(65 + j)}. ", style: const TextStyle(fontSize: 14, color: Colors.black87)),
                    // 🔥 核心修复：使用 Flexible 替代 Expanded，确保正确换行
                    Flexible(
                      fit: FlexFit.loose,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width - 140, // 减去标签和边距
                          ),
                          child: FormulaRenderer.renderMixedText(
                            opt,
                            style: const TextStyle(fontSize: 14, color: Colors.black87),
                            // 🔥 修复：移除 autoWrapLatex，避免对已有正确格式的公式进行二次包裹
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

          // 题目图片
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

          const SizedBox(height: 10),

          // 我的答案 / 标准答案
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 100),
              child: FormulaRenderer.renderMixedText(
                "我的答案：${type == "multi" ? getMultiAnswerLetter(q, q["userAnswer"]) : getAnswerLetter(q, q["userAnswer"])}",
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 100),
              child: FormulaRenderer.renderMixedText(
                "标准答案：${type == "multi" ? getMultiAnswerLetter(q, q["standardAnswer"]) : getAnswerLetter(q, q["standardAnswer"])}",
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 解析
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 100, // ✅ 添加宽度约束
              ),
              child: FormulaRenderer.renderMixedText(
                "解析：${q["analysis"] ?? "暂无解析"}",
                style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.orange),
                // 🔥 修复：移除 autoWrapLatex，避免对已有正确格式的公式进行二次包裹
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================== 重判弹窗组件 ======================
class _RejudgeDialog extends StatelessWidget {
  final TextEditingController scoreController;
  final dynamic maxScore;
  final VoidCallback onConfirm;

  const _RejudgeDialog({
    required this.scoreController,
    required this.maxScore,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: const Text(
        "修改本题得分",
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E6AFF),
        ),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: scoreController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "请输入新得分",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  "满分：",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  "$maxScore 分",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E6AFF),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            "取消",
            style: TextStyle(color: Colors.grey),
          ),
        ),
        TextButton(
          onPressed: onConfirm,
          style: TextButton.styleFrom(
            backgroundColor: const Color(0xFF1E6AFF),
            foregroundColor: Colors.white,
          ),
          child: const Text("确定修改"),
        ),
      ],
    );
  }
}
