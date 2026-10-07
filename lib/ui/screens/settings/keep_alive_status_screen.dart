/// 平台保活状态展示页面
///
/// 显示各平台的 Cookie 年龄、保活状态、健康度等信息
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../platform/keep_alive/keep_alive_service.dart';
import '../../../platform/keep_alive/keep_alive_scheduler.dart';

class KeepAliveStatusScreen extends ConsumerStatefulWidget {
  const KeepAliveStatusScreen({super.key});

  @override
  ConsumerState<KeepAliveStatusScreen> createState() => _KeepAliveStatusScreenState();
}

class _KeepAliveStatusScreenState extends ConsumerState<KeepAliveStatusScreen> {
  bool _isRefreshing = false;

  /// 手动触发保活
  Future<void> _performManualKeepAlive() async {
    setState(() => _isRefreshing = true);

    try {
      final service = ref.read(keepAliveServiceProvider);
      await service.performManualKeepAlive();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保活完成'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {}); // 刷新界面
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保活失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '未知';

    if (duration.inDays > 0) {
      return '${duration.inDays} 天前';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} 小时前';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes} 分钟前';
    } else {
      return '刚刚';
    }
  }

  Color _parseColor(String hexColor) {
    final hex = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(keepAliveServiceProvider);
    final allStatus = service.getAllStatus();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '平台保活状态',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _performManualKeepAlive,
              tooltip: '手动保活',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 说明文本
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF007AFF),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '保活机制定期访问平台保持登录态有效，减少重新登录次数',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 平台状态列表
          ...allStatus.map((status) => _buildPlatformCard(status)),

          const SizedBox(height: 20),

          // 保活设置
          _buildSettingsSection(),
        ],
      ),
    );
  }

  Widget _buildPlatformCard(Map<String, dynamic> status) {
    final platform = status['platform'] as String;
    final isBound = status['bound'] as bool;
    final cookieAge = status['cookieAge'] as Duration?;
    final lastKeepAlive = status['lastKeepAlive'] as DateTime?;
    final failureCount = status['failureCount'] as int;
    final health = status['health'] as String;

    // 平台显示名称
    final platformNames = {
      'taobao': '淘宝 / 天猫',
      'jd': '京东商城',
      'pdd': '拼多多',
    };
    final displayName = platformNames[platform] ?? platform;

    // 平台图标
    final platformIcons = {
      'taobao': Icons.shopping_bag_rounded,
      'jd': Icons.flash_on_rounded,
      'pdd': Icons.local_fire_department_rounded,
    };
    final icon = platformIcons[platform] ?? Icons.store_rounded;

    // 平台颜色
    final platformColors = {
      'taobao': const Color(0xFFFF5000),
      'jd': const Color(0xFFE1251B),
      'pdd': const Color(0xFFE02E24),
    };
    final brandColor = platformColors[platform] ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 平台头部
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: brandColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: brandColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isBound ? '已绑定' : '未绑定',
                        style: TextStyle(
                          fontSize: 13,
                          color: isBound ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                // 健康度徽章
                if (isBound && cookieAge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _parseColor(
                        KeepAliveScheduler.getCookieHealthColor(cookieAge),
                      ).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      health,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _parseColor(
                          KeepAliveScheduler.getCookieHealthColor(cookieAge),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 详细信息
          if (isBound) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInfoRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Cookie 年龄',
                    value: cookieAge != null ? '${cookieAge.inDays} 天' : '未知',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    icon: Icons.access_time_rounded,
                    label: '最近保活',
                    value: lastKeepAlive != null
                        ? _formatDuration(DateTime.now().difference(lastKeepAlive))
                        : '未执行',
                  ),
                  if (failureCount > 0) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      icon: Icons.error_outline_rounded,
                      label: '失败次数',
                      value: '$failureCount 次',
                      valueColor: Colors.red,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? const Color(0xFF1C1C1E),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '保活设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.schedule_rounded, color: Color(0xFF007AFF)),
            title: const Text('保活频率', style: TextStyle(fontSize: 14.5)),
            subtitle: const Text('根据 Cookie 年龄自动调整', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            onTap: () {
              // TODO: 打开保活频率设置对话框
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('保活频率'),
                  content: const Text(
                    '当前使用智能模式，根据 Cookie 年龄自动调整：\n\n'
                    '• 0-3 天：每 24 小时\n'
                    '• 4-7 天：每 12 小时\n'
                    '• 8-10 天：每 6 小时\n'
                    '• 11+ 天：每 4 小时',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
