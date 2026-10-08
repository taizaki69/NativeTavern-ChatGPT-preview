import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'chatgpt_plan_client.dart';

class ChatGptDelta {
  const ChatGptDelta({this.text, this.reasoning});
  final String? text;
  final String? reasoning;
}

/// Converts the existing transcript to the documented SIWC Responses format.
Map<String, dynamic> chatGptPlanRequest(
    String model, List<Map<String, dynamic>> messages) {
  if (model.isEmpty)
    throw const ChatGptPlanException(
        'Select a model from this ChatGPT account.');
  final input = <Map<String, dynamic>>[];
  for (final message in messages) {
    final originalRole = message['role'];
    final role = originalRole == 'system' ? 'developer' : originalRole;
    if (!const {'developer', 'user', 'assistant'}.contains(role) ||
        message.containsKey('tool_calls')) {
      throw const ChatGptPlanException(
          'This ChatGPT connection supports text and image chat. Native tool calls are not enabled.');
    }
    final content = message['content'];
    if (content is String) {
      input.add({'role': role, 'content': content});
    } else if (content is List) {
      final parts = <Map<String, dynamic>>[];
      for (final raw in content) {
        if (raw is! Map)
          throw const ChatGptPlanException(
              'Unsupported ChatGPT message content.');
        if (raw['type'] == 'text' && raw['text'] is String) {
          parts.add({'type': 'input_text', 'text': raw['text']});
        } else if (raw['type'] == 'image_url' &&
            role == 'user' &&
            raw['image_url'] is Map) {
          final image = raw['image_url'] as Map;
          if (image['url'] is! String)
            throw const ChatGptPlanException('Missing image URL.');
          parts.add({
            'type': 'input_image',
            'image_url': image['url'],
            if (const {'auto', 'low', 'high'}.contains(image['detail']))
              'detail': image['detail']
          });
        } else {
          throw const ChatGptPlanException(
              'This message uses a capability not enabled for ChatGPT plan sharing.');
        }
      }
      // Assistant history is an easy-input message; use text strings, not input_text items.
      if (role == 'assistant') {
        input.add({
          'role': role,
          'content': parts.map((p) => p['text'] as String).join('\n')
        });
      } else {
        input.add({'role': role, 'content': parts});
      }
    } else {
      throw const ChatGptPlanException('Unsupported ChatGPT message content.');
    }
  }
  return {'model': model, 'input': input, 'store': false, 'stream': true};
}

/// Handles SSE boundaries and requires an explicit successful terminal event.
Stream<ChatGptDelta> parseChatGptPlanStream(Stream<List<int>> bytes) async* {
  final dataLines = <String>[];
  var eventSize = 0;
  await for (final line in bytes
      .map<List<int>>((chunk) => chunk)
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.startsWith('data:')) {
      var data = line.substring(5);
      if (data.startsWith(' ')) data = data.substring(1);
      eventSize += data.length;
      if (eventSize > 2 * 1024 * 1024)
        throw const ChatGptPlanException(
            'ChatGPT stream event exceeded the supported size.');
      dataLines.add(data);
      continue;
    }
    if (line.isNotEmpty || dataLines.isEmpty) continue;
    final payload = dataLines.join('\n');
    dataLines.clear();
    eventSize = 0;
    if (payload == '[DONE]')
      break; // Never substitute [DONE] for response.completed.
    Map<String, dynamic> event;
    try {
      event = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      throw const ChatGptPlanException(
          'ChatGPT returned an invalid stream event.');
    }
    switch (event['type']) {
      case 'response.output_text.delta':
      case 'response.refusal.delta':
        if (event['delta'] is! String)
          throw const ChatGptPlanException(
              'ChatGPT returned an invalid text delta.');
        yield ChatGptDelta(text: event['delta'] as String);
        break;
      case 'response.reasoning_summary_text.delta':
        if (event['delta'] is String)
          yield ChatGptDelta(reasoning: event['delta'] as String);
        break;
      case 'response.completed':
        final response = event['response'];
        if (response is! Map ||
            response['status'] != 'completed' ||
            response['error'] != null) {
          throw const ChatGptPlanException(
              'ChatGPT did not confirm successful completion.');
        }
        return;
      case 'response.failed':
      case 'response.incomplete':
      case 'error':
        final response = event['response'];
        final error =
            response is Map ? response['error'] : event['error'] ?? event;
        throw ChatGptPlanClient.safeFailure(
            data: {'error': error},
            fallback:
                'ChatGPT returned a failed or incomplete response. The partial text is not a completed reply.');
    }
  }
  throw const ChatGptPlanException(
      'ChatGPT stream ended before response.completed. Please retry explicitly.');
}

enum _PlanBodyFormat { pending, sse, json, other }

const _diagnosticLimit = 64 * 1024;

/// Probe only a bounded prefix. Replay all original bytes once SSE is detected.
_PlanBodyFormat _probePlanBody(List<int> prefix) {
  const bom = [0xef, 0xbb, 0xbf];
  if (prefix.length < bom.length &&
      List.generate(prefix.length, (i) => prefix[i] == bom[i])
          .every((match) => match)) return _PlanBodyFormat.pending;
  final text = utf8.decode(prefix, allowMalformed: true).trimLeft();
  if (text.isEmpty) return _PlanBodyFormat.pending;
  if (text.startsWith('{') || text.startsWith('[')) return _PlanBodyFormat.json;
  const fields = ['data:', 'event:', 'id:', 'retry:', ':'];
  if (fields.any(text.startsWith)) return _PlanBodyFormat.sse;
  if (fields.any((field) => field.startsWith(text)))
    return _PlanBodyFormat.pending;
  return _PlanBodyFormat.other;
}

