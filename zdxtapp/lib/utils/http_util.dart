import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';

/// HTTP请求工具类（优化：超时控制、重试机制、错误处理）
class HttpUtil {
  static const int defaultTimeout = 10; // 默认超时时间（秒）
  static const int maxRetries = 2; // 最大重试次数
  
  /// POST请求（带超时和重试）
  static Future<Map<String, dynamic>> post(
    String url, {
    Map<String, String>? headers,
    dynamic body,
    Encoding? encoding,
    int timeout = defaultTimeout,
    int retries = maxRetries,
  }) async {
    Exception? lastError;
    
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        debugPrint('[HTTP] 请求 [$attempt]: $url');
        
        final response = await http.post(
          Uri.parse(url),
          headers: headers ?? {'Content-Type': 'application/json'},
          body: body,
          encoding: encoding,
        ).timeout(Duration(seconds: timeout));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          debugPrint('[HTTP] 成功: $url');
          return data;
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('[HTTP] 失败 [${attempt + 1}/$retries]: $e');
        
        // 最后一次尝试失败，抛出异常
        if (attempt == retries) {
          rethrow;
        }
        
        // 等待后重试（指数退避）
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    
    throw lastError ?? Exception('未知错误');
  }

  /// GET请求（带超时和重试）
  static Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? headers,
    int timeout = defaultTimeout,
    int retries = maxRetries,
  }) async {
    Exception? lastError;
    
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        debugPrint('[HTTP] GET请求 [$attempt]: $url');
        
        final response = await http.get(
          Uri.parse(url),
          headers: headers,
        ).timeout(Duration(seconds: timeout));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          debugPrint('[HTTP] GET成功: $url');
          return data;
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('[HTTP] GET失败 [${attempt + 1}/$retries]: $e');
        
        if (attempt == retries) {
          rethrow;
        }
        
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    
    throw lastError ?? Exception('未知错误');
  }

  /// 文件上传（使用MultipartRequest）
  static Future<Map<String, dynamic>> uploadFile(
    String url,
    String filePath,
    String field, {
    Map<String, String>? fields,
    int timeout = 30, // 上传超时更长
  }) async {
    try {
      debugPrint('[HTTP] 上传文件: $url');
      
      final request = http.MultipartRequest('POST', Uri.parse(url));
      
      if (fields != null) {
        request.fields.addAll(fields);
      }
      
      request.files.add(await http.MultipartFile.fromPath(field, filePath));
      
      final response = await request.send().timeout(Duration(seconds: timeout));
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        debugPrint('[HTTP] 上传成功: $url');
        return data;
      } else {
        throw Exception('上传失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[HTTP] 上传失败: $e');
      rethrow;
    }
  }
}

/// 请求缓存管理器（优化：减少重复请求）
class RequestCache {
  static final Map<String, _CacheItem> _cache = {};
  static const Duration defaultTtl = Duration(minutes: 5); // 默认缓存5分钟

  /// 获取缓存数据
  static T? get<T>(String key) {
    final item = _cache[key];
    if (item == null) return null;
    
    // 检查是否过期
    if (DateTime.now().isAfter(item.expiry)) {
      _cache.remove(key);
      return null;
    }
    
    return item.data as T?;
  }

  /// 设置缓存
  static void set(String key, dynamic data, {Duration? ttl}) {
    _cache[key] = _CacheItem(
      data: data,
      expiry: DateTime.now().add(ttl ?? defaultTtl),
    );
    
    // 清理过期缓存（限制缓存大小）
    if (_cache.length > 100) {
      _cleanup();
    }
  }

  /// 清除缓存
  static void clear([String? key]) {
    if (key != null) {
      _cache.remove(key);
    } else {
      _cache.clear();
    }
  }

  /// 清理过期缓存
  static void _cleanup() {
    final now = DateTime.now();
    _cache.removeWhere((key, item) => now.isAfter(item.expiry));
  }
}

class _CacheItem {
  final dynamic data;
  final DateTime expiry;

  _CacheItem({required this.data, required this.expiry});
}

/// 防抖工具（优化：减少频繁请求）
class Debouncer {
  Timer? _timer;

  void call(VoidCallback action, Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() {
    _timer?.cancel();
  }
}

/// 节流工具（优化：限制请求频率）
class Throttler {
  DateTime? _lastExecution;

  bool shouldExecute(Duration throttleTime) {
    final now = DateTime.now();
    if (_lastExecution == null || now.difference(_lastExecution!) >= throttleTime) {
      _lastExecution = now;
      return true;
    }
    return false;
  }
}