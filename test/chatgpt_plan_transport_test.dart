import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_tavern/domain/services/chatgpt_plan_client.dart';
import 'package:native_tavern/domain/services/chatgpt_plan_responses.dart';

import 'support/chatgpt_plan_fixture.dart';

const _events = 'event: response.output_text.delta\r\n'
    'data: {"type":"response.output_text.delta","delta":"héllo 💛"}\r\n\r\n'
    'event: response.completed\r\n'
    'data: {"type":"response.completed","response":{"status":"completed"}}\r\n\r\n';

ResponseBody _body(String text,
    {String? contentType = 'text/event-stream', int status = 200}) {
  final bytes = utf8.encode(text);
  return ResponseBody(
      Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += 3)
          Uint8List.fromList(
              bytes.sublist(i, i + 3 < bytes.length ? i + 3 : bytes.length))
      ]),
      status,
      headers: {
        if (contentType != null) Headers.contentTypeHeader: [contentType],
        'x-request-id': ['req_transport_fixture']
      });
}

Future<List<ChatGptDelta>> _run(ChatGptPlanFixture fixture) =>
    ChatGptPlanResponses(fixture.client, fixture.dio)
        .stream(
            clientId: 'oaiapp_fixture',
            model: 'gpt-6-astra',
            messages: [
              {'role': 'user', 'content': 'Synthetic transport test.'}
            ],
            cancelToken: CancelToken())
        .toList();

