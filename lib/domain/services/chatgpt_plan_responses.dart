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

class ChatGptPlanResponses {
  ChatGptPlanResponses(this.client, this.dio);
  final ChatGptPlanClient client;
  final Dio dio;

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
          '${ChatGptPlanClient.apiRoot}/responses',
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
              receiveTimeout: const Duration(minutes: 3),
              validateStatus: (s) => s != null && s >= 200 && s < 600));
      final streamBody = response.data;
      if (response.statusCode != 200 || streamBody == null) {
        // Parse bounded error bodies without exposing request headers or credentials.
        dynamic errorBody;
        if (streamBody != null) {
          final buffer = <int>[];
          await for (final bytes in streamBody.stream) {
            if (buffer.length + bytes.length > 65536) break;
            buffer.addAll(bytes);
          }
          try {
            errorBody = jsonDecode(utf8.decode(buffer));
          } catch (_) {
            errorBody = null;
          }
        }
        throw ChatGptPlanClient.safeHttpFailure(DioException(
            requestOptions: response.requestOptions,
            response: Response<dynamic>(
                requestOptions: response.requestOptions,
                statusCode: response.statusCode,
                data: errorBody,
                headers: response.headers)));
      }
      if (response.headers
              .value(Headers.contentTypeHeader)
              ?.split(';')
              .first
              .trim() !=
          'text/event-stream') {
        throw const ChatGptPlanException(
            'OpenAI returned an unexpected response type.');
      }
      yield* parseChatGptPlanStream(streamBody.stream);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ChatGptPlanClient.safeHttpFailure(e);
    } finally {
      // Also closes the request when a consumer stops listening early.
      if (!cancelToken.isCancelled) cancelToken.cancel('ChatGPT stream closed');
    }
  }
}
