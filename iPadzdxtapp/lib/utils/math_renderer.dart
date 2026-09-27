import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// 数学公式渲染工具类
/// 支持 LaTeX 公式的纯原生离线渲染，具备强大的容错和自动修复能力
class MathRenderer {
  /// 数学关键字列表，用于自动识别公式
  static const List<String> _mathKeywords = [
    r'\begin', r'\end', r'\frac', r'\sqrt', r'\sum', r'\int', r'\lim',
    r'\alpha', r'\beta', r'\gamma', r'\delta', r'\epsilon', r'\theta',
    r'\lambda', r'\mu', r'\pi', r'\sigma', r'\phi', r'\omega',
    '^', '_', '=', '<', '>', r'\leq', r'\geq', r'\neq', r'\approx',
    r'\infty', r'\partial', r'\nabla', r'\times', r'\div', r'\pm', r'\mp'
  ];

  /// 检测文本中是否包含 LaTeX 公式（增强版）
  static bool hasMathFormula(String? text) {
    if (text == null || text.isEmpty) return false;

    // 1. 检测标准公式格式
    if (text.contains(RegExp(r'\$\$[\s\S]*?\$\$|\$[^$]+\$', multiLine: true))) {
      return true;
    }

    // 2. 检测数学关键字（自动识别无包裹符的公式）
    for (var keyword in _mathKeywords) {
      if (text.contains(keyword)) {
        return true;
      }
    }

    // 3. 检测常见的数学符号模式
    if (text.contains(RegExp(r'[a-zA-Z0-9]\^[a-zA-Z0-9]')) || // x^2
        text.contains(RegExp(r'[a-zA-Z0-9]_[a-zA-Z0-9]')) || // x_1
        text.contains(r'\frac') ||
        text.contains(r'\sqrt')) {
      return true;
    }

    return false;
  }

  /// 渲染包含数学公式的文本（增强版）
  /// 自动识别并混合渲染普通文本和 LaTeX 公式，支持多行公式和自动修复
  static Widget renderMathText(
    String? text, {
    TextStyle? textStyle,
    double fontSize = 14,
    Color? color,
    TextAlign textAlign = TextAlign.left,
  }) {
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }

    // 预处理文本：标准化和自动修复
    final processedText = _preprocessAndFixText(text);

    // 如果不包含公式，直接返回普通文本
    if (!hasMathFormula(processedText)) {
      return Text(
        processedText,
        style: textStyle ?? TextStyle(fontSize: fontSize, color: color),
        textAlign: textAlign,
      );
    }

