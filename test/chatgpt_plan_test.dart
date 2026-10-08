import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:native_tavern/domain/services/chatgpt_plan_client.dart';
import 'package:native_tavern/domain/services/chatgpt_plan_responses.dart';
import 'package:native_tavern/domain/services/chatgpt_plan_platform.dart';
import 'package:native_tavern/domain/services/llm_service.dart';
import 'package:native_tavern/domain/services/tool_calling/tool_generation_loop.dart';

class _MemoryStore implements ChatGptCredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object value, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(value), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

class _Fixture {
  _Fixture(this.key) {
    dio = Dio()..httpClientAdapter = _Adapter(handle);
    client = ChatGptPlanClient(store: store, dio: dio);
  }
  final JsonWebKey key;
  final store = _MemoryStore();
  late final Dio dio;
  late final ChatGptPlanClient client;
  Map<String, String> auth = {};
  Map<String, dynamic> identityOverrides = {};
  int exchanges = 0;
  int refreshes = 0;
  bool grantSharing = true;
  String Function(String)? tokenMutator;
  String? refreshError;
  String? exchangeError;
  bool includeRefresh = true;
  bool revocationFails = false;
  String issued = 'oaiapp_fixture1';
  final tokenForms = <Map<String, dynamic>>[];
  String jwt() {
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = {
        'iss': ChatGptPlanClient.issuer,
        'aud': issued,
        'sub': 'fixture-user',
        'email': 'test@example.invalid',
        'nonce': auth['nonce'],
        'exp': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        ...identityOverrides
      }
      ..addRecipient(key, algorithm: 'RS256');
    return builder.build().toCompactSerialization();
  }

  Future<ResponseBody> handle(RequestOptions r) async {
    expect(r.followRedirects, isFalse);
    if (r.path.endsWith('/jwks.json')) {
      final public = Map<String, dynamic>.from(key.toJson())
        ..remove('d')
        ..remove('p')
        ..remove('q')
        ..remove('dp')
        ..remove('dq')
        ..remove('qi')
        ..remove('key_ops');
      return _json({
        'keys': [public]
      });
    }
    if (r.path.endsWith('/openid-configuration'))
      return _json({
        'issuer': ChatGptPlanClient.issuer,
        'revocation_endpoint': '${ChatGptPlanClient.issuer}/revoke'
      });
    if (r.path.endsWith('/revoke'))
      return revocationFails
          ? _json({}, status: 503)
          : ResponseBody.fromString('', 200);
    if (r.path.endsWith('/oauth/token')) {
      final form = r.data is Map
          ? Map<String, dynamic>.from(r.data as Map)
          : Uri.splitQueryString(r.data as String);
      tokenForms.add(form);
      expect(form['client_id'], issued);
      expect(form['resource'], ChatGptPlanClient.apiRoot);
      if (form['grant_type'] == 'refresh_token') {
        expect(form.containsKey('scope'), isFalse);
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 15));
        if (refreshError != null)
          return _json({'error': refreshError}, status: 400);
        return _json({
          'token_type': 'Bearer',
          'access_token': 'fixture-access-new',
          'refresh_token': 'fixture-refresh-new',
          'expires_in': 3600
        });
      }
      exchanges++;
      if (exchangeError != null)
        return _json({'error': exchangeError}, status: 400);
      expect(form['redirect_uri'], auth['redirect_uri']);
      expect(
          base64UrlEncode(sha256
                  .convert(ascii.encode(form['code_verifier'] as String))
                  .bytes)
              .replaceAll('=', ''),
          auth['code_challenge']);
      return _json({
        'token_type': 'Bearer',
        'access_token': 'fixture-access',
        if (includeRefresh) 'refresh_token': 'fixture-refresh',
        'id_token': tokenMutator?.call(jwt()) ?? jwt(),
        'expires_in': 3600,
        'scope':
            grantSharing ? ChatGptPlanClient.scopes : 'openid profile email'
      });
    }
    if (r.path.endsWith('/models'))
      return _json({
        'models': [
          {
            'slug': 'fixture-model-b',
            'display_name': 'B',
            'visibility': 'list'
          },
          {'slug': 'hidden', 'visibility': 'hidden'},
          {'slug': 'fixture-model-a', 'display_name': 'A', 'visibility': 'list'}
        ]
      });
    throw StateError('Unexpected fixture request route');
  }

  Future<ChatGptAccount> login(
          {String? clientId,
          Uri Function(Uri)? alter,
          bool enableSharing = false}) =>
      client.signIn(
          clientId: clientId,
          enableSharing: enableSharing,
          redirectUri: Uri.parse('http://127.0.0.1:54321/auth/callback'),
          authorize: (url, state) async {
            auth = url.queryParameters;
            expect(url.origin, ChatGptPlanClient.issuer);
            expect(auth['scope'], contains(ChatGptPlanClient.planScope));
            expect(auth['code_challenge_method'], 'S256');
            final callback = Uri.parse(auth['redirect_uri']!).replace(
                queryParameters: {
                  'state': state,
                  'code': 'fixture-code',
                  'client_id': issued
                });
            return alter?.call(callback) ?? callback;
          });
  void expire() {
    final data = jsonDecode(store.value!) as Map<String, dynamic>;
    ((data['accounts'] as List).first as Map)['expires_at'] = 0;
    store.value = jsonEncode(data);
  }
}

