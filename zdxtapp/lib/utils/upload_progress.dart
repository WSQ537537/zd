import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert'; // 🔥 新增：导入 json 编码支持
import 'package:dio/dio.dart';

/// 上传进度管理器
class UploadProgressManager {
  static final Map<String, UploadProgressInfo> _progressMap = {};
  
  /// Dio 实例（单例模式）
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 120),  // ✅ 上传超时时间更长
  ));
  
  /// 获取上传进度信息
  static UploadProgressInfo? getProgress(String uploadId) {
    return _progressMap[uploadId];
  }
  
  /// 开始上传
  static void startUpload(String uploadId, String fileName) {
    _progressMap[uploadId] = UploadProgressInfo(
      uploadId: uploadId,
      fileName: fileName,
      progress: 0.0,
      status: UploadStatus.uploading,
      startTime: DateTime.now(),
    );
  }
  
  /// 更新上传进度
  static void updateProgress(String uploadId, double progress) {
    if (_progressMap.containsKey(uploadId)) {
      _progressMap[uploadId]!.progress = progress.clamp(0.0, 1.0);
    }
  }
  
  /// 上传成功
  static void uploadSuccess(String uploadId) {
    if (_progressMap.containsKey(uploadId)) {
      _progressMap[uploadId]!.progress = 1.0;
      _progressMap[uploadId]!.status = UploadStatus.success;
      _progressMap[uploadId]!.endTime = DateTime.now();
      
      // 2秒后自动移除
      Timer(const Duration(seconds: 2), () {
        _progressMap.remove(uploadId);
      });
    }
  }

  /// 进入服务端处理阶段（真实字节已发完，但服务端仍在写入/校验）
  /// 进度条保持满格并显示"处理中"，不再伪造百分比
  static void uploadProcessing(String uploadId) {
    if (_progressMap.containsKey(uploadId)) {
      _progressMap[uploadId]!.progress = 1.0;
      _progressMap[uploadId]!.status = UploadStatus.processing;
    }
  }
  
  /// 上传失败
  static void uploadFailed(String uploadId, String error) {
    if (_progressMap.containsKey(uploadId)) {
      _progressMap[uploadId]!.status = UploadStatus.failed;
      _progressMap[uploadId]!.error = error;
      _progressMap[uploadId]!.endTime = DateTime.now();
      
      // 3秒后自动移除
      Timer(const Duration(seconds: 3), () {
        _progressMap.remove(uploadId);
      });
    }
  }
  
  /// 取消上传
  static void cancelUpload(String uploadId) {
    _progressMap.remove(uploadId);
  }
  
  /// 清理所有已完成的上传记录
  static void cleanup() {
    _progressMap.removeWhere((key, value) => 
      value.status == UploadStatus.success || value.status == UploadStatus.failed
    );
  }
  
  // ✅ 使用 Dio 进行文件上传，支持真实进度回调
  static Future<Map<String, dynamic>> uploadFileWithProgress({
    required String url,
    String filePath = '',
    List<int>? bytes,
    String byteFileName = 'upload',
    required String fieldName,
    required String uploadId,
    required Map<String, String> fields,
    required Function(double progress) onProgress,
  }) async {
    try {
      // 🔥 支持两种来源：文件路径 或 内存字节
      final MultipartFile file;
      if (bytes != null) {
        file = MultipartFile.fromBytes(bytes, filename: byteFileName);
      } else {
        file = await MultipartFile.fromFile(filePath);
      }

      final formData = FormData.fromMap({
        ...fields,
        fieldName: file,
      });

      final response = await _dio.post(
        url,
        data: formData,
        onSendProgress: (sent, total) {
          // ✅ 计算真实上传进度
          if (total > 0) {
            final progress = sent / total;
            onProgress(progress);
          }
        },
      );

      // 🔥 真实字节已全部发送完毕，进入"服务端处理中"阶段
      // 此时进度条保持满格 + 转圈，直到服务器返回结果才翻转为成功/失败
      uploadProcessing(uploadId);
      
      // 🔥 新增：验证响应数据是否为有效的Map类型
      if (response.data is! Map<String, dynamic>) {
        // 如果不是Map，尝试转换为字符串查看内容
        String responseDataStr = response.data.toString();
        // 检查是否包含HTML标签（可能是错误页面）
        if (responseDataStr.contains('<html') || responseDataStr.contains('<!DOCTYPE')) {
          return {
            'success': false,
            'error': '服务器返回了HTML页面而非JSON数据，请检查服务器配置',
          };
        }
        // 检查是否为乱码或二进制数据
        if (responseDataStr.length > 1000 || !isValidJsonString(responseDataStr)) {
          return {
            'success': false,
            'error': '服务器返回了无效数据格式，可能是编码问题或服务器错误',
          };
        }
        // 尝试解析为JSON
        try {
          final parsedData = jsonDecode(responseDataStr) as Map<String, dynamic>;
          return {
            'success': true,
            'data': parsedData,
          };
        } catch (e) {
          return {
            'success': false,
            'error': '服务器返回了无法解析的数据: $responseDataStr',
          };
        }
      }
      
      return {
        'success': true,
        'data': response.data,
      };
    } on DioException catch (e) {
      String errorMessage = e.message ?? '网络请求失败';
      if (e.response != null) {
        // 尝试获取响应体内容
        try {
          String responseBody = e.response!.data.toString();
          if (responseBody.isNotEmpty && responseBody.length < 500) {
            errorMessage = '服务器错误: $responseBody';
          }
        } catch (_) {
          // 忽略解析错误
        }
      }
      return {
        'success': false,
        'error': errorMessage,
      };
    } catch (e) {
      return {
        'success': false,
        'error': '上传异常: $e',
      };
    }
  }
  
  // 🔥 新增：验证字符串是否为有效的JSON
  static bool isValidJsonString(String str) {
    if (str.trim().isEmpty) return false;
    try {
      jsonDecode(str);
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// 上传状态枚举
enum UploadStatus {
  uploading,  // 上传中（真实字节发送中）
  processing, // 服务端处理中（字节已发完，等待响应）
  success,    // 成功
  failed,     // 失败
}

/// 上传进度信息
class UploadProgressInfo {
  final String uploadId;
  final String fileName;
  double progress;
  UploadStatus status;
  String? error;
  final DateTime startTime;
  DateTime? endTime;
  
  UploadProgressInfo({
    required this.uploadId,
    required this.fileName,
    required this.progress,
    required this.status,
    this.error,
    required this.startTime,
    this.endTime,
  });
  
  /// 计算已用时间
  Duration get elapsedTime {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }
  
  /// 获取格式化时间
  String get formattedTime {
    final duration = elapsedTime;
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}秒';
    } else {
      return '${duration.inMinutes}分${duration.inSeconds % 60}秒';
    }
  }
}

