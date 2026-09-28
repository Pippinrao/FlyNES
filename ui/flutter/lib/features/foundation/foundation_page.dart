import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/app_theme.dart';
import '../../native_client/foundation_client.dart';
import '../../native_client/foundation_controller.dart';

/// A page owns the controller it creates, but only borrows an injected one.
/// Neither ownership path owns the native game session.
class FoundationPage extends StatefulWidget {
  const FoundationPage({super.key, this.controller, this.client})
    : assert(controller == null || client == null);

  final FoundationController? controller;
  final FoundationClient? client;

  @override
  State<FoundationPage> createState() => _FoundationPageState();
}

class _FoundationPageState extends State<FoundationPage>
    with WidgetsBindingObserver {
  late final FoundationController controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller =
        widget.controller ??
        FoundationController(widget.client ?? ChannelFoundationClient());
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(controller.refresh());
  }

  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ownsController) controller.dispose();
    super.dispose();
  }

  bool get chinese =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh';
  String label(String zh, String en) => chinese ? zh : en;

  String message(String value) {
    if (chinese) return value;
    return switch (value) {
      '游戏库暂时不可用' => 'Game library unavailable',
      '游戏来源不可用' => 'Game source unavailable',
      '暂时无法读取进度' => 'Progress unavailable',
      '当前无法启动游戏' => 'Unable to start this game',
      '暂时无法打开页面' => 'Unable to open this page',
      _ => value,
    };
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Semantics(
      identifier: 'foundation-library',
      container: true,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'FlyNES',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    _nativeButton(
                      'sources',
                      Icons.folder_open,
                      label('游戏来源', 'Game sources'),
                    ),
                    _nativeButton(
                      'nearby',
                      Icons.sports_esports_outlined,
                      label('附近联机', 'Nearby play'),
                    ),
                    _nativeButton(
                      'settings',
                      Icons.settings_outlined,
                      label('设置', 'Settings'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(child: _body(context)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _nativeButton(String page, IconData icon, String tooltip) =>
      IconButton(
        key: ValueKey('native-$page'),
        tooltip: tooltip,
        onPressed: controller.launching
            ? null
            : () => controller.openNative(page),
        icon: Icon(icon),
      );

  Widget _body(BuildContext context) {
    final games = controller.snapshot?.games ?? <CatalogGame>[];
    if (games.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.loading) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  controller.loading
                      ? label('正在读取游戏…', 'Loading games…')
                      : controller.error != null
                      ? label('游戏库暂时不可用', 'Game library unavailable')
                      : label('还没有游戏', 'No games yet'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (!controller.loading) ...[
                const SizedBox(height: 12),
                if (controller.error != null && controller.error != '游戏库暂时不可用')
                  Text(message(controller.error!), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => controller.refresh(),
                  child: Text(label('重新读取', 'Refresh')),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final large = MediaQuery.textScalerOf(context).scale(16) >= 28.8;
    return LayoutBuilder(
      builder: (context, constraints) {
        final detail = _detail(context, large);
        final catalog = GridView.builder(
          key: const ValueKey('game-catalog'),
          scrollDirection: Axis.horizontal,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: large ? 1 : 2,
            mainAxisExtent: large ? 240 : 180,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: games.length,
          itemBuilder: (context, index) => _card(context, games[index], large),
        );
        if (constraints.maxWidth >= constraints.maxHeight) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: detail),
              const SizedBox(width: 16),
              Expanded(flex: 7, child: catalog),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: detail),
            const SizedBox(height: 16),
            Expanded(child: catalog),
          ],
        );
      },
    );
  }

  Widget _detail(BuildContext context, bool large) {
    final game = controller.selected;
    final resume = controller.resume;
    final enabled =
        !controller.loading &&
        !controller.launching &&
        game != null &&
        game.available &&
        (resume.state == ResumeState.available ||
            resume.state == ResumeState.none);
    final action = controller.launching
        ? label('正在打开…', 'Opening…')
        : resume.state == ResumeState.querying
        ? label('正在读取…', 'Loading…')
        : resume.state == ResumeState.available
        ? label('继续', 'Continue')
        : label('开始', 'Start');
    return Column(
      key: const ValueKey('game-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label('游戏中心', 'Game center'),
                  style: const TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                if (game != null) ...[
                  Text(
                    game.title(chinese),
                    maxLines: large ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (game.title(!chinese) != game.title(chinese)) ...[
                    const SizedBox(height: 8),
                    Text(
                      game.title(!chinese),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                  ],
                ],
                if (resume.reason.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(message(resume.reason)),
                  ),
                ],
                if (controller.error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      message(controller.error!),
                      style: const TextStyle(color: AppTheme.accent),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: large ? 88 : 56,
          child: Semantics(
            identifier: 'launch-selected',
            child: FilledButton(
              key: const ValueKey('primary-play'),
              onPressed: enabled ? () => controller.launch() : null,
              child: Text(
                action,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, CatalogGame game, bool large) {
    final selected = controller.selected?.canonicalId == game.canonicalId;
    return Semantics(
      identifier: 'game-card-${game.canonicalId}',
      selected: selected,
      button: true,
      label: game.title(chinese),
      child: Material(
        color: selected ? AppTheme.selected : AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? AppTheme.accent : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('game-${game.canonicalId}'),
          onTap: controller.launching
              ? null
              : () => controller.select(game.canonicalId),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                game.title(chinese),
                maxLines: large ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: game.available ? AppTheme.text : AppTheme.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