Stream<List<int>> _replayPlanBytes(
    StreamIterator<List<int>> iterator, List<List<int>> prefix) async* {
  try {
    for (final bytes in prefix) {
      yield bytes;
    }
    while (await iterator.moveNext()) {
      yield iterator.current;
    }
  } finally {
    await iterator.cancel();
  }
}

Future<({dynamic data, String? shape})> _readPlanDiagnostic(
    Stream<List<int>> stream) async {
  final buffer = <int>[];
  await for (final bytes in stream) {
    if (buffer.length + bytes.length > _diagnosticLimit) {
      return (data: null, shape: 'truncated');
    }
    buffer.addAll(bytes);
  }
  if (buffer.isEmpty) return (data: null, shape: 'empty');
  try {
    return (data: jsonDecode(utf8.decode(buffer)), shape: null);
  } catch (_) {
    return (data: null, shape: 'non-json');
  }
}

class ChatGptPlanResponses {
  ChatGptPlanResponses(this.client, this.dio);
  final ChatGptPlanClient client;
  final Dio dio;

  ChatGptPlanException _failure(Response<ResponseBody> response,
          {dynamic data, String? shape, String? fallback}) =>
      ChatGptPlanClient.safeFailure(
          data: data,
          status: response.statusCode,
          requestId: response.headers['x-request-id']?.firstOrNull,
          contentType:
              response.headers[Headers.contentTypeHeader]?.firstOrNull ?? '',
          bodyShapeOverride: shape,
          fallback: fallback);

  ChatGptPlanException _withContext(
      ChatGptPlanException error, Response<ResponseBody> response) {
    final context = _failure(response);
    return ChatGptPlanException(error.message,
        code: error.code,
        status: error.status ?? context.status,
        requestId: error.requestId ?? context.requestId,
        param: error.param,
        bodyShape: error.bodyShape ?? 'event-stream',
        contentType: error.contentType ?? context.contentType);
  }

  Stream<ChatGptDelta> _decode(Response<ResponseBody> response) async* {
    final iterator = StreamIterator<List<int>>(
        response.data!.stream.map<List<int>>((chunk) => chunk));
    final prefix = <List<int>>[];
    final probe = <int>[];
    var format = _PlanBodyFormat.pending;
    try {
      while (format == _PlanBodyFormat.pending && await iterator.moveNext()) {
        final chunk = iterator.current;
        prefix.add(chunk);
        probe.addAll(chunk.take(_diagnosticLimit - probe.length));
        format = _probePlanBody(probe);
        if (format == _PlanBodyFormat.pending &&
            probe.length == _diagnosticLimit) {
          throw _failure(response,
              shape: 'truncated',
              fallback:
                  'OpenAI did not start a recognizable Responses event stream.');
        }
      }
      if (format == _PlanBodyFormat.json) {
        final diagnostic =
            await _readPlanDiagnostic(_replayPlanBytes(iterator, prefix));
        throw _failure(response,
            data: diagnostic.data,
            shape: diagnostic.shape,
            fallback:
                'OpenAI returned JSON instead of the required Responses event stream. No completed streamed reply was received.');
      }
      if (format != _PlanBodyFormat.sse) {
        throw _failure(response,
            shape: probe.isEmpty ? 'empty' : 'non-json',
            fallback:
                'OpenAI did not return a recognizable Responses event stream. Check the response diagnostics.');
      }
      await for (final delta
          in parseChatGptPlanStream(_replayPlanBytes(iterator, prefix))) {
        yield delta;
      }
    } on ChatGptPlanException catch (e) {
      throw _withContext(e, response);
    } on FormatException {
      throw _failure(response,
          shape: 'event-stream',
          fallback: 'OpenAI returned an invalid UTF-8 Responses event stream.');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _withContext(ChatGptPlanClient.safeHttpFailure(e), response);
    } finally {
      await iterator.cancel();
    }
  }

  Stream<ChatGptDelta> stream(
      {required String clientId,
      required String model,
      required List<Map<String, dynamic>> messages,
      required CancelToken cancelToken}) async* {
    final body = chatGptPlanRequest(model, messages);
    final token = await client.accessToken(clientId);
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    try {
      final response = await dio.post<ResponseBody>(
          ChatGptPlanClient.apiRoot + '/responses',
          data: body,
          cancelToken: cancelToken,
          options: Options(
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'text/event-stream'
              },
              contentType: Headers.jsonContentType,
              responseType: ResponseType.stream,
              followRedirects: false,
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 3),
              validateStatus: (s) => s != null && s >= 200 && s < 600));
      final streamBody = response.data;
      if (response.statusCode != 200 || streamBody == null) {
        final diagnostic = streamBody == null
            ? (data: null, shape: 'empty')
            : await _readPlanDiagnostic(
                streamBody.stream.map<List<int>>((chunk) => chunk));
        throw _failure(response,
            data: diagnostic.data, shape: diagnostic.shape);
      }
      // A MIME label alone is neither proof of a stream nor an admission error.
      // Consume only SSE framing, with the same mandatory completed terminal event.
      yield* _decode(response);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ChatGptPlanClient.safeHttpFailure(e);
    } finally {
      if (!cancelToken.isCancelled) cancelToken.cancel('ChatGPT stream closed');
    }
  }
}
