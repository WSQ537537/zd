import 'package:flutter/material.dart';

/// UI 辅助工具类
/// 
/// 提供统一的视觉规范和通用组件
/// 用于全局页面风格统一
class UIHelpers {
  // ==================== 颜色规范 ====================
  
  /// 主题色 - 主蓝色
  static const Color primaryColor = Color(0xFF1890FF);
  
  /// 主题色 - 深蓝色
  static const Color secondaryColor = Color(0xFF096DD9);
  
  /// 成功色 - 绿色
  static const Color successColor = Color(0xFF52C41A);
  
  /// 警告色 - 黄色
  static const Color warningColor = Color(0xFFFAAD14);
  
  /// 错误色 - 红色
  static const Color errorColor = Color(0xFFFF4D4F);
  
  /// 背景色 - 浅灰
  static const Color bgColorLight = Color(0xFFF5F7FA);
  
  /// 背景色 - 白色
  static const Color bgColorWhite = Colors.white;
  
  /// 文字色 - 主文字
  static const Color textPrimary = Color(0xFF000000);
  
  /// 文字色 - 次要文字
  static const Color textSecondary = Color(0xFF666666);
  
  /// 文字色 - 提示文字
  static const Color textHint = Color(0xFF999999);
  
  // ==================== 圆角规范 ====================
  
  /// 小圆角 - 按钮、标签
  static const double radiusSmall = 8.0;
  
  /// 中圆角 - 卡片、输入框
  static const double radiusMedium = 12.0;
  
  /// 大圆角 - 大卡片、弹窗
  static const double radiusLarge = 16.0;
  
  /// 超大圆角 - 特殊卡片
  static const double radiusXLarge = 20.0;
  
  /// 胶囊形状
  static const double radiusRound = 99.0;
  
  // ==================== 间距规范 ====================
  
  /// 小内边距
  static const EdgeInsets paddingSmall = EdgeInsets.all(8.0);
  
  /// 中内边距
  static const EdgeInsets paddingMedium = EdgeInsets.all(12.0);
  
  /// 大内边距
  static const EdgeInsets paddingLarge = EdgeInsets.all(16.0);
  
  /// 超大内边距
  static const EdgeInsets paddingXLarge = EdgeInsets.all(20.0);
  
  /// 小外边距
  static const EdgeInsets marginSmall = EdgeInsets.only(bottom: 8.0);
  
  /// 中外边距
  static const EdgeInsets marginMedium = EdgeInsets.only(bottom: 12.0);
  
  /// 大外边距
  static const EdgeInsets marginLarge = EdgeInsets.only(bottom: 16.0);
  
  /// 超大外边距
  static const EdgeInsets marginXLarge = EdgeInsets.only(bottom: 20.0);
  
  // ==================== 字体规范 ====================
  
  /// 大标题
  static const TextStyle titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );
  
  /// 中标题
  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );
  
  /// 小标题
  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );
  
  /// 正文 - 正常
  static const TextStyle bodyNormal = TextStyle(
    fontSize: 14,
    color: textPrimary,
    height: 1.5,
  );
  
  /// 正文 - 小号
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    color: textSecondary,
    height: 1.4,
  );
  
  /// 按钮文字
  static const TextStyle buttonNormal = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
  
  // ==================== 通用组件 ====================
  
  /// 构建主题按钮（蓝色）
  static Widget buildPrimaryButton({
    required String text,
    required VoidCallback onPressed,
    bool fullWidth = true,
    double? width,
    EdgeInsets? padding,
  }) {
    return SizedBox(
      width: width ?? (fullWidth ? double.infinity : null),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: padding ?? const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
        ),
        child: Text(text, style: buttonNormal),
      ),
    );
  }
  
  /// 构建次要按钮（边框）
  static Widget buildSecondaryButton({
    required String text,
    required VoidCallback onPressed,
    bool fullWidth = true,
    double? width,
    EdgeInsets? padding,
  }) {
    return SizedBox(
      width: width ?? (fullWidth ? double.infinity : null),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: padding ?? const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
        ),
        child: Text(text, style: buttonNormal),
      ),
    );
  }
  
  /// 构建危险按钮（红色）
  static Widget buildDangerButton({
    required String text,
    required VoidCallback onPressed,
    bool fullWidth = true,
    double? width,
  }) {
    return SizedBox(
      width: width ?? (fullWidth ? double.infinity : null),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: errorColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
        ),
        child: Text(text, style: buttonNormal),
      ),
    );
  }
  
  /// 构建标准卡片
  static Widget buildStandardCard({
    required Widget child,
    double? width,
    EdgeInsets? padding,
    Color? color,
    bool hasShadow = true,
  }) {
    return Container(
      width: width,
      padding: padding ?? paddingLarge,
      decoration: BoxDecoration(
        color: color ?? bgColorWhite,
        borderRadius: BorderRadius.circular(radiusLarge),
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
  
  /// 构建标准输入框
  static Widget buildStandardInput({
    required String hint,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
    int? maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: textHint),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }
  
  /// 构建标准返回按钮（修复点击问题）
  static Widget buildBackButton({
    required BuildContext context,
    double top = 50,
    double left = 20,
    String? text,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // ✅ 必须设置，确保点击区域响应
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bgColorWhite,
            borderRadius: BorderRadius.circular(radiusMedium),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_back, size: 16, color: primaryColor),
              if (text != null) ...[
                const SizedBox(width: 4),
                Text(text, style: const TextStyle(color: primaryColor)),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  /// 构建加载指示器
  static Widget buildLoadingIndicator({
    String? message,
    Color? color,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(color ?? primaryColor),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: textSecondary),
            ),
          ],
        ],
      ),
    );
  }
  
  /// 构建空状态
  static Widget buildEmptyState({
    String? message,
    IconData? icon,
    double iconSize = 64,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon ?? Icons.inbox_outlined,
            size: iconSize,
            color: textHint,
          ),
          const SizedBox(height: 12),
          Text(
            message ?? '暂无数据',
            style: const TextStyle(
              color: textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建分隔线
  static Widget buildDivider({
    double height = 1,
    Color? color,
    EdgeInsets? margin,
  }) {
    return Container(
      height: height,
      margin: margin ?? const EdgeInsets.symmetric(vertical: 8),
      color: color ?? const Color(0xFFE8E8E8),
    );
  }
  
  /// 构建徽章（数字提示）
  static Widget buildBadge({
    required int count,
    Color? color,
    double size = 20,
  }) {
    if (count <= 0) return const SizedBox.shrink();
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? errorColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          count > 99 ? '99+' : count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
  
  /// 构建标签
  static Widget buildTag({
    required String text,
    Color? backgroundColor,
    Color? textColor,
    EdgeInsets? padding,
  }) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor ?? primaryColor,
          fontSize: 12,
        ),
      ),
    );
  }
}
