NativeTavern ChatGPT preview, version 0.1.17 build 44.

This update fixes response decoding behind “OpenAI returned an unexpected
response type.” Valid Responses event streams are identified from their framing
even when the MIME label is mixed-case, missing, or incorrect. JSON admission
errors retain safe code/status/request ID, body shape, and normalized content
type. Raw server bodies and MIME parameters are excluded.

A successful reply still requires response.completed. JSON objects, partial
text, interrupted streams, and policy/usage denials are not reported as completed
inference. The selected model, protected account, existing provider settings,
public Responses endpoint, and plan-consent flow remain in use. There is no
Codex bridge or paid API-key fallback.

26 transport regressions and 78 focused tests passed locally, including three
real Dio IO-adapter loopback cases and the actual chat composer with SQLite
persistence and safe denial display. These use synthetic account records and
local/mocked endpoints. They do not establish live eligibility or success on
the owner's phone.

Verified build: **613 Flutter tests passed, 2 skipped**, with zero
analysis errors. Development gates passed, including
61 Live2D artifacts. The actual downloaded IPA passed
checksum, all-member ZIP CRC, arm64 iOS-device, version 44, new transport-code
AOT markers, and native Live2D/Spine checks.

[Successful build](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37823359670).
[Compiled source](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/tree/7411415ef0bc8b6ca2bb413f7d849d22a9e6e5a8).
IPA: `NativeTavern_ChatGPT_v0.1.17+44_unsigned.ipa` (45,100,794 bytes).
SHA-256: `acde21dc00c8bbd6b74a2cc2e306effc5906a76072cde4cc117291d6b0262004`.

The matching source archive, patch, checksum and English guides accompany
this build. These checks do not show what body the owner's original request
received and do not prove completed live inference. A server/account denial
remains an error with safe diagnostics.

The IPA is unsigned, for arm64 iPhone devices with iOS 15 or later. Export
existing app data and re-sign the complete app with your existing sideload tool.
Reuse your authorized saved ChatGPT account if retained, check Model, and send
a short message. A server/account restriction remains a failure with safe
diagnostics rather than a reason to change billing or paste credentials.
