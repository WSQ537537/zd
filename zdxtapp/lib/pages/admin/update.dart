import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';

class AdminUpdatePage extends StatefulWidget {
  const AdminUpdatePage({super.key});

  @override
  State<AdminUpdatePage> createState() => _AdminUpdatePageState();
}

class _AdminUpdatePageState extends State<AdminUpdatePage> with SingleTickerProviderStateMixin {
  final String baseUrl = Config.baseUrl;
  late TabController _tabController;

  // 正式更新
  late TextEditingController _formalVersionCtrl;
  late TextEditingController _formalUrlCtrl;
  late TextEditingController _formalUpdateInfoCtrl;
  bool _formalLoading = false;

  // 内测推送
  late TextEditingController _betaVersionCtrl;
  late TextEditingController _betaUrlCtrl;
  late TextEditingController _betaUpdateInfoCtrl;
  String? _betaStartTime;
  String? _betaEndTime;
  bool _betaLoading = false;
  bool _pushEnabled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _formalVersionCtrl = TextEditingController();
    _formalUrlCtrl = TextEditingController();
    _formalUpdateInfoCtrl = TextEditingController();
    _betaVersionCtrl = TextEditingController();
    _betaUrlCtrl = TextEditingController();
    _betaUpdateInfoCtrl = TextEditingController();
    _loadFormalVersion();
    _loadBetaConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _formalVersionCtrl.dispose();
    _formalUrlCtrl.dispose();
    _formalUpdateInfoCtrl.dispose();
    _betaVersionCtrl.dispose();
    _betaUrlCtrl.dispose();
    _betaUpdateInfoCtrl.dispose();
    super.dispose();
  }

  // ========== 加载正式版本 ==========
  Future<void> _loadFormalVersion() async {
    setState(() => _formalLoading = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/version'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'get'}),
      )).body);
      if (data['success'] == true) {
        final d = data['data'] ?? {};
        setState(() {
          _formalVersionCtrl.text = d['version'] ?? '';
          _formalUrlCtrl.text = d['url'] ?? '';
          _formalUpdateInfoCtrl.text = d['updateInfo'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('加载正式版本失败: $e');
    }
    if (mounted) setState(() => _formalLoading = false);
  }

  // ========== 保存正式版本 ==========
  Future<void> _saveFormalVersion() async {
    final version = _formalVersionCtrl.text.trim();
    final url = _formalUrlCtrl.text.trim();
    if (version.isEmpty || url.isEmpty) {
      ToastUtil.show(context, '版本号和下载链接不能为空');
      return;
    }
    setState(() => _formalLoading = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/version'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'set',
          'version': version,
          'url': url,
          'updateInfo': _formalUpdateInfoCtrl.text.trim(),
        }),
      )).body);
      if (mounted) {
        if (data['success'] == true) {
          ToastUtil.show(context, '正式版本已保存');
        } else {
          ToastUtil.show(context, data['message'] ?? '保存失败');
        }
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, '保存失败');
    }
    if (mounted) setState(() => _formalLoading = false);
  }

  // ========== 加载内测配置 ==========
  Future<void> _loadBetaConfig() async {
    setState(() => _betaLoading = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/version'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getBeta'}),
      )).body);
      if (data['success'] == true && data['data'] != null) {
        final d = data['data'];
        setState(() {
          _betaVersionCtrl.text = d['version'] ?? '';
          _betaUrlCtrl.text = d['url'] ?? '';
          _betaUpdateInfoCtrl.text = d['updateInfo'] ?? '';
          _betaStartTime = d['startTimeStr'] as String?;
          _betaEndTime = d['endTimeStr'] as String?;
          _pushEnabled = d['pushEnabled'] == true;
        });
      } else {
        setState(() {
          _betaVersionCtrl.clear();
          _betaUrlCtrl.clear();
          _betaUpdateInfoCtrl.clear();
          _betaStartTime = null;
          _betaEndTime = null;
          _pushEnabled = false;
        });
      }
    } catch (e) {
      debugPrint('加载内测配置失败: $e');
    }
    if (mounted) setState(() => _betaLoading = false);
  }

  // ========== 保存内测配置 ==========
  Future<void> _saveBetaConfig() async {
    final version = _betaVersionCtrl.text.trim();
    final url = _betaUrlCtrl.text.trim();
    if (version.isEmpty || url.isEmpty) {
      ToastUtil.show(context, '版本号和下载链接不能为空');
      return;
    }
    if (_betaStartTime == null || _betaEndTime == null) {
      ToastUtil.show(context, '内测开始时间和结束时间不能为空');
      return;
    }
    setState(() => _betaLoading = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/version'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'saveBeta',
          'version': version,
          'url': url,
          'startTime': _betaStartTime,
          'endTime': _betaEndTime,
          'updateInfo': _betaUpdateInfoCtrl.text.trim(),
          'pushEnabled': _pushEnabled,
        }),
      )).body);
      if (mounted) {
        if (data['success'] == true) {
          ToastUtil.show(context, '内测配置已保存');
          await _loadBetaConfig();
        } else {
          ToastUtil.show(context, data['message'] ?? '保存失败');
        }
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, '保存失败');
    }
    if (mounted) setState(() => _betaLoading = false);
  }

  // ========== 清除内测表单（同时删除后端记录） ==========
  Future<void> _clearBetaForm() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/version'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'deleteBeta'}),
      );
    } catch (_) {}
    if (mounted) {
      setState(() {
        _betaVersionCtrl.clear();
        _betaUrlCtrl.clear();
        _betaUpdateInfoCtrl.clear();
        _betaStartTime = null;
        _betaEndTime = null;
        _pushEnabled = false;
      });
      ToastUtil.show(context, '已清除');
    }
  }

  // ========== 切换推送开关 ==========
  Future<void> _togglePushEnabled(bool value) async {
    setState(() => _pushEnabled = value);
    // 持久化到本地
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('beta_push_enabled', value);
    // 同步到数据库
    if (_betaVersionCtrl.text.isNotEmpty && _betaStartTime != null && _betaEndTime != null) {
      await http.post(
        Uri.parse('$baseUrl/api/version'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'saveBeta',
          'version': _betaVersionCtrl.text.trim(),
          'url': _betaUrlCtrl.text.trim(),
          'startTime': _betaStartTime,
          'endTime': _betaEndTime,
          'updateInfo': _betaUpdateInfoCtrl.text.trim(),
          'pushEnabled': value,
        }),
      );
    }
  }

  // ========== 选择开始时间 ==========
  Future<void> _pickStartDate() async {
    DateTime? initial;
    if (_betaStartTime != null && _betaStartTime!.isNotEmpty) {
      initial = DateTime.parse(_betaStartTime!);
      if (initial.isUtc) initial = initial.toLocal();
    }
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;

    final TimeOfDay initTime = initial != null ? TimeOfDay(hour: initial.hour, minute: initial.minute) : TimeOfDay.now();
    final time = await showTimePicker(context: context, initialTime: initTime);
    if (!mounted || time == null) return;

    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _betaStartTime = _formatDateTime(combined));
  }

  // ========== 选择结束时间 ==========
  Future<void> _pickEndDate() async {
    DateTime? initial;
    if (_betaEndTime != null && _betaEndTime!.isNotEmpty) {
      initial = DateTime.parse(_betaEndTime!);
      if (initial.isUtc) initial = initial.toLocal();
    }
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!mounted) return;

    final TimeOfDay initTime = initial != null ? TimeOfDay(hour: initial.hour, minute: initial.minute) : const TimeOfDay(hour: 23, minute: 59);
    final time = await showTimePicker(context: context, initialTime: initTime);
    if (!mounted || time == null) return;

    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _betaEndTime = _formatDateTime(combined));
  }

  /// 格式化为 'yyyy-MM-dd HH:mm'（兼容后端 Date 解析）
  String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('更新管理', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.blue,
              indicatorWeight: 3,
              indicator: const UnderlineTabIndicator(borderSide: BorderSide(color: Colors.blue, width: 3)),
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 14),
              tabs: const [
                Tab(text: '正式更新'),
                Tab(text: '内测推送'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildFormalTab(), _buildBetaTab()],
      ),
    );
  }

  // ========== 正式更新 Tab ==========
  Widget _buildFormalTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(Icons.system_update, Colors.blue, '正式更新'),
          const SizedBox(height: 16),
          _buildFormCard(
            isLoading: _formalLoading,
            child: Column(
              children: [
                _buildTextField(_formalVersionCtrl, '版本号', '例如 2.1.0', maxLength: 20),
                const SizedBox(height: 16),
                _buildTextField(_formalUrlCtrl, '下载链接', 'https://.../app.apk'),
                const SizedBox(height: 20),
                _buildTextField(_formalUpdateInfoCtrl, '更新内容', '修复了...\n新增功能...', isMultiline: true, fieldHeight: 160),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _formalLoading ? null : _saveFormalVersion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _formalLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('保存正式版本', style: TextStyle(fontSize: 15, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== 内测推送 Tab ==========
  Widget _buildBetaTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(Icons.science, Colors.orange, '内测推送'),
          const SizedBox(height: 16),
          _buildFormCard(
            isLoading: _betaLoading,
            child: Column(
              children: [
                _buildTextField(_betaVersionCtrl, '内测版本号', '例如 1.5.0-beta', maxLength: 20),
                const SizedBox(height: 12),
                _buildTextField(_betaUrlCtrl, '下载链接（仅后端存储）', '', hideLabel: true),
                const SizedBox(height: 12),
                _buildTimePickerRow('内测开始时间', _betaStartTime ?? '未设置', _pickStartDate),
                const SizedBox(height: 12),
                _buildTimePickerRow('内测结束时间', _betaEndTime ?? '未设置', _pickEndDate),
                const SizedBox(height: 12),
                _buildTextField(_betaUpdateInfoCtrl, '内测更新内容', '', isMultiline: true, hideLabel: true, fieldHeight: 160),
                const SizedBox(height: 20),
                // 底部控件：左侧胶囊按钮 + 右侧推送开关
                Row(
                  children: [
                    // 左侧：胶囊一体双按钮
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCapsuleBtn('清除内容', Colors.grey.shade300, _clearBetaForm),
                          const VerticalDivider(width: 1, color: Colors.white24),
                          _buildCapsuleBtn('保存', Colors.blue.shade300, _saveBetaConfig),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // 右侧：推送开关
                    Row(
                      children: [
                        const Text('推送', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(width: 8),
                        _buildToggleSwitch(_pushEnabled, _togglePushEnabled),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '保存仅录入数据，推送开关独立控制是否对外可见。',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== 辅助构建方法 ==========
  Widget _buildSectionHeader(IconData icon, Color color, String title) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildFormCard({required Widget child, bool isLoading = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : child,
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, String hint, {bool isMultiline = false, bool hideLabel = false, int? maxLength, double? fieldHeight}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hideLabel)
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        if (!hideLabel) const SizedBox(height: 4),
        // 多行文本：固定高度，内容超出内部滚动；单行：自适应
        isMultiline && fieldHeight != null
            ? ClipRect(
                child: SizedBox(
                  height: fieldHeight,
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    minLines: 1,
                    textCapitalization: TextCapitalization.none,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              )
            : SizedBox(
                height: fieldHeight,
                child: TextField(
                  controller: controller,
                  maxLines: isMultiline ? null : 1,
                  minLines: isMultiline ? 1 : null,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: isMultiline ? TextInputAction.newline : null,
                  maxLength: maxLength,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    counterStyle: const TextStyle(color: Colors.white38),
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildTimePickerRow(String label, String displayText, VoidCallback onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onPick,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: Colors.white54),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displayText,
                    style: TextStyle(color: displayText == '未设置' ? Colors.white38 : Colors.white, fontSize: 14),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCapsuleBtn(String label, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _buildToggleSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? Colors.blue : Colors.grey.shade600,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
