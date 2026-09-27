import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:zdxtapp/config.dart';

import 'package:zdxtapp/utils/toast.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';

class DataExportPage extends StatefulWidget {
  const DataExportPage({super.key});

  @override
  State<DataExportPage> createState() => _DataExportPageState();
}

class _DataExportPageState extends State<DataExportPage> {
  final String baseUrl = Config.baseUrl;

  int exportType = 0;
  int dataType = 0;

  List<dynamic> allStudents = [];
  List<dynamic> examPapers = [];
  List<dynamic> timeRanges = [];
  bool isLoading = false;
  bool isExporting = false;

  DateTime? examStartDate;
  DateTime? examEndDate;
  bool examAllStudents = true;
  List<String> examSelectedStudents = [];
  bool examAllPapers = true;
  String? selectedExamId;

  String? selectedRangeId;
  bool studyAllSubjects = true;
  List<String> studySelectedSubjects = [];
  bool studyAllStudents = true;
  List<String> studySelectedStudents = [];

  Map<String, dynamic>? exportResult;

  static const _subjects = [
    {'key': 'chinese', 'label': '语文', 'color': Color(0xFF5B8FF9)},
    {'key': 'math', 'label': '数学', 'color': Color(0xFF5AD8A6)},
    {'key': 'english', 'label': '英语', 'color': Color(0xFFF6BD16)},
    {'key': 'other', 'label': '其他', 'color': Color(0xFFE86452)},
  ];

  @override
  void initState() {
    super.initState();
    _loadInitData();
  }

