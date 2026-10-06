/// 设置与多平台账号管理界面
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/storage/platform_auth_store.dart';
import '../../../platform/connectors/connector_manager.dart';
import '../../providers/package_provider.dart';
import '../login/platform_login_screen.dart';
import '../pdd/pdd_web_screen.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _authStore = PlatformAuthStore();

  @override
  Widget build(BuildContext context) {
    // 监听同步状态：后台同步结束（如检测到登录失效）后立即刷新卡片标签
    ref.watch(syncStateProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '设置与平台绑定',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // ── Section 1: 平台账号绑定 ────────────────────────
          _buildSectionHeader('电商平台账号绑定', '绑定后下拉即可聚合多端在途包裹与取件码'),
          const SizedBox(height: 10),
          _buildPlatformCard(
            platform: 'taobao',
            displayName: '淘宝 / 天猫',
            subtitle: '支持菜鸟驿站取件码及在途商品图文',
            icon: Icons.shopping_bag_rounded,
            brandColor: const Color(0xFFFF5000),
          ),
          const SizedBox(height: 12),
          _buildPlatformCard(
            platform: 'jd',
            displayName: '京东商城',
            subtitle: '支持自营物流、便民柜自提码与在途配送',
            icon: Icons.flash_on_rounded,
            brandColor: const Color(0xFFE1251B),
          ),
          const SizedBox(height: 12),
          _buildPlatformCard(
            platform: 'pdd',
            displayName: '拼多多',
            subtitle: '内置移动端商城：免App防互踢，直接浏览下单并自动同步在途包裹',
            icon: Icons.local_fire_department_rounded,
            brandColor: const Color(0xFFE02E24),
          ),

          const SizedBox(height: 28),

          // ── Section 3: 数据与调试 ─────────────────────────
          _buildSectionHeader('数据管理', '本地缓存与数据同步控制'),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync_rounded, color: Color(0xFF007AFF)),
                  title: const Text('从已绑平台同步', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  subtitle: const Text('立即检查并聚合在途订单', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                    await ref.read(connectorManagerProvider).syncAll();
                    if (context.mounted) {
                      final issue = ref.read(connectorManagerProvider).lastIssue;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(issue ?? '已同步最新物流状态'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                // 同步诊断（含淘宝原始返回采集）只在调试版出现
                if (kDebugMode) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.bug_report_rounded, color: Color(0xFF8E8E93)),
                    title: const Text('同步诊断', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                    subtitle: const Text('淘宝原始返回采集与导出、拼多多会话诊断', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DiagnosticsScreen()));
                    },
                  ),
                ],
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded, color: Colors.redAccent),
                  title: const Text('清空所有包裹数据', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.redAccent)),
                  subtitle: const Text('清理本地数据库中的所有包裹', style: TextStyle(fontSize: 12)),
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('确认清空所有数据？'),
                        content: const Text('此操作将删除所有本地存储的待取与历史包裹，平台绑定关系将保留。'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('确认清空'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      ref.read(packageListProvider.notifier).clearAll();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空所有包裹数据')));
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildPlatformCard({
    required String platform,
    required String displayName,
    required String subtitle,
    required IconData icon,
    required Color brandColor,
  }) {
    final isBound = _authStore.isBound(platform);
    final liveIssue = ref.watch(connectorManagerProvider).lastIssue ?? '';
    final isExpired = isBound &&
        (_authStore.isExpired(platform) || liveIssue.contains(_issueKeyword(platform)));
    final boundTime = _authStore.getBoundTime(platform);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpired
              ? Colors.orange.withValues(alpha: 0.4)
              : (isBound ? brandColor.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.05)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: brandColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: brandColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isExpired
                            ? Colors.orange.withValues(alpha: 0.15)
                            : (isBound
                                ? const Color(0xFF34C759).withValues(alpha: 0.12)
                                : Colors.grey.withValues(alpha: 0.12)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isExpired ? '已失效' : (isBound ? '已绑定' : '未绑定'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isExpired
                              ? Colors.orange.shade800
                              : (isBound ? const Color(0xFF34C759) : Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isExpired
                      ? '登录已失效，请点击重新授权'
                      : (isBound && boundTime != null
                          ? '已于 ${boundTime.month}月${boundTime.day}日 授权绑定'
                          : subtitle),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isExpired ? Colors.orange.shade800 : Colors.grey.shade600,
                  ),
                ),
                if (_riskNoteFor(platform) != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 13, color: Colors.orange.shade700),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _riskNoteFor(platform)!,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (platform == 'pdd')
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonal(
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    await PddWebScreen.open(context);
                    if (mounted) setState(() {});
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: brandColor.withValues(alpha: 0.12),
                    foregroundColor: brandColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('打开商城', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  onSelected: (val) async {
                    if (val == 'relogin') {
                      await PddWebScreen.open(context, url: 'https://mobile.yangkeduo.com/login.html');
                      if (mounted) setState(() {});
                    } else if (val == 'unbind') {
                      await _authStore.unbind(platform);
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已解除 $displayName 绑定')),
                        );
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'relogin', child: Text('重新登录')),
                    if (isBound)
                      const PopupMenuItem(
                        value: 'unbind',
                        child: Text('解除绑定', style: TextStyle(color: Colors.red)),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.more_horiz_rounded, size: 16),
                  ),
                ),
              ],
            )
          else if (isBound)
            if (isExpired)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _openLogin(platform: platform, displayName: displayName, brandColor: brandColor),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.orange.shade50,
                      foregroundColor: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('去授权', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 2),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onSelected: (val) async {
                      if (val == 'unbind') {
                        await _authStore.unbind(platform);
                        if (mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已解除 $displayName 绑定')),
                          );
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'unbind',
                        child: Text('解除绑定', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.more_vert, size: 16),
                    ),
                  ),
                ],
              )
            else
              PopupMenuButton<String>(
              onSelected: (val) async {
                if (val == 'cainiao') {
                  await PlatformLoginScreen.show(
                    context,
                    platform: 'taobao',
                    displayName: '菜鸟驿站',
                    brandColor: const Color(0xFF00B578),
                    initialUrl: 'https://page.cainiao.com/cn-yz/station-activity/index.html',
                  );
                  if (mounted) {
                    ref.read(connectorManagerProvider).syncAll();
                  }
                } else if (val == 'relogin') {
                  await _openLogin(platform: platform, displayName: displayName, brandColor: brandColor);
                } else if (val == 'unbind') {
                  await _authStore.unbind(platform);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已解除 $displayName 绑定')),
                    );
                  }
                }
              },
              itemBuilder: (_) => [
                if (platform == 'taobao')
                  const PopupMenuItem(
                    value: 'cainiao',
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF00B578)),
                        SizedBox(width: 8),
                        Text('打开菜鸟驿站'),
                      ],
                    ),
                  ),
                const PopupMenuItem(value: 'relogin', child: Text('重新登录')),
                const PopupMenuItem(value: 'unbind', child: Text('解除绑定', style: TextStyle(color: Colors.red))),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('管理', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Icon(Icons.arrow_drop_down_rounded, size: 16),
                  ],
                ),
              ),
            )
          else
            FilledButton.tonal(
              onPressed: () async {
                HapticFeedback.lightImpact();
                await _openLogin(platform: platform, displayName: displayName, brandColor: brandColor);
              },
              style: FilledButton.styleFrom(
                backgroundColor: brandColor.withValues(alpha: 0.12),
                foregroundColor: brandColor,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('去登录', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  /// 各平台的会话冲突风险提示（null 表示无已知风险）
  String? _riskNoteFor(String platform) {
    if (platform.toLowerCase() == 'pdd') {
      return '说明：本应用已内置拼多多移动端。直接在此浏览下单可免受双端互踢影响，包裹与取件码自动同步。';
    }
    return null;
  }

  /// 登录态失效提示在同步问题上对应的平台关键词
  String _issueKeyword(String platform) {
    switch (platform.toLowerCase()) {
      case 'taobao':
      case 'tmall':
        return '淘宝';
      case 'jd':
        return '京东';
      case 'pdd':
        return '拼多多';
      default:
        return platform;
    }
  }

  /// 平台登录入口：拼多多内置移动网页端直接打开，其他平台使用专属登录
  Future<void> _openLogin({
    required String platform,
    required String displayName,
    required Color brandColor,
  }) async {
    if (platform.toLowerCase() == 'pdd') {
      await PddWebScreen.open(context, url: 'https://mobile.yangkeduo.com/login.html');
      if (mounted) setState(() {});
      return;
    }

    if (!mounted) return;
    final ok = await PlatformLoginScreen.show(
      context,
      platform: platform,
      displayName: displayName,
      brandColor: brandColor,
    );
    if (ok == true && mounted) {
      setState(() {});
      // 授权成功后清理旧失效提示并立即同步：刷新状态并补齐取件码
      final manager = ref.read(connectorManagerProvider);
      manager.clearLastIssue();
      manager.syncAll();
    }
  }
}
