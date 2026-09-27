import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'exam.dart';
import 'study.dart';
import 'notice.dart';
import 'mine.dart';
import 'package:zdxtapp/pages/public/aichat.dart';
import 'package:zdxtapp/widgets/nav_background.dart';
import 'package:zdxtapp/widgets/liquid_glass_slider.dart';
import 'package:zdxtapp/widgets/liquid_glass_card.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  int currentIndex = 0;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isPageOut = false;

  static const _aiSize = 56.0;
  static const _gap = 8.0;
  static const _navHeight = 52.0;
  static const _navPadding = 16.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  void switchTab(int index) {
    if (index == currentIndex) return;
    setState(() => _isPageOut = true);
    Future.delayed(const Duration(milliseconds: 180), () {
      setState(() {
        currentIndex = index;
        _isPageOut = false;
      });
      _animationController.reset();
      _animationController.forward();
      _sliderKey.currentState?.triggerBounce();
    });
  }

  Widget _buildCurrentPage() {
    switch (currentIndex) {
      case 0:
        return const ExamPage();
      case 1:
        return const StudyPage();
      case 2:
        return const NoticePage();
      case 3:
        return const MinePage();
      default:
        return const SizedBox();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: NavBackgroundManager(
        child: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 0),
                child: AnimatedBuilder(
                  animation: _scaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isPageOut ? 0.8 : _scaleAnimation.value,
                      child: Opacity(
                        opacity: _isPageOut ? 0 : _scaleAnimation.value,
                        child: _buildCurrentPage(),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              left: _navPadding,
              right: _navPadding,
              bottom: MediaQuery.of(context).padding.bottom + 4,
              child: _NavBar(
                aiSize: _aiSize,
                gap: _gap,
                navHeight: _navHeight,
                currentIndex: currentIndex,
                onSwitchTab: switchTab,
                sliderKey: _sliderKey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final GlobalKey<LiquidGlassSliderState> _sliderKey =
    GlobalKey<LiquidGlassSliderState>();

class _NavBar extends StatelessWidget {
  final double aiSize;
  final double gap;
  final double navHeight;
  final int currentIndex;
  final ValueChanged<int> onSwitchTab;
  final GlobalKey<LiquidGlassSliderState> sliderKey;

  const _NavBar({
    required this.aiSize,
    required this.gap,
    required this.navHeight,
    required this.currentIndex,
    required this.onSwitchTab,
    required this.sliderKey,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: navHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AiButton(size: aiSize),
          SizedBox(width: gap),
          Expanded(
            child: _LongCard(
              height: navHeight,
              currentIndex: currentIndex,
              onSwitchTab: onSwitchTab,
              sliderKey: sliderKey,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiButton extends StatefulWidget {
  final double size;
  const _AiButton({required this.size});

  @override
  State<_AiButton> createState() => _AiButtonState();
}

class _AiButtonState extends State<_AiButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _pressController.forward();
  void _onTapUp(_) => _pressController.reverse();
  void _onTapCancel() => _pressController.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AiChatPage()),
        );
      },
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            // 🔥 磨砂玻璃风格：与右侧长卡片一致的 BackdropFilter + 半透明蓝色基底
            //  - 不透出底部内容：高斯模糊 + 不透明度高的蓝色 fill
            //  - 仅折射底部阴影：BackdropFilter 保留，边缘辉光 + 白色包裹线
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.size / 2),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  // 磨砂折射层（保留，让底部阴影能被折射）
                  BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                  // 液态玻璃基底：蓝色 fill + 菲涅尔边缘辉光 + 白色包裹线
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeInOut,
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // 🔥 与右侧长卡片一致的蓝色磨砂玻璃基底（不透明度更高，遮挡底部内容）
                      color: _pressController.isAnimating
                          ? const Color(0xB81E6AFF) // ≈72%
                          : const Color(0xA61E6AFF), // ≈65%
                      border: Border.all(
                        color: const Color(0x99E6F0FF), // 半透明白色包裹线（降低不透明度，避免双重白叠加）
                        width: 1.4,
                      ),
                      // 顶部高光模拟玻璃反射
                      boxShadow: _pressController.isAnimating
                          ? [
                              BoxShadow(
                                color: const Color(0x661E6AFF),
                                blurRadius: 16,
                                spreadRadius: 3,
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.15),
                                blurRadius: 2,
                                offset: const Offset(0, -1),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: const Color(0x441E6AFF),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.10),
                                blurRadius: 2,
                                offset: const Offset(0, -1),
                              ),
                            ],
                    ),
                    child: Center(
                      child: Text(
                        "AI",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          shadows: _pressController.isAnimating
                              ? [Shadow(color: const Color(0x881E6AFF), blurRadius: 8)]
                              : [Shadow(color: const Color(0x40000000), blurRadius: 4, offset: const Offset(0, 1))],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LongCard extends StatefulWidget {
  final double height;
  final int currentIndex;
  final ValueChanged<int> onSwitchTab;
  final GlobalKey<LiquidGlassSliderState> sliderKey;
  final ValueSetter<double>? onSliderPositionUpdate = null;

  const _LongCard({
    required this.height,
    required this.currentIndex,
    required this.onSwitchTab,
    required this.sliderKey,
  });

  @override
  State<_LongCard> createState() => _LongCardState();
}

class _LongCardState extends State<_LongCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _posController;
  late Animation<double> _posAnimation;
  int _lastIndex = 0;
  // 动画起点：上一次定位时的实际 left 值（来自 LayoutBuilder 的真实宽度）
  double _animStart = 0.0;
  // 首次布局标志（防止 LayoutBuilder 未就绪时动画起点错误）
  bool _layoutReady = false;

  @override
  void initState() {
    super.initState();
    _lastIndex = widget.currentIndex;
    _posController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _posAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _posController, curve: Curves.easeOutBack),
    );
    _posController.addListener(() {
      if (!_layoutReady) return;
      final start = _animStart;
      final end = _targetSliderLeft(_lastIndex, _cachedLongCardWidth ?? 0,
          (_cachedLongCardWidth ?? 0) * 0.22, (_cachedLongCardWidth ?? 0) / 4);
      widget.onSliderPositionUpdate?.call(start + (end - start) * _posAnimation.value);
    });
    _posController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // 将终点缓存下来，作为下一次动画的真实起点
        _animStart = _cachedTargetLeft;
      }
    });
  }

  @override
  void didUpdateWidget(_LongCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      if (!_layoutReady) {
        _pendingLayout = true;
        _lastIndex = widget.currentIndex;
        return;
      }
      final longCardWidth = _cachedLongCardWidth ?? 0;
      final sliderWidth = longCardWidth * 0.22;
      final tabWidth = longCardWidth / 4;
      // 将当前动画终点作为下一次动画的起点，确保从当前位置平滑出发
      _animStart = _targetSliderLeft(_lastIndex, longCardWidth, sliderWidth, tabWidth);
      _lastIndex = widget.currentIndex;
      final newTarget =
          _targetSliderLeft(_lastIndex, longCardWidth, sliderWidth, tabWidth);
      _cachedTargetLeft = newTarget;
      setState(() {}); // 触发重绘以更新 displayLeft
      _posController.forward(from: 0.0);
      widget.sliderKey.currentState?.triggerBounce();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final w2 = _cachedLongCardWidth ?? 0;
        if (w2 > 0) {
          setState(() => _animStart = _targetSliderLeft(_lastIndex, w2,
              w2 * 0.22, w2 / 4));
        }
      });
    }
  }

  bool _pendingLayout = false;

  double? _cachedLongCardWidth;
  // 上次计算的 targetLeft，供动画 listener 使用（避免零宽度调用）
  double _cachedTargetLeft = 0.0;

  @override
  void dispose() {
    _posController.dispose();
    super.dispose();
  }

  double _targetSliderLeft(int index, double longCardWidth, double sliderWidth, double tabWidth) {
    return (tabWidth * (index + 0.5) - sliderWidth * 0.5)
        .clamp(0.0, longCardWidth - sliderWidth);
  }

  @override
  Widget build(BuildContext context) {
    // 如果还有待处理的 tab 切换，等待 LayoutBuilder 下次触发
    if (_pendingLayout && !_layoutReady) {
      _pendingLayout = false;
    }
    return LiquidGlassCard(
      borderRadius: 26,
      blurSigmaX: 4, // 小幅降低模糊度，视觉更清晰
      blurSigmaY: 4,
      tintAlpha: 0.06,
      edgeGlowAlpha: 0.52,
      whiteFrameAlpha: 0.75,
      whiteFrameWidth: 1.6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final longCardWidth = constraints.maxWidth;
          _cachedLongCardWidth = longCardWidth;
          _layoutReady = true;
          final sliderWidth = longCardWidth * 0.22;
          final tabWidth = longCardWidth / 4;
          final targetLeft =
              _targetSliderLeft(widget.currentIndex, longCardWidth, sliderWidth, tabWidth);
          _cachedTargetLeft = targetLeft;
          // 首次 build 或动画已结束时，displayLeft = targetLeft
          final isFresh = !_posController.isAnimating && _posController.value == 0.0;
          final displayLeft = isFresh
              ? targetLeft
              : _animStart + (targetLeft - _animStart) * _posAnimation.value;
          return Stack(
            clipBehavior: Clip.none,
            // 滑动条在下层，Tab 文字在上层，避免文字被遮住；
            // Slider 纯视觉（IgnorePointer），命中测试交给 Tab
            children: [
              // 滑动条视觉层：IgnorePointer 包裹，不拦截命中
              Positioned(
                left: displayLeft,
                top: 4,
                child: IgnorePointer(
                  ignoring: true,
                  child: LiquidGlassSlider(
                    key: widget.sliderKey,
                    width: sliderWidth,
                    height: widget.height - 8,
                    cornerRadius: 26.0,
                    blurSigma: 6.0,
                  ),
                ),
              ),
              Row(
                children: [
                  _tabItem("考试", 0),
                  _tabItem("学习", 1),
                  _tabItem("通知", 2),
                  _tabItem("我的", 3),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _tabItem(String title, int index) {
    return Expanded(
      child: ConsumerTab(title: title, index: index),
    );
  }
}

class ConsumerTab extends StatefulWidget {
  final String title;
  final int index;
  const ConsumerTab({super.key, required this.title, required this.index});

  @override
  State<ConsumerTab> createState() => _ConsumerTabState();
}

class _ConsumerTabState extends State<ConsumerTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _pressAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _pressController.forward();
  void _onTapUp(_) => _pressController.reverse();
  void _onTapCancel() => _pressController.reverse();

  @override
  Widget build(BuildContext context) {
    final homeState = context.findAncestorStateOfType<_HomeState>();
    final isActive = homeState?.currentIndex == widget.index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () => homeState?.switchTab(widget.index),
      child: Stack(
        children: [
          // Press 高亮层：白色半透明光晕，从按下区域扩散
          AnimatedBuilder(
            animation: _pressAnim,
            builder: (context, child) {
              if (_pressAnim.value <= 0.0) return const SizedBox.shrink();
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      Colors.white.withValues(alpha: 0.18 * _pressAnim.value),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    stops: const [0.5, 1.0],
                  ),
                ),
              );
            },
          ),
          Center(
            child: Text(
              widget.title,
              style: TextStyle(
                fontSize: 16,
                color: isActive ? const Color(0xFF1890FF) : const Color(0xFF1A1A1A),
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
