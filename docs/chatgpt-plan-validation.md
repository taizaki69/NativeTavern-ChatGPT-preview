# NativeTavern ChatGPT response transport validation — build 44

Date: 2026-10-08. Upstream base: `6dbd1ee042e994966db85693594ab61e4f4ec441`.
Personal version: `0.1.17+44`. The prior delivered build was `0.1.17+43`.
This report distinguishes reproduced client defects, source tests, compilation,
and actual device/account behavior.

## Reported failure and reproduced defects

The owner reported **OpenAI returned an unexpected response type.** with
`gpt-6-astra` selected. That exact build-43 message originates after an HTTP 200
response with a non-null streaming body when its MIME label is not exactly
`text/event-stream`. The screenshot does not establish the actual returned
MIME label or body. Neither owner credentials nor a live response were inspected.

New tests reproduced the same message for valid SSE with mixed-case, missing,
and other MIME labels. They also reproduced loss of a safe server error code
when an HTTP 200 JSON error body was rejected by the header check. Before
the patch, eight of these ten regressions failed; two normal MIME cases passed.

The plan transport now probes a bounded prefix, replays the original bytes,
and parses documented SSE framing through the existing successful terminal
event check. It does not equate HTTP 200, a MIME label, partial text, or
a JSON object with completed inference. JSON errors and direct-admission
detail objects are inspected with a 64 KiB bound. Unknown/HTML/oversized bodies
remain failures. Server text, conversation content, credentials, and MIME
parameters are excluded from errors. The actual HTTP status, safe code,
parameter, request ID, body shape, and normalized MIME label are retained.
Late SSE failures and malformed UTF-8 retain their HTTP context. The exact
documented `chatpass_v2_invalid_authorization_context` code is also recognized.

No endpoint, bearer-token source, model-selection policy, or billing path
was substituted. Requests remain public `POST /v1/responses`, with the
selected account's OAuth access token, `store: false`, `stream: true`,
and no redirects or automatic API-key fallback. Existing providers and
build-43 provider/model configuration fixes remain intact.

## Verified source checks

- **26 transport tests passed**, covering normal/mixed-case/missing MIME labels,
  mislabeled SSE, fragmented UTF-8/BOM/keepalives, HTTP 200 JSON errors/detail,
  HTTP 401/403/429/503 errors, bounded diagnostics, unknown HTML cancellation,
  invalid UTF-8, and late SSE failure.
- Three of those tests use Dio's actual IO adapter and a local HTTP server.
  Only synthetic credentials and test messages reach that loopback server.
  No request is made to a live owner account.
- **78 focused tests passed** across transport, protected auth, actual chat
  composer/pipeline and SQLite persistence, saved configuration, and chat
  lifecycle. A valid SSE body with an incorrect JSON MIME label is saved as
  a completed reply only after its terminal event. An HTTP 200 JSON eligibility
  error reaches the actual chat banner, retains safe diagnostics, and creates
  no completed assistant reply or automatic retry.
- Full-project analysis completed with **zero errors**; existing warnings remain.
  Changed Dart formatting, patch whitespace and shell checks passed.
  Development gates, full macOS tests, compilation and artifact checks
  also passed, as recorded below.

## Verified build 44 and downloaded artifact

The full macOS gate and new unsigned iPhone build succeeded.
[Run 37823359670](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37823359670) compiled `7411415ef0bc8b6ca2bb413f7d849d22a9e6e5a8`.
The full suite passed **613 tests, with 2 skipped**, and analysis
completed with zero errors. The development gate checked
61 Live2D artifacts and recorded no device evidence.

The workflow used its standard `macos-15` runner, Flutter 3.44.9 and
CocoaPods 1.17.0. Final compilation and packaging ran through the checked-in
`build_ios.sh` unsigned mode, preserving native project checks and Live2D/Spine.
No OpenAI account, Apple signing material, or paid resource was used by CI.

Downloaded artifact:

- Filename: `NativeTavern_ChatGPT_v0.1.17+44_unsigned.ipa`.
- Size: 45,100,794 bytes.
- SHA-256: `acde21dc00c8bbd6b74a2cc2e306effc5906a76072cde4cc117291d6b0262004`, matching the successful CI log,
  release checksum companion, and GitHub asset digest.
- Version 0.1.17 build 44; bundle `com.miaomiaoxworld.nativetavern`;
  minimum iOS 15.0.
- All 444 ZIP entries passed streamed CRC validation.
  Runner, App.framework, and Flutter.framework are arm64 iOS-device binaries.
- The compiled Dart app contains the prior ChatGPT/provider integration and
  the new response-transport diagnostic markers. Native Live2D/Spine markers
  remain present.
- The main executable is unsigned. There is no provisioning profile or bundle
  signature directory; SDK framework signature metadata can remain. The entire
  app requires local re-signing.
- The draft release targets the exact compiled commit. While signed into
  the fork owner, open **NativeTavern ChatGPT preview (build 44, unsigned)** from
  [the stable Releases page](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/releases).
- Matching source and the complete binary patch are supplied. The packet
  identifies compiled and packaged source commits separately. Any difference
  after the compiled source is documentation only.

The previous build-43 release remains available separately. Its 585 passed,
2 skipped result does not replace this update's full suite or artifact checks.
These checks establish source behavior with synthetic responses, a compiled
unsigned device app, and matching downloadable assets. They do not establish
the actual server response or completed inference on the owner's account.

## Live verification and remaining limits

The screenshot identifies an application error path, not the exact server
admission reason. A passing local transport test, successful compilation, or
successful OAuth alone does not prove live Responses eligibility. The fix
removes demonstrated client rejection and diagnostic-loss defects. If the
actual response is an OpenAI policy, permission, region, model, or usage-limit
denial, it remains an error and must be resolved according to that restriction.

Still to verify on the locally re-signed phone: account-specific catalog,
actual returned response diagnostics, completed inference, session refresh and
Keychain persistence under the final signing identity, cancellation and
revocation. Reuse the connected authorized account if it is retained and
check the existing Model setting. Report exact safe code/status/request ID,
shape and content-type labels when shown; do not share tokens, cookies,
raw HTTP bodies, authorization headers, or signing credentials.

Official sources checked on 2026-10-08:
[Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference),
[Errors and recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery).
The public route requires streaming and successful completion, and preserves
direct-admission restrictions. This update does not use internal ChatGPT
endpoints or an unofficial Codex bridge.

The output is an unsigned arm64 iPhone app for iOS 15 or later, requiring full
local re-signing. Export existing data before installation; preserve the
bundle ID/signing identity when possible to retain protected storage.
