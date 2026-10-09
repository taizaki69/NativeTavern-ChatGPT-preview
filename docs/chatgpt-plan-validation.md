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

## Verified source checks; native build pending

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

The full macOS test gate, native compilation and downloaded build-45 IPA remain
pending. The completed results and artifact proof will be recorded here after
those checks pass. The previous IPA does not contain this caching update.

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
