// P44：在途/派送不得因订单侧宽「完成」进入「已完成」(pickedUp)。
// 本票：拼多多 / 极兔 JT5542922044377，最新「运输中 …离开【东莞虎门转运中心】…发往【邢台转运中心】」。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/logistics_status_engine.dart';
import 'package:pickup_app/core/models/package.dart';
import 'package:pickup_app/core/models/package_status.dart';
import 'package:pickup_app/platform/connectors/pdd_connector.dart';

void main() {
  // 嘉豪真机本票最新轨迹原文（见 docs/device-qa-2026-11-05/p44-repro-notes.md）
  const pddTicketLatest =
      '您的快件离开【东莞虎门转运中心】，已发往【邢台转运中心】客服电话：956025';
  const pddTicketTag = '运输中';

  group('P44-c LogisticsStatusEngine.derive', () {
    test('① 订单侧 isOrderSigned + 最新节点「运输中」→ transit（否决宽签收）', () {
      final derived = LogisticsStatusEngine.derive(
        events: [
          {'tag': pddTicketTag, 'time': '2026-11-05 02:02:00', 'text': pddTicketLatest},
          {'tag': '运输中', 'time': '2026-11-05 02:00:00', 'text': '您的快件已到达【东莞虎门转运中心】'},
        ],
        isOrderSigned: true,
      );
      expect(derived.status, PackageStatus.transit);
      expect(derived.status.isCompleted, isFalse);
    });

    test('② 订单侧 isOrderSigned + 最新「派送中」→ delivering', () {
      final derived = LogisticsStatusEngine.derive(
        events: [
          {'tag': '派送中', 'time': '2026-11-05 10:00:00', 'text': '快递员正在派送中，请保持电话畅通'},
        ],
        isOrderSigned: true,
      );
      expect(derived.status, PackageStatus.delivering);
      expect(derived.status.isCompleted, isFalse);
    });

    test('③ 真签收节点仍 → pickedUp（lgStatus/轨迹明确签收）', () {
      final derived = LogisticsStatusEngine.derive(
        events: [
          {'tag': '已签收', 'time': '2026-11-04 18:00:00', 'text': '快件已签收，签收人：本人签收'},
        ],
        isOrderSigned: true,
      );
      expect(derived.status, PackageStatus.pickedUp);
    });

    test('③b 无轨迹但 isOrderSigned 真签收标签 → pickedUp', () {
      final derived = LogisticsStatusEngine.derive(
        events: const [],
        isOrderSigned: true,
      );
      expect(derived.status, PackageStatus.pickedUp);
    });

    test('④ 有取件码且非待发货 → arrived（不被完成抢走）', () {
      final derived = LogisticsStatusEngine.derive(
        events: [
          {'tag': '运输中', 'time': '2026-11-05 02:02:00', 'text': pddTicketLatest},
        ],
        isOrderSigned: true,
        pickupCode: '13-5-6036',
      );
      expect(derived.status, PackageStatus.arrived);
    });

    test('⑤ 本票：PDD 文案场景下 derive 不得 pickedUp', () {
      final derived = LogisticsStatusEngine.derive(
        events: [
          {
            'tag': '运输中',
            'time': '2026-11-05 02:02:00',
            'text': '您的快件离开【东莞虎门转运中心】，已发往【邢台转运中心】客服电话：956025',
          },
        ],
        isOrderSigned: true, // 模拟订单侧误标「已完成/待评价」
      );
      expect(derived.status, PackageStatus.transit);
    });
  });

  group('P44-c 签收白名单', () {
    test('裸「完成」「已完成」「待评价」不是严格签收', () {
      expect(LogisticsStatusEngine.isStrictOrderSignedLabel('完成'), isFalse);
      expect(LogisticsStatusEngine.isStrictOrderSignedLabel('已完成'), isFalse);
      expect(LogisticsStatusEngine.isStrictOrderSignedLabel('待评价'), isFalse);
      expect(LogisticsStatusEngine.isStrictOrderSignedLabel('订单已完成'), isFalse);
    });

    test('白名单短语才是严格签收', () {
      for (final ok in [
        '已签收',
        '签收成功',
        '本人签收',
        '代收人已签收',
        '已妥投',
        '妥投签收',
        '已收货',
        '交易成功',
      ]) {
        expect(LogisticsStatusEngine.isStrictOrderSignedLabel(ok), isTrue, reason: ok);
      }
    });
  });

  group('P44-c PddStatusClassifier（本票路径）', () {
    test('① prompt「已完成」+ 最新「运输中」离开虎门 → transit', () {
      final status = PddStatusClassifier.resolve(
        statusPrompt: '已完成',
        logisticsDesc: '运输中 $pddTicketLatest',
        fullText: '已完成 运输中 $pddTicketLatest',
      );
      expect(status, PackageStatus.transit);
      expect(status.isCompleted, isFalse);
    });

    test('①b prompt「待评价」+ 运输中 → transit', () {
      final status = PddStatusClassifier.resolve(
        statusPrompt: '待评价',
        logisticsDesc: '运输中：您的快件离开【东莞虎门转运中心】，已发往【邢台转运中心】',
      );
      expect(status, PackageStatus.transit);
    });

    test('①c prompt「交易成功」+ 运输中 → transit（有在途节点时交易成功不得签收）', () {
      final status = PddStatusClassifier.resolve(
        statusPrompt: '交易成功',
        logisticsDesc: '运输中 $pddTicketLatest',
      );
      expect(status, PackageStatus.transit);
    });

    test('② 「派送中」→ delivering', () {
      final status = PddStatusClassifier.resolve(
        statusPrompt: '待收货',
        logisticsDesc: '派送中 快递员正在为您派件',
      );
      expect(status, PackageStatus.delivering);
    });

    test('③ 真签收仍 pickedUp', () {
      final status = PddStatusClassifier.resolve(
        statusPrompt: '已签收',
        logisticsDesc: '已签收，签收人：本人',
      );
      expect(status, PackageStatus.pickedUp);
    });

    test('③b 交易成功且无在途节点 → pickedUp', () {
      final status = PddStatusClassifier.resolve(
        statusPrompt: '交易成功',
        logisticsDesc: '',
      );
      expect(status, PackageStatus.pickedUp);
    });

    test('④ 有取件码到站 → arrived', () {
      final status = PddStatusClassifier.resolve(
        statusPrompt: '待收货',
        logisticsDesc: '已派送至【校园驿站】，凭取件码取件',
        pickupCode: '3-2-1002',
      );
      expect(status, PackageStatus.arrived);
    });

    test('裸已完成无轨迹 → 不得仅凭「已完成」判 pickedUp', () {
      final status = PddStatusClassifier.resolve(
        statusPrompt: '已完成',
        logisticsDesc: '',
      );
      expect(status, isNot(PackageStatus.pickedUp));
    });
  });

  group('P44 tip：假完成不得 skip enrich（CTO：无 pickedUpAt）', () {
    test('Hive 假 pickedUp（无 pickedUpAt）→ 不得跳过', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.pickedUp,
          userPickedUpAt: null,
        ),
        isFalse,
      );
    });

    test('真用户取件（有 pickedUpAt）→ 可跳过', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.pickedUp,
          userPickedUpAt: DateTime(2026, 11, 5),
        ),
        isTrue,
      );
    });

    test('archived / rejected 仍跳过', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.archived,
          userPickedUpAt: null,
        ),
        isTrue,
      );
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.rejected,
        ),
        isTrue,
      );
    });

    test('活跃态不跳过', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.transit,
          userPickedUpAt: null,
        ),
        isFalse,
      );
    });
  });

  group('P44 tip：Hive 假 pickedUp + 最新运输中 → sync 后 transit', () {
    test('enrich/derive：假完成订单侧 isOrderSigned + 运输中节点 → transit（供 _resolveStatus 回滚）', () {
      // 同步链路：gate 不 skip → enrich 拉时间轴 → derive → addPackage/_resolveStatus
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.pickedUp,
          userPickedUpAt: null,
        ),
        isFalse,
        reason: '假完成必须进 enrich',
      );
      final derived = LogisticsStatusEngine.derive(
        events: [
          {'tag': pddTicketTag, 'time': '2026-11-05 02:02:00', 'text': pddTicketLatest},
        ],
        isOrderSigned: true, // 列表仍判完成 / Hive 误标
      );
      expect(derived.status, PackageStatus.transit);
      expect(derived.status.isCompleted, isFalse);
    });

    test('回归：拼「已取件」label 不得再让假完成 skip（旧 #38 闸门死穴）', () {
      final poisoned = '运输中 $pddTicketLatest 已取件';
      expect(LogisticsStatusEngine.classifyNode(poisoned), LogisticsNodeAction.signed);
      // 新闸门只认用户 pickedUpAt，与 label 拼接无关
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.pickedUp,
          userPickedUpAt: null,
        ),
        isFalse,
      );
    });
  });


  group('P44 tip9：假 pickedUp 必须吃到 JT554（本地证据 / 扫尾口径）', () {
    const jtTracking = 'JT5542922044377';
    // 故意最旧在前：复刻 Hive 未排序存储；详情 UI 会再排，旧 heal 用 parsedTimeline 会踩首节点「已下单」
    const oldestFirstJson = '['
        '{"tag":"已下单","time":"2026-11-03 10:00:00","text":"您已提交订单，等待系统确认"},'
        '{"tag":"运输中","time":"2026-11-05 02:00:00","text":"您的快件已到达【东莞虎门转运中心】"},'
        '{"tag":"运输中","time":"2026-11-05 02:02:00","text":"您的快件离开【东莞虎门转运中心】，已发往【邢台转运中心】客服电话：956025"}'
        ']';

    Package fakeJt({DateTime? pickedUpAt, String? timeline}) {
      return Package(
        id: 'PDD_261103-1819594730000',
        trackingNumber: jtTracking,
        courier: CourierType.jt,
        platform: 'pdd',
        description: pddTicketLatest,
        urgency: UrgencyLevel.normal,
        status: PackageStatus.pickedUp,
        addedAt: DateTime(2026, 11, 3),
        pickedUpAt: pickedUpAt,
        rawTimelineJson: timeline ?? oldestFirstJson,
      );
    }

    test('eventsNewestFirst：Hive 旧序（最旧在前）仍取最新运输中', () {
      final events = LogisticsStatusEngine.eventsNewestFirst(oldestFirstJson);
      expect(events, isNotEmpty);
      expect(events.first['tag'], '运输中');
      expect(events.first['text'], contains('离开【东莞虎门转运中心】'));
      expect(
        LogisticsStatusEngine.hasActiveLocalEvidence(rawTimelineJson: oldestFirstJson),
        isTrue,
      );
    });

    test('heal：假 pickedUp + 旧序时间轴 → transit（tip8 启动自愈口径）', () {
      final healed = PddFalsePickupHeal.healMisfiledPickedUp(fakeJt());
      expect(healed, isNotNull);
      expect(healed!.status, PackageStatus.transit);
      expect(healed.status.isCompleted, isFalse);
    });

    test('heal：真用户 pickedUpAt → 不回滚', () {
      final healed = PddFalsePickupHeal.healMisfiledPickedUp(
        fakeJt(pickedUpAt: DateTime(2026, 11, 5, 12)),
      );
      expect(healed, isNull);
    });

    test('Gate：本地活跃证据 → 不得 skip（即便列表未标 pickedUp）', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.transit,
          userPickedUpAt: null,
          localActiveEvidence: true,
        ),
        isFalse,
      );
    });

    test('Gate：真已取 + 本地仍有旧在途轨迹 → 仍可 skip（不回滚真已取）', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.pickedUp,
          userPickedUpAt: DateTime(2026, 11, 5),
          localActiveEvidence: true,
        ),
        isTrue,
      );
    });

    test('coerceYield：enrich 吐 pickedUp 但本地活跃 → 回滚 transit', () {
      final local = fakeJt();
      final status = PddFalsePickupHeal.coerceYieldStatus(
        derived: PackageStatus.pickedUp,
        local: local,
      );
      expect(status, PackageStatus.transit);
    });

    test('coerceYield：真已取 → 保持 pickedUp', () {
      final local = fakeJt(pickedUpAt: DateTime(2026, 11, 5));
      final status = PddFalsePickupHeal.coerceYieldStatus(
        derived: PackageStatus.pickedUp,
        local: local,
      );
      expect(status, PackageStatus.pickedUp);
    });

    test('parsedTimeline 旧死穴：未排序时首节点是已下单；heal 不得再踩', () {
      final pkg = fakeJt();
      expect(pkg.parsedTimeline.first['tag'], '已下单');
      final healed = PddFalsePickupHeal.healMisfiledPickedUp(pkg);
      expect(healed!.status, PackageStatus.transit);
    });
  });


  group('P44 tip10 / P44-g：mismatch 保 traces + enrich 失败本地 heal', () {
    const jtTracking = 'JT5542922044377';
    const orderSn = '261103-181959473543156';
    const dirtyOrderSn = '261002-207827822983156';
    const oldestFirstJson = '['
        '{"tag":"已下单","time":"2026-11-03 10:00:00","text":"您已提交订单，等待系统确认"},'
        '{"tag":"运输中","time":"2026-11-05 02:00:00","text":"您的快件已到达【东莞虎门转运中心】"},'
        '{"tag":"运输中","time":"2026-11-05 02:02:00","text":"您的快件离开【东莞虎门转运中心】，已发往【邢台转运中心】客服电话：956025"}'
        ']';
    final now = DateTime(2026, 11, 5, 22, 30);

    Package fakeJt({DateTime? pickedUpAt}) {
      return Package(
        id: 'PDD_$orderSn',
        trackingNumber: jtTracking,
        courier: CourierType.jt,
        platform: 'pdd',
        description: pddTicketLatest,
        urgency: UrgencyLevel.normal,
        status: PackageStatus.pickedUp,
        addedAt: DateTime(2026, 11, 3),
        pickedUpAt: pickedUpAt,
        rawTimelineJson: oldestFirstJson,
      );
    }

    test('① mismatch + rawTraces → 仍建时间轴并 derive transit（不得 return null）', () {
      final dirtyDom = '极兔速递: JT0000000000000\n'
          '订单编号: $dirtyOrderSn\n'
          '已签收 2026-10-02 12:00:00\n'
          '快件已签收，签收人：代收\n';
      final rawTraces = [
        {
          'time': '2026-11-05 02:02:00',
          'info': pddTicketLatest,
          'status': 'TRANSPORT',
        },
        {
          'time': '2026-11-05 02:00:00',
          'info': '您的快件已到达【东莞虎门转运中心】',
          'status': 'TRANSPORT',
        },
      ];
      final r = PddH5Connector.parseLogisticsText(
        dirtyDom,
        orderSn: orderSn,
        rawTraces: rawTraces,
        fallbackTrackingNo: jtTracking,
        now: now,
      );
      expect(r, isNotNull, reason: 'mismatch 不得整包丢掉 rawTraces');
      expect(r!.status.isCompleted, isFalse);
      expect(r.status, PackageStatus.transit);
      final list = jsonDecode(r.rawTimelineJson!) as List;
      expect(list, isNotEmpty);
      expect(list.first['text'], contains('离开【东莞虎门转运中心】'));
    });

    test('①b mismatch 且无 rawTraces → null（失败，走 enrich 兜底）', () {
      final dirtyDom = '订单编号: $dirtyOrderSn\n已签收 2026-10-02 12:00:00\n快件已签收\n';
      final r = PddH5Connector.parseLogisticsText(
        dirtyDom,
        orderSn: orderSn,
        now: now,
      );
      expect(r, isNull);
    });

    test('② detail null 兜底：本地旧序时间轴假 pickedUp → yield transit', () {
      final local = fakeJt();
      final recovered = PddFalsePickupHeal.recoverAfterEnrichFailure(
        local: local,
        listBase: local.copyWith(status: PackageStatus.transit),
      );
      expect(recovered, isNotNull);
      expect(recovered!.status, PackageStatus.transit);
      expect(recovered.status.isCompleted, isFalse);
    });

    test('②b detail null 兜底：heal 吃不到轴时采信列表运送中', () {
      final local = Package(
        id: 'PDD_$orderSn',
        trackingNumber: jtTracking,
        courier: CourierType.jt,
        platform: 'pdd',
        description: '已取件',
        urgency: UrgencyLevel.normal,
        status: PackageStatus.pickedUp,
        addedAt: DateTime(2026, 11, 3),
        rawTimelineJson: null,
      );
      final listBase = local.copyWith(
        status: PackageStatus.transit,
        description: pddTicketLatest,
      );
      final recovered = PddFalsePickupHeal.recoverAfterEnrichFailure(
        local: local,
        listBase: listBase,
      );
      expect(recovered, isNotNull);
      expect(recovered!.status, PackageStatus.transit);
    });

    test('③ 真 pickedUpAt → recover 不回滚', () {
      final recovered = PddFalsePickupHeal.recoverAfterEnrichFailure(
        local: fakeJt(pickedUpAt: DateTime(2026, 11, 5, 12)),
        listBase: fakeJt().copyWith(status: PackageStatus.transit),
      );
      expect(recovered, isNull);
    });
  });

}
