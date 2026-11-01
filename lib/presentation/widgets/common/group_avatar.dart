import 'package:flutter/material.dart';
import 'package:native_tavern/data/models/character.dart';
import 'package:native_tavern/presentation/theme/app_theme.dart';
import 'package:native_tavern/presentation/widgets/common/character_avatar_image.dart';

/// A compact group avatar assembled from the first four group members.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.characters,
    this.size = 56,
  });

  final List<Character?> characters;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visibleCharacters = characters.take(4).toList(growable: false);
    if (visibleCharacters.isEmpty) {
      return _emptyAvatar(context);
    }

    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.16),
        child: ColoredBox(
          color: context.tavern.divider,
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (var index = 0; index < visibleCharacters.length; index++)
                Positioned.fromRect(
                  rect: _memberRect(index, visibleCharacters.length),
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: _memberAvatar(context, visibleCharacters[index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Rect _memberRect(int index, int count) {
    if (count == 1) return Rect.fromLTWH(0, 0, size, size);
    if (count == 2) {
      return Rect.fromLTWH(index * size / 2, 0, size / 2, size);
    }
    if (count == 3) {
      if (index == 0) return Rect.fromLTWH(0, 0, size / 2, size);
      return Rect.fromLTWH(
        size / 2,
        (index - 1) * size / 2,
        size / 2,
        size / 2,
      );
    }
    return Rect.fromLTWH(
      (index % 2) * size / 2,
      (index ~/ 2) * size / 2,
      size / 2,
      size / 2,
    );
  }

  Widget _memberAvatar(BuildContext context, Character? character) {
    final avatarPath = character?.assets?.avatarPath;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      return CharacterAvatarImage(
        imagePath: avatarPath,
        errorBuilder: (_, __, ___) => _fallbackMember(context, character),
      );
    }
    return _fallbackMember(context, character);
  }

  Widget _fallbackMember(BuildContext context, Character? character) {
    final name = character?.name.trim() ?? '';
    return ColoredBox(
      color: context.tavern.primary.withValues(alpha: 0.24),
      child: Center(
        child: Text(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: TextStyle(
            color: context.tavern.textPrimary,
            fontSize: size * 0.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _emptyAvatar(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.tavern.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(size * 0.16),
      ),
      child: Icon(
        Icons.groups,
        size: size * 0.5,
        color: context.tavern.primary,
      ),
    );
  }
}
