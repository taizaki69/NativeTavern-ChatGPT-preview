# Automatic prompt caching across providers

Updated 2026-10-09. Personal preview, NativeTavern 0.1.17 build 46.

Select your existing provider and model in AI Configuration. The caching row shows what that connection supports. For explicit protocols, **Automatic prompt caching** defaults on for new configurations. OpenRouter retains its **Automatic OpenRouter caching** switch. Previously saved opt-outs, including direct Claude's existing false setting, remain off until you enable them.

Automatic caching does not mean every model offers a cache, every request hits one, or every request becomes cheaper. The app uses verified API formats for supported models, relies on provider defaults for implicit caching, and explains unknown or resource-based support instead of inventing parameters.

## Audited behavior

The audit covers all 14 providers exposed by this app. Custom URLs can implement a different contract; unfamiliar direct endpoints receive no speculative cache controls.

| App provider | Behavior in build 46 | Controls and reported usage |
| --- | --- | --- |
| OpenAI API | GPT-5.6 and GPT-6 API models use explicit stable-prefix breakpoints; earlier supported GPT/o models use implicit server caching. | New models use `prompt_cache_options.mode: explicit` and text-block `prompt_cache_breakpoint`. Off means no app-added breakpoints. Read/write counters come from token details. Official endpoint required. |
| OpenAI Compatible | Recognized official OpenAI or DashScope hosts use their audited controls; other servers retain their requests. | Unknown servers show a limitation. Standard reported numeric token details are still displayed. An OpenAI-compatible API is not proof of caching support. |
| Anthropic Claude | Active recognized Sonnet, Opus, Haiku, Fable and Mythos families use five-minute content-block markers, including native tool requests. | Existing Claude switch is preserved; new/missing configurations default on. Read/write counters come from native Anthropic usage. |
| Qwen / DashScope | Exact documented model aliases/snapshots receive five-minute content-block markers; other routes use the server's applicable implicit behavior. | Model and regional availability matter. Off removes app-added explicit markers; eligible implicit caching cannot be disabled by this switch. Read/write details are parsed. |
| OpenRouter | Supported Claude families, documented Alibaba Qwen routes and GPT-5.6/GPT-6 routes get their respective explicit formats. Eligible other routes cache at the serving provider. | Existing provider order and fallbacks are preserved. Missing support is shown as server-controlled. Normalized reported cache counters are retained. |
| Gemini | Gemini 2.5 and newer use implicit caching without new fields. | Native `usageMetadata.cachedContentTokenCount` is displayed, including final usage-only stream objects. Older controlled caches require separate resources; these are not created automatically. |
| DeepSeek | Official prefix caching remains automatic. | Reported `prompt_cache_hit_tokens` is read usage. Cache misses are not mislabelled as writes. |
| Moonshot / Kimi | The official Chat Completions route keeps its automatic/default caching behavior. | No unsupported explicit-block markers or longer TTL are added. Reported standard token details are displayed. Current Kimi cache-write pricing is distinct from older assumptions. |
| Z.AI | Eligible GLM models on the audited international `api.z.ai` route retain server-side caching. The app's default regional BigModel endpoint remains server-controlled in the policy. | Standard reported cached-token details are displayed for both. No international-only controls are sent to the regional endpoint. |
| MiniMax | Its OpenAI-compatible route retains passive caching. | Standard reported cached-token details are displayed. The app does not switch to another API protocol to force caching. |
| SiliconFlow | Model-specific cache pricing/support is controlled by its endpoint. | No universal cache toggle is asserted. Standard counters are displayed when actually supplied. Check the selected model's current pricing and API contract. |
| Ollama | Local server context reuse is preserved. | No cloud-cache fields or fabricated cache counters. Model keep-alive and prompt evaluation counts are not cache-hit or savings measurements. |
| KoboldCpp | Local context reuse depends on server configuration. | No remote changes to Smart Context or context size. No cloud caching fields or invented discounts. |
| ChatGPT plan preview | The official stateless Responses route is preserved. | No API-only cache options are added. Numeric final usage is displayed only after confirmed `response.completed`; caching does not establish account eligibility or completed live inference. |

## Reusable prefixes and privacy

