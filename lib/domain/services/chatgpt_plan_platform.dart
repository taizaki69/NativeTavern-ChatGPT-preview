import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chatgpt_plan_client.dart';

class _KeychainChatGptStore implements ChatGptCredentialStore {
  static const _storage = FlutterSecureStorage(
    iOptions:
        IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'native_tavern.chatgpt_plan.v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// Uses the OS-controlled Safari browser view, never an app-controlled WebView.
/// Keeping Safari's browser view in this app avoids suspending the iOS listener.
/// Browser and timeout injection allow loopback tests without signing in live.
class ChatGptPlanPlatform {
  ChatGptPlanPlatform({
    ChatGptPlanClient? client,
    Future<void> Function(Uri)? openBrowser,
    Future<void> Function()? closeBrowser,
    this.timeout = const Duration(minutes: 5),
  })  : client = client ?? ChatGptPlanClient(store: _KeychainChatGptStore()),
        _openBrowser = openBrowser ?? _launchSystemBrowser,
        _closeBrowser = closeBrowser ?? _closeSystemBrowser;
  static final instance = ChatGptPlanPlatform();
  final ChatGptPlanClient client;
  final Future<void> Function(Uri) _openBrowser;
  final Future<void> Function() _closeBrowser;
  final Duration timeout;
  bool _signingIn = false;
  Completer<Uri>? _pending;

  static Future<void> _launchSystemBrowser(Uri url) async {
    if (!await supportsLaunchMode(LaunchMode.inAppBrowserView)) {
      throw const ChatGptPlanException(
          'This device cannot open the required secure system browser view.');
    }
    if (!await launchUrl(url, mode: LaunchMode.inAppBrowserView)) {
      throw const ChatGptPlanException('Could not open ChatGPT sign-in.');
    }
  }

  static Future<void> _closeSystemBrowser() async {
    if (Platform.isIOS) await closeInAppWebView();
  }

  Future<ChatGptAccount> signIn(
      {String? clientId, bool enableSharing = false}) async {
    if (_signingIn) {
      throw const ChatGptPlanException(
          'A ChatGPT sign-in is already in progress.');
    }
    _signingIn = true;
    final pending = Completer<Uri>();
    _pending = pending;
    // Handle cancellation during bind/load/browser launch, before awaiting callback.
    unawaited(pending.future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    HttpServer? server;
    StreamSubscription<HttpRequest>? subscription;
    try {
      server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
      final redirect =
          Uri.parse('http://127.0.0.1:${server.port}/auth/callback');
      return await client.signIn(
        redirectUri: redirect,
        clientId: clientId,
        enableSharing: enableSharing,
        authorize: (url, state) async {
          if (pending.isCompleted) return await pending.future;
          subscription = server!.listen((request) async {
            final matches = request.method == 'GET' &&
                request.uri.path == '/auth/callback' &&
                request.requestedUri.host == '127.0.0.1' &&
                request.connectionInfo?.remoteAddress.isLoopback == true &&
                request.uri.queryParametersAll.values
                    .every((v) => v.length == 1) &&
                request.uri.queryParameters['state'] == state;
            try {
              request.response.headers
                  .set(HttpHeaders.cacheControlHeader, 'no-store');
              request.response.headers.set('Content-Security-Policy',
                  "default-src 'none'; frame-ancestors 'none'");
              request.response.headers.set('Referrer-Policy', 'no-referrer');
              request.response.headers.contentType = ContentType.html;
              request.response.statusCode =
                  matches ? HttpStatus.ok : HttpStatus.badRequest;
              request.response.write(matches
                  ? '<!doctype html><title>NativeTavern</title><p>Return to NativeTavern to finish connecting. You can close this browser view.</p>'
                  : '<!doctype html><title>NativeTavern</title><p>This callback was not accepted.</p>');
              await request.response.close();
              if (matches && !pending.isCompleted) {
                pending.complete(redirect.replace(query: request.uri.query));
              }
            } catch (_) {
              if (!pending.isCompleted) {
                pending.completeError(const ChatGptPlanException(
                    'The local sign-in callback failed.'));
              }
            }
          }, onError: (Object _) {
            if (!pending.isCompleted) {
              pending.completeError(const ChatGptPlanException(
                  'The local sign-in callback failed.'));
            }
          });
          try {
            await _openBrowser(url);
            return await pending.future.timeout(timeout,
                onTimeout: () => throw const ChatGptPlanException(
                    'ChatGPT sign-in timed out. Please try again.'));
          } finally {
            // A browser-dismiss failure must not replace the validated auth result.
            try {
              await _closeBrowser();
            } catch (_) {}
          }
        },
      );
    } finally {
      _pending = null;
      try {
        await subscription?.cancel();
        await server?.close(force: true);
      } finally {
        _signingIn = false;
      }
    }
  }

  void cancelSignIn() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
          const ChatGptPlanException('ChatGPT sign-in cancelled.'));
    }
  }
}
