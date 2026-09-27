import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:zdxtapp/config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/utils/toast.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  final String baseUrl = Config.baseUrl;
  String? clientVersion;

  String latestVersion = "";
  String downloadUrl = "";
  String updateInfo = "";
  bool hasNewVersion = false;
  bool isLoading = true;

  bool isDownloading = false;
  bool isDownloaded = false;
  double progress = 0;
  String? downloadedFilePath;

  // 滚动标识
  bool _updateHasMore = false;
  final ScrollController _updateScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _updateScrollCtrl.addListener(_onUpdateScroll);
    checkUpdateNow();
  }

  void _onUpdateScroll() {
    if (!_updateScrollCtrl.hasClients) return;
    final max = _updateScrollCtrl.position.maxScrollExtent;
    final cur = _updateScrollCtrl.position.pixels;
    final hasMore = max - cur > 12;
    if (hasMore != _updateHasMore) {
      setState(() => _updateHasMore = hasMore);
    }
  }

  void _syncUpdateHasMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_updateScrollCtrl.hasClients) return;
      final max = _updateScrollCtrl.position.maxScrollExtent;
      final cur = _updateScrollCtrl.position.pixels;
      final hasMore = max - cur > 12;
      if (hasMore != _updateHasMore) {
        setState(() => _updateHasMore = hasMore);
      }
    });
  }

  @override
  void dispose() {
    _updateScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> checkUpdateNow() async {
    setState(() => isLoading = true);
    PackageInfo pkg = await PackageInfo.fromPlatform();
    clientVersion = pkg.version;
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/version'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "get"}),
      )).body);
      if (data["success"] == true) {
        final d = data["data"];
        setState(() {
          latestVersion = d["version"] ?? "";
          downloadUrl = d["url"] ?? "";
          updateInfo = d["updateInfo"] ?? "";
          hasNewVersion = compareVersion(clientVersion ?? "0.0.0", latestVersion) < 0;
          isLoading = false;
          _syncUpdateHasMore();
        });
      } else {
        setState(() { hasNewVersion = false; isLoading = false; });
      }
    } catch (e) {
      setState(() { hasNewVersion = false; isLoading = false; });
    }
  }

  int compareVersion(String v1, String v2) {
    List<int> a = v1.split(".").map((s) => int.tryParse(s) ?? 0).toList();
    List<int> b = v2.split(".").map((s) => int.tryParse(s) ?? 0).toList();
    int len = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      int n1 = i < a.length ? a[i] : 0;
      int n2 = i < b.length ? b[i] : 0;
      if (n1 > n2) return 1;
      if (n1 < n2) return -1;
    }
    return 0;
  }

  void handleAction() async {
    if (isDownloading) return;
    if (isDownloaded && downloadedFilePath != null) {
      await installApk(downloadedFilePath!);
    } else {
      await startDownload();
    }
  }

  Future<void> startDownload() async {
    if (downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('下载地址无效')));
      return;
    }
    setState(() { isDownloading = true; progress = 0; isDownloaded = false; downloadedFilePath = null; });
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/app_update_${DateTime.now().millisecondsSinceEpoch}.apk';
      final Dio dio = Dio();
      await dio.download(
        downloadUrl, filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() => progress = (received / total * 100).clamp(0.0, 100.0));
          }
        },
        options: Options(responseType: ResponseType.bytes, followRedirects: false, receiveTimeout: const Duration(minutes: 5)),
      );
      setState(() { isDownloading = false; isDownloaded = true; progress = 100; downloadedFilePath = filePath; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('下载完成，点击"立即安装"进行安装')));
      }
    } catch (e) {
      setState(() { isDownloading = false; progress = 0; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e')));
    }
  }

  Future<void> installApk(String filePath) async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        if (androidInfo.version.sdkInt >= 26) {
          bool hasPermission = await _checkInstallPermission();
          if (!hasPermission) {
            await showInstallPermissionDialog();
            return;
          }
        }
      }
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('安装失败: ${result.message}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('安装异常: $e')));
    }
  }

  Future<bool> _checkInstallPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.requestInstallPackages.status;
      return status == PermissionStatus.granted;
    } catch (e) { return false; }
  }

  Future<void> showInstallPermissionDialog() async {
    if (!mounted) return;
    final shouldShow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要安装权限'),
        content: const Text('为了安装新版本应用，需要允许从未知来源安装应用。请在下一页中开启"允许来自此来源的应用"权限。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          ElevatedButton(onPressed: () async { Navigator.of(ctx).pop(true); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('去开启', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (shouldShow == true) {
      final result = await Permission.requestInstallPackages.request();
      if (result == PermissionStatus.granted && downloadedFilePath != null) {
        await installApk(downloadedFilePath!);
      } else if (result == PermissionStatus.denied && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请在设置中手动开启安装权限')));
      }
    }
  }

  void _openBetaDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _BetaFullDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff0f172a), Color(0xff1e293b), Color(0xff334155)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ===== 顶部导航栏 =====
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text('检查更新',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // 内测入口：图文并存
                    ElevatedButton.icon(
                      onPressed: _openBetaDialog,
                      icon: const Icon(Icons.science, size: 16, color: Colors.black),
                      label: const Text('内测', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ===== 主内容区 =====
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // 更新卡片
                      _buildUpdateCard(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateCard() {
    return Container(
      margin: const EdgeInsets.only(top: 0, bottom: 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: isLoading
          ? const Column(
              children: [
                SizedBox(width: 50, height: 50, child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white), strokeWidth: 4)),
                SizedBox(height: 16),
                Text("正在检查更新...", style: TextStyle(fontSize: 14, color: Colors.white70)),
              ],
            )
          : Column(
              children: [
                // 版本标题
                if (hasNewVersion)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.system_update, color: Colors.greenAccent, size: 28),
                      SizedBox(width: 8),
                      Text("发现新版本", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  )
                else
                  Column(
                    children: [
                      const Text("暂无更新，请静待更新通知", style: TextStyle(fontSize: 15, color: Colors.white70)),
                      const SizedBox(height: 8),
                      Text("当前版本：$clientVersion", style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                const SizedBox(height: 16),
                // 版本信息
                if (hasNewVersion)
                  Column(
                    children: [
                      _versionRow("当前版本", clientVersion ?? ""),
                      _versionRow("最新版本", latestVersion),
                      const SizedBox(height: 12),
                    ],
                  ),
                // 更新内容
                if (hasNewVersion && updateInfo.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("更新内容", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 300,
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              SingleChildScrollView(
                                controller: _updateScrollCtrl,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4, bottom: 36),
                                  child: Text(updateInfo, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                ),
                              ),
                              if (_updateHasMore)
                                Positioned(
                                  left: 0, right: 0, bottom: 0, height: 36,
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                        colors: [Colors.transparent, Color(0x99111827)],
                                      ),
                                    ),
                                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white54),
                                      const SizedBox(width: 4),
                                      const Text("下滑查看更多", style: TextStyle(fontSize: 10, color: Colors.white54)),
                                    ]),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                // 下载按钮
                if (hasNewVersion)
                  ElevatedButton(
                    onPressed: isDownloading ? null : handleAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDownloading ? Colors.grey : (isDownloaded ? Colors.green : Colors.blue),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 36),
                    ),
                    child: Text(
                      isDownloading ? "正在下载..." : (isDownloaded ? "立即安装" : "立即下载更新"),
                      style: const TextStyle(fontSize: 15, color: Colors.white),
                    ),
                  ),
                // 进度条
                if (isDownloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: progress / 100, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.blue)),
                  Text("${progress.toInt()}%", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                // 手动刷新
                if (!hasNewVersion)
                  TextButton(
                    onPressed: checkUpdateNow,
                    child: const Text("检查更新", style: TextStyle(color: Colors.white54)),
                  ),
              ],
            ),
    );
  }

  Widget _versionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const Text("：", style: TextStyle(color: Colors.white54, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }
}

