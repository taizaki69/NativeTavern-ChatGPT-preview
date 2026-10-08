import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/services/chatgpt_plan_client.dart';
import '../../../domain/services/chatgpt_plan_platform.dart';
import '../../../domain/services/llm_service.dart';
import '../../providers/settings_providers.dart';

class ChatGptPlanTile extends ConsumerStatefulWidget {
  const ChatGptPlanTile({super.key});
  @override
  ConsumerState<ChatGptPlanTile> createState() => _ChatGptPlanTileState();
}

class _ChatGptPlanTileState extends ConsumerState<ChatGptPlanTile> {
  final _platform = ChatGptPlanPlatform.instance;
  Future<List<ChatGptAccount>>? _accounts;
  bool _busy = false;
  String? _message;

  void _reload() {
    setState(() {
      _accounts = _platform.client.accounts();
    });
  }

  Future<void> _signIn({String? clientId, bool enableSharing = false}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    ref.read(llmServiceProvider).cancelActiveRequest();
    try {
      final account = await _platform.signIn(
          clientId: clientId, enableSharing: enableSharing);
      if (!mounted) return;
      ref
          .read(llmConfigProvider.notifier)
          .updateChatGptProfile(account.clientId);
      ref.read(modelFetchProvider.notifier).reset();
      setState(() {
        _message = account.sharing
            ? 'Connected. Select a model below to use your ChatGPT plan.'
            : 'Signed in. Plan usage is disabled; choose Enable plan usage to authorize it.';
      });
      if (account.sharing) {
        await ref
            .read(modelFetchProvider.notifier)
            .fetchModels(ref.read(llmConfigProvider));
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _message = e is ChatGptPlanException
              ? e.toString()
              : 'Could not connect ChatGPT. Please try again.';
        });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
        _reload();
      }
    }
  }

  Future<void> _signOut(String clientId) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    ref.read(llmServiceProvider).cancelActiveRequest();
    try {
      final revoked = await _platform.client.signOut(clientId);
      if (!mounted) return;
      ref.read(llmConfigProvider.notifier).updateModel('');
      ref.read(modelFetchProvider.notifier).reset();
      setState(() {
        _message = revoked
            ? 'Signed out. This registration is retained for reconnecting.'
            : 'Signed out locally. Remote revocation was not confirmed; disconnect NativeTavern in ChatGPT Settings.';
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _message =
              'Sign-out could not be completed. Try again or disconnect this app in ChatGPT Settings.';
        });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
        _reload();
      }
    }
  }

  @override
  void dispose() {
    if (_busy) _platform.cancelSignIn();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(llmConfigProvider);
    if (config.provider != LLMProvider.chatgptPlan)
      return const SizedBox.shrink();
    _accounts ??= _platform.client.accounts();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<List<ChatGptAccount>>(
        future: _accounts,
        builder: (context, snapshot) {
          final accounts = snapshot.data ?? const <ChatGptAccount>[];
          final selected = accounts
              .where((a) => a.clientId == config.chatgptProfileId)
              .firstOrNull;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    selected?.connected == true && selected?.sharing == true
                        ? 'Using ChatGPT plan'
                        : 'Connect your ChatGPT account',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                    'Official plan sharing preview for this local open-source app. Account, workspace, and regional eligibility are checked by OpenAI. Your existing plan limits apply; manage any credit allowance in ChatGPT Settings.'),
                const SizedBox(height: 8),
                if (accounts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey(config.chatgptProfileId),
                    initialValue: selected?.clientId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'ChatGPT account / registration'),
                    items: accounts
                        .map((a) => DropdownMenuItem(
                            value: a.clientId,
                            child:
                                Text(a.label, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (id) {
                            if (id == null) return;
                            ref.read(llmServiceProvider).cancelActiveRequest();
                            ref
                                .read(llmConfigProvider.notifier)
                                .updateChatGptProfile(id);
                            ref.read(modelFetchProvider.notifier).reset();
                            final chosen =
                                accounts.firstWhere((a) => a.clientId == id);
                            if (chosen.connected && chosen.sharing) {
                              ref
                                  .read(modelFetchProvider.notifier)
                                  .fetchModels(ref.read(llmConfigProvider));
                            }
                            setState(() {
                              _message = null;
                            });
                          },
                  ),
                if (snapshot.hasError)
                  const Text('Protected account settings could not be loaded.'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _signIn(clientId: selected?.clientId),
                      child: const Text('Continue with ChatGPT')),
                  if (accounts.isNotEmpty)
                    TextButton(
                        onPressed: _busy ? null : () => _signIn(),
                        child: const Text('Add account')),
                  if (selected?.connected == true && selected?.sharing != true)
                    TextButton(
                        onPressed: _busy
                            ? null
                            : () => _signIn(
                                clientId: selected!.clientId,
                                enableSharing: true),
                        child: const Text('Enable plan usage')),
                  if (selected?.connected == true)
                    TextButton(
                        onPressed:
                            _busy ? null : () => _signOut(selected!.clientId),
                        child: const Text('Sign out')),
                  TextButton(
                      onPressed: () => launchUrl(
                          Uri.parse('https://chatgpt.com/settings/usage'),
                          mode: LaunchMode.externalApplication),
                      child: const Text('Manage usage')),
                  if (_busy)
                    TextButton(
                        onPressed: _platform.cancelSignIn,
                        child: const Text('Cancel sign-in')),
                ]),
                if (selected?.connected == true && selected?.sharing == true)
                  const ChatGptPlanModelPicker(),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_message!)),
                const SizedBox(height: 8),
                const Text(
                    'This connection always streams. Sampling controls, output-token caps, and native tool calling are unavailable here. Your full required conversation history is sent with each request.'),
              ]);
        },
      ),
    );
  }
}

class ChatGptPlanModelPicker extends ConsumerWidget {
  const ChatGptPlanModelPicker({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(llmConfigProvider);
    final catalog = ref.watch(modelFetchProvider);
    final loading = catalog.status == ModelFetchStatus.loading;
    final selected =
        catalog.models.contains(config.model) ? config.model : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey(
            '${config.chatgptProfileId}:$selected:${catalog.models.join(",")}'),
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'ChatGPT model'),
        hint: const Text('Select an available model'),
        items: catalog.models
            .map((slug) => DropdownMenuItem(
                  value: slug,
                  child: Text(catalog.modelNames[slug] ?? slug,
                      overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: loading
            ? null
            : (slug) {
                if (slug != null)
                  ref.read(llmConfigProvider.notifier).updateModel(slug);
              },
      ),
      TextButton.icon(
        onPressed: loading
            ? null
            : () => ref
                .read(modelFetchProvider.notifier)
                .fetchModels(ref.read(llmConfigProvider)),
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh available models'),
      ),
      if (loading) const LinearProgressIndicator(),
      if (catalog.errorMessage != null) Text(catalog.errorMessage!),
      if (catalog.status == ModelFetchStatus.success &&
          config.model.isNotEmpty &&
          selected == null)
        const Text(
            'The previously selected model is unavailable. Select a model from this account.'),
    ]);
  }
}
