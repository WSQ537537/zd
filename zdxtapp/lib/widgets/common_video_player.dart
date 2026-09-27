import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:wakelock_plus/wakelock_plus.dart'; // 🔥 新增：屏幕常亮

/// 通用视频播放器组件（使用 video_player + chewie）
/// - 自动播放支持
/// - 完整的播放控制UI
/// - 全屏切换支持
/// - 优化的布局，避免按钮拥挤
/// 修复：全屏白屏、竖屏视频强制横屏、控制栏不显示问题
class CommonVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final VoidCallback? onVideoClosed;
  final bool autoPlay;
  final double? height;

  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onEnd;
  
  // 🔥 新增：缓冲状态回调
  final ValueChanged<bool>? onBuffering;
  
  // 🔥 新增：视频类型参数
  // type=1: 本地视频, type=2: 在线视频(B站链接)
  final int? videoType;

  const CommonVideoPlayer({
    super.key,
    required this.videoUrl,
    this.onVideoClosed,
    this.autoPlay = false,
    this.height,
    this.onPlay,
    this.onPause,
    this.onEnd,
    this.onBuffering, // 🔥 添加缓冲状态回调
    this.videoType, // 🔥 添加videoType参数
  });

  @override
  State<CommonVideoPlayer> createState() => _CommonVideoPlayerState();
}

class _CommonVideoPlayerState extends State<CommonVideoPlayer> with WidgetsBindingObserver {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;
  
  // 添加ValueNotifier来管理播放状态
  final ValueNotifier<VideoPlayerValue?> _playerValueNotifier = ValueNotifier(null);
  
  // 🔥 新增：B站解析相关状态
  bool _isResolving = false;
  Timer? _resolveTimer;

  // 🔥 新增：存储视频原始宽高比，用于判断全屏方向
  double? _videoAspectRatio;
  
  // 🔥 新增：跟踪全屏状态，用于切换全屏/退出全屏图标
  bool _isFullScreen = false;
  
  // 🔥 全屏切换期标记：进入/退出全屏时 isPlaying 会瞬时翻转，期间吞掉 onPause/onPlay
  bool _inOrientationSwitch = false;
  Timer? _orientationResetTimer;

  // 🔥 播放/缓冲状态跟踪（类成员，供 listener 与全屏切换兜底共用）
  bool _wasPlaying = false;
  bool _lastBuffering = false;