// ========== 内测数据模型 ==========
class BetaVersionInfo {
  final String version;
  final String url;
  final String updateInfo;
  final String startTimeStr;
  final String endTimeStr;
  final int startTs;
  final int endTs;
  final bool pushEnabled;
  final String timeStatus;
  BetaVersionInfo({
    required this.version,
    required this.url,
    required this.updateInfo,
    required this.startTimeStr,
    required this.endTimeStr,
    required this.startTs,
    required this.endTs,
    required this.pushEnabled,
    required this.timeStatus,
  });
  factory BetaVersionInfo.fromJson(Map<String, dynamic> d) => BetaVersionInfo(
    version: d['version'] ?? '',
    url: d['url'] ?? '',
    updateInfo: d['updateInfo'] ?? '',
    startTimeStr: d['startTimeStr'] ?? '',
    endTimeStr: d['endTimeStr'] ?? '',
    startTs: d['startTs'] as int? ?? 0,
    endTs: d['endTs'] as int? ?? 0,
    pushEnabled: d['pushEnabled'] == true,
    timeStatus: d['timeStatus'] ?? 'noBeta',
  );
}

// ========== 全屏内测弹窗 ==========
class _BetaFullDialog extends StatefulWidget {
  const _BetaFullDialog();
  @override
  State<_BetaFullDialog> createState() => _BetaFullDialogState();
}

