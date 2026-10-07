/// 现代化“在途优先”首页 - 集成流体动效、Hero仪表盘与二级完成面板
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/package_provider.dart';
import '../../../platform/connectors/connector_manager.dart';
import '../../../platform/sync/background_sync_service.dart';
import '../../../platform/keep_alive/keep_alive_service.dart';
import '../../theme/motion.dart';
import '../settings/settings_screen.dart';
import '../pdd/pdd_web_screen.dart';
import 'widgets/animated_package_list.dart';
import 'widgets/hero_stats_dashboard.dart';
import 'widgets/completed_packages_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  BackgroundSyncService? _backgroundSyncService;

  @override
  void initState() {
    super.initState();
    // 延迟初始化后台同步服务和保活服务（等待 ref 可用）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _backgroundSyncService = BackgroundSyncService(ref);
      _backgroundSyncService!.initialize();

      // 初始化保活服务（通过 Provider 自动启动）
      ref.read(keepAliveServiceProvider);
    });
  }

  @override
  void dispose() {
    _backgroundSyncService?.dispose();
    super.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(issue),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
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

  /// 无在途件的空状态卡片（供 AnimatedSwitcher 做进出场）
  Widget _buildEmptyState() {
    return Container(
      key: const ValueKey('pending_empty_state'),
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 56,
            color: Color(0xFF8E8E93),
          ),
          const SizedBox(height: 12),
          const Text(
            '暂无待取快件',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '下拉同步，或前往平台绑定页聚合在途包裹与取件码',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF8E8E93),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: () => _runSync(),
            icon: const Icon(Icons.sync_rounded, size: 16),
            label: const Text('一键同步'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingPackages = ref.watch(pendingPackagesProvider);
    final completedPackages = ref.watch(completedPackagesProvider);
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            todayStr,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '取件助手',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1C1C1E),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
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

              // 顶部 Hero 统计卡片
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: HeroStatsDashboard(),
                ),
              ),

              // 拼多多内置商城快捷入口
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      PddWebScreen.open(context);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFE02E24).withValues(alpha: 0.08),
                            const Color(0xFFFF5722).withValues(alpha: 0.03),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFE02E24).withValues(alpha: 0.22),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE02E24),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.local_fire_department_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '拼多多 · 内置商城',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1C1C1E),
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      '免App防互踢',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFE02E24),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '直接浏览下单，在途包裹与取件码自动同步',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF8E8E93),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 13,
                            color: Color(0xFFE02E24),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 列表标题栏
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '待取与在途快件 (${pendingPackages.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C2C2E),
                        ),
                      ),
                      if (completedPackages.isNotEmpty)
                        InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            CompletedPackagesSheet.show(context);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  '已完成 (${completedPackages.length})',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF007AFF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: Color(0xFF007AFF),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // 空状态：仅在无在途件时出现，与列表之间做淡入淡出 + 高度过渡
              SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: Motion.normal,
                  switchInCurve: Motion.standard,
                  switchOutCurve: Motion.exit,
                  transitionBuilder: (child, animation) => SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1.0,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: pendingPackages.isEmpty
                      ? _buildEmptyState()
                      : const SizedBox.shrink(key: ValueKey('packages_present')),
                ),
              ),

              // 在途包裹主列表：插入 / 移除 / 重排均带过渡动画
              AnimatedPackageList(packages: pendingPackages),
            ],
          ),
        ),
      ),
      // 右下角“已完成”悬浮胶囊
      floatingActionButton: completedPackages.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                HapticFeedback.lightImpact();
                CompletedPackagesSheet.show(context);
              },
              backgroundColor: const Color(0xFF1C1C1E),
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                '已完成 ${completedPackages.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            )
          : null,
    );
  }
}
