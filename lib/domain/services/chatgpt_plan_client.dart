import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:jose/jose.dart';

/// Official SIWC public-client flow. No Codex client IDs or backend-api routes.
abstract interface class ChatGptCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
}

typedef ChatGptAuthorize = Future<Uri> Function(Uri url, String state);

class ChatGptPlanException implements Exception {
  const ChatGptPlanException(this.message,
      {this.code, this.status, this.requestId, this.param, this.bodyShape});
  final String message;
  final String? code;
  final int? status;
  final String? requestId;
  final String? param;
  final String? bodyShape;
  @override
  String toString() => [
        message,
        if (code != null) 'Code: $code',
        if (status != null) 'HTTP $status',
        if (requestId != null) 'Request: $requestId',
        if (param != null) 'Parameter: $param',
        if (bodyShape != null) 'Response shape: $bodyShape'
      ].join('\n');
}

/// Display data only. Credentials never leave the auth service for the UI.
class ChatGptAccount {
  const ChatGptAccount(this.clientId, this.label, this.connected, this.sharing);
  final String clientId;
  final String label;
  final bool connected;
  final bool sharing;
}

class ChatGptModel {
  const ChatGptModel(this.slug, this.name);
  final String slug;
  final String name;
}

class ChatGptPlanClient {
  ChatGptPlanClient({required this.store, Dio? dio, DateTime Function()? now})
      : _dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
                followRedirects: false)),
        _now = now ?? DateTime.now;
  static const issuer = 'https://auth.openai.com';
  static const apiRoot = 'https://api.openai.com/v1';
  static const authorizeUrl = '$issuer/api/accounts/authorize';
  static const tokenUrl = '$issuer/api/accounts/oauth/token';
  static const scopes =
      'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';
  static const planScope = 'chatgpt.tokens.use.direct';
  final ChatGptCredentialStore store;
  final Dio _dio;
  final DateTime Function() _now;
  Future<void> _queue = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final future = _queue.then((_) => action());
    _queue = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return future;
  }

  Future<Map<String, dynamic>> _load() async {
    final raw = await store.read();
    if (raw == null) {
      final fresh = <String, dynamic>{
        'host_id': _hostId(),
        'accounts': <dynamic>[]
      };
      await store.write(jsonEncode(fresh));
      return fresh;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['host_id'] is! String || data['accounts'] is! List)
        throw const FormatException();
      return data;
    } catch (_) {
      throw const ChatGptPlanException(
          'Protected ChatGPT settings could not be read. Do not replace them with an API key.');
    }
  }

  List<Map<String, dynamic>> _accounts(Map<String, dynamic> data) =>
      (data['accounts'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Map<String, dynamic> _account(Map<String, dynamic> data, String clientId) =>
      _accounts(data).firstWhere((a) => a['client_id'] == clientId,
          orElse: () => throw const ChatGptPlanException(
              'Choose a saved ChatGPT account or sign in first.'));

  Future<void> _saveAccount(
      Map<String, dynamic> data, Map<String, dynamic> account) async {
    final accounts = _accounts(data);
    final index =
        accounts.indexWhere((a) => a['client_id'] == account['client_id']);
    if (index < 0) {
      accounts.add(account);
    } else {
      accounts[index] = account;
    }
    data['accounts'] = accounts;
    await store.write(jsonEncode(
        data)); // One atomic Keychain item, including rotating refresh token.
  }

  Future<List<ChatGptAccount>> accounts() => _exclusive(() async {
        final data = await _load();
        return _accounts(data)
            .map((a) => ChatGptAccount(
                a['client_id'] as String,
                '${a['email'] ?? 'ChatGPT account'} · ${(a['client_id'] as String).substring((a['client_id'] as String).length > 8 ? (a['client_id'] as String).length - 8 : 0)}',
                a['access_token'] is String,
                (a['scopes'] as List? ?? []).contains(planScope)))
            .toList();
      });

  Future<ChatGptAccount> signIn(
          {required Uri redirectUri,
          required ChatGptAuthorize authorize,
          String? clientId,
          bool enableSharing = false}) =>
      _exclusive(() async {
        if (redirectUri.scheme != 'http' ||
            redirectUri.host != '127.0.0.1' ||
            redirectUri.path != '/auth/callback' ||
            !redirectUri.hasPort ||
            redirectUri.hasQuery ||
            redirectUri.hasFragment ||
            redirectUri.userInfo.isNotEmpty) {
          throw const ChatGptPlanException(
              'Sign-in requires the documented HTTP loopback callback.');
        }
        final data = await _load();
        final existing = clientId == null ? null : _account(data, clientId);
        final state = _random();
        final nonce = _random();
        final verifier = _random();
        final params = <String, String>{
          'client_id': clientId ?? 'dynamic_agent_client',
          if (clientId == null) 'agent_name_hint': 'NativeTavern',
          'ext_agent_host_id': data['host_id'] as String,
          'response_type': 'code',
          'redirect_uri': redirectUri.toString(),
          'scope': scopes,
          'resource': apiRoot,
          'state': state,
          'nonce': nonce,
          'code_challenge_method': 'S256',
          'code_challenge':
              base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
                  .replaceAll('=', ''),
          if (existing?['id_token'] is String)
            'id_token_hint': existing!['id_token'] as String,
          if (existing?['email'] is String)
            'login_hint': existing!['email'] as String,
          if (enableSharing) 'prompt': 'consent',
        };
        final callback = await authorize(
            Uri.parse(authorizeUrl).replace(queryParameters: params), state);
        if (callback.scheme != redirectUri.scheme ||
            callback.host != redirectUri.host ||
            callback.port != redirectUri.port ||
            callback.path != redirectUri.path ||
            callback.hasFragment ||
            callback.userInfo.isNotEmpty ||
            callback.queryParametersAll.values.any((v) => v.length != 1) ||
            !_same(callback.queryParameters['state'] ?? '', state)) {
          throw const ChatGptPlanException(
              'Sign-in callback validation failed.');
        }
        final query = callback.queryParameters;
        if (query.containsKey('error')) {
          throw const ChatGptPlanException(
              'ChatGPT sign-in was declined or cancelled.',
              code: 'access_denied');
        }
        final issuedId = query['client_id'] ?? clientId;
        if (issuedId == null ||
            !RegExp(r'^oaiapp_[A-Za-z0-9_-]+$').hasMatch(issuedId) ||
            (clientId != null && issuedId != clientId) ||
            (query['code'] ?? '').isEmpty) {
          throw const ChatGptPlanException(
              'Sign-in did not return the expected registered client.');
        }
        Map<String, dynamic> tokens;
        try {
          tokens = await _form(tokenUrl, {
            'grant_type': 'authorization_code',
            'client_id': issuedId,
            'code': query['code']!,
            'code_verifier': verifier,
            'redirect_uri': redirectUri.toString(),
            'resource': apiRoot,
          });
        } on ChatGptPlanException catch (error) {
          // A consumed/expired code must not cause duplicate dynamic registrations.
          // Save only the opaque ID, never an unverified identity or credentials.
          if (error.code == 'invalid_grant' &&
              existing == null &&
              !_accounts(data).any((a) => a['client_id'] == issuedId)) {
            await _saveAccount(data, {
              'client_id': issuedId,
              'registration_pending': true,
            });
          }
          rethrow;
        }
        final identity = await _verifyIdentity(tokens['id_token'], issuedId,
            nonce: nonce, subject: existing?['subject'] as String?);
        final newAccount = _tokenRecord(tokens, {
          'client_id': issuedId,
          'subject': identity['sub'],
          'email': identity['email'] is String
              ? identity['email']
              : 'ChatGPT account',
        });
        // Existing registrations never change identity, including when emails match.
        if (existing == null) {
          for (final prior in _accounts(data)) {
            if (prior['client_id'] == issuedId &&
                prior['subject'] is String &&
                prior['subject'] != identity['sub']) {
              throw const ChatGptPlanException(
                  'The saved registration belongs to another account.');
            }
          }
        }
        await _saveAccount(data, newAccount);
        return ChatGptAccount(issuedId, newAccount['email'] as String, true,
            (newAccount['scopes'] as List).contains(planScope));
      });

  Future<Map<String, dynamic>> _verifyIdentity(dynamic raw, String clientId,
      {String? nonce, String? subject}) async {
    if (raw is! String)
      throw const ChatGptPlanException('Missing verified ChatGPT identity.');
    try {
      final parts = raw.split('.');
      if (parts.length != 3) throw const FormatException();
      final header = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))))
          as Map<String, dynamic>;
      if (header['alg'] != 'RS256' ||
          header['kid'] is! String ||
          header.containsKey('jku') ||
          header.containsKey('jwk') ||
          header.containsKey('x5u')) {
        throw const FormatException();
      }
      final response = await _dio.get<Map<String, dynamic>>(
          '$issuer/.well-known/jwks.json',
          options: Options(followRedirects: false));
      final keys = response.data?['keys'] as List;
      final keyStore = JsonWebKeyStore();
      for (final rawKey in keys) {
        final key = Map<String, dynamic>.from(rawKey as Map);
        if (key['kty'] == 'RSA' &&
            key['kid'] == header['kid'] &&
            (key['alg'] == null || key['alg'] == 'RS256') &&
            (key['use'] == null || key['use'] == 'sig')) {
          keyStore.addKey(JsonWebKey.fromJson(key));
        }
      }
      final jwt = JsonWebToken.unverified(raw);
      if (!await jwt.verify(keyStore, allowedArguments: ['RS256']))
        throw const FormatException();
      final claims = Map<String, dynamic>.from(jwt.claims.toJson());
      final aud = claims['aud'];
      final seconds = _now().millisecondsSinceEpoch ~/ 1000;
      if (claims['iss'] != issuer ||
          !(aud == clientId || aud is List && aud.contains(clientId)) ||
          claims['exp'] is! num ||
          (claims['exp'] as num) <= seconds ||
          (claims['nbf'] is num && (claims['nbf'] as num) > seconds + 30) ||
          (claims['iat'] is num && (claims['iat'] as num) > seconds + 30) ||
          (claims['sub'] is! String || (claims['sub'] as String).isEmpty) ||
          (nonce != null && !_same(claims['nonce'] as String? ?? '', nonce)) ||
          (subject != null && claims['sub'] != subject) ||
          (aud is List && aud.length > 1 && claims['azp'] != clientId)) {
        throw const FormatException();
      }
      return claims;
    } catch (_) {
      throw const ChatGptPlanException(
          'ChatGPT identity signature or claims could not be verified.');
    }
  }

  Map<String, dynamic> _tokenRecord(
      Map<String, dynamic> tokens, Map<String, dynamic> previous) {
    final granted = tokens['scope'] is String
        ? (tokens['scope'] as String).split(' ')
        : List<String>.from(previous['scopes'] as List? ?? const []);
    final refresh = tokens['refresh_token'];
    if (tokens['access_token'] is! String ||
        (tokens['access_token'] as String).isEmpty ||
        tokens['token_type'] is! String ||
        (tokens['token_type'] as String).toLowerCase() != 'bearer' ||
        tokens['expires_in'] is! num ||
        (tokens['expires_in'] as num) <= 0 ||
        (granted.contains(planScope) &&
            (refresh is! String || refresh.isEmpty))) {
      throw const ChatGptPlanException(
          'OpenAI returned an incomplete session. Plan sharing requires a renewable grant.');
    }
    // An identity-only sign-in may lack offline_access and a refresh token.
    // It stays connected for re-consent but cannot perform inference.
    return {
      ...previous,
      'access_token': tokens['access_token'],
      if (refresh is String && refresh.isNotEmpty) 'refresh_token': refresh,
      if (tokens['id_token'] is String) 'id_token': tokens['id_token'],
      'scopes': granted,
      'expires_at': _now()
          .add(Duration(seconds: (tokens['expires_in'] as num).toInt()))
          .millisecondsSinceEpoch
    };
  }

  Future<String> accessToken(String clientId) => _exclusive(() async {
        final data = await _load();
        var account = _account(data, clientId);
        if (account['access_token'] is! String)
          throw const ChatGptPlanException(
              'Sign in to this ChatGPT account again.');
        if (!(account['scopes'] as List? ?? []).contains(planScope)) {
          throw const ChatGptPlanException(
              'Enable ChatGPT plan usage for this connection first.');
        }
        if ((account['expires_at'] as num? ?? 0) <=
            _now().add(const Duration(seconds: 60)).millisecondsSinceEpoch) {
          try {
            final tokens = await _form(tokenUrl, {
              'grant_type': 'refresh_token',
              'client_id': clientId,
              'refresh_token': account['refresh_token'] as String,
              'resource': apiRoot
            });
            if (tokens['id_token'] != null) {
              await _verifyIdentity(tokens['id_token'], clientId,
                  subject: account['subject'] as String);
            }
            account = _tokenRecord(tokens, account);
            await _saveAccount(data, account);
          } on ChatGptPlanException catch (e) {
            if (const {
              'invalid_grant',
              'invalid_refresh_token',
              'token_expired',
              'refresh_token_expired',
              'refresh_token_invalidated',
              'refresh_token_reused'
            }.contains(e.code)) {
              await _saveAccount(data, _withoutTokens(account));
            }
            rethrow;
          }
        }
        if (!(account['scopes'] as List? ?? []).contains(planScope)) {
          throw const ChatGptPlanException(
              'ChatGPT plan usage permission is no longer enabled.');
        }
        return account['access_token'] as String;
      });

  Future<bool> signOut(String clientId) => _exclusive(() async {
        final data = await _load();
        final account = _account(data, clientId);
        var revoked = account['refresh_token'] == null;
        try {
          if (!revoked) {
            final discovery = await _dio.get<Map<String, dynamic>>(
                '$issuer/.well-known/openid-configuration',
                options: Options(followRedirects: false));
            final endpoint = Uri.tryParse(
                discovery.data?['revocation_endpoint'] as String? ?? '');
            if (discovery.data?['issuer'] != issuer ||
                endpoint?.scheme != 'https' ||
                endpoint?.host != 'auth.openai.com' ||
                endpoint?.port != 443 ||
                endpoint!.userInfo.isNotEmpty ||
                endpoint.hasQuery ||
                endpoint.hasFragment) {
              throw const ChatGptPlanException(
                  'Unexpected OpenAI revocation endpoint.');
            }
            for (var attempt = 0; attempt < 2; attempt++) {
              try {
                await _form(
                    endpoint.toString(),
                    {
                      'token': account['refresh_token'] as String,
                      'token_type_hint': 'refresh_token',
                      'client_id': clientId
                    },
                    emptyAllowed: true);
                revoked = true;
                break;
              } on ChatGptPlanException catch (e) {
                if (e.status != null && e.status! < 500) rethrow;
                if (attempt == 0)
                  await Future<void>.delayed(const Duration(milliseconds: 300));
              }
            }
          }
        } catch (_) {
          /* Still clear local secrets, but report unconfirmed revocation. */
        }
        await _saveAccount(data, _withoutTokens(account));
        return revoked;
      });

  Map<String, dynamic> _withoutTokens(Map<String, dynamic> a) =>
      Map<String, dynamic>.from(a)
        ..remove('access_token')
        ..remove('refresh_token')
        ..remove('id_token')
        ..remove('expires_at')
        ..remove('scopes');

  Future<List<ChatGptModel>> models(String clientId) async {
    final token = await accessToken(clientId);
    try {
      final response = await _dio.get<Map<String, dynamic>>('$apiRoot/models',
          options: Options(
              headers: {'Authorization': 'Bearer $token'},
              followRedirects: false));
      final entries = response.data?['models'];
      if (entries is! List)
        throw const ChatGptPlanException(
            'OpenAI returned an unexpected ChatGPT model catalog.');
      return entries
          .whereType<Map<dynamic, dynamic>>()
          .where((m) => m['visibility'] == 'list' && m['slug'] is String)
          .map((m) => ChatGptModel(m['slug'] as String,
              m['display_name'] as String? ?? m['slug'] as String))
          .toList();
    } on DioException catch (e) {
      throw safeHttpFailure(e);
    }
  }

  Future<Map<String, dynamic>> _form(String url, Map<String, String> body,
      {bool emptyAllowed = false}) async {
    try {
      final response = await _dio.post<dynamic>(url,
          data: body,
          options: Options(
              contentType: Headers.formUrlEncodedContentType,
              followRedirects: false));
      if (response.statusCode != 200)
        throw const ChatGptPlanException('Unexpected OAuth response status.');
      if (emptyAllowed && (response.data == null || response.data == ''))
        return {};
      if (response.data is! Map)
        throw const ChatGptPlanException('Unexpected OAuth response format.');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw safeHttpFailure(e);
    }
  }

  static ChatGptPlanException safeHttpFailure(DioException e) => safeFailure(
      data: e.response?.data,
      status: e.response?.statusCode,
      requestId: e.response?.headers.value('x-request-id'),
      fallback:
          e.type == DioExceptionType.cancel ? 'Request cancelled.' : null);

  /// Keep stable diagnostics only. Server free-form text can echo credentials
  /// or conversation content, so it must not enter UI errors or logs.
  static ChatGptPlanException safeFailure({
    dynamic data,
    int? status,
    String? requestId,
    String? fallback,
  }) {
    String? code;
    String? param;
    final shape = data is Map
        ? (data.containsKey('error')
            ? 'error'
            : data.containsKey('detail')
                ? 'detail'
                : 'object')
        : data == null
            ? 'empty'
            : 'non-json';
    if (data is Map) {
      final error = data['error'];
      final detail = error is Map ? error : data;
      final candidate = error is String ? error : detail['code'];
      final parameter = detail['param'];
      if (parameter is String &&
          RegExp(r'^[A-Za-z0-9_.\[\]-]{1,100}$').hasMatch(parameter)) {
        param = parameter;
      }
      if (candidate is String &&
          RegExp(r'^[a-z0-9_]{1,100}$').hasMatch(candidate)) code = candidate;
    }
    final message = switch (code) {
      'subscription_sharing_user_not_eligible' =>
        'OpenAI has not enabled ChatGPT plan usage for this account, workspace, region, or policy. Signing in again will not enable eligibility.',
      'subscription_sharing_usage_limit_exceeded' =>
        'ChatGPT plan usage limit reached. Open ChatGPT Settings → Usage.',
      'subscription_sharing_usage_unavailable' ||
      'subscription_sharing_user_unavailable' =>
        'ChatGPT plan usage is temporarily unavailable. Try again later.',
      'chatpass_v2_scope_not_authorized' ||
      'subscription_sharing_chatpass_v2_scope_not_authorized' =>
        'The selected connection does not have plan-usage permission. Choose Enable plan usage in AI Configuration.',
      'invalid_authorization_context' ||
      'subscription_sharing_invalid_authorization_context' =>
        'OpenAI rejected this connection’s authorization context. Reconnect the selected account in AI Configuration.',
      'subscription_sharing_invalid_user' =>
        'OpenAI could not use the selected subscriber. Check the account in AI Configuration and reconnect if needed.',
      'subscription_sharing_route_not_supported' ||
      'subscription_sharing_unsupported_capability' =>
        'OpenAI does not support this request on the plan-sharing route.',
      _ => fallback ??
          (status == 401
              ? 'ChatGPT authentication was not accepted. Check the account or sign in again.'
              : status == 403
                  ? 'OpenAI denied plan sharing for this request. Check permissions and regional availability.'
                  : status == 503
                      ? 'OpenAI plan sharing is temporarily unavailable or not enabled.'
                      : 'The official ChatGPT request failed. Try again or reconnect in account settings.'),
    };
    return ChatGptPlanException(message,
        code: code,
        status: status,
        param: param,
        bodyShape: shape,
        requestId: requestId != null &&
                RegExp(r'^[A-Za-z0-9_-]{1,150}$').hasMatch(requestId)
            ? requestId
            : null);
  }

  static String _random() => base64UrlEncode(
          List<int>.generate(32, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');
  static String _hostId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'urn:uuid:${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static bool _same(String a, String b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
