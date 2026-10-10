/// Request controls are selected by protocol, documented model support, and
/// endpoint. Unknown compatible servers receive no speculative cache fields.
enum PromptCacheMode {
  blocks,
  openAiBreakpoints,
  implicit,
  resource,
  local,
  unknown
}

class PromptCachePolicy {
  const PromptCachePolicy(this.mode, this.description);
  final PromptCacheMode mode;
  final String description;
  bool get appControlled =>
      mode == PromptCacheMode.blocks ||
      mode == PromptCacheMode.openAiBreakpoints;

  static bool modernOpenAi(String model) {
    final m = RegExp(r'^gpt-(5|6)(?:\.(\d+))?(?:$|[-:])').firstMatch(model);
    return m != null && (m[1] == '6' || (int.tryParse(m[2] ?? '0') ?? 0) >= 6);
  }

  static bool claude(String model) => RegExp(
          r'^claude-(?:(?:sonnet|opus|haiku|fable|mythos)-[45](?:[.-]\d+)*|3[.-]5-(?:sonnet|haiku)(?:-\d+)?)(?:-latest)?$')
      .hasMatch(model);

  // Exact advertised aliases/snapshots; do not infer arbitrary Qwen endpoints.
  static const qwenExplicit = {
    'qwen3.8-max',
    'qwen3.8-max-0902',
    'qwen3.8-2.4t-a95b',
    'qwen3.8-27b',
    'qwen3.8-flash',
    'qwen3.7-max',
    'qwen3.7-max-2026-05-20',
    'qwen3.7-max-2026-06-08',
    'qwen3.6-max-preview',
    'qwen3-max',
    'qwen3.7-plus',
    'qwen3.7-plus-2026-05-26',
    'qwen3.6-plus',
    'qwen3.5-plus',
    'qwen3.5-plus-2026-04-20',
    'qwen-plus',
    'qwen3.7-flash',
    'qwen3.7-flash-2026-07-15',
    'qwen3.6-flash',
    'qwen3.5-flash',
    'qwen-flash',
    'qwen3-coder-plus',
    'qwen3-coder-flash',
    'qwen3-vl-plus',
    'qwen3-vl-flash',
    'deepseek-v3.2',
  };
  static const routerQwenExplicit = {
    'qwen/qwen3-max',
    'qwen/qwen-plus',
    'qwen/qwen3.6-plus',
    'qwen/qwen3-coder-plus',
    'qwen/qwen3-coder-flash',
    'deepseek/deepseek-v3.2',
  };

  static bool qwenHost(String host) =>
      const {
        'dashscope.aliyuncs.com',
        'dashscope-intl.aliyuncs.com',
        'dashscope-us.aliyuncs.com',
      }.contains(host) ||
      host.endsWith('.maas.aliyuncs.com');

  static const _blocks = PromptCachePolicy(PromptCacheMode.blocks,
      'The app marks unchanged instructions and earlier history with five-minute cache breakpoints. Writes can cost extra; hits require sufficient matching context. Turning this off stops app-added markers; server caching may still apply.');
  static const _openAi = PromptCachePolicy(PromptCacheMode.openAiBreakpoints,
      'The app uses explicit breakpoints on reusable prefixes, keeping changing input outside cache writes. OpenAI uses its default 30-minute lifetime. Writes can cost extra. Turning this off disables automatic writes for these supported API models.');
  static const _implicit = PromptCachePolicy(PromptCacheMode.implicit,
      'Caching is handled automatically by the provider for eligible models and matching prefixes. No app switch can reliably disable it. Reported cache counts appear on completed replies; hits and savings are not guaranteed.');
  static const _unknown = PromptCachePolicy(PromptCacheMode.unknown,
      'Caching support is controlled by this server and model. No unverified cache parameters are added. Reported cache counts are displayed when supplied; a compatible API name alone does not establish caching support.');

