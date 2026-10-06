/// 淘宝原始返回采集（P11-a）
///
/// 设置 → 同步诊断（仅调试版）里打开开关后，淘宝连接器拿到的接口响应先脱敏，再存到
/// App 缓存目录 `diag/taobao/<接口>_<序号>.json`（getApplicationCacheDirectory，不进系统备份），
/// 每个接口只保留最近 20 份；诊断页可一键打成 zip 用系统分享导出，也可一键清空。
///
/// 约束：
/// - 开关关闭时 [TaobaoRawCapture.capture] 只做一次布尔判断就返回，不落盘；
/// - 关闭开关时自动清空已采集文件；导出用的临时 zip 分享完即删；
/// - 采集过程任何异常都只记日志，绝不抛给同步流程；
/// - 只存响应体，不存 Cookie 和请求头。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/sanitizer/diag_sanitizer.dart';

/// 采集的接口（同时作为文件名前缀）
class TaobaoDiagEndpoint {
  TaobaoDiagEndpoint._();

  /// 订单列表 mtop.taobao.order.queryboughtlistv2
  static const orderList = 'queryboughtlistv2';

  /// 物流详情 SSR 页（logisticsV2/h5-detail）里截出的 JSON
  static const ssrDetail = 'logisticsV2_h5detail';

  /// 物流详情 SSR 页找不到数据标记时（页面改版 / 跳登录页）的页面片段
  static const ssrNoMarker = 'ssr_detail_nomarker';

  /// 驿站多包裹列表 mtop.cainiao.pickup.plus.queryMultiStaPackages4Xy
  static const stationList = 'queryMultiStaPackages4Xy';

  /// 按运单号查询 mtop.cnwireless.cnlogisticdetailservice.wapquerylogisticpackagebymailno
  static const byMailNo = 'wapquerylogisticpackagebymailno';

  /// 菜鸟驿站 WebView 网络钩子抓到的响应（附带采集）
  static const cainiaoHook = 'cainiao_webview_hook';
}

/// 诊断文件目录读写（纯 dart:io，便于单测）
class DiagFileStore {
  final Directory dir;
  final int maxPerEndpoint;

  DiagFileStore(this.dir, {this.maxPerEndpoint = 20});

  /// 写入 `<endpoint>_<序号>.json`，序号在该接口已有文件的最大值上加 1，然后清理超出上限的旧文件
  Future<File> write(String endpoint, String content) async {
    await dir.create(recursive: true);
    final existing = _filesOf(endpoint);
    final nextSeq = existing.isEmpty ? 1 : existing.last.key + 1;
    final file = File('${dir.path}/${endpoint}_${nextSeq.toString().padLeft(4, '0')}.json');
    await file.writeAsString(content, flush: true);
    existing.add(MapEntry(nextSeq, file));
    final overflow = existing.length - maxPerEndpoint;
    for (var i = 0; i < overflow; i++) {
      try {
        await existing[i].value.delete();
      } catch (_) {}
    }
    return file;
  }

  /// 某接口的文件，按序号升序
  List<MapEntry<int, File>> _filesOf(String endpoint) {
    if (!dir.existsSync()) return [];
    final reg = RegExp('^${RegExp.escape(endpoint)}_(\\d+)\\.json\$');
    final result = <MapEntry<int, File>>[];
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      final m = reg.firstMatch(e.uri.pathSegments.last);
      if (m != null) result.add(MapEntry(int.parse(m.group(1)!), e));
    }
    result.sort((a, b) => a.key.compareTo(b.key));
    return result;
  }

  /// 删除目录下全部采集文件（目录本身保留）；返回删除的文件数
  Future<int> clear() async {
    if (!dir.existsSync()) return 0;
    var n = 0;
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      try {
        await e.delete();
        n++;
      } catch (_) {}
    }
    return n;
  }

  List<File> listFiles() {
    if (!dir.existsSync()) return [];
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// 把目录下全部 json 打成 zip（条目放在 `taobao/` 下）
  static Uint8List zipDirectory(String dirPath) {
    final archive = Archive();
    final d = Directory(dirPath);
    if (d.existsSync()) {
      final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        archive.addFile(ArchiveFile.bytes('taobao/${f.uri.pathSegments.last}', f.readAsBytesSync()));
      }
    }
    return ZipEncoder().encodeBytes(archive);
  }
}

class TaobaoRawCapture {
  TaobaoRawCapture._();

  static final TaobaoRawCapture instance = TaobaoRawCapture._();

  static const String _boxName = 'diag_settings';
  static const String _enabledKey = 'taobao_raw_capture_enabled';

  /// null 表示还没从 Hive 读过
  bool? _enabled;
  Future<void> _queue = Future.value();
  DiagFileStore? _store;

  Future<Box> _openBox() async =>
      Hive.isBoxOpen(_boxName) ? Hive.box(_boxName) : await Hive.openBox(_boxName);