  Future<void> _loadInitData() async {
    setState(() => isLoading = true);
    try {
      final userData = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "getUserList"}),
      )).body);
      final examData = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "getExamList", "page": 1, "limit": 1000}),
      )).body);
      final timeData = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/time"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "getTimeRanges"}),
      )).body);

      setState(() {
        allStudents = (userData['data'] as List?)?.where((s) => s['type'] == 2).toList() ?? [];
        examPapers = (examData['list'] as List?) ?? [];
        timeRanges = (timeData['data'] as List?) ?? [];
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) ToastUtil.show(context, "加载数据失败");
    }
  }

  bool get showExamConfig => exportType == 0 || (exportType == 1 && dataType == 0);
  bool get showStudyConfig => exportType == 0 || (exportType == 1 && dataType == 1);

  Map<String, dynamic> _buildParams() {
    final params = <String, dynamic>{'action': 'export'};

    if (showExamConfig) {
      params['exportType'] = exportType == 0 ? 'all' : 'exam';
      if (examStartDate != null) {
        params['examStartDate'] = _fmtDate(examStartDate!);
      }
      if (examEndDate != null) {
        params['examEndDate'] = _fmtDate(examEndDate!);
      }
      params['examStudentFilter'] = examAllStudents ? 'all' : 'selected';
      if (!examAllStudents) {
        params['examSelectedStudents'] = examSelectedStudents;
      }
      params['examPaperFilter'] = examAllPapers ? 'all' : 'selected';
      if (!examAllPapers && selectedExamId != null) {
        params['selectedExamId'] = selectedExamId;
      }
    }

    if (showStudyConfig) {
      params['exportType'] = exportType == 0 ? 'all' : 'study';
      if (selectedRangeId != null) {
        params['rangeId'] = selectedRangeId;
      }
      params['studyStudentFilter'] = studyAllStudents ? 'all' : 'selected';
      if (!studyAllStudents) {
        params['studySelectedStudents'] = studySelectedStudents;
      }
      params['studySubjectFilter'] = studyAllSubjects ? 'all' : 'selected';
      if (!studyAllSubjects) {
        params['studySelectedSubjects'] = studySelectedSubjects;
      }
    }

    if (exportType == 0) params['exportType'] = 'all';
    return params;
  }

  String _fmtDate(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  Future<void> _doExport() async {
    if (showExamConfig && !examAllStudents && examSelectedStudents.isEmpty) {
      ToastUtil.show(context, "请选择至少一名学生");
      return;
    }
    if (showStudyConfig) {
      if (selectedRangeId == null) {
        ToastUtil.show(context, "请选择时间任务范围");
        return;
      }
      if (!studyAllStudents && studySelectedStudents.isEmpty) {
        ToastUtil.show(context, "请选择至少一名学生");
        return;
      }
      if (!studyAllSubjects && studySelectedSubjects.isEmpty) {
        ToastUtil.show(context, "请选择至少一个科目");
        return;
      }
    }

    setState(() => isExporting = true);
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/export"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(_buildParams()),
      ).timeout(Duration(seconds: 120))).body);
      final data = res;
      if (data['success'] == true) {
        setState(() {
          exportResult = data;
          isExporting = false;
        });
        if (mounted) ToastUtil.show(context, "导出成功");
      } else {
        setState(() => isExporting = false);
        if (mounted) ToastUtil.show(context, data['message'] ?? "导出失败");
      }
    } on Exception catch (e) {
      setState(() => isExporting = false);
      final msg = e.toString();
      if (msg.contains('TimeoutException') || msg.contains('timed out')) {
        if (mounted) ToastUtil.show(context, "导出超时，请稍后重试或缩小数据范围");
      } else {
        if (mounted) ToastUtil.show(context, "导出失败: $e");
      }
    }
  }

  void _downloadFile() async {
    if (exportResult == null) return;
    final url = "$baseUrl${exportResult!['url']}";
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ToastUtil.show(context, "无法打开下载链接");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("数据导出"),
        backgroundColor: const Color(0xFF4A90D9),
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildExportTypeSection(),
                  if (exportType == 1) ...[
                    const SizedBox(height: 12),
                    _buildDataTypeSection(),
                  ],
                  const SizedBox(height: 12),
                  if (showExamConfig) _buildExamConfigSection(),
                  if (showExamConfig && showStudyConfig) const SizedBox(height: 12),
                  if (showStudyConfig) _buildStudyConfigSection(),
                  const SizedBox(height: 20),
                  _buildExportButton(),
                  if (exportResult != null) ...[
                    const SizedBox(height: 20),
                    _buildResultSection(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF333333))),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildExportTypeSection() {
    return _buildCard(
      title: "导出方式",
      children: [
        Row(
          children: [
            Expanded(child: _buildRadioOption("导出全部数据", exportType == 0, () => setState(() { exportType = 0; exportResult = null; }))),
            const SizedBox(width: 12),
            Expanded(child: _buildRadioOption("单独导出", exportType == 1, () => setState(() { exportType = 1; exportResult = null; }))),
          ],
        ),
      ],
    );
  }

  Widget _buildRadioOption(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4A90D9).withValues(alpha: 0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? const Color(0xFF4A90D9) : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20, color: selected ? const Color(0xFF4A90D9) : Colors.grey),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 14, color: selected ? const Color(0xFF4A90D9) : Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTypeSection() {
    return _buildCard(
      title: "数据类型",
      children: [
        Row(
          children: [
            Expanded(child: _buildRadioOption("考试数据", dataType == 0, () => setState(() { dataType = 0; exportResult = null; }))),
            const SizedBox(width: 12),
            Expanded(child: _buildRadioOption("学习数据", dataType == 1, () => setState(() { dataType = 1; exportResult = null; }))),
          ],
        ),
      ],
    );
  }

  Widget _buildExamConfigSection() {
    return _buildCard(
      title: "考试数据配置",
      children: [
        _buildLabel("时间范围"),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange: examStartDate != null && examEndDate != null
                        ? DateTimeRange(start: examStartDate!, end: examEndDate!)
                        : null,
                  );
                  if (range != null) setState(() { examStartDate = range.start; examEndDate = range.end; });
                },
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                  examStartDate != null && examEndDate != null
                      ? "${_fmtDate(examStartDate!)} ~ ${_fmtDate(examEndDate!)}"
                      : "选择日期范围",
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            if (examStartDate != null)
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() { examStartDate = null; examEndDate = null; })),
          ],
        ),
        const SizedBox(height: 12),
        _buildLabel("试卷选择"),
        Row(
          children: [
            Expanded(child: _buildChipOption("全部试卷", examAllPapers, () => setState(() => examAllPapers = true))),
            const SizedBox(width: 8),
            Expanded(child: _buildChipOption("指定试卷", !examAllPapers, () => setState(() => examAllPapers = false))),
          ],
        ),
        if (!examAllPapers) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selectedExamId,
            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            hint: const Text("选择试卷"),
            items: examPapers.map<DropdownMenuItem<String>>((e) {
              return DropdownMenuItem<String>(
                value: e['examId'] as String?,
                child: Text("${e['examName'] ?? ''} (${e['subject'] ?? ''})", overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) => setState(() => selectedExamId = v),
          ),
        ],
        const SizedBox(height: 12),
        _buildLabel("学生筛选"),
        Row(
          children: [
            Expanded(child: _buildChipOption("全部学生", examAllStudents, () => setState(() => examAllStudents = true))),
            const SizedBox(width: 8),
            Expanded(child: _buildChipOption("指定学生", !examAllStudents, () => setState(() => examAllStudents = false))),
          ],
        ),
        if (!examAllStudents) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showStudentPicker(examSelectedStudents, (v) => setState(() => examSelectedStudents = v)),
            icon: const Icon(Icons.people, size: 18),
            label: Text(examSelectedStudents.isEmpty ? "选择学生" : "已选 ${examSelectedStudents.length} 人"),
          ),
        ],
      ],
    );
  }

  Widget _buildStudyConfigSection() {
    return _buildCard(
      title: "学习数据配置",
      children: [
        _buildLabel("时间任务范围"),
        DropdownButtonFormField<String>(
          initialValue: selectedRangeId,
          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          hint: const Text("选择预设时间范围"),
          items: timeRanges.map<DropdownMenuItem<String>>((e) {
            final name = e['name'] ?? '未命名';
            final start = e['startDate'] ?? '';
            final end = e['endDate'] ?? '';
            return DropdownMenuItem<String>(
              value: e['_id'] as String?,
              child: Text("$name ($start~$end)", overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (v) => setState(() => selectedRangeId = v),
        ),
        const SizedBox(height: 12),
        _buildLabel("科目筛选"),
        Row(
          children: [
            Expanded(child: _buildChipOption("全部科目", studyAllSubjects, () => setState(() { studyAllSubjects = true; studySelectedSubjects.clear(); }))),
            const SizedBox(width: 8),
            Expanded(child: _buildChipOption("指定科目", !studyAllSubjects, () => setState(() => studyAllSubjects = false))),
          ],
        ),
        if (!studyAllSubjects) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _subjects.map((s) {
              final selected = studySelectedSubjects.contains(s['key'] as String);
              return FilterChip(
                label: Text(s['label'] as String),
                selected: selected,
                onSelected: (v) => setState(() {
                  if (v) {
                    studySelectedSubjects.add(s['key'] as String);
                  } else {
                    studySelectedSubjects.remove(s['key'] as String);
                  }
                }),
                selectedColor: (s['color'] as Color).withValues(alpha: 0.3),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 12),
        _buildLabel("学生筛选"),
        Row(
          children: [
            Expanded(child: _buildChipOption("全部学生", studyAllStudents, () => setState(() => studyAllStudents = true))),
            const SizedBox(width: 8),
            Expanded(child: _buildChipOption("指定学生", !studyAllStudents, () => setState(() => studyAllStudents = false))),
          ],
        ),
        if (!studyAllStudents) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showStudentPicker(studySelectedStudents, (v) => setState(() => studySelectedStudents = v)),
            icon: const Icon(Icons.people, size: 18),
            label: Text(studySelectedStudents.isEmpty ? "选择学生" : "已选 ${studySelectedStudents.length} 人"),
          ),
        ],
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildChipOption(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4A90D9).withValues(alpha: 0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? const Color(0xFF4A90D9) : Colors.grey.shade300),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: selected ? const Color(0xFF4A90D9) : Colors.grey.shade700)),
      ),
    );
  }

  void _showStudentPicker(List<String> current, ValueChanged<List<String>> onDone) {
    final temp = List<String>.from(current);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text("选择学生 (${temp.length}/${allStudents.length})"),
          content: SizedBox(
            width: double.maxFinite,
            child: allStudents.isEmpty
                ? const Center(child: Text("暂无学生数据"))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: allStudents.length,
                    itemBuilder: (ctx, i) {
                      final s = allStudents[i];
                      final account = s['account'] as String? ?? '';
                      final remark = s['remark'] as String? ?? account;
                      final selected = temp.contains(account);
                      return CheckboxListTile(
                        value: selected,
                        title: Text("$remark ($account)"),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            temp.add(account);
                          } else {
                            temp.remove(account);
                          }
                        }),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(onPressed: () { onDone(temp); Navigator.pop(ctx); }, child: const Text("确定")),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButton() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: isExporting ? null : _doExport,
            icon: isExporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download),
            label: Text(isExporting ? "正在导出..." : "开始导出", style: const TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            onPressed: isLoading ? null : _runDiagnostics,
            icon: const Icon(Icons.bug_report, size: 18),
            label: const Text("数据诊断", style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Future<void> _runDiagnostics() async {
    setState(() => isLoading = true);
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/export"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "debug"}),
      ).timeout(Duration(seconds: 15))).body);
      final data = res;
      if (data['success'] == true && mounted) {
        final d = data['data'] as Map<String, dynamic>;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("数据诊断结果"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _diagRow("学生总数", "${d['studentCount'] ?? 0}"),
                _diagRow("答题记录数", "${d['examRecordCount'] ?? 0}"),
                _diagRow("学习记录数", "${d['timerecordCount'] ?? 0}"),
                _diagRow("时间范围数", "${d['timeRangeCount'] ?? 0}"),
                if (d['examSample'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text("答题记录字段: ${d['examSample'].join(', ')}",
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                if ((d['timeRanges'] as List?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("时间范围:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ...((d['timeRanges'] as List).map((r) => Text(
                          "  ${r['name']} (${r['start']}~${r['end']})",
                          style: const TextStyle(fontSize: 12),
                        ))),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    (d['examRecordCount'] ?? 0) == 0
                        ? "提示: 答题记录为0，请确认学生已提交过试卷"
                        : (d['studentCount'] ?? 0) == 0
                            ? "提示: 学生数为0，请检查用户数据"
                            : "数据正常，可以导出",
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭")),
            ],
          ),
        );
      } else if (mounted) {
        ToastUtil.show(context, "诊断失败: ${data['message'] ?? '未知错误'}");
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, "诊断请求失败: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildResultSection() {
    final summary = exportResult!['summary'] as Map<String, dynamic>?;
    final debug = exportResult!['debug'] as Map<String, dynamic>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCard(
          title: "导出结果",
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 28),
                const SizedBox(width: 8),
                const Expanded(child: Text("导出成功", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                FilledButton.icon(
                  onPressed: _downloadFile,
                  icon: const Icon(Icons.file_download, size: 18),
                  label: const Text("下载Excel"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(exportResult!['filename'] as String? ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        if (debug != null) ...[
          const SizedBox(height: 12),
          _buildDebugCard(debug),
        ],
        if (summary != null) ...[
          if (summary['exam'] != null) ...[
            const SizedBox(height: 12),
            _buildExamSummary(summary['exam'] as Map<String, dynamic>),
          ],
          if (summary['study'] != null) ...[
            const SizedBox(height: 12),
            _buildStudySummary(summary['study'] as Map<String, dynamic>),
          ],
        ],
      ],
    );
  }

  Widget _buildDebugCard(Map<String, dynamic> debug) {
    final sheets = (debug['sheets'] as List?) ?? [];
    final examExec = debug['examSection'] == true;
    final examRecs = debug['examRecords'] ?? 0;
    final fileSize = debug['fileSize'] ?? 0;

    return _buildCard(
      title: "导出诊断",
      children: [
        _buildStatRow([
          {'label': '导出类型', 'value': '${debug['exportType'] ?? "?"}'},
          {'label': '学生映射', 'value': '${debug['nameMapSize'] ?? 0}'},
          {'label': '文件大小', 'value': (fileSize as num) > 1024 ? '${(fileSize / 1024).round()}KB' : '${fileSize}B'},
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: examExec
                ? (examRecs > 0 ? Colors.green.shade50 : Colors.red.shade50)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    examExec ? (examRecs > 0 ? Icons.check : Icons.warning) : Icons.remove_circle_outline,
                    size: 18,
                    color: examExec ? (examRecs > 0 ? Colors.green : Colors.red) : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "考试数据: ${examExec ? '已执行, 查到 $examRecs 条' : '未执行'}",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: examExec ? (examRecs > 0 ? Colors.green.shade800 : Colors.red.shade800) : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    debug['studySection'] == true ? Icons.check : Icons.remove_circle_outline,
                    size: 18,
                    color: debug['studySection'] == true ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "学习数据: ${debug['studySection'] == true ? '已执行, 查到 ${debug['studyRecords'] ?? 0} 条' : '未执行'}",
                    style: TextStyle(
                      fontSize: 13,
                      color: debug['studySection'] == true ? Colors.green.shade800 : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text("Excel工作表:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ...sheets.map((s) {
          final map = s as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Text(
              "  ${map['name']}: ${map['rowCount']}行",
              style: TextStyle(
                fontSize: 12,
                color: ((map['rowCount'] as int?) ?? 0) > 1 ? Colors.black87 : Colors.red.shade600,
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildExamSummary(Map<String, dynamic> exam) {
    final subjectStats = (exam['subjectStats'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final scoreDist = (exam['scoreDistribution'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return _buildCard(
      title: "考试数据统计",
      children: [
        _buildStatRow([
          {'label': '学生数', 'value': '${exam['totalStudents'] ?? 0}'},
          {'label': '考试数', 'value': '${exam['totalExams'] ?? 0}'},
          {'label': '记录数', 'value': '${exam['totalRecords'] ?? 0}'},
          {'label': '平均分', 'value': '${exam['avgScore'] ?? 0}'},
          {'label': '及格率', 'value': '${exam['passRate'] ?? 0}%'},
        ]),
        const SizedBox(height: 16),
        if (subjectStats.isNotEmpty) ...[
          const Text("各科平均分", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: _buildSubjectBarChart(subjectStats),
          ),
        ],
        if (scoreDist.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text("分数段分布", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: _buildScorePieChart(scoreDist),
          ),
        ],
      ],
    );
  }

  Widget _buildStudySummary(Map<String, dynamic> study) {
    final subjectTotals = (study['subjectTotals'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final studentTotals = (study['studentTotals'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return _buildCard(
      title: "学习数据统计",
      children: [
        _buildStatRow([
          {'label': '学生数', 'value': '${study['totalStudents'] ?? 0}'},
          {'label': '学习天数', 'value': '${study['totalDays'] ?? 0}'},
          {'label': '记录数', 'value': '${study['totalRecords'] ?? 0}'},
        ]),
        const SizedBox(height: 16),
        if (subjectTotals.isNotEmpty) ...[
          const Text("科目时长占比", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: _buildSubjectPieChart(subjectTotals),
          ),
        ],
        if (studentTotals.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text("学生学习时长排行", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: _buildStudentBarChart(studentTotals),
          ),
        ],
      ],
    );
  }

  Widget _buildStatRow(List<Map<String, String>> stats) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: stats.map((s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF4A90D9).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(s['value']!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4A90D9))),
            const SizedBox(height: 2),
            Text(s['label']!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildSubjectBarChart(List<Map<String, dynamic>> stats) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gIdx, rod, rIdx) =>
                BarTooltipItem(rod.toY.toStringAsFixed(1), const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i >= 0 && i < stats.length) {
                  return Text(stats[i]['subject'] as String? ?? '',
                      style: const TextStyle(fontSize: 11, color: Colors.black87));
                }
                return const Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: stats.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: (e.value['avgScore'] as num?)?.toDouble() ?? 0,
                color: const Color(0xFF4A90D9),
                width: 22,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildScorePieChart(List<Map<String, dynamic>> dist) {
    final colors = [const Color(0xFFE86452), const Color(0xFFFAAD14), const Color(0xFFFFD666), const Color(0xFF5AD8A6), const Color(0xFF5B8FF9)];
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: PieChart(
            PieChartData(
              sections: dist.asMap().entries.map((e) {
                final count = (e.value['count'] as num?)?.toInt() ?? 0;
                return PieChartSectionData(
                  value: count.toDouble(),
                  color: colors[e.key % colors.length],
                  title: count > 0 ? '$count' : '',
                  radius: 65,
                  titleStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                );
              }).toList(),
              sectionsSpace: 3,
              centerSpaceRadius: 40,
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: dist.asMap().entries.map((e) {
              final range = e.value['range'] as String? ?? '';
              final count = (e.value['count'] as num?)?.toInt() ?? 0;
              final color = colors[e.key % colors.length];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(child: Text('$range: $count人', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectPieChart(List<Map<String, dynamic>> totals) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: PieChart(
            PieChartData(
              sections: totals.asMap().entries.map((e) {
                final mins = (e.value['totalMinutes'] as num?)?.toDouble() ?? 0;
                final subj = e.value['subject'] as String? ?? '';
                final color = _subjects.firstWhere((s) => s['label'] == subj, orElse: () => {'color': Colors.grey})['color'] as Color;
                return PieChartSectionData(
                  value: mins,
                  color: color,
                  title: mins > 0 ? '${(mins / totals.fold(0.0, (sum, t) => sum + (t['totalMinutes'] as num?)!.toDouble()) * 100).round()}%' : '',
                  radius: 65,
                  titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                );
              }).toList(),
              sectionsSpace: 3,
              centerSpaceRadius: 40,
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: totals.map((t) {
              final subj = t['subject'] as String? ?? '';
              final mins = (t['totalMinutes'] as num?)?.toInt() ?? 0;
              final color = _subjects.firstWhere((s) => s['label'] == subj, orElse: () => {'color': Colors.grey})['color'] as Color;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text("$subj: $mins分钟", style: const TextStyle(fontSize: 12)),
                ]),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentBarChart(List<Map<String, dynamic>> students) {
    final top = students.take(10).toList();
    final maxVal = top.fold<double>(0, (max, s) {
      final v = (s['totalMinutes'] as num?)?.toDouble() ?? 0;
      return v > max ? v : max;
    });
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gIdx, rod, rIdx) {
              final i = group.x.toInt();
              if (i >= 0 && i < top.length) {
                return BarTooltipItem('${top[i]['name'] ?? ''}: ${rod.toY.toInt()}分钟', const TextStyle(color: Colors.white, fontSize: 12));
              }
              return null;
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i >= 0 && i < top.length) {
                  final name = top[i]['name'] as String? ?? '';
                  return Text(name.length > 4 ? '${name.substring(0, 3)}…' : name,
                      style: const TextStyle(fontSize: 10, color: Colors.black87));
                }
                return const Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 1),
        maxY: maxVal * 1.2,
        barGroups: top.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: (e.value['totalMinutes'] as num?)?.toDouble() ?? 0,
                color: const Color(0xFF5AD8A6),
                width: 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

