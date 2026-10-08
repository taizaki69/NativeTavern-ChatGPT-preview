import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:native_tavern/domain/services/chatgpt_plan_client.dart';
import 'package:native_tavern/domain/services/chatgpt_plan_platform.dart';
import 'package:native_tavern/domain/services/llm_service.dart';

/// Synthetic restored sessions only. No live account, cookies, or credentials.
class ChatGptPlanMemoryStore implements ChatGptCredentialStore {
  ChatGptPlanMemoryStore({bool sharing = true}) {
    value = jsonEncode({
      'host_id': 'urn:uuid:00000000-0000-4000-8000-000000000001',
      'accounts': [
        for (final id in ['oaiapp_fixture', 'oaiapp_second'])
          {
            'client_id': id,
            'subject': 'fixture-user',
            'email': 'fixture@example.invalid',
            'access_token': 'synthetic-$id',
            'refresh_token': 'synthetic-refresh',
            'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
            'scopes': sharing
                ? ChatGptPlanClient.scopes.split(' ')
                : ['openid', 'profile', 'email'],
          }
      ]
    });
  }
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody fixtureJson(Object value, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(value), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
      'x-request-id': ['req_fixture'],
    });

ResponseBody fixtureEvents(List<Map<String, dynamic>> events) {
  final bytes = utf8.encode(events
      .map((e) =>
          'event: ' +
          e['type'].toString() +
          '\r\ndata: ' +
          jsonEncode(e) +
          '\r\n\r\n')
      .join());
  return ResponseBody(
      Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += 7)
          Uint8List.fromList(
              bytes.sublist(i, i + 7 < bytes.length ? i + 7 : bytes.length)),
      ]),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream']
      });
}

const fixtureCompleted = {
  'type': 'response.completed',
  'response': {'status': 'completed'}
};

class ChatGptPlanFixture {
  ChatGptPlanFixture({bool sharing = true})
      : store = ChatGptPlanMemoryStore(sharing: sharing) {
    dio = Dio()..httpClientAdapter = _FixtureAdapter(handle);
    client = ChatGptPlanClient(store: store, dio: dio);
    platform = ChatGptPlanPlatform(client: client);
    service = LLMService(dio: dio, chatGptClient: client);
  }
  final ChatGptPlanMemoryStore store;
  late final Dio dio;
  late final ChatGptPlanClient client;
  late final ChatGptPlanPlatform platform;
  late final LLMService service;
  final requests = <RequestOptions>[];
  FutureOr<ResponseBody> Function(RequestOptions)? modelHandler;
  FutureOr<ResponseBody> Function(RequestOptions)? responseHandler;

  FutureOr<ResponseBody> handle(RequestOptions request) {
    requests.add(request);
    if (request.path == ChatGptPlanClient.apiRoot + '/models') {
      if (modelHandler != null) return modelHandler!(request);
      final second =
          request.headers['Authorization'] == 'Bearer synthetic-oaiapp_second';
      return fixtureJson({
        'models': [
          {
            'slug': second ? 'second-model' : 'fixture-model-b',
            'display_name': second ? 'Second model' : 'Fixture B',
            'visibility': 'list'
          },
          {'slug': 'hidden-model', 'visibility': 'hidden'},
          {
            'slug': 'fixture-model-a',
            'display_name': 'Fixture A',
            'visibility': 'list'
          }
        ]
      });
    }
    if (request.path == ChatGptPlanClient.apiRoot + '/responses') {
      if (responseHandler != null) return responseHandler!(request);
      return fixtureEvents([
        {'type': 'response.output_text.delta', 'delta': 'A saved '},
        {'type': 'response.output_text.delta', 'delta': 'reply ✓'},
        fixtureCompleted,
      ]);
    }
    throw StateError('Unexpected route in the synthetic plan fixture.');
  }
}

const fixturePlanConfig = LLMConfig(
  provider: LLMProvider.chatgptPlan,
  model: 'fixture-model-b',
  apiKey: '',
  apiUrl: ChatGptPlanClient.apiRoot,
  chatgptProfileId: 'oaiapp_fixture',
  autoSummarizeEnabled: false,
);
