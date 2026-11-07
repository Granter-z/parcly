/// 在途列表只持有呈现状态；业务数据和排序仍由上游提供。
library;

import 'package:flutter/material.dart';

import '../../../../core/models/package.dart';
import '../../../theme/motion.dart';
import 'modern_package_card.dart';

class AnimatedPackageList extends StatefulWidget {
  final List<Package> packages;
  final EdgeInsetsGeometry padding;

  const AnimatedPackageList({
    super.key,
    required this.packages,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 100),
  });

  @override
  State<AnimatedPackageList> createState() => _AnimatedPackageListState();
}

class _PresentationEntry {
  Package package;
  final AnimationController controller;
  bool present = true;
  int generation = 0;
  String? exitSuccessorId;

  _PresentationEntry(this.package, this.controller);
}

class _AnimatedPackageListState extends State<AnimatedPackageList>
    with TickerProviderStateMixin {
  final _entries = <String, _PresentationEntry>{};
  List<String> _renderIds = [];
  Map<String, int> _indices = {};
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _assertUnique(widget.packages);
    for (final package in widget.packages) {
      _entries[package.id] = _entry(package, 1);
    }
    _order(widget.packages.map((p) => p.id).toList());
  }

  void _assertUnique(List<Package> packages) {
    assert(packages.map((p) => p.id).toSet().length == packages.length,
        'AnimatedPackageList requires unique package IDs');
  }

  _PresentationEntry _entry(Package package, double value) =>
      _PresentationEntry(
          package, AnimationController(vsync: this, value: value));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = Motion.reduce(context);
    if (reduced == _reduced) return;
    _reduced = reduced;
    if (reduced) _settle();
  }

  @override
  void didUpdateWidget(covariant AnimatedPackageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcile(widget.packages);
  }

  void _reconcile(List<Package> next) {
    _assertUnique(next);
    final nextIds = next.map((p) => p.id).toList();
    final nextSet = nextIds.toSet();
    final oldOrder = List<String>.of(_renderIds);
    for (var i = 0; i < oldOrder.length; i++) {
      final entry = _entries[oldOrder[i]]!;
      if (!entry.present || nextSet.contains(oldOrder[i])) continue;
      entry.present = false;
      entry.exitSuccessorId = null;
      for (var j = i + 1; j < oldOrder.length; j++) {
        if (nextSet.contains(oldOrder[j])) {
          entry.exitSuccessorId = oldOrder[j];
          break;
        }
      }
      if (!_reduced) _animate(oldOrder[i], entry, 0);
    }
    for (final package in next) {
      var entry = _entries[package.id];
      if (entry == null) {
        entry = _entry(package, _reduced ? 1 : 0);
        _entries[package.id] = entry;
        if (!_reduced) _animate(package.id, entry, 1);
      } else {
        entry.package = package;
        if (!entry.present) {
          entry.present = true;
          entry.exitSuccessorId = null;
          if (!_reduced) _animate(package.id, entry, 1);
        }
      }
    }
    _order(nextIds);
    if (_reduced) _settle();
  }

  void _order(List<String> activeIds) {
    // 退出项按旧相对顺序插在锚点前；活跃项严格保留最新上游顺序。
    final exits = <String?, List<String>>{};
    for (final id in _renderIds) {
      final entry = _entries[id];
      if (entry == null || entry.present) continue;
      final anchor = activeIds.contains(entry.exitSuccessorId)
          ? entry.exitSuccessorId
          : null;
      exits.putIfAbsent(anchor, () => []).add(id);
    }
    _renderIds = [
      for (final id in activeIds) ...[...?exits[id], id],
      ...?exits[null],
    ];
    _indices = {for (var i = 0; i < _renderIds.length; i++) _renderIds[i]: i};
  }

  void _animate(String id, _PresentationEntry entry, double target) {
    final generation = ++entry.generation;
    final remaining = (target - entry.controller.value).abs();
    final duration = Duration(
      microseconds: (Motion.emphasized.inMicroseconds * remaining).round(),
    );
    entry.controller
        .animateTo(target, duration: duration, curve: Curves.linear)
        .whenCompleteOrCancel(() {
      if (!mounted ||
          generation != entry.generation ||
          !identical(_entries[id], entry) ||
          entry.present) {
        return;
      }
      // 取消也会回调；仅真正收起至 0 的当前退出代可以回收。
      if (entry.controller.value != 0) return;
      setState(() {
        _entries.remove(id);
        entry.generation++;
        entry.controller.dispose();
        _order(widget.packages.map((p) => p.id).toList());
      });
    });
  }

  void _settle() {
    for (final id in _entries.keys.toList()) {
      final entry = _entries[id]!;
      entry.generation++;
      if (entry.present) {
        entry.controller.value = 1;
      } else {
        _entries.remove(id);
        entry.controller.dispose();
      }
    }
    _order(widget.packages.map((p) => p.id).toList());
  }

  @override
  void dispose() {
    for (final entry in _entries.values) {
      entry.generation++;
      entry.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: widget.padding,
        sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
          (context, index) {
            final id = _renderIds[index];
            final entry = _entries[id]!;
            final generation = entry.generation;
            return SizeTransition(
              key: ValueKey(id),
              sizeFactor: entry.controller,
              axisAlignment: -1,
              child: FadeTransition(
                opacity: entry.controller,
                child: IgnorePointer(
                  ignoring: !entry.present,
                  child: ExcludeSemantics(
                    excluding: !entry.present,
                    child: ExcludeFocus(
                      excluding: !entry.present,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: ModernPackageCard(
                          package: entry.package,
                          interactive: entry.present,
                          interactionAllowed: () =>
                              mounted &&
                              entry.present &&
                              entry.generation == generation &&
                              identical(_entries[id], entry),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          childCount: _renderIds.length,
          findChildIndexCallback: (key) =>
              key is ValueKey<String> ? _indices[key.value] : null,
        )),
      );
}
