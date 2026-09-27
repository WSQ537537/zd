import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart' hide ImageSource;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/common_video_player.dart';
import '../../widgets/shimmer_loading.dart';

class NoticePage extends StatefulWidget {
  const NoticePage({super.key});

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  final String baseUrl = Config.baseUrl;
  List systemList = [];
  List departmentList = [];
  List myFeedbackList = [];

  String studentId = '';
  String studentRemark = '';
  String feedbackContent = '';
  String activeTab = 'send';

  bool showFeedbackModal = false;
  bool showDetailModal = false;
  bool showImagePreview = false;
  List<dynamic> feedbackImages = [];
  final ImagePicker _picker = ImagePicker();
  // 图片上传状态跟踪
  final Map<String, bool> uploadingImages = {};

  Map<String, dynamic> currentDetail = {};
  String previewImageUrl = '';

  // 分页状态
  int systemPage = 1;
  int departmentPage = 1;
  bool systemHasMore = true;
  bool departmentHasMore = true;
  bool systemLoadingMore = false;
  bool departmentLoadingMore = false;
  int _sysUnread = 0;
  int _deptUnread = 0;
  bool _isInitialLoading = true;
  final ScrollController systemScrollController = ScrollController();
  final ScrollController departmentScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    getUserInfo().then((_) {
      getNoticeList();
      getMyFeedbackList();
    });
  }

  @override
  void dispose() {
    systemScrollController.dispose();
    departmentScrollController.dispose();
    super.dispose();
  }

  String cutText(String? str) {
    if (str == null || str.isEmpty) return '空通知';
    str = str.replaceAll(RegExp(r'\[image:[^\]]+\]'), '');
    str = str.replaceAll(RegExp(r'\[video:[^\]]+\]'), '');
    str = str.replaceAll('\n', '');
    if (str.length <= 5) return str;
    return '${str.substring(0, 5)}...';
  }

  String formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      final parsed = DateTime.parse(timeStr);
      final cst = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
      return '${cst.year}-${cst.month.toString().padLeft(2, '0')}-${cst.day.toString().padLeft(2, '0')} '
          '${cst.hour.toString().padLeft(2, '0')}:${cst.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timeStr;
    }
  }

  String renderContent(String? text) {
    if (text == null) return '';
    String html = text.replaceAllMapped(
      RegExp(r'\[image:([^\]]+)\]'),
          (m) => '<img src="${m.group(1)}" style="width:100%;max-width:100%;height:auto;display:block;margin:8px 0;border-radius:8px;" />',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[video:([^\]]+)\]'),
          (m) => '<div class="video-container" data-src="${m.group(1)}">🎬 视频占位</div>',
    );
    return html.replaceAll('\n', '<br/>');
  }

  Future<void> getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfo = prefs.getString('userInfo');
    
    debugPrint('📥 [用户信息] 原始数据: $userInfo');
    
    if (userInfo != null) {
      Map<String, dynamic> user;
      try {
        final dynamic decoded = jsonDecode(userInfo);
        user = (decoded is Map) ? (decoded.map((k, v) => MapEntry(k.toString(), v))) : <String, dynamic>{};
      } catch (_) {
        debugPrint('❌ [用户信息] 解析失败，按空处理');
        return;
      }
      debugPrint('📥 [用户信息] 解析结果: account=${user['account']}, remark=${user['remark']}');
      
      setState(() {
        studentId = user['account'] ?? '';
        studentRemark = user['remark'] ?? '';
      });
      
      debugPrint('✅ [用户信息] 设置完成: studentId="$studentId", studentRemark="$studentRemark"');
    } else {
      debugPrint('❌ [用户信息] 未找到 userInfo');
    }
  }

  Future<void> getNoticeList() async {
    systemPage = 1;
    departmentPage = 1;
    systemHasMore = true;
    departmentHasMore = true;
    setState(() {
      systemList = [];
      departmentList = [];
      systemLoadingMore = false;
      departmentLoadingMore = false;
    });
    await _fetchNoticePage(1);
  }

  Future<void> _fetchNoticePage(int page) async {
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/notice'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "list", "studentId": studentId, "page": "$page", "limit": "10"}),
      )).body);
      if (!mounted) return;
      if (data['success'] == true) {
        final newSystem = data['data']['systemList'] ?? [];
        final newDept = data['data']['departmentList'] ?? [];
        final pagination = data['data']['pagination'] ?? {};
        int sysTotal = int.tryParse((pagination['systemTotal'] ?? 0).toString()) ?? 0;
        int deptTotal = int.tryParse((pagination['departmentTotal'] ?? 0).toString()) ?? 0;
        int sysUnread = int.tryParse((pagination['systemUnread'] ?? 0).toString()) ?? 0;
        int deptUnread = int.tryParse((pagination['departmentUnread'] ?? 0).toString()) ?? 0;
        setState(() {
          _isInitialLoading = false;
          if (page == 1) {
            systemList = newSystem;
            departmentList = newDept;
          } else {
            systemList = [...systemList, ...newSystem];
            departmentList = [...departmentList, ...newDept];
          }
          systemPage = page;
          departmentPage = page;
          systemHasMore = systemList.length < sysTotal;
          departmentHasMore = departmentList.length < deptTotal;
          _sysUnread = sysUnread;
          _deptUnread = deptUnread;
        });
      }
    } catch (e) {
      debugPrint('Get notice list error: $e');
    }
  }

  Future<void> _loadMoreSystem() async {
    if (systemLoadingMore || !systemHasMore) return;
    setState(() => systemLoadingMore = true);
    final nextPage = systemPage + 1;
    await _fetchNoticePage(nextPage);
    setState(() => systemLoadingMore = false);
  }

  Future<void> _loadMoreDepartment() async {
    if (departmentLoadingMore || !departmentHasMore) return;
    setState(() => departmentLoadingMore = true);
    final nextPage = departmentPage + 1;
    await _fetchNoticePage(nextPage);
    setState(() => departmentLoadingMore = false);
  }

  void openDetail(Map<String, dynamic> item) {
    // 标记为已读
    if (item['isRead'] != true) {
      markNoticeRead(item['id'], item['type'] ?? '');
    }
    setState(() {
      currentDetail = item;
      showDetailModal = true;
    });
  }

  Future<void> markNoticeRead(String noticeId, String noticeType) async {
    try {
      await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/notice'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "markRead", "studentId": studentId, "id": noticeId}),
      )).body);
      if (!mounted) return;
      // 更新本地状态：标记已读 + 递减未读计数
      setState(() {
        for (var item in systemList) {
          if (item['id'] == noticeId) item['isRead'] = true;
        }
        for (var item in departmentList) {
          if (item['id'] == noticeId) item['isRead'] = true;
        }
        if (noticeType == 'system' && _sysUnread > 0) {
          _sysUnread--;
        } else if (noticeType == 'department' && _deptUnread > 0) {
          _deptUnread--;
        }
      });
    } catch (e) {
      debugPrint('Mark read error: $e');
    }
  }

  void openImagePreview(String url) {
    setState(() {
      previewImageUrl = url;
      showImagePreview = true;
    });
  }

  void openFeedbackModal() {
    if (studentId.isEmpty) {
      ToastUtil.show(context, '请先登录');
      return;
    }
    getMyFeedbackList();
    setState(() {
      activeTab = 'send';
      showFeedbackModal = true;
    });
  }

  Future<void> _pickFeedbackImage() async {
    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      
      // 使用文件路径作为唯一标识
      final String imageId = file.path;
      // 立即添加占位项到列表，显示加载动画
      setState(() {
        feedbackImages.add({'type': 'image', 'url': '', 'id': imageId});
        uploadingImages[imageId] = true;
      });
      
      final result = await _uploadImageWithRetry(file.path);
      if (result['success'] == true) {
        final url = result['url'];
        setState(() {
          // 找到对应索引，替换为真实url
          final index = feedbackImages.indexWhere((img) => img['id'] == imageId);
          if (index != -1) {
            feedbackImages[index]['url'] = url;
          }
          uploadingImages.remove(imageId);
        });
      } else {
        setState(() {
          // 上传失败，移除占位项
          feedbackImages.removeWhere((img) => img['id'] == imageId);
          uploadingImages.remove(imageId);
        });
        if (mounted) ToastUtil.show(context, '上传失败，请重试');
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.show(context, '上传失败，请重试');
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
        final uri = Uri.parse('$baseUrl/api/notice');
        final request = http.MultipartRequest('POST', uri)
          ..fields['action'] = 'upload'
          ..fields['type'] = 'image';
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
        final response = await request.send();
        final body = await response.stream.bytesToString();
        final data = jsonDecode(body);
        if (data['success'] == true) {
          return {'success': true, 'url': '$baseUrl${data['url']}'};
        }
        lastResult = {'success': false, 'message': data['message'] ?? '上传失败'};
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

  Future<void> submitFeedback() async {
    if (feedbackContent.trim().isEmpty && feedbackImages.isEmpty) {
      ToastUtil.show(context, '请输入反馈内容或添加图片');
      return;
    }
    
    debugPrint('📤 [提交反馈] studentId: "$studentId", studentRemark: "$studentRemark"');
    if (studentId.isEmpty) {
      ToastUtil.show(context, '用户信息未加载，请重试');
      return;
    }
    
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/notice'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "send",
        "type": "feedback",
        "content": feedbackContent,
        "studentId": studentId,
        "studentRemark": studentRemark,
        "status": "unhandled",
        "mediaList": feedbackImages
      }),
      )).body);
      
      if (data['success'] == true) {
        if (mounted) ToastUtil.show(context, '提交成功');
        setState(() {
          feedbackContent = '';
          feedbackImages = [];
          activeTab = 'record';
        });
        await Future.delayed(Duration(milliseconds: 500));
        await getMyFeedbackList();
      } else {
        if (mounted) ToastUtil.show(context, data['message'] ?? '提交失败');
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, '网络错误，请稍后重试');
    }
  }

  Future<void> getMyFeedbackList() async {
    try {
      debugPrint('📥 [我的记录] 开始加载反馈列表, studentId: $studentId');

      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/notice'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "getFeedback", "studentId": studentId}),
      )).body);
      debugPrint('📥 [我的记录] 响应数据: success=${data['success']}, data数量=${(data['data'] ?? []).length}');
      
      if (data['success'] == true) {
        setState(() {
          myFeedbackList = data['data'] ?? [];
        });
        debugPrint('✅ [我的记录] 加载成功，共 ${myFeedbackList.length} 条记录');
      } else {
        debugPrint('❌ [我的记录] 加载失败: ${data['message']}');
      }
    } catch (e) {
      debugPrint('❌ [我的记录] 加载异常: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !showFeedbackModal && !showDetailModal && !showImagePreview,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() {
            if (showImagePreview) {
              showImagePreview = false;
            } else if (showFeedbackModal) {
              showFeedbackModal = false;
            } else if (showDetailModal) {
              showDetailModal = false;
            }
          });
        }
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: getNoticeList,
        child: Stack(
          children: [
            Positioned(
              top: 15,
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 56,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "通知中心",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color.fromARGB(255, 255, 255, 255),
                          ),
                        ),
                        // 反馈按钮（带文字）
                        GestureDetector(
                          onTap: openFeedbackModal,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  "反馈",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.feedback_outlined,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 系统通知和学习通知布局（合并为一张整体卡片）
                    Expanded(
                      child: _buildNoticeCard(systemList, departmentList,
                          systemScrollController, departmentScrollController,
                          systemLoadingMore, departmentLoadingMore,
                          !systemHasMore, !departmentHasMore,
                          _loadMoreSystem, _loadMoreDepartment,
                          _isInitialLoading),
                    ),
                  ],
                ),
              ),
            ),

            if (showDetailModal) _buildDetailModal(),
            if (showImagePreview) _buildImagePreview(),
            if (showFeedbackModal) _buildFeedbackModal(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildNoticeCard(List systemList, List departmentList,
      ScrollController systemController, ScrollController deptController,
      bool systemLoadingMore, bool deptLoadingMore,
      bool systemNoMore, bool deptNoMore,
      VoidCallback loadMoreSystem, VoidCallback loadMoreDept,
      bool isInitialLoading) {
    if (isInitialLoading && systemList.isEmpty && departmentList.isEmpty) {
      return const NoticeCardShimmer();
    }
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
        children: [
          // 系统通知区域
          Expanded(
            flex: 1,
            child: _buildNoticeSection(
              "系统通知", _sysUnread, systemList, systemController,
              systemLoadingMore, systemNoMore, loadMoreSystem,
            ),
          ),
          const Divider(height: 1, color: Colors.black12),
          // 学习通知区域
          Expanded(
            flex: 1,
            child: _buildNoticeSection(
              "学习通知", _deptUnread, departmentList, deptController,
              deptLoadingMore, deptNoMore, loadMoreDept,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeSection(String title, int unreadCount, List list,
      ScrollController scrollController, bool loadingMore, bool noMore,
      VoidCallback onLoadMore) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            if (unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        const Divider(height: 1, color: Colors.black12),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? ListView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 60, child: Center(child: Text("暂无数据", style: TextStyle(fontSize: 13, color: Colors.grey)))),
                  ],
                )
              : ListView.builder(
                  controller: scrollController,
                  // 始终可滚动：内容不足一屏也能 overscroll，让 RefreshIndicator 能接到拖拽手势
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: list.length + (loadingMore ? 1 : (noMore && list.isNotEmpty ? 1 : 0)),
                  itemBuilder: (context, index) {
                    if (index == list.length) {
                      if (loadingMore) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                        );
                      }
                      if (noMore && list.isNotEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: Text("暂无更多", style: TextStyle(fontSize: 13, color: Colors.grey))),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                    return _buildNoticeItem(list[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNoticeItem(Map<String, dynamic> item) {
    bool isUnread = item['isRead'] != true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // 未读红点
          if (isUnread)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            )
          else
            const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cutText(item['content']), style: const TextStyle(fontSize: 14, color: Colors.black87)),
                const SizedBox(height: 6),
                Text(formatTime(item['createTime']), style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => openDetail(item),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2B7DFF)),
            child: const Text("查看详情", style: TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailModal() {
    return Stack(
      children: [
        ModalBarrier(color: Colors.black54, dismissible: true),
        Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("通知详情", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      onPressed: () => setState(() => showDetailModal = false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(),
                SizedBox(
                  height: 320,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: HtmlWidget(
                      renderContent(currentDetail['content'] ?? ''),
                      customWidgetBuilder: (element) {
                        if (element.localName == 'img') {
                          final src = element.attributes['src'];
                          if (src != null) {
                            return GestureDetector(
                              onTap: () => openImagePreview(src),
                              child: Image.network(
                                src,
                                loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: double.infinity,
                                    height: 200,
                                    color: Colors.grey[200],
                                    child: Center(
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
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
                                  width: double.infinity,
                                  height: 200,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                                ),
                              ),
                            );
                          }
                        }
                        if (element.localName == 'div' && element.attributes['class'] == 'video-container') {
                          final videoUrl = element.attributes['data-src'];
                          if (videoUrl != null) {
                            return _buildVideoPlayer(videoUrl);
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(formatTime(currentDetail['createTime'])),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        ModalBarrier(color: Colors.black, dismissible: true),
        Center(
          child: PhotoView(
            imageProvider: NetworkImage(previewImageUrl),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackModal() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        return Stack(
          children: [
            ModalBarrier(color: Colors.black54, dismissible: true, onDismiss: () => setState(() => showFeedbackModal = false)),
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.65,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tab 栏
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey[200]!, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => activeTab = "send"),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: activeTab == "send" ? const Color(0xFF2B7DFF) : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Text("发送反馈", style: TextStyle(
                                  color: activeTab == "send" ? const Color(0xFF2B7DFF) : Colors.grey[600],
                                  fontWeight: activeTab == "send" ? FontWeight.w600 : FontWeight.normal,
                                  fontSize: 15,
                                )),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                getMyFeedbackList();
                                setModalState(() => activeTab = "record");
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: activeTab == "record" ? const Color(0xFF2B7DFF) : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Text("我的记录", style: TextStyle(
                                  color: activeTab == "record" ? const Color(0xFF2B7DFF) : Colors.grey[600],
                                  fontWeight: activeTab == "record" ? FontWeight.w600 : FontWeight.normal,
                                  fontSize: 15,
                                )),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 发送反馈 Tab
                    if (activeTab == "send")
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Column(
                            children: [
                              // 上方：文字输入区域（内容超出自动滚动）
                              Expanded(
                                child: SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: TextField(
                                    onChanged: (v) => feedbackContent = v,
                                    autofocus: false,
                                    maxLines: null,
                                    minLines: 10,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    decoration: InputDecoration(
                                      hintText: "请输入反馈内容",
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
                                      children: List.generate(feedbackImages.length, (i) {
                                      final img = feedbackImages[i];
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
                                                  final imgUrl = feedbackImages[i]['url'] ?? '';
                                                  // 先从本地移除
                                                  setModalState(() => feedbackImages.removeAt(i));
                                                  // 同步删除后端文件
                                                  if (imgUrl.isNotEmpty) {
                                                    try {
                                                      await http.post(
                                                        Uri.parse('$baseUrl/api/notice'),
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
                              // 底部按钮行（固定位置）：左侧加图按钮，右侧取消+提交
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _pickFeedbackImage(),
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
                                      // 取消时删除已上传的图片
                                      for (final img in List.from(feedbackImages)) {
                                        final url = img['url'] ?? '';
                                        if (url.isNotEmpty) {
                                          try {
                                            await http.post(
                                              Uri.parse('$baseUrl/api/notice'),
                                              headers: {"Content-Type": "application/json"},
                                              body: jsonEncode({"action": "deleteMediaFile", "url": url}),
                                            );
                                          } catch (_) {}
                                        }
                                      }
                                      if (mounted) {
                                        setState(() {
                                          showFeedbackModal = false;
                                          feedbackContent = '';
                                          feedbackImages = [];
                                          uploadingImages.clear();
                                        });
                                      }
                                    },
                                    child: Text("取消", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: submitFeedback,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2B7DFF),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    child: const Text("提交", style: TextStyle(fontSize: 14, color: Colors.white)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    // 我的记录 Tab
                    if (activeTab == "record")
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: myFeedbackList.isEmpty
                                  ? const Center(child: Text("暂无记录", style: TextStyle(fontSize: 13, color: Colors.grey)))
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      itemCount: myFeedbackList.length,
                                      itemBuilder: (_, i) {
                                        var item = myFeedbackList[i];
                                        final isHandled = item['status'] == 'handled' || item['status'] == '已处理';
                                        final statusText = isHandled ? '已处理' : '待处理';
                                        final statusColor = isHandled ? Colors.green : Colors.orange;
                                        final content = item['content'] ?? '';
                                        final displayContent = content.length > 5 ? '${content.substring(0, 5)}...' : content;

                                        return GestureDetector(
                                          onTap: () => _showFeedbackDetailDialog(item),
                                          child: Container(
                                            margin: const EdgeInsets.only(bottom: 10),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[50],
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.grey[200]!),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                            decoration: BoxDecoration(
                                                              color: statusColor.withValues(alpha: 0.1),
                                                              borderRadius: BorderRadius.circular(10),
                                                            ),
                                                            child: Text(
                                                              statusText,
                                                              style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w500),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            formatTime(item['createTime']),
                                                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        displayContent,
                                                        style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            // ✅ 右下角关闭按钮
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: GestureDetector(
                                  onTap: () => setState(() => showFeedbackModal = false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Text(
                                      "关闭",
                                      style: TextStyle(fontSize: 13, color: Colors.black54),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVideoPlayer(String videoUrl) {
    return CommonVideoPlayer(
      videoUrl: videoUrl,
      // 🔥 统一按在线视频处理：原始直链直接播放，B站网页地址播放时解析，
      //    与"不预解析、播放时解析"策略保持一致
      videoType: 2,
      autoPlay: false,
      onVideoClosed: () {},
    );
  }


  // 反馈详情弹窗
  void _showFeedbackDetailDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (_) => _FeedbackDetailDialog(
        item: item,
        timeLabel: formatTime(item['createTime']),
      ),
    );
  }
}

/// 反馈详情弹窗（有状态 widget，管理各分区的滚动提示）
class _FeedbackDetailDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final String timeLabel;
  const _FeedbackDetailDialog({required this.item, required this.timeLabel});

  @override
  State<_FeedbackDetailDialog> createState() => _FeedbackDetailDialogState();
}

class _FeedbackDetailDialogState extends State<_FeedbackDetailDialog> {
  Map<String, dynamic> get item => widget.item;

  @override
  Widget build(BuildContext context) {
    final bool isHandled = item['status'] == 'handled' || item['status'] == '已处理';
    final String statusText = isHandled ? '已处理' : '待处理';
    final Color statusColor = isHandled ? Colors.green : Colors.orange;
    final List<dynamic> mediaList = item['mediaList'] ?? [];
    final String replyContent = item['replyContent'] ?? '';
    final List<dynamic> replyMediaList = item['replyMediaList'] ?? [];

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width * 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.72,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("反馈详情", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 状态和时间
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.timeLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 内容区域
            if (isHandled && replyContent.isNotEmpty) ...[
              // 已处理且有回复：上下两个独立可滚动的分区卡片
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 上区：用户反馈
                    Expanded(
                      child: _FeedbackSectionCard(
                        title: "用户反馈",
                        dotColor: Colors.grey,
                        bgColor: const Color(0xFFF5F7FA),
                        textColor: const Color(0xFF2B7DFF),
                        content: item['content'] ?? '',
                        mediaList: mediaList,
                        margin: const EdgeInsets.only(bottom: 10),
                      ),
                    ),
                    // 下区：管理员回复
                    Expanded(
                      child: _FeedbackSectionCard(
                        title: "管理员回复",
                        dotColor: const Color(0xFF2B7DFF),
                        bgColor: const Color(0xFFEAF3FF),
                        textColor: const Color(0xFF2B7DFF),
                        content: replyContent,
                        mediaList: replyMediaList,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // 未处理或无回复：单区域
              Expanded(
                child: _FeedbackSectionCard(
                  title: "反馈内容",
                  dotColor: Colors.grey,
                  bgColor: const Color(0xFFF5F7FA),
                  textColor: Colors.grey,
                  content: item['content'] ?? '',
                  mediaList: mediaList,
                  margin: const EdgeInsets.only(bottom: 4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单个反馈分区卡片：标题固定，内容可滚动，底部智能提示"下滑更多"
class _FeedbackSectionCard extends StatefulWidget {
  final String title;
  final Color dotColor;
  final Color bgColor;
  final Color textColor;
  final String content;
  final List<dynamic> mediaList;
  final EdgeInsets margin;

  const _FeedbackSectionCard({
    required this.title,
    required this.dotColor,
    required this.bgColor,
    required this.textColor,
    required this.content,
    required this.mediaList,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<_FeedbackSectionCard> createState() => _FeedbackSectionCardState();
}

class _FeedbackSectionCardState extends State<_FeedbackSectionCard>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollCtrl = ScrollController();
  late final AnimationController _bounceCtrl;
  late final Animation<Offset> _bounceAnim;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _bounceAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 0.35),
    ).animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首帧后判断内容是否溢出，决定是否需要显示下滑提示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      setState(() {
        _showHint = _scrollCtrl.position.maxScrollExtent > 4;
      });
    });
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    // 已滚到接近底部时隐藏提示
    final nearBottom = _scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 8;
    if (nearBottom && _showHint) {
      setState(() => _showHint = false);
    } else if (!nearBottom && !_showHint && _scrollCtrl.position.maxScrollExtent > 4) {
      setState(() => _showHint = true);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: widget.margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 固定标题行
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: widget.textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 可滚动内容区
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      widget.content,
                      style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.black87),
                    ),
                  ),
                  if (widget.mediaList.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: widget.mediaList.map<Widget>((m) {
                        final url = m['url'] ?? m;
                        final imgUrl = url is String ? url : url.toString();
                        return _buildSectionNetworkImage(imgUrl);
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 下滑更多提示（仅在内容溢出时显示）
          if (_showHint)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "下滑更多",
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.textColor.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedBuilder(
                    animation: _bounceAnim,
                    builder: (_, child) => Transform.translate(offset: _bounceAnim.value, child: child),
                    child: Icon(
                      Icons.arrow_downward,
                      size: 14,
                      color: widget.textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 分区内网络图片（复用公共 notice 页面的图片构建逻辑）
Widget _buildSectionNetworkImage(String url) {
  return Image.network(
    url,
    width: 120,
    height: 120,
    fit: BoxFit.cover,
    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
      if (wasSynchronouslyLoaded || frame != null) return child;
      return const SizedBox(
        width: 120,
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    },
    errorBuilder: (context, error, stackTrace) => const SizedBox(
      width: 120,
      height: 120,
      child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
    ),
  );
}

