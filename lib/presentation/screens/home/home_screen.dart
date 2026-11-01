import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:native_tavern/data/models/chat.dart';
import 'package:native_tavern/data/models/character.dart';
import 'package:native_tavern/data/models/group.dart';
import 'package:native_tavern/data/repositories/character_repository.dart';
import 'package:native_tavern/data/repositories/chat_repository.dart';
import 'package:native_tavern/data/repositories/group_repository.dart';
import 'package:native_tavern/l10n/generated/app_localizations.dart';
import 'package:native_tavern/presentation/providers/chat_providers.dart';
import 'package:native_tavern/presentation/router/app_router.dart';
import 'package:native_tavern/presentation/theme/app_theme.dart';
import 'package:native_tavern/presentation/widgets/common/character_avatar_image.dart';
import 'package:native_tavern/presentation/widgets/common/confirm_delete_dialog.dart';
import 'package:native_tavern/presentation/widgets/common/group_avatar.dart';
import 'package:native_tavern/presentation/widgets/common/adaptive_popup_menu.dart';

/// Home screen showing recent chats
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  GoRouter? _router;
  String? _lastPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh chat list when screen is first created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Chats are pushed above the shell, so this screen stays mounted while a
    // conversation is open. Watch the router to refresh previews and ordering
    // as soon as the user comes back.
    final router = GoRouter.maybeOf(context);
    if (!identical(router, _router)) {
      _router?.routerDelegate.removeListener(_onRouteChanged);
      _router = router;
      _router?.routerDelegate.addListener(_onRouteChanged);
      _lastPath = _currentPath;
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String? get _currentPath =>
      _router?.routerDelegate.currentConfiguration.uri.path;

  void _onRouteChanged() {
    final path = _currentPath;
    if (path == AppRoutes.home && _lastPath != AppRoutes.home && mounted) {
      _refresh();
    }
    _lastPath = path;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh chat list when returning to the app
      _refresh();
    }
  }

  void _refresh() => _invalidateChatList(ref.invalidate);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: l10n.groupChats,
            onPressed: () => context.push(AppRoutes.groups),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: l10n.import,
            onPressed: () => context.push(AppRoutes.import_),
          ),
        ],
      ),
      body: const _ChatListView(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.characters),
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(l10n.newChat),
      ),
    );
  }
}

/// Invalidate everything the chat list renders, so ordering, titles, avatars
/// and last-message previews are all re-read from the database.
void _invalidateChatList(void Function(ProviderOrFamily provider) invalidate) {
  invalidate(pagedChatsProvider);
  invalidate(_groupPresentationProvider);
  invalidate(_lastMessageProvider);
  invalidate(_characterForChatProvider);
}

class _ChatListView extends ConsumerWidget {
  const _ChatListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final chatsAsync = ref.watch(pagedChatsProvider);

    return chatsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _HomeMessage(
        icon: Icons.error_outline,
        iconColor: Theme.of(context).colorScheme.error,
        title: l10n.errorLoadingChats(error.toString()),
        action: FilledButton.tonalIcon(
          onPressed: () => _invalidateChatList(ref.invalidate),
          icon: const Icon(Icons.refresh),
          label: Text(l10n.retry),
        ),
      ),
      data: (chats) {
        if (chats.isEmpty) {
          return _HomeMessage(
            icon: Icons.chat_bubble_outline,
            title: l10n.noChatsYet,
            subtitle: l10n.startNewConversation,
            action: FilledButton.icon(
              onPressed: () => context.push(AppRoutes.characters),
              icon: const Icon(Icons.people_outline),
              label: Text(l10n.browseCharacters),
            ),
          );
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 600) {
              ref.read(pagedChatsProvider.notifier).loadMore();
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: () async {
              _invalidateChatList(ref.invalidate);
              await ref.read(pagedChatsProvider.future);
            },
            child: ListView.builder(
              // Keep pull-to-refresh working when only a few chats exist.
              physics: const AlwaysScrollableScrollPhysics(),
              // Leave room so the last chat isn't hidden behind the FAB.
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chat = chats[index];
                return _ChatListTile(key: ValueKey(chat.id), chat: chat);
              },
            ),
          ),
        );
      },
    );
  }
}

