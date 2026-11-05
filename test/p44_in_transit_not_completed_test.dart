// P44：在途/派送不得因订单侧宽「完成」进入「已完成」(pickedUp)。
// 本票：拼多多 / 极兔 JT5542922044377，最新「运输中 …离开【东莞虎门转运中心】…发往【邢台转运中心】」。
import 'package:flutter_test/flutter_test.dart';
import 'package:pickup_app/core/engine/logistics_status_engine.dart';
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

  group('P44 tip：已完成跳过同步闸门（禁拼「已取件」label）', () {
    test('列表描述含运输中 → 即使 status 已是 pickedUp 也不得跳过', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.pickedUp,
          listDescription: '运输中 $pddTicketLatest',
        ),
        isFalse,
      );
    });

    test('空列表描述的误标 pickedUp → 不得跳过（解开 Hive 锁死）', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.pickedUp,
          listDescription: '',
        ),
        isFalse,
      );
    });

    test('回归：旧 bug 路径「desc + 已取件 label」不得再被当成真签收而跳过', () {
      // 旧代码：listEvidence = '$desc ${status.label}' → classifyNode 命中「已取件」→ 永假回滚
      final poisoned = '运输中 $pddTicketLatest 已取件';
      expect(LogisticsStatusEngine.classifyNode(poisoned), LogisticsNodeAction.signed);
      // 新闸门只看 desc，不看 label
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.pickedUp,
          listDescription: '运输中 $pddTicketLatest',
        ),
        isFalse,
      );
    });

    test('列表物流真签收 → 仍可跳过', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.pickedUp,
          listDescription: '已签收，签收人：本人签收',
        ),
        isTrue,
      );
    });

    test('archived / rejected 仍跳过', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.archived,
          listDescription: '运输中 $pddTicketLatest',
        ),
        isTrue,
      );
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.rejected,
          listDescription: '',
        ),
        isTrue,
      );
    });

    test('活跃态不跳过', () {
      expect(
        PddCompletedSyncGate.shouldSkip(
          status: PackageStatus.transit,
          listDescription: '',
        ),
        isFalse,
      );
    });
  });

  group('P44 tip：误标 pickedUp + 最新运输中 → derive 回滚', () {
    test('Hive 已是 pickedUp、时间轴最新运输中 → transit（同步/启动自愈同源）', () {
      final derived = LogisticsStatusEngine.derive(
        events: [
          {'tag': pddTicketTag, 'time': '2026-11-05 02:02:00', 'text': pddTicketLatest},
        ],
        isOrderSigned: true, // 模拟 Hive 误标 / 订单侧宽签收
      );
      expect(derived.status, PackageStatus.transit);
      expect(derived.status.isCompleted, isFalse);
    });
  });
}
