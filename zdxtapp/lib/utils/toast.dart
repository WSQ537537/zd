import 'package:flutter/material.dart';

/// 显示屏幕中间的Toast提示
class ToastUtil {
  static OverlayEntry? _currentOverlay;
  
  /// 显示简短的Toast消息（屏幕中间）
  static void show(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    // 防护：context 所属页面可能已在 async 回调前销毁
    if (!context.mounted) return;

    // 移除之前的overlay
    _currentOverlay?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);

    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.4,
        left: 0,
        right: 0,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
    _currentOverlay = entry;

    overlay.insert(entry);

    // 仅当仍指向自己时移除，避免连续 toast 时旧回调误删新 toast
    Future.delayed(duration, () {
      if (_currentOverlay == entry) {
        entry.remove();
        _currentOverlay = null;
      }
    });
  }
  
  /// 显示成功提示
  static void showSuccess(BuildContext context, String message) {
    show(context, '✓ $message');
  }
  
  /// 显示错误提示
  static void showError(BuildContext context, String message) {
    show(context, '✗ $message', duration: const Duration(seconds: 3));
  }
}
