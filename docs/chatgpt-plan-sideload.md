# NativeTavern: ChatGPT plan-sharing preview

Prepared 2026-10-08. Upstream base: `miaoxworld/NativeTavern` commit
`6dbd1ee042e994966db85693594ab61e4f4ec441`, version `0.1.17+41`.
This personal source modification uses version `0.1.17+43`.
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

## Download build 43

The integration fix is being checked and packaged as **build 43**. It must not
be confused with the previous build 42. When the build succeeds, its unsigned
IPA and checksum will be in the personal fork's draft release:
[NativeTavern ChatGPT previews](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/releases).
Sign in as the fork owner and open **NativeTavern ChatGPT preview (build 43, unsigned)**.
The build and downloaded artifact results will be recorded in the validation report.

Re-sign the complete app and its frameworks with your existing sideload tool.
The app targets **iOS 15 or later**. Export existing data before installation;
your signing tool's bundle-ID/team handling determines whether it replaces the
existing app or creates separate storage. Using the same signing identity and
bundle ID is the best way to retain your existing protected account records.
The source bundle identifies the exact compiled commit separately from later
documentation-only changes.

## Use it after sideloading

1. Keep an export of the data you want to preserve from the existing app.
   Re-signing with another bundle ID/team may create a separate app and
   separate storage. Do not uninstall your existing app to make room.
2. Open NativeTavern's AI connection settings and select
   **ChatGPT plan (preview)**.
3. Tap **Continue with ChatGPT**. Sign in and authorize the app in the
   OS-controlled Safari browser view. Keep the app foregrounded.
4. If your saved account is already authorized, it can be reused without
   repeating sign-in. Otherwise grant permission to use your ChatGPT plan. If only identity permission is
   granted, the app retains the sign-in and offers **Enable plan usage**;
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

The catalog is not hard-coded. Reopening AI Configuration automatically reloads
it for an authorized account. Account switching discards stale catalog and
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
release/NativeTavern_ChatGPT_v0.1.17+43_unsigned.ipa
release/NativeTavern_ChatGPT_v0.1.17+43_unsigned.ipa.sha256
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
