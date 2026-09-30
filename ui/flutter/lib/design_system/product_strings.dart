import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class ProductStrings {
  ProductStrings(BuildContext context, String locale)
    : _pseudo =
          kDebugMode &&
          locale == 'system' &&
          Localizations.localeOf(context) == const Locale('en', 'XA'),
      chinese =
          locale == 'zh-CN' ||
          locale == 'zh-Hans' ||
          (locale == 'system' &&
              Localizations.localeOf(context).languageCode == 'zh');
  final bool chinese;
  final bool _pseudo;

  // Android's standard pseudo locale is observation-only: native preferences
  // remain "system" and release builds retain ordinary English/Chinese text.
  String text(String en, String zh) {
    if (chinese) return zh;
    if (!_pseudo || en.isEmpty) return en;
    const plain = 'AEIOUaeiou';
    const accents = 'ÁÉÍÓÚáéíóú';
    final accented = en.split('').map((character) {
      final index = plain.indexOf(character);
      return index < 0 ? character : accents[index];
    }).join();
    final padding = List.filled((en.length * .3).ceil(), '~').join();
    return '[$accented $padding]';
  }

  String category(String key) => switch (key) {
    'recent' => text('Recent', '最近'),
    'favorites' => text('Favorites', '收藏'),
    'builtin' => text('Built-in', '内置'),
    _ => text('All', '全部'),
  };
  String error(String code) => switch (code) {
    'folder_selection_unsupported' => text(
      'Folder selection is unavailable on this system. Add files or ZIP archives instead.',
      '当前系统不支持选择文件夹，请添加文件或 ZIP 压缩包。',
    ),
    'history_unavailable' => text(
      'Progress could not be read. Retry to continue.',
      '无法读取进度，请重试。',
    ),
    'snapshot_expired' => text(
      'The library changed. Reload the list.',
      '游戏库已更新，请重新加载。',
    ),
    'reset_incomplete' => text(
      'Reset did not finish. Current saved values are shown; retry to finish resetting.',
      '重置尚未完成。当前显示已保存的值，请重试完成重置。',
    ),
    'reset_state_unavailable' => text(
      'Reset did not finish and current values could not be read. Reload before editing.',
      '重置尚未完成，且无法读取当前值。请重新加载后再修改。',
    ),
    'storage_failed' => text(
      'Changes could not be saved. Your previous value is retained.',
      '未能保存修改，已保留原值。',
    ),
    'source_unavailable' => text(
      'This source is unavailable. Check its access in Sources.',
      '来源不可用，请在来源管理中检查授权。',
    ),
    'source_cleanup_failed' => text(
      'Library entries were removed, but source cleanup could not finish. Reload and retry removal.',
      '游戏条目已移除，但来源清理尚未完成。请刷新后重试移除。',
    ),
    'source_reauthorize_cleanup_failed' => text(
      'Source access could not be updated completely. Reload Sources and retry authorization.',
      '来源授权更新尚未完成。请刷新来源后重试授权。',
    ),
    'scan_conflict' => text(
      'The source changed during scanning. Scan it again.',
      '扫描期间来源发生变化，请重新扫描。',
    ),
    'scan_committed_refresh_failed' => text(
      'The scan was saved, but the library could not finish refreshing. Reload Sources.',
      '扫描结果已保存，但游戏库刷新尚未完成。请刷新来源。',
    ),
    'scan_partial' => text(
      'Some files could not be imported. Check the source and scan again.',
      '部分文件未能导入，请检查来源后重新扫描。',
    ),
    'permission_required' => text(
      'Access to this source has expired. Authorize it again.',
      '此来源的访问权限已失效，请重新授权。',
    ),
    'unsupported_capability' => text(
      'This option requires verified device support.',
      '此选项需要经过验证的设备支持。',
    ),
    'native_busy' => text('An operation is already in progress.', '已有操作正在进行。'),
    'launch_failed' => text(
      'The game could not be started. Please retry.',
      '未能启动游戏，请重试。',
    ),
    _ => text(
      'This operation could not be completed. Please retry.',
      '操作未能完成，请重试。',
    ),
  };
  String get retry => text('Retry', '重试');
}
