# NativeTavern ChatGPT integration validation — build 43

Date: 2026-10-08. Upstream base: `6dbd1ee042e994966db85693594ab61e4f4ec441`.
Personal version: `0.1.17+43`. The previous delivered build was `0.1.17+42`.
This report distinguishes source tests, a compiled unsigned device IPA, and live account/device verification.

## Reproduced defect and changes

The previous chat screen considered every cloud connection configured only when an API key was present. The ChatGPT provider correctly keeps its OAuth credentials in protected storage and its API-key field empty. A widget regression test reproduced the resulting **API Not Configured** banner before the fix.

The chat composer and other chat actions now use the shared connection settings plus the selected protected account's connection and plan-scope state. Identity-only sign-in is not marked ready for inference. The existing Model setting is available for the plan provider; it automatically restores the selected account's catalog, displays and searches server-provided model names, and keeps the selected slug in the normal saved provider settings. An empty selection defaults to the first server-ordered available model. A saved selection survives reconnecting the same registration. Account/provider changes invalidate stale catalog and connection-test results. Older connection snapshots recover their public account/model binding without recovering or exporting OAuth tokens.

HTTP and nested SSE errors preserve safe codes, parameters, request IDs, and status when available. Free-form server text is excluded because it can echo credentials or conversation content. Eligibility, permission, usage, incomplete, and interrupted failures remain failures through the existing chat pipeline. A partial stream is not persisted as a completed assistant reply. Unsupported sampling and token-cap controls are hidden for this provider. Existing API providers, connection profiles, and saved API keys are preserved.

## Verified local checks

- **65 focused tests passed** on Mint for the final build-43 source before CI. These include the actual chat composer, real chat notifier/context pipeline, real LLM service, streamed Responses parser, SQLite persistence, restored settings, model UI, account switching, and safe errors.
- The transport and protected account records in these tests are synthetic. They do not establish live OpenAI admission. Existing auth tests separately exercise PKCE/state/nonce, RSA identity validation, consent gating, refresh rotation, cancellation, account isolation, and revocation.
- The real app pipeline was exercised with streaming display both enabled and disabled. In both cases the official Responses request has `stream: true`, `store: false`, and no separately billed API-key fallback.
- The initial API-key-banner regression failed before the patch and passes afterward.

Full-project local analysis completed with zero errors (existing warnings remain). Changed Dart formatting, patch whitespace, shell syntax, and workflow YAML passed. The Live2D development gate passed with 61 artifacts; the mobile development gate passed while reporting no device evidence. The completed macOS build passed the full suite: **585 tests passed, 2 skipped**. Its analysis, mobile checks, native compilation, unsigned packaging, and release-save steps all succeeded.

## Verified build 43 and downloaded artifact

- [Successful run 37817606854](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37817606854) compiled source `1ae5695467f76c2ffd11fb81ef8e8b584e97995d`.
- Flutter 3.44.9, CocoaPods 1.17.0, and the workflow's macOS/Xcode runner built the real arm64 device app through `build_ios.sh`.
- The IPA is `NativeTavern_ChatGPT_v0.1.17+43_unsigned.ipa`, 45,088,282 bytes, version 0.1.17 build 43, minimum iOS 15.0.
- Downloaded SHA-256: `d25cb1a66fd66881eb32274580b0b25e2168fd25917c984e8779cbceea0828ed`. It matches the checksum in the successful build log and the release checksum companion.
- Every ZIP member passed CRC validation. Runner, App.framework, and Flutter.framework are arm64 iOS-device binaries. The compiled app contains the ChatGPT provider and new integration UI markers; Live2D and Spine markers remain present.
- The main executable is unsigned, with no provisioning profile or bundle signature directories. SDK framework signature metadata may remain; the entire app still needs local re-signing.
- The release targets the exact compiled commit and remains a draft. Download while signed into the fork owner from [the stable Releases page](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/releases); open **NativeTavern ChatGPT preview (build 43, unsigned)**.
- Matching source, a complete binary patch, and English instructions accompany the IPA. Any later commit in this source packet changes documentation only; the manifest records both source and compiled commits.

These are build and artifact checks. They do not establish live OpenAI eligibility, completed inference on the owner's account, or installation under the final signing identity.

## Build route and prior evidence

The isolated public personal fork is [taizaki69/NativeTavern-ChatGPT-preview](https://github.com/taizaki69/NativeTavern-ChatGPT-preview). Its existing manual workflow uses a standard `macos-15` runner, Flutter 3.44.9, and CocoaPods 1.17.0. Final packaging uses the repository's `build_ios.sh` in unsigned mode, preserving its native source, architecture, minimum-iOS, Live2D, Spine, and ZIP checks. It saves the actual verified output and checksum in a draft release. No Apple signing material or OpenAI account is used by CI, and no paid resources are configured.

Build 42 was previously compiled and verified in [run 37800965945](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37800965945), with 566 tests passed and 2 skipped. That evidence applies to build 42; it is not substituted for this update's checks.

## Live verification limits

The maintainer has not inspected or used the owner's OpenAI credentials, cookies, account session, plan allowance, or signing material. A reported successful sign-in does not prove the selected account has `chatgpt.tokens.use.direct` or that OpenAI admits a Responses request for this mobile client.

Still to verify on the re-signed iPhone build: live catalog admission and completed inference, session refresh and Keychain persistence under the signing identity, Safari routing, cancellation, account switching, and remote revocation. Eligibility and workspace/region policy are server decisions. The [official preview requirements](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) and [error guidance](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery) remain the integration contract; no unofficial Codex bridge or internal ChatGPT endpoint is used.

The unsigned IPA needs local re-signing before installation. Export current app data first and use the same signing identity/bundle ID to retain storage where possible. Open AI Configuration, select ChatGPT plan (preview), reuse or authorize the saved account, verify the normal Model setting, and send a short message. Test connection also performs inference and consumes the authorized allowance. Report any exact safe error code/status/request ID; do not share credentials. A policy/eligibility denial cannot be fixed by repeating sign-in or changing to an API key.
