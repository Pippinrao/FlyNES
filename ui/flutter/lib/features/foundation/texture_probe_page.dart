import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// G1 media experiment; the native host owns the core and audio clock.
class TextureProbePage extends StatefulWidget {
  const TextureProbePage({super.key});

  @override
  State<TextureProbePage> createState() => _TextureProbePageState();
}

class _TextureProbePageState extends State<TextureProbePage>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('flynes/foundation_texture');
  static int nextOwner = 0;
  final owner = 'texture-page-${++nextOwner}';
  final pointers = <int, int>{};
  int? texture;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(toggle());
  }

  Future<void> command(String method, [Map<String, Object>? arguments]) async {
    try {
      await channel.invokeMethod<void>(method, {'owner': owner, ...?arguments});
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    }
  }

  void clearInput() {
    pointers.clear();
    unawaited(command('input', {'buttons': 0}));
  }

  Future<void> toggle() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (texture == null) {
        final id = await channel.invokeMethod<int>('attach', {'owner': owner});
        if (!mounted) {
          await command('detach');
          return;
        }
        if (id == null || id < 0) {
          throw StateError('Native texture unavailable');
        }
        setState(() => texture = id);
      } else {
        clearInput();
        await channel.invokeMethod<void>('detach', {'owner': owner});
        if (mounted) setState(() => texture = null);
      }
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (!active) clearInput();
    unawaited(command('active', {'active': active}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clearInput();
    unawaited(command('detach'));
    super.dispose();
  }

  Widget pad(String name, int bit) => Semantics(
    identifier: 'texture-pad-$name',
    label: name,
    excludeSemantics: true,
    button: true,
    child: Listener(
      key: ValueKey('pad-$name'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (texture == null || busy) return;
        pointers[event.pointer] = bit;
        sendInput();
      },
      onPointerUp: (event) {
        pointers.remove(event.pointer);
        sendInput();
      },
      onPointerCancel: (event) {
        pointers.remove(event.pointer);
        sendInput();
      },
      child: SizedBox(width: 64, height: 56, child: Center(child: Text(name))),
    ),
  );

  void sendInput() => unawaited(
    command('input', {
      'buttons': pointers.values.fold<int>(0, (mask, bit) => mask | bit),
    }),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 256 / 240,
                child: texture == null
                    ? const Center(child: Text('Texture detached'))
                    : Texture(textureId: texture!),
              ),
            ),
          ),
          if (error != null) Text(error!, maxLines: 2),
          Wrap(
            children: [
              pad('Left', 64),
              pad('Right', 128),
              pad('Up', 16),
              pad('Down', 32),
              pad('Select', 4),
              pad('Start', 8),
              pad('B', 2),
              pad('A', 1),
              TextButton(
                key: const ValueKey('texture-toggle'),
                onPressed: busy ? null : toggle,
                child: Text(texture == null ? 'Attach' : 'Detach'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
