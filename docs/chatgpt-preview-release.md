NativeTavern ChatGPT preview, version 0.1.17 build 46.

This update extends automatic prompt caching across the app's audited provider protocols. Supported direct Claude and Qwen models use stable-prefix content-block markers; newer OpenAI API models use their own explicit breakpoints. Eligible implicit caching remains controlled by the server. OpenRouter's existing connection and routing are preserved, with broader supported model coverage.

AI Configuration explains app-controlled, provider-managed, local, unknown and resource-based caching. Existing opt-outs are retained. Replies show reported numeric cache reads/writes across native and compatible APIs, selected alternatives and tool rounds. Repeated cumulative stream usage is not counted twice.

[English provider caching guide](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/blob/main/docs/provider-prompt-caching.md).

Cache writes can cost extra. Hits and savings depend on exact reusable content, model support, minimum length, retention and routing. No paid cache resources, extra warm-up inference or longer retention are requested. Live cache hits and billed savings remain unverified. Tests use synthetic accounts and local/mock HTTP, without owner API credentials.

**671 full Flutter tests passed, 2 skipped**, with zero analysis errors.
The source also passed 149 focused tests, including 58 caching tests. Native
development gates, device compilation and unsigned packaging succeeded.
The downloaded IPA passed checksum, all-member ZIP CRC, version, arm64 device,
provider caching/ChatGPT compiled markers and native Live2D/Spine checks.

[Successful build](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/38014008008). [Exact compiled source](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/tree/820c196ed0c9c100edded8411b1fd8e8e2758a97).
IPA: `NativeTavern_ChatGPT_v0.1.17+46_unsigned.ipa` (45,121,961 bytes).
SHA-256: `41a88d671c138d7d97dfcf9b688559605a9f1c17fd8db6f05fa027938a1c5238`.

Matching source, complete patch, checksums, English guides and verification
reports accompany this build. Earlier draft releases remain unchanged.

The official ChatGPT provider and existing response transport are retained. Completed live Responses inference, account/mobile admission and re-signed device behavior remain unverified. No Codex bridge or API-key fallback was added.

This is an unsigned device app for iOS 15 or later. Back up existing data, then re-sign the whole app with your usual sideload tool. Keep your current connection and model and check the caching row in settings. Some providers cache implicitly without a local off switch; unknown servers receive no speculative fields. Older Gemini explicit caches require separately managed resources and are not provisioned automatically.
