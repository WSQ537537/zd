import 'dart:async'; // 🔥 异步操作支持（unawaited）
import 'dart:convert'; // 🔥 JSON 编解码
import 'dart:io'; // 🔥 文件操作
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'; // 🔥 使用增强版WebView
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 持久化存储
import 'package:path_provider/path_provider.dart'; // 🔥 路径获取
import 'package:device_info_plus/device_info_plus.dart'; // 🔥 设备信息
// import 'package:media_scanner/media_scanner.dart'; // 🔥 媒体扫描支持（已移除，存在跨盘符编译问题）
// import 'package:open_file/open_file.dart'; // 🔥 打开文件（预留）
// import 'package:url_launcher/url_launcher.dart'; // 🔥 打开目录（已移除，避免 FileUriExposedException）

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with SingleTickerProviderStateMixin {
  // 🔥 MethodChannel：与 Android 原生层通信
  static const _fileChannel = MethodChannel('com.zdxt.app/file_manager');

  late TabController _tabController;
  int _currentTabIndex = 0; // 当前选中的标签索引
  bool _isLoading = false; // 加载状态
  
  // 🔥 下载状态管理
  String? _downloadingFilename; // 当前下载的文件名
  double _downloadProgress = 0.0; // 下载进度（0.0-1.0）
  bool _isDownloading = false; // 是否正在下载
  bool _showDownloadingToastBanner = false; // 是否显示"正在下载"toast
  Timer? _downloadingToastTimer; // "正在下载"toast 自动消失定时器

  // 🔥 中部弹窗提示状态
  String? _toastMessage; // 中部弹窗文本
  Color _toastColor = Colors.transparent; // 中部弹窗背景色
  Timer? _toastTimer; // 中部弹窗自动消失定时器
  
  // 🔥 下载历史记录
  List<Map<String, dynamic>> _downloadHistory = []; // 下载记录列表

  @override
  void initState() {
    super.initState();
    
    // 🔥 设置状态栏样式
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    
    // 🔥 移除自动权限请求，让WebView在处理文件上传时自动触发系统权限请求
    
    // 初始化Tab控制器
    _tabController = TabController(length: 2, vsync: this);
    
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
        
        // 🔥 切换标签时清除所有 SnackBar
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    });
    
    // 🔥 加载下载历史记录
    _loadDownloadHistory();
  }

  // 🔥 从本地存储加载下载历史
  Future<void> _loadDownloadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('download_history');
      
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        setState(() {
          _downloadHistory = decoded.map((item) {
            // 将时间字符串转换回 DateTime 对象
            return <String, dynamic>{
              ...item as Map<String, dynamic>,
              'time': DateTime.parse(item['time'] as String),
            };
          }).toList();
        });
        debugPrint('📚 加载了 ${_downloadHistory.length} 条下载记录');
      }
    } catch (e) {
      debugPrint('⚠️ 加载下载历史失败: $e');
    }
  }

  // 🔥 保存下载历史到本地存储
  Future<void> _saveDownloadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 将 DateTime 转换为字符串以便存储
      final historyToSave = _downloadHistory.map((item) {
        return {
          ...item,
          'time': item['time'].toIso8601String(),
        };
      }).toList();
      
      final historyJson = jsonEncode(historyToSave);
      await prefs.setString('download_history', historyJson);
      debugPrint('💾 已保存 ${_downloadHistory.length} 条下载记录');
    } catch (e) {
      debugPrint('⚠️ 保存下载历史失败: $e');
    }
  }

  @override
  void dispose() {
    // 🔥 清除所有 SnackBar（下载完成提示、错误提示等）
    ScaffoldMessenger.of(context).clearSnackBars();
    _tabController.dispose();
    super.dispose();
  }

  // 🔥 权限检查和引导功能已移至Android原生层处理
  // AndroidManifest.xml中已声明所需权限，WebView会自动处理文件上传时的权限请求
  // 如需Flutter层权限管理，可后续启用permission_handler库

  // 🔥 根据文件扩展名获取 MIME 类型
  String _getMimeType(String fileExtension) {
    final ext = fileExtension.toLowerCase();
    const mimeMap = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'bmp': 'image/bmp',
      'webp': 'image/webp',
      'svg': 'image/svg+xml',
      'mp4': 'video/mp4',
      'avi': 'video/x-msvideo',
      'mov': 'video/quicktime',
      'wmv': 'video/x-ms-wmv',
      'mkv': 'video/x-matroska',
      'flv': 'video/x-flv',
      'webm': 'video/webm',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'flac': 'audio/flac',
      'aac': 'audio/aac',
      'wma': 'audio/x-ms-wma',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'rtf': 'application/rtf',
      'zip': 'application/zip',
      'rar': 'application/x-rar-compressed',
      '7z': 'application/x-7z-compressed',
      'apk': 'application/vnd.android.package-archive',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }

  // 🔥 将下载的文件保存到系统公共目录（通过 MediaStore）
  Future<String?> _saveToSystemGallery(String filePath, String filename, String fileExtension) async {
    try {
      // 检查源文件是否存在且有内容
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        debugPrint('❌ 源文件不存在: $filePath');
        return null;
      }
      final fileSize = await sourceFile.length();
      if (fileSize == 0) {
        debugPrint('❌ 源文件为空，跳过保存到系统目录: $filePath');
        return null;
      }
      
      final mimeType = _getMimeType(fileExtension);
      debugPrint('📡 保存到系统: path=$filePath, name=$filename, size=$fileSize bytes, MIME=$mimeType');
      
      final result = await _fileChannel.invokeMethod<String>('saveToMediaStore', {
        'filePath': filePath,
        'displayName': filename,
        'mimeType': mimeType,
      });
      
      if (result != null && result.isNotEmpty) {
        debugPrint('✅ 已保存到系统公共目录: $result');
        // 保存成功后删除临时文件
        try {
          if (await sourceFile.exists()) {
            await sourceFile.delete();
            debugPrint('🗑️ 已删除临时文件: $filePath');
          }
        } catch (e) {
          debugPrint('⚠️ 删除临时文件失败: $e');
        }
        return result;
      } else {
        debugPrint('⚠️ MediaStore 返回空路径');
        return null;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ PlatformException: code=${e.code}, message=${e.message}, details=${e.details}');
      return null;
    } catch (e, stackTrace) {
      debugPrint('❌ 保存到系统失败: $e');
      debugPrint('StackTrace: $stackTrace');
      return null;
    }
  }

  // 🔥 显示中部弹窗提示（替代底部 SnackBar）
  void _showCenterToast(String message, Color color) {
    if (!mounted) return;
    setState(() {
      _toastMessage = message;
      _toastColor = color;
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _toastMessage = null;
          _toastColor = Colors.transparent;
        });
      }
    });
  }

  // 🔥 中部弹窗视觉组件（在 build 中条件渲染）
  Widget _buildCenterToast() {
    final msg = _toastMessage;
    if (msg == null || _toastColor == Colors.transparent) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: _toastColor.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            msg,
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  // 🔥 获取安全的下载保存路径
  Future<String> _getSafeDownloadPath(String filename, String fileExtension) async {
    Directory? baseDir;
    
    try {
      // Android 10+ (API 29+) 使用应用外部文件目录，避免 Scoped Storage 限制
      baseDir = await getExternalStorageDirectory();
      if (baseDir != null) {
        // 在应用外部目录下创建 Downloads 子目录
        final downloadDir = Directory('${baseDir.path}/Downloads');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return '${downloadDir.path}/$filename';
      }
    } catch (e) {
      debugPrint('⚠️ 获取外部存储目录失败: $e');
    }
    
    // 降级方案：使用应用文档目录
    baseDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${baseDir.path}/Downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return '${downloadDir.path}/$filename';
  }

  // 🔥 请求存储权限（适配不同 Android 版本）
  Future<bool> _requestStoragePermission() async {
    debugPrint('🔍 检查存储权限...');
    
    // 获取 Android 版本
    int sdkInt = 0;
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      sdkInt = androidInfo.version.sdkInt;
      debugPrint('📱 Android SDK 版本: $sdkInt');
    } catch (e) {
      debugPrint('⚠️ 获取设备信息失败: $e');
    }
    
    // 🔥 Android 11+ (API 30+) 需要 MANAGE_EXTERNAL_STORAGE 才能写入公共目录
    if (sdkInt >= 30) {
      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) {
        debugPrint('✅ MANAGE_EXTERNAL_STORAGE 已授予');
        return true;
      } else {
        debugPrint('❌ MANAGE_EXTERNAL_STORAGE 被拒绝，尝试引导用户到设置');
        // 引导用户到设置页面开启权限
        if (mounted) {
          _showManageStorageDialog();
        }
        return false;
      }
    }
    // Android 10 (API 29)
    else if (sdkInt == 29) {
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) {
        debugPrint('✅ 存储权限已授予');
        return true;
      }
    }
    // Android 9 及以下 (API 28-)
    else {
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) {
        debugPrint('✅ 存储权限已授予');
        return true;
      }
    }
    
    debugPrint('❌ 存储权限被拒绝');
    return false;
  }

  // 🔥 显示引导用户开启 MANAGE_EXTERNAL_STORAGE 权限的对话框
  void _showManageStorageDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要文件管理权限'),
        content: const Text(
          'Android 11+ 系统要求应用获得"所有文件访问权限"才能将下载的文件保存到系统相册和文件管理器中。\n\n'
          '请在设置中找到"所有文件访问权限"并开启。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _fileChannel.invokeMethod('requestManageExternalStorage');
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  // 🔥 处理文件下载
  Future<void> _handleDownload(String url, String? suggestedFilename) async {
    if (_isDownloading) {
      _showCenterToast('已有文件正在下载，请稍候', Colors.blue);
      return;
    }

    // 🔥 请求存储权限
    final hasPermission = await _requestStoragePermission();
    if (!hasPermission) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            content: const Text('需要存储权限才能下载文件\n请在设置中手动开启权限'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('去设置'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // 🔥 智能提取文件名并判断文件类型
    String filename;
    String? fileExtension;
    
    try {
      // 🔥 优先使用后端提供的建议文件名（从 Content-Disposition 头获取）
      if (suggestedFilename != null && suggestedFilename.isNotEmpty) {
        filename = suggestedFilename;
        
        // 🔥 URL 解码建议文件名（解决中文乱码问题）
        try {
          if (filename.contains('%')) {
            filename = Uri.decodeComponent(filename);
            debugPrint('🔤 URL 解码后的建议文件名: $filename');
          }
        } catch (e) {
          debugPrint('⚠️ URL 解码失败，使用原始文件名: $e');
        }

        // 从建议文件名中提取扩展名
        if (filename.contains('.')) {
          fileExtension = filename.split('.').last.toLowerCase();
        }
      } else {
        // 从 URL 推断文件名
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments;
        
        if (pathSegments.isNotEmpty) {
          filename = pathSegments.last;
          if (filename.contains('?')) filename = filename.split('?').first;
          if (filename.contains('#')) filename = filename.split('#').first;
          
          try {
            filename = Uri.decodeComponent(filename);
          } catch (e) {
            debugPrint('⚠️ URL 解码失败: $e');
          }
          
          if (filename.contains('.')) {
            fileExtension = filename.split('.').last.toLowerCase();
          }
          
          if (filename.isEmpty || filename.length > 100 || !filename.contains('.')) {
            filename = 'download_${DateTime.now().millisecondsSinceEpoch}';
          }
        } else {
          filename = 'download_${DateTime.now().millisecondsSinceEpoch}';
        }
      }
      
      // 🔥 如果没有扩展名，根据 URL 特征推断文件类型
      if (fileExtension == null || fileExtension.isEmpty) {
        final urlLower = url.toLowerCase();
        
        if (urlLower.contains('.pdf')) {
          fileExtension = 'pdf';
        } else if (urlLower.contains('.doc') || urlLower.contains('word')) {
          fileExtension = 'docx';
        } else if (urlLower.contains('.xls') || urlLower.contains('excel')) {
          fileExtension = 'xlsx';
        } else if (urlLower.contains('.ppt') || urlLower.contains('powerpoint')) {
          fileExtension = 'pptx';
        } else if (urlLower.contains('.zip')) {
          fileExtension = 'zip';
        } else if (urlLower.contains('.rar')) {
          fileExtension = 'rar';
        } else if (urlLower.contains('.7z')) {
          fileExtension = '7z';
        } else if (urlLower.contains('.jpg') || urlLower.contains('.jpeg') || urlLower.contains('/image/')) {
          fileExtension = 'jpg';
        } else if (urlLower.contains('.png')) {
          fileExtension = 'png';
        } else if (urlLower.contains('.gif')) {
          fileExtension = 'gif';
        } else if (urlLower.contains('.mp4') || urlLower.contains('/video/')) {
          fileExtension = 'mp4';
        } else if (urlLower.contains('.mp3') || urlLower.contains('/audio/')) {
          fileExtension = 'mp3';
        } else if (urlLower.contains('.apk')) {
          fileExtension = 'apk';
        } else {
          fileExtension = 'dat';
          debugPrint('⚠️ 无法识别文件类型，使用默认扩展名 .dat');
        }
        
        if (!filename.endsWith('.$fileExtension')) {
          filename = '$filename.$fileExtension';
        }
      }
      
      debugPrint('📄 最终文件名: $filename');
      debugPrint('🏷️ 文件类型: .$fileExtension');
      
    } catch (e) {
      debugPrint('⚠️ 解析文件名失败: $e');
      filename = 'download_${DateTime.now().millisecondsSinceEpoch}.dat';
      fileExtension = 'dat';
    }

    // 🔥 获取安全的保存路径
    final String savePath = await _getSafeDownloadPath(filename, fileExtension);
    debugPrint('💾 保存路径: $savePath');

    setState(() {
      _isDownloading = true;
      _downloadingFilename = filename;
      _downloadProgress = 0.0;
    });

    // 🔥 显示"正在下载"toast（顶部 3 秒自动消失，不打断浏览）
    if (mounted) {
      _showDownloadingToastBanner = true;
      _downloadingToastTimer?.cancel();
      _downloadingToastTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _showDownloadingToastBanner = false;
      });
    }

    try {
      debugPrint('📥 开始下载: $url');

      // 使用 Dio 流式下载到本地文件（边下边写盘，避免整文件读进内存导致大文件 OOM/卡顿）
      final dio = Dio();

      final request = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 5,
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 2),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
            'Accept': '*/*',
          },
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            if (mounted) {
              setState(() {
                _downloadProgress = progress;
              });
            }
          }
        },
      );

      // 🔥 流式写入磁盘（边下边写：逐块取数写入，避免整文件读入内存）
      final file = File(savePath);
      final raf = await file.open(mode: FileMode.write);
      await for (final chunk in request.data!.stream) {
        await raf.writeFrom(chunk);
      }
      await raf.close();
      
      dio.close(force: true);

      // 下载完成 - 验证文件有效性
      debugPrint('✅ 下载完成: $savePath');
      
      // 🔥 验证下载的文件是否真正存在且有内容
      final downloadedFile = File(savePath);
      if (!await downloadedFile.exists()) {
        throw Exception('下载文件不存在: $savePath');
      }
      final fileSize = await downloadedFile.length();
      debugPrint('📊 下载文件大小: $fileSize bytes');
      if (fileSize == 0) {
        throw Exception('下载文件为空(0 bytes)，可能下载失败');
      }
      
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
      });

      // 🔥 将文件保存到系统公共目录（通过 MediaStore 注册到相册/文件管理器）
      debugPrint('🔄 开始保存到系统目录...');
      final systemPath = await _saveToSystemGallery(savePath, filename, fileExtension);
      if (systemPath != null) {
        debugPrint('✅ 已保存到系统目录: $systemPath');
      } else {
        debugPrint('⚠️ 未能保存到系统目录，使用临时路径: $savePath');
      }
      final finalPath = systemPath ?? savePath;

      // 🔥 添加到下载历史
      setState(() {
        _downloadHistory.insert(0, {
          'filename': filename,
          'url': url,
          'savePath': finalPath,
          'time': DateTime.now(),
          'status': 'completed',
        });
      });
      
      await _saveDownloadHistory();

      // 🔥 显示成功提示（中部弹窗）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (systemPath != null) {
          _showCenterToast('✅ 已保存到系统相册/文件\n$filename', Colors.green);
        } else {
          _showCenterToast('✅ 下载完成（仅保存在应用目录）\n$filename', Colors.orange);
        }
      });
    } catch (e) {
      debugPrint('❌ 下载失败: $e');
      setState(() {
        _isDownloading = false;
      });
      
      setState(() {
        _downloadHistory.insert(0, {
          'filename': filename,
          'url': url,
          'savePath': savePath,
          'time': DateTime.now(),
          'status': 'failed',
          'error': e.toString(),
        });
      });
      
      await _saveDownloadHistory();
      
      // 🔥 显示失败提示（中部弹窗，含"重试"操作）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            content: const Text('下载失败，请检查网络后重试'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _handleDownload(url, suggestedFilename);
                },
                child: const Text('重试'),
              ),
            ],
          ),
        );
      });
    }
  }

  // 🔥 用于存储 InAppWebViewController 以便执行 goBack/reload
  InAppWebViewController? _courseResourceWebViewController;
  InAppWebViewController? _quarkWebViewController;
  
  // 🔥 页面实际加载完成标记
  bool _courseResourceLoaded = false;
  bool _quarkLoaded = false;

  // 🔥 直接退出浏览器页面（不再处理网页内返回逻辑）
  void _exitBrowser() {
    if (mounted) {
      Navigator.pop(context);
    }
  }

  // 🔥 网页后退
  Future<void> _goBack() async {
    final controller = _currentTabIndex == 0 ? _courseResourceWebViewController : _quarkWebViewController;
    if (controller != null) {
      if (await controller.canGoBack()) {
        await controller.goBack();
      }
    }
  }

  // 🔥 网页前进
  Future<void> _goForward() async {
    final controller = _currentTabIndex == 0 ? _courseResourceWebViewController : _quarkWebViewController;
    if (controller != null) {
      if (await controller.canGoForward()) {
        await controller.goForward();
      }
    }
  }

  // 刷新页面
  Future<void> _refresh() async {
    final controller = _currentTabIndex == 0 ? _courseResourceWebViewController : _quarkWebViewController;
    if (controller != null) {
      // 🔥 刷新时重置加载状态
      if (mounted) {
        setState(() {
          _isLoading = true;
          if (_currentTabIndex == 0) {
            _courseResourceLoaded = false;
          } else {
            _quarkLoaded = false;
          }
        });
      }
      await controller.reload();
    }
  }

  // 🔥 显示下载管理弹窗
  void _showDownloadManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.5, // 半屏高度
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '下载管理',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      if (_downloadHistory.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.delete_sweep, size: 20),
                          label: const Text('清空全部'),
                          onPressed: () {
                            // 🔥 先关闭弹窗（同步操作）
                            Navigator.pop(context);
                            
                            // 🔥 清空记录（同步操作）
                            setState(() {
                              _downloadHistory.clear();
                            });
                            
                            // 🔥 异步保存（使用 unawaited 明确表示不等待结果）
                            unawaited(_saveDownloadHistory());
                            
                            // 🔥 显示提示（同步操作，中部弹窗）
                            _showCenterToast('已清空所有下载记录', Colors.grey);
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              
              // 下载记录列表
              Expanded(
                child: _downloadHistory.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.download_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '暂无下载记录',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _downloadHistory.length,
                        itemBuilder: (context, index) {
                          final item = _downloadHistory[index];
                          final isCompleted = item['status'] == 'completed';
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: Icon(
                                isCompleted ? Icons.check_circle : Icons.error,
                                color: isCompleted ? Colors.green : Colors.red,
                              ),
                              title: Text(
                                item['filename'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item['time'].year}-${item['time'].month.toString().padLeft(2, '0')}-${item['time'].day.toString().padLeft(2, '0')} ${item['time'].hour.toString().padLeft(2, '0')}:${item['time'].minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (!isCompleted && item['error'] != null)
                                    Text(
                                      item['error'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.red,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              trailing: isCompleted
                                  ? IconButton(
                                      icon: const Icon(Icons.folder_outlined, size: 20),
                                      tooltip: '查看文件所在文件夹',
                                      onPressed: () async {
                                        final savePath = item['savePath'] as String?;
                                        if (savePath == null || savePath.isEmpty) {
                                          _showCenterToast('该文件暂无可打开的存储位置', Colors.orange);
                                          return;
                                        }
                                        final ok = await _fileChannel.invokeMethod('openFileLocation', {'filePath': savePath});
                                        _showCenterToast(ok ? '已打开文件存储位置' : '无法打开，请手动前往 Download 目录', ok == true ? Colors.green : Colors.red);
                                      },
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.refresh, size: 20),
                                      tooltip: '重新下载',
                                      onPressed: () {
                                        _handleDownload(item['url'], item['filename']);
                                        Navigator.pop(context);
                                      },
                                    ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 🔥 构建课程资源 WebView
  Widget _buildCourseResourceWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('http://cydc.dpdns.org')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        // 🔥 使用 Android 系统 WebView 原生 UA（跟随 Chromium 内核版本），避免写死旧版 Chrome 被站点按旧内核降级
        supportZoom: true, // 启用缩放
        // 🔥 启用下载支持
        useOnDownloadStart: true,
        // 🔥 允许混合内容（HTTP/HTTPS）
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        // 🔥 启用第三方 Cookie（某些下载需要）
        thirdPartyCookiesEnabled: true,
        // 🔥 允许文件访问（下载需要）
        allowFileAccess: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        // 🔥 开启缓存：页面 HTML/CSS/JS 走 WebView 本地磁盘缓存，二次进入显著提速
        cacheEnabled: true,
      ),
      onWebViewCreated: (controller) {
        _courseResourceWebViewController = controller;
        // 🔥 初始显示加载动画
        if (mounted && !_courseResourceLoaded) {
          setState(() {
            _isLoading = true;
          });
        }
      },
      onLoadStart: (controller, url) {
        debugPrint('🔄 页面开始加载: $url');
      },
      onProgressChanged: (controller, progress) {
        // 🔥 使用进度变化来控制加载状态，更准确
        if (mounted) {
          if (progress < 100) {
            // 页面还在加载中
            if (!_isLoading) {
              setState(() {
                _isLoading = true;
              });
            }
          } else {
            // 进度达到100%，但还需要等待页面真正渲染完成
            debugPrint('📊 课程资源页面加载进度: $progress%');
          }
        }
      },
      onLoadStop: (controller, url) async {
        debugPrint('✅ 课程资源页面加载完成: $url');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _courseResourceLoaded = true;
          });
        }
        
        // 🔥 注入JavaScript检测文件上传元素和下载链接
        await controller.evaluateJavascript(source: '''
          (function() {
            // 1. 检测文件上传元素
            const fileInputs = document.querySelectorAll('input[type="file"]');
            console.log('📁 检测到 ' + fileInputs.length + ' 个文件上传元素');
            
            fileInputs.forEach((input, index) => {
              console.log('文件上传元素 ' + index + ':', input);
              
              // 添加点击事件监听
              input.addEventListener('click', function(e) {
                console.log('🔘 用户点击了文件上传按钮');
              });
              
              // 添加change事件监听
              input.addEventListener('change', function(e) {
                console.log('✅ 文件已选择:', this.files.length + ' 个文件');
              });
            });
            
            // 2. 🔥 拦截所有下载链接的点击事件
            const downloadLinks = document.querySelectorAll('a[href]');
            console.log('🔗 检测到 ' + downloadLinks.length + ' 个链接');
            
            downloadLinks.forEach((link, index) => {
              const href = link.href.toLowerCase();
              // 检测是否为下载链接（常见文件扩展名或下载API）
              const isDownloadLink = 
                href.endsWith('.pdf') || href.endsWith('.doc') || href.endsWith('.docx') ||
                href.endsWith('.xls') || href.endsWith('.xlsx') || href.endsWith('.ppt') ||
                href.endsWith('.pptx') || href.endsWith('.zip') || href.endsWith('.rar') ||
                href.endsWith('.7z') || href.endsWith('.tar') || href.endsWith('.gz') ||
                href.endsWith('.apk') || href.endsWith('.mp4') || href.endsWith('.avi') ||
                href.endsWith('.mov') || href.endsWith('.wmv') || href.endsWith('.flv') ||
                href.endsWith('.mkv') || href.endsWith('.mp3') || href.endsWith('.wav') ||
                href.endsWith('.jpg') || href.endsWith('.jpeg') || href.endsWith('.png') ||
                href.endsWith('.gif') || href.endsWith('.bmp') || href.endsWith('.webp') ||
                href.includes('/download/') || href.includes('/api/download/') ||
                href.includes('/api/file/') || href.includes('/file/download');
              
              if (isDownloadLink) {
                console.log('📥 检测到下载链接 ' + index + ':', link.href);
                
                link.addEventListener('click', function(e) {
                  console.log('🔘 用户点击下载链接:', this.href);
                  // 不阻止默认行为，让 WebView 的 onDownloadStart 处理
                });
              }
            });
          })();
        ''');
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString().toLowerCase() ?? '';
        
        // 🔥 只拦截不支持的协议，其他所有请求都允许正常加载
        if (url.startsWith('intent://')) {
          debugPrint('⚠️ 拦截不支持的协议: $url');
          return NavigationActionPolicy.CANCEL;
        }
        
        // 允许所有 http/https 请求（包括下载）
        if (url.startsWith('http') || url.startsWith('https')) {
          return NavigationActionPolicy.ALLOW;
        } else {
          // 其他协议一律拦截
          debugPrint('⚠️ 拦截未知协议: $url');
          return NavigationActionPolicy.CANCEL;
        }
      },
      onDownloadStartRequest: (controller, request) async {
        debugPrint('📥 检测到下载请求: ${request.url}');
        // 🔥 下载前确保 WebView 加载状态已重置，避免下载后持续转圈
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        await _handleDownload(request.url.toString(), request.suggestedFilename);
      },
    );
  }

  // 🔥 构建夸克搜索 WebView
  Widget _buildQuarkWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('https://quark.sm.cn/')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        // 🔥 使用 Android 系统 WebView 原生 UA（跟随 Chromium 内核版本）
        supportZoom: true, // 启用缩放
        // 🔥 启用下载支持
        useOnDownloadStart: true,
        // 🔥 允许混合内容（HTTP/HTTPS）
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        // 🔥 启用第三方 Cookie（某些下载需要）
        thirdPartyCookiesEnabled: true,
        // 🔥 允许文件访问（下载需要）
        allowFileAccess: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        // 🔥 开启缓存：页面 HTML/CSS/JS 走 WebView 本地磁盘缓存，二次进入显著提速
        cacheEnabled: true,
      ),
      onWebViewCreated: (controller) {
        _quarkWebViewController = controller;
        // 🔥 初始显示加载动画
        if (mounted && !_quarkLoaded) {
          setState(() {
            _isLoading = true;
          });
        }
      },
      onLoadStart: (controller, url) {
        debugPrint('🔄 页面开始加载: $url');
      },
      onProgressChanged: (controller, progress) {
        // 🔥 使用进度变化来控制加载状态，更准确
        if (mounted) {
          if (progress < 100) {
            // 页面还在加载中
            if (!_isLoading) {
              setState(() {
                _isLoading = true;
              });
            }
          } else {
            // 进度达到100%，但还需要等待页面真正渲染完成
            debugPrint('📊 夸克搜索页面加载进度: $progress%');
          }
        }
      },
      onLoadStop: (controller, url) async {
        debugPrint('✅ 夸克搜索页面加载完成: $url');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _quarkLoaded = true;
          });
        }
        
        // 🔥 注入JavaScript检测文件上传元素和下载链接
        await controller.evaluateJavascript(source: '''
          (function() {
            // 1. 检测文件上传元素
            const fileInputs = document.querySelectorAll('input[type="file"]');
            console.log('📁 检测到 ' + fileInputs.length + ' 个文件上传元素');
            
            fileInputs.forEach((input, index) => {
              console.log('文件上传元素 ' + index + ':', input);
              
              // 添加点击事件监听
              input.addEventListener('click', function(e) {
                console.log('🔘 用户点击了文件上传按钮');
              });
              
              // 添加change事件监听
              input.addEventListener('change', function(e) {
                console.log('✅ 文件已选择:', this.files.length + ' 个文件');
              });
            });
            
            // 2. 🔥 拦截所有下载链接的点击事件
            const downloadLinks = document.querySelectorAll('a[href]');
            console.log('🔗 检测到 ' + downloadLinks.length + ' 个链接');
            
            downloadLinks.forEach((link, index) => {
              const href = link.href.toLowerCase();
              // 检测是否为下载链接（常见文件扩展名或下载API）
              const isDownloadLink = 
                href.endsWith('.pdf') || href.endsWith('.doc') || href.endsWith('.docx') ||
                href.endsWith('.xls') || href.endsWith('.xlsx') || href.endsWith('.ppt') ||
                href.endsWith('.pptx') || href.endsWith('.zip') || href.endsWith('.rar') ||
                href.endsWith('.7z') || href.endsWith('.tar') || href.endsWith('.gz') ||
                href.endsWith('.apk') || href.endsWith('.mp4') || href.endsWith('.avi') ||
                href.endsWith('.mov') || href.endsWith('.wmv') || href.endsWith('.flv') ||
                href.endsWith('.mkv') || href.endsWith('.mp3') || href.endsWith('.wav') ||
                href.endsWith('.jpg') || href.endsWith('.jpeg') || href.endsWith('.png') ||
                href.endsWith('.gif') || href.endsWith('.bmp') || href.endsWith('.webp') ||
                href.includes('/download/') || href.includes('/api/download/') ||
                href.includes('/api/file/') || href.includes('/file/download');
              
              if (isDownloadLink) {
                console.log('📥 检测到下载链接 ' + index + ':', link.href);
                
                link.addEventListener('click', function(e) {
                  console.log('🔘 用户点击下载链接:', this.href);
                  // 不阻止默认行为，让 WebView 的 onDownloadStart 处理
                });
              }
            });
          })();
        ''');
      },
      onReceivedError: (controller, request, error) {
        debugPrint('❌ WebView加载错误: ${error.description}');
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString().toLowerCase() ?? '';
        
        if (url.startsWith('intent://')) {
          return NavigationActionPolicy.CANCEL;
        }
        
        if (url.startsWith('http') || url.startsWith('https')) {
          return NavigationActionPolicy.ALLOW;
        } else {
          return NavigationActionPolicy.CANCEL;
        }
      },
      onDownloadStartRequest: (controller, request) async {
        debugPrint('📥 检测到下载请求: ${request.url}');
        // 🔥 下载前确保 WebView 加载状态已重置，避免下载后持续转圈
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        await _handleDownload(request.url.toString(), request.suggestedFilename);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 获取状态栏高度
    final statusBarHeight = MediaQuery.of(context).padding.top;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 🔥 状态栏安全区域占位
          SizedBox(height: statusBarHeight),
          
          // ✅ 顶部工具栏：严格按 6 等份分配
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // 🔥 第1份（最左）：返回按钮（直接退出页面）
                Expanded(
                  flex: 1,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    onPressed: _exitBrowser,
                    tooltip: '退出浏览器',
                  ),
                ),
                
                // 🔥 第2、3份：课程资源标签（占2份）
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () {
                      if (_currentTabIndex != 0) {
                        _tabController.animateTo(0);
                      }
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _currentTabIndex == 0 ? Colors.blue : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        '课程资源',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _currentTabIndex == 0 ? Colors.blue : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
                
                // 🔥 第4、5份：夸克搜索标签（占2份）
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () {
                      if (_currentTabIndex != 1) {
                        _tabController.animateTo(1);
                      }
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _currentTabIndex == 1 ? Colors.blue : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        '夸克搜索',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _currentTabIndex == 1 ? Colors.blue : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
                
                // 🔥 第6份（最右）：刷新按钮
                Expanded(
                  flex: 1,
                  child: IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: Colors.black87,
                    ),
                    onPressed: _refresh,
                    tooltip: '刷新',
                  ),
                ),
              ],
            ),
          ),
          
          // WebView内容区域
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(), // 禁止左右滑动切换
                  children: [
                    _buildCourseResourceWebView(),
                    _buildQuarkWebView(),
                  ],
                ),
                
                // 🔥 加载动画（页面加载中显示居中圆形进度条）
                if (_isLoading)
                  Container(
                    color: Colors.white.withValues(alpha: 0.9),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            strokeWidth: 4,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '加载中...',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // 顶部加载进度条（细线）
                if (_isLoading)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      backgroundColor: Colors.grey[200],
                      minHeight: 2,
                    ),
                  ),

                // 🔥 "正在下载"toast（顶部浮层，3 秒自动消失，不打断浏览）
                if (_showDownloadingToastBanner)
                  Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '正在下载 ${_downloadingFilename ?? ''}',
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              Text(
                                '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: _downloadProgress,
                              minHeight: 5,
                              backgroundColor: Colors.white.withValues(alpha: 0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 🔥 中部弹窗提示（替代底部 SnackBar，2 秒自动消失）
                if (_toastMessage != null)
                  _buildCenterToast(),
              ],
            ),
          ),
          
          // 🔥 底部工具栏：三栏均分
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // 🔥 左侧：网页后退
                Expanded(
                  flex: 1,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
                    onPressed: _goBack,
                    tooltip: '后退',
                  ),
                ),
                
                // 🔥 中间：网页前进
                Expanded(
                  flex: 1,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.black87),
                    onPressed: _goForward,
                    tooltip: '前进',
                  ),
                ),
                
                // 🔥 右侧：下载管理入口
                Expanded(
                  flex: 1,
                  child: Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.download, color: Colors.black87),
                        onPressed: _showDownloadManager,
                        tooltip: '下载管理',
                      ),
                      // 🔥 下载数量角标
                      if (_downloadHistory.isNotEmpty)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              _downloadHistory.length > 99 ? '99+' : '${_downloadHistory.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
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
      ),
    );
  }
}
