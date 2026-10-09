# NativeTavern: ChatGPT plan-sharing preview

Prepared 2026-10-09. Upstream base: `miaoxworld/NativeTavern` commit
`6dbd1ee042e994966db85693594ab61e4f4ec441`, version `0.1.17+41`.
This personal source modification uses version `0.1.17+45`.
It is not an upstream, OpenAI, App Store, or TestFlight release.

## What this adds

A separate **ChatGPT plan (preview)** provider in AI settings, with
**Continue with ChatGPT**, saved account registrations, explicit plan consent,
account-specific model selection, refresh, sign-out, and streaming chat.

NativeTavern is a standalone Flutter mobile application. This integration
runs on the phone; it does not require a SillyTavern server, Codex, a Codex
bridge, browser cookies, or an OpenAI API key. Existing API providers remain
separate and use their existing billing paths. The new provider never falls
back to a paid API key.

The implementation follows OpenAI's documented open-source direct plan-sharing
preview. The current documentation permits open-source and personal local
clients, but does not establish that this particular iOS build or your account
will be admitted. Plus/Pro plan availability, account/workspace policy, region,
and preview rollout remain server decisions. Source tests or a successful
compilation cannot establish live eligibility.

Sources:

- [Official OSS overview](https://developers.openai.com/siwc/token-sharing-open-source)
- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Preview limits](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [Errors and recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery)

## OpenRouter caching in build 45

Build 45 adds automatic prompt-cache markers for supported OpenRouter Claude
models, including `anthropic/claude-sonnet-5.5`. It keeps your existing provider,
model, API connection and billing configuration. The separate **Automatic
OpenRouter caching** switch defaults on and provides a persisted opt-out.
Completed replies show reported cache reads and writes when available.
See [the caching guide](openrouter-prompt-caching.md) for setup and limitations.
Live cache hits and savings are not established by synthetic tests.

## Download build 45

**Build 45 has been compiled and its downloaded unsigned IPA verified.**
Sign in as the fork owner at [the stable Releases page](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/releases)
and open **NativeTavern ChatGPT preview (build 45, unsigned)**.
Download `NativeTavern_ChatGPT_v0.1.17+45_unsigned.ipa` and its `.sha256` companion.
Earlier build 44 does not contain automatic OpenRouter prompt-cache markers.

The IPA is 45,111,769 bytes (43.0 MiB), above this
chat's 9 MiB file limit. SHA-256:

~~~
9ae9f1f934280b216ad484016fd0634e23abe9db68b992005b790094cc10e6ff
~~~

[The successful macOS build](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37894204117) passed **640 Flutter tests,
with 2 skipped**, and analysis completed with zero errors.
[Exact compiled source](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/tree/6fab43d0cda0b55c5ef61dbdc5237f6962474693): `6fab43d0cda0b55c5ef61dbdc5237f6962474693`.
The source packet identifies any documentation-only changes after compilation.

Re-sign the complete app and its frameworks with your existing sideload tool.
The app targets **iOS 15 or later**. Export existing data before installation.
Your signing tool's bundle-ID/team handling determines whether it updates the
existing app or creates separate storage. Keeping the same signing identity
and bundle ID helps retain protected accounts and saved configuration.

For Sonnet 5.5, keep your existing OpenRouter provider and model, and follow
[the caching guide](openrouter-prompt-caching.md). The instructions below concern
the separate ChatGPT provider; using OpenRouter does not require its sign-in.

## Use it after sideloading

1. Keep an export of the data you want to preserve from the existing app.
   Re-signing with another bundle ID/team may create a separate app and
   separate storage. Do not uninstall your existing app to make room.
2. Open NativeTavern's AI connection settings and select
   **ChatGPT plan (preview)**.
3. Reuse your saved authorized account if it is still connected. Otherwise
   tap **Continue with ChatGPT**, sign in and authorize the app in the
   OS-controlled Safari browser view, keeping the app foregrounded.
4. Grant permission to use your ChatGPT plan if that grant is missing.
   Identity-only sign-in is retained and offers **Enable plan usage**;
   it cannot generate until that grant is present.
5. The existing **Model** setting now loads the selected account's catalog
   automatically. A saved model is retained; an empty selection defaults to the
   first model in OpenAI's returned order. Tap **Model** to search display names
   or change the selection. The refresh button in the model list reloads it.
6. Send a short message. A successful reply requires the stream's
   `response.completed` event. **Test connection** also performs one short
   inference request, so it consumes the authorized plan/credit allowance.
7. Use **Manage usage** to review the app at
   [ChatGPT Settings → Usage](https://chatgpt.com/settings/usage).
   If you want to use only included plan allowance, keep credit usage disabled
   in that app's limits. The app does not buy credits or modify billing settings.

The catalog is not hard-coded. Opening AI Configuration automatically loads
a missing catalog for an authorized account, including after an app restart.
The model list's refresh button explicitly reloads a cached catalog. Account switching discards stale catalog and
connection-test results, clears the model binding, and loads the new account's
models. Reconnecting the same registration preserves the existing selection.
Existing connection profiles and API provider settings remain available.

If the catalog is empty or denied, the Model setting shows the safe error and
**Retry models**. Identity-only sign-in offers **Enable plan usage**. The chat
composer uses the protected account and model settings, so this provider no
longer needs an API key to send messages. A denied or interrupted Responses
request remains a chat error; partial text is not saved as a completed reply.
Errors include safe codes, HTTP status, and request IDs when supplied. An
eligibility or regional denial must be resolved with OpenAI, not repeated
sign-in or a token pasted into another provider.

The client detects documented SSE framing from the response bytes instead
of rejecting a valid stream solely because of a mixed-case, missing, or
incorrect MIME label. It preserves fragmented UTF-8 and still requires
`response.completed`. JSON objects are inspected as bounded diagnostics;
an ordinary JSON response is not substituted for a completed event stream.
Errors retain the actual HTTP status, safe code/parameter/request ID, body
shape, and normalized content-type label. Raw server text and MIME parameters
are excluded. A server/account denial is still a failed request.

This provider always uses streaming HTTP, even when an existing preset has
non-streaming display selected. Temperature, top-p, output token limits,
service-tier overrides, server-stored conversations, and native tool/MCP
calling are not sent by this integration. Text, image prompts, and reasoning
summary deltas are supported. Existing context-building features determine
the required transcript; the plan transport itself does not merge or trim it.

## Build from the patch

The patch must be applied to the exact upstream commit above. From a development
machine with Git:

~~~sh
git clone https://github.com/miaoxworld/NativeTavern.git NativeTavern-chatgpt
cd NativeTavern-chatgpt
git checkout --detach 6dbd1ee042e994966db85693594ab61e4f4ec441
git apply --index --check /path/to/NativeTavern-chatgpt.patch
git apply --index /path/to/NativeTavern-chatgpt.patch
~~~

`--index` stages the restored iOS support files as well as the code changes.
This is required because the build script checks that native project files are
tracked; it does not commit or push anything.

The source archive also contains the complete modified files for inspection.
Keep the original license and third-party notices. The patch does not include
tokens, account data, certificates, provisioning profiles, or a compiled IPA.

### macOS build

iOS compilation requires macOS and Xcode. Linux Mint can run source checks and
tests, but cannot compile this iOS application. Use Flutter **3.44.9** (the
repository's minimum), installed Xcode with its iOS SDK, and CocoaPods **1.17.0**.
The native lockfile was generated with that CocoaPods version; the workflow
checks it before building so a runner update cannot silently rewrite the lockfile.
See [Flutter's iOS setup](https://docs.flutter.dev/platform-integration/ios/setup).

From the patched repository:

~~~sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
bash tool/run_mobile_release_checks.sh
UNSIGNED_SIDELOAD=true bash build_ios.sh
~~~

The repository's iOS build script has an explicit unsigned mode. It checks
the tracked native source, versions, iOS 15 minimum, arm64 device architecture,
Live2D/Spine linkage, and final IPA contents. It packages only after those checks.
The standard signed release and device-install modes remain available.
The patch also restores standard iOS workspace, shared-scheme, bridge,
configuration, storyboard, and asset files missing from the upstream checkout.
They are based on the pinned Flutter template and the repository's existing
`icon.png`; the native AppDelegate and project are preserved. Do not recreate
the entire iOS project with `flutter create` over this checkout.

Expected output **only if the build actually succeeds**:

~~~
release/NativeTavern_ChatGPT_v0.1.17+45_unsigned.ipa
release/NativeTavern_ChatGPT_v0.1.17+45_unsigned.ipa.sha256
~~~

An unsigned IPA contains a real device application, but must be locally
re-signed before installation. Use your existing sideload tool and its own
signing process. Keep Apple credentials on your own trusted device/computer;
the build workflow does not need them. Free signing may require periodic
refreshing, depending on your tool/account. Do not upload a signing certificate
or OpenAI credential into the workflow to bypass a build error.

### GitHub Actions build

The patch includes `.github/workflows/ios-chatgpt-unsigned.yml`.
Use a **public personal fork** with Actions enabled. The workflow intentionally
refuses private repositories and the upstream repository. It is manual:
**Actions → iOS ChatGPT preview (unsigned) → Run workflow** on the branch
containing the patch.

It checks out without persisting credentials, installs pinned Flutter,
analyzes, runs the full mobile test gate, and delegates to the checked-in
`build_ios.sh` unsigned mode. It uses a standard `macos-15` runner.
No Apple signing secrets or OpenAI account are used by CI.

After successful build verification, it saves the IPA and checksum in a
**draft release** targeting that exact commit. Repository write permission is
limited to that job so the ephemeral GitHub token can create the draft.
It does not publish an upstream release or send an announcement. Download
the draft's assets from the fork's Releases page while signed into its owner
account. Verify the checksum, then re-sign locally with your sideload tool.

Standard hosted runners in public repositories are free. Release assets avoid
the pooled Actions artifact-storage allowance; no paid runners, caches,
subscriptions, or signing services are configured here.
[GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
[release asset quotas](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases#storage-and-bandwidth-quotas).

If GitHub is not authenticated or repository permissions prohibit running
Actions, no workflow dispatch or IPA is implied. A prepared workflow is source
code, not evidence of a completed build. See the separate validation report
for the actual run status.

## Auth and credential handling

- The app binds only `127.0.0.1` on a temporary available port at
  `/auth/callback`, before opening the browser. It closes the listener after
  success, failure, cancellation, or timeout.
- Initial registration uses `dynamic_agent_client`, a stable per-installation
  host UUID, and the real app name. Returning login uses the issued
  `oaiapp_...` client ID, bound identity, host ID, and appropriate login hints.
- Every attempt uses fresh state, nonce, and PKCE S256. Callbacks with another
  state, duplicate parameters, a substituted issued client, or an unexpected
  origin are rejected.
- ID-token signatures are checked against OpenAI's trusted JWKS using RS256.
  Issuer, audience, expiry, nonce, and returning subject must validate before
  credentials replace a saved session.
- OAuth access/refresh/ID tokens and host/account records are held in protected
  storage, using iOS Keychain with `unlocked_this_device` accessibility.
  General configuration and exports keep only the public registration ID.
  Credential records are replaced together; refreshes are serialized.
- Sign-out cancels generation, attempts renewable-session revocation through
  OpenAI's discovery endpoint, then clears local tokens. An unconfirmed
  remote revocation is reported; disconnect the app in ChatGPT Settings.
- Auth/model requests and inference disable redirects. OAuth credentials are
  sent only to the documented OpenAI auth/API origins. The inference endpoint
  is fixed to public `POST https://api.openai.com/v1/responses`, with
  `store: false` and `stream: true`.
- Temporary failures retain credentials. Terminal refresh errors clear tokens
  while retaining the registration. Partial text, interrupted streams, and
  explicit failures are not reported as successful completed replies.

The browser launcher is the platform's Safari browser view, not an
app-controlled WebView. This keeps the temporary listener in the same
foreground application. The HTTP loopback routing, Safari behavior, Keychain
access under the final re-signing identity, and eligibility **must still be
verified on an iPhone**. The source tests use injected browser callbacks and
mock OpenAI endpoints, not a live account.

## Useful recovery

- **Sign-in cancelled/declined:** retry explicitly; no inference is attempted.
- **Code expired (`invalid_grant`):** select the retained disconnected
  registration in the account picker and reconnect with fresh authorization.
- **Signed in, plan disabled:** choose **Enable plan usage** and approve that
  permission in the official browser.
- **401:** check the selected registration and grant. Reconnect after a
  confirmed terminal refresh error/disconnection.
- **403 / user not eligible:** this account/workspace/region/integration is not
  admitted. Do not loop login or substitute ChatGPT internal endpoints.
- **429 / plan limit:** pause generation and check the app's limits in
  ChatGPT Settings → Usage. The error does not establish a reset time.
- **503:** preserve the session and retry later.
- **Interrupted/failed stream:** the text shown so far is partial; retry
  explicitly after resolving the error.

## License

The upstream application includes its GPL-3.0 license; its Rust manifest also
declares AGPL-3.0, and bundled/native dependencies carry their own notices.
This patch preserves those notices and does not change licensing. Distribute
matching source with any compiled personal fork you share. No claim of
third-party commercial licensing or App Store approval is made.
