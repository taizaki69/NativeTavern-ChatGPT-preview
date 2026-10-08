NativeTavern source modification implementing the documented Sign in with ChatGPT open-source plan-sharing preview. Existing API providers remain available.

This is an **unsigned arm64 iPhone device IPA** intended for local re-signing and sideloading. It is not a signed installable IPA or an App Store/TestFlight release. The build job does not sign in to OpenAI, store OpenAI credentials, or use Apple signing material.

Select **ChatGPT plan (preview)** in AI settings, use **Continue with ChatGPT**, grant plan permission in the official system browser, and select a model returned by the account catalog. Preview availability and iPhone browser behavior require live device verification; a successful build does not establish either.

See `docs/chatgpt-plan-sideload.md` for build, signing, security, and validation details. The attached `.sha256` file identifies the artifact. Matching source and original license notices are in this repository at the release target commit.
