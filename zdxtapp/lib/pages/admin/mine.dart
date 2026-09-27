import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/upload_progress.dart';
import 'package:zdxtapp/pages/admin/usermanage.dart';
import 'package:zdxtapp/pages/public/update.dart';
import 'package:zdxtapp/pages/admin/signmanage.dart';
import '../../widgets/user_agreement.dart';
import 'package:zdxtapp/pages/admin/dataexport.dart';
import 'package:zdxtapp/pages/admin/explain.dart';
import 'package:zdxtapp/pages/admin/update.dart';
import 'package:url_launcher/url_launcher.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  final String serverDomain = Config.baseUrl;

  bool showBgManageModal = false;
  late String bgImageUrl;
  bool _isRefreshingBg = false;

  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    bgImageUrl = "$serverDomain/bg/background.png";
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 上传/删除后强制刷新：清 Flutter 内存图片缓存 + 拉取后端最新 state 码作为 URL 参数
  Future<void> _forceRefreshBg() async {
    if (_isRefreshingBg) return;
    setState(() => _isRefreshingBg = true);

    // 1. 清 Flutter 内存图片缓存（全局单例通过 PaintingBinding 访问）
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
    } catch (_) {
      // 缓存清理失败不阻塞刷新
    }

    // 2. 拉取后端最新 state 码作为 URL 参数（确保每次唯一）
    int state = DateTime.now().millisecondsSinceEpoch;
    try {
      final resp = await http
          .get(Uri.parse('$serverDomain/api/getBgState'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>?;
        final s = json?['state'];
        if (s is int) state = s;
      }
    } catch (_) {
      // 网络失败时仍用时间戳，保证刷新语义
    }

    if (!mounted) return;
    setState(() {
      bgImageUrl = "$serverDomain/bg/background.png?state=$state";
      _isRefreshingBg = false;
    });
  }

  // ====================== 背景图 ======================
  void openBgManage() {
    setState(() {
      showBgManageModal = true;
    });
  }

  Future<void> chooseAndUploadBg() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final uploadId = 'bg_image_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      // ✅ 开始上传，显示进度对话框
      UploadProgressManager.startUpload(uploadId, '背景图片');
      if (!mounted) return;
      showUploadProgress(context, uploadId);

      await http.post(
        Uri.parse('$serverDomain/api/deleteBg'),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
      );

      // ✅ 使用 Dio 流式 multipart 上传，onSendProgress 回报真实字节进度
      final result = await UploadProgressManager.uploadFileWithProgress(
        url: '$serverDomain/api/setBg',
        filePath: picked.path,
        fieldName: 'file',
        uploadId: uploadId,
        fields: {},
        onProgress: (progress) {
          UploadProgressManager.updateProgress(uploadId, progress);
        },
      );

      if (result['success'] == true) {
        UploadProgressManager.uploadSuccess(uploadId);
        if (!mounted) return;
        await _forceRefreshBg();
      } else {
        UploadProgressManager.uploadFailed(uploadId, "上传失败");
      }
    } catch (e) {
      UploadProgressManager.uploadFailed(uploadId, e.toString());
    } finally {
      // 确保上传结束后关闭进度对话框
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> deleteBgImage() async {
    // 🔥 新增：二次确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("确定要删除背景图片吗？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await http.post(
        Uri.parse('$serverDomain/api/deleteBg'),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
      );
      await _forceRefreshBg();
    } catch (e) {
      // 忽略错误
    }
  }

  // ====================== 检查更新 ======================
  void checkUpdate() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UpdatePage()),
    );
  }

  // ====================== 退出登录 ======================
  void logout() async {
    // 🔥 精确清理用户会话 key（userInfo 等），保留声明一次性标记 agreement_ever_shown
    await UserAgreementWidget.removeUserKeys();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  // 🔥 新增：打开官网
  void _openWebsite() async {
    final url = Uri.parse('https://wsq537537.github.io/zd/index');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ToastUtil.show(context, "无法打开官网");
      }
    }
  }

  // ====================== 主界面 ======================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardSize = (screenWidth - 80 - 24) / 3; // 左右各20padding + 2个间距12

    // 管理区功能
    final manageItems = [
      {'icon': Icons.menu_book_outlined, 'label': '课程资源', 'onTap': () => Navigator.pushNamed(context, '/public/browser')},
      {'icon': Icons.people_outline, 'label': '用户管理', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagePage()))},
      {'icon': Icons.system_update_outlined, 'label': '更新管理', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminUpdatePage()))},
      {'icon': Icons.image_outlined, 'label': '设置背景', 'onTap': openBgManage},
      {'icon': Icons.edit_calendar_outlined, 'label': '签到管理', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SignManagePage()))},
      {'icon': Icons.import_export_outlined, 'label': '数据导出', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DataExportPage()))},
      {'icon': Icons.tv_outlined, 'label': '投屏讲解', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ExplainPage()))},
    ];

    // 常规区功能
    final normalItems = [
      {'icon': Icons.update_outlined, 'label': '检查更新', 'onTap': checkUpdate},
      {'icon': Icons.language_outlined, 'label': '官网', 'onTap': _openWebsite},
      {'icon': Icons.logout_outlined, 'label': '退出登录', 'onTap': logout},
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                // 管理区域
                _buildSection(
                  label: "管理",
                  items: manageItems,
                  cardSize: cardSize,
                ),
                const SizedBox(height: 24),
                // 常规区域
                _buildSection(
                  label: "常规",
                  items: normalItems,
                  cardSize: cardSize,
                ),
              ],
            ),
          ),

          if (showBgManageModal) _buildBgModal(),
        ],
      ),
    );
  }

  // 构建分区（透明边框 + 左上角浮标文字 + 卡片网格）
  Widget _buildSection({required String label, required List<Map<String, dynamic>> items, required double cardSize}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black.withValues(alpha: 0.25), width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 浮标标签
          Positioned(
            top: -10,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              color: Colors.transparent,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // 卡片网格
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.start,
              children: items.map((item) {
                return _buildCard(
                  icon: item['icon'] as IconData,
                  label: item['label'] as String,
                  onTap: item['onTap'] as VoidCallback,
                  size: cardSize,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // 方形磨砂卡片
  Widget _buildCard({required IconData icon, required String label, required VoidCallback onTap, required double size}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: const Color(0xFF2B7DFF)),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fullScreenModal({required Widget child}) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black54,
          dismissible: true,
          onDismiss: () => setState(() {
            showBgManageModal = false;
          }),
        ),
        Center(child: child),
      ],
    );
  }

  Widget _buildBgModal() {
    return _fullScreenModal(
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 56),
        constraints: const BoxConstraints(maxHeight: 520),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Row(
                  children: [
                    const Text("背景图管理",
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => showBgManageModal = false),
                      child: const CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(0xFFF5F5F5),
                        child: Icon(Icons.close, size: 16, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.5),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("当前已导入背景：", style: TextStyle(fontSize: 14, color: Colors.black87)),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                bgImageUrl,
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: SizedBox(
                                      width: 32, height: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: const Color(0xFF4F9BFF),
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(child: Text("暂无已导入的背景图", style: TextStyle(color: Colors.black54)));
                                },
                              ),
                              // 刷新中指示器：上传/删除成功后 _forceRefreshBg 期间显示
                              if (_isRefreshingBg)
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      "正在刷新…",
                                      style: TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: deleteBgImage,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        child: const Text("删除当前背景"),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: chooseAndUploadBg,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: const Text("上传新背景图"),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 0.5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => setState(() => showBgManageModal = false),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F9BFF)),
                    child: const Text("关闭"),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
