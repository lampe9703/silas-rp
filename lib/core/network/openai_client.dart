import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../features/settings/domain/settings_models.dart';
import 'api_exception.dart';

class TokenUsage {
  const TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
}

class ChatStreamEvent {
  const ChatStreamEvent({
    this.contentDelta,
    this.isDone = false,
    this.finishReason,
    this.usage,
  });

  final String? contentDelta;
  final bool isDone;
  final String? finishReason;
  final TokenUsage? usage;
}

/// OpenAI 兼容协议的流式客户端。
///
/// 只做一件事：把 SSE 的 `data:` 行翻译成 [ChatStreamEvent]。
/// 取消通过 [CancelToken] 实现，取消后底层连接立即断开。
class OpenAiClient {
  OpenAiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 180),
                sendTimeout: const Duration(seconds: 20),
                // 非 2xx 交给业务层判断，避免 dio 直接抛出丢失错误体
                validateStatus: (code) => code != null && code < 500,
              ),
            );

  final Dio _dio;

  /// 候选根地址：先按用户填的来；404 时再补/去一个 /v1 重试。
  ///
  /// 中转站的分歧就在这一层：有的把 OpenAI 兼容接口挂在 `/v1` 下，
  /// 有的直接挂在根路径。只填域名时谁也不知道对方哪种，所以两种都试。
  static List<String> _candidateRoots(String baseUrl) {
    final root = _root(baseUrl);
    if (root.isEmpty) return <String>[root];
    final lower = root.toLowerCase();
    if (lower.endsWith('/v1')) {
      return <String>[root, root.substring(0, root.length - 3)];
    }
    return <String>[root, '$root/v1'];
  }

  static String _root(String baseUrl) {
    var base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    // 允许直接粘贴完整端点或 /v1/models，统一退回到根地址再拼
    const suffixes = <String>[
      '/chat/completions',
      '/models',
    ];
    var changed = true;
    while (changed) {
      changed = false;
      for (final suffix in suffixes) {
        if (base.endsWith(suffix)) {
          base = base.substring(0, base.length - suffix.length);
          base = base.replaceAll(RegExp(r'/+$'), '');
          changed = true;
        }
      }
    }
    return base;
  }

  Map<String, String> _headers(ApiConfig config, String apiKey) => {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        ...config.extraHeaders,
      };

  /// 流式对话。返回的事件流以 [ChatStreamEvent.isDone] 结束。
  Stream<ChatStreamEvent> streamChat({
    required ApiConfig config,
    required String apiKey,
    required List<Map<String, String>> messages,
    required CancelToken cancelToken,
    int? maxTokens,
    double? temperature,
    double? topP,
    bool includeUsage = true,
  }) async* {
    final body = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'stream': true,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'top_p': topP,
      if (includeUsage) 'stream_options': {'include_usage': true},
    };

    Response<ResponseBody> response;
    try {
      response = await _post(config, apiKey, body, cancelToken);
    } on ApiException catch (e) {
      final detail = (e.detail ?? '').toLowerCase();
      final message = e.message.toLowerCase();
      // 部分网关不认 stream_options，去掉后重试一次
      if (e.kind == ApiErrorKind.badRequest &&
          includeUsage &&
          detail.contains('stream_options')) {
        body.remove('stream_options');
        response = await _post(config, apiKey, body, cancelToken);
      } else if (e.statusCode == 400 &&
          (detail.contains('temperature') ||
              message.contains('temperature') ||
              detail.contains('top_p') ||
              message.contains('top_p')) &&
          (body.containsKey('temperature') || body.containsKey('top_p'))) {
        // 有些模型（新版 Claude / o1 等）只接受默认采样参数，
        // 带上 temperature / top_p 会直接 400：去掉后重试一次
        body
          ..remove('temperature')
          ..remove('top_p');
        response = await _post(config, apiKey, body, cancelToken);
      } else {
        rethrow;
      }
    }

    final stream = response.data?.stream;
    if (stream == null) {
      throw ApiException(ApiErrorKind.unknown, '响应为空');
    }

    // utf8.decoder 处理跨 chunk 的多字节字符；LineSplitter 处理 \r\n
    final lines =
        utf8.decoder.bind(stream).transform(const LineSplitter());

    String? finishReason;
    TokenUsage? usage;

    // 取消/断网发生在流消费阶段时，dio 会把 DioException 直接塞进字节流，
    // 必须在这里转成 ApiException，否则上层会当成「生成失败」而不是「已取消」。
    try {
      await for (final line in lines) {
        if (line.isEmpty) continue;
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') {
          yield ChatStreamEvent(isDone: true, finishReason: finishReason, usage: usage);
          return;
        }

        Map<String, dynamic> json;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is! Map<String, dynamic>) continue;
          json = decoded;
        } catch (_) {
          // 个别网关会插入非 JSON 的心跳行，跳过即可
          continue;
        }

        if (json['error'] != null) {
          final err = json['error'];
          final message = err is Map ? '${err['message'] ?? err}' : '$err';
          throw ApiException(ApiErrorKind.server, message);
        }

        final choices = json['choices'];
        if (choices is List && choices.isNotEmpty) {
          final choice = choices.first;
          if (choice is Map) {
            final delta = choice['delta'];
            final content = delta is Map ? delta['content'] : null;
            final fr = choice['finish_reason'];
            if (fr is String && fr.isNotEmpty) finishReason = fr;
            if (content is String && content.isNotEmpty) {
              yield ChatStreamEvent(contentDelta: content, finishReason: finishReason);
            }
          }
        }

        final rawUsage = json['usage'];
        if (rawUsage is Map) {
          final pt = (rawUsage['prompt_tokens'] as num?)?.toInt() ?? 0;
          final ct = (rawUsage['completion_tokens'] as num?)?.toInt() ?? 0;
          final tt = (rawUsage['total_tokens'] as num?)?.toInt() ?? (pt + ct);
          usage = TokenUsage(
            promptTokens: pt,
            completionTokens: ct,
            totalTokens: tt,
          );
        }
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw ApiException(ApiErrorKind.cancelled, '已取消');
      }
      throw ApiException(ApiErrorKind.network, e.message ?? '网络异常');
    }

    // 连接被对端关闭但没收到 [DONE]
    yield ChatStreamEvent(isDone: true, finishReason: finishReason, usage: usage);
  }

  Future<Response<ResponseBody>> _post(
    ApiConfig config,
    String apiKey,
    Map<String, dynamic> body,
    CancelToken cancelToken,
  ) async {
    final roots = _candidateRoots(config.baseUrl);
    for (var i = 0; i < roots.length; i++) {
      try {
        final response = await _dio.post<ResponseBody>(
          '${roots[i]}/chat/completions',
          data: body,
          options: Options(
            responseType: ResponseType.stream,
            headers: _headers(config, apiKey),
          ),
          cancelToken: cancelToken,
        );
        final code = response.statusCode ?? 0;
        // 路径不对时换下一个根地址再试，别急着把 404 抛给用户
        if (code == 404 && i < roots.length - 1) continue;
        if (code >= 400) {
          final detail = await _readErrorBody(response.data);
          throw _mapError(code, detail);
        }
        return response;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          throw ApiException(ApiErrorKind.cancelled, '已取消');
        }
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          throw ApiException(ApiErrorKind.timeout, '请求超时');
        }
        final code = e.response?.statusCode;
        if (code == 404 && i < roots.length - 1) continue;
        if (code != null) {
          final detail = await _readErrorBody(e.response?.data);
          throw _mapError(code, detail);
        }
        throw ApiException(ApiErrorKind.network, e.message ?? '网络异常');
      }
    }
    throw ApiException(
      ApiErrorKind.badRequest,
      '模型或路径不存在：请核对模型 ID、所选分组与 Base URL',
      statusCode: 404,
    );
  }

  static Future<String> _readErrorBody(dynamic data) async {
    if (data is ResponseBody) {
      try {
        final text = await utf8.decoder
            .bind(data.stream)
            .join()
            .timeout(const Duration(seconds: 3));
        return text.length > 600 ? text.substring(0, 600) : text;
      } catch (_) {
        return '';
      }
    }
    if (data is String) return data;
    return '';
  }

  static ApiException _mapError(int code, String detail) {
    final message = _extractMessage(detail);
    if (code == 401 || code == 403) {
      return ApiException(ApiErrorKind.auth, message, statusCode: code, detail: detail);
    }
    if (code == 429) {
      return ApiException(ApiErrorKind.rateLimit, message, statusCode: code, detail: detail);
    }
    if (code == 404) {
      return ApiException(
        ApiErrorKind.badRequest,
        message.isEmpty
            ? '模型或路径不存在：请核对模型 ID、所选分组与 Base URL'
            : '模型或路径不存在：$message',
        statusCode: code,
        detail: detail,
      );
    }
    if (code == 400 || code == 422) {
      return ApiException(ApiErrorKind.badRequest, message, statusCode: code, detail: detail);
    }
    return ApiException(ApiErrorKind.server, message, statusCode: code, detail: detail);
  }

  static String _extractMessage(String body) {
    if (body.isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        return '${(decoded['error'] as Map)['message'] ?? body}';
      }
      if (decoded is Map && decoded['message'] != null) {
        return '${decoded['message']}';
      }
    } catch (_) {
      // 非 JSON 错误体，原样返回截断内容
    }
    return body;
  }

  /// 拉取可用模型列表：`GET /models`，同样会在两个候选根地址间回退。
  ///
  /// 返回按名称排序的 id 列表；服务端没给标准结构时返回空列表。
  Future<List<String>> fetchModels(ApiConfig config, String apiKey) async {
    final roots = _candidateRoots(config.baseUrl);
    var lastError = '';
    for (var i = 0; i < roots.length; i++) {
      try {
        final response = await _dio.get<dynamic>(
          '${roots[i]}/models',
          options: Options(
            headers: {
              if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
              ...config.extraHeaders,
            },
            responseType: ResponseType.json,
          ),
        );
        final code = response.statusCode ?? 0;
        if (code == 404 && i < roots.length - 1) continue;
        if (code >= 400) {
          throw _mapError(code, response.data?.toString() ?? '');
        }
        final data = response.data;
        final items = data is Map ? data['data'] : data;
        if (items is! List) return const <String>[];
        final ids = <String>[];
        for (final item in items) {
          if (item is Map && item['id'] != null) {
            final id = item['id'].toString().trim();
            if (id.isNotEmpty) ids.add(id);
          } else if (item is String && item.trim().isNotEmpty) {
            ids.add(item.trim());
          }
        }
        ids.sort();
        return ids;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          throw ApiException(ApiErrorKind.timeout, '连接超时');
        }
        final code = e.response?.statusCode;
        if (code == 404 && i < roots.length - 1) continue;
        if (code != null) {
          throw _mapError(code, e.response?.data?.toString() ?? '');
        }
        throw ApiException(ApiErrorKind.network, e.message ?? '网络异常');
      } catch (e) {
        lastError = '$e';
      }
    }
    if (lastError.isNotEmpty) {
      throw ApiException(ApiErrorKind.unknown, '获取模型列表失败：$lastError');
    }
    return const <String>[];
  }

  /// 测试连接：GET /models（OpenAI 兼容端点几乎都支持）
  ///
  /// 与对话请求同样会试两个候选根地址，避免「只填域名」时误报 404。
  Future<String> testConnection(ApiConfig config, String apiKey) async {
    final roots = _candidateRoots(config.baseUrl);
    for (var i = 0; i < roots.length; i++) {
      try {
        final response = await _dio.get<dynamic>(
          '${roots[i]}/models',
          options: Options(
            headers: {
              if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
              ...config.extraHeaders,
            },
            responseType: ResponseType.json,
          ),
        );
        final code = response.statusCode ?? 0;
        if (code == 404 && i < roots.length - 1) continue;
        if (code >= 400) {
          throw _mapError(code, response.data?.toString() ?? '');
        }
        final data = response.data;
        var count = 0;
        if (data is Map && data['data'] is List) {
          count = (data['data'] as List).length;
        }
        return count > 0 ? '连接成功，可用模型 $count 个' : '连接成功';
      } on DioException catch (e) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          throw ApiException(ApiErrorKind.timeout, '连接超时');
        }
        final code = e.response?.statusCode;
        if (code == 404 && i < roots.length - 1) continue;
        if (code != null) {
          throw _mapError(code, e.response?.data?.toString() ?? '');
        }
        throw ApiException(ApiErrorKind.network, e.message ?? '网络异常');
      }
    }
    throw ApiException(
      ApiErrorKind.badRequest,
      '模型或路径不存在：请核对 Base URL',
      statusCode: 404,
    );
  }
}
