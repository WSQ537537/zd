import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// iOS 风格液态玻璃卡片（单层 CustomPaint 实现）
///
/// 命中测试策略：
/// - 视觉层（BackdropFilter / 两个 CustomPaint）全部 [IgnorePointer] 包裹，
///   仅负责渲染，不拦截命中；
/// - 命中测试完全交给 [child] 处理，卡片背景区域由 child 自行决定是否响应。
/// 这样底部导航长卡片内部的 Tab GestureDetector 可以直接接收点击。
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigmaX;
  final double blurSigmaY;
  final Color tintColor;
  final double tintAlpha;
  final double edgeGlowAlpha;
  final double whiteFrameAlpha;
  final double whiteFrameWidth;

  const LiquidGlassCard({
    super.key,
    this.child = const SizedBox.shrink(),
    this.borderRadius = 28,
    this.blurSigmaX = 6,
    this.blurSigmaY = 6,
    this.tintColor = Colors.white,
    this.tintAlpha = 0.06,
    this.edgeGlowAlpha = 0.52,
    this.whiteFrameAlpha = 0.0,
    this.whiteFrameWidth = 1.4,
  });

  @override
  Widget build(BuildContext context) {
    // 🔥 拆分绘制：白色包裹线独立置顶，避免被菲涅尔边缘光 / 高斯磨砂稀释而不可见
    final hasWhiteFrame = whiteFrameAlpha > 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // 命中测试由 child 完全接管；BackdropFilter 只负责视觉渲染
          IgnorePointer(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: blurSigmaX,
                sigmaY: blurSigmaY,
              ),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          // 液态玻璃基底（磨砂 + 菲涅尔 + 顶部高光 + 内描边）—— 纯视觉
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _LiquidGlassPainter(
                borderRadius: borderRadius,
                tintAlpha: tintAlpha,
                edgeGlowAlpha: edgeGlowAlpha,
                whiteFrameAlpha: hasWhiteFrame ? 0.0 : whiteFrameAlpha,
                whiteFrameWidth: whiteFrameWidth,
              ),
            ),
          ),
          child,
          // 🔥 白色包裹线：在 child 之上、最顶层绘制，确保清晰可见 —— 纯视觉
          if (hasWhiteFrame)
            IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: _WhiteFramePainter(
                  borderRadius: borderRadius,
                  whiteFrameAlpha: whiteFrameAlpha,
                  whiteFrameWidth: whiteFrameWidth,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiquidGlassPainter extends CustomPainter {
  final double borderRadius;
  final double tintAlpha;
  final double edgeGlowAlpha;
  final double whiteFrameAlpha;
  final double whiteFrameWidth;

  const _LiquidGlassPainter({
    required this.borderRadius,
    required this.tintAlpha,
    required this.edgeGlowAlpha,
    this.whiteFrameAlpha = 0.0,
    this.whiteFrameWidth = 1.4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = borderRadius;
    final tc = Colors.white;

    // ── a. 半透明基底渐变 ──
    final baseGrad = ui.Gradient.linear(
      Offset(w * 0.5, 0),
      Offset(w * 0.5, h),
      [
        tc.withValues(alpha: (tintAlpha * 0.5).clamp(0.0, 1.0)),
        tc.withValues(alpha: tintAlpha),
        tc.withValues(alpha: (tintAlpha * 0.5).clamp(0.0, 1.0)),
      ],
      [0.0, 0.5, 1.0],
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(0, 0, w, h, r, r),
      Paint()..shader = baseGrad,
    );

    // ── b. 菲涅尔边缘丝光 ──
    final diag = math.sqrt(w * w + h * h);
    final fresnelGrad = ui.Gradient.radial(
      Offset(w * 0.5, h * 0.5),
      diag * 0.6,
      [
        tc.withValues(alpha: 0.0),
        tc.withValues(alpha: 0.0),
        tc.withValues(alpha: edgeGlowAlpha * 0.4),
        tc.withValues(alpha: edgeGlowAlpha),
      ],
      [0.0, 0.55, 0.85, 1.0],
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(0, 0, w, h, r, r),
      Paint()
        ..shader = fresnelGrad
        ..blendMode = BlendMode.screen,
    );

    // ── c. 顶部高光弧（约 1px 高）──
    final highlightAlpha = (edgeGlowAlpha * 0.6).clamp(0.0, 1.0);
    final highlightGrad = ui.Gradient.linear(
      Offset(w * 0.1, 0),
      Offset(w * 0.9, 0),
      [
        tc.withValues(alpha: 0.0),
        tc.withValues(alpha: highlightAlpha),
        tc.withValues(alpha: 0.0),
      ],
      [0.0, 0.5, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTRB(w * 0.1, 0.5, w * 0.9, 1.5),
      Paint()..shader = highlightGrad,
    );

    // ── d. 边缘描边 ──
    final edgeAlpha = (edgeGlowAlpha * 0.35).clamp(0.0, 1.0);
    final edgePaint = Paint()
      ..color = tc.withValues(alpha: edgeAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRRect(
      RRect.fromLTRBXY(0.25, 0.25, w - 0.5, h - 0.5, r, r),
      edgePaint,
    );

    // ── e. 高光白外框（可选：白亮外描边，增强卡片轮廓）──
    if (whiteFrameAlpha > 0.0) {
      final framePaint = Paint()
        ..color = tc.withValues(alpha: whiteFrameAlpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = whiteFrameWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.5, 0.5, w - 1.0, h - 1.0),
          Radius.circular(math.max(0.0, r - 0.5)),
        ),
        framePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter oldDelegate) =>
      oldDelegate.tintAlpha != tintAlpha ||
      oldDelegate.edgeGlowAlpha != edgeGlowAlpha ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.whiteFrameAlpha != whiteFrameAlpha ||
      oldDelegate.whiteFrameWidth != whiteFrameWidth;
}

/// 🔥 独立绘制白色包裹线（置顶，避免被磨砂/菲涅尔稀释）
class _WhiteFramePainter extends CustomPainter {
  final double borderRadius;
  final double whiteFrameAlpha;
  final double whiteFrameWidth;

  const _WhiteFramePainter({
    required this.borderRadius,
    required this.whiteFrameAlpha,
    required this.whiteFrameWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = borderRadius;
    if (w <= 0 || h <= 0) return;

    // 外圈微光（增强"包裹"立体感）
    final glowAlpha = (whiteFrameAlpha * 0.35).clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-1.0, -1.0, w + 2.0, h + 2.0),
        Radius.circular(math.max(0.0, r + 1.0)),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: glowAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = whiteFrameWidth + 1.0
        ..strokeCap = StrokeCap.round,
    );

    // 主白色包裹线（清晰、高不透明度）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.5, 0.5, w - 1.0, h - 1.0),
        Radius.circular(math.max(0.0, r - 0.5)),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: whiteFrameAlpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = whiteFrameWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WhiteFramePainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.whiteFrameAlpha != whiteFrameAlpha ||
      oldDelegate.whiteFrameWidth != whiteFrameWidth;
}

/// 蓝色磨砂 AI 按钮（双层描边 + 菲涅尔蓝光 + Press 高亮反馈）
class TranslucentBlueButton extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigmaX;
  final double blurSigmaY;
  final double opacity;

  const TranslucentBlueButton({
    super.key,
    this.child = const SizedBox.shrink(),
    this.borderRadius = 28,
    this.blurSigmaX = 14,
    this.blurSigmaY = 14,
    this.opacity = 0.30,
  });

  @override
  State<TranslucentBlueButton> createState() => _TranslucentBlueButtonState();
}

class _TranslucentBlueButtonState extends State<TranslucentBlueButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
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
    // 按下时叠加一层亮蓝色高光，opacity 0→0.28
    final pressedOverlay = AnimatedOpacity(
      opacity: _pressAnim.value * 0.28,
      duration: const Duration(milliseconds: 120),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0x001E6AFF),
                const Color(0x441E6AFF),
                const Color(0x001E6AFF),
              ],
            ),
          ),
        ),
      ),
    );
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 蓝色磨砂层（与长卡片同一液态玻璃体系）
            // 增强磨砂质感：提高基底透明度（降低透明度 = 提高不透明填充），
            // 让背景文字/画面被磨砂填充柔和遮罩，避免文字穿透干扰
            BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: widget.blurSigmaX,
                sigmaY: widget.blurSigmaY,
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0x331E6AFF),
                      const Color(0x551E6AFF),
                      const Color(0x331E6AFF),
                    ],
                  ),
                ),
              ),
            ),
            // Press 高亮层（与磨砂层独立，不干扰其他动画）
            pressedOverlay,
            // 双层描边（press 时同步增强）
            CustomPaint(
              painter: _BlueEdgePainter(
                opacity: widget.opacity + _pressAnim.value * 0.25,
                borderRadius: widget.borderRadius,
              ),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _BlueEdgePainter extends CustomPainter {
  final double opacity;
  final double borderRadius;
  const _BlueEdgePainter({required this.opacity, this.borderRadius = 28});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // 圆形按钮：圆角半径取短边一半；圆角矩形：用传入的 borderRadius
    final isCircle = borderRadius >= (math.min(w, h) / 2.0) - 1.0;
    final r = isCircle ? math.min(w, h) / 2.0 : borderRadius;

    // 外暗边：略扩散，营造厚度感
    final outerAlpha = (opacity * 0.9).clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromLTRBXY(-0.5, -0.5, w + 0.5, h + 0.5, r + 0.5, r + 0.5),
      Paint()
        ..color = const Color(0x301E6AFF).withValues(alpha: outerAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // 内亮边：主轮廓，与长卡片白色边缘光对标
    final innerAlpha = (opacity * 1.2).clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromLTRBXY(0.5, 0.5, w - 1.0, h - 1.0, r - 0.5, r - 0.5),
      Paint()
        ..color = const Color(0x88AACCFF).withValues(alpha: innerAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant _BlueEdgePainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}