Markers operate on request copies after context fitting, role processing and tool decoration. They preserve message text, roles, ordering, images, thinking signatures and tool identities. Leading instructions and earlier conversation history are marked while the newest input and trailing assistant prefill remain outside app-added history boundaries. At most four total markers are used, including existing message/system/tool markers. Manual longer Claude TTLs are retained and respected.

There is no prompt padding, extra warm-up inference, local plaintext cache file, forced routing, background paid request, or automatic cache-resource creation. Existing chat storage remains unchanged. Changing any prefix sends the changed content; the provider decides whether anything still matches. Dynamic macros, changing lore, context truncation, summarization and tool-schema changes can reduce reuse.

The app retains only numeric cache reads/writes in reply metadata, separately for each alternative. Build-45 metrics remain readable. Repeated cumulative stream snapshots are not added together; separate tool-round request counters are aggregated. Missing counters stay unknown, while reported zero is displayed as zero. No raw response, prompt, account identifier, key or cache resource ID is added to this metadata.

## Costs, retention and opt-out

Explicit writes can cost more than ordinary input, and unused/expired entries do not guarantee a saving. Claude/DashScope markers request the default five-minute lifetime. New OpenAI controls use the provider's default 30-minute lifetime without prewarming. Other providers retain their existing defaults; the app does not request longer billed retention.

The switch controls app-added explicit caching. Manual caller-supplied markers are preserved. Providers with mandatory or implicit caching may still cache after app markers are disabled; settings say so. New OpenAI explicit-only requests without app or manual breakpoints avoid automatic cache writes. The app does not claim it can flush a provider's cache.

Gemini's separately managed explicit cache objects incur storage/resource charges. The app does not provision them under this automatic feature. Use supported implicit models if you want provider-managed reuse without app-created storage.

## Check actual results

Re-sign and install build 46, keep your current connection and model, and check the caching row. Reuse a sufficiently long, unchanged character/system prefix across nearby turns. Completed replies show **Cache read** and **Cache write** only when the provider reports those counters. Compare those figures and your provider's billing records. Short prompts, route changes, cache expiry and edited prefixes can cause misses.

Automated tests use synthetic accounts and mocked/local HTTP. Live cache hits, actual costs, account/model admission and final re-signed iPhone behavior remain unverified. No paid inference was made to validate this change.

## Official sources

- [OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching) and [Chat Completions reference](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create).
- [Anthropic prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching).
- [OpenRouter caching](https://openrouter.ai/docs/guides/best-practices/prompt-caching).
- [Alibaba context cache](https://www.alibabacloud.com/help/en/model-studio/context-cache) and [stream usage](https://www.alibabacloud.com/help/en/model-studio/stream).
- [Gemini caching](https://ai.google.dev/gemini-api/docs/caching) and [generateContent usage metadata](https://ai.google.dev/api/generate-content#UsageMetadata).
- [DeepSeek context caching](https://api-docs.deepseek.com/guides/kv_cache) and [Chat Completions streaming](https://api-docs.deepseek.com/api/create-chat-completion/).
- [Kimi context caching](https://platform.kimi.ai/docs/guide/context-caching).
- [Z.AI context caching](https://docs.z.ai/guides/capabilities/cache).
- [MiniMax passive caching](https://platform.minimax.io/docs/api-reference/text-prompt-caching).
- [SiliconFlow caching/pricing guidance](https://www.siliconflow.com/blog/siliconflow-prompt-caching-api-costs) and [API contract](https://docs.siliconflow.com/en/api-reference/chat-completions/chat-completions).
- [Ollama chat API](https://docs.ollama.com/api/chat) and [KoboldCpp Smart Context](https://github.com/LostRuins/koboldcpp/wiki#what-is-smart-context).
- [Official ChatGPT preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).

## Verified build 46

[The actual macOS run](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/38014008008) passed **671 tests, with 2 skipped**,
with zero analysis errors. The final source passed 149 focused tests, including
58 caching tests. The downloaded IPA passed checksum, all-member ZIP CRC,
version, arm64 iOS-device, compiled general cache/ChatGPT and Live2D/Spine checks.
Matching source and verification reports accompany the unsigned release.

These results verify the request formats, saved controls, numerical reporting
and actual compiled artifact. They do not establish live cache hits or savings.
