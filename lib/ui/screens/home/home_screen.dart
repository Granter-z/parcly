/// 现代化「在途优先」首页 - 集成流体动效、Hero 仪表盘与二级完成面板
///
/// 改版要点：
/// - **去掉重复入口**。原先「拼多多」有两个入口（顶栏红色图标 + 下方横幅），
///   「已完成」也有两个（列表标题栏链接 + 右下悬浮按钮）——同一个意图放了两遍。
///   现在各留一个：拼多多只保留横幅（它自带说明，比一个裸图标可读），
///   已完成只保留列表标题栏链接（它就在列表旁边）。
/// - **同步反馈只留一个落点**。原先顶栏和 Hero 各有一个同步按钮，同步中的转圈与
///   「已同步」完成态却挂在 Hero 上，Hero 还要同时承担信息展示。现在同步统一在顶栏，
///   完成态跟着按钮走。
/// - **Hero 与空态互斥**。两者都在回答「现在有没有包裹」，同时出现是重复信息。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/package_provider.dart';
import '../../../core/engine/station_grouping.dart';
import '../../../app/hero_decision.dart';
import '../../../core/engine/platform_auth_status.dart'
    show kLoginExpiredSignals, PlatformAuthStatus;
import '../../../platform/connectors/connector_manager.dart';
import '../../../platform/sync/background_sync_service.dart';
import '../../../platform/keep_alive/keep_alive_controller.dart';
import '../../components/glass_backdrop.dart';
import '../../components/glass_surface.dart';
import '../../theme/glass_tokens.dart';
import '../../components/platform_status_bar.dart';
import '../../constants/app_constants.dart';
import '../../providers/platform_auth_status_provider.dart';
import '../../theme/motion.dart';
import '../login/platform_login_flow.dart';
import '../settings/settings_screen.dart';
import '../pdd/pdd_web_screen.dart';
import 'widgets/animated_package_list.dart';
import 'widgets/hero_stats_dashboard.dart';
import 'widgets/completed_packages_sheet.dart';
import 'widgets/station_group_header.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  BackgroundSyncService? _backgroundSyncService;

  /// 同步中的图标旋转。同步按钮是页面唯一的同步入口，转圈挂在这里。
  late final AnimationController _spinController;

  /// 同步刚结束时短暂展示「已同步」完成态。
  bool _justSynced = false;
  Timer? _justSyncedTimer;

  /// 折叠起来的取件点分组（按组名记）。
  final Set<String> _collapsedStations = {};

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // 延迟初始化后台同步服务和保活服务（等待 ref 可用）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _backgroundSyncService = BackgroundSyncService(ref);
      _backgroundSyncService!.initialize();

      // 启动前台保活（进程外续期由 WorkManager 承担）
      ref.read(keepAliveControllerProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    _justSyncedTimer?.cancel();
    _spinController.dispose();
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
        final loginExpired = kLoginExpiredSignals.any(issue.contains);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(issue),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            // Flutter 3.47：有 action 时 persist 默认 true，会一直挂着；失败提示应自动消失。
            persist: false,
            action: loginExpired
                ? SnackBarAction(
                    label: '去重新登录',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  )
                : SnackBarAction(
                    label: '重试',
                    onPressed: () {
                      if (mounted) _runSync();
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

  /// 同步由 true 落回 false 时，闪一次完成态
  void _flashSynced() {
    _justSyncedTimer?.cancel();
    setState(() => _justSynced = true);
    _justSyncedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _justSynced = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stationGroups = ref.watch(groupedPendingPackagesProvider);
    final inTransitPackages = ref.watch(inTransitPackagesProvider);
    final completedPackages = ref.watch(completedPackagesProvider);
    final decision = ref.watch(heroDecisionProvider);
    final isSyncing = ref.watch(syncStateProvider);
    // 全部未绑定只加横幅，绝不整页盖住本地包裹（#9 修好后 #15 曾丢掉状态条，这里一并恢复）。
    final allUnbound = kPlatforms.every(
      (p) =>
          ref.watch(platformAuthStatusProvider(p.id)) ==
          PlatformAuthStatus.unbound,
    );

    ref.listen<bool>(syncStateProvider, (previous, next) {
      if (previous == true && next == false) _flashSynced();
    });

    if (isSyncing) {
      // 转圈是「正在工作」的反馈，属于有动机的循环；系统要求移除动画时不转。
      if (!_spinController.isAnimating && !Motion.reduce(context)) {
        _spinController.repeat();
      }
    } else {
      if (_spinController.isAnimating) _spinController.stop();
    }

    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final now = DateTime.now();
    final todayStr = '${now.month}月${now.day}日 星期${weekdays[now.weekday - 1]}';
    final pickupCount = stationGroups.fold<int>(
      0,
      (sum, g) => sum + g.packages.length,
    );
    final hasPending = pickupCount > 0 || inTransitPackages.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const GlassBackdrop(),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.primaryStrong,
              backgroundColor: AppColors.surface,
              onRefresh: () async {
                HapticFeedback.lightImpact();
                await _runSync();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(todayStr, isSyncing)),

                  // ① 平台登录状态条（需重登 / 同步失败 / 去绑定）
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        AppSpacing.sm,
                      ),
                      child: PlatformStatusBar(),
                    ),
                  ),

                  // 全部未绑定：横幅引导，本地包裹仍在下面
                  if (allUnbound)
                    const SliverToBoxAdapter(child: _BindBanner()),

                  // Hero：有在途件才出现，与下方空态互斥
                  if (hasPending)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.xs,
                          AppSpacing.xl,
                          AppSpacing.lg,
                        ),
                        child: HeroStatsDashboard(),
                      ),
                    ),

                  // 拼多多内置商城：全页唯一入口
                  SliverToBoxAdapter(child: _buildPddEntry()),

                  // 列表标题栏 + 构成明细
                  SliverToBoxAdapter(
                    child: _buildListHeader(
                      pickupCount,
                      inTransitPackages.length,
                      completedPackages.length,
                      decision,
                    ),
                  ),

                  // 空状态：仅在无待取/在途时出现
                  SliverToBoxAdapter(
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.normal),
                      switchInCurve: Motion.standard,
                      switchOutCurve: Motion.exit,
                      transitionBuilder: (child, animation) => SizeTransition(
                        sizeFactor: animation,
                        axisAlignment: -1.0,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: hasPending
                          ? const SizedBox.shrink(
                              key: ValueKey('packages_present'),
                            )
                          : _buildEmptyState(),
                    ),
                  ),

                  // ② 待取件：按取件点分组（arrivedAt 排序 / 快过期由卡片读）
                  if (pickupCount > 0) ...[
                    SliverToBoxAdapter(
                      child: _sectionTitle('待取件', pickupCount),
                    ),
                    for (final group in stationGroups)
                      ..._stationGroupSlivers(group),
                  ],

                  // ③ 在途：扁平列表，不按取件点分组
                  if (inTransitPackages.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _sectionTitle('在途', inTransitPackages.length),
                    ),
                    AnimatedPackageList(
                      packages: inTransitPackages,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.xs,
                        AppSpacing.xl,
                        AppSpacing.lg,
                      ),
                    ),
                  ],

                  // 底部留白
                  if (hasPending)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: AppSpacing.xxl +
                            MediaQuery.paddingOf(context).bottom,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分区小标题（待取件 / 在途）。
  Widget _sectionTitle(String label, int count) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Text('$label ($count)', style: text.titleMedium),
    );
  }

  /// 一个取件点分组：可折叠标题 + 组内卡片列表。
  List<Widget> _stationGroupSlivers(StationGroup group) {
    final collapsed = _collapsedStations.contains(group.name);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: StationGroupHeader(
            group: group,
            collapsed: collapsed,
            onToggle: () {
              setState(() {
                if (collapsed) {
                  _collapsedStations.remove(group.name);
                } else {
                  _collapsedStations.add(group.name);
                }
              });
            },
          ),
        ),
      ),
      if (!collapsed)
        AnimatedPackageList(
          key: ValueKey('station_${group.name}'),
          packages: group.packages,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
        ),
    ];
  }

  /// 顶栏：日期 + 应用名 + 页面级动作（同步 / 设置）。
  ///
  /// 动作只留两个。原先第三个是拼多多的红色火苗图标，与下方横幅同义。
  Widget _buildHeader(String todayStr, bool isSyncing) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(todayStr, style: text.bodySmall),
              const SizedBox(height: AppSpacing.xxs),
              Text('取件助手', style: text.headlineLarge),
            ],
          ),
          Row(
            children: [
              _buildSyncAction(isSyncing),
              const SizedBox(width: AppSpacing.sm),
              _GlassIconButton(
                tooltip: '平台账号绑定与设置',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                icon: const Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 同步按钮：图标在「同步 / 同步中 / 已同步」之间切换。
  Widget _buildSyncAction(bool isSyncing) {
    final Widget icon;
    if (_justSynced) {
      icon = const Icon(
        Icons.check_circle_rounded,
        size: 20,
        color: AppColors.statusPickedUp,
      );
    } else {
      icon = RotationTransition(
        turns: _spinController,
        child: const Icon(Icons.sync_rounded, size: 20),
      );
    }

    return _GlassIconButton(
      onPressed: isSyncing
          ? null
          : () async {
              HapticFeedback.lightImpact();
              await _runSync();
            },
      icon: icon,
      tooltip: _justSynced ? '已同步' : (isSyncing ? '同步中...' : '一键同步包裹'),
    );
  }

  /// 拼多多内置商城入口横幅。
  ///
  /// 品牌红只用在图标上（非文字元素）；文案全部走令牌。
  /// 原先 11px 红字压 8% 红底只有 3.80:1，且"免App防互踢"这种微型标签
  /// 读起来像补丁 —— 现在并进说明句里。
  Widget _buildPddEntry() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            PddWebScreen.open(context);
          },
          borderRadius: GlassTokens.radiusContentAll,
          child: ContentSurface(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            borderRadius: GlassTokens.radiusContentAll,
            borderColor: const Color(0xFFE02E24).withValues(alpha: 0.22),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE02E24),
                    borderRadius: AppRadius.xsAll,
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '拼多多内置商城',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: AppSpacing.xxs),
                      Text(
                        '免 App 防互踢，下单后包裹与取件码自动同步',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 列表标题栏：标题 + 件数，第二行是构成明细。
  ///
  /// 明细原先挤在 Hero 里（三个数字 + 两根竖分隔线），把 Hero 变成了功能清单。
  /// 它描述的是列表构成，放在列表标题下更贴切。
  Widget _buildListHeader(
    int pickupCount,
    int inTransitCount,
    int completedCount,
    HeroDecision decision,
  ) {
    final parts = <String>[
      if (pickupCount > 0) '$pickupCount 件待取',
      if (decision.deliveringCount > 0) '${decision.deliveringCount} 件派送中',
      if (decision.transitCount > 0) '${decision.transitCount} 件在途',
      if (decision.pendingShipmentCount > 0)
        '${decision.pendingShipmentCount} 件待发货',
    ];
    final text = Theme.of(context).textTheme;
    final total = pickupCount + inTransitCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('待取与在途快件 ($total)', style: text.titleLarge),
              if (completedCount > 0)
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    CompletedPackagesSheet.show(context);
                  },
                  borderRadius: AppRadius.xsAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '已完成 ($completedCount)',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.primaryStrong,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.primaryStrong,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            // 用间距分组，不用中点分隔符堆一行
            Text(parts.join('    '), style: text.bodySmall),
          ],
        ],
      ),
    );
  }

  /// 无在途件的空状态卡片（供 AnimatedSwitcher 做进出场）
  Widget _buildEmptyState() {
    final text = Theme.of(context).textTheme;

    return Padding(
      key: const ValueKey('pending_empty_state'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: ContentSurface(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        borderRadius: GlassTokens.radiusAll,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('暂无待取快件', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              '下拉同步，或前往平台绑定页聚合在途包裹与取件码',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.tonalIcon(
              onPressed: () async {
                HapticFeedback.lightImpact();
                await _runSync();
              },
              icon: const Icon(Icons.sync_rounded, size: 16),
              label: const Text('一键同步'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏圆形玻璃按钮（同步 / 设置）。
class _GlassIconButton extends StatelessWidget {
  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: GlassChrome(
            padding: const EdgeInsets.all(10),
            borderRadius: AppRadius.pillAll,
            fill: GlassTokens.fill,
            blurSigma: GlassTokens.blurSigmaSoft,
            boxShadow: const [],
            child: SizedBox(width: 24, height: 24, child: Center(child: icon)),
          ),
        ),
      ),
    );
  }
}

/// 三个平台都没绑定时的引导横幅。只是一条横幅，下面的包裹照常显示。
class _BindBanner extends ConsumerWidget {
  const _BindBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: ContentSurface(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        borderRadius: GlassTokens.radiusAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '绑定拼多多 / 京东 / 淘宝，包裹自动出现在这里',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final p in kPlatforms)
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      foregroundColor: p.brandColor,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => openPlatformLogin(
                      context,
                      ref,
                      platform: p.id,
                      displayName: p.displayName,
                      brandColor: p.brandColor,
                    ),
                    child: Text('绑定${p.shortName}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