  // 🔥 新增：控制栏显示状态和自动隐藏定时器（使用ValueNotifier确保UI能响应状态变化）
  final ValueNotifier<bool> _showControlsNotifier = ValueNotifier<bool>(true);
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 🔥 根据视频类型决定初始化方式
    _initializeVideoPlayer();
  }

  /// 🔥 B站解析（委托给公共顶层函数，保持原实例方法名供内部使用）
  Future<String?> _parseBilibiliVideo(String input) async {
    return parseBilibiliToDirectUrl(input);
  }


  // 🔥 初始化视频播放器
  Future<void> _initializeVideoPlayer() async {
    final videoType = widget.videoType ?? 1; // 默认为本地视频
    final originalUrl = widget.videoUrl;
    
    if (originalUrl.isEmpty) {
      setState(() {
        _hasError = true;
      });
      return;
    }
    
    if (videoType == 2) {
      // 在线视频：仅当是「B站网页地址」时才解析成直链；
      // 若填入的是「原始视频直链」（如 mp4 直链、非 B站 http(s) 地址），直接播放，不解析
      // （防止直链被提前解析后失效）
      final isBilibili = originalUrl.contains('bilibili.com') ||
          originalUrl.contains('b23.tv') ||
          RegExp(r'BV[0-9A-Za-z]+').hasMatch(originalUrl);

      if (isBilibili) {
        // B站网页地址：播放时解析
        setState(() {
          _isResolving = true;
        });

        try {
          final resolvedUrl = await _parseBilibiliVideo(originalUrl);
          if (resolvedUrl != null && mounted) {
            setState(() {
              _isResolving = false;
            });
            await _setupVideoPlayer(resolvedUrl);
          } else if (mounted) {
            setState(() {
              _isResolving = false;
              _hasError = true;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _isResolving = false;
              _hasError = true;
            });
          }
        }
      } else {
        // 非 B站的原始视频直链：直接播放（不走解析）
        await _setupVideoPlayer(originalUrl);
      }
    } else {
      // 本地视频，直接播放
      await _setupVideoPlayer(originalUrl);
    }
  }

  // 🔥 设置视频播放器（核心修复点）
  Future<void> _setupVideoPlayer(String videoUrl) async {
    try {
      final videoType = widget.videoType ?? 1;
      
      // 🔥 优化本地视频播放：使用 VideoPlayerOptions 配置流式播放
      // 在带宽有限的服务器上，允许边加载边播放，而不是一次性下载完整视频
      VideoPlayerController? controller;
      
      if (videoType == 1) {
        // 本地视频：配置HTTP Range请求支持流式播放
        // 🔥 关键优化：
        // 1. mixWithOthers: 允许与其他音频混合，避免独占音频焦点
        // 2. allowBackgroundPlayback: 允许后台播放
        // 注意：HTTP Range请求由底层播放器（ExoPlayer/AVPlayer）自动处理
        controller = VideoPlayerController.networkUrl(
          Uri.parse(videoUrl),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: true,
          ),
        );
      } else {
        // 在线视频（B站解析后的直链）
        controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      }
      
      _videoPlayerController = controller;
      
      // 🔥 关键优化：在初始化之前设置监听器，以便捕获初始化过程中的事件
      // 这有助于在视频开始缓冲时就更新UI状态
      
      await _videoPlayerController!.initialize();
      
      if (!mounted) return;
      
      // 🔥 修复问题2：存储视频原始宽高比，用于判断全屏方向
      _videoAspectRatio = _videoPlayerController!.value.aspectRatio;
      
      // 🔥 修复问题1：根据视频宽高比自动选择全屏方向
      // 宽高比 > 1 是横屏视频，宽高比 < 1 是竖屏视频
      List<DeviceOrientation> fullScreenOrientations = [];
      if (_videoAspectRatio! > 1) {
        // 横屏视频，允许左右横屏
        fullScreenOrientations = const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      } else {
        // 竖屏视频，保持竖屏
        fullScreenOrientations = const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ];
      }
      
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: widget.autoPlay,
        looping: false,
        aspectRatio: _videoAspectRatio!,
        customControls: _buildCustomControls(), // 🔥 自定义控制栏
        // 🔥 关键修复：必须设置为true，Chewie才会渲染customControls
        showControls: true,
        showControlsOnInitialize: true,
        placeholder: Container(color: Colors.black),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              '视频加载失败，请稍后重试',
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
        // 🔥 添加控制栏安全区域配置，避免按钮拥挤
        controlsSafeAreaMinimum: const EdgeInsets.all(8),
        // 🔥 修复问题1：使用Flutter 3.0+颜色API规范
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.blue.withValues(alpha: 1.0),
          handleColor: Colors.blue.withValues(alpha: 1.0),
          bufferedColor: Colors.white.withValues(alpha: 0.3),
          backgroundColor: Colors.black.withValues(alpha: 0.54),
        ),
        allowFullScreen: true,
        // 🔥 修复问题1：使用Flutter 3.0+颜色API规范
        deviceOrientationsOnEnterFullScreen: fullScreenOrientations,
        deviceOrientationsAfterFullScreen: const [
          DeviceOrientation.portraitUp,
        ],
        systemOverlaysOnEnterFullScreen: [],
        systemOverlaysAfterFullScreen: SystemUiOverlay.values,
        fullScreenByDefault: false,
        // 🔥 核心修复：简化全屏路由，使用Scaffold确保背景色正确
        routePageBuilder: (context, animation, secondAnimation, child) {
          return PopScope(
            canPop: true,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop && mounted) {
                // 🔥 退出全屏时进入方向切换期：拦截 isPlaying 瞬时翻转（不触发 onPause/onPlay），
                //    防止上层 _stopTimer 被误调、挂钟基准被作废；
                //    listener 的 300ms 稳定检测会在切换结束时自动对齐 wasPlaying
                _inOrientationSwitch = true;
                // 🔥 退出全屏时重置状态
                setState(() {
                  _isFullScreen = false;
                });
                _showControlsNotifier.value = true;
                _showControlsBar();
              }
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: child,
            ),
          );
        },
        // 🔥 新增：防止屏幕休眠干扰渲染
        allowedScreenSleep: false,
      );

      // 监听播放状态变化
      // _wasPlaying: 记录上一次值是否为播放中，用于仅在「真正进入暂停态」时触发 onPause，
      // 避免拖动进度条 seekTo 引起的瞬时 isPlaying 翻转导致上层进度卡片误刷新
      // 🔥 全屏切换期：进入/退出全屏时 isPlaying 会瞬时翻转（方向锁定、surface 重建），
      // 这段时间内的 isPlaying 变化不视为"用户主动暂停"，不应触发 onPause
      // 🔥 缓冲状态回调：仅在 isBuffering「真正翻转」时触发一次，
      // 避免 seek 到已缓存片段、拖动进度条等场景下的瞬时 isBuffering=false 误触发 onBuffering(false)
      // 导致上层 _resumeTimer 被误调用、挂钟重启、计时被重算
      // 🔥 进入全屏前，记录当前播放状态，全屏期间所有 isPlaying 翻转都吞掉
      // 方向变化完成（isPlaying 稳定）后，再恢复原状态并继续监听
      _videoPlayerController!.addListener(() {
        _playerValueNotifier.value = _videoPlayerController!.value;

        // 🔥 全屏切换期：拦截 isPlaying / isBuffering 的瞬时翻转（不触发 onPause/onPlay/onBuffering），
        //    避免上层 _stopTimer / _pauseTimer / _resumeTimer 被误调、挂钟基准被作废或重新基准清零；
        //    切换期结束时由 _switchDone 对齐状态并按真实情况补发缓冲回调，
        //    让视频自然的状态翻转（用户在全屏里点播放/暂停）驱动上层。
        if (_inOrientationSwitch) {
          _orientationResetTimer?.cancel();
          _orientationResetTimer = Timer(const Duration(milliseconds: 300), _switchDone);
          return;
        }

        // 🔥 缓冲状态回调：只在「翻转」时触发一次（避免 seek/暂停态下重复回调）
        // 关键：只有「正在播放」时的缓冲才代表"加载中"；
        // 视频已暂停/结束后 isBuffering 恒为 false，此时的 false 是常态，不能触发 resume。
        final nowBuffering = _videoPlayerController!.value.isBuffering;
        if (nowBuffering != _lastBuffering) {
          _lastBuffering = nowBuffering;
          final resumeEffective = nowBuffering ? false : _videoPlayerController!.value.isPlaying;
          widget.onBuffering?.call(resumeEffective);
        }

        // 🔥 播放状态回调（避免重复调用）
        final isPlayingNow = _videoPlayerController!.value.isPlaying;
        if (isPlayingNow) {
          // 🔥 视频开始播放时，启用屏幕常亮
          WakelockPlus.enable();
          widget.onPlay?.call();
        } else if (!_videoPlayerController!.value.isBuffering && _wasPlaying) {
          // 🔥 仅在从播放态真正切入暂停态时调用 onPause；
          // 拖动进度条的 seekTo 不经过播放态、_wasPlaying 仍为 false，故不触发
          widget.onPause?.call();
        }
        _wasPlaying = isPlayingNow;

        // 播放结束回调
        if (_videoPlayerController!.value.isCompleted) {
          // 🔥 视频播放结束时，禁用屏幕常亮
          WakelockPlus.disable();
          widget.onEnd?.call();
        }
      });
        
        setState(() {
          _isInitialized = true;
          _isResolving = false;
        });
        
        // 🔥 初始化完成后，延迟一帧再启动自动隐藏定时器，确保UI已渲染
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showControlsBar();
          }
        });
        
        if (widget.autoPlay) {
          _videoPlayerController!.play();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _isResolving = false;
          });
        }
      }
  }

  // ====================== 🔥 全屏切换期结束：对齐状态 ======================
  // 进入/退出全屏时 isPlaying 会瞬时翻转（方向锁定、surface 重建），
  // 期间 listener 拦截 onPause/onPlay（避免上层 _stopTimer 被误调、挂钟基准被作废）。
  // 切换期结束时统一对齐 _wasPlaying/_lastBuffering 到视频真实状态，不补发任何回调，
  // 让后续用户在全屏里的自然播放/暂停驱动上层；
  // 全屏暂停期间 isBuffering 的翻转会正常触发 onBuffering → 上层挂钟冻结/恢复。
  void _switchDone() {
    if (!_inOrientationSwitch) return;
    _inOrientationSwitch = false;
    if (_videoPlayerController == null) return;
    _wasPlaying = _videoPlayerController!.value.isPlaying;
    // 切换期间 isBuffering 若发生变化，listener 已跳过回调，这里按真实状态补发一次
    final nowBuffering = _videoPlayerController!.value.isBuffering;
    if (nowBuffering != _lastBuffering) {
      _lastBuffering = nowBuffering;
      final resumeEffective = nowBuffering ? false : _videoPlayerController!.value.isPlaying;
      widget.onBuffering?.call(resumeEffective);
    }
  }

  @override
  void dispose() {
    // 🔥 仅在组件真正销毁（视频被关闭、卡片收起、切换视频等）时通知上层
    // 用于 study.dart 调用 _resetTimer 清零累计计时；拖动进度条/暂停/全屏切换不会触发
    widget.onVideoClosed?.call();
    WidgetsBinding.instance.removeObserver(this);
    
    // 🔥 禁用屏幕常亮（防止内存泄漏）
    WakelockPlus.disable();
    
    // 清理解析定时器
    _resolveTimer?.cancel();
    _resolveTimer = null;
    
    // 🔥 清理控制栏自动隐藏定时器
    _hideTimer?.cancel();
    _hideTimer = null;
    
    // 🔥 清理全屏切换期定时器
    _orientationResetTimer?.cancel();
    _orientationResetTimer = null;
    
    // 清理播放器
    _videoPlayerController?.pause();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _playerValueNotifier.dispose(); // 销毁ValueNotifier
    
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // 🔥 修复：仅在应用「真正切到后台」(paused) 时暂停视频。
      // inactive 在 Android 上会被屏幕旋转、全屏切换、弹窗等触发，若在此暂停
      // 会导致进入/退出全屏时视频被意外打断，无法连续播放；
      // 全屏切换的瞬时 isPlaying 翻转已由 _inOrientationSwitch 拦截，无需在此处理。
      _videoPlayerController?.pause();
      // 🔥 关键修复：不在这里调用 onPause，避免与全屏切换冲突
      // widget.onPause?.call();

      // 🔥 应用真正进入后台时，禁用屏幕常亮
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed) {
      // 🔥 应用恢复前台时，如果视频仍在播放则重新启用屏幕常亮
      if (_videoPlayerController?.value.isPlaying == true) {
        WakelockPlus.enable();
      }
    }
  }

  // ========== 控制栏显示/隐藏管理方法 ==========
  
  /// 显示控制栏并重置自动隐藏定时器
  void _showControlsBar() {
    if (!mounted) return;
    
    _showControlsNotifier.value = true;
    
    // 取消之前的定时器
    _hideTimer?.cancel();
    
    // 启动新的5秒自动隐藏定时器
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _showControlsNotifier.value) {
        _showControlsNotifier.value = false;
      }
    });
  }
  
  /// 切换控制栏显示/隐藏状态
  void _toggleControls() {
    if (_showControlsNotifier.value) {
      // 当前显示，则隐藏并取消定时器
      _showControlsNotifier.value = false;
      _hideTimer?.cancel();
    } else {
      // 当前隐藏，则显示并启动定时器
      _showControlsBar();
    }
  }
  
  /// 用户交互时重置定时器（仅在控制栏显示时有效）
  void _onUserInteraction() {
    // 只有当控制栏当前处于显示状态时，才重置自动隐藏定时器
    // 如果控制栏已隐藏，通常由 onTap (_toggleControls) 负责重新显示
    if (_showControlsNotifier.value) {
      _showControlsBar();
    }
  }

  // ========== 自定义控制栏构建方法（修复层级问题） ==========
  Widget _buildCustomControls() {
    debugPrint('🎬 [DEBUG] _buildCustomControls被调用');
    
    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          // 🔥 控制栏内容，根据_showControlsNotifier状态显示/隐藏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: _showControlsNotifier,
              builder: (context, showControls, _) {
                debugPrint('🎬 [DEBUG] ValueListenableBuilder重建，showControls = $showControls');
                return AnimatedOpacity(
                  opacity: showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !showControls, // 🔥 隐藏时忽略指针事件，避免误触
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.54),
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 左侧：播放/暂停按钮 + 已播放时长
                          ValueListenableBuilder<VideoPlayerValue?>(
                            valueListenable: _playerValueNotifier,
                            builder: (context, value, _) {
                              return Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      value?.isPlaying == true ? Icons.pause : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                    onPressed: () {
                                      _onUserInteraction(); // 🔥 用户交互时重置定时器
                                      final controller = _videoPlayerController!;
                                      if (controller.value.isPlaying) {
                                        controller.pause();
                                      } else {
                                        controller.play();
                                      }
                                    },
                                  ),
                                  Text(
                                    value != null ? _formatDuration(value.position) : '00:00',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          // 中间：进度条
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: ValueListenableBuilder<VideoPlayerValue?>(
                                valueListenable: _playerValueNotifier,
                                builder: (context, value, _) {
                                  if (value == null) {
                                    return Slider(
                                      value: 0,
                                      min: 0,
                                      max: 1,
                                      onChanged: (_) {},
                                    );
                                  }
                                  return SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: Colors.blue,
                                      inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                                      thumbColor: Colors.blue,
                                      overlayColor: Colors.blue.withValues(alpha: 0.2),
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                                    ),
                                    child: Slider(
                                      value: value.position.inMilliseconds.toDouble(),
                                      min: 0.0,
                                      max: value.duration.inMilliseconds.toDouble(),
                                      onChangeStart: (_) => _onUserInteraction(), // 🔥 开始拖动时重置定时器
                                      onChanged: (newValue) {
                                        final newDuration = Duration(milliseconds: newValue.toInt());
                                        _videoPlayerController!.seekTo(newDuration);
                                      },
                                      onChangeEnd: (_) => _onUserInteraction(), // 🔥 结束拖动时重置定时器
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          // 右侧：总时长 + 全屏按钮
                          ValueListenableBuilder<VideoPlayerValue?>(
                            valueListenable: _playerValueNotifier,
                            builder: (context, value, _) {
                              return Row(
                                children: [
                                  Text(
                                    value != null ? _formatDuration(value.duration) : '00:00',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                    onPressed: () {
                                    _onUserInteraction(); // 🔥 用户交互时重置定时器
                                    _inOrientationSwitch = true; // 标记进入全屏切换期
                                    // 🔥 修复问题8：严格按照Flutter视频全屏播放优化规范
                                    if (_isFullScreen) {
                                      // 当前是全屏状态，点击退出全屏
                                      Navigator.of(context).pop();
                                      setState(() {
                                        _isFullScreen = false;
                                      });
                                    } else {
                                      // 当前是小窗状态，点击进入全屏
                                      _chewieController?.enterFullScreen();
                                      setState(() {
                                        _isFullScreen = true;
                                      });
                                    }
                                    // 🔥 全屏切换期间保持屏幕常亮（surface 重建可能影响常亮状态）
                                    if (_videoPlayerController?.value.isPlaying == true) {
                                      WakelockPlus.enable();
                                    }
                                    // 🔥 安全兜底：2s 后强制结束切换期（listener 的 300ms 检测会先行对齐状态）
                                    _orientationResetTimer?.cancel();
                                    _orientationResetTimer = Timer(const Duration(seconds: 2), _switchDone);
                                  },
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 格式化时间显示
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 处理解析中的状态
    if (_isResolving) {
      return Container(
        height: widget.height ?? 200,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 8),
              Text(
                '正在解析视频链接...',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    
    // 🔥 处理解析失败的状态
    if (_hasError) {
      return Container(
        height: widget.height ?? 200,
        color: Colors.black,
         child: const Center(
          child: Text(
            '视频加载失败，请检查链接有效性',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      );
    }

    if (!_isInitialized || _videoPlayerController == null || _chewieController == null) {
      return Container(
        height: widget.height ?? 200,
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Container(
      height: widget.height ?? 200,
      color: Colors.black,
      child: Chewie(controller: _chewieController!),
    );
  }
}

/// 🔥 公共：B站网页链接 → 可播放的 m4s 直链
/// 逻辑与 CommonVideoPlayer 内部解析一致，提升为顶层函数以便其他页面（如通知页）纯前端解析复用。
/// 非 B 站链接或解析失败时返回 null。
Future<String?> parseBilibiliToDirectUrl(String input) async {
  if (input.isEmpty) {
    return null;
  }

  try {
    // 1. 提取 BV 号
    final bvRegex = RegExp(r'BV[0-9A-Za-z]+');
    final match = bvRegex.firstMatch(input);
    if (match == null) {
      return null;
    }
    final bvid = match.group(0)!;

    // 2. 提取 p 参数（分P标识）
    int? pageParam;
    final uri = Uri.tryParse(input);
    if (uri != null && uri.queryParameters.containsKey('p')) {
      final pStr = uri.queryParameters['p'];
      if (pStr != null) {
        try {
          pageParam = int.parse(pStr);
        } catch (e) {
          // p参数无效，忽略
          pageParam = null;
        }
      }
    }

    // 3. 获取视频信息（包含所有分P信息）
    final infoUrl = 'https://api.bilibili.com/x/web-interface/view?bvid=$bvid';
    final infoRes = await http.get(Uri.parse(infoUrl), headers: {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      "Referer": "https://www.bilibili.com/",
      "Origin": "https://www.bilibili.com"
    });
    final infoData = json.decode(infoRes.body);
    if (infoData['code'] != 0) {
      return null;
    }

    // 4. 确定正确的 cid
    String cid;
    if (pageParam != null && pageParam > 1) {
      // 合集视频，需要获取指定分P的cid
      // pages数组索引从0开始，所以pageParam-1
      final pages = infoData['data']['pages'] as List;
      if (pageParam <= pages.length) {
        cid = pages[pageParam - 1]['cid'].toString();
      } else {
        // p参数超出范围，使用第一个分P
        cid = infoData['data']['cid'].toString();
      }
    } else {
      // 单个视频或p=1，使用主cid
      cid = infoData['data']['cid'].toString();
    }

    // 5. 获取真实视频直链（m4s）
    final playUrl =
        "https://api.bilibili.com/x/player/playurl?bvid=$bvid&cid=$cid&qn=80&type=m4s&platform=html5&high_quality=1";
    final playRes = await http.get(Uri.parse(playUrl), headers: {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      "Referer": "https://www.bilibili.com/",
      "Origin": "https://www.bilibili.com"
    });

    final playData = json.decode(playRes.body);
    if (playData['code'] != 0) {
      return null;
    }

    // 6. 提取真实视频直链（这才是能播放的）
    String videoUrl = "";
    try {
      videoUrl = playData['data']['durl'][0]['url']; // 兼容老格式
    } catch (e) {
      try {
        videoUrl = playData['data']['dash']['video'][0]['baseUrl']; // dash 格式
      } catch (e2) {
        try {
          videoUrl = playData['data']['dash']['video'][0]['backupUrl'][0];
        } catch (e3) {
          // 所有格式都失败
          videoUrl = "";
        }
      }
    }

    if (videoUrl.isEmpty) {
      return null;
    }

    return videoUrl; // ✅ 真实视频直链
  } catch (e) {
    return null;
  }
}