NativeTavern ChatGPT preview, version 0.1.17 build 43.

This update fixes the chat composer's API-key-only configuration gate. The official ChatGPT plan connection now uses the normal provider and Model settings, automatically restores the account catalog, and keeps the selected model across reconnects. Account switching discards stale model and connection-test results. Existing API providers and their saved settings remain available.

Sign-in, plan-usage authorization, model selection, and a completed inference request are separate checks. Identity-only sign-in offers Enable plan usage. Catalog, policy, usage-limit, and streaming failures show safe diagnostics and are not treated as completed replies. Unsupported generation controls are hidden for this provider.

Select ChatGPT plan (preview) in AI Configuration. An authorized saved account is reused, and the normal Model setting loads its available models. Test connection makes one short Responses request; ordinary chats use the same official route. There is no Codex bridge or paid API-key fallback.

This is an unsigned arm64 iPhone IPA for iOS 15 or later. Re-sign the complete app with your existing trusted sideload tool. CI uses no OpenAI account or Apple signing material. Live account eligibility, model requests, and final re-signed device behavior remain unverified by the build; successful OAuth alone does not establish inference eligibility.

The workflow will run the complete test gate, native compilation, and packaging checks before saving this draft. See docs/chatgpt-plan-sideload.md and docs/chatgpt-plan-validation.md for the exact results and limitations.
