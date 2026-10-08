NativeTavern source modification implementing the documented Sign in with ChatGPT open-source plan-sharing preview. Existing API providers remain available.

This is an **unsigned arm64 iPhone device IPA** intended for local re-signing and sideloading. It is not a signed installable IPA or an App Store/TestFlight release. The build job does not sign in to OpenAI, store OpenAI credentials, or use Apple signing material.

Select **ChatGPT plan (preview)** in AI settings, use **Continue with ChatGPT**, grant plan permission in the official system browser, and select a model returned by the account catalog. Preview availability and iPhone browser behavior require live device verification; a successful build does not establish either.

See `docs/chatgpt-plan-sideload.md` for build, signing, security, and validation details. The attached `.sha256` file identifies the artifact. Matching source and original license notices are in this repository at the release target commit.

Verified build: 566 Flutter tests passed, 2 skipped, zero analysis errors,
arm64 iPhone compilation, native capability checks, and downloaded IPA checks.
Minimum iOS 15; version 0.1.17 build 42.

Build run: https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37800965945
Compiled source: e7ac02ec352db8bafd46cbe1c96232ec6016f690
IPA SHA-256: 331f91cdc803f9bfadce1850dd1884a1fc097afbdccc84ceac0c9f882e4c8db0

The English sideload guide, source patch archive, and verification reports
accompany this preview. Live OpenAI eligibility and iPhone sign-in remain
untested. Re-sign the whole app with your existing trusted sideload tool.
