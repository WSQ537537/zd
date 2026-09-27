import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// 导航栏背景管理器
/// 职责：
/// 1. 冷启动时立即展示缓存背景（无网络等待）；无缓存则展示默认渐变
/// 2. 首帧渲染后再与后端 getBgState 同步：状态码一致则保持，不一致则下载更新
/// 3. 后端无背景配置 → 清除缓存，回退到默认渐变
/// 4. 登录/切换账号等场景重新 mount 时会触发缓存优先 + 后台同步
class NavBackgroundManager extends StatefulWidget {
  final Widget child;

  const NavBackgroundManager({super.key, required this.child});

  @override
  State<NavBackgroundManager> createState() => _NavBackgroundManagerState();
}

class _NavBackgroundManagerState extends State<NavBackgroundManager>
    with SingleTickerProviderStateMixin {
  static const LinearGradient _defaultGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFe0f7fa), Color(0xFF1e88e5)],
  );

  File? _bgImage;
  int _downloadAttempts = 0; // 当前尝试次数（用于退避）
  bool _syncStarted = false; // 防止后台同步被触发多次

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    // 第1步：立即读缓存，展示缓存背景或默认渐变（不阻塞首帧，不在网络请求后等待）
    _showCachedBackgroundImmediately();
    // 第2步：首帧渲染后与后端同步（状态码比对 + 必要时下载更新）
    // 使用 addPostFrameCallback 确保首帧已完成渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncBackgroundWithBackend();
    });
  }

  /// 立即加载并展示本地缓存背景（无网络等待）。
  /// - 有缓存且文件存在 → 立即显示
  /// - 无缓存 / 文件缺失 → 保持默认渐变（build 中已默认渐变兜底）
  Future<void> _showCachedBackgroundImmediately() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const stateKey = 'nav_bg_state';
      const pathKey = 'nav_bg_path';
      final cachePath = prefs.getString(pathKey);
      if (cachePath == null) return;
      final file = File(cachePath);
      if (!file.existsSync()) {
        // 缓存文件丢失：清理无效路径，下次冷启动走默认渐变
        prefs.remove(pathKey);
        prefs.remove(stateKey);
        return;
      }
      if (!mounted) return;
      _showBackgroundImage(file);
    } catch (e) {
      debugPrint('缓存背景加载失败，使用默认渐变: $e');
    }
  }

  /// 首帧渲染后与后端同步：状态码比对 + 必要时下载更新。
  /// - 后端无背景配置 → 清除本地缓存 + 回退默认渐变
  /// - 状态码一致且本地有缓存 → 保持当前展示，不动作
  /// - 状态码不一致 / 缓存失效 / 首次加载 → 下载并更新（带退避重试）
  Future<void> _syncBackgroundWithBackend() async {
    if (!mounted || _syncStarted) return;
    _syncStarted = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      const stateKey = 'nav_bg_state';
      const pathKey = 'nav_bg_path';

      // 获取远程状态码（失败时静默保留当前缓存展示）
      String remoteState = '';
      bool hasBg = false;
      bool remoteOk = false;
      try {
        final resp = await http
            .get(Uri.parse('${Config.baseUrl}/api/getBgState'))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          remoteOk = true;
          final data = (resp.body.isNotEmpty)
              ? utf8.decode(resp.bodyBytes)
              : '{}';
          final json = jsonDecode(data) as Map<String, dynamic>?;
          remoteState = (json?['state'] ?? '').toString();
          final rawHasBg = json?['hasBg'];
          hasBg = rawHasBg is bool
              ? rawHasBg
              : rawHasBg == 1 || rawHasBg == 'true';
        }
      } catch (e) {
        debugPrint('获取背景状态码失败: $e');
      }

      // 网络异常 → 保持当前缓存展示，不做任何变更
      if (!remoteOk) return;

      final localState = prefs.getString(stateKey) ?? '';
      final cachePath = prefs.getString(pathKey);
      final hasLocalCache =
          cachePath != null && File(cachePath).existsSync();

      // 情况A：后端无背景配置 → 清空缓存，显示默认渐变
      if (!hasBg) {
        if (cachePath != null) {
          try {
            await File(cachePath).delete();
          } catch (_) {}
        }
        await prefs.remove(stateKey);
        await prefs.remove(pathKey);
        if (mounted) {
          setState(() {
            _bgImage = null; // 回退默认渐变
          });
        }
        return;
      }

      // 情况B：状态码一致且有有效缓存 → 直接复用，不动作
      if (localState == remoteState &&
          hasLocalCache &&
          remoteState.isNotEmpty) {
        return;
      }

      // 情况C：状态码不一致 / 缓存失效 / 首次加载 → 下载（带重试）
      _downloadAttempts = 0;
      await _downloadWithRetry(prefs, stateKey, pathKey, remoteState, hasBg);
    } catch (e) {
      debugPrint('背景后台同步失败: $e');
    }
  }

  /// 带退避重试的背景图下载
  Future<void> _downloadWithRetry(
    SharedPreferences prefs,
    String stateKey,
    String pathKey,
    String remoteState,
    bool hasBg,
  ) async {
    const maxRetries = 2; // 最多重试2次（共3次尝试）
    const baseTimeout = Duration(seconds: 20); // 单次超时20s，适应大PNG

    while (_downloadAttempts <= maxRetries) {
      final ok = await _tryDownload(prefs, stateKey, pathKey, remoteState,
          timeout: baseTimeout);
      if (ok) return; // 成功

      _downloadAttempts++;
      if (_downloadAttempts > maxRetries) {
        debugPrint('背景图下载最终失败（已重试$maxRetries次），使用默认渐变');
        return;
      }

      // 指数退避：1s, 2s
      final backoff = Duration(seconds: 1 << (_downloadAttempts - 1));
      debugPrint('背景图下载失败，${backoff.inSeconds}s 后重试 ($_downloadAttempts/$maxRetries)');
      await Future.delayed(backoff);
    }
  }

  /// 单次下载尝试，返回是否成功
  Future<bool> _tryDownload(
    SharedPreferences prefs,
    String stateKey,
    String pathKey,
    String remoteState, {
    required Duration timeout,
  }) async {
    try {
      final response = await http
          .get(Uri.parse('${Config.baseUrl}/bg/background.png'))
          .timeout(timeout);

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        debugPrint(
            '背景图下载返回非200或空内容（status=${response.statusCode}）');
        return false;
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/nav_background.png');
      await file.writeAsBytes(response.bodyBytes);

      // 验证写入的文件确实存在且非空
      if (!await file.exists() || file.lengthSync() == 0) {
        debugPrint('背景图写入后文件为空，丢弃');
        return false;
      }

      await prefs.setString(stateKey, remoteState);
      await prefs.setString(pathKey, file.path);

      if (mounted) _showBackgroundImage(file);
      return true;
    } catch (e) {
      debugPrint('背景图下载失败: $e');
      return false;
    }
  }

  void _showBackgroundImage(File file) {
    if (!mounted) return;
    setState(() => _bgImage = file);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundFile = _bgImage;

    return Container(
      decoration: const BoxDecoration(gradient: _defaultGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景层用 RepaintBoundary 隔离：背景图切换/淡入时只重绘背景，
          // 不触发内容层（已加载好的页面）重建，避免连坐销毁重组
          RepaintBoundary(
            child: backgroundFile != null
                ? AnimatedBuilder(
                    animation: _fadeAnimation,
                    builder: (context, child) => Opacity(
                      opacity: _fadeAnimation.value,
                      child: child,
                    ),
                    child: Image.file(
                      backgroundFile,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // 内容层：包一层轻量 _NavContent，使每次 build 返回同类型 widget。
          // 背景 setState 重建时 Flutter 会复用 _NavContent 的 Element，
          // 其内部子树（已加载好的页面）不会因背景切换而被重新 inflate。
          _NavContent(child: widget.child),
        ],
      ),
    );
  }
}

/// 内容层占位 widget。
/// 仅作为 Stack 的内容子节点，自身不持有任何会变化的状态。
/// 关键作用：保证 `NavBackgroundManager.build` 每次返回的这棵子树
/// 类型结构恒定（_NavContent > widget.child），配合 Flutter 的
/// element 复用机制，使背景切换触发的 setState 不会连坐重建内容页。
class _NavContent extends StatelessWidget {
  final Widget child;
  const _NavContent({required this.child});

  @override
  Widget build(BuildContext context) => child;
}
