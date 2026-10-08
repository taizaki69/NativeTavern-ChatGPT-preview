NativeTavern ChatGPT preview, version 0.1.17 build 43.

This update fixes the chat composer's API-key-only configuration gate. The official ChatGPT plan connection now uses the normal provider and Model settings, automatically restores the account catalog, and keeps the selected model across reconnects. Account switching discards stale model and connection-test results. Existing API providers and their saved settings remain available.

Sign-in, plan-usage authorization, model selection, and a completed inference request are separate checks. Identity-only sign-in offers Enable plan usage. Catalog, policy, usage-limit, and streaming failures show safe diagnostics and are not treated as completed replies. Unsupported generation controls are hidden for this provider.

Select ChatGPT plan (preview) in AI Configuration. An authorized saved account is reused, and the normal Model setting loads its available models. Test connection makes one short Responses request; ordinary chats use the same official route. There is no Codex bridge or paid API-key fallback.

This is an unsigned arm64 iPhone IPA for iOS 15 or later. Re-sign the complete app with your existing trusted sideload tool. CI uses no OpenAI account or Apple signing material. Live account eligibility, model requests, and final re-signed device behavior remain unverified by the build; successful OAuth alone does not establish inference eligibility.

Verified build: 585 Flutter tests passed, 2 skipped; zero analysis errors.
The mobile development gates passed, including 61 Live2D artifacts.
The actual downloaded IPA passed checksum, all-member ZIP CRC, iOS-device arm64,
version 43, compiled ChatGPT integration, and native Live2D/Spine checks.

Build: https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37817606854
Compiled source: https://github.com/taizaki69/NativeTavern-ChatGPT-preview/tree/1ae5695467f76c2ffd11fb81ef8e8b584e97995d
IPA: NativeTavern_ChatGPT_v0.1.17+43_unsigned.ipa
Size: 45,088,282 bytes.
SHA-256: `d25cb1a66fd66881eb32274580b0b25e2168fd25917c984e8779cbceea0828ed`

Download the IPA and checksum, export your existing app data, and re-sign with
your existing sideload tool. Reuse the authorized account if retained, check
the normal Model setting, and send a short message. Catalog and generation
admission still require a real device/account check. Exact safe error codes,
status, and request IDs are useful for a follow-up; do not share credentials.

The attached source packet, checksum, English guides, and reports match this
build. See chatgpt-plan-sideload.md and chatgpt-plan-validation.md for details.
