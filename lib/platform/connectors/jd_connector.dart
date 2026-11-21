/// 京东商城真实连接器 - 采用双引擎（接口拦截 + DOM提取），精准抓取「待收货」在途快递，过滤外卖/秒送/已完成
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/engine/logistics_status_engine.dart';
import '../../core/models/package.dart';
import '../../core/models/package_status.dart';
import '../../core/parser/trace_time.dart';
import '../../core/sanitizer/goods_name_cleaner.dart';
import '../../core/utils/image_url.dart';
import '../storage/platform_auth_store.dart';
import '../webview/webview_release.dart';
import 'jd_delivery_filter.dart';
import 'jd_sync_network.dart';
import 'jd_trace_parser.dart';
import 'platform_connector.dart';
import 'package:pickup_app/core/parser/pickup_point_name.dart';
import 'package:pickup_app/core/engine/package_identity.dart';

/// 调试日志只走 debugPrint；不再落盘明文文件（含订单号/运单号，且无清理机制）。
void _logJd(String msg) {
  debugPrint(msg);
}

/// 是否是京东订单列表响应。
///
/// 配置/埋点包里也可能出现 `orderList` 字样；真机实测订单响应带
/// `orderId` + `wareInfoList`（旧版还有 orderStatusInfo，新版已扁平化）。
/// 只用于提前结束 fast-path 等待，宽松收集仍走 `orderList` 匹配。
bool isJdOrderListPayload(String text) =>
    text.contains('orderId') && text.contains('wareInfoList');

/// 京东新接口的英文终态枚举（真机：orderStatusName=Accomplish, statusId=5）。
bool _isJdTerminalStatus(String statusLower) =>
    statusLower == 'accomplish' ||
    statusLower == 'complete' ||
    statusLower == 'completed' ||
    statusLower == 'finished';

/// 详情预取是否已用完本轮时间预算（纯函数，便于单测）。
///
/// [deadline] 之后不再发起新的详情请求：外层 15s 硬超时量的是事件间隔，
/// 必须保证第一个 yield 在此之前出现；预算耗尽后退回订单侧状态。
@visibleForTesting
bool detailBudgetExhausted(DateTime deadline, {DateTime? now}) =>
    !(now ?? DateTime.now()).isBefore(deadline);

class JdH5Connector implements PlatformConnector {
  final PlatformAuthStore _authStore;
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; 25102RKBEC Build/UP1A.231005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  // 直接打开订单列表，默认筛选待收货
  static const _orderUrl =
      'https://trade.m.jd.com/order/orderlist_jdm.shtml';

  JdH5Connector({PlatformAuthStore? authStore})
      : _authStore = authStore ?? PlatformAuthStore();

  @override
  String get platformId => 'jd';

  @override
  String get displayName => '京东商城';

  @override
  String get brandColorHex => '#E1251B';

  @override
  Future<bool> isAuthenticated() async => _authStore.isBound('jd');

  bool _cancelled = false;

  @override
  Future<void> cancelSync() async {
    _cancelled = true;
    _capturedJsonList.clear();
    _capturedLogisticsJson.clear();
    final oc = _orderCapturedCompleter;
    if (oc != null && !oc.isCompleted) oc.complete();
    final lc = _logisticsCapturedCompleter;
    if (lc != null && !lc.isCompleted) lc.complete();
  }

  @override
  String? get lastIssue => _lastIssue;

  /// 用户重新授权后清理上一次的失效提示
  void clearLastIssue() {
    _lastIssue = null;
  }

  String? _lastIssue;
  WebViewController? _controller;
  final List<String> _capturedJsonList = [];
  Completer<void>? _orderCapturedCompleter;
  final List<String> _capturedLogisticsJson = [];
  Completer<void>? _logisticsCapturedCompleter;

  /// P42-a/c：本轮主 frame 网络硬失败 / 外层 8s 超时 → soft，禁止 expire
  final JdNetworkSoftFailGate _networkGate = JdNetworkSoftFailGate();

  bool get _networkSoftFail => _networkGate.failed;

  void _applyNetworkSoftFail(String reason) {
    _networkGate.apply(reason);
    if (_networkGate.issue != null) {
      _lastIssue = _networkGate.issue;
    }
    _logJd('[JD] network soft fail: $reason');
  }

  /// 本轮真正产出的包裹 ID（供上层清理旧版 DOM 伪卡片）
  final Set<String> _lastSyncYieldedIds = <String>{};

  /// 本轮是否解析到结构化订单列表（即使过滤后为空）
  bool _sawStructuredOrderList = false;
  bool get lastSyncSawStructuredList => _sawStructuredOrderList;
  Set<String> get lastSyncYieldedIds => Set.unmodifiable(_lastSyncYieldedIds);

  /// 本轮是否完整跑完（超时 / 取消时为 false，不能据此清理旧卡片）
  bool _lastSyncCompleted = false;
  bool get lastSyncCompleted => _lastSyncCompleted;

