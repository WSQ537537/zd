import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:zdxtapp/config.dart';

import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/upload_progress.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart' hide ImageSource;
import '../../widgets/common_video_player.dart';

class NoticePage extends StatefulWidget {
  const NoticePage({super.key});

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  final String baseUrl = Config.baseUrl;
  int currentTab = 1;
  int subTab = 1;
  String noticeType = "system";

  final TextEditingController _contentController = TextEditingController();
  List<dynamic> mediaList = [];
  int cursorPos = 0;

  List<dynamic> systemList = [];
  List<dynamic> departmentList = [];
  List<dynamic> feedbackList = [];
  bool isRequesting = false;

  // 🔥 批量删除状态（系统通知、学习通知各自独立）
  bool systemBatchMode = false;
  bool departmentBatchMode = false;
  Set<String> systemSelectedIds = {};
  Set<String> departmentSelectedIds = {};

  // 🔥 删除动画反馈状态
  bool _isDeleting = false;
  String? _deletingType; // "single" | "batch"

  // 🔥 懒加载分页状态（系统通知、学习通知各自独立）
  int systemPage = 1;
  int departmentPage = 1;
  static const int _pageSize = 10;
  int systemTotal = 0;
  int departmentTotal = 0;
  bool systemLoadingMore = false;
  bool departmentLoadingMore = false;
  ScrollController? _systemScrollCtrl;
  ScrollController? _deptScrollCtrl;

  bool showEditModal = false;
  final TextEditingController _editController = TextEditingController();
  List<dynamic> editMediaList = [];
  String? currentEditId;
  int editCursorPos = 0;

  final ImagePicker _picker = ImagePicker();
  bool _showVideoSourceDialog = false;
  String? _videoInsertTarget; // "main" | "edit"

  @override
  void initState() {
    super.initState();
    _systemScrollCtrl = ScrollController();
    _deptScrollCtrl = ScrollController();
    _systemScrollCtrl!.addListener(() => _onScroll(_systemScrollCtrl!, true));
    _deptScrollCtrl!.addListener(() => _onScroll(_deptScrollCtrl!, false));
    Future.microtask(() {
      if (currentTab == 2) {
        subTab == 1 ? getNoticeList() : getFeedbackList();
      }
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _editController.dispose();
    _systemScrollCtrl?.dispose();
    _deptScrollCtrl?.dispose();
    super.dispose();
  }

  String cleanContent(String content) {
    // 处理图片标签
    content = content.replaceAllMapped(
      RegExp(r'\[image:(https?://[^\s\]]+)\]'),
      (match) => '<img src="${match.group(1)}" style="max-width:100%;height:auto;">',
    );
    // 处理视频标签
    content = content.replaceAllMapped(
      RegExp(r'\[video:(https?://[^\s\]]+)\]'),
      (match) => '<video src="${match.group(1)}" controls style="max-width:100%;height:auto;margin:8px 0;"></video>',
    );
    // 清理残留的标签标记
    content = content.replaceAll(RegExp(r'\[(image|video):[^\]]*\]'), '');
    content = content.replaceAll('\n', '<br>');
    return content;
  }

  List<String> extractImageUrls(String content) {
    final reg = RegExp(r'https?://[^\s<>"]+\.(jpg|jpeg|png|gif|webp)');
    return reg.allMatches(content).map((m) => m.group(0)!).toList();
  }

  String formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return "";
    try {
      DateTime d = DateTime.parse(timeStr);
      return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} "
          "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return timeStr;
    }
  }

  Widget _buildEditVideoPlayer(String videoUrl) {
    return CommonVideoPlayer(
      videoUrl: videoUrl,
      // 🔥 统一按在线视频处理：原始直链直接播放，B站网页地址才解析，
      //    与"不预解析、播放时解析"策略保持一致
      videoType: 2,
      autoPlay: false, // 通知页面不自动播放
    );
  }

