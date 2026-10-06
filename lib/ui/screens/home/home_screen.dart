/// 现代化“在途优先”首页 - 集成流体动效、Hero仪表盘与二级完成面板
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/package_provider.dart';
import '../../../platform/connectors/connector_manager.dart';
import '../settings/settings_screen.dart';
import '../pdd/pdd_web_screen.dart';
import '../../../core/engine/station_grouping.dart';
import '../../../core/engine/platform_auth_status.dart' show kLoginExpiredSignals;
import '../../../core/models/package_status.dart';
import '../../components/platform_status_bar.dart';
import '../../providers/platform_auth_status_provider.dart';
import '../login/platform_login_flow.dart';
import 'widgets/pickup_widgets.dart';
import 'widgets/completed_packages_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _collapsedTransitCount = 3;

  /// 折叠起来的驿站分组（按组名记）
  final Set<String> _collapsedStations = {};
  bool _transitExpanded = false;
  bool _shipmentExpanded = false;

  Widget _sectionTitle(String title, int count, {Widget? trailing}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
        child: Row(
          children: [
            Text(
              '$title $count',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
            ),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
    );
  }

  List<Widget> _buildStationGroup(StationGroup group, DateTime now) {
    final collapsed = _collapsedStations.contains(group.name);
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: StationGroupHeader(
            group: group,
            collapsed: collapsed,
            onToggle: () => setState(() {
              collapsed ? _collapsedStations.remove(group.name) : _collapsedStations.add(group.name);
            }),
          ),
        ),
      ),
      if (!collapsed)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          sliver: SliverList.separated(
            itemCount: group.packages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => PickupCodeCard(
              key: ValueKey(group.packages[i].id),
              package: group.packages[i],
              now: now,
            ),
          ),
        ),
    ];
  }

  /// 三个平台都没绑定时的整页引导
  /// 三个平台都没绑定时的引导横幅。只是一条横幅，下面的包裹照常显示。
  Widget _buildBindBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '绑定拼多多 / 京东 / 淘宝，包裹自动出现在这里',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in kPlatforms)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    foregroundColor: p.brandColor,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => openPlatformLogin(context, ref,
                      platform: p.id, displayName: p.displayName, brandColor: p.brandColor),
                  child: Text('绑定${p.shortName}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 执行同步：首批在途件到达或首个通道完成即提前停转圈，后台静默继续抓取
  Future<void> _runSync() async {
    final manager = ref.read(connectorManagerProvider);
    final refreshCompleter = Completer<void>();

    final syncFuture = manager.syncAll(
      onEarlyProgress: () {
        if (!refreshCompleter.isCompleted) {
          refreshCompleter.complete();
        }
      },
    );

    syncFuture.whenComplete(() {
      if (!refreshCompleter.isCompleted) {
        refreshCompleter.complete();
      }
      if (!mounted) return;
      final issue = manager.lastIssue;
      if (issue != null) {
        final loginExpired = kLoginExpiredSignals.any(issue.contains);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(issue),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            persist: false,
            action: !loginExpired
                ? null
                : SnackBarAction(
                    label: '去重新登录',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                  ),
          ),
        );
      }
    });

    // 首批在途件到达即停圈，最长保护等待 3.5 秒
    final timeout = Future.delayed(const Duration(milliseconds: 3500));
    await Future.any([refreshCompleter.future, timeout]);
  }

  @override
  Widget build(BuildContext context) {
    final pendingPackages = ref.watch(pendingPackagesProvider);
    final completedPackages = ref.watch(completedPackagesProvider);
    final stationGroups = groupPackagesByStation(pendingPackages);
    final pickupCount = stationGroups.fold<int>(0, (n, g) => n + g.packages.length);
    // 待发货的还没出仓，不算在途，折叠成在途区底部一行（产品 10-07 定）。
    final inTransit = pendingPackages
        .where((p) => !isAwaitingPickup(p) && p.status != PackageStatus.pendingShipment)
        .toList();
    final awaitingShipment = pendingPackages.where((p) => p.status == PackageStatus.pendingShipment).toList();
    final allUnbound =
        kPlatforms.every((p) => ref.watch(platformAuthStatusProvider(p.id)) == PlatformAuthStatus.unbound);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final now = DateTime.now();
    final todayStr = '${now.month}月${now.day}日 星期${weekdays[now.weekday - 1]}';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: const Color(0xFF007AFF),
          onRefresh: () async {
            HapticFeedback.lightImpact();
            await _runSync();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // 顶栏 Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              todayStr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '取件助手',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1C1C1E),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              PddWebScreen.open(context);
                            },
                            icon: const Icon(
                              Icons.local_fire_department_rounded,
                              size: 20,
                              color: Color(0xFFE02E24),
                            ),
                            tooltip: '拼多多网页版 (内置商城)',
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SettingsScreen()),
                              );
                            },
                            icon: const Icon(Icons.tune_rounded, size: 20),
                            tooltip: '平台账号绑定与设置',
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              await _runSync();
                            },
                            icon: const Icon(Icons.sync_rounded, size: 20),
                            tooltip: '一键同步包裹',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ① 平台登录状态条
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: PlatformStatusBar(),
                ),
              ),

              if (allUnbound) SliverToBoxAdapter(child: _buildBindBanner()),
              ...[
                // ② 待取件（按驿站分组）
                _sectionTitle('待取件', pickupCount),
                if (stationGroups.isEmpty)
                  SliverToBoxAdapter(
                    child: _hint(pendingPackages.isEmpty ? '暂时没有要取的包裹，下拉可以同步' : '暂时没有要取的包裹'),
                  )
                else
                  for (final group in stationGroups) ..._buildStationGroup(group, now),

                // ③ 在途（底部折叠一行「N 件待发货」）
                if (inTransit.isNotEmpty || awaitingShipment.isNotEmpty) ...[
                  _sectionTitle(
                    '在途',
                    inTransit.length,
                    trailing: inTransit.length > _collapsedTransitCount
                        ? TextButton(
                            onPressed: () => setState(() => _transitExpanded = !_transitExpanded),
                            child: Text(_transitExpanded ? '收起' : '展开全部'),
                          )
                        : null,
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            for (final p
                                in (_transitExpanded ? inTransit : inTransit.take(_collapsedTransitCount)))
                              InTransitRow(package: p),
                            if (awaitingShipment.isNotEmpty) ...[
                              AwaitingShipmentRow(
                                count: awaitingShipment.length,
                                expanded: _shipmentExpanded,
                                onToggle: () => setState(() => _shipmentExpanded = !_shipmentExpanded),
                              ),
                              if (_shipmentExpanded)
                                for (final p in awaitingShipment) InTransitRow(package: p),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],

              // ④ 已取 / 已归档入口
              if (completedPackages.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF34C759)),
                        title: Text('已取 / 已归档 ${completedPackages.length}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          CompletedPackagesSheet.show(context);
                        },
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),
        ),
      ),
    );
  }
}