/// Centered icon + text used for the empty and error states.
class _HomeMessage extends StatelessWidget {
  const _HomeMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.tavern;
    final tint = iconColor ?? colors.primary;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 52, color: tint),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatListTile extends ConsumerWidget {
  final Chat chat;

  const _ChatListTile({super.key, required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.tavern;
    final characterAsync =
        ref.watch(_characterForChatProvider(chat.characterId));
    final groupPresentationAsync = chat.groupId == null
        ? null
        : ref.watch(_groupPresentationProvider(chat.groupId!));
    final lastMessageAsync = ref.watch(_lastMessageProvider(chat.id));

    final tile = Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        leading: groupPresentationAsync != null
            ? groupPresentationAsync.when(
                loading: () => const SizedBox.square(
                  dimension: 56,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, __) => const GroupAvatar(characters: []),
                data: (presentation) => GroupAvatar(
                  characters: presentation?.characters ?? const [],
                ),
              )
            : characterAsync.when(
                loading: () => const CircleAvatar(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const CircleAvatar(child: Icon(Icons.person)),
                data: (character) => _buildCharacterAvatar(context, character),
              ),
        title: DefaultTextStyle.merge(
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: groupPresentationAsync != null
              ? groupPresentationAsync.when(
                  loading: () => Text(l10n.loading),
                  error: (_, __) => Text(chat.title),
                  data: (presentation) =>
                      Text(presentation?.group.name ?? chat.title),
                )
              : characterAsync.when(
                  loading: () => Text(l10n.loading),
                  error: (_, __) => Text(chat.title),
                  data: (character) => Text(character?.name ?? chat.title),
                ),
        ),
        subtitle: lastMessageAsync.when(
          loading: () => const Text('...'),
          error: (_, __) => Text(l10n.noMessages),
          data: (message) => Text(
            _previewText(message, l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatTime(context, chat.updatedAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textMuted,
              ),
            ),
            AdaptivePopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              padding: EdgeInsets.zero,
              onSelected: (value) => _handleMenuAction(context, ref, value),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: colors.danger),
                      const SizedBox(width: 8),
                      Text(l10n.delete, style: TextStyle(color: colors.danger)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () {
          // Navigate to chat screen
          context.push('/chat/${chat.id}');
        },
      ),
    );

    // Swipe left to delete, with the same confirmation as the menu action.
    return Dismissible(
      key: ValueKey('dismiss-${chat.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: AlignmentDirectional.centerEnd,
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) => confirmDeletion(
        context,
        ref,
        title: l10n.deleteChat,
        message: l10n.deleteChatConfirmation,
      ),
      onDismissed: (_) => _deleteChat(context, ref),
      child: tile,
    );
  }

  Widget _buildCharacterAvatar(BuildContext context, Character? character) {
    final avatarPath = character?.assets?.avatarPath;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      return CharacterAvatarCircle(
        imagePath: avatarPath,
        errorBuilder: (_, __, ___) => _characterFallback(context, character),
      );
    }
    return _characterFallback(context, character);
  }

  Widget _characterFallback(BuildContext context, Character? character) {
    return CircleAvatar(
      backgroundColor: context.tavern.accent.withValues(alpha: 0.2),
      child: Text(
        character?.name.isNotEmpty == true
            ? character!.name.characters.first.toUpperCase()
            : '?',
        style: TextStyle(color: context.tavern.accent),
      ),
    );
  }

  /// One-line preview of the latest message: markup stripped, whitespace
  /// collapsed, and prefixed with "You:" when the user spoke last.
  String _previewText(ChatMessage? message, AppLocalizations l10n) {
    if (message == null) return l10n.noMessagesYet;
    var text = message.content;
    if (text.length > 400) text = text.substring(0, 400);
    text = text
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'[*_`#>]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) text = l10n.noMessagesYet;
    if (message.role == MessageRole.user) return '${l10n.you}: $text';
    return text;
  }

  String _formatTime(BuildContext context, DateTime dateTime) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final local = dateTime.toLocal();
    final now = DateTime.now();
    // Compare calendar days (in UTC to stay DST-safe), not 24h windows, so
    // "Yesterday" really means the previous calendar day.
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(local.year, local.month, local.day))
        .inDays;

    if (days <= 0) {
      return material.formatTimeOfDay(
        TimeOfDay.fromDateTime(local),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
    }
    if (days == 1) return l10n.yesterday;
    if (days < 7) return l10n.daysAgo(days);
    if (local.year == now.year) return material.formatShortMonthDay(local);
    return material.formatShortDate(local);
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    switch (action) {
      case 'delete':
        final l10n = AppLocalizations.of(context);
        final confirmed = await confirmDeletion(
          context,
          ref,
          title: l10n.deleteChat,
          message: l10n.deleteChatConfirmation,
        );
        if (confirmed && context.mounted) await _deleteChat(context, ref);
        break;
    }
  }

  /// Remove the chat from the list immediately, then delete it from storage.
  Future<void> _deleteChat(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // The tile unmounts once the chat leaves the list, so capture the
    // container instead of using `ref` afterwards.
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = container.read(chatRepositoryProvider);

    container.read(pagedChatsProvider.notifier).removeChat(chat.id);
    try {
      await repository.deleteChat(chat.id);
      container.invalidate(allChatsProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatDeleted)));
    } catch (error) {
      _invalidateChatList(container.invalidate);
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.error}: $error')),
      );
    }
  }
}

/// Provider to get character for a chat
final _characterForChatProvider =
    FutureProvider.family<Character?, String>((ref, characterId) async {
  final repo = ref.watch(characterRepositoryProvider);
  return repo.getCharacter(characterId);
});

class _GroupPresentation {
  const _GroupPresentation({required this.group, required this.characters});

  final Group group;
  final List<Character?> characters;
}

final _groupPresentationProvider =
    FutureProvider.family<_GroupPresentation?, String>((ref, groupId) async {
  final groupRepo = ref.watch(groupRepositoryProvider);
  final characterRepo = ref.watch(characterRepositoryProvider);
  final group = await groupRepo.getGroup(groupId);
  if (group == null) return null;
  final characters = await Future.wait(
    group.sortedMembers.take(4).map(
          (member) => characterRepo.getCharacter(member.characterId),
        ),
  );
  return _GroupPresentation(group: group, characters: characters);
});

/// Provider to get last message for a chat
final _lastMessageProvider =
    FutureProvider.family<ChatMessage?, String>((ref, chatId) async {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.getLastMessage(chatId);
});
