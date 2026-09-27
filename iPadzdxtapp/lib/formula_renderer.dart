import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// 全链路优化重构的公式渲染器 - iPad平板端适配版
/// 
/// 核心原则：
/// 1. 最小干预原则 - 只处理必要的编码转换，不清理空格，不破坏LaTeX语法
/// 2. 布局控制分离 - 通用公式解析模块只负责解析渲染，布局控制由调用方页面自行处理
/// 3. 单次处理原则 - 确保每个数据只被预处理一次
/// 4. 完整性保护 - 保持块级公式完整性不被拆分
/// 5. 🔥 智能公式识别 - 优先匹配 $$...$$，再匹配 $...$，避免误判
/// 
/// 🔥 平板端适配说明：
/// 本文件参考手机端zdxtapp的formula_renderer.dart实现，
/// 完全复用手机端的公式渲染逻辑，确保渲染一致性
class FormulaRenderer {
  // ==================== 主入口方法 ====================
  
  /// 渲染混合文本：支持 $...$、$$...$$
  /// 
  /// 参数说明：
  /// - text: 待渲染的文本内容
  /// - style: 基础文本样式（会被公式继承）
  /// - autoWrapLatex: 是否自动包裹未包裹的 LaTeX 公式（默认 false，避免双重处理）
  /// 
  /// 返回值：Widget，可直接嵌入Flutter UI树
  static Widget renderMixedText(String text, {TextStyle? style, bool autoWrapLatex = false}) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final baseStyle = (style ?? const TextStyle(fontSize: 14)).copyWith(
      color: style?.color ?? Colors.black,
    );

    // 🔥 核心修复1：基础预处理（只做必要转换，不破坏LaTeX语法）
    String processed = _basicPreprocess(text);
    
    // 🔥 核心修复2：如果需要，自动包裹未包裹的 LaTeX 公式
    if (autoWrapLatex) {
      processed = _wrapAndFormatLatex(processed);
    }

    // 🔥 核心修复3：先检查块级公式 $$...$$（优先级更高）
    final blockRegex = RegExp(r'\$\$([\s\S]*?)\$\$', multiLine: true, dotAll: true);
    if (blockRegex.hasMatch(processed)) {
      return _renderMixedTextWithBlockFormulas(processed, baseStyle);
    }

    // 🔥 核心修复3：再检查行内公式 $...$
    // 🔥 关键修复：使用更精确的正则，避免匹配到单独的$符号
    final inlineRegex = RegExp(r'(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)', dotAll: true);
    if (inlineRegex.hasMatch(processed)) {
      return _renderMixedTextInternal(processed, baseStyle);
    }

