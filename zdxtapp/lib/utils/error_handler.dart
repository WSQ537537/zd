import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 全局错误处理器（优化：统一错误处理和日志记录）
class ErrorHandler {
  /// 记录错误日志
  static void logError(String module, String message, [dynamic error, StackTrace? stackTrace]) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[ERROR][$timestamp][$module] $message');
    
    if (error != null) {
      debugPrint('[ERROR] 错误详情: $error');
    }
    
    if (stackTrace != null && kDebugMode) {
      debugPrint('[ERROR] 堆栈跟踪:\n$stackTrace');
    }
  }

  /// 显示用户友好的错误提示
  static void showUserError(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade400,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 处理API错误
  static String handleApiError(dynamic error) {
    if (error is Map<String, dynamic>) {
      // 后端返回的错误格式
      final msg = error['msg'] ?? error['message'] ?? '操作失败';
      return msg.toString();
    }
    
    if (error is Exception) {
      final msg = error.toString();
      
      // 网络超时
      if (msg.contains('TimeoutException') || msg.contains('timeout')) {
        return '网络超时，请检查网络连接';
      }
      
      // 连接错误
      if (msg.contains('SocketException') || msg.contains('Connection')) {
        return '网络连接失败，请检查网络';
      }
      
      // HTTP错误
      if (msg.contains('HTTP')) {
        return '服务器响应错误';
      }
      
      return '操作失败，请稍后重试';
    }
    
    return error?.toString() ?? '未知错误';
  }

  /// 验证用户输入
  static bool validateInput({
    String? value,
    String? fieldName,
    bool required = true,
    int? minLength,
    int? maxLength,
    Pattern? pattern,
    BuildContext? context,
  }) {
    if (required && (value == null || value.trim().isEmpty)) {
      final msg = '${fieldName ?? '此字段'}不能为空';
      if (context != null) showUserError(context, msg);
      return false;
    }
    
    if (value != null) {
      if (minLength != null && value.length < minLength) {
        final msg = '${fieldName ?? '此字段'}长度不能少于$minLength个字符';
        if (context != null) showUserError(context, msg);
        return false;
      }
      
      if (maxLength != null && value.length > maxLength) {
        final msg = '${fieldName ?? '此字段'}长度不能超过$maxLength个字符';
        if (context != null) showUserError(context, msg);
        return false;
      }
      
      if (pattern != null && !RegExp(pattern.toString()).hasMatch(value)) {
        final msg = '${fieldName ?? '此字段'}格式不正确';
        if (context != null) showUserError(context, msg);
        return false;
      }
    }
    
    return true;
  }

  /// 验证邮箱格式
  static bool validateEmail(String email, {BuildContext? context}) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      if (context != null) showUserError(context, '邮箱格式不正确');
      return false;
    }
    return true;
  }

  /// 验证手机号格式（中国大陆）
  static bool validatePhone(String phone, {BuildContext? context}) {
    final phoneRegex = RegExp(r'^1[3-9]\d{9}$');
    if (!phoneRegex.hasMatch(phone)) {
      if (context != null) showUserError(context, '手机号格式不正确');
      return false;
    }
    return true;
  }
}

/// 加载状态管理器（优化：统一loading管理）
class LoadingManager {
  static bool _isLoading = false;
  static BuildContext? _context;

  /// 初始化
  static void init(BuildContext context) {
    _context = context;
  }

  /// 显示加载
  static void show([String? message]) {
    if (_context == null || !_context!.mounted) return;
    
    showDialog(
      context: _context!,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: Text(message ?? '加载中...'),
              ),
            ],
          ),
        ),
      ),
    );
    
    _isLoading = true;
  }

  /// 隐藏加载
  static void hide() {
    if (_context == null || !_context!.mounted || !_isLoading) return;
    
    Navigator.of(_context!, rootNavigator: true).pop();
    _isLoading = false;
  }

  /// 是否在加载中
  static bool get isLoading => _isLoading;
}