/// 应用配置类
class Config {
  /// API 基础 URL
  static const String baseUrl = 'http://zdxt.dpdns.org';

  /// 获取完整的 API URL
  static String getApiUrl(String path) {
    return '$baseUrl$path';
  }
}