    // 包含公式，使用富文本渲染
    return _renderRichMathText(
      processedText,
      textStyle: textStyle,
      fontSize: fontSize,
      color: color,
      textAlign: textAlign,
    );
  }

  /// 文本预处理和自动修复
  static String _preprocessAndFixText(String text) {
    String result = text;

    // 1. 标准化换行符
    result = result.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 2. 清理HTML实体编码
    result = result.replaceAll(RegExp(r'&#(\d+);'), '');
    result = result.replaceAll('&nbsp;', ' ');
    result = result.replaceAll('&lt;', '<');
    result = result.replaceAll('&gt;', '>');
    result = result.replaceAll('&amp;', '&');
    result = result.replaceAll('&quot;', '"');
    result = result.replaceAll('&#39;', "'");

    // 3. 清理多余空格（保留单个空格）
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    // 4. 解码Unicode转义字符
    result = _decodeUnicodeEscapes(result);

    // 5. 特殊字符转换为LaTeX
    result = _convertSpecialCharsToLatex(result);

    // 6. 自动补全公式包裹符
    result = _autoWrapFormulas(result);

    // 7. 修复残缺语法
    result = _fixIncompleteSyntax(result);

    // 8. 处理多行公式环境
    result = _handleMultiLineEnvironments(result);

    return result.trim();
  }

  /// 解码Unicode转义字符
  static String _decodeUnicodeEscapes(String text) {
    return text.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (match) {
        try {
          final codePoint = int.parse(match.group(1)!, radix: 16);
          return String.fromCharCode(codePoint);
        } catch (e) {
          return match.group(0)!;
        }
      },
    );
  }

  /// 特殊字符转换为LaTeX
  static String _convertSpecialCharsToLatex(String text) {
    String result = text;

    // 平方、立方符号
    result = result.replaceAll('²', '^{2}');
    result = result.replaceAll('³', '^{3}');

    // 根号
    result = result.replaceAllMapped(
      RegExp(r'√([a-zA-Z0-9]+)'),
      (match) => '\\sqrt{${match.group(1)}}',
    );
    result = result.replaceAll('√', '\\sqrt{}');

    // 乘除号
    result = result.replaceAll('×', '\\times ');
    result = result.replaceAll('÷', '\\div ');

    // 分数格式 (a/b) → \frac{a}{b}
    result = result.replaceAllMapped(
      RegExp(r'\(([^/]+)/([^)]+)\)'),
      (match) => '\\frac{${match.group(1)}}{${match.group(2)}}',
    );

    return result;
  }

  /// 自动补全公式包裹符
  static String _autoWrapFormulas(String text) {
    // 如果已经包含标准公式格式，直接返回
    if (text.contains(RegExp(r'\$\$[\s\S]*?\$\$|\$[^$]+\$', multiLine: true))) {
      return text;
    }

    // 检测是否包含数学内容但没有包裹符
    bool hasMathContent = false;
    for (var keyword in _mathKeywords) {
      if (text.contains(keyword)) {
        hasMathContent = true;
        break;
      }
    }

    // 如果包含数学内容但没有包裹符，自动添加行内公式包裹符
    if (hasMathContent && !text.contains('\$')) {
      // 简单策略：如果整个文本看起来像公式，用块级公式；否则用行内公式
      if (_looksLikeBlockFormula(text)) {
        return '\$\$$text\$\$';
      } else {
        return '\$$text\$';
      }
    }

    return text;
  }

  /// 判断文本是否看起来像块级公式
  static bool _looksLikeBlockFormula(String text) {
    // 包含多行环境
    if (text.contains(r'\begin{') ||
        text.contains(r'\end{') ||
        text.contains('\\\\') ||
        text.contains('&')) {
      return true;
    }

    // 包含复杂的数学结构
    if (text.contains(r'\frac') && text.contains('\n') ||
        text.contains(r'\sqrt') && text.contains('=') ||
        text.length > 50) {
      return true;
    }

    return false;
  }

  /// 修复残缺语法
  static String _fixIncompleteSyntax(String text) {
    String result = text;

    // 修复上下标缺少大括号的情况：x^2 → x^{2}, x_1 → x_{1}
    result = result.replaceAllMapped(
      RegExp(r'(\^|_)([a-zA-Z0-9])'),
      (match) => '${match.group(1)}{${match.group(2)}}',
    );

    // 修复分式语法：\frac a b → \frac{a}{b}
    result = result.replaceAllMapped(
      RegExp(r'\\frac\s+([a-zA-Z0-9]+)\s+([a-zA-Z0-9]+)'),
      (match) => '\\frac{${match.group(1)}}{${match.group(2)}}',
    );

    // 清理多余的LaTeX包裹符
    result = result.replaceAll(RegExp(r'\\\('), '');
    result = result.replaceAll(RegExp(r'\\\)'), '');
    result = result.replaceAll(RegExp(r'\\\['), '');
    result = result.replaceAll(RegExp(r'\\\]'), '');

    return result;
  }

  /// 处理多行公式环境
  static String _handleMultiLineEnvironments(String text) {
    String result = text;

    // 处理 cases 环境
    result = result.replaceAllMapped(
      RegExp(r'\\begin\{cases\}([\s\S]*?)\\end\{cases\}'),
      (match) {
        String content = match.group(1) ?? '';
        // 确保 cases 内容中的换行符正确
        content = content.replaceAll('\\\\', '\\\\');
        return '\\begin{cases}$content\\end{cases}';
      },
    );

    // 处理 align 环境
    result = result.replaceAllMapped(
      RegExp(r'\\begin\{align\*\}([\s\S]*?)\\end\{align\*\}'),
      (match) {
        String content = match.group(1) ?? '';
        // 确保 align 内容中的换行符正确
        content = content.replaceAll('\\\\', '\\\\');
        return '\\begin{align*}$content\\end{align*}';
      },
    );

    // 处理多行公式中的换行
    if (result.contains('\\\\') && !result.contains(r'\begin{')) {
      // 如果有换行但没有环境包裹，自动添加 align* 环境
      if (result.startsWith('\$\$') && result.endsWith('\$\$')) {
        String inner = result.substring(2, result.length - 2);
        if (inner.contains('\\\\')) {
          return '\$\$\\begin{align*}$inner\\end{align*}\$\$';
        }
      }
    }

    return result;
  }

  /// 内部方法：渲染富文本（混合普通文本和公式）
  static Widget _renderRichMathText(
    String text, {
    TextStyle? textStyle,
    double fontSize = 14,
    Color? color,
    TextAlign textAlign = TextAlign.left,
  }) {
    final defaultStyle = textStyle ?? TextStyle(fontSize: fontSize, color: color);

    // 尝试提取块级公式 $$...$$
    final blockFormulaRegex = RegExp(r'\$\$([\s\S]*?)\$\$', multiLine: true);
    final matches = blockFormulaRegex.allMatches(text).toList();

    if (matches.isNotEmpty) {
      // 有块级公式，分段渲染
      return Column(
        crossAxisAlignment: textAlign == TextAlign.center
            ? CrossAxisAlignment.center
            : textAlign == TextAlign.right
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
        children: _splitAndRenderBlocks(text, defaultStyle),
      );
    }

    // 只有行内公式 $...$
    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: _splitAndRenderInline(text, defaultStyle),
    );
  }

  /// 分割并渲染块级公式
  static List<Widget> _splitAndRenderBlocks(String text, TextStyle style) {
    final widgets = <Widget>[];
    final blockFormulaRegex = RegExp(r'\$\$([\s\S]*?)\$\$', multiLine: true);

    int lastEnd = 0;
    for (final match in blockFormulaRegex.allMatches(text)) {
      // 添加公式前的普通文本
      if (match.start > lastEnd) {
        final plainText = text.substring(lastEnd, match.start);
        if (plainText.trim().isNotEmpty) {
          widgets.add(Text(
            plainText.trim(),
            style: style,
            softWrap: true,
            overflow: TextOverflow.visible,
          ));
        }
      }

      // 渲染块级公式
      final formula = match.group(1)?.trim() ?? '';
      if (formula.isNotEmpty) {
        widgets.add(_buildMathWidget(formula, style.copyWith(fontSize: style.fontSize! * 1.2)));
      }

      lastEnd = match.end;
    }

    // 添加剩余的普通文本
    if (lastEnd < text.length) {
      final remainingText = text.substring(lastEnd).trim();
      if (remainingText.isNotEmpty) {
        widgets.add(Text(
          remainingText,
          style: style,
          softWrap: true,
          overflow: TextOverflow.visible,
        ));
      }
    }

    return widgets;
  }

  /// 分割并渲染行内公式
  static List<Widget> _splitAndRenderInline(String text, TextStyle style) {
    final widgets = <Widget>[];
    final inlineFormulaRegex = RegExp(r'\$([^$]+)\$');

    int lastEnd = 0;
    for (final match in inlineFormulaRegex.allMatches(text)) {
      // 添加公式前的普通文本
      if (match.start > lastEnd) {
        final plainText = text.substring(lastEnd, match.start);
        if (plainText.isNotEmpty) {
          widgets.add(Text(
            plainText,
            style: style,
            softWrap: true,
            overflow: TextOverflow.visible,
          ));
        }
      }

      // 渲染行内公式
      final formula = match.group(1)?.trim() ?? '';
      if (formula.isNotEmpty) {
        widgets.add(_buildMathWidget(formula, style, mathStyle: MathStyle.text));
      }

      lastEnd = match.end;
    }

    // 添加剩余的普通文本
    if (lastEnd < text.length) {
      final remainingText = text.substring(lastEnd);
      if (remainingText.isNotEmpty) {
        widgets.add(Text(
          remainingText,
          style: style,
          softWrap: true,
          overflow: TextOverflow.visible,
        ));
      }
    }

    return widgets.isEmpty ? [Text(text, style: style, softWrap: true, overflow: TextOverflow.visible)] : widgets;
  }

  /// 构建数学公式组件，包含错误处理
  static Widget _buildMathWidget(String formula, TextStyle style, {MathStyle mathStyle = MathStyle.display}) {
    try {
      final mathWidget = Math.tex(
        formula,
        mathStyle: mathStyle,
        textStyle: style,
      );

      final breakResult = mathWidget.texBreak(enforceNoBreak: false);
      if (breakResult.parts.length > 1) {
        return Wrap(
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 0,
          runSpacing: 0,
          children: breakResult.parts.map((part) => _buildMathChunk(part, style)).toList(),
        );
      }

      return _buildMathChunk(mathWidget, style);
    } catch (e) {
      // 捕获任何异常，返回原始文本
      return Text(
        '\$$formula\$',
        style: style,
        softWrap: true,
        overflow: TextOverflow.visible,
      );
    }
  }

  static Widget _buildMathChunk(Math mathWidget, TextStyle style) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite) {
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: mathWidget,
            ),
          );
        }
        return mathWidget;
      },
    );
  }

  /// 仅渲染纯公式（不包含普通文本）
  static Widget renderPureFormula(
    String formula, {
    TextStyle? textStyle,
    double fontSize = 16,
    Color? color,
  }) {
    final style = textStyle ?? TextStyle(fontSize: fontSize, color: color);
    return _buildMathWidget(formula, style);
  }
}
