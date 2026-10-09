NativeTavern ChatGPT preview, version 0.1.17 build 45.

This update adds automatic prompt caching for supported OpenRouter Claude
models, including Sonnet 5.5. It marks reusable instruction/history prefixes
in streaming, non-streaming and tool requests without changing prompt text,
provider routing or the newest question. The setting defaults on and can be
turned off in AI configuration. Replies show OpenRouter's reported cache reads
and writes for the selected reply alternative.

See [the caching guide](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/blob/main/docs/openrouter-prompt-caching.md).
The default retention is five minutes. Writes cost extra; hits and savings
depend on actual reuse, model minimums, unchanged content and provider routing.
No live paid inference or owner API credentials are used to test this change.

The official ChatGPT plan-sharing provider and build-44 response transport
remain in use. Completed live Responses inference and account eligibility are
still unverified. No Codex bridge or API-key fallback was introduced.

129 focused source tests passed, including 27 caching tests. Analysis reports
zero errors, and native development gates passed. These checks use synthetic
responses and local/mock HTTP. The new CI run and downloaded IPA are not verified yet;
this draft's validation details will be updated after those checks complete.
The IPA must be re-signed locally before sideloading. Preserve your existing
app data and signing identity. Earlier preview builds remain separate.
