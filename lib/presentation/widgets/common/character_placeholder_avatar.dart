import 'package:flutter/material.dart';

/// Visual identity for characters without an avatar image: built-in
/// assistants keep their icon and brand color, everyone else gets a stable
/// color derived from their name plus their initial.
class CharacterPlaceholderStyle {
  const CharacterPlaceholderStyle._(this.color, this.icon, this.initial);

  final Color color;

  /// Icon for built-in assistants; `null` means show [initial].
  final IconData? icon;
  final String initial;

  static const _builtIns = <String, (Color, IconData)>{
    'builtin_coding_assistant': (Color(0xFF2196F3), Icons.code),
    'builtin_image_gen_assistant': (Color(0xFFE91E63), Icons.image),
    'builtin_xiaohongshu_copywriter': (Color(0xFFFF5722), Icons.edit_note),
  };

  factory CharacterPlaceholderStyle.of({
    required String id,
    required String name,
  }) {
    final trimmed = name.trim();
    final initial =
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    final builtIn = _builtIns[id];
    if (builtIn != null) {
      return CharacterPlaceholderStyle._(builtIn.$1, builtIn.$2, initial);
    }
    return CharacterPlaceholderStyle._(
      colorFor(trimmed.isEmpty ? id : trimmed),
      null,
      initial,
    );
  }

  /// A deterministic, readable-under-white-text color for [seed].
  static Color colorFor(String seed) {
    // FNV-1a keeps the color stable across launches and platforms.
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.42, 0.40).toColor();
  }
}

/// Filled placeholder (square tile or circle) showing a character's initial
/// or built-in icon on their identity color.
class CharacterPlaceholderAvatar extends StatelessWidget {
  const CharacterPlaceholderAvatar({
    super.key,
    required this.id,
    required this.name,
    this.radius,
    this.glyphSize = 40,
  });

  final String id;
  final String name;

  /// When set, renders a circle of this radius; otherwise fills its parent.
  final double? radius;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    final style = CharacterPlaceholderStyle.of(id: id, name: name);
    final glyph = style.icon != null
        ? Icon(style.icon, size: glyphSize, color: Colors.white)
        : Text(
            style.initial,
            style: TextStyle(
              color: Colors.white,
              fontSize: glyphSize,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          );

    final decoration = BoxDecoration(
      shape: radius != null ? BoxShape.circle : BoxShape.rectangle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(style.color, Colors.white, 0.12)!,
          Color.lerp(style.color, Colors.black, 0.18)!,
        ],
      ),
    );

    final child = DecoratedBox(
      decoration: decoration,
      child: Center(child: glyph),
    );
    if (radius == null) return child;
    return SizedBox.square(dimension: radius! * 2, child: child);
  }
}