class _BetaFullDialogState extends State<_BetaFullDialog> {
  final String baseUrl = Config.baseUrl;
  bool _loading = true;
  BetaVersionInfo? _betaData;
  bool _signedUp = false;
  String _timeStatus = 'noBeta';
  bool _downloadingBeta = false;
  double _betaProgress = 0;
  bool _signingUp = false;

  // 滚动标识（内测更新内容区）
  bool _updateHasMore = false;
  final ScrollController _updateScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _updateScrollCtrl.addListener(_onUpdateScroll);
    _loadBetaStatus();
  }

  void _onUpdateScroll() {
    if (!_updateScrollCtrl.hasClients) return;
    final max = _updateScrollCtrl.position.maxScrollExtent;
    final cur = _updateScrollCtrl.position.pixels;
    final hasMore = max - cur > 12;
    if (hasMore != _updateHasMore) {
      setState(() => _updateHasMore = hasMore);
    }
  }

  void _syncUpdateHasMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_updateScrollCtrl.hasClients) return;
      final max = _updateScrollCtrl.position.maxScrollExtent;
      final cur = _updateScrollCtrl.position.pixels;
      final hasMore = max - cur > 12;
      if (hasMore != _updateHasMore) {
        setState(() => _updateHasMore = hasMore);
      }
    });
  }

  @override
  void dispose() {
    _updateScrollCtrl.dispose();
    super.dispose();
  }

  Future<String?> _getUserAccount() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final info = sp.getString('userInfo');
      if (info != null) {
        final map = jsonDecode(info);
        return map['account'] as String?;
      }
    } catch (e) {
      debugPrint('⚠️ 读取用户账号失败: $e');
    }
    return null;
  }

  Future<void> _loadBetaStatus() async {
    setState(() => _loading = true);
    final account = await _getUserAccount();
    if (account == null) {
      if (mounted) {
        showDialog(context: context, builder: (_) => const _LoginRequiredDialog());
      }
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/version'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "getBetaStatus", "account": account}),
      )).body);
      if (mounted) {
        if (data['success'] == true && data['data'] != null) {
          final d = data['data'];
          setState(() {
            _betaData = d['hasBeta'] == true ? BetaVersionInfo.fromJson(d) : null;
            _signedUp = d['signedUp'] ?? false;
            _timeStatus = d['timeStatus'] ?? 'noBeta';
            _loading = false;
          });
          _syncUpdateHasMore();
        } else {
          setState(() { _betaData = null; _timeStatus = 'noBeta'; _loading = false; });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signup() async {
    if (_signingUp) return;
    final account = await _getUserAccount();
    if (account == null) {
      if (mounted) ToastUtil.show(context, '请先登录');
      return;
    }
    setState(() => _signingUp = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/version'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "signupBeta", "account": account}),
      )).body);
      if (mounted) {
        if (data['success'] == true) {
          ToastUtil.show(context, '报名成功！请等待开始时间');
          await _loadBetaStatus();
        } else {
          ToastUtil.show(context, data['message'] ?? '报名失败');
        }
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, '报名失败，请重试');
    }
    if (mounted) setState(() => _signingUp = false);
  }

  Future<void> _downloadBeta() async {
    final account = await _getUserAccount();
    if (account == null) return;
    setState(() { _downloadingBeta = true; _betaProgress = 0; });
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/version'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "downloadBeta", "account": account}),
      )).body);
      if (!mounted) return;
      if (data['success'] == true && data['data'] != null) {
        final url = data['data']['url'];
        if (url != null) {
          await _doBetaDownload(url);
          if (mounted) setState(() { _downloadingBeta = false; });
        }
      } else {
        setState(() { _downloadingBeta = false; });
        if (mounted) {
          if (data['message'] == '内测已结束') {
            showDialog(context: context, builder: (_) => AlertDialog(
              title: const Text('内测已结束'),
              content: const Text('已超过内测时间，请下次再来'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
            ));
          } else {
            ToastUtil.show(context, data['message'] ?? '获取下载链接失败');
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() { _downloadingBeta = false; });
      if (mounted) ToastUtil.show(context, '下载失败，请重试');
    }
  }

  Future<void> _doBetaDownload(String url) async {
    final currentContext = context;
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/beta_update_${DateTime.now().millisecondsSinceEpoch}.apk';
      final Dio dio = Dio();
      await dio.download(url, filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            if (mounted) setState(() => _betaProgress = (received / total * 100).clamp(0.0, 100.0));
          }
        },
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 5)),
      );
      if (mounted) await _installApk(filePath);
    } catch (e) {
      if (mounted && currentContext.mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(SnackBar(content: Text('下载失败: $e')));
      }
    }
  }

  Future<void> _installApk(String filePath) async {
    final currentContext = context;
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.version.sdkInt >= 26) {
        final status = await Permission.requestInstallPackages.status;
        if (status != PermissionStatus.granted) {
          if (!mounted || !currentContext.mounted) return;
          final should = await showDialog<bool>(context: currentContext, builder: (_) => AlertDialog(
            title: const Text('需要安装权限'),
            content: const Text('为了安装应用，需要允许从未知来源安装。请在下一页开启权限。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(currentContext, false), child: const Text('取消')),
              ElevatedButton(onPressed: () => Navigator.pop(currentContext, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('去开启', style: TextStyle(color: Colors.white))),
            ],
          ));
          if (should == true) {
            final r = await Permission.requestInstallPackages.request();
            if (r == PermissionStatus.granted) await _installApk(filePath);
          }
          return;
        }
      }
    }
    final result = await OpenFile.open(filePath);
    if (!mounted || !currentContext.mounted) return;
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(currentContext).showSnackBar(SnackBar(content: Text('安装失败: ${result.message}')));
    }
  }

  // ---------- 视觉常量 ----------
  static const Color _bgTop = Color(0xFF1a2744);
  static const Color _bgBottom = Color(0xFF0f172a);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            _buildTitleBar(),
            Flexible(
              fit: FlexFit.loose,
              child: _buildContentArea(),
            ),
            _buildBottomActionArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.science, color: Colors.orangeAccent, size: 24),
          const SizedBox(width: 10),
          const Text('内测推送',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// 内容区：
  /// - 推送关闭 → 显示"暂无内测，请等待通知"卡片
  /// - 推送开启 → 无论是否报名，都展示版本信息卡片
  Widget _buildContentArea() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: CircularProgressIndicator(color: Colors.orangeAccent),
        ),
      );
    }
    // 推送关闭 / 无内测数据：显示等待通知卡片
    if (_betaData == null || !_betaData!.pushEnabled) {
      return _buildWaitingCard();
    }
    // 推送开启：展示内测信息卡片
    return _buildBetaContentCard();
  }

  /// 推送关闭 / 无内测数据时的等待卡片
  Widget _buildWaitingCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_off, size: 56, color: Colors.white24),
              const SizedBox(height: 16),
              const Text('暂无内测，请等待通知',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  /// 推送开启时的内测信息卡片（无论是否报名都展示）
  Widget _buildBetaContentCard() {
    final v = _betaData!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 版本号标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.label, size: 14, color: Colors.orangeAccent),
                const SizedBox(width: 6),
                Text('v${v.version}',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 时间范围卡片
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time, size: 18, color: Colors.white54),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('内测时间',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('${v.startTimeStr} ~ ${v.endTimeStr}',
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 更新内容卡片（与正式更新主界面样式对齐）
          if (v.updateInfo.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('更新内容',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 250,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        SingleChildScrollView(
                          controller: _updateScrollCtrl,
                          padding: const EdgeInsets.only(right: 4, bottom: 36),
                          child: Text(v.updateInfo,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            )),
                        ),
                        if (_updateHasMore)
                          Positioned(
                            left: 0, right: 0, bottom: 0, height: 36,
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, _bgBottom],
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white54),
                                  const SizedBox(width: 4),
                                  const Text('下滑查看更多',
                                    style: TextStyle(fontSize: 10, color: Colors.white54)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 底部操作区：
  /// - 推送关闭 / 无内测数据 → 禁用按钮"暂无内测，请等待通知"
  /// - 推送开启 + 未报名 → 禁用按钮"暂无内测资格"
  /// - 推送开启 + 已报名 + active → 下载按钮或进度条
  /// - 推送开启 + 已报名 + notStarted → 禁用"请等待内测开始"
  /// - 推送开启 + 已报名 + ended → 禁用"内测已结束"
  Widget _buildBottomActionArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPrimaryAction(),
          const SizedBox(height: 12),
          _buildRefreshRow(),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction() {
    // 加载中
    if (_loading) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              color: Colors.orangeAccent,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    // 推送关闭 / 无内测数据
    if (_betaData == null || !_betaData!.pushEnabled) {
      return _fullWidthBtn('暂无内测，请等待通知',
        Colors.white.withValues(alpha: 0.15), null,
        textColor: Colors.white54);
    }

    // 推送开启 + 未报名：按时间状态区分
    if (!_signedUp) {
      switch (_timeStatus) {
        case 'notStarted':
          // 内测开始前：展示报名按钮，可点击报名
          if (_signingUp) {
            return SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          }
          return _fullWidthBtn('报名', Colors.orangeAccent, _signup);
        case 'active':
        case 'ended':
          // 内测进行中 / 结束：显示"暂无内测资格"，无报名/下载按钮
          return _fullWidthBtn('暂无内测资格',
            Colors.white.withValues(alpha: 0.15), null,
            textColor: Colors.white54);
        default:
          return _fullWidthBtn('暂无内测资格',
            Colors.white.withValues(alpha: 0.15), null,
            textColor: Colors.white54);
      }
    }

    // 推送开启 + 已报名：按时间状态显示不同按钮
    switch (_timeStatus) {
      case 'active':
        if (_downloadingBeta) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: _betaProgress / 100,
                backgroundColor: Colors.white24,
                valueColor:
                    const AlwaysStoppedAnimation(Colors.orangeAccent),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${_betaProgress.toInt()}%',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    )),
                  Text('正在下载内测包...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    )),
                ],
              ),
            ],
          );
        }
        return _fullWidthBtn('下载内测包', Colors.blue, _downloadBeta);
      case 'notStarted':
        return _fullWidthBtn('您已报名，请等待内测开始',
          Colors.white.withValues(alpha: 0.15), null,
          textColor: Colors.orangeAccent);
      case 'ended':
        return _fullWidthBtn('内测已结束，无法下载',
          Colors.white.withValues(alpha: 0.15), null,
          textColor: Colors.white54);
      default:
        return _fullWidthBtn('内测已结束，无法下载',
          Colors.white.withValues(alpha: 0.15), null,
          textColor: Colors.white54);
    }
  }

  Widget _buildRefreshRow() {
    return Row(
      children: [
        const Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('状态可能已变化？',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
        ),
        TextButton(
          onPressed: _loading ? null : _loadBetaStatus,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 14),
              SizedBox(width: 4),
              Text('刷新', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fullWidthBtn(String label, Color color, VoidCallback? onTap,
      {Color? textColor, Color? bgOverride}) {
    final Color bgColor = bgOverride ?? color;
    final Color fgColor = textColor ?? Colors.white;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
          disabledForegroundColor: Colors.white38,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

// 未登录提示弹窗
class _LoginRequiredDialog extends StatelessWidget {
  const _LoginRequiredDialog();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1e293b),
      title: const Text('请先登录', style: TextStyle(color: Colors.white)),
      content: const Text('登录后可参与内测推送活动', style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定', style: TextStyle(color: Colors.orangeAccent))),
      ],
    );
  }
}
