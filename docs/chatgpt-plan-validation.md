# Validation of the NativeTavern ChatGPT preview patch

Date: 2026-10-08. Base: `6dbd1ee042e994966db85693594ab61e4f4ec441`.
Personal source version: `0.1.17+42`. These results concern the source patch,
not an installed iPhone application.

## Verified

- Dependencies resolved on Linux Mint with Flutter 3.44.9 / Dart 3.12.2.
- Final targeted run: **35 tests passed**, exit 0. Files:
  `chatgpt_plan_test.dart`, `gemini_streaming_regression_test.dart`,
  `connection_profile_key_test.dart`, `llm_config_persistence_test.dart`.
- Coverage includes signed JWT identity validation and tampering, fresh PKCE
  and callbacks, account identity isolation, identity-only grants, retained
  registration after expired code, serialized rotating refresh, terminal versus
  temporary errors, successful and unconfirmed revocation, real local HTTP
  callback listener cleanup/cancellation, ordered model catalogs, multimodal
  conversion, fragmented UTF-8/multiline SSE, late stream failures, public
  Responses transport, no API-key fallback, and provider/profile persistence.
- The final full-project analysis completed with **0 errors**. Existing warnings
  remain in the repository. New auth/platform/Responses files had no warnings.
- Changed Dart files pass formatting. The iOS shell script passes
  `bash -n`; the patch passes whitespace checks.
- Live2D development gate passed (61 artifacts). Mobile development gate
  passed while explicitly warning that no device evidence has been recorded.
- The source includes an explicit unsigned mode in the repository's original
  iOS build script and a manual macOS GitHub Actions workflow. The workflow
  uses a standard public-repository runner and saves verified output only as
  draft release assets.
- Two existing backup-screen compilation errors were fixed by supplying the
  lazy export callback expected by the cloud-backup API. These changes do not
  perform a backup or upload anything.

## Limits and incomplete checks

A broader Linux test run reached **546 passing tests and 2 skipped tests**,
then ended unsuccessfully: a Flutter test subprocess segfaulted while loading
the Live2D lifecycle tests, and several unrelated UI tests did not complete.
**The full suite is not reported as passing.** The macOS workflow retains the
full mobile test gate; it must pass before packaging or uploading output.

The Dart tool/analyzer also crashed with its default concurrent garbage
collection on this host. Final source analysis and the targeted test driver
used serialized marking with one marker task. Targeted Flutter tests used the
official, unmodified Flutter engine. Experimental private test-launcher
wrappers were rejected by the engine or aborted and were removed; those runs
are not passing evidence. No GC workaround is added to the application or
the macOS build workflow.

The local packaging attempt returned:

~~~
ERROR: iOS packaging requires macOS with Xcode; this host is Linux
~~~

GitHub CLI and the persistent browser were signed out. No available authenticated
repository write/Actions permission could therefore be verified. No remote fork
was created, workflow dispatched, macOS job run, release asset downloaded, or
compiled IPA produced during this validation. The included workflow is prepared
source, not a completed build.

The OpenAI network is mocked in the source tests. No owner credentials, Codex
auth files, cookies, or live account/session were inspected or used.
The loopback test uses a real Linux listener with an injected browser;
it does not establish Safari routing on an iPhone. Live eligibility, system
browser behavior, Keychain operation under a re-signed app, and real Responses
inference remain untested.

## Required next verification

After GitHub is connected, create a public personal fork/branch containing
only the source changes, run the manual workflow, inspect the actual job and
full test results, and download/verify the draft release's unsigned IPA and
checksum. A signed installable IPA still requires local re-signing.

On the iPhone, verify initial consent, callback completion, model discovery,
one completed reply, restart/refresh, cancellation, account switching, and
sign-out. Rejected eligibility or unsupported mobile routing must be reported
as a restriction, without replacing the route with an unofficial bridge.