    // 如果没有发现已包裹的公式，直接返回文本
    // 🔥 关键修复：必须设置完整的换行属性
    return Text(
      processed, 
      style: baseStyle, 
      softWrap: true,              // ✅ 允许自动换行
      maxLines: null,              // ✅ 允许无限行数
      textWidthBasis: TextWidthBasis.parent,  // ✅ 使用父容器宽度作为换行基准
      overflow: TextOverflow.visible,         // ✅ 确保内容可见
    );
  }

  /// AI消息专用渲染方法（支持流式输出）
  /// 
  /// 🔥 核心修复：移除所有高度限制，让气泡根据内容自动调整高度
  /// 
  /// 参数说明：
  /// - text: AI回复的文本内容
  /// - baseStyle: 基础文本样式
  /// - isStreaming: 是否正在流式输出（影响渲染策略）
  static Widget renderAIMessage(
    String? text, {
    required TextStyle baseStyle, 
    bool isStreaming = false,
  }) {
    final content = (text ?? '').toString();
    
    // 🔥 核心修复：直接使用 renderMixedText，不使用 ConstrainedBox 限制高度
    // 让气泡根据内容自然流动，避免内容溢出
    return renderMixedText(content, style: baseStyle);
  }

  // ==================== 内部渲染方法 ====================

  /// 渲染包含行内公式的混合文本
  /// 
  /// 策略：将文本按 $...$ 分割，普通文本用TextSpan，公式用WidgetSpan
  static Widget _renderMixedTextInternal(String text, TextStyle style) {
    // 🔥 核心修复：使用更精确的正则表达式，避免误匹配
    // (?<!\$) 确保前面不是$，(?!\$) 确保后面不是$
    final inlineRegex = RegExp(r'(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)', dotAll: true);
    final matches = inlineRegex.allMatches(text).toList();
    
    // 如果没有找到公式，直接返回文本
    if (matches.isEmpty) {
      return Text(
        text, 
        style: style,
        softWrap: true, 
        maxLines: null, 
        textWidthBasis: TextWidthBasis.parent,
        overflow: TextOverflow.visible,
      );
    }

    final spans = <InlineSpan>[];
    int lastIndex = 0;
    
    for (final m in matches) {
      // 添加公式前的普通文本
      if (m.start > lastIndex) {
        final plainText = text.substring(lastIndex, m.start);
        if (plainText.isNotEmpty) {
          spans.add(TextSpan(text: plainText, style: style));
        }
      }
      
      // 提取公式内容（去除$符号）
      final formula = m.group(1)?.trim();
      if (formula != null && formula.isNotEmpty) {
        spans.add(
          WidgetSpan(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _renderInlineFormula(formula, style: style),
            ),
            alignment: PlaceholderAlignment.baseline, // 🔥 修复：使用 baseline 让公式更好地融入文本流
            baseline: TextBaseline.alphabetic,
          ),
        );
      }
      
      lastIndex = m.end;
    }
    
    // 添加剩余的文本
    if (lastIndex < text.length) {
      final remainingText = text.substring(lastIndex);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(text: remainingText, style: style));
      }
    }
    
    // 🔥 关键修复：RichText必须设置完整的换行属性
    return RichText(
      text: TextSpan(children: spans), 
      softWrap: true,              // ✅ 允许自动换行
      maxLines: null,              // ✅ 允许无限行数
      textWidthBasis: TextWidthBasis.parent,  // ✅ 使用父容器宽度作为换行基准
      overflow: TextOverflow.visible,         // ✅ 确保内容可见
    );
  }

  /// 处理包含块级公式 $$...$$ 的混合文本
  /// 
  /// 🔥 核心修复：将块级公式转换为行内公式渲染，避免布局问题
  /// 原因：exampublish 预览页做了这个转换，但只影响显示，不影响数据库
  /// 其他页面从数据库读取的数据仍包含 $$...$$，需要统一转换
  static Widget _renderMixedTextWithBlockFormulas(String text, TextStyle style) {
    final List<InlineSpan> spans = [];
    int lastIndex = 0;
    
    // 🔥 核心修复：使用正则表达式同时匹配块级和行内公式
    // 优先匹配 $$...$$，再匹配 $...$
    final formulaRegex = RegExp(
      r'\$\$([\s\S]*?)\$\$|(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)', 
      multiLine: true, 
      dotAll: true,
    );
    final matches = formulaRegex.allMatches(text);
    
    for (final match in matches) {
      // 添加公式前的普通文本
      if (match.start > lastIndex) {
        final plainText = text.substring(lastIndex, match.start);
        if (plainText.isNotEmpty) {
          spans.add(TextSpan(text: plainText, style: style));
        }
      }
      
      // 处理公式
      final String? blockFormula = match.group(1); // $$...$$ 的内容
      final String? inlineFormula = match.group(2); // $...$ 的内容
      
      if (blockFormula != null) {
        // 🔥 核心修复：将块级公式作为行内公式渲染，而不是独立块
        // 这样可以确保公式和文字在同一行，避免布局问题
        final formula = blockFormula.trim();
        if (formula.isNotEmpty) {
          spans.add(
            WidgetSpan(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _renderInlineFormula(formula, style: style),
              ),
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
            ),
          );
        }
      } else if (inlineFormula != null) {
        // 行内公式
        final formula = inlineFormula.trim();
        if (formula.isNotEmpty) {
          spans.add(
            WidgetSpan(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _renderInlineFormula(formula, style: style),
              ),
              alignment: PlaceholderAlignment.baseline, // 🔥 修复：使用 baseline 让公式更好地融入文本流
              baseline: TextBaseline.alphabetic,
            ),
          );
        }
      }
      
      lastIndex = match.end;
    }
    
    // 添加剩余的文本
    if (lastIndex < text.length) {
      final remainingText = text.substring(lastIndex);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(text: remainingText, style: style));
      }
    }
    
    // 如果没有找到任何公式，返回普通文本
    if (spans.isEmpty) {
      return Text(
        text, 
        style: style,
        softWrap: true, 
        maxLines: null, 
        textWidthBasis: TextWidthBasis.parent,
        overflow: TextOverflow.visible,
      );
    }
    
    // 🔥 关键修复：RichText必须设置完整的换行属性
    return RichText(
      text: TextSpan(children: spans), 
      softWrap: true,              // ✅ 允许自动换行
      maxLines: null,              // ✅ 允许无限行数
      textWidthBasis: TextWidthBasis.parent,  // ✅ 使用父容器宽度作为换行基准
      overflow: TextOverflow.visible,         // ✅ 确保内容可见
    );
  }

  /// 渲染行内公式（嵌入文本流，基线对齐）
  static Widget _renderInlineFormula(String latex, {required TextStyle style}) {
    final cleanedLatex = _preprocessLatex(latex);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Math.tex(
        cleanedLatex, 
        textStyle: style.copyWith(height: 1.2), // ✅ 统一设置高度
        mathStyle: MathStyle.text,
        onErrorFallback: (error) {
          return Text(
            '\$$latex\$', // ✅ 显示原始LaTeX代码
            style: style.copyWith(
              color: Colors.orange.withValues(alpha: 0.8), 
              fontStyle: FontStyle.italic,
              fontSize: style.fontSize != null ? style.fontSize! * 0.9 : 12,
            ),
          );
        },
      ),
    );
  }

  // ==================== 预处理方法 ====================

  /// 基础预处理：只做必要的编码转换，遵循最小干预原则
  /// 
  /// 🔥 核心原则：
  /// 1. Unicode解码（必须）
  /// 2. HTML实体清理（必须）
  /// 3. LaTeX包裹符转换 \( \) → $...$（可选）
  /// 4. ❌ 不清理空格（会破坏 \sin x 等命令）
  /// 5. ❌ 不转换特殊字符（让后端返回正确的LaTeX）
  /// 6. ❌ 不进行智能判断（避免误判率高）
  static String _basicPreprocess(String text) {
    if (text.isEmpty) return text;
    var r = text;
    
    // ✅ 1. 处理Unicode转义（如 \u00b2 → ²）
    r = r.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (m) {
      try {
        final cp = int.parse(m.group(1)!, radix: 16);
        return String.fromCharCode(cp);
      } catch (e) {
        return m.group(0)!;
      }
    });
    
    // ✅ 2. 处理HTML实体
    r = r.replaceAll('&nbsp;', ' ');
    r = r.replaceAll('&lt;', '<');
    r = r.replaceAll('&gt;', '>');
    r = r.replaceAll('&amp;', '&');
    
    // ✅ 3. 标准化换行符（将 \r\n 和 \r 替换为 \n）
    r = r.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    
    // ✅ 4. 移除多余的LaTeX包裹符（如果已经用$包裹了，就不需要 \( \) 等）
    // 🔥 核心修复：使用更宽松的正则，支持嵌套括号
    r = r.replaceAllMapped(
      RegExp(r'\\\(([\s\S]+?)\\\)', multiLine: true, dotAll: true),
      (m) => '\$${m.group(1)}\$',
    );
    r = r.replaceAllMapped(
      RegExp(r'\\\[([\s\S]+?)\\\]', multiLine: true, dotAll: true),
      (m) => '\$\$${m.group(1)}\$\$',
    );
    
    // ❌ 禁止以下操作（会破坏LaTeX语法）：
    // - result.replaceAll(RegExp(r'\s+'), ' ')  // 清理所有空格
    // - result.replaceAll('×', '\\times ')       // 转换特殊字符
    // - result.replaceAll('÷', '\\div ')         // 转换特殊字符
    
    return r;
  }
  
  /// 🔥 核心修复：预处理 LaTeX 内容，清理可能导致渲染失败的问题
  /// 
  /// 处理策略：
  /// 1. 清理多余的空格（但保留命令后的必要空格）
  /// 2. 修复常见的转义问题
  /// 3. 清理不可见字符
  static String _preprocessLatex(String latex) {
    if (latex.isEmpty) return latex;
    
    var result = latex;
    
    // 1. 清理首尾空白
    result = result.trim();
    
    // 2. 清理多余的连续空格（但保留命令后的单个空格）
    // 例如："\\sin   x" → "\\sin x"
    result = result.replaceAll(RegExp(r' {2,}'), ' ');
    
    // 3. 修复双重反斜杠问题（如果存在）
    // 例如："\\\\frac" → "\\frac"
    result = result.replaceAll(RegExp(r'\\\\(?=[a-zA-Z])'), r'\');
    
    // 4. 清理不可见字符（如零宽空格、软连字符等）
    result = result.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    
    // 5. 修复常见的 LaTeX 错误格式
    // 例如："\\ frac" → "\\frac"（去除命令和反斜杠之间的空格）
    result = result.replaceAll(RegExp(r'\\ ([a-zA-Z]+)'), r'\$1');
    
    // 6. 确保花括号配对（简单的检查）
    final openBraces = result.split('{').length - 1;
    final closeBraces = result.split('}').length - 1;
    if (openBraces != closeBraces) {
      // 花括号不配对，尝试自动补全
      if (openBraces > closeBraces) {
        result += '}' * (openBraces - closeBraces);
      }
    }
    
    return result;
  }

  /// 🔥 新增：自动包裹未包裹的 LaTeX 公式
  /// 
  /// 用于处理后端返回的纯文本公式，自动添加 $ 包裹符
  static String _wrapAndFormatLatex(String text) {
    if (text.isEmpty) return text;

    // 如果已经包含 $ 包裹符，直接返回
    if (text.contains(RegExp(r'\$[^$]+\$'))) {
      return text;
    }

    // 检测是否包含数学关键字
    final mathKeywords = [
      r'\begin', r'\end', r'\frac', r'\sqrt', r'\sum', r'\int', r'\lim',
      r'\alpha', r'\beta', r'\gamma', r'\delta', r'\epsilon', r'\theta',
      r'\lambda', r'\mu', r'\pi', r'\sigma', r'\phi', r'\omega',
      '^', '_', r'\leq', r'\geq', r'\neq', r'\approx',
      r'\infty', r'\partial', r'\nabla', r'\times', r'\div', r'\pm', r'\mp'
    ];

    bool hasMathContent = false;
    for (var keyword in mathKeywords) {
      if (text.contains(keyword)) {
        hasMathContent = true;
        break;
      }
    }

    // 如果包含数学内容但未包裹，自动添加 $
    if (hasMathContent) {
      // 检测是否为块级公式
      if (text.contains(r'\begin{') || 
          text.contains(r'\end{') ||
          text.contains('\\\\') ||
          text.contains('&') ||
          text.length > 50) {
        return '\$\$$text\$\$';
      } else {
        return '\$$text\$';
      }
    }

    return text;
  }
}