  Future<Map<String, dynamic>> uploadFile(String path, String type, {bool showProgress = true}) async {
    final uploadId = 'notice_${type}_${DateTime.now().millisecondsSinceEpoch}';
    final fileName = type == 'image' ? '图片' : '视频';
    
    try {
      // ✅ 开始上传，显示进度对话框（仅在需要时）
      UploadProgressManager.startUpload(uploadId, fileName);
      if (showProgress) {
        showUploadProgress(context, uploadId);
      }
      
      // ✅ 使用 Dio 进行真实上传，支持进度回调
      final result = await UploadProgressManager.uploadFileWithProgress(
        url: "$baseUrl/api/notice",
        filePath: path,
        fieldName: 'file',
        uploadId: uploadId,
        fields: {
          'action': 'upload',
          'type': type,
        },
        onProgress: (progress) {
          // ✅ 实时更新真实进度
          UploadProgressManager.updateProgress(uploadId, progress);
        },
      );
      
      if (result['success'] == true) {
        final data = result['data'];
        if (data['success'] == true) {
          UploadProgressManager.uploadSuccess(uploadId);
          return {
            "success": true,
            "url": data['url'] != null ? "$baseUrl${data['url']}" : null
          };
        } else {
          UploadProgressManager.uploadFailed(uploadId, data['message'] ?? "服务器返回失败");
          return {"success": false};
        }
      } else {
        UploadProgressManager.uploadFailed(uploadId, result['error'] ?? "上传失败");
        return {"success": false};
      }
    } catch (e) {
      UploadProgressManager.uploadFailed(uploadId, e.toString());
      return {"success": false};
    } finally {
      // 统一在 finally 中关闭进度对话框，避免遗漏
      if (showProgress && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  /// 图片上传（带重试机制，最多重试2次，提升成功率）
  Future<Map<String, dynamic>> _uploadImageWithRetry(String filePath) async {
    int maxRetries = 2;
    int attempt = 0;
    Map<String, dynamic> lastResult = {'success': false};

    while (attempt <= maxRetries) {
      try {
        final result = await uploadFile(filePath, 'image', showProgress: false);
        if (result['success'] == true) {
          return result;
        }
        lastResult = result;
      } catch (e) {
        lastResult = {'success': false, 'error': e.toString()};
      }
      attempt++;
      if (attempt <= maxRetries) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return lastResult;
  }

  Future<void> insertMedia(String type) async {
    try {
      XFile? file;
      if (type == "image") {
        file = await _picker.pickImage(source: ImageSource.gallery);
      } else {
        file = await _picker.pickVideo(source: ImageSource.gallery);
      }
      if (file == null) return;

      setState(() => isRequesting = true);
      // 🔥 修复：主界面上传时显示进度弹窗
      final up = await uploadFile(file.path, type, showProgress: true);
      setState(() => isRequesting = false);

      if (up['success'] == true) {
        String url = up['url'];
        String tag = type == 'video' ? '[video:$url]' : '[image:$url]';
        final text = _contentController.text;
        _contentController.text = text.substring(0, cursorPos) + tag + text.substring(cursorPos);
        setState(() {
          mediaList.add({"type": type, "url": url});
        });
      }
    } catch (e) {
      setState(() => isRequesting = false);
    }
  }

  Future<void> insertEditMedia(String type) async {
    try {
      XFile? file;
      if (type == "image") {
        file = await _picker.pickImage(source: ImageSource.gallery);
      } else {
        file = await _picker.pickVideo(source: ImageSource.gallery);
      }
      if (file == null) return;

      // 🔥 修复：编辑弹窗中上传时不显示进度弹窗，避免冲突
      final up = await uploadFile(file.path, type, showProgress: false);
      if (up['success'] == true) {
        String url = up['url'];
        String tag = type == 'video' ? '[video:$url]' : '[image:$url]';
        final text = _editController.text;
        _editController.text = text.substring(0, editCursorPos) + tag + text.substring(editCursorPos);
        setState(() {
          editMediaList.add({"type": type, "url": url});
        });
      }
    } catch (e) {
      // Intentionally empty - error handling done via return value check or ignored for non-critical errors
    }
  }

  Future<void> removeMedia(int index) async {
    final m = mediaList[index];
    String tag = m['type'] == 'image' ? '[image:${m['url']}]' : '[video:${m['url']}]';
    _contentController.text = _contentController.text.replaceAll(tag, "");
    setState(() => mediaList.removeAt(index));

    // 确保在异步操作中使用context前检查mounted状态
    if (!mounted) return;
    
    await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "deleteMediaFile", "url": m['url']}),
      )).body);
  }

  void removeEditMedia(int index) async {
    final m = editMediaList[index];
    String tag = m['type'] == 'image' ? '[image:${m['url']}]' : '[video:${m['url']}]';
    _editController.text = _editController.text.replaceAll(tag, "");
    setState(() => editMediaList.removeAt(index));

    // 确保在异步操作中使用context前检查mounted状态
    if (mounted) {
      await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "deleteMediaFile", "url": m['url']}),
      )).body);
    }
  }

  Future<void> sendNotice() async {
    setState(() => isRequesting = true);
    try {
      await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "send",
        "type": noticeType,
        "content": _contentController.text,
        "mediaList": mediaList,
      }),
      )).body);
      _contentController.clear();
      setState(() {
        mediaList.clear();
        isRequesting = false;
      });
      if (mounted) {
        ToastUtil.show(context, "发送成功");
      }
    } catch (e) {
      setState(() => isRequesting = false);
    }
  }

  Future<void> getNoticeList() async {
    if (isRequesting) return;
    setState(() => isRequesting = true);
    try {
      systemPage = 1;
      departmentPage = 1;
      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "list", "page": 1, "limit": _pageSize}),
      )).body);
      if (res['success'] == true) {
        setState(() {
          systemList = res['data']['systemList'] ?? [];
          departmentList = res['data']['departmentList'] ?? [];
          final pg = res['data']['pagination'] ?? {};
          systemTotal = int.tryParse((pg['systemTotal'] ?? 0).toString()) ?? 0;
          departmentTotal = int.tryParse((pg['departmentTotal'] ?? 0).toString()) ?? 0;
        });
      }
    } finally {
      setState(() => isRequesting = false);
    }
  }

  /// 🔥 懒加载更多通知
  Future<void> _loadMoreNotice(bool isSystem) async {
    final loading = isSystem ? systemLoadingMore : departmentLoadingMore;
    final page = isSystem ? systemPage : departmentPage;
    final total = isSystem ? systemTotal : departmentTotal;
    if (loading) return;
    if (page * _pageSize >= total) return;

    setState(() {
      if (isSystem) {
        systemLoadingMore = true;
      } else {
        departmentLoadingMore = true;
      }
    });

    try {
      final nextPage = page + 1;
      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "list", "page": nextPage, "limit": _pageSize}),
      )).body);
      if (res['success'] == true) {
        setState(() {
          if (isSystem) {
            systemList.addAll(res['data']['systemList'] ?? []);
            systemPage = nextPage;
          } else {
            departmentList.addAll(res['data']['departmentList'] ?? []);
            departmentPage = nextPage;
          }
        });
      }
    } catch (e) {
      debugPrint("加载更多失败: $e");
    } finally {
      setState(() {
        if (isSystem) {
          systemLoadingMore = false;
        } else {
          departmentLoadingMore = false;
        }
      });
    }
  }

  /// 🔥 滚动监听：接近底部时触发加载
  void _onScroll(ScrollController ctrl, bool isSystem) {
    if (!ctrl.hasClients) return;
    final maxScroll = ctrl.position.maxScrollExtent;
    final currentScroll = ctrl.position.pixels;
    if (maxScroll - currentScroll < 100) {
      _loadMoreNotice(isSystem);
    }
  }

  Future<void> getFeedbackList() async {
    setState(() => isRequesting = true);
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "adminList"}),
      )).body);
      if (res['success'] == true) {
        setState(() => feedbackList = res['data'] ?? []);
      }
    } finally {
      setState(() => isRequesting = false);
    }
  }

  // 反馈加载状态
  bool _feedbackLoading = false;

  Future<void> refreshFeedbackList() async {
    if (_feedbackLoading) return;
    setState(() => _feedbackLoading = true);
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "adminList"}),
      )).body);
      if (res['success'] == true) {
        setState(() => feedbackList = res['data'] ?? []);
      }
    } finally {
      setState(() => _feedbackLoading = false);
    }
  }

  Future<void> deleteNotice(dynamic id) async {
    // 🔥 新增：二次确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("删除后无法恢复，确定要删除这条公告吗？"),
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

    setState(() { _isDeleting = true; _deletingType = "single"; });
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "delete", "id": id}),
      )).body);
      if (res['success'] == true) {
        getNoticeList(); // 删除成功后刷新列表
        if (mounted) ToastUtil.show(context, "删除成功");
      } else {
        if (mounted) ToastUtil.show(context, "删除失败：${res['message'] ?? res['msg'] ?? '未知错误'}");
      }
    } catch (e) {
      debugPrint("删除通知异常: $e");
      if (mounted) ToastUtil.show(context, "删除失败，请重试");
    } finally {
      if (mounted) setState(() { _isDeleting = false; _deletingType = null; });
    }
  }

  void _showFeedbackDetail(Map<String, dynamic> item) {
    final isHandled = item['status'] == 'handled';
    final userContent = (item['content'] ?? '').toString();
    final userMedia = (item['mediaList'] ?? []) as List;
    final replyContent = (item['replyContent'] ?? '').toString();
    final replyMedia = (item['replyMediaList'] ?? []) as List;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    int detailTab = 0; // 0=用户反馈, 1=管理员回复

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: isHandled
            ? Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => detailTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: detailTab == 0 ? const Color(0xFF2B7DFF) : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          "反馈内容",
                          style: TextStyle(
                            fontSize: 15,
                            color: detailTab == 0 ? const Color(0xFF2B7DFF) : Colors.grey,
                            fontWeight: detailTab == 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => detailTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: detailTab == 1 ? const Color(0xFF2B7DFF) : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          "管理员回复",
                          style: TextStyle(
                            fontSize: 15,
                            color: detailTab == 1 ? const Color(0xFF2B7DFF) : Colors.grey,
                            fontWeight: detailTab == 1 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: Text(
                  "反馈内容",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
          content: SizedBox(
            width: screenWidth * 0.85,
            height: screenHeight * 0.45,
            child: isHandled
              ? (detailTab == 0
                ? _buildDetailColumn(userContent, userMedia)
                : _buildDetailColumn(replyContent.isEmpty ? '暂无回复内容' : replyContent, replyMedia))
              : _buildDetailColumn(userContent, userMedia),
          ),
          actions: [
            if (!isHandled)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  handleFeedback(item['_id']);
                },
                child: const Text("去处理"),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("关闭"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailColumn(String content, List mediaList) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(content, style: const TextStyle(fontSize: 15, height: 1.6)),
          if (mediaList.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: mediaList.map<Widget>((item) {
                final url = item is String ? item : (item['url'] ?? '');
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url.toString(),
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 120,
                        height: 120,
                        color: Colors.grey[200],
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (e, s, r) => Container(
                      width: 120, height: 120, color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, size: 36),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> handleFeedback(dynamic id) async {
    final replyController = TextEditingController();
    List<dynamic> replyImages = [];
    // 图片上传状态跟踪
    final Map<String, bool> uploadingImages = {};
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: screenWidth * 0.85,
            height: screenHeight * 0.5,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              children: [
                // 标题
                const Row(
                  children: [
                    Text("处理反馈", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                // 上方：文字输入区域（内容超出自动滚动）
                Expanded(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: TextField(
                      controller: replyController,
                      autofocus: false,
                      maxLines: null,
                      minLines: 10,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: "输入回复内容...",
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                // 分界线（固定位置）
                const Divider(height: 1, thickness: 1, color: Color(0xFFE8E8E8)),
                const SizedBox(height: 12),
                // 图片区域（紧贴分界线下方，从左到右横向排布，多行时内部滚动）
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        children: List.generate(replyImages.length, (i) {
                        final img = replyImages[i];
                        final imageId = img['id'] ?? img['url'];
                        final isUploading = uploadingImages[imageId] ?? false;

                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: isUploading
                                ? Container(
                                    width: 64, height: 64,
                                    color: Colors.grey[200],
                                    child: const Center(
                                      child: SizedBox(
                                        width: 16, height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  )
                                : Image.network(
                                    img['url'],
                                    width: 64, height: 64, fit: BoxFit.cover,
                                    errorBuilder: (e, s, r) => Container(width: 64, height: 64, color: Colors.grey[200], child: const Icon(Icons.broken_image, size: 20)),
                                  ),
                            ),
                            if (!isUploading)
                              Positioned(
                                top: 2, right: 2,
                                child: GestureDetector(
                                  onTap: () async {
                                    final imgUrl = replyImages[i]['url'] ?? '';
                                    // 先从本地移除
                                    setS(() => replyImages.removeAt(i));
                                    // 同步删除后端文件
                                    if (imgUrl.isNotEmpty) {
                                      try {
                                        await http.post(
                                          Uri.parse("$baseUrl/api/notice"),
                                          headers: {"Content-Type": "application/json"},
                                          body: jsonEncode({"action": "deleteMediaFile", "url": imgUrl}),
                                        );
                                      } catch (_) {}
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                                  ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
                const SizedBox(height: 12),
                // 底部按钮行（固定位置）：左侧加图按钮，右侧取消+确认
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        XFile? file = await _picker.pickImage(source: ImageSource.gallery);
                        if (file == null) return;

                        final String imageId = file.path;
                        // 立即添加占位项到列表，显示加载动画
                        setS(() {
                          replyImages.add({'type': 'image', 'url': '', 'id': imageId});
                          uploadingImages[imageId] = true;
                        });

                        final up = await _uploadImageWithRetry(file.path);
                        if (up['success'] == true) {
                          setS(() {
                            // 找到对应索引，替换为真实url
                            final index = replyImages.indexWhere((img) => img['id'] == imageId);
                            if (index != -1) {
                              replyImages[index]['url'] = up['url'];
                            }
                            uploadingImages.remove(imageId);
                          });
                        } else {
                          setS(() {
                            // 上传失败，移除占位项
                            replyImages.removeWhere((img) => img['id'] == imageId);
                            uploadingImages.remove(imageId);
                          });
                          if (mounted) ToastUtil.show(context, '上传失败，请重试');
                        }
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: const Text("添加图片", style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey[300]!),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        replyController.dispose();
                        final navigator = Navigator.of(ctx);
                        // 取消时删除已上传的图片
                        for (final img in replyImages) {
                          final url = img['url'] ?? '';
                          if (url.isNotEmpty) {
                            try {
                              await http.post(
                                Uri.parse("$baseUrl/api/notice"),
                                headers: {"Content-Type": "application/json"},
                                body: jsonEncode({"action": "deleteMediaFile", "url": url}),
                              );
                            } catch (_) {}
                          }
                        }
                        navigator.pop(null);
                      },
                      child: Text("取消", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final replyContent = replyController.text;
                        replyController.dispose();
                        Navigator.pop(ctx, {
                          'replyContent': replyContent,
                          'replyMediaList': replyImages,
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2B7DFF),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("确认", style: TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == null) return;

    final replyContent = result['replyContent'] as String? ?? '';
    final replyMediaList = result['replyMediaList'] as List<dynamic>? ?? [];

    await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "handle",
        "_id": id,
        "replyContent": replyContent,
        "replyMediaList": replyMediaList,
      }),
      )).body);
    getFeedbackList();
  }

  Future<void> deleteFeedback(dynamic id) async {
    // 🔥 新增：二次确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("删除后无法恢复，确定要删除这条反馈吗？"),
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

    await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "delete", "id": id}),
      )).body);
    getFeedbackList();
  }

  void openEditModal(dynamic item) {
    setState(() {
      currentEditId = item['id'] ?? item['_id'];
      _editController.text = item['content'] ?? "";
      editMediaList = List.from(item['mediaList'] ?? []);
      showEditModal = true;
    });
  }

  void closeEditModal() {
    setState(() {
      showEditModal = false;
      _editController.clear();
      editMediaList.clear();
      currentEditId = null;
    });
  }

  Future<void> saveEditNotice() async {
    try {
      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "update",
          "id": currentEditId,
          "content": _editController.text,
          "mediaList": editMediaList,
        }),
      )).body);

      if (res['success'] == true) {
        closeEditModal();
        getNoticeList();
        if (mounted) {
          ToastUtil.show(context, "修改成功");
        }
      } else {
        if (mounted) {
          ToastUtil.show(context, "修改失败: ${res['message'] ?? '未知错误'}");
        }
      }
    } catch (e) {
      debugPrint("Save edit notice error: $e");
      if (mounted) {
        ToastUtil.show(context, "发生错误，请重试");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _buildTabItem("发布通知", 1),
                      _buildTabItem("记录反馈", 2),
                    ],
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: currentTab - 1,
                    children: [
                      _buildPublishPage(),
                      _buildHandlePage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showEditModal) _buildEditModal(),
          if (_showVideoSourceDialog) _buildVideoSourceDialog(),
        ],
      ),
    );
  }

  Widget _buildTabItem(String text, int idx) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => currentTab = idx);
          if (idx == 2) {
            subTab == 1 ? getNoticeList() : getFeedbackList();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: currentTab == idx
                ? const Border(bottom: BorderSide(color: Color(0xFF007AFF), width: 2))
                : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              color: currentTab == idx ? const Color(0xFF007AFF) : Colors.black87,
              fontWeight: currentTab == idx ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPublishPage() {
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCardHeight = constraints.maxHeight - 70;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxCardHeight),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildTypeItem("系统通知", "system"),
                      const SizedBox(width: 12),
                      _buildTypeItem("学习通知", "department"),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _buildMediaBtn("📷 插入图片", "image")),
                      const SizedBox(width: 12),
                      Expanded(child: _buildMediaBtn("🎬 插入视频", "video")),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 固定高度输入框，内容超出时内部滚动
                  SizedBox(
                    height: 200, // 固定高度
                    child: TextField(
                      controller: _contentController,
                      autofocus: false,
                      maxLines: null, // 允许无限行数
                      expands: true, // 填充整个容器高度
                      textAlignVertical: TextAlignVertical.top, // 文本从顶部开始，光标在左上角
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      scrollPadding: EdgeInsets.only(bottom: viewInsetsBottom + 20),
                      decoration: const InputDecoration(
                        hintText: "请输入通知内容，支持换行。点击插入图片/视频按钮，会在光标处添加标记",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12),
                      ),
                      onChanged: (v) {
                        cursorPos = _contentController.selection.baseOffset;
                        setState(() {});
                      },
                      onTap: () {
                        cursorPos = _contentController.selection.baseOffset;
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text("已输入：${_contentController.text.length} 字"),
                  ),
                  // 媒体列表区域（独立布局，不再与输入框共用Expanded）
                  if (mediaList.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      height: 150, // 固定高度
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("已添加媒体：", style: TextStyle(color: Colors.black87)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: mediaList.length,
                              itemBuilder: (ctx, i) {
                                final item = mediaList[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      item['type'] == "image"
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.network(item['url'], width: 60, height: 60, fit: BoxFit.cover),
                                            )
                                          : Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(
                                                color: Colors.black12,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Icon(Icons.play_arrow),
                                            ),
                                      const SizedBox(width: 12),
                                      Text(item['type'] == "image" ? "图片" : "视频", style: const TextStyle(color: Colors.black87)),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: () => removeMedia(i),
                                        child: const Text("删除", style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isRequesting ? null : sendNotice,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        isRequesting ? "发送中..." : "发送通知",
                        style: const TextStyle(color: Colors.black87, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypeItem(String text, String type) {
    return GestureDetector(
      onTap: () => setState(() => noticeType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: noticeType == type ? const Color(0xFF007AFF) : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(color: noticeType == type ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildMediaBtn(String text, String type) {
    if (type == "video") {
      return ElevatedButton(
        onPressed: () => _showVideoSourcePicker("main"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.85),
          elevation: 2,
        ),
        child: Text(text, style: const TextStyle(color: Color(0xFF007AFF))),
      );
    }
    return ElevatedButton(
      onPressed: () => insertMedia(type),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.85),
        elevation: 2,
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF007AFF))),
    );
  }

  void _showVideoSourcePicker(String target) {
    _videoInsertTarget = target;
    _showVideoSourceDialog = true;
    setState(() {});
  }

  void _showOnlineVideoInput() {
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("在线视频"),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "粘贴视频网址（B站网页地址或视频直链），不预先解析，播放时自动解析",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: "视频链接",
                    hintText: "粘贴视频网址（B站地址或直链）",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("取消"),
            ),
            ElevatedButton(
              onPressed: () async {
                final url = urlCtrl.text.trim();
                if (url.isEmpty) {
                  ToastUtil.show(ctx, "请输入视频链接");
                  return;
                }
                // ✅ 直接插入原始网址，不预先解析；解析由播放器在播放时执行
                setDialogState(() {});
                final result = await _insertOnlineVideoParsed(ctx, url);
                if (result != null && mounted) {
                  ToastUtil.show(context, result);
                }
              },
              child: const Text("插入"),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔥 在线视频插入：直接存入原始网址，不预先解析；解析交给播放器在每次播放时执行（防止直链提前解析后失效）
  /// 不走后端 saveOnlineVideo 动作，mediaList 标记 online:true，占位符 [video:原始网址]
  /// 返回提示消息（由调用方统一 Toast），null 表示未插入（如页面已卸载）
  Future<String?> _insertOnlineVideoParsed(BuildContext dialogContext, String url) async {
    if (!mounted) return null;

    final target = _videoInsertTarget ?? "main";
    final savedUrl = url.trim();
    final tag = '[video:$savedUrl]';
    if (target == "main") {
      final text = _contentController.text;
      _contentController.text = text.substring(0, cursorPos) + tag + text.substring(cursorPos);
      setState(() {
        mediaList.add({"type": "video", "url": savedUrl, "online": true});
      });
    } else {
      final text = _editController.text;
      _editController.text = text.substring(0, editCursorPos) + tag + text.substring(editCursorPos);
      setState(() {
        editMediaList.add({"type": "video", "url": savedUrl, "online": true});
      });
    }
    // ✅ 关闭对话框，返回值供调用方统一 Toast（避免跨 async 使用 dialogContext）
    final msg = "在线视频已插入（播放时自动解析）";
    Navigator.of(dialogContext).pop(msg);
    return msg;
  }

  // 在线视频改为纯前端解析，无需后端 saveOnlineVideo 动作；旧方法已移除。


  Widget _buildVideoSourceDialog() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showVideoSourceDialog = false;
          _videoInsertTarget = null;
        });
      },
      child: Stack(
        children: [
          ModalBarrier(color: Colors.black38, dismissible: true),
          Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "插入视频",
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),
                    // 本地视频
                    _buildVideoSourceCard(
                      icon: Icons.folder,
                      title: "本地视频",
                      subtitle: "从相册选择并上传",
                      onTap: () {
                        final target = _videoInsertTarget ?? "main";
                        setState(() {
                          _showVideoSourceDialog = false;
                          _videoInsertTarget = null;
                        });
                        if (target == "main") {
                          insertMedia("video");
                        } else {
                          insertEditMedia("video");
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    // 在线视频
                    _buildVideoSourceCard(
                      icon: Icons.cloud,
                      title: "在线视频",
                      subtitle: "粘贴B站链接或视频直链",
                      onTap: () {
                        setState(() {
                          _showVideoSourceDialog = false;
                        });
                        _showOnlineVideoInput();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showVideoSourceDialog = false;
                          _videoInsertTarget = null;
                        });
                      },
                      child: const Text("取消", style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSourceCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E9F0)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: const Color(0xFF007AFF)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildHandlePage() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              _buildSubTabItem("通知记录", 1),
              _buildSubTabItem("反馈处理", 2),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: IndexedStack(
            index: subTab - 1,
            children: [
              _buildNoticeListPage(),
              _buildFeedbackPage(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubTabItem(String text, int idx) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => subTab = idx);
          idx == 1 ? getNoticeList() : getFeedbackList();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: subTab == idx
                ? const Border(bottom: BorderSide(color: Color(0xFF007AFF), width: 2))
                : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              color: subTab == idx ? const Color(0xFF007AFF) : Colors.black87,
              fontWeight: subTab == idx ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoticeListPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          // 系统通知
          SizedBox(
            height: 260, // 下移10单位
            child: _buildNoticeList("系统通知", systemList, isSystem: true),
          ),

          // 中间间距
          const SizedBox(height: 4),

          // 学习通知（自动占满剩下高度，底部保持70单位间距）
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 65),
              child: _buildNoticeList("学习通知", departmentList, isSystem: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeList(String title, List<dynamic> list, {required bool isSystem}) {
    final batchMode = isSystem ? systemBatchMode : departmentBatchMode;
    final selectedIds = isSystem ? systemSelectedIds : departmentSelectedIds;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${isSystem ? systemTotal : departmentTotal}",
                  style: const TextStyle(color: Colors.black87, fontSize: 12),
                ),
              ),
              const Spacer(),
              // 🔥 批量删除模式切换
              if (!batchMode)
                GestureDetector(
                  onTap: list.isEmpty
                      ? null
                      : () {
                          setState(() {
                            if (isSystem) {
                              systemBatchMode = true;
                            } else {
                              departmentBatchMode = true;
                            }
                          });
                        },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.delete_sweep, size: 20, color: Color(0xFF007AFF)),
                  ),
                )
              else ...[
                // 取消按钮
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (isSystem) {
                          systemBatchMode = false;
                          systemSelectedIds.clear();
                        } else {
                          departmentBatchMode = false;
                          departmentSelectedIds.clear();
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text("取消", style: TextStyle(fontSize: 13, color: Colors.grey)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 全选/取消全选按钮
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        final ids = Set<String>.from(list.map((item) => (item['id'] ?? item['_id']).toString()));
                        if (isSystem) {
                          // 🔥 修复：用 isEmpty 判断全选态——非空=有选中→取消全选；空=未选→全选
                          if (systemSelectedIds.isNotEmpty) {
                            systemSelectedIds.clear();
                          } else {
                            systemSelectedIds = ids;
                          }
                        } else {
                          if (departmentSelectedIds.isNotEmpty) {
                            departmentSelectedIds.clear();
                          } else {
                            departmentSelectedIds = ids;
                          }
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        selectedIds.isEmpty ? "全选" : "取消全选",
                        style: const TextStyle(fontSize: 13, color: Color(0xFF007AFF)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 确认删除按钮
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: selectedIds.isEmpty || _isDeleting
                        ? null
                        : () => _batchDeleteNotice(isSystem, selectedIds.toList()),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: (_isDeleting && _deletingType == "batch")
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(
                              "删除(${selectedIds.length})",
                              style: TextStyle(
                                fontSize: 13,
                                color: selectedIds.isEmpty || _isDeleting ? Colors.grey : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const Divider(height: 1, color: Colors.white30),
          // 内容独立滚动，填满区
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text("暂无数据", style: TextStyle(fontSize: 13, color: Colors.grey)))
                : batchMode
                    ? _buildLazyList(isSystem, list, selectedIds, batchMode: true)
                    : _buildLazyList(isSystem, list, selectedIds, batchMode: false),
          ),
        ],
      ),
    );
  }

  /// 🔥 懒加载列表（普通模式+批量模式通用）
  Widget _buildLazyList(bool isSystem, List<dynamic> list, Set<String> selectedIds, {required bool batchMode}) {
    final ctrl = isSystem ? _systemScrollCtrl : _deptScrollCtrl;
    final loading = isSystem ? systemLoadingMore : departmentLoadingMore;
    final total = isSystem ? systemTotal : departmentTotal;
    final hasMore = list.length < total;

    return ListView.builder(
      controller: ctrl,
      padding: const EdgeInsets.only(bottom: 8),
      shrinkWrap: false,
      itemCount: list.length + 1, // +1 for footer
      itemBuilder: (ctx, i) {
        if (i < list.length) {
          final item = list[i];
          if (batchMode) {
            final itemId = (item['id'] ?? item['_id']).toString();
            final isSelected = selectedIds.contains(itemId);
            return _buildBatchNoticeItem(item, isSelected, () {
              setState(() {
                if (isSelected) {
                  selectedIds.remove(itemId);
                } else {
                  selectedIds.add(itemId);
                }
              });
            });
          } else {
            return _buildNoticeItem(item);
          }
        }
        // 🔥 底部状态
        if (loading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        if (hasMore) {
          return const SizedBox(height: 4);
        }
        // 无更多数据
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              list.isEmpty ? "暂无数据" : "暂无更多",
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        );
      },
    );
  }

  /// 🔥 批量删除模式下的列表项（带勾选框）
  Widget _buildBatchNoticeItem(dynamic item, bool isSelected, VoidCallback onToggle) {
    String content = item['content'] ?? '';
    String plainText = content
        .replaceAll(RegExp(r'\[image:[^\]]*\]'), '[图片]')
        .replaceAll(RegExp(r'\[video:[^\]]*\]'), '[视频]')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('\n', ' ')
        .trim();
    String preview = plainText.length > 5 ? '${plainText.substring(0, 5)}...' : plainText;

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: const Color(0xFF007AFF), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 勾选框
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 22,
                color: isSelected ? const Color(0xFF007AFF) : Colors.grey,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatTime(item['createTime']),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔥 批量删除通知
  Future<void> _batchDeleteNotice(bool isSystem, List<String> ids) async {
    if (ids.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认批量删除"),
        content: Text("删除后无法恢复，确定要删除选中的 ${ids.length} 条通知吗？"),
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

    setState(() { _isDeleting = true; _deletingType = "batch"; });
    try {
      for (final id in ids) {
        await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "delete", "id": id}),
      )).body);
      }
      setState(() {
        if (isSystem) {
          systemBatchMode = false;
          systemSelectedIds.clear();
        } else {
          departmentBatchMode = false;
          departmentSelectedIds.clear();
        }
      });
      getNoticeList();
      if (mounted) ToastUtil.show(context, "删除成功");
    } catch (e) {
      debugPrint("批量删除异常: $e");
      if (mounted) ToastUtil.show(context, "删除失败，请重试");
    } finally {
      if (mounted) setState(() { _isDeleting = false; _deletingType = null; });
    }
  }

  Widget _buildNoticeItem(dynamic item) {
    String content = item['content'] ?? '';
    // 列表只展示纯文本前5个字，去掉HTML/媒体标记
    String plainText = content
        .replaceAll(RegExp(r'\[image:[^\]]*\]'), '[图片]')
        .replaceAll(RegExp(r'\[video:[^\]]*\]'), '[视频]')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('\n', ' ')
        .trim();
    String preview = plainText.length > 5 ? '${plainText.substring(0, 5)}...' : plainText;

    return GestureDetector(
      onTap: () => _showNoticeDetailDialog(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧：内容预览
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatTime(item['createTime']),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            // 右侧：删除、更改按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _isDeleting ? null : () => deleteNotice(item['id'] ?? item['_id']),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2, right: 10, top: 4, bottom: 4),
                    child: (_isDeleting && _deletingType == "single")
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  ),
                ),
                GestureDetector(
                  onTap: () => openEditModal(item),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.edit, size: 20, color: Color(0xFF007AFF)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 🔥 通知详情弹窗（尺寸稍大，内容超出可滚动）
  void _showNoticeDetailDialog(dynamic item) {
    String content = item['content'] ?? '';
    String html = cleanContent(content);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("通知详情", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: Colors.grey, size: 24),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 内容区（可滚动）
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: HtmlWidget(
                    html,
                    textStyle: const TextStyle(fontSize: 15, height: 1.6),
                    customWidgetBuilder: (element) {
                      if (element.localName == 'video') {
                        final src = element.attributes['src'];
                        if (src != null) {
                          return _buildEditVideoPlayer(src);
                        }
                      }
                      return null;
                    },
                  ),
                ),
              ),
              // 底部时间
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                alignment: Alignment.centerRight,
                child: Text(
                  formatTime(item['createTime']),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔥 问题3：全部删除反馈
  Future<void> deleteAllFeedback() async {
    if (feedbackList.isEmpty) {
      ToastUtil.show(context, "暂无反馈可删除");
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除全部"),
        content: Text("确定要删除所有 ${feedbackList.length} 条反馈吗？删除后无法恢复。",
            style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("全部删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => isRequesting = true);
    try {
      // 获取所有反馈ID并批量删除
      final ids = feedbackList.map((item) => item['_id']).toList();
      await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "deleteAll", "ids": ids}),
      )).body);
      setState(() {
        feedbackList.clear();
        isRequesting = false;
      });
      if (mounted) {
        ToastUtil.show(context, "已删除全部反馈");
      }
    } catch (e) {
      setState(() => isRequesting = false);
      if (mounted) {
        ToastUtil.showError(context, "删除失败: $e");
      }
    }
  }

  Widget _buildFeedbackPage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("用户反馈处理", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (feedbackList.isNotEmpty)
                  TextButton.icon(
                    onPressed: deleteAllFeedback,
                    icon: const Icon(Icons.delete_sweep, size: 16),
                    label: const Text("全部删除", style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: isRequesting
                ? const Center(child: CircularProgressIndicator())
                : feedbackList.isEmpty
                ? const Center(child: Text("暂无反馈"))
                : _feedbackLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: refreshFeedbackList,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 70),
                      itemCount: feedbackList.length,
                      itemBuilder: (ctx, i) {
                        var item = feedbackList[i];
                        return FeedbackCard(
                          item: item,
                          onTap: () => _showFeedbackDetail(item),
                          onHandle: () => handleFeedback(item['_id']),
                          onDelete: () => deleteFeedback(item['_id']),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditModal() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    return Stack(
      children: [
        ModalBarrier(color: Colors.black54, dismissible: true, onDismiss: closeEditModal),
        // 使用 Positioned 固定弹窗位置，不受键盘唤起影响
        Positioned(
          left: 8,
          right: 8,
          top: screenHeight * 0.08,
          bottom: screenHeight * 0.08,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: screenWidth - 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 标题栏
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "编辑通知",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        GestureDetector(
                          onTap: closeEditModal,
                          child: const Icon(Icons.close, color: Colors.grey, size: 24),
                        ),
                      ],
                    ),
                  ),
                  // 内容区域
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(
                        children: [
                          // 媒体按钮
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => insertEditMedia("image"),
                                  icon: const Icon(Icons.image, size: 18),
                                  label: const Text("图片"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF0F7FF),
                                    foregroundColor: const Color(0xFF007AFF),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _showVideoSourcePicker("edit"),
                                  icon: const Icon(Icons.video_library, size: 18),
                                  label: const Text("视频"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFF0F5),
                                    foregroundColor: const Color(0xFFFF6B9D),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 输入框 - 限制最大高度并允许内部滚动
                          Container(
                            constraints: BoxConstraints(
                              maxHeight: screenHeight * 0.22,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE9ECEF)),
                            ),
                            child: TextField(
                              controller: _editController,
                              autofocus: false,
                              maxLines: null,
                              minLines: 5,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              decoration: const InputDecoration(
                                hintText: "请输入通知内容...",
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                              onChanged: (v) {
                                editCursorPos = _editController.selection.baseOffset;
                              },
                              onTap: () {
                                editCursorPos = _editController.selection.baseOffset;
                              },
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 媒体列表标题
                          Row(
                            children: [
                              const Icon(Icons.attachment, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              const Text(
                                "已添加媒体",
                                style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 4),
                              if (editMediaList.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF007AFF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    "${editMediaList.length}",
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 媒体列表
                          Expanded(
                            child: editMediaList.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.perm_media_outlined, size: 40, color: Colors.grey[300]),
                                        const SizedBox(height: 8),
                                        Text("暂无媒体文件", style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    shrinkWrap: false,
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    itemCount: editMediaList.length,
                                    itemBuilder: (ctx, i) {
                                      dynamic m = editMediaList[i];
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8F9FA),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFE9ECEF)),
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          leading: m['type'] == "image"
                                              ? ClipRRect(
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: Image.network(m['url'], width: 44, height: 44, fit: BoxFit.cover),
                                                )
                                              : Container(
                                                  width: 44,
                                                  height: 44,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFFF0F5),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Icon(Icons.play_circle_outline, color: Color(0xFFFF6B9D), size: 24),
                                                ),
                                          title: Text(
                                            m['type'] == "image" ? "图片 ${i + 1}" : "视频 ${i + 1}",
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                          trailing: IconButton(
                                            onPressed: () => removeEditMedia(i),
                                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                            splashRadius: 20,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 底部按钮栏
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Color(0xFFEEEEEE), width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: closeEditModal,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              side: BorderSide(color: Colors.grey[300]!),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text("取消", style: TextStyle(fontSize: 15)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: saveEditNotice,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF007AFF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text("保存", style: TextStyle(fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// 反馈卡片组件
class FeedbackCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onHandle;
  final VoidCallback onDelete;

  const FeedbackCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onHandle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isHandled = item['status'] == 'handled';
    final content = (item['content'] ?? '').toString();
    final studentId = item['studentId'] ?? '未知';
    final studentRemark = item['studentRemark'] ?? '无';
    final createTime = _formatTime(item['createTime']);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部信息行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "账号: $studentId",
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "备注: $studentRemark",
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isHandled)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onHandle,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text("处理", style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onDelete,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        child: Text("删除", style: TextStyle(color: Colors.red[400], fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 内容区域
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.length > 5 ? '${content.substring(0, 5)}...' : content,
                  style: TextStyle(fontSize: 14, height: 1.5, color: Colors.grey[800]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    createTime,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      final DateTime dt = DateTime.parse(timeStr);
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timeStr;
    }
  }
}

