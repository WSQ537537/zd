import 'package:flutter/material.dart';

/// 骨架屏基础组件：单个带流光动画的矩形块
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + _controller.value * 2, 0),
              end: Alignment(1.0 + _controller.value * 2, 0),
              colors: const [
                Color(0xFFE3F2FD),
                Color(0xFFBBDEFB),
                Color(0xFFE3F2FD),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// 通知卡片骨架屏（用于 system + department 两栏）
class NoticeCardShimmer extends StatelessWidget {
  const NoticeCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 系统通知区域
          Expanded(
            flex: 1,
            child: _buildSection(),
          ),
          const Divider(height: 1, color: Colors.black12),
          // 学习通知区域
          Expanded(
            flex: 1,
            child: _buildSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const ShimmerBox(width: 80, height: 18, borderRadius: 4),
              const ShimmerBox(width: 32, height: 18, borderRadius: 12),
            ],
          ),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 8),
          // 通知条目占位
          Expanded(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const ShimmerBox(width: 8, height: 8, borderRadius: 4),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          ShimmerBox(width: double.infinity, height: 14, borderRadius: 4),
                          SizedBox(height: 6),
                          ShimmerBox(width: 120, height: 12, borderRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const ShimmerBox(width: 72, height: 32, borderRadius: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 视频列表骨架屏
class VideoListShimmer extends StatelessWidget {
  const VideoListShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 100),
      itemCount: 5,
      itemBuilder: (_, i) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const ShimmerBox(width: 36, height: 36, borderRadius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerBox(width: double.infinity, height: 14, borderRadius: 4),
                  SizedBox(height: 6),
                  ShimmerBox(width: 160, height: 12, borderRadius: 4),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const ShimmerBox(width: 28, height: 28, borderRadius: 8),
          ],
        ),
      ),
    );
  }
}

/// 考试列表骨架屏
class ExamListShimmer extends StatelessWidget {
  const ExamListShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 75),
      children: List.generate(4, (_) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: ShimmerBox(width: double.infinity, height: 16, borderRadius: 4),
                  ),
                  const ShimmerBox(width: 60, height: 22, borderRadius: 12),
                ],
              ),
              const SizedBox(height: 10),
              const ShimmerBox(width: 180, height: 12, borderRadius: 4),
              const SizedBox(height: 8),
              const ShimmerBox(width: 120, height: 12, borderRadius: 4),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    ShimmerBox(width: 60, height: 14, borderRadius: 4),
                    SizedBox(width: 12),
                    ShimmerBox(width: 80, height: 36, borderRadius: 18),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}