import '../../design_system/product_button.dart';
import '../../design_system/product_notice.dart';
import '../../design_system/product_switch.dart';
import 'package:flutter/material.dart';
import '../../native_client/product_client.dart';
import '../../design_system/app_theme.dart';
import '../../design_system/product_strings.dart';
import '../../design_system/product_motion.dart';
import '../../design_system/product_dialogs.dart';

class ProductSettings extends StatefulWidget {
  const ProductSettings({
    super.key,
    required this.client,
    required this.locale,
    required this.onLocaleChanged,
    required this.onSources,
    required this.onLicenses,
    this.version = '',
    this.buildRevision = '',
    this.onBack,
    this.hostRoot = false,
  });
  final ProductClient client;
  final String locale;
  final ValueChanged<String> onLocaleChanged;
  final VoidCallback onSources;
  final VoidCallback onLicenses;
  final String version;
  final String buildRevision;
  final VoidCallback? onBack;
  final bool hostRoot;
  @override
  State<ProductSettings> createState() => _ProductSettingsState();
}

class _ProductSettingsState extends State<ProductSettings> {
  ProductMap values = {};
  ProductMap capabilities = {};
  String layoutSummary = 'unavailable';
  bool synchronized = false;
  String section = 'display';
  String error = '';
  bool loading = true;
  bool busy = false;
  bool compactDetail = false;
  int _request = 0;
  final _scrolls = <String, ScrollController>{};
  ProductStrings get s =>
      ProductStrings(context, values['localeTag'] as String? ?? widget.locale);
  static const sections = ['display', 'controls', 'audio', 'game', 'about'];
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    ++_request;
    for (final c in _scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply(ProductMap result) {
    synchronized = true;
    layoutSummary = result['layoutSummary'] as String? ?? 'unavailable';
    values = Map<String, Object?>.from(result['values'] as Map);
    capabilities = Map<String, Object?>.from(
      result['capabilities'] as Map? ?? {},
    );
  }

  Future<void> _read() async {
    final request = ++_request;
    setState(() {
      loading = true;
      synchronized = false;
    });
    try {
      final result = await widget.client.call('settings');
      if (!mounted || request != _request) return;
      setState(() {
        _apply(result);
        error = '';
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(
          () => error = e is ProductFailure ? e.code : 'service_unavailable',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => loading = false);
    }
  }

  Future<void> _write(String key, Object value) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await widget.client.call('patchSetting', {
        'key': key,
        'value': value,
      });
      if (!mounted) return;
      setState(() => _apply(result));
      if (key == 'localeTag') {
        widget.onLocaleChanged(values['localeTag'] as String);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is ProductFailure ? e.code : 'storage_failed');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _sectionTitle(String key) => switch (key) {
    'display' => s.text('Display', '显示'),
    'controls' => s.text('Controls', '操作'),
    'audio' => s.text('Audio', '音频'),
    'game' => s.text('Game & language', '游戏语言'),
    _ => s.text('About', '关于'),
  };
  bool _allowed(String key, Object value) {
    final cap = capabilities['$key.$value'];
    if (cap is Map) return cap['available'] == true;
    return !((key == 'videoQualityPreset' && value == 3) ||
        (key == 'customRefreshPolicy' && (value == 4 || value == 5)) ||
        (key == 'customTemporalMode' && value == 2));
  }

  Widget _toggle(String key, String title) => ProductSwitchTile(
    key: ValueKey('setting-$key'),
    title: title,
    value: values[key] == true,
    onChanged: busy || !synchronized ? null : (value) => _write(key, value),
  );
  Widget _choice(String key, String title, Map<Object, String> choices) =>
      ListTile(
        key: ValueKey('setting-$key'),
        title: Text(title),
        subtitle: Text(choices[values[key]] ?? s.text('Unavailable', '不可用')),
        trailing: const Icon(Icons.chevron_right),
        onTap: busy || !synchronized
            ? null
            : () async {
                final result = await productDialog<Object>(
                  context,
                  SimpleDialog(
                    title: Text(title),
                    children: [
                      for (final entry in choices.entries)
                        Semantics(
                          checked: values[key] == entry.key,
                          inMutuallyExclusiveGroup: true,
                          child: ListTile(
                            title: Text(entry.value),
                            leading: Icon(
                              values[key] == entry.key
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: AppTheme.accent,
                            ),
                            subtitle: _allowed(key, entry.key)
                                ? null
                                : Text(s.error('unsupported_capability')),
                            onTap: _allowed(key, entry.key)
                                ? () => Navigator.pop(context, entry.key)
                                : null,
                          ),
                        ),
                    ],
                  ),
                );
                if (result != null && mounted) await _write(key, result);
              },
      );
  Widget _link(
    String title,
    IconData icon,
    VoidCallback action, {
    String? summary,
  }) => ListTile(
    title: Text(title),
    subtitle: summary == null ? null : Text(summary),
    leading: Icon(icon),
    trailing: const Icon(Icons.chevron_right),
    onTap: busy || !synchronized ? null : action,
  );
  Future<void> _native(String page) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.client.call('openNative', {'page': page});
      if (mounted) await _read();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ProductFailure ? e.code : 'service_unavailable',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reset() async {
    if (!await productConfirm(
          context,
          s,
          s.text('Reset controls', '重置操作设置'),
          s.text(
            'Reset control style, haptics and your saved layout?',
            '重置操作方式、触感和已保存的布局？',
          ),
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await widget.client.call('resetControls');
      if (mounted) setState(() => _apply(result));
    } catch (_) {
      // Layout and scalar settings have separate native persistence owners.
      // A failed reset may have committed one part; never claim rollback.
      try {
        final actual = await widget.client.call('settings');
        if (mounted) {
          setState(() {
            _apply(actual);
            error = 'reset_incomplete';
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            synchronized = false;
            error = 'reset_state_unavailable';
          });
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Widget> _fields() => switch (section) {
    'display' => [
      _choice('videoQualityPreset', s.text('Quality preset', '画质预设'), {
        1: s.text('Power saver', '省电'),
        2: s.text('Balanced', '均衡'),
        3: s.text('Extreme', '极致'),
        4: s.text('Custom', '自定义'),
      }),
      if (values['videoQualityPreset'] == 4) ...[
        _choice('customRefreshPolicy', s.text('Refresh policy', '刷新策略'), {
          1: s.text('Follow system', '跟随系统'),
          3: '60 Hz',
          4: '90 Hz',
          5: '120 Hz',
        }),
        _choice('customTemporalMode', s.text('Time processing', '时间处理'), {
          1: s.text('Native', '原始'),
          2: s.text('Motion interpolation', '运动插帧'),
        }),
        _choice('customSpatialMode', s.text('Image scaling', '空间处理'), {
          1: s.text('Nearest', '最近邻'),
          2: s.text('Sharp bilinear', '锐利双线性'),
          3: 'MMPX',
          4: 'ScaleFX',
        }),
        _choice('customPostEffect', s.text('Post-processing', '后处理'), {
          1: s.text('None', '无'),
          2: 'CRT',
        }),
      ],
      _choice('aspectMode', s.text('Aspect ratio', '宽高比'), {
        1: '4:3',
        2: s.text('Square pixels', '方形像素'),
        3: s.text('Integer scale', '整数缩放'),
      }),
      _toggle('adaptiveProtection', s.text('Adaptive protection', '自适应保护')),
    ],
    'controls' => [
      _choice('directionMode', s.text('Direction control', '方向操作'), {
        2: s.text('Fixed joystick', '固定摇杆'),
        1: s.text('Following joystick', '跟随摇杆'),
        3: s.text('D-pad', '十字键'),
      }),
      _link(
        s.text('Edit layout', '编辑布局'),
        Icons.gamepad_outlined,
        () => _native('layout'),
        summary: switch (layoutSummary) {
          'recommended' => s.text('Recommended layout', '推荐布局'),
          'custom' => s.text('Custom layout', '自定义布局'),
          _ => s.text('Layout unavailable', '布局不可用'),
        },
      ),
      _link(s.text('Preview haptics', '触感预览'), Icons.vibration, () async {
        try {
          await widget.client.call('previewHaptics');
        } catch (e) {
          if (mounted) {
            setState(
              () =>
                  error = e is ProductFailure ? e.code : 'service_unavailable',
            );
          }
        }
      }),
      _choice('hapticLevel', s.text('Haptic strength', '触感强度'), {
        1: s.text('Off', '关闭'),
        2: s.text('Light', '轻'),
        3: s.text('Standard', '标准'),
        4: s.text('Strong', '强'),
      }),
      _toggle('distinctAbHaptics', s.text('Distinct A/B haptics', '区分 A/B 触感')),
      _link(s.text('Reset controls', '重置操作设置'), Icons.restart_alt, _reset),
    ],
    'audio' => [
      _toggle('audioEnabled', s.text('Sound', '声音')),
      _choice('audioFocusPolicy', s.text('Audio focus', '音频焦点'), {
        1: s.text('Pause', '暂停'),
        2: s.text('Lower volume', '降低音量'),
        3: s.text('Keep playing', '继续播放'),
      }),
    ],
    'game' => [
      _choice('localeTag', s.text('Language', '语言'), {
        'system': s.text('Follow system', '跟随系统'),
        'en': s.text('English', '英文'),
        'zh-Hans': s.text('Simplified Chinese', '简体中文'),
      }),
      _toggle('autosaveEnabled', s.text('Automatic save', '自动保存')),
      _link(
        s.text('Manage sources', '管理来源'),
        Icons.folder_outlined,
        widget.onSources,
      ),
    ],
    _ => [
      ListTile(title: const Text('FlyNES'), subtitle: Text(widget.version)),
      ListTile(
        title: Text(s.text('Build revision', '构建修订')),
        subtitle: SelectableText(
          widget.buildRevision.isEmpty
              ? s.text('Unavailable', '不可用')
              : widget.buildRevision,
        ),
      ),
      _link(
        s.text('Licenses', '许可'),
        Icons.description_outlined,
        widget.onLicenses,
      ),
      ListTile(
        title: Text(s.text('Project source', '项目来源')),
        subtitle: Text(s.text('Not configured', '未配置')),
      ),
    ],
  };
  Widget _content() => Column(
    children: [
      ProductNotice(
        message: error.isNotEmpty ? s.error(error) : '',
        actionLabel: s.retry,
        onAction: error == 'reset_incomplete' ? _reset : _read,
      ),
      Expanded(
        child: loading
            ? Center(
                child: DeferredProgress(
                  label: s.text('Loading settings…', '正在读取设置…'),
                ),
              )
            : ProductFadeSwitcher(
                duration: ProductMotion.duration(context, 120),
                child: ListView(
                  key: PageStorageKey('settings-scroll-$section'),
                  controller: _scrolls.putIfAbsent(
                    section,
                    () => ScrollController(),
                  ),
                  padding: const EdgeInsets.all(16),
                  children: _fields(),
                ),
              ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final compact = bounds.maxWidth < 720;
      final nav = ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final key in sections)
            ListTile(
              key: ValueKey('section-$key'),
              selected: section == key,
              selectedTileColor: AppTheme.selected,
              title: Text(_sectionTitle(key)),
              onTap: () => setState(() {
                section = key;
                compactDetail = true;
              }),
            ),
        ],
      );
      return PopScope(
        canPop: !widget.hostRoot && (!compact || !compactDetail),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            if (compact && compactDetail) {
              setState(() => compactDetail = false);
            } else if (widget.hostRoot) {
              widget.onBack?.call();
            }
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(s.text('Settings', '设置')),
            leading: compact && compactDetail
                ? ProductBackButton(
                    label: s.text('Back', '返回'),
                    onPressed: () => setState(() => compactDetail = false),
                  )
                : widget.onBack == null
                ? null
                : ProductBackButton(
                    label: s.text('Back', '返回'),
                    onPressed: widget.onBack,
                  ),
          ),
          body: SafeArea(
            child: compact
                ? (compactDetail ? _content() : nav)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: bounds.maxWidth * .26, child: nav),
                      const VerticalDivider(width: 1),
                      Expanded(child: _content()),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