  @override
  Stream<Package> streamSync() async* {
    _lastSyncYieldedIds.clear();
    _lastSyncCompleted = false;
    _sawStructuredOrderList = false;
    final cookies = _authStore.getCookies('jd');
    if (cookies == null || cookies.trim().isEmpty) {
      _logJd('[JD] No cookies, skip');
      return;
    }

    _lastIssue = null;
    _cancelled = false;
    _networkGate.failed = false;
    _networkGate.issue = null;
    _networkGate.wake = null;
    _capturedJsonList.clear();
    _logJd('[JD] Starting sync with cookies (len: ${cookies.length})');
    await _injectCookies(cookies);

    final WebViewController controller;
    if (_controller != null) {
      controller = _controller!;
    } else {
      controller = WebViewController();
      _controller = controller;
      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(_ua)
        ..addJavaScriptChannel(
          'JdBridge',
          onMessageReceived: (JavaScriptMessage msg) {
            final text = msg.message;
            if (text.contains('orderList')) {
              // 宽松收集：配置包也可能含 orderList 字样，交给解析器按结构筛选；
              // 只有带订单对象字段的响应才提前结束 fast-path 等待。
              _capturedJsonList.add(text);
              if (isJdOrderListPayload(text)) {
                _logJd('[JD Hook] Captured order_list_m response (len: ${text.length})');
                final c = _orderCapturedCompleter;
                if (c != null && !c.isCompleted) c.complete();
              }
            } else if (text.contains('tracePointVOList') || text.contains('carriageId')) {
              _logJd('[JD Hook] Captured logistics response (len: ${text.length})');
              _capturedLogisticsJson.add(text);
              final c = _logisticsCapturedCompleter;
              if (c != null && !c.isCompleted) c.complete();
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              _injectNetworkHook(controller);
            },
            onNavigationRequest: (request) {
              final lower = request.url.toLowerCase();
              if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onWebResourceError: (error) {
              final main = error.isForMainFrame ?? false;
              if (main) {
                _logJd('[JD] main frame error: ${error.errorCode} ${error.description}');
              }
              // P42-a：主 frame 网络硬失败 → soft + 立刻结束（唤醒 hook 等待）
              _networkGate.onMainFrameError(
                errorCode: error.errorCode,
                description: error.description,
                isForMainFrame: main,
              );
              if (_networkGate.failed && _networkGate.issue != null) {
                _lastIssue = _networkGate.issue;
              }
            },
          ),
        );
    }

    final completer = Completer<void>();
    _orderCapturedCompleter = completer;
    _networkGate.wake = completer;

    // P30-b ① / P30-b′：本轮 plogin / setExpired(true) / 开始前已失效 → finally 禁止 persist
    final alreadyExpiredAtStart = _authStore.isExpired('jd');
    var skipPersist = alreadyExpiredAtStart;
    if (alreadyExpiredAtStart) {
      _logJd('[JD] skip cookie persist: already expired before sync (P30-b\')');
    }

    try {
      // P42-a：外层硬超时 8s；超时与主 frame 硬失败同一 soft 出口
      yield* _streamSyncBody(
        controller,
        alreadyExpiredAtStart: alreadyExpiredAtStart,
        markSkipPersist: () {
          skipPersist = true;
        },
      ).timeout(
        kJdStreamSyncHardTimeout,
        onTimeout: (EventSink<Package> sink) {
          _applyNetworkSoftFail(
            'streamSync hard timeout ${kJdStreamSyncHardTimeout.inSeconds}s',
          );
          sink.close();
        },
      );
    } catch (e, stack) {
      _logJd('[JD] streamSync error: $e\n$stack');
    } finally {
      // 只有完整跑完（未取消、未网络软失败）才允许上层用本轮 ID 清理旧伪卡片
      _lastSyncCompleted = !_cancelled && !_networkSoftFail;
      _networkGate.wake = null;
      _orderCapturedCompleter = null;
      // P30-b ① / P30-b′：plogin / 本轮标失效 / 开始前已失效 → 绝不 persist
      if (skipPersist) {
        _logJd(
          alreadyExpiredAtStart
              ? '[JD] skip cookie persist: already expired before sync'
              : '[JD] skip cookie persist: landed login/expired this round',
        );
      } else {
        await _persistJdCookiesIfHealthy(cookies);
      }
      // 同步用 WebView 不常驻：拉 blank 停活动并丢引用，交给 GC 销毁原生层，
      // 避免每轮同步泄漏一个原生 WebView（PDD 因心跳复用才常驻）。
      await parkWebView(_controller);
      _controller = null;
    }
  }

  /// P42-a 主体：可被外层 8s timeout 取消；网络 soft 后立刻 return。
  Stream<Package> _streamSyncBody(
    WebViewController controller, {
    required bool alreadyExpiredAtStart,
    required void Function() markSkipPersist,
  }) async* {
    // 1) 注入请求拦截钩子并直接导航到订单列表（消除加载 home.m.jd.com 造成的 10s 死等）
    _logJd('[JD] Navigating directly to orderlist_jdm.shtml...');
    await controller.loadRequest(Uri.parse(_orderUrl));
    if (_networkSoftFail) {
      _logJd('[JD] abort after navigate: network soft fail');
      return;
    }
    await _injectNetworkHook(controller);
    if (_networkSoftFail) {
      _logJd('[JD] abort after hook inject: network soft fail');
      return;
    }

    // 2) 极速拦截通道：等待网络钩子捕获 order_list_m；硬失败会 complete wake 提前结束
    final completer = _orderCapturedCompleter;
    if (completer != null) {
      try {
        await completer.future.timeout(const Duration(milliseconds: 3500));
        if (!_networkSoftFail) {
          _logJd('[JD] Fast hook capture hit! Captured ${_capturedJsonList.length} JSON responses');
        }
      } on TimeoutException {
        if (!_networkSoftFail) {
          _logJd('[JD] Hook fast path timed out (3.5s), proceeding to fallback check');
        }
      }
    }
    if (_networkSoftFail) {
      _logJd('[JD] abort after hook wait: network soft fail');
      return;
    }

    final orders = <_JdOrder>[];

    // 3) 优先从拦截到的 JSON 响应中解析订单
    if (_capturedJsonList.isNotEmpty) {
      for (final jsonStr in _capturedJsonList) {
        orders.addAll(_parseOrdersFromJson(jsonStr));
      }
    }

    // [临时探针] 已收集到结论：10 单全为即时配送（无运单号、轨迹含骑手）。

    // 4) DOM 兜底只在「结构化订单列表不可用」时执行。
    //    结构化源已经判定没有快递单时，绝不能用 DOM 文本重新造出包裹
    //    （DOM 不携带渠道信息，会把外卖/虚拟单当成快递）。
    if (orders.isEmpty && _sawStructuredOrderList) {
      _logJd('[JD] structured order list parsed (0 courier orders); skip DOM fallback');
    }
    if (orders.isEmpty && !_sawStructuredOrderList) {
      if (_networkSoftFail) return;
      final landedUrl = await _locationHref(controller);
      // 只记 host：落地 URL 的 query 里可能带订单号。
      _logJd('[JD] Fallback landed host=${Uri.tryParse(landedUrl)?.host ?? ''}');
      if (_networkSoftFail) return;
      // P42-c：网络 soft 本轮禁止因 plogin/login 误 expire
      if (jdShouldExpireOnLoginLanding(
        networkSoftFailThisRound: _networkSoftFail,
        landedUrl: landedUrl,
      )) {
        _lastIssue = '京东登录态已失效，请在「设置」中重新登录';
        markSkipPersist();
        await _authStore.setExpired('jd', true);
        return;
      }

      // 尝试等待 DOM 渲染并提取（P42-a：≤3s，且网络 soft 不进）
      await _awaitPageReady();
      if (_networkSoftFail) return;
      final rawExtracted = await _extractWaitReceiveOrdersViaJs(controller);
      if (rawExtracted != null && rawExtracted.isNotEmpty) {
        orders.addAll(_parseExtractedOrdersFromDom(rawExtracted));
      }
    }

    if (_networkSoftFail) return;

    // 去重并排除已归档订单（外卖/秒送已在 _parseOrdersFromJson 按快递白名单过滤）
    final validOrders = <String, _JdOrder>{};
    for (final o in orders) {
      if (o.status == PackageStatus.archived) {
        continue;
      }
      validOrders[o.orderId] = o;
    }

    _logJd('[JD] Final valid shopping orders: ${validOrders.length}');

    // 能拉到有效订单说明会话还能拉数；但若同步前已失效（保活自然掉），
    // 不得仅凭 orderlist 冲回已绑定——清失效留给设置页重登（P30-b′）。
    if (validOrders.isNotEmpty && !alreadyExpiredAtStart) {
      await _authStore.setExpired('jd', false);
    } else if (validOrders.isNotEmpty && alreadyExpiredAtStart) {
      _logJd('[JD] keep expired: orders ok but already expired before sync');
    }

    if (_networkSoftFail || _cancelled) return;

    // 共享 WebView 必须串行：详情页共用 _controller 与 _capturedLogisticsJson，
    // 并发 loadRequest 会互相打断，A 单捕获的轨迹会被 B 单当成自己的（与 PDD 同因，见 pdd_connector）。
    //
    // 详情预取必须留出时间预算：外层 15s 硬超时量的是事件间隔，若等全部详情
    // 取完才开始 yield，多包裹用户必然超时（0 张卡 + 误报「暂时不可达」）。
    // 预算耗尽后退回订单侧状态，卡片照常产出，只是没有轨迹详情。
    final detailMap = <String, _JdLogisticsDetail?>{};
    final detailDeadline = DateTime.now().add(const Duration(seconds: 8));
    final random = Random();
    for (final o in validOrders.values) {
      if (o.progressLink.isEmpty) continue;
      if (_networkSoftFail || _cancelled) return;
      if (detailBudgetExhausted(detailDeadline)) {
        _logJd('[JD] detail budget exhausted, remaining orders use list status');
        break;
      }
      detailMap[o.orderId] =
          await _fetchLogisticsDetail(o.orderId, o.progressLink);
      if (_networkSoftFail || _cancelled) return;
      await Future.delayed(
        Duration(milliseconds: 150 + random.nextInt(201)),
      );
    }
    if (_networkSoftFail) return;

    for (final o in validOrders.values) {
      if (_networkSoftFail || _cancelled) return;
      final detail = detailMap[o.orderId];

      final timelineJson = (detail != null && detail.timelineNodes.isNotEmpty)
          ? jsonEncode(detail.timelineNodes)
          : null;

      final status = detail != null
          ? LogisticsStatusEngine.derive(
              events: detail.timelineNodes,
              isPendingShipment: o.status == PackageStatus.pendingShipment,
              isOrderSigned: o.status == PackageStatus.pickedUp,
              pickupCode: o.pickupCode,
            ).status
          : o.status;

      _logJd('[JD Yield] id=${packageIdForLog('JD_${o.orderId}')} status=${status.label} '
          'hasTracking=${(detail?.trackingNumber ?? '').isNotEmpty} '
          'nodes=${detail?.timelineNodes.length ?? 0}');

      _lastSyncYieldedIds.add('JD_${o.orderId}');
      yield Package(
        id: 'JD_${o.orderId}',
        trackingNumber: (detail != null && detail.trackingNumber.isNotEmpty)
            ? detail.trackingNumber
            : o.orderId,
        courier: CourierType.jd,
        goodsName: o.goodsName.isNotEmpty ? o.goodsName : '京东商品快件',
        goodsImageUrl: o.imageUrl.isNotEmpty ? o.imageUrl : null,
        pickupCode: o.pickupCode,
        stationName: o.stationName.isNotEmpty ? o.stationName : '京东自提/配送',
        location: (detail != null && detail.address.isNotEmpty) ? detail.address : o.statusText,
        platform: 'jd',
        urgency: LogisticsStatusEngine.urgencyFor(status: status, pickupCode: o.pickupCode),
        status: status,
        addedAt: DateTime.now(),
        rawTimelineJson: timelineJson,
      );
    }
  }

  /// 同步完成后回写最新 Cookie，防止 pt_key 丢失或数据萎缩
  Future<void> _persistJdCookiesIfHealthy(String originalCookies) async {
    try {
      final cm = WebViewCookieManager();
      final map = <String, String>{};
      for (final host in kJdPersistCookieHosts) {
        try {
          final list = await cm.getCookies(domain: Uri.parse(host));
          for (final c in list) {
            if (c.name.isNotEmpty && c.value.isNotEmpty) {
              map[c.name] = c.value;
            }
          }
        } catch (_) {}
      }
      if (map.isEmpty) return;

      final merged = map.entries.map((e) => '${e.key}=${e.value}').join('; ');
      if (isJdCookieHealthy(originalCookies, merged)) {
        if (merged != originalCookies) {
          await _authStore.saveCookies('jd', merged);
          _logJd('[JD] cookies refreshed (len: ${merged.length})');
        }
      } else {
        _logJd('[JD] skip cookie persist: failed health check (pt_key missing or degraded)');
      }
    } catch (e) {
      _logJd('[JD] persist cookies error: $e');
    }
  }

  /// 导航到订单物流跟踪页：双轨机制（优先拦截接口，超时走 DOM 纯文本状态机兜底）
  Future<_JdLogisticsDetail?> _fetchLogisticsDetail(String orderId, String progressLink) async {
    final controller = _controller;
    if (controller == null || _cancelled) return null;
    _capturedLogisticsJson.clear();
    final completer = Completer<void>();
    _logisticsCapturedCompleter = completer;
    try {
      await controller.loadRequest(Uri.parse(progressLink));
      try {
        await completer.future.timeout(const Duration(milliseconds: 3000));
      } on TimeoutException {
        // 页面未触发物流接口，继续走 DOM 兜底
      } finally {
        _logisticsCapturedCompleter = null;
      }
      if (_capturedLogisticsJson.isNotEmpty) {
        final parsed = _parseLogisticsJson(_capturedLogisticsJson.first);
        if (parsed != null && parsed.timelineNodes.isNotEmpty) {
          return parsed;
        }
      }

      // ── DOM 纯文本行状态机兜底（抗接口变动与缓存） ──
      final domText = await _domText(controller);
      if (domText.isNotEmpty) {
        final domNodes = parseJdDomTimeline(domText);
        if (domNodes.isNotEmpty) {
          _logJd('[JD Logistics] DOM fallback parsed ${domNodes.length} nodes');
          // 页面行序不保证最新在前；引擎以 events.first 为最新节点。
          domNodes.sort((a, b) => (b['time'] ?? '').compareTo(a['time'] ?? ''));
          return _JdLogisticsDetail(
            trackingNumber: '',
            carrier: '京东快递',
            address: '',
            timelineNodes: domNodes,
          );
        }
      }
      return null;
    } catch (e) {
      _logJd('[JD Logistics] fetch error: $e');
      return null;
    }
  }

  Future<String> _domText(WebViewController controller) async {
    try {
      final result = await controller.runJavaScriptReturningResult(
        "(function(){return document.body ? document.body.innerText.slice(0, 30000) : '';})()",
      );
      var text = result.toString();
      if (text.startsWith('"') && text.endsWith('"')) {
        try {
          text = jsonDecode(text) as String;
        } catch (_) {
          text = text.substring(1, text.length - 1);
        }
      }
      return text.replaceAll(r'\n', '\n');
    } catch (_) {
      return '';
    }
  }

  /// 解析 get_logistics_list_by_order_m 响应：运单号 + 承运商 + 地址 + 完整轨迹节点
  _JdLogisticsDetail? _parseLogisticsJson(String jsonStr) {
    try {
      final root = jsonDecode(jsonStr) as Map<String, dynamic>;
      final body = root['body'] as Map<String, dynamic>?;
      if (body == null) return null;
      final nodes = <Map<String, String>>[];
      final traceList = body['tracePointVOList'] as List<dynamic>?;
      if (traceList != null) {
        for (final t in traceList) {
          if (t is! Map<String, dynamic>) continue;
          // createTime 可能是约定格式或 epoch 毫秒，统一规范化；解析不出时间的节点不写入
          final time = normalizeTraceTime(t['createTime']);
          final text = t['wlStateDesc']?.toString() ?? '';
          if (text.isEmpty || time == null) continue;
          nodes.add({'tag': '', 'time': time, 'text': text});
        }
      }
      if (nodes.isEmpty) return null;
      // 引擎读 events.first 作为最新节点；接口不保证顺序，统一按时间倒序。
      nodes.sort((a, b) => (b['time'] ?? '').compareTo(a['time'] ?? ''));
      return _JdLogisticsDetail(
        trackingNumber: body['carriageId']?.toString() ?? '',
        carrier: body['carrier']?.toString() ?? '',
        address: body['recvAddr']?.toString() ?? '',
        timelineNodes: nodes,
      );
    } catch (e) {
      _logJd('[JD Logistics] parse error: $e');
      return null;
    }
  }

  Future<void> _injectNetworkHook(WebViewController controller) async {
    const hookJs = '''
(function(){
  if (window.__jdHookInstalled) return;
  window.__jdHookInstalled = true;

  function report(data){
    try {
      JdBridge.postMessage(typeof data === 'string' ? data : JSON.stringify(data));
    } catch(e) {}
  }

  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function(input, init) {
      var p = origFetch.apply(this, arguments);
      if (p && p.then) {
        p.then(function(res) {
          try {
            res.clone().text().then(function(t) {
              var isOrder = t.indexOf('orderList') !== -1;
              var isLogistics = t.indexOf('tracePointVOList') !== -1 || t.indexOf('carriageId') !== -1;
              if (isOrder || isLogistics) report(t);
            });
          } catch(e) {}
        });
      }
      return p;
    };
  }

  var origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function() {
    this.addEventListener('load', function() {
      try {
        var t = this.responseText || '';
        var isOrder = t.indexOf('orderList') !== -1;
        var isLogistics = t.indexOf('tracePointVOList') !== -1 || t.indexOf('carriageId') !== -1;
        if (isOrder || isLogistics) report(t);
      } catch(e) {}
    });
    return origSend.apply(this, arguments);
  };
})();
''';
    try {
      await controller.runJavaScript(hookJs);
    } catch (_) {}
  }

  Future<void> _injectCookies(String cookies) async {
    final cm = WebViewCookieManager();
    var count = 0;
    for (final part in cookies.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final name = part.substring(0, idx).trim();
      final value = part.substring(idx + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      for (final host in const ['.jd.com', 'trade.m.jd.com', 'home.m.jd.com', 'api.m.jd.com']) {
        try {
          await cm.setCookie(WebViewCookie(domain: host, path: '/', name: name, value: value));
          count++;
        } catch (_) {}
      }
    }
    _logJd('[JD] injected cookie calls: $count');
  }

  Future<String> _locationHref(WebViewController controller) async {
    try {
      final r = await controller.runJavaScriptReturningResult('location.href');
      var s = r.toString();
      if (s.startsWith('"') && s.endsWith('"')) {
        try {
          s = jsonDecode(s) as String;
        } catch (_) {
          s = s.substring(1, s.length - 1);
        }
      }
      return s;
    } catch (_) {
      return '';
    }
  }

  Future<void> _awaitPageReady() async {
    // P42-a：网络硬失败本轮不进；上限 ≤3s（原 10s）
    if (_networkSoftFail) return;
    final controller = _controller;
    if (controller == null) return;
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      if (_networkSoftFail) return;
      await Future.delayed(const Duration(milliseconds: 350));
      try {
        final r = await controller.runJavaScriptReturningResult(
          "(function(){return (document.body && document.body.innerText && document.body.innerText.length > 200 && (document.body.innerText.indexOf('订单') !== -1 || document.body.innerText.indexOf('¥') !== -1)) ? '1' : '0';})()",
        );
        if (r.toString().contains('1')) break;
      } catch (_) {}
    }
  }

  /// 从拦截到的 order_list_m JSON 响应中解析
  /// 在任意层级的响应里定位订单数组。
  ///
  /// 京东不同接口把列表放在 `body` / `data` / 更深包裹中（真机实测根节点是
  /// `{code,msg,version,data,traceId}`），写死 `body.orderList` 会整包解析失败、
  /// 退化成标题靠猜的 DOM 兜底。这里递归找第一个订单对象数组，深度上限防异常结构。
  static List<dynamic>? _findJdOrderList(dynamic node, [int depth = 0]) {
    if (depth > 5) return null;
    if (node is Map) {
      final ol = node['orderList'];
      // 空数组不是订单列表：继续向下找，避免配置节点里的 `orderList: []`
      // 抢占真正的订单数组。整包都没有才返回 null。
      if (ol is List && _looksLikeJdOrderList(ol)) return ol;
      for (final v in node.values) {
        final found = _findJdOrderList(v, depth + 1);
        if (found != null) return found;
      }
    } else if (node is List) {
      if (_looksLikeJdOrderList(node)) return node;
      for (final v in node) {
        final found = _findJdOrderList(v, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  static bool _looksLikeJdOrderList(List<dynamic> list) =>
      list.isNotEmpty &&
      list.first is Map &&
      (list.first as Map).containsKey('orderId');

  @visibleForTesting
  static List<dynamic>? debugFindJdOrderList(dynamic node) =>
      _findJdOrderList(node);

  /// 单测入口：解析一段订单 JSON，返回是否被认定为权威结构化源。
  @visibleForTesting
  bool debugParseOrders(String jsonStr) {
    _sawStructuredOrderList = false;
    _parseOrdersFromJson(jsonStr);
    return _sawStructuredOrderList;
  }

  List<_JdOrder> _parseOrdersFromJson(String jsonStr) {
    final list = <_JdOrder>[];
    try {
      var s = jsonStr;
      if (s.startsWith('"') && s.endsWith('"')) {
        s = jsonDecode(s) as String;
      }
      final root = jsonDecode(s) as Map<String, dynamic>;
      // 京东不同接口/版本把订单列表放在 body / data / 更深的包裹里，
      // 不写死层级：递归找第一个「订单对象数组」，避免整包解析失败退化成 DOM 兜底。
      final orderList = _findJdOrderList(root);
      if (orderList == null) return list;
      // 只有真正的订单数组（非空且首元素带 orderId）才算结构化源可用。
      // 埋点/配置包里的空 `orderList: []` 不能当权威结论，否则一次钩子漏抓
      // 就会跳过 DOM 兜底并触发清卡。
      if (_looksLikeJdOrderList(orderList)) {
        _sawStructuredOrderList = true;
      }

      _logJd('[JD Hook] Found ${orderList.length} orders in JSON');

      for (final item in orderList) {
        if (item is! Map<String, dynamic>) continue;

        final orderId = item['orderId']?.toString() ?? '';
        if (orderId.isEmpty) continue;

        if (!isJdCourierDelivery(item)) {
          _logJd('[JD Filter] Not courier delivery, drop: ${packageIdForLog('JD_$orderId')}');
          continue;
        }

        final statusInfo = item['orderStatusInfo'] as Map<String, dynamic>?;
        final statusName = statusInfo?['orderStatusName']?.toString() ??
            item['orderStatusName']?.toString() ??
            item['orderStatus']?.toString() ??
            '';
        final statusLower = statusName.toLowerCase();

        // 过滤已关闭/取消（兼容英文枚举 Cancel/Closed/Refund）
        if (statusName.contains('取消') ||
            statusName.contains('关闭') ||
            statusName.contains('退款') ||
            statusLower.contains('cancel') ||
            statusLower.contains('close') ||
            statusLower.contains('refund')) {
          continue;
        }

        // P44：严格签收白名单，禁止裸「完成」宽匹配；京东新接口用英文 Accomplish
        final isCompleted = LogisticsStatusEngine.isStrictOrderSignedLabel(statusName) ||
            _isJdTerminalStatus(statusLower);

        // 商品标题与主图
        String goodsName = '';
        String imageUrl = '';
        final wareList = item['wareInfoList'] as List<dynamic>?;
        if (wareList != null && wareList.isNotEmpty) {
          final w0 = wareList[0] as Map<String, dynamic>;
          goodsName = GoodsNameCleaner.clean(w0['wareName']?.toString() ?? '');
          imageUrl = w0['imageUrl']?.toString() ?? '';
          imageUrl = normalizeImageUrl(imageUrl);
        }

        // 轨迹进展与自提码
        final prog = item['progressInfo'] as Map<String, dynamic>?;
        final latestText = prog?['content']?.toString() ??
            item['messageTitle']?.toString() ??
            item['message']?.toString() ??
            statusName;
        final tip = prog?['tip']?.toString() ?? '';
        final rawProgressLink = prog?['progressLink']?.toString() ?? '';

        // P45：部分秒送单 progressId 同为 logistics，结构标记漏网时用状态文案兜底
        if (looksLikeJdInstantDeliveryText('$latestText $statusName $tip')) {
          _logJd('[JD Filter] Instant delivery, drop: ${packageIdForLog('JD_$orderId')}');
          continue;
        }
        final orderDetailLink =
            (item['orderDetailLink'] as Map<String, dynamic>?)?['url']?.toString() ?? '';

        String skuId = '';
        if (wareList != null && wareList.isNotEmpty) {
          final w0 = wareList[0] as Map<String, dynamic>;
          skuId = w0['skuId']?.toString() ?? '';
        }
        final shopInfo = item['shopInfo'] as Map<String, dynamic>?;
        final shopId = shopInfo?['shopId']?.toString() ?? '';
        final dealState = statusInfo?['originOrderStatus']?.toString() ?? '';
        final orderType = item['orderType']?.toString() ?? '';

        final progressLink = buildJdLogisticsUrl(
          orderId: orderId,
          progressLink: rawProgressLink,
          skuId: skuId,
          shopId: shopId,
          dealState: dealState,
          orderType: orderType,
        );

        final pickupCode = _pickupCodeFromText('$latestText $statusName $tip');
        final station = _stationFromText('$latestText $statusName');

        // 若含有提货码/自提码（如已放入快递柜/便民点），即使标记完成也视为待取件；
        // 其余状态统一交由物流状态引擎根据最新轨迹文本推导（与拼多多/淘宝同一套引擎）。
        final status = pickupCode.isNotEmpty
            ? PackageStatus.arrived
            : LogisticsStatusEngine.derive(
                events: [
                  if (latestText.isNotEmpty)
                    {'tag': statusName, 'time': '', 'text': latestText},
                ],
                isPendingShipment: statusName.contains('待发货') ||
                    statusName.contains('等待发货') ||
                    statusName.contains('待出库'),
                isOrderSigned: isCompleted,
                pickupCode: '',
              ).status;

        list.add(_JdOrder(
          orderId: orderId,
          status: status,
          statusText: latestText,
          pickupCode: pickupCode,
          stationName: station,
          goodsName: goodsName,
          imageUrl: imageUrl,
          progressLink: progressLink,
          orderDetailLink: orderDetailLink,
        ));
      }
    } catch (e) {
      _logJd('[JD Hook] parse JSON error: $e');
    }
    return list;
  }

  /// DOM 提取兜底脚本 - 深度提取页面中的待收货订单卡片与真实商品图片
  Future<String?> _extractWaitReceiveOrdersViaJs(WebViewController controller) async {
    // raw 字符串：JS 正则里的 \/ 是字面量，非 raw 会被 Dart 当多余转义剥掉
    const jsCode = r'''
(function(){
  try {
    var bodyText = document.body ? document.body.innerText : '';
    var goodsImages = [];
    var seenImg = {};

    var imgNodes = document.querySelectorAll('img');
    for (var i = 0; i < imgNodes.length; i++) {
      var src = imgNodes[i].src || imgNodes[i].getAttribute('data-src') || imgNodes[i].getAttribute('data-img') || '';
      if (src.indexOf('//') === 0) src = 'https:' + src;

      // 严格过滤头像、logo、小图标、自营狗标、横幅、Plus会员标志、活动/img/横幅
      var isLogoOrAvatar = src.match(/avatar|logo|icon|plus|member|arrow|banner|badge|dada|mascot|brand|\/img\//i);

      // 京东真实商品主图特征路径（CDN 专属规则：包含 /n0/, /n1/, /n2/, /n5/ 或 popWareMobile）
      var isRealJdProduct = src.match(/popWareMobile|mobile_ware|\/n[0-9]\/|s150x150|s100x100|s200x200|s300x300/i);

      if (src && isRealJdProduct && !isLogoOrAvatar && !seenImg[src]) {
        seenImg[src] = true;
        goodsImages.push(src);
      }
    }

    return JSON.stringify({
      bodyText: bodyText,
      goodsImages: goodsImages
    });
  } catch(e) {
    return JSON.stringify({error: String(e)});
  }
})()
''';
    try {
      final r = await controller.runJavaScriptReturningResult(jsCode);
      var s = r.toString();
      if (s == 'null' || s == '""') return null;
      if (s.startsWith('"') && s.endsWith('"')) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is String) {
            s = decoded;
          }
        } catch (_) {
          s = s.substring(1, s.length - 1);
        }
      }
      return s;
    } catch (e) {
      _logJd('[JD] JS extract error: $e');
      return null;
    }
  }

  List<_JdOrder> _parseExtractedOrdersFromDom(String jsonStr) {
    final list = <_JdOrder>[];
    Map<String, dynamic>? root;
    try {
      root = jsonDecode(jsonStr) as Map<String, dynamic>?;
    } catch (e) {
      return list;
    }

    final bodyText = root?['bodyText']?.toString() ?? '';
    final goodsImages = (root?['goodsImages'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    _logJd('[JD Goods Images] count: ${goodsImages.length}, list: $goodsImages');
    if (bodyText.isEmpty) return list;

    final lines = bodyText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // 匹配包裹在途与近期已签收/完成状态（排除导航 Tab 标签）
    const validOrderStatuses = [
      '正在出库',
      '出库中',
      '等待出库',
      '已出库',
      '派送中',
      '派件中',
      '等待收货',
      '运输中',
      '已到达',
      '已存入',
      '已签收',
      '已妥投',
      '已完成',
      '完成',
    ];

    final seenTitles = <String>{};

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 排除头部导航区（前 8 行内的误判）
      if (i < 8 && (line == '全部' || line == '待付款' || line == '待收货' || line == '待评价' || line == '下拉刷新')) {
        continue;
      }

      final matchedStatus = validOrderStatuses.firstWhere(
        (st) => line == st || (line.contains(st) && line.length <= 8),
        orElse: () => '',
      );

      if (matchedStatus.isNotEmpty) {
        // 必须在后续行中找到「实付」或「¥」，确保这是一个真实的订单卡片，而非页面散落文本
        var hasOrderContext = false;
        for (var cIdx = i; cIdx < lines.length && cIdx < i + 10; cIdx++) {
          if (lines[cIdx].contains('实付') || lines[cIdx].contains('¥') || lines[cIdx].contains('再次购买')) {
            hasOrderContext = true;
            break;
          }
        }
        if (!hasOrderContext) continue;

        // 提取店铺名称（状态行之前且不是导航标签）
        var shopName = '京东自营';
        if (i > 0) {
          final prev = lines[i - 1];
          if (!prev.contains('全部') && !prev.contains('待付款') && !prev.contains('待收货') && !prev.contains('刷新')) {
            shopName = prev;
          }
        }

        final progress = (i + 1 < lines.length && !lines[i + 1].contains('¥') && !lines[i + 1].startsWith('x'))
            ? lines[i + 1]
            : '';

        var title = '';
        var searchStart = i + (progress.isNotEmpty ? 2 : 1);
        for (var j = searchStart; j < lines.length && j < searchStart + 5; j++) {
          final cand = lines[j];
          if (cand.startsWith('实付') || cand.contains('¥') || cand.contains('再次购买')) {
            break;
          }
          if (cand.length >= 6 && title.isEmpty && !cand.startsWith('x') && !cand.contains('件')) {
            title = cand;
          }
        }

        // 页面按钮/服务文案不是商品名，先剔掉
        const uiNoise = [
          '查看送达照片', '送达照片', '不支持7天无理由退货', '7天无理由退货',
          '再次购买', '申请售后', '评价晒单', '查看物流', '确认收货',
          '删除订单', '联系客服', '查看发票', '价格保护', '催单', '修改地址',
        ];
        if (title.isNotEmpty && uiNoise.any(title.contains)) title = '';
        if (title.isEmpty) {
          // 进展行不是物流动作时才可能是商品名（如「【…】牛肉汉堡套餐」）
          final progressIsStatus = progress.isEmpty ||
              LogisticsStatusEngine.isActiveLogisticsText(progress) ||
              progress.contains('送达') ||
              progress.contains('签收') ||
              progress.contains('完成') ||
              progress.contains('运输') ||
              progress.contains('派送');
          title = progressIsStatus ? '京东在途商品' : progress;
        }

        if (seenTitles.contains(title)) continue;
        seenTitles.add(title);

        // P45：DOM 兜底没有 JSON 结构，只认渠道词（骑手/达达/秒送/京东到家…），
        // 且物流进展仍活跃时不丢。不用菜名（螺蛳粉/套餐…）判外卖——网上买的
        // 食品也是真实快递；宁可漏清外卖，也不误删真实包裹。
        if (!LogisticsStatusEngine.isActiveLogisticsText(progress) &&
            looksLikeJdInstantDeliveryText('$matchedStatus $progress $title')) {
          _logJd('[JD Filter] Instant delivery in DOM, drop');
          continue;
        }

        final pickupCode = _pickupCodeFromText('$matchedStatus $progress $title');
        final station = _stationFromText('$shopName $progress');
        // P44 口径：订单侧「完成」不能压过仍在途的物流节点；
        // 但进展行没有活跃物流动作（空 / 商品名）时，「完成」就是真完成。
        final isBareCompleted = matchedStatus == '完成' || matchedStatus == '已完成';
        final progressActive = LogisticsStatusEngine.isActiveLogisticsText(progress);
        final isCompleted = LogisticsStatusEngine.isStrictOrderSignedLabel(matchedStatus) ||
            (isBareCompleted && !progressActive);
        final status = pickupCode.isNotEmpty
            ? PackageStatus.arrived
            : (isCompleted
                ? PackageStatus.pickedUp
                : LogisticsStatusEngine.derive(
                    events: [
                      {'tag': matchedStatus, 'time': '', 'text': progress},
                    ],
                    isPendingShipment: matchedStatus.contains('待发货') ||
                        matchedStatus.contains('等待发货') ||
                        matchedStatus.contains('待出库'),
                    isOrderSigned: false,
                    pickupCode: '',
                  ).status);
        final hash = md5.convert(utf8.encode('$title$shopName')).toString().substring(0, 12);

        // 匹配商品图片（严格优先选取 /n1/, /n2/, /n0/, /popWareMobile/ 等商品路径）
        final realProductImgs = goodsImages.where((url) =>
            url.contains('/n1/') ||
            url.contains('/n2/') ||
            url.contains('/n0/') ||
            url.contains('/n5/') ||
            url.contains('/popWareMobile/')).toList();
        final img = realProductImgs.isNotEmpty
            ? realProductImgs.first
            : (goodsImages.isNotEmpty ? goodsImages.first : '');

        _logJd('[JD Found In-Transit] titleLen=${title.length} '
            'status=${status.label} progressLen=${progress.length}');

        list.add(_JdOrder(
          // DOM 兜底的合成 id 用 x 前缀明确标记来源，避免与真实十进制订单号混淆
          orderId: 'x$hash',
          status: status,
          statusText: progress.isNotEmpty ? '$matchedStatus · $progress' : matchedStatus,
          pickupCode: pickupCode,
          stationName: station.isNotEmpty ? station : shopName,
          goodsName: GoodsNameCleaner.clean(title),
          imageUrl: img,
        ));
      }
    }

    return list;
  }

  String _pickupCodeFromText(String block) {
    final m = RegExp(r'(?:取件码|提货码|取货码|凭码|自提码)[:：\s]*([A-Za-z0-9\-]{3,12})').firstMatch(block);
    return m?.group(1) ?? '';
  }

  String _stationFromText(String block) => extractPickupPointName(block);

}

class _JdOrder {
  final String orderId;
  final PackageStatus status;
  final String statusText;
  final String pickupCode;
  final String stationName;
  final String goodsName;
  final String imageUrl;
  final String progressLink;
  final String orderDetailLink;

  const _JdOrder({
    required this.orderId,
    required this.status,
    required this.statusText,
    required this.pickupCode,
    required this.stationName,
    required this.goodsName,
    required this.imageUrl,
    this.progressLink = '',
    this.orderDetailLink = '',
  });
}

/// 京东物流跟踪页解析结果：真实运单号 + 承运商 + 收货地址 + 完整轨迹节点
class _JdLogisticsDetail {
  final String trackingNumber;
  final String carrier;
  final String address;
  final List<Map<String, String>> timelineNodes;

  const _JdLogisticsDetail({
    required this.trackingNumber,
    required this.carrier,
    required this.address,
    required this.timelineNodes,
  });
}