  /// 读取开关状态（只在第一次读 Hive，之后用缓存）
  Future<bool> loadEnabled() async {
    final cached = _enabled;
    if (cached != null) return cached;
    try {
      final box = await _openBox();
      _enabled = box.get(_enabledKey, defaultValue: false) == true;
    } catch (e) {
      debugPrint('[TaobaoRawCapture] load flag failed: $e');
      _enabled = false;
    }
    return _enabled!;
  }

  /// 关闭时会等正在写的文件落盘后清空已采集文件
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final box = await _openBox();
    await box.put(_enabledKey, value);
    if (!value) await clearAll();
  }

  /// 采集文件放缓存目录（不进 iCloud / Android 自动备份）
  Future<DiagFileStore> store() async {
    final existing = _store;
    if (existing != null) return existing;
    final base = await getApplicationCacheDirectory();
    return _store = DiagFileStore(Directory('${base.path}/diag/taobao'));
  }

  /// 清空已采集文件（等队列里正在写的先写完）；顺带删掉早期版本放在 Application Support 下的旧目录
  Future<int> clearAll() async {
    try {
      await _queue;
    } catch (_) {}
    var n = 0;
    try {
      n = await (await store()).clear();
    } catch (e) {
      debugPrint('[TaobaoRawCapture] clear failed: $e');
    }
    try {
      final legacy = Directory('${(await getApplicationSupportDirectory()).path}/diag/taobao');
      if (legacy.existsSync()) await legacy.delete(recursive: true);
    } catch (_) {}
    return n;
  }

  /// 同步流程里拿到响应后调用；不 await、不抛异常，开关关闭时立即返回。
  void capture(String endpoint, String? raw) {
    if (_enabled == false || raw == null || raw.isEmpty) return;
    _enqueue(endpoint, () => compute(DiagSanitizer.sanitizeRaw, raw));
  }

  /// SSR 物流详情页找不到数据标记时调用，存脱敏后的 url/title/页面片段。
  void captureSsrNoMarker({required String url, required String html, int? statusCode}) {
    if (_enabled == false) return;
    // 只把前 256KB 送进后台 isolate，title 和前 4KB 足够定位
    final head = html.length > 262144 ? html.substring(0, 262144) : html;
    final length = html.length;
    _enqueue(TaobaoDiagEndpoint.ssrNoMarker,
        () => compute(_ssrNoMarkerJson, [url, head, '$length', '${statusCode ?? ''}']));
  }

  void _enqueue(String endpoint, Future<String> Function() produce) {
    _queue = _queue.then((_) => _doCapture(endpoint, produce)).catchError((Object e) {
      debugPrint('[TaobaoRawCapture] $endpoint capture failed: $e');
    });
  }

  Future<void> _doCapture(String endpoint, Future<String> Function() produce) async {
    try {
      if (!await loadEnabled()) return;
      final sanitized = await produce();
      final s = await store();
      final file = await s.write(endpoint, sanitized);
      debugPrint('[TaobaoRawCapture] saved ${file.uri.pathSegments.last} (${sanitized.length} chars)');
    } catch (e) {
      debugPrint('[TaobaoRawCapture] $endpoint capture failed: $e');
    }
  }

  /// 当前已采集的文件数
  Future<int> fileCount() async {
    try {
      return (await store()).listFiles().length;
    } catch (_) {
      return 0;
    }
  }

  /// 打包 diag/taobao 为 zip 并调起系统分享；没有文件时返回 false
  Future<bool> exportAndShare() async {
    await _queue; // 等正在写的文件落盘
    final s = await store();
    if (s.listFiles().isEmpty) return false;
    final bytes = await compute(DiagFileStore.zipDirectory, s.dir.path);
    final tmp = await getTemporaryDirectory();
    // 专用子目录：每次导出前清掉上次异常退出留下的 zip
    final exportDir = Directory('${tmp.path}/diag_export');
    try {
      if (exportDir.existsSync()) await exportDir.delete(recursive: true);
    } catch (_) {}
    await exportDir.create(recursive: true);
    final ts = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name =
        'parcly_taobao_diag_${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}${two(ts.second)}.zip';
    final zip = File('${exportDir.path}/$name');
    try {
      await zip.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(zip.path, mimeType: 'application/zip')],
        subject: '取件助手 淘宝原始返回（已脱敏）',
      ));
    } finally {
      // 分享面板关闭后即删（share_plus 在 Android 上会先把文件拷到自己的共享目录）
      try {
        if (zip.existsSync()) await zip.delete();
      } catch (_) {}
    }
    return true;
  }
}

/// 后台 isolate 里生成 ssr_detail_nomarker 文件内容；args = [url, html, 原始长度, 状态码]
String _ssrNoMarkerJson(List<String> args) {
  final page = DiagSanitizer.sanitizeHtmlPage(
    url: args[0],
    html: args[1],
    statusCode: int.tryParse(args[3]),
  );
  page['length'] = int.tryParse(args[2]) ?? page['length'];
  return const JsonEncoder.withIndent('  ').convert(page);
}