/// 上传进度对话框组件
class UploadProgressDialog extends StatefulWidget {
  final String uploadId;
  final VoidCallback? onCancel;
  
  const UploadProgressDialog({
    super.key,
    required this.uploadId,
    this.onCancel,
  });
  
  @override
  State<UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<UploadProgressDialog> {
  Timer? _timer;
  bool _closed = false;
  
  @override
  void initState() {
    super.initState();
    // 每秒刷新一次以更新进度和时间
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final progress = UploadProgressManager.getProgress(widget.uploadId);
      // 上传完成（成功/失败）后，延迟 1.2 秒自动关闭弹窗
      if (!_closed && progress != null &&
          (progress.status == UploadStatus.success || progress.status == UploadStatus.failed)) {
        _closed = true;
        _timer?.cancel();
        Timer(const Duration(milliseconds: 1200), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
      setState(() {});
    });
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final progress = UploadProgressManager.getProgress(widget.uploadId);
    if (progress == null) {
      return const SizedBox.shrink();
    }
    
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标和标题
            _buildHeader(progress),
            
            const SizedBox(height: 20),
            
            // 文件名
            Text(
              progress.fileName,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            
            const SizedBox(height: 16),
            
            // 进度条
            _buildProgressBar(progress),
            
            const SizedBox(height: 12),
            
            // 进度文字和时间
            _buildProgressText(progress),
            
            const SizedBox(height: 20),
            
            // 按钮
            _buildActions(progress),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader(UploadProgressInfo progress) {
    IconData icon;
    Color color;
    String title;

    switch (progress.status) {
      case UploadStatus.uploading:
        icon = Icons.cloud_upload_outlined;
        color = const Color(0xFF1890FF);
        title = '上传中...';
        break;
      case UploadStatus.processing:
        // 真实字节已发完，服务端仍在写入/校验
        icon = Icons.hourglass_top_rounded;
        color = const Color(0xFF1890FF);
        title = '服务端处理中...';
        break;
      case UploadStatus.success:
        icon = Icons.check_circle_outline;
        color = Colors.green;
        title = '上传成功';
        break;
      case UploadStatus.failed:
        icon = Icons.error_outline;
        color = Colors.red;
        title = '上传失败';
        break;
    }

    return Row(
      children: [
        if (progress.status == UploadStatus.processing)
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          )
        else
          Icon(icon, size: 32, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildProgressBar(UploadProgressInfo progress) {
    if (progress.status == UploadStatus.processing) {
      // 服务端处理中：环形转圈，不再伪造百分比
      return SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }
    return Stack(
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 8,
          width: MediaQuery.of(context).size.width * 0.6 * progress.progress,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: progress.status == UploadStatus.failed
                  ? [Colors.red, Colors.red.shade300]
                  : progress.status == UploadStatus.success
                      ? [Colors.green, Colors.green.shade300]
                      : [const Color(0xFF1890FF), const Color(0xFF40A9FF)],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressText(UploadProgressInfo progress) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (progress.status == UploadStatus.processing)
          Text(
            '正在写入并校验...',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1890FF),
            ),
          )
        else
          Text(
            '${(progress.progress * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: progress.status == UploadStatus.failed
                  ? Colors.red
                  : progress.status == UploadStatus.success
                      ? Colors.green
                      : const Color(0xFF1890FF),
            ),
          ),
        Text(
          progress.formattedTime,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
  
  Widget _buildActions(UploadProgressInfo progress) {
    if (progress.status == UploadStatus.uploading) {
      return TextButton.icon(
        onPressed: widget.onCancel,
        icon: const Icon(Icons.close, size: 18),
        label: const Text('取消'),
        style: TextButton.styleFrom(
          foregroundColor: Colors.grey[600],
        ),
      );
    } else if (progress.status == UploadStatus.failed) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            progress.error ?? '未知错误',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.red,
            ),
          ),
        ],
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}

/// 显示上传进度对话框
void showUploadProgress(BuildContext context, String uploadId, {VoidCallback? onCancel}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => UploadProgressDialog(
      uploadId: uploadId,
      onCancel: onCancel,
    ),
  );
}

/// 隐藏上传进度对话框
void hideUploadProgress(BuildContext context) {
  Navigator.of(context).pop();
}