Stream<List<int>> _sse(List<Map<String, dynamic>> events,
    {bool fragmented = false}) async* {
  final data = utf8.encode(events
      .map((e) => 'event: ${e['type']}\r\ndata: ${jsonEncode(e)}\r\n\r\n')
      .join());
  if (fragmented) {
    for (final b in data) {
      yield [b];
    }
  } else {
    yield data;
  }
}

const _complete = {
  'type': 'response.completed',
  'response': {'status': 'completed'}
};

void main() {
  late JsonWebKey key;
  setUpAll(() {
    final generated = JsonWebKey.generate('RS256', keyBitLength: 2048);
    key = JsonWebKey.fromJson(
        {...generated.toJson(), 'kid': 'fixture-signing-key'});
  });
  test(
      'official dynamic registration verifies identity and persists a stable host',
      () async {
    final f = _Fixture(key);
    final account = await f.login();
    expect(account.sharing, isTrue);
    expect(f.auth['client_id'], 'dynamic_agent_client');
    expect(f.auth['agent_name_hint'], 'NativeTavern');
    final host = f.auth['ext_agent_host_id'];
    expect(host, startsWith('urn:uuid:'));
    await f.login(clientId: account.clientId);
    expect(f.auth['client_id'], account.clientId);
    expect(f.auth.containsKey('agent_name_hint'), isFalse);
    expect(f.auth['ext_agent_host_id'], host);
    expect((await f.client.accounts()).length, 1);
  });
  test('callback state mismatch and duplicate parameters never exchange a code',
      () async {
    final f = _Fixture(key);
    await expectLater(
        f.login(
            alter: (u) => u.replace(
                queryParameters: {...u.queryParameters, 'state': 'wrong'})),
        throwsA(isA<ChatGptPlanException>()));
    await expectLater(
        f.login(alter: (u) => u.replace(query: '${u.query}&state=again')),
        throwsA(isA<ChatGptPlanException>()));
    expect(f.exchanges, 0);
  });
  test('callback denial and substituted client never exchange a code',
      () async {
    final f = _Fixture(key);
    await expectLater(
        f.login(
            alter: (u) => u.replace(queryParameters: {
                  ...u.queryParameters,
                  'error': 'access_denied'
                })),
        throwsA(isA<ChatGptPlanException>()));
    await f.login();
    final before = f.exchanges;
    await expectLater(
        f.login(
            clientId: f.issued,
            alter: (u) => u.replace(queryParameters: {
                  ...u.queryParameters,
                  'client_id': 'oaiapp_other'
                })),
        throwsA(isA<ChatGptPlanException>()));
    expect(f.exchanges, before);
  });
  test('nonce, issuer, expiry and audience failures never save credentials',
      () async {
    for (final override in [
      {'nonce': 'wrong'},
      {'iss': 'https://attacker.invalid'},
      {'exp': 1},
      {'aud': 'wrong-client'}
    ]) {
      final f = _Fixture(key)..identityOverrides = override;
      await expectLater(f.login(), throwsA(isA<ChatGptPlanException>()));
      expect(await f.client.accounts(), isEmpty);
      expect(f.store.value, isNot(contains('fixture-access')));
    }
  });
  test('reconnecting rejects changed subject without overwriting old session',
      () async {
    final f = _Fixture(key);
    await f.login();
    final before = f.store.value;
    f.identityOverrides = {'sub': 'someone-else'};
    await expectLater(
        f.login(clientId: f.issued), throwsA(isA<ChatGptPlanException>()));
    expect(f.store.value, before);
  });
  test(
      'identity-only login cannot perform inference and supports explicit reconsent',
      () async {
    final f = _Fixture(key)..grantSharing = false;
    final account = await f.login();
    expect(account.sharing, isFalse);
    await expectLater(f.client.accessToken(account.clientId),
        throwsA(isA<ChatGptPlanException>()));
    f.grantSharing = true;
    await f.login(clientId: account.clientId, enableSharing: true);
    expect(f.auth['prompt'], 'consent');
    expect(await f.client.accessToken(account.clientId), 'fixture-access');
  });
  test('multiple registrations with the same email stay separate', () async {
    final f = _Fixture(key);
    await f.login();
    f.issued = 'oaiapp_fixture2';
    await f.login();
    expect((await f.client.accounts()).map((a) => a.clientId),
        ['oaiapp_fixture1', 'oaiapp_fixture2']);
  });
  test(
      'concurrent expiry refreshes rotate once and preserve credentials atomically',
      () async {
    final f = _Fixture(key);
    await f.login();
    f.expire();
    final tokens = await Future.wait(
        [f.client.accessToken(f.issued), f.client.accessToken(f.issued)]);
    expect(tokens, ['fixture-access-new', 'fixture-access-new']);
    expect(f.refreshes, 1);
    expect(f.store.value, contains('fixture-refresh-new'));
    expect(f.store.value, isNot(contains('"fixture-refresh"')));
  });
  test('terminal refresh failure clears tokens but retains registration',
      () async {
    final f = _Fixture(key);
    await f.login();
    f.expire();
    f.refreshError = 'invalid_grant';
    await expectLater(
        f.client.accessToken(f.issued), throwsA(isA<ChatGptPlanException>()));
    expect(f.store.value, isNot(contains('fixture-access')));
    final account = (await f.client.accounts()).single;
    expect(account.clientId, f.issued);
    expect(account.connected, isFalse);
  });
  test('temporary refresh failure preserves session', () async {
    final f = _Fixture(key);
    await f.login();
    f.expire();
    f.refreshError = 'temporarily_unavailable';
    final before = f.store.value;
    await expectLater(
        f.client.accessToken(f.issued), throwsA(isA<ChatGptPlanException>()));
    expect(f.store.value, before);
  });
  test('sign-out reports failed remote revocation and clears local secrets',
      () async {
    final f = _Fixture(key);
    await f.login();
    f.revocationFails = true;
    expect(await f.client.signOut(f.issued), isFalse);
    expect(f.store.value, isNot(contains('fixture-access')));
    expect(f.store.value, isNot(contains('fixture-refresh')));
    expect((await f.client.accounts()).single.connected, isFalse);
  });
  test('model discovery uses the account catalog order and visibility',
      () async {
    final f = _Fixture(key);
    await f.login();
    expect((await f.client.models(f.issued)).map((m) => m.slug),
        ['fixture-model-b', 'fixture-model-a']);
  });
  test(
      'request preserves prompt order, changes system to developer, and omits unsupported fields',
      () {
    final request = chatGptPlanRequest('fixture-model', [
      {'role': 'system', 'content': 'Character instructions'},
      {'role': 'user', 'content': 'Hello'},
      {'role': 'system', 'content': 'Late author note'},
      {'role': 'assistant', 'content': 'Hi'}
    ]);
    expect(request.keys.toSet(), {'model', 'input', 'store', 'stream'});
    expect(request['store'], isFalse);
    expect(request['stream'], isTrue);
    final input = request['input'] as List;
    expect(input.map((m) => (m as Map)['role']),
        ['developer', 'user', 'developer', 'assistant']);
    expect(
        () => chatGptPlanRequest('fixture', [
              {'role': 'tool', 'content': 'output'}
            ]),
        throwsA(isA<ChatGptPlanException>()));
  });
  test('image message conversion and assistant text history are supported', () {
    final request = chatGptPlanRequest('fixture', [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Look'},
          {
            'type': 'image_url',
            'image_url': {
              'url': 'https://example.invalid/image.png',
              'detail': 'low'
            }
          }
        ]
      },
      {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'Description'}
        ]
      }
    ]);
    final input = request['input'] as List;
    expect(((input.first as Map)['content'] as List).last, {
      'type': 'input_image',
      'image_url': 'https://example.invalid/image.png',
      'detail': 'low'
    });
    expect((input.last as Map)['content'], 'Description');
  });
  test('fragmented UTF-8 and CRLF SSE text and reasoning emit once', () async {
    final chunks = await parseChatGptPlanStream(_sse([
      {'type': 'response.reasoning_summary_text.delta', 'delta': 'summary'},
      {'type': 'response.output_text.delta', 'delta': 'héllo 💛'},
      _complete
    ], fragmented: true))
        .toList();
    expect(chunks.map((c) => c.text).whereType<String>().join(), 'héllo 💛');
    expect(chunks.first.reasoning, 'summary');
  });
  test(
      'failure after partial output and EOF never report successful completion',
      () async {
    await expectLater(
        parseChatGptPlanStream(_sse([
          {'type': 'response.output_text.delta', 'delta': 'partial'},
          {
            'type': 'response.failed',
            'response': {
              'error': {'code': 'subscription_sharing_usage_limit_exceeded'}
            }
          }
        ])).toList(),
        throwsA(isA<ChatGptPlanException>()));
    await expectLater(
        parseChatGptPlanStream(_sse([
          {'type': 'response.output_text.delta', 'delta': 'partial'}
        ])).toList(),
        throwsA(isA<ChatGptPlanException>()));
    await expectLater(
        parseChatGptPlanStream(Stream.value(utf8.encode('data: [DONE]\n\n')))
            .toList(),
        throwsA(isA<ChatGptPlanException>()));
  });
  test(
      'LLMService plan provider uses Responses even with a configured custom URL',
      () async {
    final f = _Fixture(key);
    await f.login();
    final calls = <String>[];
    final dio = Dio()
      ..httpClientAdapter = _Adapter((r) {
        calls.add(r.uri.toString());
        expect(r.uri.toString(), '${ChatGptPlanClient.apiRoot}/responses');
        expect(r.headers['Authorization'], 'Bearer fixture-access');
        expect(r.followRedirects, isFalse);
        final body = r.data as Map;
        expect(body['stream'], isTrue);
        expect(body['store'], isFalse);
        expect(body.containsKey('temperature'), isFalse);
        final bytes = utf8.encode(
            'data: {"type":"response.output_text.delta","delta":"Done."}\n\ndata: {"type":"response.completed","response":{"status":"completed"}}\n\n');
        return ResponseBody(Stream.value(Uint8List.fromList(bytes)), 200,
            headers: {
              Headers.contentTypeHeader: ['text/event-stream']
            });
      });
    final config = LLMConfig(
        provider: LLMProvider.chatgptPlan,
        model: 'fixture-model',
        apiKey: 'must-not-use',
        apiUrl: 'https://attacker.invalid',
        chatgptProfileId: f.issued);
    expect(
        await LLMService(dio: dio, chatGptClient: f.client).generate([
          {'role': 'user', 'content': 'Hi'}
        ], config),
        'Done.');
    expect(calls, hasLength(1));
    expect(config.toJson()['apiKey'], '');
    expect(
        ToolGenerationLoop.adapterForProvider(LLMProvider.chatgptPlan), isNull);
  });
  test('direct admission denial has no automatic retry or API billing fallback',
      () async {
    final f = _Fixture(key);
    await f.login();
    var count = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((r) {
        count++;
        return _json({
          'error': {'code': 'subscription_sharing_user_not_eligible'}
        }, status: 403);
      });
    await expectLater(
        ChatGptPlanResponses(f.client, dio)
            .stream(
                clientId: f.issued,
                model: 'fixture',
                messages: [
                  {'role': 'user', 'content': 'Hi'}
                ],
                cancelToken: CancelToken())
            .toList(),
        throwsA(isA<ChatGptPlanException>()));
    expect(count, 1);
  });

  test(
      'tampered JWT, algorithm substitution, and untrusted key ID are rejected',
      () async {
    for (final mutation in ['payload', 'algorithm', 'kid']) {
      final f = _Fixture(key);
      f.tokenMutator = (token) {
        final parts = token.split('.');
        final index = mutation == 'payload' ? 1 : 0;
        final data = jsonDecode(utf8
                .decode(base64Url.decode(base64Url.normalize(parts[index]))))
            as Map<String, dynamic>;
        if (mutation == 'payload') data['sub'] = 'substituted-user';
        if (mutation == 'algorithm') data['alg'] = 'none';
        if (mutation == 'kid') data['kid'] = 'untrusted-key';
        parts[index] =
            base64UrlEncode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
        return parts.join('.');
      };
      await expectLater(f.login(), throwsA(isA<ChatGptPlanException>()));
      expect(await f.client.accounts(), isEmpty);
    }
  });

  test(
      'loopback callback validates state, returns no secrets, and closes its port',
      () async {
    final f = _Fixture(key);
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    Uri? callback;
    var closed = false;
    final platform = ChatGptPlanPlatform(
      client: f.client,
      openBrowser: (url) async {
        f.auth = url.queryParameters;
        callback = Uri.parse(f.auth['redirect_uri']!);
        expect(callback!.host, '127.0.0.1');
        expect(callback!.scheme, 'http');
        final bad =
            await (await http.getUrl(callback!.replace(queryParameters: {
          'state': 'bad-state',
          'code': 'fixture-code',
          'client_id': f.issued,
        })))
                .close();
        expect(bad.statusCode, 400);
        await bad.drain<void>();
        final good =
            await (await http.getUrl(callback!.replace(queryParameters: {
          'state': f.auth['state']!,
          'code': 'fixture-code',
          'client_id': f.issued,
        })))
                .close();
        expect(good.statusCode, 200);
        expect(good.headers.value('Cache-Control'), 'no-store');
        final text = await good.transform(utf8.decoder).join();
        expect(text, isNot(contains('fixture-code')));
        expect(text, isNot(contains(f.auth['state']!)));
      },
      closeBrowser: () async {
        closed = true;
      },
    );
    try {
      final account = await platform.signIn();
      expect(account.sharing, isTrue);
      expect(closed, isTrue);
      final probe = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 500);
      try {
        await expectLater(
            probe.getUrl(callback!), throwsA(isA<SocketException>()));
      } finally {
        probe.close(force: true);
      }
    } finally {
      http.close(force: true);
    }
  });

  test(
      'cancelled and timed-out login exchange no tokens and release the listener',
      () async {
    final f = _Fixture(key);
    final opened = Completer<void>();
    var closed = false;
    final platform = ChatGptPlanPlatform(
      client: f.client,
      openBrowser: (_) async {
        opened.complete();
      },
      closeBrowser: () async {
        closed = true;
      },
    );
    final attempt = platform.signIn();
    final rejected = expectLater(attempt, throwsA(isA<ChatGptPlanException>()));
    await opened.future;
    await expectLater(platform.signIn(), throwsA(isA<ChatGptPlanException>()));
    platform.cancelSignIn();
    await rejected;
    expect(closed, isTrue);
    expect(f.exchanges, 0);
    final timed = ChatGptPlanPlatform(
      client: f.client,
      openBrowser: (_) async {},
      closeBrowser: () async {},
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(timed.signIn(), throwsA(isA<ChatGptPlanException>()));
    expect(f.exchanges, 0);
  });

  test(
      'plan transcript is not trimmed or merged by other provider context processing',
      () async {
    final f = _Fixture(key);
    await f.login();
    final original = [
      {'role': 'system', 'content': 'Character instructions'},
      {'role': 'user', 'content': List.filled(1000, 'Long history.').join(' ')},
      {'role': 'user', 'content': 'Distinct consecutive user message'},
      {'role': 'assistant', 'content': 'Previous answer'},
      {'role': 'system', 'content': 'Later author note'},
      {'role': 'user', 'content': 'New message'},
    ];
    final dio = Dio()
      ..httpClientAdapter = _Adapter((r) {
        final input = (r.data as Map)['input'] as List;
        expect(input.length, original.length);
        expect(input[1]['content'], original[1]['content']);
        expect(input[2]['content'], original[2]['content']);
        return ResponseBody(
            _sse([
              {'type': 'response.output_text.delta', 'delta': 'Done'},
              _complete
            ]).map((bytes) => Uint8List.fromList(bytes)),
            200,
            headers: {
              Headers.contentTypeHeader: ['text/event-stream']
            });
      });
    final result = await LLMService(dio: dio, chatGptClient: f.client).generate(
        original,
        LLMConfig(
            provider: LLMProvider.chatgptPlan,
            model: 'fixture',
            apiKey: '',
            apiUrl: ChatGptPlanClient.apiRoot,
            chatgptProfileId: f.issued,
            contextLength: 64,
            maxTokens: 32,
            mergeConsecutiveRoles: true));
    expect(result, 'Done');
  });

  test('multiline SSE data joins actual newlines', () async {
    final bytes = utf8.encode(
        'data: {"type":"response.output_text.delta",\ndata: "delta":"Hi"}\n\n'
        'data: {"type":"response.completed","response":{"status":"completed"}}\n\n');
    final output = await parseChatGptPlanStream(Stream.value(bytes)).toList();
    expect(output.single.text, 'Hi');
  });

  test(
      'identity-only sign-in without offline access retains identity but denies inference',
      () async {
    final f = _Fixture(key)
      ..grantSharing = false
      ..includeRefresh = false;
    final account = await f.login();
    expect(account.connected, isTrue);
    expect(account.sharing, isFalse);
    expect(f.store.value, isNot(contains('refresh_token')));
    await expectLater(
        f.client.accessToken(f.issued), throwsA(isA<ChatGptPlanException>()));
    f.grantSharing = true;
    f.includeRefresh = true;
    expect((await f.login(clientId: f.issued, enableSharing: true)).sharing,
        isTrue);
  });

  test(
      'expired code retains only issued registration and reauthorization reuses it',
      () async {
    final f = _Fixture(key)..exchangeError = 'invalid_grant';
    await expectLater(f.login(), throwsA(isA<ChatGptPlanException>()));
    final pending = (await f.client.accounts()).single;
    expect(pending.clientId, f.issued);
    expect(pending.connected, isFalse);
    expect(pending.sharing, isFalse);
    expect(f.store.value, isNot(contains('fixture-access')));
    expect(f.store.value, isNot(contains('fixture-user')));
    f.exchangeError = null;
    expect((await f.login(clientId: pending.clientId)).connected, isTrue);
    expect(f.auth['client_id'], pending.clientId);
    expect(await f.client.accounts(), hasLength(1));
  });
  test('successful sign-out revokes the renewable session then removes tokens',
      () async {
    final f = _Fixture(key);
    await f.login();
    expect(await f.client.signOut(f.issued), isTrue);
    expect((await f.client.accounts()).single.connected, isFalse);
    expect(f.store.value, isNot(contains('fixture-access')));
    expect(f.store.value, isNot(contains('fixture-refresh')));
  });

  test(
      'direct error diagnostics retain shape and request ID without raw detail or tokens',
      () {
    final options =
        RequestOptions(path: '${ChatGptPlanClient.apiRoot}/responses');
    final e = ChatGptPlanClient.safeHttpFailure(DioException(
        requestOptions: options,
        response: Response<dynamic>(
            requestOptions: options,
            statusCode: 403,
            data: {'detail': 'fixture-secret-in-diagnostic'},
            headers: Headers.fromMap({
              'x-request-id': ['req_fixture']
            }))));
    expect(e.bodyShape, 'detail');
    expect(e.requestId, 'req_fixture');
    expect(e.status, 403);
    expect(e.toString(), isNot(contains('fixture-secret')));
  });
  test(
      'nested SSE permission errors retain safe code and parameter diagnostics',
      () async {
    try {
      await parseChatGptPlanStream(_sse([
        {
          'type': 'error',
          'error': {
            'code': 'chatpass_v2_scope_not_authorized',
            'param': 'input',
            'message': 'fixture-secret-must-not-be-shown',
          }
        }
      ])).toList();
      fail('A permission failure must not complete successfully.');
    } on ChatGptPlanException catch (e) {
      expect(e.code, 'chatpass_v2_scope_not_authorized');
      expect(e.param, 'input');
      expect(e.toString(), contains('Enable plan usage'));
      expect(e.toString(), isNot(contains('fixture-secret')));
    }
  });
}
