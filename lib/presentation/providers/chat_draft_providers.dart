import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_providers.dart';

/// Keeps unsent chat input per conversation, so leaving a chat (to check a
/// lorebook, switch apps, or open another chat) never loses typed text.
class ChatDraftStore {
  ChatDraftStore(this._prefs);

  static const _keyPrefix = 'chat_draft::';

  final SharedPreferences _prefs;

  String _key(String chatId) => '$_keyPrefix$chatId';

  /// The saved draft for [chatId], or `null` when there is none.
  String? read(String chatId) {
    final draft = _prefs.getString(_key(chatId));
    return (draft == null || draft.trim().isEmpty) ? null : draft;
  }

  /// Save [text] as the draft for [chatId]; blank text clears it.
  Future<void> write(String chatId, String text) async {
    if (text.trim().isEmpty) {
      await clear(chatId);
      return;
    }
    if (_prefs.getString(_key(chatId)) == text) return;
    await _prefs.setString(_key(chatId), text);
  }

  Future<void> clear(String chatId) async {
    if (!_prefs.containsKey(_key(chatId))) return;
    await _prefs.remove(_key(chatId));
  }
}

final chatDraftStoreProvider = Provider<ChatDraftStore>((ref) {
  return ChatDraftStore(ref.watch(sharedPreferencesProvider));
});

/// Saved draft for a chat. Invalidate to re-read after the chat screen
/// changes it.
final chatDraftProvider = Provider.family<String?, String>((ref, chatId) {
  return ref.watch(chatDraftStoreProvider).read(chatId);
});
