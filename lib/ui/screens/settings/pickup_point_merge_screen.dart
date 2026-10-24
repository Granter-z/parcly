/// 设置「取件点合并」：声明多名同一物理点（P28-d2）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/station_grouping.dart';
import '../../providers/package_provider.dart';
import '../../providers/pickup_point_alias_provider.dart';

class PickupPointMergeScreen extends ConsumerWidget {
  const PickupPointMergeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliases = ref.watch(pickupPointAliasesProvider);
    final entries = aliases.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '取件点合并',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          _showAddDialog(context, ref);
        },
        icon: const Icon(Icons.merge_type_rounded),
        label: const Text('添加合并'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Text(
            '把同一地点的不同叫法合并成一组。未声明的名字各自独立；不会改包裹原始数据。',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.place_outlined, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  Text(
                    '还没有合并规则',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '点右下角「添加合并」，从已有取件点名里选两个，声明它们是同一点。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Text(
                        entries[i].key,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '显示为「${entries[i].value}」',
                                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          await ref
                              .read(pickupPointAliasesProvider.notifier)
                              .removeAlias(entries[i].key);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final packages = ref.read(packageListProvider);
    final names = <String>{};
    for (final p in packages) {
      final s = (p.stationName ?? '').trim();
      if (s.isEmpty || isUnknownStationLabel(s)) continue;
      names.add(s);
    }
    final sorted = names.toList()..sort();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddMergeSheet(knownNames: sorted),
    );
  }
}

class _AddMergeSheet extends ConsumerStatefulWidget {
  const _AddMergeSheet({required this.knownNames});

  final List<String> knownNames;

  @override
  ConsumerState<_AddMergeSheet> createState() => _AddMergeSheetState();
}

class _AddMergeSheetState extends ConsumerState<_AddMergeSheet> {
  String? _nameA;
  String? _nameB;
  String? _canonical;
  final _typedA = TextEditingController();
  final _typedB = TextEditingController();
  bool _useTyped = false;

  @override
  void initState() {
    super.initState();
    _useTyped = widget.knownNames.length < 2;
  }

  @override
  void dispose() {
    _typedA.dispose();
    _typedB.dispose();
    super.dispose();
  }

  String get _resolvedA => _useTyped ? _typedA.text.trim() : (_nameA ?? '').trim();
  String get _resolvedB => _useTyped ? _typedB.text.trim() : (_nameB ?? '').trim();

  void _syncCanonicalDefault() {
    final a = _resolvedA;
    final b = _resolvedB;
    if (a.isEmpty || b.isEmpty) return;
    final preferred = preferredCanonicalName(a, b);
    if (_canonical != a && _canonical != b) {
      setState(() => _canonical = preferred);
    }
  }

  Future<void> _submit() async {
    final a = _resolvedA;
    final b = _resolvedB;
    if (a.isEmpty || b.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写两个取件点名'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (normalizeStationName(a) == normalizeStationName(b)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两个名字规范化后相同，无需合并'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final canonical = (_canonical ?? preferredCanonicalName(a, b)).trim();
    if (canonical.isEmpty) return;

    // 较短/另一名映射到规范名；若用户选的规范名等于 B，则 A→B，反之亦然。
    // 两边都可映射到同一规范名（多对一）。
    final notifier = ref.read(pickupPointAliasesProvider.notifier);
    if (normalizeStationName(a) != normalizeStationName(canonical)) {
      await notifier.setAlias(a, canonical);
    }
    if (normalizeStationName(b) != normalizeStationName(canonical)) {
      await notifier.setAlias(b, canonical);
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已合并：显示为「$canonical」'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              '声明同一取件点',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '选两个名字（或手输），再选首页组头要显示的规范名。',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            if (!_useTyped && widget.knownNames.isNotEmpty) ...[
              _label('名称 A'),
              _nameChips(
                selected: _nameA,
                onSelect: (v) {
                  setState(() {
                    _nameA = v;
                    _canonical = null;
                  });
                  _syncCanonicalDefault();
                },
              ),
              const SizedBox(height: 12),
              _label('名称 B'),
              _nameChips(
                selected: _nameB,
                onSelect: (v) {
                  setState(() {
                    _nameB = v;
                    _canonical = null;
                  });
                  _syncCanonicalDefault();
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _useTyped = true),
                  child: const Text('改用手输名称'),
                ),
              ),
            ] else ...[
              _label('名称 A'),
              TextField(
                controller: _typedA,
                decoration: _inputDeco('例如：北门店'),
                onChanged: (_) {
                  setState(() => _canonical = null);
                  _syncCanonicalDefault();
                },
              ),
              const SizedBox(height: 12),
              _label('名称 B'),
              TextField(
                controller: _typedB,
                decoration: _inputDeco('例如：菜鸟驿站（北门）'),
                onChanged: (_) {
                  setState(() => _canonical = null);
                  _syncCanonicalDefault();
                },
              ),
              if (widget.knownNames.length >= 2)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _useTyped = false),
                    child: const Text('改从已有取件点选择'),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            _label('规范显示名（组头）'),
            if (_resolvedA.isNotEmpty && _resolvedB.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in {_resolvedA, _resolvedB})
                    ChoiceChip(
                      label: Text(name),
                      selected: (_canonical ?? preferredCanonicalName(_resolvedA, _resolvedB)) == name,
                      onSelected: (_) => setState(() => _canonical = name),
                    ),
                ],
              )
            else
              Text('先填两个名称', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('保存合并'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF6F7F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _nameChips({
    required String? selected,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final n in widget.knownNames)
          ChoiceChip(
            label: Text(n, overflow: TextOverflow.ellipsis),
            selected: selected == n,
            onSelected: (_) => onSelect(n),
          ),
      ],
    );
  }
}
