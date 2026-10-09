# NativeTavern: automatic OpenRouter prompt caching — build 45

Prepared 2026-10-09. Personal version: `0.1.17+45`.
This update retains the official ChatGPT plan-sharing preview and existing API
providers. OpenRouter requests continue to use your existing OpenRouter
connection and its billing; caching does not consume your ChatGPT subscription.

## Use it

1. Export your existing app data before updating. Download the build-45 unsigned
   IPA from [the fork's Releases page](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/releases)
   while signed in as the fork owner. Re-sign the entire app with your existing
   sideload tool, preferably keeping the same bundle ID and signing identity.
2. Keep your existing **OpenRouter** provider and connection. Choose
   `anthropic/claude-sonnet-5.5` in the normal **Model** setting.
3. **Automatic OpenRouter caching** is enabled by default, including for saved
   connections created before this update. This switch appears in AI settings
   for recognized OpenRouter Claude Sonnet, Opus and Haiku 4/5 model IDs. Turn it
   off there if you do not want the app to add cache markers. Your choice survives
   app restarts and switching providers. Direct Anthropic's existing caching
   setting remains separate.
4. Chat normally. When OpenRouter reports counters, a completed assistant reply
   shows **Cache read: N tokens** and/or **Cache write: N tokens**. The counts
   belong to the selected reply alternative and survive saving and reloading.
   Tool-generated replies total the reported counters from their generation
   rounds. The app makes no extra usage-query or cache warm-up requests.

The counters come from OpenRouter's response, including its final streaming
event; no additional usage parameter is needed. Reported zero reads means
no reported cache hit for that generation. An absent label means the response
did not supply recognized counters, not a proven hit or miss.
[OpenRouter usage accounting](https://openrouter.ai/docs/cookbook/administration/usage-accounting).

## What the app changes

For supported OpenRouter Claude requests, the app adds
`cache_control: {"type": "ephemeral"}` to request copies of reusable text blocks.
It prioritizes the end of leading instructions and earlier conversation history,
with earlier instruction boundaries as fallbacks. The newest user question and
trailing assistant prefill stay outside the growing-history boundary.

Prompt text, role order, images, tools, provider selection and fallback policy
are preserved. The app adds at most four markers, accounting for existing
message markers. New five-minute markers stay after any existing one-hour
message marker. It does not reorder lore, strip needed context, pad short
prompts, retain a local plaintext cache, force another provider, or request
the more expensive one-hour retention. It handles streaming and non-streaming
chat, regeneration, group/assistant generation and tool continuations.

The automatic placement runs after the app's existing context fitting and
role processing. A changed card, prompt, lore, RAG result, summary or trimmed
history is still sent as changed content. No cached answer replaces generation.

## Why a cache may miss

The default retention is five minutes. Sonnet 5.5 currently requires a cacheable
prefix of at least 512 tokens; other models/routes can have different minimums.
Cache writes cost extra, so enabling caching does not guarantee savings.
A cold or expired cache, changed prompt prefix, changed model or a provider
fallback can produce writes rather than reads. Your manual provider order
continues to take priority.
[OpenRouter caching requirements](https://openrouter.ai/docs/guides/best-practices/prompt-caching).

A cache matches exact prefixes. The provider's backward search is limited to
20 content-block positions per boundary. The early instruction boundaries help
when later content changes, but edits before a boundary and long newly appended
block sequences can still prevent reuse. Images and tool changes can also
invalidate later content.
[Anthropic prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching).

Use the reported read/write counts and OpenRouter's activity page to assess
your actual requests. The app does not display estimated dollar savings or
promise a cache hit. For one-off prompts that will not be reused, the switch
lets you avoid app-requested cache writes.

## Verification limits

Source tests exercise outgoing requests, stable prefixes over chat turns, edited
content, limits, persisted opt-out, other providers, tool rounds, and saved reply
counters. They use synthetic responses and local/mock HTTP, not your API key.
The matching build report records the actual macOS test gate and IPA inspection.

Live cache hits, billed savings and behavior on a re-signed iPhone remain
unverified. A successful OAuth sign-in in the separate ChatGPT provider also
does not establish completed Responses inference or account eligibility.

## Verified build 45

[The macOS run](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/37894204117) passed **640 tests, with 2 skipped**,
and analysis completed with zero errors. The downloaded unsigned device IPA
passed checksum, all-member ZIP CRC and compiled cache/ChatGPT/native feature
checks. Its matching source and reports accompany the release.

These checks establish request behavior with synthetic responses and a compiled
device app. They do not establish live cache hits, paid savings or the final
re-signed phone's behavior.
