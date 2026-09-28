import 'package:flutter/material.dart';

import 'app/flynes_app.dart';
import 'design_system/app_theme.dart';
import 'features/foundation/texture_probe_page.dart';

void main() => runApp(const FlynesApp());

@pragma('vm:entry-point')
void textureProbeMain() =>
    runApp(MaterialApp(theme: AppTheme.dark(), home: const TextureProbePage()));
