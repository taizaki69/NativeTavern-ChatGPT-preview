# Validation of the NativeTavern ChatGPT preview

Date: 2026-10-08. Upstream base: `6dbd1ee042e994966db85693594ab61e4f4ec441`.
Personal version: `0.1.17+42`. This is a source and unsigned-device-build
preview; successful source checks cannot establish live ChatGPT eligibility.

## Verified source and CI checks

- Auth, Responses streaming, provider persistence, and existing-provider
  regression checks passed. The final focused Linux run recorded **35 passing
  tests**. OpenAI endpoints and browser callbacks were mocked; the local
  callback listener itself was exercised over real loopback HTTP.
- macOS analysis passed with **zero errors**; existing repository warnings
  remain. The workflow treats analysis errors as fatal.
- Three macOS build runs completed the full mobile test gate, each recording
  **566 Flutter tests passed and 2 skipped**. The final successful job log
  and exact compiled source commit were downloaded and checked.
- The Live2D development gate checked **61 artifacts**. The mobile development
  gate passed while explicitly reporting that no device evidence was recorded.
- Changed Dart formatting, shell syntax, workflow YAML, patch whitespace,
  restored iOS XML and asset JSON were checked.
- Existing API providers retain their configuration and transport paths.
  The ChatGPT provider has separate credentials and cannot fall back to a
  separately billed API key.
- Two pre-existing backup-screen compilation errors were corrected using the
  cloud-backup API's required lazy export callback. This does not perform a
  backup or upload data.

The auth tests cover fresh PKCE/state/nonce, callback rejection, verified RSA
identity signatures and claims, identity-only consent, registration retention,
account isolation, serialized refresh rotation, temporary versus terminal
errors, revocation, and cancellation. Stream tests cover ordered multimodal
history, fragmented UTF-8/SSE, completed versus interrupted/incomplete replies,
safe diagnostics, and the fixed public Responses endpoint.

## Native build history

The source is in the isolated public personal fork
[taizaki69/NativeTavern-ChatGPT-preview](https://github.com/taizaki69/NativeTavern-ChatGPT-preview).
GitHub access and repository write/Actions permissions were verified without
printing credentials. The workflow runs on a standard `macos-15` runner with
Flutter **3.44.9**, Dart **3.12.2**, Xcode **16.4**, and CocoaPods **1.17.0**.
No Apple signing or OpenAI account is used by the job.

1. [Initial run](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37794490930):
   analysis and the complete test gate passed. Compilation stopped because
   upstream did not track the required Xcode workspace and other support files.
2. [Restored-project run](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37797390199):
   analysis and the complete gate passed again. Xcode compiled a **77.3 MB**
   iPhone `Runner.app`; packaging correctly refused a regenerated dependency
   lockfile. No IPA or draft release came from this run.
3. [Configuration inspection](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37799910615):
   Flutter's official `--config-only` route succeeded. The exact changes were
   CocoaPods 1.17.0 dependency checksums and its workspace project reference.
   Those changes were reviewed and committed; the source consistency check
   remains active.
4. [Corrected-configuration build](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37800965945):
   commit `e7ac02ec352db8bafd46cbe1c96232ec6016f690`. Analysis, the complete test
   gate, native compilation, packaging checks,
   and draft release upload all succeeded. The IPA and checksum were downloaded
   and independently inspected.

The restored support files came from the pinned official Flutter template and
upstream `icon.png`. The existing native AppDelegate and Xcode project were
preserved. No whole-project regeneration, signing bypass, or removal of native
Live2D/Spine checks was used.

## Verified compiled artifact

- Filename: `NativeTavern_ChatGPT_v0.1.17+42_unsigned.ipa`.
- Compiled source: `e7ac02ec352db8bafd46cbe1c96232ec6016f690`.
- Size: **45,083,569 bytes** (about 43.0 MiB).
- SHA-256: `331f91cdc803f9bfadce1850dd1884a1fc097afbdccc84ceac0c9f882e4c8db0`.
- Version **0.1.17**, build **42**, bundle ID
  `com.miaomiaoxworld.nativetavern`, minimum **iOS 15.0**.
- The downloaded checksum matches the checksum in the actual CI log, and the
  asset byte count matches GitHub release metadata.
- Independent Info-ZIP validation and the final Python streaming inspector
  passed ZIP CRC checks for the **444 entries**.
- Mach-O inspection verified **arm64 iOS device** binaries for the app,
  `App.framework`, and `Flutter.framework`.
- Compiled Dart AOT markers for ChatGPT sign-in, plan consent, and the official
  auth/API origins were found. Native Live2D/render-scale and Spine markers
  remain present; the macOS packaging script also checked the Spine export.
- No provisioning profile or `_CodeSignature` directories are packaged.
  The main app executable has no code-signature load command. SDK frameworks
  retain signature load-command metadata; the sideload tool must re-sign
  the complete app and its frameworks.
- This is an **unsigned device IPA** requiring local re-signing. No Apple
  signing certificate or installable Apple-signed IPA was produced.

[Draft release with actual downloads](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/releases/tag/untagged-f0544c2bffdabc1d643b).
It requires the owning GitHub account's login. The source package includes
`ipa-verification.json`, and the separate GitHub build report records the
job, test counts, source commit, release target, and checksum evidence.

## Linux limits

The initial broader Linux suite reached **546 passing tests and 2 skipped**,
then failed when a Flutter test subprocess crashed and some unrelated UI tests
did not finish. It is not reported as passing. The subsequent macOS full-suite
runs resolve the source-suite uncertainty, but do not establish device behavior.

The Dart tool/analyzer also crashed with default concurrent garbage collection
on Mint. Successful final local source analysis and the focused test driver
used serialized marking. The official Flutter test engine was restored after
unsuccessful private launcher experiments. No local GC workaround is present
in the application or macOS workflow.

Local iOS packaging correctly returned:

~~~
ERROR: iOS packaging requires macOS with Xcode; this host is Linux
~~~

One initial local Python member read reported a CRC error. The unchanged
IPA then passed independent Info-ZIP validation, repeated Python full and
streamed reads, and the final streaming inspector. Its SHA-256 remained
identical to the CI checksum throughout.

## Not verified on a live iPhone

No owner OpenAI credentials, cookies, Codex auth files, live account/session,
plan allowance, or signing material were inspected or used. The following
remain untested:

- Whether the preview admits this personal iOS client and the owner's account,
  plan, workspace, or region.
- Safari browser-view routing to the app's temporary loopback callback.
- Keychain access and persistence under the final sideload signing identity.
- Live model discovery, a completed Responses inference, refresh after restart,
  cancellation, switching accounts, and remote revocation.
- Native rendering, voice, and other existing app features on the device.

OpenAI's OSS/local-client documentation establishes the implemented protocol;
it does not promise support for this particular iOS build. Test rejection or
unsupported routing must be reported as a restriction, without substituting
an unofficial bridge or ChatGPT internal endpoint.

## Device verification after re-signing

Export existing data first. Re-sign the unsigned IPA with the owner's existing
trusted sideload tool. Then test initial consent, callback completion, catalog
selection, one short completed reply, restart/refresh, cancellation, account
switching, and sign-out. Generation and the app's Test connection consume the
authorized plan/credit allowance. Keep credit usage disabled in ChatGPT's app
limits if only included allowance is intended.
