# NativeTavern provider validation — build 46

Date: 2026-10-09. Upstream base: `6dbd1ee042e994966db85693594ab61e4f4ec441`.
Personal version: `0.1.17+46`. Previous delivered version: `0.1.17+45`.

## Provider caching changes

All 14 app providers have an explicit support policy. Supported direct Claude,
DashScope/Qwen and OpenRouter content-block routes use stable-prefix markers.
New OpenAI API routes use their own explicit breakpoint format. Eligible implicit
caching remains managed by the serving provider. Unknown compatible servers get
no speculative fields, local servers retain their behavior, and older Gemini
cache resources are not provisioned.

Markers operate on request copies after prompt fitting and tool decoration.
Text, roles, order, images, thinking signatures and tool identities are
preserved. Existing message/system/tool markers share the four-marker budget.
The newest input and trailing assistant prefill remain outside app-added
history boundaries. Manual markers and longer Claude TTL ordering are retained.

A new persisted `automaticPromptCacheEnabled` defaults on. Existing OpenRouter
and direct Claude switches are retained; saved false values are honored.
Settings display the selected connection's supported controls or limitations.

Reported native/normalized numeric cache reads/writes reach streaming,
non-streaming and tool requests, the real composer/pipeline, SQLite and reply
alternatives. Repeated cumulative stream snapshots are merged rather than
summed; separate tool rounds are aggregated. DeepSeek misses are not labelled
writes. Build-45 reply metadata remains readable. No raw prompt or response is
added to cache metadata.

## Verified source checks

- **149 focused tests passed**, including **58 caching tests** covering outgoing
  requests, provider/model/host gating, manual marker budgets, stable and edited
  prefixes, saved opt-outs, native usage-only chunks, stream snapshot merging,
  native and compatible tool rounds, settings UI and actual chat/SQLite storage.
- Existing ChatGPT auth, public Responses transport, chat integration, tool
  execution, parameter controls and Gemini streaming regressions passed.
- The tool-loop tests use Dio's actual IO adapter against a local HTTP server.
  Other request and chat cases use mocked HTTP with synthetic credentials.
- Local full-project analysis completed with **zero errors** and 810 warning
  diagnostics. Formatting and whitespace checks passed.
- Development gates checked **61 Live2D artifacts** and recorded
  **zero device-evidence runs**.

## Verified macOS gate and downloaded build 46

[The successful workflow](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/38014008008) compiled `820c196ed0c9c100edded8411b1fd8e8e2758a97`.
The full suite passed **671 tests, with 2 skipped**. Analysis completed
with zero errors. The native development gates passed.

The workflow used standard public `macos-15`, Flutter 3.44.9 and CocoaPods
1.17.0. Native compilation and packaging ran through the original
`build_ios.sh` unsigned mode, retaining locked native source checks.

- `NativeTavern_ChatGPT_v0.1.17+46_unsigned.ipa`: 45,121,961 bytes.
- SHA-256: `41a88d671c138d7d97dfcf9b688559605a9f1c17fd8db6f05fa027938a1c5238`, matching CI, its checksum companion and GitHub's digest.
- Version 0.1.17 build 46, bundle `com.miaomiaoxworld.nativetavern`,
  minimum iOS 15.0.
- All 444 ZIP members passed streamed CRC validation.
  Runner, App.framework and Flutter.framework are arm64 iOS-device binaries.
- Compiled general caching policy/settings/usage markers are present alongside
  the earlier OpenRouter and ChatGPT configuration/transport markers.
  Native Live2D and Spine markers remain present.
- The main executable is unsigned. No provisioning profile or bundle signature
  directory is included. Framework signature metadata may remain; the complete
  app needs local re-signing.
- The draft targets the exact compiled source. Open **NativeTavern ChatGPT
  preview (build 46, unsigned)** at [the stable Releases page](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/releases)
  while signed in as the fork owner.
- Matching source identifies compiled and packaged commits separately.
  Changes after compilation are documentation only. The complete binary patch
  is applied to a fresh upstream checkout and every modified file is compared.

Earlier builds 42–45 stay separate. Their test results and artifacts do not
substitute for this update's verification.

## Preserved integration and live limits

The official ChatGPT route retains OAuth-protected public Responses,
`store: false`, `stream: true`, and confirmed `response.completed` admission.
Only confirmed final numeric usage is added; API-only caching options are not
sent. JSON errors, partial text and account denials remain failed requests.
No Codex bridge, private endpoint or paid API-key fallback is introduced.

No owner credentials, Apple signing material, paid inference, paid cache storage
or purchases were used. Live hits, billed savings, account/model admission,
completed live ChatGPT inference and re-signed device/Keychain behavior remain
unverified. Explicit cache writes can cost extra. A local app switch cannot
disable mandatory server caching.

See [provider support and controls](provider-prompt-caching.md) and
[build/sideload instructions](chatgpt-plan-sideload.md).
