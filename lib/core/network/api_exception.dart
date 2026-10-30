enum ApiErrorKind {
  auth,
  rateLimit,
  timeout,
  network,
  badRequest,
  server,
  cancelled,
  unknown,
}

/// 统一的 API 错误模型：任何网络异常都转成它，UI 只处理这一种。
class ApiException implements Exception {
  ApiException(this.kind, this.message, {this.statusCode, this.detail});

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? detail;

  /// 给用户看的中文提示，明确告知下一步该做什么
  String get userMessage {
    switch (kind) {
      case ApiErrorKind.auth:
        return '鉴权失败（$statusCode）：API Key 无效或已过期，请到「设置 → API 配置」检查。';
      case ApiErrorKind.rateLimit:
        return '请求过于频繁或额度不足（$statusCode），请稍后重试或检查账户余额。';
      case ApiErrorKind.timeout:
        return '请求超时，请检查网络或代理设置。';
      case ApiErrorKind.network:
        return '网络连接失败，请检查网络后重试。';
      case ApiErrorKind.badRequest:
        return '请求被拒绝（$statusCode）：$message';
      case ApiErrorKind.server:
        return '服务端错误（$statusCode），请稍后重试。';
      case ApiErrorKind.cancelled:
        return '已取消';
      case ApiErrorKind.unknown:
        return message.isEmpty ? '未知错误' : message;
    }
  }

  @override
  String toString() => 'ApiException($kind, $statusCode): $message';
}
