# NativeTavern provider validation — build 45

Date: 2026-10-09. Upstream base: `6dbd1ee042e994966db85693594ab61e4f4ec441`.
Personal version: `0.1.17+45`. Previous delivered version: `0.1.17+44`.

## OpenRouter caching change

The active OpenRouter Chat Completions connector previously omitted Claude
cache_control blocks. This update adds request-only explicit markers to reusable
instruction and history prefixes for recognized Claude Sonnet/Opus/Haiku 4/5
model IDs. Markers use the default five-minute TTL, fit the four-marker limit,
preserve existing manual message markers, and do not rewrite or reorder content.
Context fitting and role processing occur first. Newest input and trailing
assistant prefill remain outside the growing-history boundary.

A separate persisted `openRouterPromptCacheEnabled` defaults true for existing
configurations; disabling it removes app-added markers on subsequent requests.
The direct Anthropic setting and non-supported provider/model paths are retained.
No provider order, fallback behavior or deprecated usage parameter is added.

Only recognized numeric cached_tokens/cache_write_tokens from OpenRouter's
prompt_tokens_details are retained. Streaming terminal usage, non-streaming
responses and tool-round totals reach the chat pipeline, SQLite metadata and
selected reply alternative. Deleted alternatives remap these counters.
Raw response data and prompts are not copied into this new cache metadata.
Existing citation metadata remains separate. The normal and visual novel chat
views display reported counts, not estimated cost savings.

## Verified source checks

- **27 caching tests passed**: request payloads, legacy settings, model/provider
  gating, stable and edited prefixes, four-marker limits, manual TTL ordering,
  images/thinking preservation, reported zero/absent counters, tool rounds,
  reply alternatives/deletion, SQLite persistence and the actual chat composer.
- **129 focused tests passed** on the final source, including the existing
  ChatGPT auth/transport/chat, generation pipeline, tool behavior, saved settings,
  parameter controls and Gemini streaming regressions.
- The OpenRouter tool-loop test uses Dio's real IO adapter with a loopback HTTP
  server. Other caching and chat cases use mocked HTTP. All credentials and
  prompts in these tests are synthetic; no paid inference request is made.
- Full-project analysis completed with **zero errors**. The existing 811 warning
  diagnostics remain; no new cache-file warning was added.
- Changed Dart formatting and patch whitespace checks passed. The Live2D
  development gate checked **61 artifacts**. The mobile development gate passed
  with **zero device-evidence runs**.

## Verified macOS gate and downloaded build 45

[The successful workflow](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37894204117) compiled `6fab43d0cda0b55c5ef61dbdc5237f6962474693`.
The full suite passed **640 tests, with 2 skipped**. Analysis completed
with zero errors. The development gate checked 61
Live2D artifacts and recorded no device-evidence runs.

The workflow used the standard public `macos-15` runner, Flutter 3.44.9 and
CocoaPods 1.17.0. Final compilation and packaging ran through the existing
`build_ios.sh` unsigned mode. Locked native project checks and Live2D/Spine
were retained. No Apple, OpenAI or OpenRouter owner login was used by CI.

Downloaded artifact:

- `NativeTavern_ChatGPT_v0.1.17+45_unsigned.ipa`, 45,111,769 bytes.
- SHA-256: `9ae9f1f934280b216ad484016fd0634e23abe9db68b992005b790094cc10e6ff`; matches the actual CI log, checksum companion
  and GitHub asset digest.
- Version 0.1.17 build 45; bundle `com.miaomiaoxworld.nativetavern`;
  minimum iOS 15.0.
- All 444 ZIP entries passed streamed CRC validation.
  Runner, App.framework and Flutter.framework are arm64 iOS-device binaries.
- Compiled Dart markers for the OpenRouter cache setting, saved usage and reply
  counters are present, together with the prior ChatGPT provider/configuration/
  response transport markers. Native Live2D/Spine markers remain present.
- The main executable is unsigned. No provisioning profile or bundle signature
  directory is included. SDK framework signature metadata can remain; the
  complete app requires local re-signing.
- The new draft targets the exact compiled commit. While signed in as the fork
  owner, open **NativeTavern ChatGPT preview (build 45, unsigned)** from
  [the stable Releases page](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/releases).
- The source packet identifies compiled and packaged commits separately.
  Later changes are documentation only. The complete patch is checked against
  the exact upstream base and every modified file is byte-compared.

Earlier builds 42, 43 and 44 remain separate. Their test results and downloaded
files do not substitute for this update's source, CI or artifact verification.

## Preserved integration and live limits

The build-44 official ChatGPT provider, public Responses transport and secure
account/model configuration are preserved. That transport requires its successful
terminal event; JSON errors, partial text and account denials remain errors.
No Codex bridge, internal endpoint or automatic paid API-key fallback is added.

Tests use synthetic credentials and local/mock HTTP. They do not demonstrate
real OpenRouter cache hits, billed savings, a completed live ChatGPT reply,
account/mobile eligibility or re-signed iPhone Keychain behavior. No owner
credentials, Apple signing material, paid inference or purchased resources are
used by these tests or the unsigned build workflow.

See [OpenRouter setup and limitations](openrouter-prompt-caching.md) and
[the build/sideload guide](chatgpt-plan-sideload.md).
