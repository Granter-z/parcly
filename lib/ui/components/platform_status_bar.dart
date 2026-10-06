import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/connectors/connector_manager.dart';
import '../../platform/storage/platform_auth_store.dart';
import '../providers/platform_auth_status_provider.dart';
import '../screens/login/platform_login_flow.dart';

/// 首页顶部的平台登录状态条（P4，见 docs/pickup_app-界面.md 第 2 节）。
///
/// - 有平台需重登：整条淡红底，不能关；点那个平台直接进登录页。
/// - 全部正常：缩成一行小字，不抢待取件的位置。
/// - 未绑定：灰色「去绑定」。
/// - 同步中：圆点换成转圈，不响应点击。
class PlatformStatusBar extends ConsumerWidget {
  const PlatformStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(syncStateProvider);
    final statuses = {
      for (final p in kPlatforms) p.id: ref.watch(platformAuthStatusProvider(p.id)),
    };
    final anyExpired = statuses.values.contains(PlatformAuthStatus.needsRelogin);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: anyExpired ? 8 : 4),
      decoration: BoxDecoration(
        color: anyExpired ? const Color(0xFFFFEBEE) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final p in kPlatforms)
            _PlatformChip(
              info: p,
              status: statuses[p.id]!,
              syncing: syncing,
              emphasized: anyExpired,
            ),
        ],
      ),
    );
  }
}

class _PlatformChip extends ConsumerWidget {
  final PlatformInfo info;
  final PlatformAuthStatus status;
  final bool syncing;
  final bool emphasized;

  const _PlatformChip({
    required this.info,
    required this.status,
    required this.syncing,
    required this.emphasized,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSize = emphasized ? 13.0 : 12.0;
    late final Widget dot;
    late final String label;
    late final Color textColor;

    switch (status) {
      case PlatformAuthStatus.needsRelogin:
        dot = _dot(const Color(0xFFE53935));
        label = '${info.shortName} 需重登';
        textColor = const Color(0xFFC62828);
      case PlatformAuthStatus.unbound:
        dot = Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade500),
          ),
        );
        label = '${info.shortName} 去绑定';
        textColor = Colors.grey.shade600;
      case PlatformAuthStatus.ok:
        dot = syncing
            ? SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: info.brandColor),
              )
            // 正常用绿勾，不用品牌色：拼多多/京东的品牌红和「需重登」的红点太像。
            : const Icon(Icons.check_circle, size: 12, color: Color(0xFF2E7D32));
        label = info.shortName;
        textColor = Colors.grey.shade800;
    }

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: syncing ? null : () => _onTap(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot,
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  color: textColor,
                  fontWeight: status == PlatformAuthStatus.needsRelogin ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    if (status == PlatformAuthStatus.ok) {
      _showPlatformSheet(context, ref);
      return;
    }
    final ok = await openPlatformLogin(
      context,
      ref,
      platform: info.id,
      displayName: info.displayName,
      brandColor: info.brandColor,
    );
    if (ok && context.mounted && status == PlatformAuthStatus.needsRelogin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${info.shortName}已重新登录，正在同步')),
      );
    }
  }

  void _showPlatformSheet(BuildContext context, WidgetRef ref) {
    final bound = PlatformAuthStore().getBoundTime(info.id);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.displayName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                bound == null ? '登录正常' : '登录正常 · ${_formatDate(bound)} 绑定',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('立即同步这个平台'),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    syncSinglePlatform(ref, info.id);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
