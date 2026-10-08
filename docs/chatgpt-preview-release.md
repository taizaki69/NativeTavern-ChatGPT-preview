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

The full macOS test gate and native packaging will finish before this draft's
IPA is saved. The validation report and matching source packet will record
the actual successful run and downloaded artifact results.

The IPA is unsigned, for arm64 iPhone devices with iOS 15 or later. Export
existing app data and re-sign the complete app with your existing sideload tool.
Reuse your authorized saved ChatGPT account if retained, check Model, and send
a short message. A server/account restriction remains a failure with safe
diagnostics rather than a reason to change billing or paste credentials.