void main() {
  for (final contentType in <String?>[
    'text/event-stream',
    'Text/Event-Stream; Charset=UTF-8',
    'text/event-stream; charset=utf-8',
    'application/json',
    'text/plain',
    'application/octet-stream',
    null,
  ]) {
    test('documented SSE body is consumed with header $contentType', () async {
      final fixture = ChatGptPlanFixture();
      fixture.responseHandler = (_) => _body(_events, contentType: contentType);
      final chunks = await _run(fixture);
      expect(chunks.map((c) => c.text).whereType<String>().join(), 'héllo 💛');
      final request = fixture.requests.single;
      expect(request.uri.toString(), ChatGptPlanClient.apiRoot + '/responses');
      expect(request.responseType, ResponseType.stream);
      expect(request.followRedirects, isFalse);
      expect((request.data as Map)['model'], 'gpt-6-astra');
      expect((request.data as Map)['stream'], isTrue);
      expect((request.data as Map)['store'], isFalse);
    });
  }

  test('BOM, initial blank lines, keepalives and fragmented UTF-8 preserve SSE',
      () async {
    final fixture = ChatGptPlanFixture();
    fixture.responseHandler = (_) => _body(
        '\uFEFF\r\n\r\n: keepalive\r\n\r\nretry: 1000\r\nid: fixture\r\n$_events',
        contentType: null);
    expect((await _run(fixture)).single.text, 'héllo 💛');
  });

  for (final contentType in [
    'application/json',
    'text/event-stream',
    'text/plain'
  ]) {
    test('HTTP 200 JSON denial preserves code with header $contentType',
        () async {
      final fixture = ChatGptPlanFixture();
      fixture.responseHandler = (_) => _body(
          jsonEncode({
            'error': {
              'code': 'subscription_sharing_user_not_eligible',
              'param': 'model',
              'message': 'SENSITIVE_BODY_AND_BEARER'
            }
          }),
          contentType: contentType);
      await expectLater(
          _run(fixture),
          throwsA(isA<ChatGptPlanException>()
              .having((e) => e.code, 'safe server code',
                  'subscription_sharing_user_not_eligible')
              .having((e) => e.status, 'actual HTTP status', 200)
              .having((e) => e.bodyShape, 'body shape', 'error')
              .having((e) => e.param, 'parameter', 'model')
              .having((e) => e.requestId, 'request ID', 'req_transport_fixture')
              .having((e) => e.toString(), 'no raw body',
                  isNot(contains('SENSITIVE_BODY_AND_BEARER')))));
      expect(fixture.requests, hasLength(1));
    });
  }

  test('HTTP 200 detail body remains a failure with actual diagnostics',
      () async {
    final fixture = ChatGptPlanFixture();
    fixture.responseHandler = (_) => _body(
        '{"detail":"SENSITIVE_PRIVATE_SERVER_DIAGNOSTIC"}',
        contentType: 'application/json');
    await expectLater(
        _run(fixture),
        throwsA(isA<ChatGptPlanException>()
            .having((e) => e.status, 'status', 200)
            .having((e) => e.bodyShape, 'shape', 'detail')
            .having((e) => e.toString(), 'content type',
                contains('Content type: application/json'))
            .having((e) => e.toString(), 'no free-form detail',
                isNot(contains('SENSITIVE_PRIVATE_SERVER_DIAGNOSTIC')))));
  });

  test('completed JSON object is not substituted for a completed stream',
      () async {
    final fixture = ChatGptPlanFixture();
    fixture.responseHandler = (_) => _body(
        '{"object":"response","status":"completed","output":[{"text":"PRIVATE_RESPONSE"}]}',
        contentType: 'application/json');
    await expectLater(
        _run(fixture),
        throwsA(isA<ChatGptPlanException>()
            .having((e) => e.status, 'status', 200)
            .having((e) => e.bodyShape, 'shape', 'object')
            .having((e) => e.message, 'stream required', contains('stream'))
            .having((e) => e.toString(), 'no output',
                isNot(contains('PRIVATE_RESPONSE')))));
  });

  test('signed permission-context denial is retained without a login loop',
      () async {
    final fixture = ChatGptPlanFixture();
    fixture.responseHandler = (_) => _body(
        '{"error":{"code":"chatpass_v2_invalid_authorization_context"}}',
        contentType: 'application/json',
        status: 403);
    await expectLater(
        _run(fixture),
        throwsA(isA<ChatGptPlanException>()
            .having((e) => e.code, 'exact code',
                'chatpass_v2_invalid_authorization_context')
            .having((e) => e.message, 'grant recovery',
                contains('plan-usage permission'))
            .having((e) => e.message, 'no repeated sign-in advice',
                isNot(contains('Reconnect')))));
    expect(fixture.requests, hasLength(1));
  });

  test('MIME parameters and invalid header text are excluded from diagnostics',
      () async {
    for (final mime in [
      'text/plain; private=PRIVATE_HEADER',
      'PRIVATE_HEADER'
    ]) {
      final fixture = ChatGptPlanFixture();
      fixture.responseHandler =
          (_) => _body('{"detail":"PRIVATE_BODY"}', contentType: mime);
      await expectLater(
          _run(fixture),
          throwsA(isA<ChatGptPlanException>()
              .having((e) => e.toString(), 'safe MIME label',
                  contains('Content type:'))
              .having((e) => e.toString(), 'no private header/body',
                  isNot(contains('PRIVATE')))));
    }
  });

  for (final status in [401, 403, 429, 503]) {
    test('HTTP $status JSON direct admission preserves status and safe code',
        () async {
      final fixture = ChatGptPlanFixture();
      fixture.responseHandler = (_) => _body(
          '{"error":{"code":"subscription_sharing_usage_unavailable","message":"PRIVATE"}}',
          status: status,
          contentType: 'application/json; charset=utf-8');
      await expectLater(
          _run(fixture),
          throwsA(isA<ChatGptPlanException>()
              .having((e) => e.status, 'actual status', status)
              .having((e) => e.code, 'server code',
                  'subscription_sharing_usage_unavailable')
              .having((e) => e.toString(), 'content type',
                  contains('Content type: application/json'))
              .having((e) => e.toString(), 'no raw body',
                  isNot(contains('PRIVATE')))));
      expect(fixture.requests, hasLength(1));
    });
  }

  test('late SSE failure with missing MIME retains request context', () async {
    final fixture = ChatGptPlanFixture();
    fixture.responseHandler = (_) => _body(
        'data: {"type":"response.output_text.delta","delta":"partial"}\n\n'
        'data: {"type":"error","error":{"code":"subscription_sharing_usage_limit_exceeded"}}\n\n',
        contentType: null);
    await expectLater(
        _run(fixture),
        throwsA(isA<ChatGptPlanException>()
            .having((e) => e.code, 'code',
                'subscription_sharing_usage_limit_exceeded')
            .having((e) => e.status, 'HTTP context', 200)
            .having(
                (e) => e.requestId, 'request ID', 'req_transport_fixture')));
  });

  test('unknown HTML response is bounded, diagnosed and its stream cancelled',
      () async {
    final cancelled = Completer<void>();
    final controller =
        StreamController<Uint8List>(onCancel: cancelled.complete);
    final fixture = ChatGptPlanFixture();
    fixture.responseHandler = (_) {
      controller.add(Uint8List.fromList(utf8.encode('<html>PRIVATE_HTML')));
      return ResponseBody(controller.stream, 200, headers: {
        Headers.contentTypeHeader: ['text/html'],
        'x-request-id': ['req_transport_fixture']
      });
    };
    await expectLater(
        _run(fixture).timeout(const Duration(seconds: 2)),
        throwsA(isA<ChatGptPlanException>()
            .having((e) => e.status, 'status', 200)
            .having((e) => e.bodyShape, 'shape', 'non-json')
            .having((e) => e.toString(), 'MIME',
                contains('Content type: text/html'))
            .having((e) => e.toString(), 'no HTML',
                isNot(contains('PRIVATE_HTML')))));
    await cancelled.future.timeout(const Duration(seconds: 2));
    await controller.close();
  });

  test('oversized JSON diagnostics stop at the byte limit and hide the body',
      () async {
    final fixture = ChatGptPlanFixture();
    fixture.responseHandler = (_) => _body(
        jsonEncode({'detail': List.filled(70000, 'x').join()}),
        contentType: 'application/json',
        status: 403);
    await expectLater(
        _run(fixture),
        throwsA(isA<ChatGptPlanException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.bodyShape, 'bounded shape', 'truncated')));
  });

  test('invalid UTF-8 SSE remains a safe transport failure', () async {
    final fixture = ChatGptPlanFixture();
    fixture.responseHandler = (_) => ResponseBody(
            Stream.value(Uint8List.fromList(
                [...utf8.encode('data: '), 0xff, ...utf8.encode('\n\n')])),
            200,
            headers: {
              Headers.contentTypeHeader: ['text/event-stream'],
              'x-request-id': ['req_transport_fixture']
            });
    await expectLater(
        _run(fixture),
        throwsA(isA<ChatGptPlanException>()
            .having((e) => e.status, 'status', 200)
            .having((e) => e.requestId, 'request ID', 'req_transport_fixture')
            .having((e) => e.message, 'safe diagnostic', contains('invalid'))));
  });

  for (final contentType in [
    'Text/Event-Stream; Charset=UTF-8',
    'application/json',
    'text/plain'
  ]) {
    test('real Dio IO adapter handles SSE over loopback with $contentType',
        () async {
      final server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
      final received = <Map<String, dynamic>>[];
      final listener = server.listen((request) async {
        final payload = await request
            .map<List<int>>((chunk) => chunk)
            .transform(utf8.decoder)
            .join();
        received.add(jsonDecode(payload) as Map<String, dynamic>);
        request.response.headers.set(Headers.contentTypeHeader, contentType);
        request.response.headers.set('x-request-id', 'req_loopback_fixture');
        await request.response.addStream(_body(_events).stream);
        await request.response.close();
      });
      final native = IOHttpClientAdapter();
      final fixture = ChatGptPlanFixture();
      fixture.responseHandler = (request) {
        expect(
            request.uri.toString(), ChatGptPlanClient.apiRoot + '/responses');
        expect(request.headers['Authorization'],
            'Bearer synthetic-oaiapp_fixture');
        final local = request.copyWith(
            path: 'http://127.0.0.1:' + server.port.toString() + '/responses');
        return native.fetch(
            local,
            Stream.value(
                Uint8List.fromList(utf8.encode(jsonEncode(request.data)))),
            null);
      };
      try {
        final chunks = await _run(fixture);
        expect(chunks.single.text, 'héllo 💛');
        expect(received.single['model'], 'gpt-6-astra');
        expect(received.single['stream'], isTrue);
        expect(received.single['store'], isFalse);
      } finally {
        native.close(force: true);
        await listener.cancel();
        await server.close(force: true);
      }
    });
  }
}
