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
        // 5xx 的正文里往往写着真原因（New API 的「无可用渠道」「上游负载已饱和」、
        // Gemini 的 overloaded）。之前一律显示「请稍后重试」，等于把线索扔了 ——
        // 用户只能看到一个 503，分不清是站点挂了还是模型没渠道。
        final brief = _brief(message);
        return brief.isEmpty
            ? '服务端错误（$statusCode），请稍后重试。'
            : '服务端错误（$statusCode）：$brief';
      case ApiErrorKind.cancelled:
        return '已取消';
      case ApiErrorKind.unknown:
        return message.isEmpty ? '未知错误' : message;
    }
  }

  /// 把上游正文压成一行：可能是 JSON 里的 message，也可能是一整页 HTML。
  static String _brief(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    if (text.startsWith('<')) {
      // Cloudflare / 网关的错误页：整页 HTML 塞进气泡只会刷屏
      final title = RegExp(r'<title>(.*?)</title>', caseSensitive: false)
          .firstMatch(text);
      return title == null
          ? '上游返回了网页错误页（可能是网关或防火墙拦截）'
          : '网关错误页：${title.group(1)!.trim()}';
    }
    final one = text.replaceAll(RegExp(r'\s+'), ' ');
    return one.length > 160 ? '${one.substring(0, 160)}…' : one;
  }

  @override
  String toString() => 'ApiException($kind, $statusCode): $message';
}
