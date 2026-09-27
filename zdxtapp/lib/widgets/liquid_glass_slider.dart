import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// iOS 液态玻璃滑动指示器（微圆角矩形）—— v13
///
/// 效果层级（从下到上）：
///   ① BackdropFilter 磨砂（sigma=6，通透感强）
///   ② 半透明渐变基底（极低 alpha）
///   ③ 菲涅尔边缘圆滑丝光（径向渐变 + screen 混合）
///   ④ 顶部高光弧（极薄）
///   ⑤ 底部暗面内阴影
///   ⑥ 双层边缘描边（内亮边 + 外暗边，增强轮廓）
class LiquidGlassSlider extends StatefulWidget {
  final double width;
  final double height;
  final double cornerRadius;
  final double blurSigma;
  /// 是否忽略命中测试（作为纯视觉层时设为 true，不拦截下层 Tab 的点击）
  final bool ignorePointer;

  const LiquidGlassSlider({
    super.key,
    required this.width,
    required this.height,
    this.cornerRadius = 26.0,
    this.blurSigma = 6.0,
    this.ignorePointer = false,
  });

  @override
  LiquidGlassSliderState createState() => LiquidGlassSliderState();
}

class LiquidGlassSliderState extends State<LiquidGlassSlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeOutBack),
    );
    _bounceController.forward();
  }

  /// 触发指示器弹跳效果（每次切换到新 tab 调用）
  void triggerBounce() {
    _bounceController.reset();
    _bounceController.forward();
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget slider = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: widget.blurSigma,
                sigmaY: widget.blurSigma,
              ),
              child: Container(color: Colors.transparent),
            ),
            AnimatedBuilder(
              animation: _bounceAnimation,
              builder: (context, child) {
                final stretch = 1.0 + _bounceAnimation.value * 0.15;
                return Transform.scale(
                  scale: stretch,
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: Size(widget.width, widget.height),
                    painter: _LiquidGlassSliderPainter(
                      cornerRadius: widget.cornerRadius,
                      width: widget.width,
                      height: widget.height,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
    // 作为纯视觉层时忽略命中测试，让下层 Tab 手势可达
    if (widget.ignorePointer) {
      slider = IgnorePointer(child: slider);
    }
    return slider;
  }
}

class _LiquidGlassSliderPainter extends CustomPainter {
  final double cornerRadius;
  final double width;
  final double height;

  const _LiquidGlassSliderPainter({
    required this.cornerRadius,
    required this.width,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = width;
    final h = height;
    final r = cornerRadius;
    final tc = Colors.white;

    // ── ② 半透明基底渐变 ──
    final baseGrad = ui.Gradient.linear(
      Offset(w * 0.5, 0),
      Offset(w * 0.5, h),
      [
        tc.withValues(alpha: 0.04),
        tc.withValues(alpha: 0.10),
        tc.withValues(alpha: 0.04),
      ],
      [0.0, 0.5, 1.0],
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(0, 0, w, h, r, r),
      Paint()..shader = baseGrad,
    );

    // ── ③ 菲涅尔边缘丝光 ──
    final diag = math.sqrt(w * w + h * h);
    final fresnelGrad = ui.Gradient.radial(
      Offset(w * 0.5, h * 0.5),
      diag * 0.6,
      [
        tc.withValues(alpha: 0.0),
        tc.withValues(alpha: 0.0),
        tc.withValues(alpha: 0.20),
        tc.withValues(alpha: 0.42),
      ],
      [0.0, 0.55, 0.85, 1.0],
    );
    canvas.drawRRect(
      RRect.fromLTRBXY(0, 0, w, h, r, r),
      Paint()
        ..shader = fresnelGrad
        ..blendMode = BlendMode.screen,
    );

    // ── ④ 顶部高光弧（约 1px 高）──
    // 注：取消绘制顶部高光线，避免与外层 LiquidGlassCard 的高光边界产生割裂

    // ── ⑤ 底部暗面内阴影 ──
    canvas.save();
    canvas.clipRRect(RRect.fromLTRBXY(0, 0, w, h, r, r));
    final shadowGrad = ui.Gradient.radial(
      Offset(w * 0.5, h * 1.1),
      w * 0.7,
      [
        Colors.black.withValues(alpha: 0.06),
        Colors.black.withValues(alpha: 0.0),
      ],
      [0.0, 0.6],
    );
    canvas.drawRect(Rect.fromLTRB(0, h * 0.4, w, h), Paint()..shader = shadowGrad);
    canvas.restore();

    // ── ⑥ 双层边缘描边（内亮边 + 外暗边）──
    // 外暗边
    canvas.drawRRect(
      RRect.fromLTRBXY(-0.5, -0.5, w + 0.5, h + 0.5, r + 0.5, r + 0.5),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    // 内亮边
    canvas.drawRRect(
      RRect.fromLTRBXY(0.5, 0.5, w - 1.0, h - 1.0, r - 0.5, r - 0.5),
      Paint()
        ..color = tc.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassSliderPainter oldDelegate) =>
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.width != width ||
      oldDelegate.height != height;
}
