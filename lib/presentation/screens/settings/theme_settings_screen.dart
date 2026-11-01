import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../data/models/app_theme_config.dart';
import '../../providers/theme_providers.dart';
import '../../theme/app_theme.dart';
import 'package:native_tavern/l10n/generated/app_localizations.dart';
import 'package:native_tavern/presentation/widgets/common/adaptive_popup_menu.dart';

/// Screen for managing app themes
class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final allThemes = ref.watch(allThemesProvider);
    final followSystem = ref.watch(themeFollowSystemProvider);
    final activeThemeId = ref.watch(activeThemeIdProvider);
    final lightThemeId = ref.watch(lightThemeIdProvider);
    final darkThemeId = ref.watch(darkThemeIdProvider);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final displayed = displayedThemeConfig(ref, platformBrightness);

    bool isSelected(AppThemeConfig theme) {
      if (!followSystem) return theme.id == activeThemeId;
      return theme.id == (theme.isDark ? darkThemeId : lightThemeId);
    }

    final builtInDark =
        allThemes.where((t) => t.isBuiltIn && t.isDark).toList();
    final builtInLight =
        allThemes.where((t) => t.isBuiltIn && !t.isDark).toList();
    final userThemes = allThemes.where((t) => !t.isBuiltIn).toList();

    Widget grid(List<AppThemeConfig> themes, {bool isCustom = false}) {
      return _buildThemeGrid(
        context,
        ref,
        themes,
        isSelected: isSelected,
        followSystem: followSystem,
        isCustom: isCustom,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.themes),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.createCustomTheme,
            onPressed: () => _showCreateThemeDialog(context, ref, displayed),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              key: const Key('theme-follow-system-switch'),
              secondary: const Icon(Icons.brightness_auto_outlined),
              title: Text(l10n.followSystemTheme),
              subtitle: Text(l10n.followSystemThemeSubtitle),
              value: followSystem,
              onChanged: (value) =>
                  _setFollowSystem(ref, value, displayed, platformBrightness),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(context, l10n.darkThemes),
          const SizedBox(height: 12),
          grid(builtInDark),
          const SizedBox(height: 24),
          _buildSectionHeader(context, l10n.lightThemes),
          const SizedBox(height: 12),
          grid(builtInLight),
          if (userThemes.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSectionHeader(context, l10n.customThemes),
            const SizedBox(height: 12),
            grid(userThemes, isCustom: true),
          ],
          const SizedBox(height: 32),
          _buildSectionHeader(context, l10n.preview),
          const SizedBox(height: 12),
          _buildThemePreview(context, displayed),
        ],
      ),
    );
  }

  Future<void> _setFollowSystem(
    WidgetRef ref,
    bool value,
    AppThemeConfig displayed,
    Brightness platformBrightness,
  ) async {
    if (value) {
      // Seed the matching slot with the current theme so nothing changes
      // visually until the system appearance flips.
      final slot =
          displayed.isDark ? darkThemeIdProvider : lightThemeIdProvider;
      await ref.read(slot.notifier).setActiveTheme(displayed.id);
    } else {
      // Keep whatever is on screen right now as the single active theme.
      await ref
          .read(activeThemeIdProvider.notifier)
          .setActiveTheme(displayed.id);
    }
    await ref.read(themeFollowSystemProvider.notifier).setFollowSystem(value);
  }

  void _selectTheme(WidgetRef ref, AppThemeConfig theme, bool followSystem) {
    if (followSystem) {
      final slot = theme.isDark ? darkThemeIdProvider : lightThemeIdProvider;
      ref.read(slot.notifier).setActiveTheme(theme.id);
    } else {
      ref.read(activeThemeIdProvider.notifier).setActiveTheme(theme.id);
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: context.tavern.accent,
            fontWeight: FontWeight.bold,
          ),
    );
  }

  Widget _buildThemeGrid(
    BuildContext context,
    WidgetRef ref,
    List<AppThemeConfig> themes, {
    required bool Function(AppThemeConfig) isSelected,
    required bool followSystem,
    bool isCustom = false,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Size cards by width so tablets get more columns instead of huge tiles.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: themes.length,
      itemBuilder: (context, index) {
        final theme = themes[index];

        return _ThemeCard(
          theme: theme,
          isActive: isSelected(theme),
          showSlotIcon: followSystem,
          isCustom: isCustom,
          onTap: () => _selectTheme(ref, theme, followSystem),
          onEdit:
              isCustom ? () => _showEditThemeDialog(context, ref, theme) : null,
          onDelete: isCustom
              ? () => _showDeleteConfirmation(context, ref, theme)
              : null,
        );
      },
    );
  }

  Widget _buildThemePreview(BuildContext context, AppThemeConfig activeTheme) {
    final l10n = AppLocalizations.of(context);
    final onAccent = TavernTheme.foregroundFor(activeTheme.accent);
    final onPrimary = TavernTheme.foregroundFor(activeTheme.primary);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: activeTheme.background,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App bar preview
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: activeTheme.surface,
              child: Row(
                children: [
                  Icon(Icons.arrow_back,
                      color: activeTheme.textPrimary, size: 20),
                  const SizedBox(width: 16),
                  Text(
                    l10n.chatPreview,
                    style: TextStyle(
                      color: activeTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.more_vert,
                      color: activeTheme.textPrimary, size: 20),
                ],
              ),
            ),
            // Chat preview
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Assistant message
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: activeTheme.card,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                      border: Border.all(
                        color: activeTheme.divider.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      l10n.sampleMessage1,
                      style: TextStyle(
                          color: activeTheme.textPrimary, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // User message
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: activeTheme.accent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(14),
                          topRight: Radius.circular(4),
                          bottomLeft: Radius.circular(14),
                          bottomRight: Radius.circular(14),
                        ),
                      ),
                      child: Text(
                        l10n.sampleMessage2,
                        style: TextStyle(color: onAccent, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Input preview
            Container(
              padding: const EdgeInsets.all(12),
              color: activeTheme.surface,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: activeTheme.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: activeTheme.divider),
                      ),
                      child: Text(
                        l10n.typeMessage,
                        style: TextStyle(
                            color: activeTheme.textSecondary, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: activeTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.send, color: onPrimary, size: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateThemeDialog(
    BuildContext context,
    WidgetRef ref,
    AppThemeConfig baseTheme,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => _ThemeEditorDialog(
        // Start from the theme on screen rather than always Default Dark.
        baseTheme: baseTheme,
        onSave: (AppThemeConfig theme) {
          ref.read(customThemesProvider.notifier).addTheme(theme);
          _selectTheme(ref, theme, ref.read(themeFollowSystemProvider));
        },
      ),
    );
  }

  void _showEditThemeDialog(
      BuildContext context, WidgetRef ref, AppThemeConfig theme) {
    showDialog<void>(
      context: context,
      builder: (context) => _ThemeEditorDialog(
        theme: theme,
        onSave: (AppThemeConfig updatedTheme) {
          ref.read(customThemesProvider.notifier).updateTheme(updatedTheme);
        },
      ),
    );
  }

  void _showDeleteConfirmation(
      BuildContext context, WidgetRef ref, AppThemeConfig theme) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteTheme),
        content: Text(l10n.deleteThemeConfirmation(theme.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              // Move any slot that pointed at this theme back to a default.
              final slots =
                  <StateNotifierProvider<ActiveThemeIdNotifier, String>,
                      String>{
                activeThemeIdProvider: BuiltInThemes.defaultDark.id,
                darkThemeIdProvider: BuiltInThemes.defaultDark.id,
                lightThemeIdProvider: BuiltInThemes.defaultLight.id,
              };
              slots.forEach((slot, fallbackId) {
                if (ref.read(slot) == theme.id) {
                  ref.read(slot.notifier).setActiveTheme(fallbackId);
                }
              });
              ref.read(customThemesProvider.notifier).deleteTheme(theme.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppThemeConfig theme;
  final bool isActive;
  final bool showSlotIcon;
  final bool isCustom;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ThemeCard({
    required this.theme,
    required this.isActive,
    required this.isCustom,
    required this.onTap,
    this.showSlotIcon = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.tavern;
    final selectedIcon = showSlotIcon
        ? (theme.isDark ? Icons.dark_mode : Icons.light_mode)
        : Icons.check_circle;

    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isActive
            ? BorderSide(color: colors.accent, width: 2.5)
            : BorderSide(color: colors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            // Color preview
            Expanded(
              child: Container(
                color: theme.background,
                child: Column(
                  children: [
                    // Top bar
                    Container(
                      height: 20,
                      color: theme.surface,
                    ),
                    // Content area
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 16,
                              width: 40,
                              decoration: BoxDecoration(
                                color: theme.card,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const Spacer(),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                height: 16,
                                width: 30,
                                decoration: BoxDecoration(
                                  color: theme.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Bottom bar
                    Container(
                      height: 16,
                      color: theme.card,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: theme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Name
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 4, 6),
              child: Row(
                children: [
                  if (isActive) ...[
                    Icon(selectedIcon, size: 14, color: colors.accent),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      theme.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Custom themes stay editable even while in use.
                  if (isCustom)
                    SizedBox(
                      width: 24,
                      height: 20,
                      child: AdaptivePopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        iconSize: 14,
                        icon: const Icon(Icons.more_vert, size: 14),
                        itemBuilder: (context) => [
                          PopupMenuItem(value: 'edit', child: Text(l10n.edit)),
                          PopupMenuItem(
                              value: 'delete', child: Text(l10n.delete)),
                        ],
                        onSelected: (value) {
                          if (value == 'edit') onEdit?.call();
                          if (value == 'delete') onDelete?.call();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeEditorDialog extends StatefulWidget {
  /// Theme being edited; `null` when creating a new one.
  final AppThemeConfig? theme;

  /// Colors to start from when creating a new theme.
  final AppThemeConfig? baseTheme;
  final void Function(AppThemeConfig) onSave;

  const _ThemeEditorDialog({
    this.theme,
    this.baseTheme,
    required this.onSave,
  });

  @override
  State<_ThemeEditorDialog> createState() => _ThemeEditorDialogState();
}

class _ThemeEditorDialogState extends State<_ThemeEditorDialog> {
  late TextEditingController _nameController;
  late bool _isDark;
  late String _primaryColor;
  late String _accentColor;
  late String _backgroundColor;
  late String _surfaceColor;
  late String _cardColor;
  bool _initializedDefaultName = false;

  @override
  void initState() {
    super.initState();
    final theme = widget.theme ?? widget.baseTheme ?? BuiltInThemes.defaultDark;
    _nameController = TextEditingController(text: widget.theme?.name ?? '');
    _isDark = theme.isDark;
    _primaryColor = theme.primaryColor;
    _accentColor = theme.accentColor;
    _backgroundColor = theme.backgroundColor;
    _surfaceColor = theme.surfaceColor;
    _cardColor = theme.cardColor;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.theme == null && !_initializedDefaultName) {
      _nameController.text = AppLocalizations.of(context).myTheme;
      _initializedDefaultName = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.theme != null;
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(isEditing ? l10n.editTheme : l10n.createTheme),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.themeName,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(l10n.darkMode),
              value: _isDark,
              onChanged: (value) => setState(() => _isDark = value),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            _ColorPickerTile(
              label: l10n.primaryColor,
              color: _primaryColor,
              onChanged: (color) => setState(() => _primaryColor = color),
            ),
            _ColorPickerTile(
              label: l10n.accentColor,
              color: _accentColor,
              onChanged: (color) => setState(() => _accentColor = color),
            ),
            _ColorPickerTile(
              label: l10n.background,
              color: _backgroundColor,
              onChanged: (color) => setState(() => _backgroundColor = color),
            ),
            _ColorPickerTile(
              label: l10n.surface,
              color: _surfaceColor,
              onChanged: (color) => setState(() => _surfaceColor = color),
            ),
            _ColorPickerTile(
              label: l10n.card,
              color: _cardColor,
              onChanged: (color) => setState(() => _cardColor = color),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            // Keep the source theme's text/divider colors when the brightness
            // is unchanged; otherwise use readable defaults for the new mode.
            final source = widget.theme ?? widget.baseTheme;
            final keepText = source != null && source.isDark == _isDark;
            final name = _nameController.text.trim();
            final theme = AppThemeConfig(
              id: widget.theme?.id ?? const Uuid().v4(),
              name: name.isEmpty ? l10n.myTheme : name,
              isDark: _isDark,
              primaryColor: _primaryColor,
              accentColor: _accentColor,
              backgroundColor: _backgroundColor,
              surfaceColor: _surfaceColor,
              cardColor: _cardColor,
              textPrimaryColor: keepText
                  ? source.textPrimaryColor
                  : (_isDark ? '#FFFFFF' : '#171717'),
              textSecondaryColor: keepText
                  ? source.textSecondaryColor
                  : (_isDark ? '#A3A3A3' : '#737373'),
              dividerColor: keepText
                  ? source.dividerColor
                  : (_isDark ? '#404040' : '#E5E5E5'),
              isBuiltIn: false,
            );
            widget.onSave(theme);
            Navigator.pop(context);
          },
          child: Text(isEditing ? l10n.save : l10n.create),
        ),
      ],
    );
  }
}

class _ColorPickerTile extends StatelessWidget {
  final String label;
  final String color;
  final void Function(String) onChanged;

  const _ColorPickerTile({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label),
          const Spacer(),
          GestureDetector(
            onTap: () => _showColorPicker(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppThemeConfig.hexToColor(color),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showColorPicker(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _HexColorDialog(label: label, initial: color),
    );
    if (picked != null) onChanged(picked);
  }
}

/// Hex color entry with swatches; Apply is only enabled for valid colors.
class _HexColorDialog extends StatefulWidget {
  const _HexColorDialog({required this.label, required this.initial});

  final String label;
  final String initial;

  @override
  State<_HexColorDialog> createState() => _HexColorDialogState();
}

class _HexColorDialogState extends State<_HexColorDialog> {
  static const _swatches = [
    '#6366F1',
    '#8B5CF6',
    '#EC4899',
    '#EF4444',
    '#F97316',
    '#EAB308',
    '#22C55E',
    '#06B6D4',
    '#3B82F6',
    '#000000',
    '#1A1A1A',
    '#FFFFFF',
  ];

  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color? get _parsed => AppThemeConfig.tryParseHex(_controller.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parsed = _parsed;

    return AlertDialog(
      title: Text(l10n.selectThemeColor(widget.label)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.hexColor,
              hintText: '#RRGGBB',
              errorText: parsed == null ? '#RRGGBB' : null,
              border: const OutlineInputBorder(),
              suffixIcon: Padding(
                padding: const EdgeInsets.all(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: parsed ?? Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: const SizedBox.square(dimension: 24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final swatch in _swatches)
                GestureDetector(
                  onTap: () => setState(() => _controller.text = swatch),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppThemeConfig.hexToColor(swatch),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: parsed == null
              ? null
              : () => Navigator.pop(context, AppThemeConfig.colorToHex(parsed)),
          child: Text(l10n.apply),
        ),
      ],
    );
  }
}
