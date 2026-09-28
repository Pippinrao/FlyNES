import 'package:flutter/material.dart';

/// A truthful bootstrap screen; no catalog or native capability is simulated.
class BootstrapPage extends StatelessWidget {
  const BootstrapPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('FlyNES')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Flutter 迁移基础工程',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text('原生服务尚未接入', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}