  static PromptCachePolicy forConnection(
      String provider, String model, String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    final slug = model.trim().toLowerCase().split(':').first;
    if (provider == 'chatgptPlan') {
      return const PromptCachePolicy(PromptCacheMode.unknown,
          'ChatGPT plan usage keeps the official stateless Responses route. API cache controls are not enabled for this preview. Any reported cache usage is displayed without promising plan savings or account eligibility.');
    }
    if (provider == 'ollama' || provider == 'koboldCpp') {
      return const PromptCachePolicy(PromptCacheMode.local,
          'Local context reuse depends on the server, model, memory and context settings. The app preserves prompt order and adds no cloud cache fields. Keeping a model loaded is not a reported cache hit or a billing discount.');
    }
    if (provider == 'openRouter') {
      if (slug.startsWith('anthropic/') && claude(slug.substring(10)))
        return _blocks;
      if (routerQwenExplicit.contains(slug)) return _blocks;
      if (slug.startsWith('openai/') && modernOpenAi(slug.substring(7)))
        return _openAi;
      if (slug.startsWith('google/gemini-')) {
        return _gemini(slug.substring(7));
      }
      if (RegExp(
              r'^(?:openai/(?:gpt-(?:4o|4\.1|5)|o[134])|deepseek/deepseek-|z-ai/glm-|moonshotai/kimi-|minimax/minimax-m|x-ai/grok-)')
          .hasMatch(slug)) {
        return _implicit;
      }
      // Other routes may cache at their serving endpoint; do not infer a
      // parameter contract just from an arbitrary model name.
      return _unknown;
    }
    // A custom OpenAI-compatible connection may use an audited official host.
    if (provider == 'openai' || provider == 'openAICompatible') {
      if (host == 'api.openai.com') {
        if (modernOpenAi(slug)) return _openAi;
        if (RegExp(r'^(?:gpt-(?:4o|4\.1|5)(?:$|[.-])|o[134](?:$|-))')
            .hasMatch(slug)) return _implicit;
      }
      if (qwenHost(host) && qwenExplicit.contains(slug)) return _blocks;
      return _unknown;
    }
    if (provider == 'qwen' && qwenHost(host)) {
      return qwenExplicit.contains(slug) ? _blocks : _implicit;
    }
    if (provider == 'claude') {
      return host == 'api.anthropic.com' && claude(slug) ? _blocks : _unknown;
    }
    if (provider == 'gemini' && host == 'generativelanguage.googleapis.com') {
      return _gemini(slug);
    }
    if (provider == 'deepSeek' && host == 'api.deepseek.com' ||
        provider == 'zai' && host == 'api.z.ai' ||
        provider == 'miniMax' &&
            const {'api.minimax.io', 'api.minimaxi.com'}.contains(host) ||
        provider == 'moonshot' &&
            const {'api.moonshot.ai', 'api.moonshot.cn', 'api.kimi.ai'}
                .contains(host)) {
      return _implicit;
    }
    // SiliconFlow has model-specific cached-input pricing; the public Chat
    // Completions contract does not expose a universal cache toggle.
    return _unknown;
  }

  static PromptCachePolicy _gemini(String slug) {
    final m = RegExp(r'^gemini-(\d+)(?:\.(\d+))?(?:$|-)').firstMatch(slug);
    if (m != null &&
        (int.parse(m[1]!) > 2 ||
            int.parse(m[1]!) == 2 && int.parse(m[2] ?? '0') >= 5))
      return _implicit;
    return const PromptCachePolicy(PromptCacheMode.resource,
        'This older Gemini route requires an explicit cache resource for controlled reuse. The app does not automatically create paid storage resources. Gemini 2.5 and newer use provider-managed implicit caching.');
  }

  /// Only audited direct OpenAI/DashScope streaming schemas request usage.
  static bool requestsStreamUsage(String provider, String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return (provider == 'openai' || provider == 'openAICompatible') &&
            host == 'api.openai.com' ||
        (provider == 'qwen' || provider == 'openAICompatible') &&
            qwenHost(host);
  }
}
