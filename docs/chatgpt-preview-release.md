NativeTavern ChatGPT preview, version 0.1.17 build 45.

This update adds automatic prompt caching for supported OpenRouter Claude
models, including Sonnet 5.5. The existing provider, model, prompt content and
routing are preserved. Caching defaults on; use **Automatic OpenRouter caching**
in AI settings to opt out. Replies show reported cache reads and writes for the
selected alternative, including totals from tool generation rounds.

[English caching instructions](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/blob/main/docs/openrouter-prompt-caching.md).
Default retention is five minutes. Writes cost extra; reuse depends on model
minimums, exact content, retention and provider routing. Live cache hits and
billed savings are unverified. No live paid inference or owner API credentials
were used to test this change.

**640 full Flutter tests passed, 2 skipped**, with zero analysis errors.
The final source also passed 129 focused tests, including 27 caching tests.
The native development gates passed, and the downloaded IPA passed checksum,
all-member ZIP CRC, version, arm64 iOS-device, caching/ChatGPT compiled markers
and Live2D/Spine checks.

[Successful build](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37894204117).
[Compiled source](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/tree/6fab43d0cda0b55c5ef61dbdc5237f6962474693).
IPA: `NativeTavern_ChatGPT_v0.1.17+45_unsigned.ipa` (45,111,769 bytes).
SHA-256: `9ae9f1f934280b216ad484016fd0634e23abe9db68b992005b790094cc10e6ff`.

Matching source, complete patch, checksums, English guides and verification
reports accompany the build. Earlier preview drafts remain unchanged.

The official ChatGPT provider and build-44 transport are retained. Completed
live Responses inference and account/mobile eligibility remain unverified.
No Codex bridge or paid API-key fallback was added.

This is an unsigned device app for iOS 15 or later. Export your existing data,
then re-sign the complete app with your existing sideload tool. Keep your
OpenRouter connection and Sonnet 5.5 model; no ChatGPT login is needed for that
provider. Reported counters appear under completed replies when supplied.
